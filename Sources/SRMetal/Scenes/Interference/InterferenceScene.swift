import Metal
import simd

/// Draws the Rings and Interference scenes on the graphics chip. They share ring pictures and a shader;
/// `part` says which one this is.
///
/// Unlike the dot tunnel, this scene paints every pixel of the canvas. The shader runs once per pixel
/// and decides its colour.
///
///  - Classic look: it looks the pixel up in the two ring pictures, exactly as the VGA card did.
///  - Modern look: it ignores the pictures and calculates the rings from the pixel's distance to each
///    centre, at full screen resolution, with soft edges. The 1993 code could never afford that maths
///    per pixel; a graphics chip does it without effort.
final class InterferenceScene: DemoScene {
    private(set) var model: InterferenceModel
    private let pipeline: MTLRenderPipelineState
    private let ringTexture: MTLTexture
    private let stripeTexture: MTLTexture

    /// Must match `Uniforms` in the shader source below.
    private struct Uniforms {
        var canvasSize: SIMD2<Float>
        var ringScroll: SIMD2<Float>
        var stripeScroll: SIMD2<Float>
        var wobbleAmplitude: Float
        var wobblePhase: Float
        var cycle: Float
        var classic: UInt32
        var stripesOn: UInt32
        var padding: UInt32 = 0
    }

    init(part: InterferenceModel.Part, device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        model = InterferenceModel(part: part)
        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.fragmentSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("interference_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        ringTexture = try Self.pictureTexture(device: device, bytes: InterferenceModel.ringPicture)
        stripeTexture = try Self.pictureTexture(device: device, bytes: InterferenceModel.stripePicture)
    }

    /// Hands one of the 640x400 ring pictures to the graphics chip, one whole number per pixel.
    private static func pictureTexture(device: MTLDevice, bytes: [UInt8]) throws -> MTLTexture {
        let width = InterferenceModel.pictureWidth
        let height = InterferenceModel.pictureHeight
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Uint, width: width, height: height, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw SceneError.textureFailed
        }
        bytes.withUnsafeBytes { buffer in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: buffer.baseAddress!, bytesPerRow: width)
        }
        return texture
    }

    func reset() { model.reset() }
    func tick() { model.tick() }

    func classicReferenceFrame() -> [UInt8] {
        model.classicReferenceFrame().map { byteFromVGA(Int($0)) }
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        var uniforms: Uniforms
        var palette: [SIMD4<Float>]
        var wobble: [Int32]

        if frame.look == .classic {
            let layout = model.classicLayout()
            palette = model.classicPalette().map { SIMD4<Float>(SIMD3<Float>($0) / 63, 1) }
            wobble = layout.wobble.map { Int32($0) }
            uniforms = Uniforms(
                canvasSize: frame.canvasSize,
                ringScroll: SIMD2<Float>(layout.ringScroll),
                stripeScroll: SIMD2<Float>(layout.stripeScroll ?? SIMD2(0, 0)),
                wobbleAmplitude: 0, wobblePhase: 0, cycle: 0,
                classic: 1,
                stripesOn: layout.stripeScroll == nil ? 0 : 1)
        } else {
            let parameters = model.modernParameters(alpha: Double(frame.alpha))
            palette = parameters.ramps.map { SIMD4<Float>($0, 1) }
            wobble = [Int32](repeating: 0, count: 200)
            uniforms = Uniforms(
                canvasSize: frame.canvasSize,
                ringScroll: parameters.ringScroll,
                stripeScroll: parameters.stripeScroll,
                wobbleAmplitude: parameters.wobbleAmplitude,
                wobblePhase: parameters.wobblePhase,
                cycle: parameters.cycle,
                classic: 0,
                stripesOn: parameters.stripesOn ? 1 : 0)
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&palette, length: MemoryLayout<SIMD4<Float>>.stride * palette.count, index: 1)
        encoder.setFragmentBytes(&wobble, length: MemoryLayout<Int32>.stride * wobble.count, index: 2)
        encoder.setFragmentTexture(ringTexture, index: 0)
        encoder.setFragmentTexture(stripeTexture, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    private static let fragmentSource = """
    struct Uniforms {
        float2 canvasSize;
        float2 ringScroll;      // top-left of the screen window on the 8-colour ring picture
        float2 stripeScroll;    // same for the 1-bit stripe picture
        float wobbleAmplitude;  // modern look: sideways wave size, in canvas pixels
        float wobblePhase;      // modern look: wave position at the top row, in 1/1024 turns
        float cycle;            // modern look: how far the colours have rotated, 0..8
        uint classic;
        uint stripesOn;
        uint padding;
    };

    // Colour of ring-position `t` on an 8-colour ramp, with the edge between two rings softened
    // over one screen pixel. `base` is 0 or 8: which of the two ramps.
    static float3 bandColour(const device float4 *palette, int base, float t) {
        float whole = floor(t);
        float edge = saturate((t - whole) / max(fwidth(t), 1e-5));
        int i = int(whole);
        float3 previous = palette[base + ((i - 1) & 7)].rgb;
        float3 current = palette[base + (i & 7)].rgb;
        return mix(previous, current, edge);
    }

    fragment float4 interference_fragment(CanvasOut in [[stage_in]],
                                          constant Uniforms &u [[buffer(0)]],
                                          const device float4 *palette [[buffer(1)]],
                                          const device int *wobble [[buffer(2)]],
                                          texture2d<uint> ringPicture [[texture(0)]],
                                          texture2d<uint> stripePicture [[texture(1)]]) {
        float2 pos = in.uv * u.canvasSize;   // canvas position; whole pixels are centred on .5

        if (u.classic != 0) {
            // 1993: look both pictures up, then let the 16-colour table decide.
            int2 pixel = clamp(int2(floor(pos)), int2(0, 0), int2(319, 199));
            uint ring = ringPicture.read(uint2(pixel + int2(u.ringScroll))).r;
            uint bit = 0;
            if (u.stripesOn != 0) {
                int2 where = pixel + int2(u.stripeScroll) + int2(wobble[pixel.y], 0);
                bit = stripePicture.read(uint2(where)).r;
            }
            return float4(palette[bit * 8 + ring].rgb, 1.0);
        }

        // Modern: work the rings out from distance, per screen pixel.
        const float2 centre = float2(320.0, 200.0);
        float ringDistance = length(pos + u.ringScroll - centre);
        float t = pow(ringDistance, 1.4) / 16.0 + u.cycle;
        float3 lower = bandColour(palette, 0, t);
        if (u.stripesOn == 0) {
            return float4(lower, 1.0);
        }
        float3 upper = bandColour(palette, 8, t);

        float wave = u.wobbleAmplitude * sin((u.wobblePhase + 9.0 * (pos.y + 0.5)) * (M_PI_F / 512.0));
        float stripeDistance = length(pos + u.stripeScroll + float2(wave, 0.0) - centre);
        float s = stripeDistance / 12.0;
        float whole = floor(s);
        float edge = saturate((s - whole) / max(fwidth(s), 1e-5));
        int i = int(whole);
        float on = mix(float((i - 1) & 1), float(i & 1), edge);

        return float4(mix(lower, upper, on), 1.0);
    }
    """
}

enum SceneError: Error, CustomStringConvertible {
    case textureFailed

    var description: String {
        switch self {
        case .textureFailed: return "Could not create a texture"
        }
    }
}
