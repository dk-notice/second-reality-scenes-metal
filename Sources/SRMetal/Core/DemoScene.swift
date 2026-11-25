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
    /// Called just before `draw`, while no drawing pass is open yet. A scene that needs to draw
    /// into a picture of its own first (for example 3D shapes with a depth buffer, which the app's
    /// main pass does not have) does that here, using `commands`. Most scenes need nothing: there
    /// is an empty default.
    func prepare(commands: MTLCommandBuffer, frame: FrameInfo)
    /// Draw the current state. The viewport is already set; (0,0) is the canvas's top-left corner.
    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo)
    /// The classic-look picture for the current state, worked out on the processor by the 1993 rules:
    /// red, green, blue bytes (0...255) for each canvas pixel, row by row. The self-test compares
    /// what the graphics chip draws against this.
    func classicReferenceFrame() -> [UInt8]
    /// The canvas size right now, for a scene whose size changes as it runs (Play Demo, which
    /// shows other scenes and pictures). nil, the default, means the entry's `canvasSize`.
    var currentCanvasSize: SIMD2<Float>? { get }
    /// Only while Play Demo runs: called just before each `tick` with where the music is and how long
    /// the part has been running, for a scene that reacts to the music as the original part did (for
    /// example the techno bars' flash on the beat). Shown on its own, a scene is never called this and
    /// keeps its own clock. The default does nothing.
    func demoUpdate(_ context: DemoContext)
}

extension DemoScene {
    func prepare(commands: MTLCommandBuffer, frame: FrameInfo) {}
    var currentCanvasSize: SIMD2<Float>? { nil }
    func demoUpdate(_ context: DemoContext) {}
}

/// What Play Demo tells a scene each step (see `DemoScene.demoUpdate`).
struct DemoContext {
    /// The music as the original parts saw it: section, row, "music plus", sync value.
    var music: DemoMusicState
    /// Steps since the current part of the demo started.
    var partSteps: Int
    /// Steps since this scene appeared (a part may show several things in turn).
    var sceneSteps: Int
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
    /// The moment (in steps from the start) that makes a good small picture for the scene list.
    let thumbnailStep: Int
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
            thumbnailStep: 500,
            make: { device, format in try DotTunnelScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "rings",
            title: "Rings",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [0, 40, 100, 127, 300, 1000],
            thumbnailStep: 300,
            make: { device, format in try InterferenceScene(part: .rings, device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "interference",
            title: "Interference",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [0, 44, 300, 500, 700, 900, 1023, 1024],
            thumbnailStep: 700,
            make: { device, format in try InterferenceScene(part: .interference, device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "techno-bars",
            title: "Techno Bars",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [1, 100, 419, 430, 800, 1259, 1262, 1300, 1700, 1920],
            thumbnailStep: 310,
            make: { device, format in try TechnoBarsScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "troll",
            title: "Troll",
            credit: "Psi; picture by Pixel",
            canvasSize: SIMD2(320, 400),
            checkpoints: [0, 34, 35, 40, 60, 70, 80, 88, 89, 90, 95, 104, 105, 120, 140, 300],
            thumbnailStep: 200,
            make: { device, format in try TrollScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "switch-off",
            title: "Screen Switches Off",
            credit: "Wildfire",
            canvasSize: SIMD2(320, 400),
            checkpoints: [0, 70, 71, 72, 73, 76, 80, 83, 84, 85, 100, 130, 131, 132, 135, 150, 180, 200, 260],
            thumbnailStep: 75,
            make: { device, format in try SwitchOffScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "bouncing-dots",
            title: "Bouncing Dots",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [0, 60, 129, 200, 500, 700, 1100, 1900, 2300, 2500, 2579],
            thumbnailStep: 1300,
            make: { device, format in try BouncingDotsScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "plasma",
            title: "Plasma",
            credit: "Wildfire",
            // The original ran in a 320x400 screen mode: twice the usual number of lines.
            canvasSize: SIMD2(320, 400),
            checkpoints: [0, 1, 2, 17, 33, 400, 724, 740, 787, 800, 1600, 2000, 2300, 2322],
            thumbnailStep: 1000,
            make: { device, format in try PlasmaScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "starfield",
            title: "Hidden Starfield",
            credit: "Psi",
            canvasSize: SIMD2(320, 400),
            checkpoints: [0, 1, 20, 300, 900, 1000, 1300, 1700, 1984, 2030, 2047],
            thumbnailStep: 1700,
            make: { device, format in try StarfieldScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "sine-landscape",
            title: "3D Sine Landscape",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [0, 31, 100, 200, 700, 1300, 1978, 2047],
            thumbnailStep: 700,
            make: { device, format in try SineLandscapeScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "plasma-cube",
            title: "Plasma Cube",
            credit: "Wildfire",
            // 134 picture rows, each shown on three of the monitor's 400 lines.
            canvasSize: SIMD2(320, 400),
            checkpoints: [0, 16, 60, 100, 416, 800, 1200, 1600, 1916, 2010, 2047],
            thumbnailStep: 416,
            make: { device, format in try PlasmaCubeScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "glenz-vectors",
            title: "Glenz Vectors",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [0, 1, 100, 330, 420, 800, 960, 1014, 1300, 1700, 2100, 2250, 2340, 2359],
            thumbnailStep: 1300,
            make: { device, format in try GlenzScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "ships-flyby",
            title: "Ships Fly-by",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [0, 70, 130, 200, 290, 330, 345, 350, 400, 480, 560, 591],
            thumbnailStep: 350,
            make: { device, format in try ShipsFlybyScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "explosion",
            title: "Explosion",
            credit: "Trug, Wildfire",
            canvasSize: SIMD2(320, 200),
            checkpoints: [0, 3, 4, 5, 8, 23, 60, 100, 119, 124, 140, 156, 163, 176, 179],
            thumbnailStep: 60,
            make: { device, format in try ExplosionScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "title-picture",
            title: "Title Picture",
            credit: "Future Crew",
            // 320x400, like the original.
            canvasSize: SIMD2(320, 400),
            checkpoints: [0, 31, 32, 33, 50, 96, 159, 160, 161, 250],
            thumbnailStep: 200,
            make: { device, format in
                try FadingPictureScene(picture: "04-title", timing: FadingPictureScene.titleTiming, device: device, pixelFormat: format)
            }
        ),
        SceneEntry(
            id: "city-3d",
            title: "3D City",
            credit: "Psi",
            canvasSize: SIMD2(320, 200),
            checkpoints: [0, 2, 40, 200, 660, 1210, 1600, 1920, 2360, 2920, 3200, 3560, 3603],
            thumbnailStep: 1600,
            make: { device, format in try City3DScene(device: device, pixelFormat: format) }
        ),
        SceneEntry(
            id: "end-picture",
            title: "End Picture",
            credit: "Future Crew",
            canvasSize: SIMD2(320, 400),
            checkpoints: [0, 33, 34, 60, 162, 163, 300, 538, 539, 560, 601, 602, 620],
            thumbnailStep: 300,
            make: { device, format in
                try FadingPictureScene(picture: "17-end-picture", timing: FadingPictureScene.endTiming, device: device, pixelFormat: format)
            }
        ),
        SceneEntry(
            id: "end-scroller",
            title: "End Scroller",
            credit: "Future Crew",
            // The original's 640x400 screen.
            canvasSize: SIMD2(640, 400),
            checkpoints: [0, 2, 3, 50, 51, 400, 799, 800, 801, 1500, 3000, 6001],
            thumbnailStep: 1300,
            make: { device, format in try EndScrollerScene(device: device, pixelFormat: format) }
        )
    ]
}
