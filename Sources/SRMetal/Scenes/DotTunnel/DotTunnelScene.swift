import Metal
import simd

/// Draws the dot tunnel on the graphics chip.
///
/// The processor only works out about 80 rings per frame (centre, size, brightness).
/// The shader then places all 64 dots of every ring itself. In 1993 this was the other way round:
/// every dot position came from a table made in advance, and an assembly loop copied them to the screen.
final class DotTunnelScene: DemoScene {
    private(set) var model = DotTunnelModel()
    private let pipeline: MTLRenderPipelineState

    /// What the shader is told about one ring. The layout must match `Ring` in the shader source below.
    private struct RingData {
        var center: SIMD2<Float>
        var radius: SIMD2<Float>
        var brightness: Float
        var dotSize: Float
    }

    /// Must match `Uniforms` in the shader source below.
    private struct Uniforms {
        var canvasSize: SIMD2<Float>
        var targetSize: SIMD2<Float>
        var classic: UInt32
        var dotsPerRing: UInt32
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        let library = try Shaders.library(device: device, source: Self.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("tunnel_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("tunnel_fragment", in: library)
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = pixelFormat
        // Blending lets the modern look's soft dot edges mix with what is behind them.
        // Rings are drawn far to near, so nearer dots cover further ones, as in the original.
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }

    func classicReferenceFrame() -> [UInt8] {
        // The tunnel is grey, so red, green and blue are all the same value.
        model.classicReferenceFrame().flatMap { value -> [UInt8] in
            let byte = byteFromVGA(Int(value))
            return [byte, byte, byte]
        }
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        var rings = frame.look == .classic ? classicRings() : modernRings(alpha: frame.alpha)
        guard !rings.isEmpty else { return }

        var uniforms = Uniforms(
            canvasSize: frame.canvasSize,
            targetSize: frame.targetSize,
            classic: frame.look == .classic ? 1 : 0,
            dotsPerRing: UInt32(DotTunnelModel.dotsPerRing))

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&rings, length: MemoryLayout<RingData>.stride * rings.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        // Each dot is a tiny square (4 corners). "Instances" means: draw that square once per dot.
        encoder.drawPrimitives(
            type: .triangleStrip, vertexStart: 0, vertexCount: 4,
            instanceCount: rings.count * DotTunnelModel.dotsPerRing)
    }

    /// The 1993 rules exactly: whole-number positions and sizes, slots 80 down to 4.
    private func classicRings() -> [RingData] {
        let reference = model.rings[DotTunnelModel.referenceSlot]
        var result: [RingData] = []
        for slot in stride(from: 80, through: 4, by: -1) {
            let ring = model.rings[slot]
            guard ring.band != .invisible else { continue }
            let radiusY = DotTunnelModel.classicRadiusY(slot: slot)
            let radiusX = DotTunnelModel.classicRadiusX(radiusY: radiusY)
            result.append(RingData(
                center: SIMD2(Float(160 + ring.x - reference.x), Float(100 + ring.y - reference.y)),
                radius: SIMD2(Float(radiusX), Float(radiusY)),
                brightness: Float(DotTunnelModel.classicBrightness(slot: slot, band: ring.band)) / 63,
                dotSize: 1))
        }
        return result
    }

    /// The same tunnel without the whole-number steps. `alpha` is how far we are towards the next step,
    /// so each ring glides between slots instead of jumping, and sizes and brightness change smoothly.
    private func modernRings(alpha: Float) -> [RingData] {
        let rings = model.rings
        let ref = DotTunnelModel.referenceSlot
        let referenceX = simd_mix(Float(rings[ref].x), Float(rings[ref + 1].x), alpha)
        let referenceY = simd_mix(Float(rings[ref].y), Float(rings[ref + 1].y), alpha)

        var result: [RingData] = []
        for slot in stride(from: 81, through: 1, by: -1) {
            let ring = rings[slot]
            guard ring.band != .invisible else { continue }
            let position = Float(slot) - alpha
            let radiusY = 16384 / (position * 7 + 95) + 10
            var brightness = (64 - position / 1.3) / 63
            if ring.band == .dim { brightness *= 0.75 }
            result.append(RingData(
                center: SIMD2(160 + Float(ring.x) - referenceX, 100 + Float(ring.y) - referenceY),
                radius: SIMD2(radiusY * 1.7, radiusY),
                brightness: min(max(brightness, 0), 1),
                // Nearer dots are drawn larger. The original's were all one pixel.
                dotSize: 0.7 + radiusY / 70))
        }
        return result
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Ring {
        float2 center;      // in canvas units (320x200)
        float2 radius;      // horizontal, vertical
        float brightness;   // 0...1
        float dotSize;      // dot diameter in canvas rows
    };

    struct Uniforms {
        float2 canvasSize;
        float2 targetSize;
        uint classic;
        uint dotsPerRing;
    };

    struct DotOut {
        float4 position [[position]];
        float2 uv;          // -1...1 across the dot's square
        float brightness;
        float edge;         // soft-edge width; 0 means a hard square pixel
    };

    // Runs once per corner of every dot, and works out where that corner goes on screen.
    vertex DotOut tunnel_vertex(uint vid [[vertex_id]],
                                uint iid [[instance_id]],
                                const device Ring *rings [[buffer(0)]],
                                constant Uniforms &u [[buffer(1)]]) {
        Ring ring = rings[iid / u.dotsPerRing];
        float angle = float(iid % u.dotsPerRing) * (2.0 * M_PI_F / float(u.dotsPerRing));
        float2 onCircle = float2(sin(angle) * ring.radius.x, cos(angle) * ring.radius.y);
        float2 corner = float2(vid & 1, vid >> 1);

        float2 pixelsPerUnit = u.targetSize / u.canvasSize;
        float diameter = ring.dotSize * pixelsPerUnit.y;   // in real pixels

        float2 pos;
        if (u.classic != 0) {
            // Snap to whole pixels, rounding the way the original's table was rounded.
            pos = ring.center + rint(onCircle) + corner;
        } else {
            // Canvas pixels are not square, so size the dot in real pixels to keep it round.
            pos = ring.center + onCircle + 0.5 + (corner - 0.5) * diameter / pixelsPerUnit;
        }

        DotOut out;
        float2 ndc = pos / u.canvasSize * 2.0 - 1.0;
        out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
        out.uv = corner * 2.0 - 1.0;
        out.brightness = ring.brightness;
        out.edge = (u.classic != 0) ? 0.0 : 2.0 / max(diameter, 1.0);
        return out;
    }

    // Runs once per pixel of every dot, and decides its colour.
    fragment float4 tunnel_fragment(DotOut in [[stage_in]]) {
        float alpha = 1.0;
        if (in.edge > 0.0) {
            // Round dot with a one-pixel soft edge.
            alpha = saturate((1.0 - length(in.uv)) / in.edge);
        }
        float c = in.brightness * alpha;
        return float4(c, c, c, alpha);
    }
    """
}
