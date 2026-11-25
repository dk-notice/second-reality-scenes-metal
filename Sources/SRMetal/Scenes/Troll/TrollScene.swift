import Metal

/// The troll's entrance at the end of the techno part (`TECHNO/KOE.C`, after the bars), step for step.
///
/// The original drew the troll on the right half of a video page twice the screen's width, the left half
/// black, and showed the left half. At the music's cue it scrolled the view right, faster and faster
/// (each refresh `xpos += xposa / 4`, `xposa` + 1), until the troll filled the screen. Then a short
/// sideways shake (50 refreshes, `xpos = 320 + sin1024[ripple] / ripplep`, the divisor growing) with a
/// flash that faded over 16 refreshes (every colour level + 45, 42, ... 0). Then it held until the music
/// moved on.
struct TrollModel {
    enum Phase: Equatable { case wait, scroll, shake, hold }

    static let shakeSteps = 50
    static let flashSteps = 16
    /// On its own: black before the scroll, and the hold before starting again.
    static let standaloneWait = 35
    static let standaloneHold = 300

    private(set) var phase = Phase.wait
    private(set) var phaseStep = 0
    /// How far the view has moved right, in pixels: 0 = all black, 320 = the troll fills the screen.
    private(set) var xpos = 0
    private var xposa = 0
    private var ripple = 0
    private var ripplep = 8
    /// The flash showing: levels added to every colour.
    private(set) var flash = 0

    /// Inside Play Demo: whether the music has reached the cue (section 35, row 48). nil on its own.
    var musicCue: Bool?

    mutating func reset() { self = TrollModel() }

    /// One refresh: as one pass of the original's loops, so what is set here is what shows.
    mutating func tick() {
        phaseStep += 1
        switch phase {
        case .wait:
            if musicCue ?? (phaseStep >= Self.standaloneWait) { begin(.scroll); scrollStep() }
        case .scroll:
            if xpos == 320 { begin(.shake); shakeStep() } else { scrollStep() }
        case .shake:
            if phaseStep >= Self.shakeSteps { begin(.hold); xpos = 320; flash = 0 } else { shakeStep() }
        case .hold:
            if musicCue == nil && phaseStep >= Self.standaloneHold { reset() }
        }
    }

    private mutating func begin(_ next: Phase) {
        phase = next
        phaseStep = 0
    }

    private mutating func scrollStep() {
        xpos += xposa / 4
        if xpos > 320 { xpos = 320 } else { xposa += 1 }
    }

    private mutating func shakeStep() {
        ripplep = ripplep > 1023 ? 1024 : ripplep * 5 / 4
        xpos = 320 + SinTable.sin(ripple) / ripplep
        ripple += ripplep + 100
        // The original set flash colour c (45 - 3c) after waiting for the refresh, so it shows one
        // refresh after the shake position it was set with: refreshes 1...16 of the shake.
        flash = (1...Self.flashSteps).contains(phaseStep) ? 45 - 3 * (phaseStep - 1) : 0
    }

    /// Where a step after this one would be (for the Modern look's gliding).
    func next() -> TrollModel {
        var copy = self
        copy.tick()
        return copy
    }
}

/// Shows `TrollModel`: the troll picture (original artwork, `artwork/original/rgb/07-troll.png`) moved
/// sideways, with the flash. 1993 look: whole pixels and the original's colour rule. Modern look: the
/// picture 8x by Super-xBR, the scroll, shake and flash gliding smoothly between refreshes.
final class TrollScene: DemoScene {
    private(set) var model = TrollModel()
    private let picture: ScenePicture
    private let layer: PictureLayer

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        picture = try ScenePicture(named: "07-troll", device: device)
        layer = try PictureLayer(device: device, pixelFormat: pixelFormat)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func demoUpdate(_ context: DemoContext) {
        model.musicCue = context.music.order > 35 || (context.music.order == 35 && context.music.row > 48)
    }

    /// The view at `xpos` shows the troll moved left by xpos - 320 (it starts a whole screen to the right).
    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        var xpos = Float(model.xpos), flash = Float(model.flash)
        if frame.look == .modern {
            let after = model.next()
            xpos += (Float(after.xpos) - xpos) * frame.alpha
            flash += (Float(after.flash) - flash) * frame.alpha
        }
        layer.draw(picture, into: encoder, look: frame.look, fade: .brighten(flash), offsetX: xpos - 320)
    }

    func classicReferenceFrame() -> [UInt8] {
        guard let rgb = ScenePicture.pixels("07-troll") else { return [] }
        let fade = PictureFade.brighten(Float(model.flash))
        let shift = model.xpos - 320
        var out = [UInt8]()
        out.reserveCapacity(rgb.count)
        for y in 0..<400 {
            for x in 0..<320 {
                let sx = x + shift
                for k in 0..<3 {
                    let level = (sx >= 0 && sx < 320) ? Int((Double(rgb[(y * 320 + sx) * 3 + k]) * 63 / 255).rounded()) : 0
                    out.append(byteFromVGA(fade.classicLevel(level)))
                }
            }
        }
        return out
    }
}
