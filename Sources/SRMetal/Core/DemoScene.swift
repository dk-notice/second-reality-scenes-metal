import Metal
import simd

/// The two ways every scene can be shown.
enum Look: String, CaseIterable {
    /// Full display resolution, smooth motion between steps.
    case modern
    /// The 1993 picture: a small canvas (usually 320x200) scaled up, moving in 1/70 s steps.
    case classic

    var title: String {
        switch self {
        case .modern: return "Modern"
        case .classic: return "1993"
        }
    }
}

/// Everything a scene needs to know to draw one frame.
struct FrameInfo {
    var look: Look
    /// How far we are between the last step and the next one, 0..<1. Always 0 in the classic look.
    var alpha: Float
    /// Size of the scene's own coordinate system, e.g. 320x200. Scenes position things in these units.
    var canvasSize: SIMD2<Float>
    /// Size in real pixels of the area being drawn into.
    var targetSize: SIMD2<Float>
}

/// The contract every scene follows. To add a scene: write a class that conforms to this,
/// then add one entry to `SceneCatalog.all`.
protocol DemoScene: AnyObject {
    /// Go back to the start of the scene.
    func reset()
    /// Advance the scene by one step. Called 70 times per second, like the VGA refresh the demo was timed to.
    func tick()
    /// Draw the current state. The viewport is already set; (0,0) is the canvas's top-left corner.
    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo)
    /// The classic-look picture for the current state, worked out on the processor by the 1993 rules:
    /// red, green, blue bytes (0...255) for each canvas pixel, row by row. The self-test compares
    /// what the graphics chip draws against this.
    func classicReferenceFrame() -> [UInt8]
}

/// VGA colours were 0...63 per channel. This is how such a value lands in a 0...255 byte.
func byteFromVGA(_ value: Int) -> UInt8 {
    UInt8((Double(value) * 255 / 63).rounded())
}

/// One row in the list of scenes.
struct SceneEntry: Identifiable {
    let id: String
    let title: String
    /// Who wrote the original.
    let credit: String
    /// The scene's coordinate system. It is always shown at 4:3, as on a VGA monitor.
    let canvasSize: SIMD2<Float>
    /// Moments (in steps from the start) at which the self-test checks the classic look.
    let checkpoints: [Int]
    let make: (MTLDevice, MTLPixelFormat) throws -> DemoScene
}

enum SceneCatalog {
    static let all: [SceneEntry] = [
        SceneEntry(
            id: "dot-tunnel",
            title: "Dot Tunnel",
            credit: "Trug",
            canvasSize: SIMD2(320, 200),
            checkpoints: [1, 60, 250, 500, 777, 1000],
            make: { device, format in try DotTunnelScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "rings",
            title: "Rings",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [0, 40, 100, 127, 300, 1000],
            make: { device, format in try InterferenceScene(part: .rings, device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "interference",
            title: "Interference",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [0, 44, 300, 500, 700, 900, 1023, 1024],
            make: { device, format in try InterferenceScene(part: .interference, device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "techno-bars",
            title: "Techno Bars",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [1, 100, 419, 430, 800, 1259, 1262, 1300, 1700, 1920],
            make: { device, format in try TechnoBarsScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "bouncing-dots",
            title: "Bouncing Dots",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [0, 60, 129, 200, 500, 700, 1100, 1900, 2300, 2500, 2579],
            make: { device, format in try BouncingDotsScene(device: device, pixelFormat: format) }
        )
    ]
}
