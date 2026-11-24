import MetalKit
import QuartzCore
import simd

/// Owns the clock and the two looks. Scenes only describe what to draw.
final class Renderer: NSObject, MTKViewDelegate {
    /// Steps per second. The original demo was timed to the VGA card's 70 Hz refresh.
    static let tickRate = 70.0
    /// A VGA monitor was 4:3 whatever the pixel grid, so every canvas is shown at that shape.
    static let displayAspect = 4.0 / 3.0
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    let device: MTLDevice
    var look: Look = .modern

    private let queue: MTLCommandQueue
    private let blitPipeline: MTLRenderPipelineState
    private let nearestSampler: MTLSamplerState
    private var classicTexture: MTLTexture?

    private(set) var entry: SceneEntry
    private var scene: DemoScene

    private var lastTime: CFTimeInterval?
    private var clock = StepClock()

    init(device: MTLDevice, entry: SceneEntry) throws {
        self.device = device
        self.entry = entry
        self.scene = try entry.make(device, Self.pixelFormat)

        guard let queue = device.makeCommandQueue() else { throw RendererError.noCommandQueue }
        self.queue = queue

        let library = try Shaders.library(device: device, source: Shaders.blitSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("blit_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
        self.blitPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        // "Nearest" keeps the classic look's pixels as hard-edged blocks when scaled up.
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .nearest
        sampler.magFilter = .nearest
        guard let samplerState = device.makeSamplerState(descriptor: sampler) else { throw RendererError.noSampler }
        self.nearestSampler = samplerState

        super.init()
    }

    func show(_ newEntry: SceneEntry) throws {
        guard newEntry.id != entry.id else { return }
        scene = try newEntry.make(device, Self.pixelFormat)
        entry = newEntry
        classicTexture = nil
        clock = StepClock()
        lastTime = nil
    }

    /// Plays the current scene again from its beginning.
    func restart() {
        scene.reset()
        clock = StepClock()
        lastTime = nil
    }

    // MARK: - Clock

    /// Runs as many 1/70 s steps as real time calls for, and returns how far we are into the next one.
    private func advanceClock() -> Float {
        let now = CACurrentMediaTime()
        defer { lastTime = now }
        guard let last = lastTime else { return 0 }

        let due = clock.advance(by: now - last)
        for _ in 0..<due.steps { scene.tick() }
        return due.alpha
    }

    // MARK: - Drawing

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let alpha = advanceClock()
        guard let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer() else { return }

        let screen = drawable.texture
        let box = Self.letterbox(width: Double(screen.width), height: Double(screen.height))
        let canvasSize = scene.currentCanvasSize ?? entry.canvasSize

        switch look {
        case .modern:
            // Draw the scene straight onto the screen at full resolution.
            let frame = FrameInfo(look: .modern, alpha: alpha, canvasSize: canvasSize,
                                  targetSize: SIMD2(Float(box.width), Float(box.height)))
            scene.prepare(commands: commands, frame: frame)
            if let encoder = commands.makeRenderCommandEncoder(descriptor: Self.clearPass(into: screen)) {
                encoder.setViewport(box)
                scene.draw(into: encoder, frame: frame)
                encoder.endEncoding()
            }

        case .classic:
            // Draw the scene onto a small picture the size of the original screen, then scale that up.
            guard let small = classicTarget(canvasSize) else { break }
            Self.drawClassic(scene: scene, canvasSize: canvasSize, into: small, commands: commands)
            if let encoder = commands.makeRenderCommandEncoder(descriptor: Self.clearPass(into: screen)) {
                encoder.setViewport(box)
                encoder.setRenderPipelineState(blitPipeline)
                encoder.setFragmentTexture(small, index: 0)
                encoder.setFragmentSamplerState(nearestSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
            }
        }

        commands.present(drawable)
        commands.commit()
    }

    /// Draws one classic-look frame into `texture`. Also used by the self-test.
    static func drawClassic(scene: DemoScene, canvasSize: SIMD2<Float>, into texture: MTLTexture, commands: MTLCommandBuffer) {
        let frame = FrameInfo(look: .classic, alpha: 0, canvasSize: canvasSize, targetSize: canvasSize)
        scene.prepare(commands: commands, frame: frame)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: clearPass(into: texture)) else { return }
        scene.draw(into: encoder, frame: frame)
        encoder.endEncoding()
    }

    static func makeClassicTexture(device: MTLDevice, canvasSize: SIMD2<Float>) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: Int(canvasSize.x), height: Int(canvasSize.y), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    private func classicTarget(_ canvasSize: SIMD2<Float>) -> MTLTexture? {
        if let texture = classicTexture, texture.width != Int(canvasSize.x) || texture.height != Int(canvasSize.y) {
            classicTexture = nil   // the canvas changed size (Play Demo moved on to another part)
        }
        if classicTexture == nil {
            classicTexture = Self.makeClassicTexture(device: device, canvasSize: canvasSize)
        }
        return classicTexture
    }

    static func clearPass(into texture: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    /// The largest 4:3 rectangle that fits in the window, centred, with black bars around it.
    /// (Not private so that the self-test can check it.)
    static func letterbox(width: Double, height: Double) -> MTLViewport {
        var w = width
        var h = width / displayAspect
        if h > height {
            h = height
            w = height * displayAspect
        }
        return MTLViewport(originX: (width - w) / 2, originY: (height - h) / 2, width: w, height: h, znear: 0, zfar: 1)
    }
}

/// The arithmetic of the 70-steps-a-second clock, kept apart from the real time source so that the
/// self-test can feed it made-up times (a 60 Hz display, a 120 Hz one, a long pause).
struct StepClock {
    /// Length of one step in seconds.
    static let step = 1.0 / Renderer.tickRate
    /// After a pause (window hidden, Mac asleep) at most this much time is caught up on, so the
    /// scene does not race through minutes of steps.
    static let longestCatchUp = 0.25

    /// Time not yet turned into steps: always at least 0 and less than one step.
    private(set) var owed = 0.0

    /// Adds `elapsed` seconds of real time. Returns how many whole steps are now due, and how far
    /// we are into the next one: 0 up to, but never reaching, 1.
    mutating func advance(by elapsed: Double) -> (steps: Int, alpha: Float) {
        owed += min(max(elapsed, 0), Self.longestCatchUp)
        var steps = 0
        while owed >= Self.step {
            owed -= Self.step
            steps += 1
        }
        // The fraction is below 1 as a 64-bit number, but squeezing it into 32 bits can round it
        // up to exactly 1 (anything above 0.99999997 does). Hold it just under.
        return (steps, min(Float(owed / Self.step), Float(1).nextDown))
    }
}

enum RendererError: Error, CustomStringConvertible {
    case noCommandQueue
    case noSampler

    var description: String {
        switch self {
        case .noCommandQueue: return "Could not create a Metal command queue"
        case .noSampler: return "Could not create a Metal sampler"
        }
    }
}
