import Metal
import simd

/// Draws the Plasma scene on the graphics chip. The shader runs once per pixel and decides its colour.
///
///  - Classic look: the shader does the original's table lookups with whole numbers, for both of the
///    alternating frames, and averages the two colours.
///  - Modern look: no tables. The shader evaluates the sine formulas the tables were made from, at every
///    screen pixel, for both plasmas, and mixes them. No 4-pixel columns, no chessboard.
final class PlasmaScene: DemoScene {
    private(set) var model = PlasmaModel()
    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let psiniBuffer: MTLBuffer
    private let lsini16Buffer: MTLBuffer
    private let lsini4Buffer: MTLBuffer

    /// Must match `Uniforms` in the shader source below.
    private struct Uniforms {
        var canvasSize: SIMD2<Float>
        var classic: UInt32
        var hidden: UInt32
        var k: SIMD4<Int32>
        var l: SIMD4<Int32>
        /// Classic look: top line of field 0, top line of field 1, shift of field 0, shift of field 1.
        var fields: SIMD4<Int32>
        var kSmooth: SIMD4<Float>
        var lSmooth: SIMD4<Float>
        /// Modern look: canvas line of the band's top edge.
        var top: SIMD4<Float>
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.fragmentSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("plasma_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        // Hand the three sine tables to the graphics chip once.
        guard let psini = device.makeBuffer(bytes: PlasmaModel.psini, length: PlasmaModel.psini.count),
              let lsini16 = device.makeBuffer(bytes: PlasmaModel.lsini16, length: PlasmaModel.lsini16.count * 2),
              let lsini4 = device.makeBuffer(bytes: PlasmaModel.lsini4, length: PlasmaModel.lsini4.count * 2) else {
            throw SceneError.textureFailed
        }
        psiniBuffer = psini
        lsini16Buffer = lsini16
        lsini4Buffer = lsini4
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func classicReferenceFrame() -> [UInt8] { model.classicReferenceFrame() }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        var uniforms: Uniforms
        var palette: [SIMD4<Float>]

        if frame.look == .classic {
            let fields = model.fields
            let shown = model.shownPalette
            palette = (0..<256).map { (i: Int) -> SIMD4<Float> in
                let red = Float(shown[i * 3]) / 63
                let green = Float(shown[i * 3 + 1]) / 63
                let blue = Float(shown[i * 3 + 2]) / 63
                return SIMD4<Float>(red, green, blue, 1)
            }
            uniforms = Uniforms(
                canvasSize: frame.canvasSize, classic: 1, hidden: 0,
                k: model.k, l: model.l,
                fields: SIMD4(Int32(fields[0].top), Int32(fields[1].top), Int32(fields[0].pan), Int32(fields[1].pan)),
                kSmooth: .zero, lSmooth: .zero, top: .zero)
        } else {
            let parameters = model.modernParameters(alpha: frame.alpha)
            palette = parameters.palette
            uniforms = Uniforms(
                canvasSize: frame.canvasSize, classic: 0, hidden: parameters.hidden ? 1 : 0,
                k: .zero, l: .zero, fields: .zero,
                kSmooth: parameters.k, lSmooth: parameters.l,
                top: SIMD4(parameters.top, 0, 0, 0))
        }

        // The palette is too big to pass inline, so it goes in a small buffer of its own each frame.
        guard let paletteBuffer = device.makeBuffer(
            bytes: palette, length: MemoryLayout<SIMD4<Float>>.stride * palette.count) else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBuffer(paletteBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(psiniBuffer, offset: 0, index: 2)
        encoder.setFragmentBuffer(lsini16Buffer, offset: 0, index: 3)
        encoder.setFragmentBuffer(lsini4Buffer, offset: 0, index: 4)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    private static let fragmentSource = """
    struct Uniforms {
        float2 canvasSize;
        uint classic;
        uint hidden;
        int4 k;           // the four parameters of plasma K
        int4 l;           // ... and of plasma L
        int4 fields;      // classic: top line of field 0 and 1, sideways shift of field 0 and 1
        float4 kSmooth;   // modern: the same parameters, gliding between steps
        float4 lSmooth;
        float4 top;       // modern: x = canvas line of the band's top edge
    };

    // --- 1993 look: the original's table lookups, in whole numbers ---

    static uint plasmaTable(int c, int y, int4 p,
                            const device uchar *psini, const device ushort *lsini16, const device ushort *lsini4) {
        int bend1 = int(lsini16[y + p.y + 4 * (80 - c)]);
        int first = int(psini[c * 8 + bend1 + p.x]);
        int bend2 = int(lsini4[y + p.w + 16 * c]);
        int second = int(psini[2 * y + bend2 + p.z + 4 * (80 - c)]);
        return uint(first + second) & 255;
    }

    // --- Modern look: the formulas the tables were made from ---

    static float psiniWave(float a) {
        float t = fmod(a, 4096.0) * (M_PI_F / 2048.0);
        return sin(t) * 55.0 + sin(t * 6.0) * 5.0 + sin(t * 21.0) * 4.0 + 64.0;
    }
    static float lsini16Wave(float a) {
        float t = fmod(a, 4096.0) * (M_PI_F / 2048.0);
        return (sin(t) * 55.0 + sin(t * 4.0) * 5.0 + sin(t * 17.0) * 3.0 + 64.0) * 16.0;
    }
    static float lsini4Wave(float a) {
        float t = fmod(a, 4096.0) * (M_PI_F / 2048.0);
        return (sin(t) * 55.0 + sin(t * 5.0) * 8.0 + sin(t * 15.0) * 2.0 + 64.0) * 8.0;
    }
    static float plasmaSmooth(float c, float y, float4 p) {
        float first = psiniWave(c * 8.0 + lsini16Wave(y + p.y + 4.0 * (80.0 - c)) + p.x);
        float second = psiniWave(2.0 * y + lsini4Wave(y + p.w + 16.0 * c) + p.z + 4.0 * (80.0 - c));
        return first + second;
    }
    // A colour from the 256-entry palette at a fractional position.
    static float3 paletteSmooth(const device float4 *palette, float v) {
        v = clamp(v, 0.0, 255.0);
        int i = min(int(floor(v)), 254);
        return mix(palette[i].rgb, palette[i + 1].rgb, v - float(i));
    }

    fragment float4 plasma_fragment(CanvasOut in [[stage_in]],
                                    constant Uniforms &u [[buffer(0)]],
                                    const device float4 *palette [[buffer(1)]],
                                    const device uchar *psini [[buffer(2)]],
                                    const device ushort *lsini16 [[buffer(3)]],
                                    const device ushort *lsini4 [[buffer(4)]]) {
        float2 pos = in.uv * u.canvasSize;   // canvas position; whole pixels are centred on .5

        if (u.classic != 0) {
            int2 pixel = clamp(int2(floor(pos)), int2(0, 0), int2(319, 399));
            float3 sum = float3(0.0);
            for (int f = 0; f < 2; f++) {
                int row = pixel.y - (f == 0 ? u.fields.x : u.fields.y);
                int memoryX = pixel.x + (f == 0 ? u.fields.z : u.fields.w);
                uint number = 0;
                if (row >= 0 && row < 280) {
                    // Chessboard: which of the two plasmas owns this pixel.
                    int4 p = ((memoryX + row) & 1) == 1 ? u.k : u.l;
                    number = plasmaTable(memoryX >> 2, row, p, psini, lsini16, lsini4);
                }
                sum += palette[number].rgb;
            }
            return float4(sum * 0.5, 1.0);
        }

        float row = pos.y - u.top.x;
        if (u.hidden != 0 || row < 0.0 || row >= 280.0) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }
        // Column c's four pixels are centred on c + 0.5; row y's line on y + 0.5.
        float c = (pos.x + 1.0) / 4.0 - 0.5;
        float y = row - 0.5;
        float3 colourK = paletteSmooth(palette, plasmaSmooth(c, y, u.kSmooth));
        float3 colourL = paletteSmooth(palette, plasmaSmooth(c, y, u.lSmooth));
        return float4((colourK + colourL) * 0.5, 1.0);
    }
    """
}
