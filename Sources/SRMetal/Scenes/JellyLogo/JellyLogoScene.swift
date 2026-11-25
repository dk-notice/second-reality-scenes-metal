import Metal

/// Draws `JellyLogoModel`. 1993 look: the original's 320x400 screen, kept from step to step and changed
/// exactly as `doit` changed it (whole-number edges, even widths, DOL.C's column rounding, the rows the
/// row cache leaves black). Modern look: every screen pixel works out its own source row and line width
/// from the same formulas without rounding, on the picture made 8x by Super-xBR; the slide-in glides
/// in 1/64 rows and the bounce is spread evenly over its refreshes (the 1993 table shows each value twice).
///
/// THIS SCENE USES ORIGINAL ARTWORK (`artwork/original/rgb/15-jelly-logo.png`).
final class JellyLogoScene: DemoScene {
    static let pictureName = "15-jelly-logo"
    private(set) var model: JellyLogoModel
    private let canvas: IndexedCanvas
    private let picture: ScenePicture
    private let pipeline: MTLRenderPipelineState
    private let smooth: MTLSamplerState
    /// The 1993 screen's colours (VGA levels) by colour number.
    private let levels: [SIMD3<Int>]

    /// Must match `JellyUniforms` in the shader.
    private struct Uniforms {
        var mode: Float          // 0 black, 1 slide-in (flat picture), 2 jelly
        var startRow: Float
        var top: Float
        var bottom: Float
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        guard let indexed = ScenePicture.colourNumbers(Self.pictureName, limit: 256 - JellyLogoModel.firstPictureColour),
              indexed.numbers.count == 320 * 400 else {
            throw PictureError.missing(Self.pictureName)
        }
        model = JellyLogoModel(picture: indexed.numbers.map { $0 + UInt8(JellyLogoModel.firstPictureColour) })
        levels = [SIMD3(0, 0, 0), SIMD3(63, 63, 63)] + indexed.colours
        canvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat, width: 320, height: 400)
        picture = try ScenePicture.shared(named: Self.pictureName, device: device)

        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("jelly_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        smooth = try Shaders.sampler(device: device, smooth: true, anisotropy: 16)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func demoUpdate(_ context: DemoContext) { model.musicPlus = context.music.plus }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            let palette = levels.map { SIMD4<Float>(SIMD3<Float>($0) / 63, 1) }
            canvas.draw(into: encoder, indices: model.screen, palette: palette)
            return
        }
        var uniforms = Uniforms(mode: 0, startRow: 0, top: 0, bottom: 0)
        switch model.modernView(alpha: frame.alpha) {
        case .black: break
        case .slide(let row): uniforms.mode = 1; uniforms.startRow = row
        case .jelly(let top, let bottom): uniforms.mode = 2; uniforms.top = top; uniforms.bottom = bottom
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(picture.upscaled, index: 0)
        encoder.setFragmentSamplerState(smooth, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    func classicReferenceFrame() -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(320 * 400 * 3)
        for n in model.screen {
            let c = levels[Int(n)]
            out += [byteFromVGA(c.x), byteFromVGA(c.y), byteFromVGA(c.z)]
        }
        return out
    }

    private static let shaderSource = """
    struct JellyUniforms {
        float mode;       // 0 black, 1 slide-in (flat picture), 2 jelly
        float startRow;   // slide-in: the screen's start row (rows below the picture are black)
        float top;        // jelly: the picture's top and bottom edges, screen rows
        float bottom;
    };

    // How much of [lo, hi) a pixel of width w around v covers (soft edges, one pixel wide).
    static float inside(float v, float lo, float hi, float w) {
        return clamp((v - lo) / w + 0.5, 0.0, 1.0) * clamp((hi - v) / w + 0.5, 0.0, 1.0);
    }

    fragment float4 jelly_fragment(CanvasOut in [[stage_in]], texture2d<float> pic [[texture(0)]],
                                   sampler smp [[sampler(0)]], constant JellyUniforms &u [[buffer(0)]]) {
        if (u.mode < 0.5) return float4(0.0, 0.0, 0.0, 1.0);
        float2 p = in.uv * float2(320.0, 400.0);       // canvas position; pixel centres at n + 0.5
        float2 w = max(fwidth(p), float2(1e-4));
        float row, cover, xsc;
        if (u.mode < 1.5) {
            row = p.y + u.startRow;                        // memory row
            cover = inside(row, 0.0, 400.0, w.y);
            xsc = 0.0;
        } else {
            float h = max(u.bottom - u.top, 1.0);
            row = (p.y - u.top) * 400.0 / h;
            cover = inside(p.y, u.top, u.bottom, w.y);
            xsc = (400.0 - h) / 8.0;
        }
        // The line's width: 184 plus the sine bulge (JPLOGO's table: sin x 256, at most 255).
        float s = clamp(256.0 * sin(clamp(row, 0.0, 400.0) * M_PI_F / 400.0), -255.0, 255.0);
        float width = 184.0 + s * xsc / 64.0;
        // DOL.C: columns 160 - width/2 ... 160 + width/2 (width + 1 of them) show the 185 source columns.
        float left = 160.0 - width * 0.5;
        float scale = 185.0 / (width + 1.0);
        float source = (p.x - left) * scale;               // 0 ... 185: picture columns 70 ... 253, then white
        float sw = w.x * scale;
        cover *= inside(source, 0.0, 185.0, sw);
        float2 uv = float2(clamp(70.0 + source, 70.5, 253.5) / 320.0, clamp(row, 0.5, 399.5) / 400.0);
        float3 c = pic.sample(smp, uv).rgb;
        c = mix(c, float3(1.0), inside(source, 184.0, 185.0, sw));   // the white edge column
        return float4(c * cover, 1.0);
    }
    """
}
