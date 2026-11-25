import Metal

/// The explosion (part 3 of the demo, `PAM`): a hand-drawn animation of 40 frames, made in Autodesk
/// Animator, played at 17.5 frames a second while the colours fade in from white and back out.
///
/// THIS SCENE USES ORIGINAL ARTWORK: the frames are Future Crew's, exported from `PAM/OUT.ANI` into
/// `artwork/original/rgb/explosion` (see artwork/README.md).
///
/// - 1993 look: each frame's original pixels, faded by the original's whole-number rule.
/// - Modern look: each frame made 8 times larger by Super-xBR just before it is due (the next frame is
///   prepared on a background thread while the current one shows), the fade gliding smoothly on top.
final class ExplosionScene: DemoScene {
    private(set) var model = ExplosionModel()
    private let frames: [ScenePicture]
    private let layer: PictureLayer
    /// The frame whose Modern-look version is being prepared ahead.
    private var preparedFrame = 0

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        frames = try (1...ExplosionModel.frameCount).map {
            try ScenePicture(named: ExplosionModel.pictureName($0), device: device)
        }
        layer = try PictureLayer(device: device, pixelFormat: pixelFormat)
    }

    func reset() {
        model.reset()
        preparedFrame = 0
    }

    func tick() { model.tick() }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        let number = ExplosionModel.frame(at: model.step)
        let picture = frames[number - 1]
        if frame.look == .modern {
            prepareAhead(after: number)
            layer.draw(picture, into: encoder, look: .modern,
                       fade: .white(Float(ExplosionModel.smoothFade(at: model.step, alpha: Double(frame.alpha)))))
        } else {
            layer.draw(picture, into: encoder, look: .classic, fade: .white(Float(ExplosionModel.fade(at: model.step))))
        }
    }

    /// Keeps the Modern-look versions of only the frame showing and the next one (each is 2560x1600),
    /// and starts making the next one in the background.
    private func prepareAhead(after number: Int) {
        let next = number % ExplosionModel.frameCount + 1
        guard preparedFrame != next else { return }
        for (index, picture) in frames.enumerated() where index + 1 != number && index + 1 != next {
            picture.dropUpscaled()
        }
        frames[next - 1].prepareUpscaledInBackground()
        preparedFrame = next
    }

    /// The 1993 picture worked out on the processor: the frame's pixels from its file, each colour level
    /// faded by the original's rule.
    func classicReferenceFrame() -> [UInt8] {
        let fade = PictureFade.white(Float(ExplosionModel.fade(at: model.step)))
        guard let rgb = ScenePicture.pixels(ExplosionModel.pictureName(ExplosionModel.frame(at: model.step))) else { return [] }
        return rgb.map { byteFromVGA(fade.classicLevel(Int((Double($0) * 63 / 255).rounded()))) }
    }
}
