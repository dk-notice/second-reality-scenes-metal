import Metal

/// Draws `MountainScrollerModel`. 1993 look: the original's screen, kept from step to step and changed
/// exactly as `putrouts` changed it, shown through the part's palette with its fades.
///
/// Modern look: everything drawn afresh each frame. The background is the picture made 8x by Super-xBR.
/// The text is its own picture made 8x the same way, laid over the hills through a smooth map fitted to
/// the position tables (`MountainData.smoothMap`): every screen pixel works out its own place in the text,
/// and the text glides (the 1993 look moves it a third of a column per refresh, a third of the pixels at a
/// time). Text colours come from the same palette entries, blended; the leaves stay in front through a
/// mask of the hills' colours, also made 8x. The fades are the original's rules without the rounding.
///
/// THIS SCENE USES ORIGINAL ARTWORK (`09-mountain-background`, and the files in `Data/Mountain`).
final class MountainScrollerScene: DemoScene {
    static let pictureName = "09-mountain-background"
    private(set) var model: MountainScrollerModel
    private let canvas: IndexedCanvas
    private let picture: ScenePicture
    /// Red: 1 where the background is a hill colour (0...31), made 8x by Super-xBR.
    private let hillMask: MTLTexture
    /// Red: the hill colour's number x 8 (spread outwards under the leaves' edges), made 8x.
    private let hillNumber: MTLTexture
    /// Red: the text's value x 36, 640x32 made 8x.
    private let text: MTLTexture
    /// The smooth map's two planes per screen pixel (320x200, four floats each).
    private let mapU: MTLTexture
    private let mapV: MTLTexture
    private let pipeline: MTLRenderPipelineState
    private let smooth: MTLSamplerState

    static let rampCount = 40
    /// Must match `MountainUniforms` in the shader.
    private struct Uniforms {
        var leaves: Float
        var hills: Float
        var fadeOut: Float
        var shift: Float
        var textOn: Float
        var unused: SIMD3<Float> = .zero
    }
    /// Colours 128...167 (the hills with text on), 0...1.
    private let ramp: [SIMD4<Float>]

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        guard let data = MountainData.load() else { throw PictureError.missing("Data/Mountain") }
        model = MountainScrollerModel(data: data)
        canvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat, width: 320, height: 200)
        picture = try ScenePicture.shared(named: Self.pictureName, device: device)
        ramp = (0..<Self.rampCount).map { SIMD4(SIMD3<Float>(data.palette[128 + $0]) / 63, 1) }

        func grey(_ values: [UInt8], width: Int, height: Int) throws -> MTLTexture {
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for (i, v) in values.enumerated() { bytes[4 * i] = v; bytes[4 * i + 1] = v; bytes[4 * i + 2] = v }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            guard let small = device.makeTexture(descriptor: descriptor) else { throw SceneError.textureFailed }
            small.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
            return try PictureScaler.upscaled(small, device: device)
        }
        let background = data.background
        hillMask = try grey(background.map { $0 < 32 ? 255 : 0 }, width: 320, height: 200)
        // The hills' colour numbers, carried a few pixels in under the leaves so the leaves' edges do not
        // darken the text's colour.
        var numbers = background.map { $0 < 32 ? Int($0) : -1 }
        for _ in 0..<12 {
            var next = numbers
            for y in 0..<200 {
                for x in 0..<320 where numbers[y * 320 + x] < 0 {
                    var sum = 0, count = 0
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let xx = x + dx, yy = y + dy
                        if xx >= 0, yy >= 0, xx < 320, yy < 200, numbers[yy * 320 + xx] >= 0 { sum += numbers[yy * 320 + xx]; count += 1 }
                    }
                    if count > 0 { next[y * 320 + x] = (2 * sum + count) / (2 * count) }
                }
            }
            numbers = next
        }
        hillNumber = try grey(numbers.map { UInt8(max($0, 0) * 8) }, width: 320, height: 200)
        // The text with an empty 32nd row (a tidy height; the part never shows the picture's own row 31).
        text = try grey(data.text.map { $0 * 36 } + [UInt8](repeating: 0, count: 640), width: 640, height: 32)

        let map = data.smoothMap()
        func floats(_ values: [Float]) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: 320, height: 200, mipmapped: false)
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw SceneError.textureFailed }
            texture.replace(region: MTLRegionMake2D(0, 0, 320, 200), mipmapLevel: 0, withBytes: values, bytesPerRow: 320 * 16)
            return texture
        }
        mapU = try floats(map.u)
        mapV = try floats(map.v)

        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("mountain_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        smooth = try Shaders.sampler(device: device, smooth: true, anisotropy: 16)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func demoUpdate(_ context: DemoContext) { model.musicPlus = context.music.plus }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            let palette = model.palette.map { SIMD4<Float>(SIMD3<Float>($0) / 63, 1) }
            canvas.draw(into: encoder, indices: model.screen, palette: palette)
            return
        }
        let view = model.modernView(alpha: frame.alpha)
        var uniforms = Uniforms(leaves: view.leaves / 63, hills: view.hills / 63, fadeOut: view.fadeOut / 63,
                                shift: view.shift ?? 0, textOn: view.shift == nil ? 0 : 1)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(picture.upscaled, index: 0)
        encoder.setFragmentTexture(hillMask, index: 1)
        encoder.setFragmentTexture(hillNumber, index: 2)
        encoder.setFragmentTexture(text, index: 3)
        encoder.setFragmentTexture(mapU, index: 4)
        encoder.setFragmentTexture(mapV, index: 5)
        encoder.setFragmentSamplerState(smooth, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(ramp, length: MemoryLayout<SIMD4<Float>>.stride * ramp.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    func classicReferenceFrame() -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(64000 * 3)
        let levels = model.palette
        for n in model.screen {
            let c = levels[Int(n)]
            out += [byteFromVGA(c.x), byteFromVGA(c.y), byteFromVGA(c.z)]
        }
        return out
    }

    private static let shaderSource = """
    struct MountainUniforms {
        float leaves;    // how far the leaves have faded in, 0...1 (each channel: min(colour, this))
        float hills;     // the same for the hills and the text
        float fadeOut;   // taken off every channel at the end
        float shift;     // how far the text has moved, columns
        float textOn;    // 0 before the scroll
    };

    // How much of [lo, hi) a pixel of width w around v covers (soft edges, one pixel wide).
    static float mountain_inside(float v, float lo, float hi, float w) {
        return clamp((v - lo) / w + 0.5, 0.0, 1.0) * clamp((hi - v) / w + 0.5, 0.0, 1.0);
    }

    fragment float4 mountain_fragment(CanvasOut in [[stage_in]],
                                      texture2d<float> background [[texture(0)]],
                                      texture2d<float> hillMask [[texture(1)]],
                                      texture2d<float> hillNumber [[texture(2)]],
                                      texture2d<float> text [[texture(3)]],
                                      texture2d<float> mapU [[texture(4)]],
                                      texture2d<float> mapV [[texture(5)]],
                                      sampler smp [[sampler(0)]],
                                      constant MountainUniforms &u [[buffer(0)]],
                                      constant float4 *ramp [[buffer(1)]]) {
        float3 c = background.sample(smp, in.uv).rgb;
        float mask = hillMask.sample(smp, in.uv).r;
        float3 hill = c;
        if (u.textOn > 0.5 && mask > 0.004) {
            // The four map pixels around this point: each one's plane says where in the text we are.
            float2 p = in.uv * float2(320.0, 200.0) - 0.5;      // map pixel centres at whole numbers
            float2 base = floor(p);
            float bestWeight = -1.0;
            float2 best = float2(0.0), bestDx = float2(0.0), bestDy = float2(0.0);
            float2 where[4]; float2 gx[4]; float2 gy[4]; float weight[4];
            for (int k = 0; k < 4; k++) {
                float2 q = base + float2(k & 1, k >> 1);
                weight[k] = -1.0;
                if (q.x < 0.0 || q.y < 0.0 || q.x > 319.0 || q.y > 199.0) continue;
                float4 a = mapU.read(uint2(q)), b = mapV.read(uint2(q));
                if (a.w < 0.5) continue;
                float2 d = p - q;
                where[k] = float2(a.x + a.y * d.x + a.z * d.y, b.x + b.y * d.x + b.z * d.y);
                gx[k] = float2(a.y, b.y); gy[k] = float2(a.z, b.z);
                weight[k] = (1.0 - abs(d.x)) * (1.0 - abs(d.y));
                if (weight[k] > bestWeight) { bestWeight = weight[k]; best = where[k]; bestDx = gx[k]; bestDy = gy[k]; }
            }
            if (bestWeight >= 0.0) {
                // Blend the neighbours that agree with the nearest one (the others are another fold of the hills).
                float2 sum = float2(0.0), sumDx = float2(0.0), sumDy = float2(0.0); float total = 0.0;
                for (int k = 0; k < 4; k++) {
                    if (weight[k] < 0.0) continue;
                    float2 off = abs(where[k] - best);
                    if (off.x >= 1.0 || off.y >= 1.0) continue;
                    float wt = weight[k] + 1e-4;
                    sum += where[k] * wt; sumDx += gx[k] * wt; sumDy += gy[k] * wt; total += wt;
                }
                float2 t = sum / total;                       // window column, text row
                float2 dx = sumDx / total, dy = sumDy / total;  // their change per canvas pixel
                float2 px = fwidth(in.uv) * float2(320.0, 200.0);   // one screen pixel in canvas pixels
                float2 span = max(abs(dx) * px.x + abs(dy) * px.y, float2(1e-4));
                float cover = mountain_inside(t.x, 0.0, 237.0, span.x) * mountain_inside(t.y, 0.0, 31.0, span.y);
                float column = t.x - 104.0 + u.shift;
                cover *= clamp(column / span.x + 0.5, 0.0, 1.0);     // nothing before the text's first column
                if (cover > 0.0) {
                    // Past the last column the sampler repeats it, as the original's window did.
                    float2 tuv = float2(column / 640.0, t.y / 32.0);
                    float2 scale = float2(1.0 / 640.0, 1.0 / 32.0);
                    float level = text.sample(smp, tuv, gradient2d(dx * px.x * scale, dy * px.y * scale)).r * (255.0 / 36.0);
                    if (level > 0.0) {
                        // 1993: colour 128 + hill colour + text value. Between whole values: blended.
                        float position = clamp(hillNumber.sample(smp, in.uv).r * (255.0 / 8.0) + max(level, 1.0), 0.0, 38.999);
                        int i = int(position);
                        float3 lit = mix(ramp[i].rgb, ramp[i + 1].rgb, position - float(i));
                        hill = mix(c, lit, min(level, 1.0) * cover);
                    }
                }
            }
        }
        float3 shown = mix(min(c, float3(u.leaves)), min(hill, float3(u.hills)), mask);
        return float4(max(shown - u.fadeOut, 0.0), 1.0);
    }
    """
}
