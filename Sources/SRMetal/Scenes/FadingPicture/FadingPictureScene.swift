import Metal

/// The timing of a picture that appears out of a white screen and may fade out to black: the title
/// picture (`BEG/BEG.C`) and the end picture (`END/END.C`), which work the same way:
///
/// 1. A white screen for `whiteSteps` refreshes.
/// 2. Fade in from white over 129 refreshes: at refresh c (0...128) each colour level p is
///    ((128 − c) · 63 + p · c) / 128.
/// 3. (End picture only) Hold until the music's "music plus" goes above -16 (at most 5000 refreshes),
///    then fade to black over 64 refreshes: at c = 63 ... 0, p · c / 64.
///
/// Shown on its own (no music), the hold lasts `standaloneHoldSteps`; afterwards the scene holds black
/// for a moment and starts again.
struct FadingPictureModel {
    struct Timing {
        var whiteSteps: Int
        /// Whether the picture fades out to black after the hold (the end picture).
        var fadesOut: Bool
        /// How long the picture holds when there is no music to wait for.
        var standaloneHoldSteps: Int
        /// Black (or the finished picture, if it does not fade out) at the end, before starting again.
        var endSteps: Int
    }

    static let fadeInSteps = 129
    static let fadeOutSteps = 64
    /// The end picture's music cue: "music plus" above this (END.C line 110).
    static let musicCue = -16
    static let longestHold = 5000

    enum Phase: Equatable { case white, fadeIn, hold, fadeOut, end }

    let timing: Timing
    private(set) var phase = Phase.white
    /// Steps into the current phase.
    private(set) var phaseStep = 0
    /// Inside Play Demo: the music's "music plus", given before each step. nil on its own.
    var musicPlus: Int?

    init(timing: Timing) { self.timing = timing }

    mutating func reset() {
        phase = .white
        phaseStep = 0
    }

    mutating func tick() {
        phaseStep += 1
        switch phase {
        case .white:
            if phaseStep >= timing.whiteSteps { next(.fadeIn) }
        case .fadeIn:
            if phaseStep >= Self.fadeInSteps { next(timing.fadesOut ? .hold : .end) }
        case .hold:
            let cue = musicPlus.map { $0 > Self.musicCue } ?? (phaseStep >= timing.standaloneHoldSteps)
            if cue || phaseStep >= Self.longestHold { next(.fadeOut) }
        case .fadeOut:
            if phaseStep >= Self.fadeOutSteps { next(.end) }
        case .end:
            if phaseStep >= timing.endSteps { reset() }
        }
    }

    private mutating func next(_ phase: Phase) {
        self.phase = phase
        phaseStep = 0
    }

    /// The fade showing, `alpha` of a step on (the Modern look glides; the 1993 look passes 0).
    func fade(alpha: Float = 0) -> PictureFade {
        let at = Float(phaseStep) + alpha
        switch phase {
        case .white: return .fromWhite(keep: 0, outOf: 128)
        case .fadeIn: return .fromWhite(keep: min(at, 128), outOf: 128)
        case .hold: return .none
        case .fadeOut: return .toBlack(keep: max(63 - at, 0), outOf: 64)
        case .end: return timing.fadesOut ? .toBlack(keep: 0, outOf: 64) : .none
        }
    }
}

/// A scene that shows one original picture through `FadingPictureModel`: the title picture and the end
/// picture. 1993 look: the original pixels, faded exactly by the original's rule. Modern look: the
/// picture made 8x by Super-xBR, the fade gliding smoothly on top.
///
/// THESE SCENES USE ORIGINAL ARTWORK (the pictures in `artwork/original/rgb`).
final class FadingPictureScene: DemoScene {
    private(set) var model: FadingPictureModel
    let pictureName: String
    private let picture: ScenePicture
    private let layer: PictureLayer

    init(picture name: String, timing: FadingPictureModel.Timing, device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        model = FadingPictureModel(timing: timing)
        pictureName = name
        picture = try ScenePicture(named: name, device: device)
        layer = try PictureLayer(device: device, pixelFormat: pixelFormat)
    }

    /// The title picture (BEG.C): 32 refreshes of white, then the fade in; the demo moves on right after.
    static let titleTiming = FadingPictureModel.Timing(whiteSteps: 32, fadesOut: false, standaloneHoldSteps: 0, endSteps: 140)
    /// The end picture (END.C): 34 refreshes of white, the fade in, the hold, the fade to black.
    /// Standalone the hold is 375 steps, about what it lasts in the demo.
    static let endTiming = FadingPictureModel.Timing(whiteSteps: 34, fadesOut: true, standaloneHoldSteps: 375, endSteps: 35)

    func reset() { model.reset() }
    func tick() { model.tick() }
    func demoUpdate(_ context: DemoContext) { model.musicPlus = context.music.plus }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        let fade = frame.look == .modern ? model.fade(alpha: frame.alpha) : model.fade()
        layer.draw(picture, into: encoder, look: frame.look, fade: fade)
    }

    func classicReferenceFrame() -> [UInt8] {
        let fade = model.fade()
        guard let rgb = ScenePicture.pixels(pictureName) else { return [] }
        return rgb.map { byteFromVGA(fade.classicLevel(vgaFromByte($0))) }
    }
}
