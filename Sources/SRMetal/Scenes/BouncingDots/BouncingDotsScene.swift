import Metal
import simd

/// Draws the bouncing dots.
///
///  - Classic look: the processor replays the 1993 drawing steps into a 256-colour picture and the
///    graphics chip turns the colour numbers into colours.
///  - Modern look: the graphics chip paints a smooth floor, then draws every shadow and dot as a soft
///    round shape at full resolution, bigger when nearer, gliding between steps.
final class BouncingDotsScene: DemoScene {
    private(set) var model = BouncingDotsModel()
    private let indexedCanvas: IndexedCanvas
    private let floorPipeline: MTLRenderPipelineState
    private let spritePipeline: MTLRenderPipelineState
    /// A few buffers used in turn, so a new frame's shapes never overwrite ones still being drawn.
    private var spriteBuffers: [MTLBuffer] = []
    private var nextBuffer = 0

    /// One round shape. Must match `Sprite` in the shader source below.
    private struct Sprite {
        var centre: SIMD2<Float>
        var halfSize: SIMD2<Float>
        var inner: SIMD4<Float>     // colour at the middle
        var outer: SIMD4<Float>     // colour at the rim
    }

    /// Must match `Uniforms` in the shader source below.
    private struct Uniforms {
        var canvasSize: SIMD2<Float>
        var targetSize: SIMD2<Float>
        var fade: Float             // amount taken off every colour, 0...1
        var padding: SIMD3<Float> = SIMD3(0, 0, 0)
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        indexedCanvas = try IndexedCanvas(
            device: device, pixelFormat: pixelFormat,
            width: BouncingDotsModel.width, height: BouncingDotsModel.height)

        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.shaderSource)

        let floor = MTLRenderPipelineDescriptor()
        floor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        floor.fragmentFunction = try Shaders.function("dots_floor_fragment", in: library)
        floor.colorAttachments[0].pixelFormat = pixelFormat
        floorPipeline = try device.makeRenderPipelineState(descriptor: floor)

        let sprite = MTLRenderPipelineDescriptor()
        sprite.vertexFunction = try Shaders.function("dots_sprite_vertex", in: library)
        sprite.fragmentFunction = try Shaders.function("dots_sprite_fragment", in: library)
        let colour = sprite.colorAttachments[0]!
        colour.pixelFormat = pixelFormat
        colour.isBlendingEnabled = true
        colour.sourceRGBBlendFactor = .one
        colour.sourceAlphaBlendFactor = .one
        colour.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colour.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        spritePipeline = try device.makeRenderPipelineState(descriptor: sprite)

        let length = MemoryLayout<Sprite>.stride * BouncingDotsModel.dotCount * 2
        for _ in 0..<3 {
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
                throw SceneError.textureFailed
            }
            spriteBuffers.append(buffer)
        }
    }

    func reset() { model.reset() }
    func tick() { model.tick() }

    func classicReferenceFrame() -> [UInt8] {
        let palette = model.classicPalette()
        var frame = [UInt8]()
        frame.reserveCapacity(BouncingDotsModel.width * BouncingDotsModel.height * 3)
        for index in model.classicIndices() {
            let colour = palette[Int(index)]
            frame.append(byteFromVGA(colour.x))
            frame.append(byteFromVGA(colour.y))
            frame.append(byteFromVGA(colour.z))
        }
        return frame
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            indexedCanvas.draw(
                into: encoder,
                indices: model.classicIndices(),
                palette: model.classicPalette().map { SIMD4<Float>(SIMD3<Float>($0) / 63, 1) })
            return
        }

        let alpha = Double(frame.alpha)
        var uniforms = Uniforms(
            canvasSize: frame.canvasSize,
            targetSize: frame.targetSize,
            fade: Float(model.smoothFade(alpha: alpha) / 63))

        // Floor first.
        encoder.setRenderPipelineState(floorPipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        // No dots until the floor has faded in.
        guard model.ticks > BouncingDotsModel.fadeInTicks else { return }

        // Where every dot is right now, gliding from its last step to this one.
        struct Placed {
            var position: SIMD2<Double>
            var shadowY: Double
            var depth: Double
        }
        var placed: [Placed] = []
        placed.reserveCapacity(BouncingDotsModel.dotCount)
        for i in 0..<BouncingDotsModel.dotCount {
            let now = model.current[i]
            let before = now.jumped ? now : model.previous[i]
            let depth = before.depth + (now.depth - before.depth) * alpha
            guard depth > 100 else { continue }
            placed.append(Placed(
                position: before.position + (now.position - before.position) * alpha,
                shadowY: before.shadowY + (now.shadowY - before.shadowY) * alpha,
                depth: depth))
        }
        // Furthest first, so nearer dots are drawn over further ones.
        placed.sort { $0.depth > $1.depth }

        var sprites: [Sprite] = []
        sprites.reserveCapacity(placed.count * 2)
        let shadow = SIMD4<Float>(SIMD3<Float>(repeating: Float(BouncingDotsModel.shadowGrey) / 63), 1)
        func radius(_ dot: Placed) -> Double {
            // The original's dots were about 1.6 pixels in radius at any distance. Here nearer is bigger.
            min(max(1.6 * 9000 / dot.depth, 0.6), 6)
        }
        // The canvas's pixels are taller than wide, so shapes are 1.2 times as many pixels across to look round.
        for dot in placed {
            let r = radius(dot)
            sprites.append(Sprite(
                centre: SIMD2(Float(dot.position.x + 2), Float(dot.shadowY + 0.5)),
                halfSize: SIMD2(Float(r * 1.2 * 1.3), Float(r * 0.45)),
                inner: shadow, outer: shadow))
        }
        for dot in placed {
            let r = radius(dot)
            let shadeDepth = min(max((dot.depth / 256 - 31) * 0.75 + 8, 0), 15)
            let colours = BouncingDotsModel.dotColours(shade: 15 - shadeDepth)
            sprites.append(Sprite(
                centre: SIMD2(Float(dot.position.x + 2), Float(dot.position.y + 1.5)),
                halfSize: SIMD2(Float(r * 1.2), Float(r)),
                inner: SIMD4(SIMD3<Float>(colours.middle / 63), 1),
                outer: SIMD4(SIMD3<Float>(colours.edge / 63), 1)))
        }
        guard !sprites.isEmpty else { return }

        let buffer = spriteBuffers[nextBuffer]
        nextBuffer = (nextBuffer + 1) % spriteBuffers.count
        sprites.withUnsafeBytes { bytes in
            buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }

        encoder.setRenderPipelineState(spritePipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: sprites.count)
    }

    private static let shaderSource = """
    struct Uniforms {
        float2 canvasSize;
        float2 targetSize;
        float fade;
        float3 padding;
    };

    // The floor: black above the horizon, getting lighter towards the viewer below it.
    fragment float4 dots_floor_fragment(CanvasOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float row = in.uv.y * u.canvasSize.y - 100.5;
        float grey = 0.0;
        if (row > -0.5) {
            float c = 64.0 - 256.0 / (max(row, 0.0) + 4.0);
            grey = c * c / 64.0 / 4.0 / 63.0;
        }
        grey = max(grey - u.fade, 0.0);
        return float4(grey, grey, grey, 1.0);
    }

    struct Sprite {
        float2 centre;
        float2 halfSize;
        float4 inner;
        float4 outer;
    };

    struct SpriteOut {
        float4 position [[position]];
        float2 uv;
        float4 inner;
        float4 outer;
        float edge;
    };

    vertex SpriteOut dots_sprite_vertex(uint vid [[vertex_id]],
                                        uint iid [[instance_id]],
                                        const device Sprite *sprites [[buffer(0)]],
                                        constant Uniforms &u [[buffer(1)]]) {
        Sprite s = sprites[iid];
        float2 corner = float2(vid & 1, vid >> 1) * 2.0 - 1.0;
        float2 pos = s.centre + corner * s.halfSize;
        float2 ndc = pos / u.canvasSize * 2.0 - 1.0;

        SpriteOut out;
        out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
        out.uv = corner;
        out.inner = s.inner;
        out.outer = s.outer;
        // Soft rim about one real pixel wide.
        float heightInPixels = 2.0 * s.halfSize.y * u.targetSize.y / u.canvasSize.y;
        out.edge = 2.0 / max(heightInPixels, 1.0);
        return out;
    }

    fragment float4 dots_sprite_fragment(SpriteOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float d = length(in.uv);
        float alpha = saturate((1.0 - d) / in.edge);
        float3 colour = mix(in.inner.rgb, in.outer.rgb, smoothstep(0.25, 1.0, d));
        colour = max(colour - u.fade, 0.0);
        return float4(colour * alpha, alpha);
    }
    """
}
