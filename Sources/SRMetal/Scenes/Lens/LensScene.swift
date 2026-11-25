import Metal

/// Draws `LensModel`. 1993 look: the original's screen, kept from step to step and changed exactly as the
/// original changed it, shown through its palette. Modern look: everything drawn afresh each frame: the
/// lens picture made 8x by Super-xBR, uncovered by the same sweeps (gliding, soft-edged), and the lens
/// bending it by the same formula worked out for every screen pixel, with the unrounded path blended
/// between steps, smooth-edged tint zones and a smooth fade-in. No random wobble (it only broke up the
/// 1993 rounding) and nothing left behind to wipe.
///
/// THIS SCENE USES ORIGINAL ARTWORK (`10-lens-picture`, and the lens shape `10-lens-shape` for the tables).
final class LensScene: DemoScene {
    static let pictureName = "10-lens-picture"
    private(set) var model: LensModel
    private let canvas: IndexedCanvas
    private let picture: ScenePicture
    /// The lens's zones (red: the lens, green: zone 2, blue: zone 3), 160x120 made 8x by Super-xBR.
    private let zones: MTLTexture
    private let pipeline: MTLRenderPipelineState
    private let smooth: MTLSamplerState

    /// Must match `LensUniforms` in the shader.
    private struct Uniforms {
        var tint1: SIMD4<Float>
        var tint2: SIMD4<Float>
        var tint3: SIMD4<Float>
        var lensTopLeft: SIMD2<Float>
        var moves: Float
        var lensOn: Float
        var glass: Float
        var unused: SIMD3<Float> = .zero
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        guard let indexed = ScenePicture.colourNumbers(Self.pictureName, limit: 64), indexed.numbers.count == 64000 else {
            throw PictureError.missing(Self.pictureName)
        }
        guard let shape = LensTables.shape() else { throw PictureError.missing(LensTables.shapeName) }
        guard let ring = LensTables.ringTable() else { throw PictureError.missing("Data/Lens/LENS.EX4") }
        model = LensModel(picture: indexed.numbers, colours: indexed.colours, tables: LensTables.calculated(shape: shape) + [ring])
        canvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat, width: 320, height: 200)
        picture = try ScenePicture.shared(named: Self.pictureName, device: device)

        // The zone masks: lens pixels are columns 0...149 and rows 0...115 of the shape (row 116 is never drawn).
        let w = 160, h = 120
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<LensModel.lensHeight {
            for x in 0..<150 {
                let zone = shape[x + y * 320], i = 4 * (x + y * w)
                bytes[i] = (1...3).contains(zone) ? 255 : 0
                bytes[i + 1] = zone == 2 ? 255 : 0
                bytes[i + 2] = zone == 3 ? 255 : 0
            }
        }
        for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        guard let mask = device.makeTexture(descriptor: descriptor) else { throw SceneError.textureFailed }
        mask.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
        zones = try PictureScaler.upscaled(mask, device: device)

        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.shaderSource)
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        pipelineDescriptor.fragmentFunction = try Shaders.function("lens_fragment", in: library)
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        smooth = try Shaders.sampler(device: device, smooth: true, anisotropy: 16)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func demoUpdate(_ context: DemoContext) {
        model.musicPlus = context.music.plus
        if context.justShown { model.startIfCued() }
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            let palette = model.palette.map { SIMD4<Float>(SIMD3<Float>($0) / 63, 1) }
            canvas.draw(into: encoder, indices: Array(model.screen[0..<64000]), palette: palette)
            return
        }
        func tint(_ i: Int) -> SIMD4<Float> { SIMD4(SIMD3<Float>(LensModel.tints[i]) / 63, 0) }
        let centre = model.lensCentre(alpha: frame.alpha)
        let half = SIMD2<Float>(Float(LensModel.lensWidth / 2), Float(LensModel.lensHeight / 2))
        var uniforms = Uniforms(tint1: tint(0), tint2: tint(1), tint3: tint(2),
                                lensTopLeft: (centre ?? .zero) - half,
                                moves: model.sweepMoves(alpha: frame.alpha), lensOn: centre == nil ? 0 : 1,
                                glass: model.glass(alpha: frame.alpha))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(picture.upscaled, index: 0)
        encoder.setFragmentTexture(zones, index: 1)
        encoder.setFragmentSamplerState(smooth, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    func classicReferenceFrame() -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(64000 * 3)
        let levels = model.palette
        for n in model.screen[0..<64000] {
            let c = levels[Int(n)]
            out += [byteFromVGA(c.x), byteFromVGA(c.y), byteFromVGA(c.z)]
        }
        return out
    }

    private static let shaderSource = """
    struct LensUniforms {
        float4 tint1, tint2, tint3;   // the three zones' tints (0...1)
        float2 lensTopLeft;           // the lens's top-left corner, canvas pixels
        float moves;                  // sweep moves done (480 = the picture fully uncovered)
        float lensOn;
        float glass;                  // 0: the tint alone shows in the lens ... 1: the tinted picture
        float3 unused;
    };

    // Row b's sweeps (MAIN.C part1): start (170·64 + (100 − b)·50) / 64; per move right ((23 + b/5) & ~7) / 64,
    // left ((23 + (199 − b)/5) rounded up to a multiple of 8) / 64. b is continuous for the start (a smooth
    // slant), whole for the speeds (the original's bands of rows). Returns (left end, right end).
    static float2 sweepSpan(float b, float moves) {
        int row = clamp(int(floor(b)), 0, 199);
        float start = (170.0 * 64.0 + (100.0 - b) * 50.0) / 64.0;
        float right = float((23 + row / 5) & ~7) / 64.0;
        float left = float((23 + (199 - row) / 5 + 7) & ~7) / 64.0;
        return float2(start - left * max(moves - 1.0, 0.0), start + right * max(moves - 1.0, 0.0));
    }

    static float covered(float x, float2 span, float moves) {
        if (moves <= 0.0) return 0.0;
        return clamp(x - span.x + 1.0, 0.0, 1.0) * clamp(span.y + 1.0 - x, 0.0, 1.0);
    }

    fragment float4 lens_fragment(CanvasOut in [[stage_in]], texture2d<float> pic [[texture(0)]],
                                  texture2d<float> zones [[texture(1)]], sampler smp [[sampler(0)]],
                                  constant LensUniforms &u [[buffer(0)]]) {
        float2 p = in.uv * float2(320.0, 200.0);
        // The picture, uncovered by the sweeps. A sweep that runs past its row's end carries on into the
        // next row (left sweep: into the previous one), as the original's addresses did.
        float b = p.y - 0.5, x = p.x - 0.5;
        float shown = covered(x, sweepSpan(b, u.moves), u.moves);
        shown = max(shown, covered(x + 320.0, sweepSpan(b - 1.0, u.moves), u.moves));
        shown = max(shown, covered(x - 320.0, sweepSpan(b + 1.0, u.moves), u.moves));
        float3 colour = pic.sample(smp, in.uv).rgb * shown;
        if (u.lensOn < 0.5) return float4(colour, 1.0);

        // The lens (CALC.C's lenscalc): lens pixel (x1, y1) from the centre (76, 58) shows the picture at
        // (x1, y1) · 250 / max(full − x1² − (9·y1/8)², 1)^0.69, full = 59² + 50².
        float2 local = p - u.lensTopLeft;
        float4 zone = zones.sample(smp, local / float2(160.0, 120.0));
        if (zone.r <= 0.0) return float4(colour, 1.0);
        float2 d = local - 0.5 - float2(76.0, 58.0);
        float now = max(59.0 * 59.0 + 50.0 * 50.0 - (d.x * d.x + (d.y * 9.0 / 8.0) * (d.y * 9.0 / 8.0)), 1.0);
        float bend = 250.0 / pow(now, 0.69);
        float2 source = u.lensTopLeft + float2(76.0, 58.0) + d * bend + 0.5;
        float2 gx = dfdx(source) / float2(320.0, 200.0), gy = dfdy(source) / float2(320.0, 200.0);
        float2 suv = clamp(source / float2(320.0, 200.0), float2(0.0), float2(1.0));
        float3 seen = pic.sample(smp, suv, gradient2d(gx, gy)).rgb;
        float3 tint = u.tint1.rgb + zone.g * (u.tint2.rgb - u.tint1.rgb) + zone.b * (u.tint3.rgb - u.tint1.rgb);
        // The original's fade2: the tinted colour, less the picture's own colour times (1 − glass).
        float3 glassColour = min(seen + tint, float3(1.0)) - seen * (1.0 - u.glass);
        return float4(mix(colour, glassColour, zone.r), 1.0);
    }
    """
}
