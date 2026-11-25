import Metal
import simd

/// Shows `CreditsModel`.
///
/// - 1993 look: the original's screen, worked out on the processor (`CreditsModel.classicScreen`) and
///   shown through its palette: the released pictures and the original font, of which only every other
///   row reached the screen.
/// - Modern look: see `docs/scenes/credits.md` (until it is built, the same as the 1993 look).
final class CreditsScene: DemoScene {
    private(set) var model: CreditsModel
    private let canvas: IndexedCanvas
    /// Video memory of the screen showing, worked out once per screen.
    private var memoryScreen = -1
    private var screenPalette: [SIMD4<Float>] = []

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        model = try CreditsModel.load()
        canvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat,
                                   width: CreditsModel.width, height: CreditsModel.height)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }

    private func palette() -> [SIMD4<Float>] {
        if memoryScreen != model.screen {
            memoryScreen = model.screen
            let levels = model.palette(screen: model.screen)
            screenPalette = (0..<256).map { (c: Int) -> SIMD4<Float> in
                let rgb = SIMD3<Float>(Float(levels[c * 3]), Float(levels[c * 3 + 1]), Float(levels[c * 3 + 2])) / 63
                return SIMD4<Float>(rgb, 1)
            }
        }
        return screenPalette
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        canvas.draw(into: encoder, indices: model.classicScreen(), palette: palette())
    }

    func classicReferenceFrame() -> [UInt8] {
        let levels = model.palette(screen: model.screen)
        return model.classicScreen().flatMap { c in (0..<3).map { byteFromVGA(Int(levels[Int(c) * 3 + $0])) } }
    }
}
