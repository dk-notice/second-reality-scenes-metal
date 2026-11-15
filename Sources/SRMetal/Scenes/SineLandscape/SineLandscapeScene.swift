import Foundation
import Metal
import simd

/// Draws the 3D Sine Landscape.
///
///  - Classic look: the processor replays the original's column-by-column drawing into a picture of
///    colour numbers, and the graphics chip turns the numbers into colours.
///  - Modern look: the graphics chip sends out a ray for every screen pixel (not one per 2-pixel
///    column), finds exactly where it meets the ground, and works the colour out from the palette's formula. The camera glides
///    between steps.
final class SineLandscapeScene: DemoScene {
    private(set) var model = SineLandscapeModel()
    private let indexedCanvas: IndexedCanvas
    private let pipeline: MTLRenderPipelineState
    private let firstWaveBuffer: MTLBuffer
    private let secondWaveBuffer: MTLBuffer
    private let classicPalette: [SIMD4<Float>]

    /// Must match `LandUniforms` in the shader source below.
    private struct Uniforms {
        var canvasSize: SIMD2<Float>
        var position: SIMD2<Float>
        /// sine and cosine of the heading, then of the heading plus the skew of the second axis.
        var turn: SIMD4<Float>
        /// x = how many canvas lines the picture is pushed down.
        var rise: SIMD4<Float>
    }

    /// The two height tables for the modern look: the same formulas as the originals, but without
    /// rounding to whole numbers and without the random roughness, so the ground is smooth however
    /// closely it is looked at.
    static let smoothWaves: (first: [Float], second: [Float]) = {
        func wave(_ index: Double) -> Double {
            let x = index.truncatingRemainder(dividingBy: 1024)
            var swell = x / 700
            if swell > 1 { swell = 2 - swell }
            return Foundation.sin(x * Double.pi * 3 / 1024) * swell * swell * 400
        }
        var first = [Float](repeating: 0, count: 32768)
        var second = [Float](repeating: 0, count: 32768)
        for u in 0..<32768 {
            let k = Double(u) / 32
            // 1.5 stands in for the average of the original's random roughness.
            first[u] = Float((wave(k * 7) / 8 + wave(k * 3) / 7 + 1.5) * 5 / 9)
            second[u] = Float((wave(k * 5) / 5 + wave(k * 2) / 6) * 7 / 9)
        }
        return (first, second)
    }()

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        indexedCanvas = try IndexedCanvas(
            device: device, pixelFormat: pixelFormat,
            width: SineLandscapeModel.width, height: SineLandscapeModel.height)

        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.fragmentSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("landscape_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        classicPalette = SineLandscapeModel.palette.map { SIMD4<Float>(SIMD3<Float>($0) / 63, 1) }
        let waves = Self.smoothWaves
        let floatSize = MemoryLayout<Float>.stride
        guard let first = device.makeBuffer(bytes: waves.first, length: waves.first.count * floatSize),
              let second = device.makeBuffer(bytes: waves.second, length: waves.second.count * floatSize) else {
            throw SceneError.textureFailed
        }
        firstWaveBuffer = first
        secondWaveBuffer = second
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func classicReferenceFrame() -> [UInt8] { model.classicReferenceFrame() }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            indexedCanvas.draw(into: encoder, indices: model.classicIndices(), palette: classicPalette)
            return
        }

        let camera = model.camera(alpha: Double(frame.alpha))
        let angle = camera.heading * 2 * Double.pi / 1024
        let skew = 177 * 2 * Double.pi / 1024
        // The landscape repeats every 65536 units each way; wrapping here keeps the numbers small
        // enough for the graphics chip's less precise arithmetic.
        func wrapped(_ value: Double) -> Float {
            Float(value - (value / 65536).rounded(.down) * 65536)
        }
        var uniforms = Uniforms(
            canvasSize: frame.canvasSize,
            position: SIMD2(wrapped(camera.position.x), wrapped(camera.position.y)),
            turn: SIMD4(Float(sin(angle)), Float(cos(angle)), Float(sin(angle + skew)), Float(cos(angle + skew))),
            rise: SIMD4(Float(camera.startRise), 0, 0, 0))

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBuffer(firstWaveBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(secondWaveBuffer, offset: 0, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    private static let fragmentSource = """
    struct LandUniforms {
        float2 canvasSize;
        float2 position;
        float4 turn;      // sin, cos of the heading; sin, cos of the heading plus the skew
        float4 rise;      // x = canvas lines the picture is pushed down
    };

    // A height table has 32768 entries and covers 65536 position units, then repeats.
    static float tableAt(const device float *table, float position) {
        float u = position * 0.5;
        float whole = floor(u);
        int i = int(whole) & 32767;
        return mix(table[i], table[(i + 1) & 32767], u - whole);
    }

    // Height of the ground at distance d along a ray, measured from the eye (the eye is at 0).
    static float groundAt(float d, float2 start, float2 direction,
                          const device float *first, const device float *second) {
        // The original looked one step ahead of the distance it counted (two in the far half).
        float2 at = start + direction * (d + (d < 64.0 ? 1.0 : 2.0));
        float ripple = 16.0 * sin(d * (6.2831853 * 3.0 / 192.0));
        return tableAt(first, at.x) + tableAt(second, at.y) + ripple - 240.0;
    }

    // How far the ground stands above a ray of slope q at distance d. Above zero means "hit".
    // The original's ray also dropped one unit per step, and its far steps were two units long.
    static float above(float d, float q, float2 start, float2 direction,
                       const device float *first, const device float *second) {
        float steps = d < 64.0 ? d : 64.0 + (d - 64.0) * 0.5;
        return groundAt(d, start, direction, first, second) + steps - d * q;
    }

    // The original's palette formula (MAIN.C), without rounding to 64 levels or to 128 colours,
    // so the shading has no steps in it.
    static float3 landColour(float index) {
        float a = (223.0 - index) * 26.0 / 22.0;
        float red = (40.0 - min(abs(a - 220.0), 40.0)) / 3.0;
        float green = clamp((230.0 - a) / 4.0 + 8.0 * sin(a * (6.2831853 / 256.0)), 0.0, 63.0);
        float blue = clamp((255.0 - a) / 3.0, 0.0, 63.0);
        return min(float3(red, green, blue) * 1.5, 63.0) / 63.0;
    }

    fragment float4 landscape_fragment(CanvasOut in [[stage_in]],
                                       constant LandUniforms &u [[buffer(0)]],
                                       const device float *first [[buffer(1)]],
                                       const device float *second [[buffer(2)]]) {
        float2 canvas = in.uv * u.canvasSize;
        // Line in the original's off-screen column buffer. Lines above 60 were never shown.
        float line = canvas.y - 10.0 - u.rise.x;
        if (line < 60.0) return float4(0.0, 0.0, 0.0, 1.0);

        // The original cast 160 rays, one per two pixels. Here every pixel gets its own.
        float x = (canvas.x - 1.0) * 0.5 - 80.0;
        float2 direction = float2(x * u.turn.y + 160.0 * u.turn.x, 160.0 * u.turn.w - x * u.turn.z);

        // Slope of this pixel's ray: level 130 pixels above the bottom of the buffer.
        float q = (199.5 - line - 130.0) * (2560.0 / 65536.0);

        float before = 0.0;
        float d = 0.0;
        bool hit = false;
        for (int i = 0; i < 128; i++) {
            if (above(d, q, u.position, direction, first, second) > 0.0) { hit = true; break; }
            before = d;
            d += d < 64.0 ? 1.0 : 2.0;
        }
        if (!hit) return float4(0.0, 0.0, 0.0, 1.0);

        // Close in on the exact spot between the last miss and the first hit.
        float after = d;
        for (int i = 0; i < 7; i++) {
            float middle = (before + after) * 0.5;
            if (above(middle, q, u.position, direction, first, second) > 0.0) after = middle; else before = middle;
        }
        d = after;

        // Colour by height, a little darker with distance; the original halved an 8-bit number.
        float value = groundAt(d, u.position, direction, first, second) + 140.0 - d / 8.0;
        float index = (value - floor(value / 256.0) * 256.0) * 0.5;
        return float4(landColour(index), 1.0);
    }
    """
}
