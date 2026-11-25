import Metal

/// Draws `WaterScrollerModel`. 1993 look: the original's screen, kept from step to step and changed
/// exactly as `putrouts1` changed it, shown through the part's palette with its fades.
///
/// Modern look: everything drawn afresh each frame. The background is the picture made 8x by Super-xBR.
/// The sword is its own picture made 8x the same way (its colours on black, and its outline as a mask),
/// laid over the water and the reflections through the smooth map fitted to the position tables
/// (`ScrollTables.smoothMap`): every screen pixel works out its own place on the sword, and the sword
/// glides (the 1993 look moves it a third of a column per refresh, a third of the pixels at a time). In
/// the tiny reflections, where a whole stretch of sword falls inside one pixel, each pixel shows the
/// average of its stretch. The fades are the original's rule, red twice as fast, without the rounding.
///
/// THIS SCENE USES ORIGINAL ARTWORK (`13-water-background`, and the files in `Data/Water`).
final class WaterScrollerScene: DemoScene {
    static let pictureName = "13-water-background"
    /// Empty rows above and below the sword in its texture, so nothing is repeated at its edges.
    static let padding = 3
    private(set) var model: WaterScrollerModel
    private let canvas: IndexedCanvas
    private let picture: ScenePicture
    /// The sword's colours on black, 400x40 made 8x by Super-xBR.
    private let sword: MTLTexture
    /// Red: 1 where the sword is, made 8x the same way.
    private let swordMask: MTLTexture
    /// Red: 1 where the sword can show (water and reflections), 320x200 made 8x: smooth edges against
    /// the balls in front.
    private let areaMask: MTLTexture
    /// The smooth map's two planes per screen pixel (320x200, four floats each).
    private let mapU: MTLTexture
    private let mapV: MTLTexture
    private let pipeline: MTLRenderPipelineState
    private let smooth: MTLSamplerState

    /// Must match `WaterUniforms` in the shader.
    private struct Uniforms {
        var fadeIn: Float
        var fadeOut: Float
        var shift: Float
        var swordOn: Float
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        guard let data = WaterData.load() else { throw PictureError.missing("Data/Water") }
        model = WaterScrollerModel(data: data)
        canvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat, width: 320, height: 200)
        picture = try ScenePicture.shared(named: Self.pictureName, device: device)

        /// `colours`: red, green, blue per pixel. Made 8x by Super-xBR.
        func upscaled(_ colours: [SIMD3<UInt8>], width: Int, height: Int) throws -> MTLTexture {
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for (i, c) in colours.enumerated() { bytes[4 * i] = c.x; bytes[4 * i + 1] = c.y; bytes[4 * i + 2] = c.z }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            guard let small = device.makeTexture(descriptor: descriptor) else { throw SceneError.textureFailed }
            small.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
            return try PictureScaler.upscaled(small, device: device)
        }
        let w = WaterData.swordWidth, h = WaterData.rows + 2 * Self.padding
        var colours = [SIMD3<UInt8>](repeating: .zero, count: w * h), mask = colours
        for row in 0..<WaterData.rows {
            for column in 0..<w {
                let number = Int(data.sword[row * w + column])
                guard number != 0 else { continue }
                let c = data.colour(number)
                colours[(row + Self.padding) * w + column] = SIMD3(byteFromVGA(c.x), byteFromVGA(c.y), byteFromVGA(c.z))
                mask[(row + Self.padding) * w + column] = SIMD3(repeating: 255)
            }
        }
        sword = try upscaled(colours, width: w, height: h)
        swordMask = try upscaled(mask, width: w, height: h)

        let map = data.smoothMap()
        // Where the sword can show: the tables' own pixels, and the map's grown-on pixels that lie beyond
        // the window's edge (there the map itself cuts the sword off; a grown-on pixel that is still inside
        // the window is something in front of the water, a ball's edge).
        var area = [SIMD3<UInt8>](repeating: .zero, count: 64000)
        for table in data.tables { for address in table.addresses { area[Int(address)] = SIMD3(repeating: 255) } }
        for i in 0..<64000 where area[i].x == 0 && map.u[4 * i + 3] == 1 {
            let u = map.u[4 * i], v = map.v[4 * i]
            if u < 0 || u > Float(WaterData.columns) || v < 0 || v > Float(WaterData.rows) { area[i] = SIMD3(repeating: 255) }
        }
        areaMask = try upscaled(area, width: 320, height: 200)

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
        descriptor.fragmentFunction = try Shaders.function("water_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        smooth = try Shaders.sampler(device: device, smooth: true, anisotropy: 16)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func demoUpdate(_ context: DemoContext) { model.update(music: context.music, justShown: context.justShown) }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            let palette = model.palette.map { SIMD4<Float>(SIMD3<Float>($0) / 63, 1) }
            canvas.draw(into: encoder, indices: model.screen, palette: palette)
            return
        }
        let view = model.modernView(alpha: frame.alpha)
        var uniforms = Uniforms(fadeIn: view.fadeIn / 63, fadeOut: view.fadeOut / 63,
                                shift: view.shift ?? 0, swordOn: view.shift == nil ? 0 : 1)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(picture.upscaled, index: 0)
        encoder.setFragmentTexture(sword, index: 1)
        encoder.setFragmentTexture(swordMask, index: 2)
        encoder.setFragmentTexture(areaMask, index: 3)
        encoder.setFragmentTexture(mapU, index: 4)
        encoder.setFragmentTexture(mapV, index: 5)
        encoder.setFragmentSamplerState(smooth, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
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
    struct WaterUniforms {
        float fadeIn;    // how far the picture has faded in, 0...1 (green, blue: min(colour, this); red: twice this)
        float fadeOut;   // taken off green and blue at the end (red: twice this)
        float shift;     // how far the sword has moved, columns
        float swordOn;   // 0 before the scroll
    };

    // How much of [lo, hi) a pixel of width w around v covers (soft edges, one pixel wide).
    static float water_inside(float v, float lo, float hi, float w) {
        return clamp((v - lo) / w + 0.5, 0.0, 1.0) * clamp((hi - v) / w + 0.5, 0.0, 1.0);
    }

    fragment float4 water_fragment(CanvasOut in [[stage_in]],
                                   texture2d<float> background [[texture(0)]],
                                   texture2d<float> sword [[texture(1)]],
                                   texture2d<float> swordMask [[texture(2)]],
                                   texture2d<float> areaMask [[texture(3)]],
                                   texture2d<float> mapU [[texture(4)]],
                                   texture2d<float> mapV [[texture(5)]],
                                   sampler smp [[sampler(0)]],
                                   constant WaterUniforms &u [[buffer(0)]]) {
        float3 c = background.sample(smp, in.uv).rgb;
        float area = areaMask.sample(smp, in.uv).r;
        if (u.swordOn > 0.5 && area > 0.004) {
            // The four map pixels around this point: each one's plane says where on the sword we are.
            float2 p = in.uv * float2(320.0, 200.0) - 0.5;      // map pixel centres at whole numbers
            float2 base = floor(p);
            float bestWeight = -1.0, bestKind = 1.0;
            float2 best = float2(0.0);
            float2 where[4]; float2 gx[4]; float2 gy[4]; float weight[4]; float kind[4];
            for (int k = 0; k < 4; k++) {
                float2 q = base + float2(k & 1, k >> 1);
                weight[k] = -1.0;
                if (q.x < 0.0 || q.y < 0.0 || q.x > 319.0 || q.y > 199.0) continue;
                float4 a = mapU.read(uint2(q)), b = mapV.read(uint2(q));
                if (a.w < 0.5) continue;
                float2 d = p - q;
                kind[k] = a.w;
                // A tiny reflection's pixel (2) is one place on the sword; its slopes are its footprint.
                where[k] = a.w > 1.5 ? float2(a.x, b.x) : float2(a.x + a.y * d.x + a.z * d.y, b.x + b.y * d.x + b.z * d.y);
                gx[k] = float2(a.y, b.y); gy[k] = float2(a.z, b.z);
                weight[k] = (1.0 - abs(d.x)) * (1.0 - abs(d.y));
                if (weight[k] > bestWeight) { bestWeight = weight[k]; best = where[k]; bestKind = a.w; }
            }
            if (bestWeight >= 0.0) {
                // Blend the neighbours that agree with the nearest one (the others are another fold of the
                // water, or another reflection).
                float2 sum = float2(0.0), sumDx = float2(0.0), sumDy = float2(0.0); float total = 0.0;
                for (int k = 0; k < 4; k++) {
                    if (weight[k] < 0.0 || kind[k] != bestKind) continue;
                    float2 off = abs(where[k] - best);
                    if (off.x >= 1.0 || off.y >= 1.0) continue;
                    float wt = weight[k] + 1e-4;
                    sum += where[k] * wt; sumDx += gx[k] * wt; sumDy += gy[k] * wt; total += wt;
                }
                float2 t = sum / total;                         // window column, sword row
                // How much sword one screen pixel spans, along x and along y.
                float2 px = fwidth(in.uv) * float2(320.0, 200.0);   // one screen pixel in canvas pixels
                float2 fx = sumDx / total * px.x, fy = sumDy / total * px.y;
                if (bestKind > 1.5) { fx = sumDx / total; fy = sumDy / total; }   // the whole canvas pixel's stretch
                float2 span = max(abs(fx) + abs(fy), float2(1e-4));
                float cover = water_inside(t.x, 0.0, 158.0, span.x) * water_inside(t.y, 0.0, 34.0, span.y);
                float column = t.x - 159.0 + u.shift;
                cover *= clamp(column / span.x + 0.5, 0.0, 1.0);     // nothing before the sword's first column
                if (cover > 0.0) {
                    // Past the last column the sampler repeats it (empty).
                    float2 scale = float2(1.0 / 400.0, 1.0 / 40.0);
                    float2 tuv = float2(column, t.y + 3.0) * scale;
                    float3 s = sword.sample(smp, tuv, gradient2d(fx * scale, fy * scale)).rgb;
                    float m = clamp(swordMask.sample(smp, tuv, gradient2d(fx * scale, fy * scale)).r, 0.0, 1.0);
                    cover *= clamp(area * 2.0, 0.0, 1.0);
                    // The sword's colours were scaled up on black: add them, and take the water away under them.
                    c = c * (1.0 - cover * m) + max(s, 0.0) * cover;
                }
            }
        }
        float3 shown = min(c, float3(2.0 * u.fadeIn, u.fadeIn, u.fadeIn));
        return float4(max(shown - float3(2.0 * u.fadeOut, u.fadeOut, u.fadeOut), 0.0), 1.0);
    }
    """
}
