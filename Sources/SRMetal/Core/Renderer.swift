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
    private var accumulator = 0.0

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
        accumulator = 0
        lastTime = nil
    }

    /// Plays the current scene again from its beginning.
    func restart() {
        scene.reset()
        accumulator = 0
        lastTime = nil
    }

    // MARK: - Clock

    /// Runs as many 1/70 s steps as real time calls for, and returns how far we are into the next one.
    private func advanceClock() -> Float {
        let now = CACurrentMediaTime()
        defer { lastTime = now }
        guard let last = lastTime else { return 0 }

        // If the app was paused (window hidden, Mac asleep), don't try to catch up on minutes of steps.
        accumulator += min(now - last, 0.25)
        let step = 1.0 / Self.tickRate
        while accumulator >= step {
            scene.tick()
            accumulator -= step
        }
        return Float(accumulator / step)
    }

    // MARK: - Drawing

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let alpha = advanceClock()
        guard let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer() else { return }

        let screen = drawable.texture
        let box = Self.letterbox(width: Double(screen.width), height: Double(screen.height))

        switch look {
        case .modern:
            // Draw the scene straight onto the screen at full resolution.
            if let encoder = commands.makeRenderCommandEncoder(descriptor: Self.clearPass(into: screen)) {
                encoder.setViewport(box)
                scene.draw(into: encoder, frame: FrameInfo(
                    look: .modern,
                    alpha: alpha,
                    canvasSize: entry.canvasSize,
                    targetSize: SIMD2(Float(box.width), Float(box.height))))
                encoder.endEncoding()
            }

        case .classic:
            // Draw the scene onto a small picture the size of the original screen, then scale that up.
            guard let small = classicTarget() else { break }
            Self.drawClassic(scene: scene, canvasSize: entry.canvasSize, into: small, commands: commands)
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
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: clearPass(into: texture)) else { return }
        scene.draw(into: encoder, frame: FrameInfo(look: .classic, alpha: 0, canvasSize: canvasSize, targetSize: canvasSize))
        encoder.endEncoding()
    }

    static func makeClassicTexture(device: MTLDevice, canvasSize: SIMD2<Float>) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: Int(canvasSize.x), height: Int(canvasSize.y), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    private func classicTarget() -> MTLTexture? {
        if classicTexture == nil {
            classicTexture = Self.makeClassicTexture(device: device, canvasSize: entry.canvasSize)
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
    private static func letterbox(width: Double, height: Double) -> MTLViewport {
        var w = width
        var h = width / displayAspect
        if h > height {
            h = height
            w = height * displayAspect
        }
        return MTLViewport(originX: (width - w) / 2, originY: (height - h) / 2, width: w, height: h, znear: 0, zfar: 1)
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
