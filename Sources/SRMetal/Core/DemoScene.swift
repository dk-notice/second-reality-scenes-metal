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
}

/// One row in the list of scenes.
struct SceneEntry: Identifiable {
    let id: String
    let title: String
    /// Who wrote the original.
    let credit: String
    /// The scene's coordinate system. It is always shown at 4:3, as on a VGA monitor.
    let canvasSize: SIMD2<Float>
    let make: (MTLDevice, MTLPixelFormat) throws -> DemoScene
}

enum SceneCatalog {
    static let all: [SceneEntry] = [
        SceneEntry(
            id: "dot-tunnel",
            title: "Dot Tunnel",
            credit: "Trug",
            canvasSize: SIMD2(320, 200),
            make: { device, format in try DotTunnelScene(device: device, pixelFormat: format) }
        )
    ]
}
