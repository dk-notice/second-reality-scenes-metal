import Foundation
import Metal
import simd

/// Draws the 3D City: the original's long flight through a city of flat-shaded buildings, trees
/// and cars, behind a small ship, ending on the "Future Crew" logo. Models and recorded flight are
/// the original's, played through the shared VISU engine in `Core/Visu/`.
///
///  - Classic look: the engine's 1993 replay draws each animation frame into a 320x200 screen of
///    colour numbers (`City3DModel`); the graphics chip only looks the colours up (`IndexedCanvas`).
///  - Modern look: the same objects as real triangles at full resolution (`VisuModernRenderer`),
///    gliding between animation frames (each lasts two steps).
///
/// THIS SCENE USES ORIGINAL 3D DATA: the models and the animation are Future Crew's files (see
/// docs/scenes/city-3d.md and Data/Visu/README.md). It uses no picture.
final class City3DScene: DemoScene {
    let model: City3DModel
    private let indexedCanvas: IndexedCanvas
    private let renderer: VisuModernRenderer
    /// Inside Play Demo: the lead-in's 400-line screens, and one pixel to fill the background with.
    private let tallCanvas: IndexedCanvas
    private let fill: IndexedCanvas

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        model = try City3DModel()
        indexedCanvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat,
                                          width: City3DModel.width, height: City3DModel.height)
        renderer = try VisuModernRenderer(device: device, pixelFormat: pixelFormat)
        tallCanvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat, width: 320, height: 400)
        fill = try IndexedCanvas(device: device, pixelFormat: pixelFormat, width: 1, height: 1)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func demoUpdate(_ context: DemoContext) {
        model.update(music: context.music, justShown: context.justShown, previous: context.previous)
    }
    func classicReferenceFrame() -> [UInt8] { model.classicReferenceFrame() }

    /// The modern look is drawn into the engine's own off-screen picture first, because it needs
    /// a depth buffer and smoothed edges that the app's main drawing pass does not have.
    func prepare(commands: MTLCommandBuffer, frame: FrameInfo) {
        guard frame.look == .modern else { return }
        if model.demo != nil {
            // Inside Play Demo: no fades of this version's; the whitening at the end glides.
            guard model.demoPicture == nil else { return }
            renderer.render(model.pose(alpha: frame.alpha), view: model.engine.view,
                            palette: VisuPlayback.colours(model.demoFlightPalette(alpha: frame.alpha)),
                            targetSize: frame.targetSize, commands: commands)
            return
        }
        // The fade glides between steps too.
        let brightness = City3DModel.brightness(atStep: Float(model.step) + frame.alpha)
        renderer.render(model.pose(alpha: frame.alpha), view: model.engine.view,
                        palette: VisuPlayback.colours(model.palette, brightness: brightness),
                        targetSize: frame.targetSize, commands: commands)
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if let picture = model.demoPicture {
            // Inside Play Demo, before the flight. The Modern look shows the jelly logo's own Modern
            // picture brightening while it lasts; the window that follows is plain rectangles.
            if frame.look == .modern, let lift = model.demoLift(alpha: frame.alpha),
               let previous = model.demo?.previous.drawModern {
                previous(encoder, frame, lift)
                return
            }
            (picture.height == 400 ? tallCanvas : indexedCanvas)
                .draw(into: encoder, indices: picture.numbers, palette: VisuPlayback.colours(picture.levels))
            return
        }
        if frame.look == .modern && model.demo != nil {
            // The background is colour 255: black, until the whitening shows colour 0 there.
            fill.draw(into: encoder, indices: [255], palette: VisuPlayback.colours(model.demoFlightPalette(alpha: frame.alpha)))
        }
        if frame.look == .classic {
            indexedCanvas.draw(into: encoder, indices: model.screen,
                               palette: VisuPlayback.colours(model.classicPalette))
        } else {
            // The main pass has already been cleared to black, the colour U2E.C cleared to.
            renderer.composite(into: encoder)
        }
    }
}
