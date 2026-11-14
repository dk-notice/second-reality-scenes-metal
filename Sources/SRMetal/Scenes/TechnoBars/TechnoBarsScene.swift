import Metal
import simd

/// Draws the techno bars.
///
///  - Classic look: the processor replays the 1993 steps (draw one-colour bars, store them in one layer
///    of a page, show the page) and the graphics chip only turns the resulting colour numbers into
///    colours. This keeps every pixel as it was.
///  - Modern look: the graphics chip works out, for each screen pixel, whether it is inside the current
///    bars and inside each of the three ghosts, and shades it by how many. Edges are soft and everything
///    glides between steps.
final class TechnoBarsScene: DemoScene {
    private(set) var model = TechnoBarsModel()
    private let pipeline: MTLRenderPipelineState
    private let indexedCanvas: IndexedCanvas

    /// Must match `Snapshot` in the shader source below.
    private struct Snapshot {
        var centre: SIMD2<Float>
        var along: SIMD2<Float>      // unit direction along the bars (after undoing the pixel stretch)
        var halfThickness: Float
        var weight: Float
    }

    /// Must match `Uniforms` in the shader source below.
    private struct Uniforms {
        var canvasSize: SIMD2<Float>
        var slide: Float
        var padding: Float = 0
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.fragmentSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("bars_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        indexedCanvas = try IndexedCanvas(
            device: device, pixelFormat: pixelFormat,
            width: TechnoBarsModel.width, height: TechnoBarsModel.height)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }

    func classicReferenceFrame() -> [UInt8] {
        let palette = model.classicPalette()
        var frame = [UInt8]()
        frame.reserveCapacity(TechnoBarsModel.width * TechnoBarsModel.height * 3)
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

        let parameters = model.modernParameters(alpha: Double(frame.alpha))
        var snapshots = parameters.snapshots.map { snapshot -> Snapshot in
            let angle = snapshot.state.rotation * .pi / 512
            return Snapshot(
                centre: SIMD2<Float>(snapshot.state.centre),
                along: SIMD2(Float(sin(angle)), Float(cos(angle))),
                halfThickness: Float(snapshot.state.halfThickness),
                weight: snapshot.weight)
        }
        var levels = parameters.levels.map { SIMD4<Float>($0, 1) }
        var uniforms = Uniforms(canvasSize: frame.canvasSize, slide: parameters.slide)

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&snapshots, length: MemoryLayout<Snapshot>.stride * snapshots.count, index: 1)
        encoder.setFragmentBytes(&levels, length: MemoryLayout<SIMD4<Float>>.stride * levels.count, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    private static let fragmentSource = """
    struct Uniforms {
        float2 canvasSize;
        float slide;        // how far the picture has slid right, in canvas pixels
        float padding;
    };

    struct Snapshot {
        float2 centre;
        float2 along;
        float halfThickness;
        float weight;
    };

    fragment float4 bars_fragment(CanvasOut in [[stage_in]],
                                  constant Uniforms &u [[buffer(0)]],
                                  const device Snapshot *snapshots [[buffer(1)]],
                                  const device float4 *levels [[buffer(2)]]) {
        float2 pos = in.uv * u.canvasSize;
        pos.x -= u.slide;

        // How many of the four sets of bars cover this pixel (soft at the edges).
        float covered = 0.0;
        if (pos.x >= 0.0) {
            for (int i = 0; i < 4; i++) {
                Snapshot s = snapshots[i];
                if (s.weight == 0.0 || s.halfThickness < 0.01) { continue; }
                // Undo the 6/5 stretch of the pixels, then measure how far across the bars we are.
                float2 q = float2((pos.x - s.centre.x) / 1.2, pos.y - s.centre.y);
                float across = q.x * s.along.y - q.y * s.along.x;
                // Bars sit every 4 half-thicknesses; there are 11 of them (-5...5).
                float bar = clamp(round(across / (4.0 * s.halfThickness)), -5.0, 5.0);
                float inside = s.halfThickness - abs(across - bar * 4.0 * s.halfThickness);
                covered += saturate(inside / max(fwidth(across), 1e-5) + 0.5) * s.weight;
            }
        }

        // Shade by the count: 0 = black ... 4 = brightest.
        float lower = floor(covered);
        int i = int(lower);
        float3 colour = mix(levels[min(i, 4)].rgb, levels[min(i + 1, 4)].rgb, covered - lower);
        return float4(colour, 1.0);
    }
    """
}
