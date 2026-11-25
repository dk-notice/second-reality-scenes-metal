import Foundation
import Metal

/// Scales a small original picture (e.g. 320x200) up for the Modern look, on the graphics chip.
/// Four ways were compared (2026-11-24, `--scaler-compare`); the user chose Super-xBR, which the app
/// now uses for every picture (`upscaled(_:device:)`): made once, 8x (chosen over 4x the same day for
/// crisper outlines in fullscreen), then stretched smoothly.
///
/// - `smooth`: ordinary bilinear stretching (each screen pixel mixes the four nearest picture pixels).
/// - `sharp`: hard-edged blocks, with only the block edges softened ("sharp bilinear"), so the blocks
///   stay even at any size.
/// - `xbrLv2`: Hyllian's xBR level 2: finds edges between pixels and redraws them as smooth lines and
///   curves, at any size in one pass.
/// - `superXBR`: Hyllian's Super-xBR: three passes that each double the size, filtering along the edge
///   directions it finds; run twice (4x) or three times (8x), then stretched smoothly to the screen.
///
/// The xBR shaders are written for Metal from Hyllian's published shaders (libretro "slang-shaders",
/// `edge-smoothing/xbr/shaders/xbr-lv2-standalone.slang` and `super-xbr/super-xbr-pass0..2.slang`,
/// MIT licence, copyright 2011-2022 Hyllian; see ThirdParty/xBR-LICENSE.txt), with the settings of their default presets.
final class PictureScaler {
    enum Method: String, CaseIterable {
        case smooth, sharp, xbrLv2 = "xbr-lv2", superXBR = "super-xbr", superXBR8 = "super-xbr-8"

        /// The four compared first (2026-11-24); 8x was compared with 4x afterwards.
        static let firstComparison: [Method] = [.smooth, .sharp, .xbrLv2, .superXBR]

        var title: String {
            switch self {
            case .smooth: return "Smooth stretch (bilinear)"
            case .sharp: return "Sharp pixels"
            case .xbrLv2: return "xBR level 2"
            case .superXBR: return "Super-xBR (4x, then smooth)"
            case .superXBR8: return "Super-xBR (8x, then smooth)"
            }
        }
    }

    /// How much larger `upscaled` makes a picture: 8x, three Super-xBR rounds.
    static let modernScale = 8

    /// The Modern look's pictures: `picture` (8-bit, at its original size) made `modernScale` times larger
    /// by Super-xBR, once, with smaller copies for showing it small. Draw it with a smooth (linear,
    /// mipmapped) sampler. Safe to call from any thread; waits for the graphics chip.
    static func upscaled(_ picture: MTLTexture, device: MTLDevice) throws -> MTLTexture {
        let scaler = try shared(device)
        guard let commands = scaler.queue.makeCommandBuffer() else {
            throw RendererError.noCommandQueue
        }
        var result = picture
        let rounds = modernScale.trailingZeroBitCount   // each round doubles: 8x is 3 rounds
        for round in 0..<rounds { result = scaler.superXBRRound(result, commands: commands, last: round == rounds - 1) }
        if result.mipmapLevelCount > 1, let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: result)
            blit.endEncoding()
        }
        commands.commit()
        commands.waitUntilCompleted()
        return result
    }

    /// One scaler per graphics device: compiling its shaders takes a moment.
    private static let lock = NSLock()
    private static var scalers: [UInt64: PictureScaler] = [:]
    private static func shared(_ device: MTLDevice) throws -> PictureScaler {
        lock.lock()
        defer { lock.unlock() }
        if let scaler = scalers[device.registryID] { return scaler }
        let scaler = try PictureScaler(device: device)
        scalers[device.registryID] = scaler
        return scaler
    }

    private let device: MTLDevice
    /// For `upscaled` (a command queue can be used from any thread).
    private let queue: MTLCommandQueue
    private let pipelines: [String: MTLRenderPipelineState]
    private let linear: MTLSamplerState

    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw RendererError.noCommandQueue }
        self.queue = queue
        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.source)
        let vertex = try Shaders.function("canvas_vertex", in: library)
        var made: [String: MTLRenderPipelineState] = [:]
        for (name, format) in [("scale_smooth", MTLPixelFormat.bgra8Unorm), ("scale_sharp", .bgra8Unorm),
                               ("scale_xbr_lv2", .bgra8Unorm), ("sxbr_pass0", .rgba16Float),
                               ("sxbr_pass1", .rgba16Float), ("sxbr_pass2", .rgba16Float)] {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = try Shaders.function(name, in: library)
            descriptor.colorAttachments[0].pixelFormat = format
            made[name] = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        pipelines = made
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        sampler.sAddressMode = .clampToEdge
        sampler.tAddressMode = .clampToEdge
        guard let state = device.makeSamplerState(descriptor: sampler) else { throw RendererError.noSampler }
        linear = state
    }

    /// What the final pass needs: which part of the source to show (in 0...1 of its width and height),
    /// the source's size in pixels, and how many source pixels one output pixel spans (for xBR's blending).
    private struct Uniforms {
        var region: SIMD4<Float>     // x, y, width, height
        var sourceSize: SIMD2<Float>
        var outputSize: SIMD2<Float>
    }

    /// Draws `source` (an 8-bit picture at its original size) scaled by `method` into `target`
    /// (bgra8Unorm, any size), showing `region` of it (default: all of it).
    func draw(_ source: MTLTexture, method: Method, into target: MTLTexture, commands: MTLCommandBuffer,
              region: SIMD4<Float> = SIMD4(0, 0, 1, 1)) {
        var input = source
        var name: String
        switch method {
        case .smooth: name = "scale_smooth"
        case .sharp: name = "scale_sharp"
        case .xbrLv2: name = "scale_xbr_lv2"
        case .superXBR, .superXBR8:
            // Rounds of the three passes, each doubling: 4x is two rounds, 8x three.
            for _ in 0..<(method == .superXBR ? 2 : 3) { input = superXBRRound(input, commands: commands) }
            name = "scale_smooth"
        }
        var uniforms = Uniforms(region: region, sourceSize: SIMD2(Float(input.width), Float(input.height)),
                                outputSize: SIMD2(Float(target.width), Float(target.height)))
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: Renderer.clearPass(into: target)),
              let pipeline = pipelines[name] else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        encoder.setFragmentSamplerState(linear, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// One Super-xBR round: the picture at twice the size. `last`: the result gets room for smaller copies.
    private func superXBRRound(_ input: MTLTexture, commands: MTLCommandBuffer, last: Bool = false) -> MTLTexture {
        let w = input.width, h = input.height
        let corners = makeTexture(w, h), doubled = makeTexture(2 * w, 2 * h)
        let refined = makeTexture(2 * w, 2 * h, mipmapped: last)
        pass("sxbr_pass0", inputs: [input], into: corners, commands: commands)
        pass("sxbr_pass1", inputs: [input, corners], into: doubled, commands: commands)
        pass("sxbr_pass2", inputs: [doubled], into: refined, commands: commands)
        return refined
    }

    private func makeTexture(_ width: Int, _ height: Int, mipmapped: Bool = false) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width,
                                                                  height: height, mipmapped: mipmapped)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)!
    }

    private func pass(_ name: String, inputs: [MTLTexture], into target: MTLTexture, commands: MTLCommandBuffer) {
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: Renderer.clearPass(into: target)),
              let pipeline = pipelines[name] else { return }
        encoder.setRenderPipelineState(pipeline)
        for (index, texture) in inputs.enumerated() { encoder.setFragmentTexture(texture, index: index) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // MARK: - Shaders

    static let source = """
    struct ScaleUniforms {
        float4 region;
        float2 sourceSize;
        float2 outputSize;
    };

    // Where in the source (0...1) this output pixel shows.
    static float2 sourceUV(float2 uv, constant ScaleUniforms &u) { return u.region.xy + uv * u.region.zw; }

    fragment float4 scale_smooth(CanvasOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                 sampler smp [[sampler(0)]], constant ScaleUniforms &u [[buffer(0)]]) {
        return float4(tex.sample(smp, sourceUV(in.uv, u)).rgb, 1.0);
    }

    // Hard-edged blocks, softened only across one output pixel at each block edge.
    fragment float4 scale_sharp(CanvasOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                sampler smp [[sampler(0)]], constant ScaleUniforms &u [[buffer(0)]]) {
        // Measured from pixel centres: between two centres, hold the nearer pixel and blend only in
        // the output pixel or so where the two blocks meet.
        float2 texel = sourceUV(in.uv, u) * u.sourceSize - 0.5;
        float2 scale = u.outputSize / (u.region.zw * u.sourceSize);   // output pixels per source pixel
        float2 base = floor(texel);
        float2 f = clamp((fract(texel) - 0.5) * scale + 0.5, 0.0, 1.0);
        return float4(tex.sample(smp, (base + f + 0.5) / u.sourceSize).rgb, 1.0);
    }

    // ---- xBR level 2 (Hyllian), corner C, blending on. ----
    constant float XBR_EQ_THRESHOLD = 0.32;
    constant float lv2_cf = 0.30 + 2.0;
    constant float4 Ao = float4( 1.0, -1.0, -1.0, 1.0 );
    constant float4 Bo = float4( 1.0,  1.0, -1.0,-1.0 );
    constant float4 Co = float4( 1.5,  0.5, -0.5, 0.5 );
    constant float4 Ax = float4( 1.0, -1.0, -1.0, 1.0 );
    constant float4 Bx = float4( 0.5,  2.0, -0.5,-2.0 );
    constant float4 Cx = float4( 1.0,  1.0, -0.5, 0.0 );
    constant float4 Ay = float4( 1.0, -1.0, -1.0, 1.0 );
    constant float4 By = float4( 2.0,  0.5, -2.0,-0.5 );
    constant float4 Cy = float4( 2.0,  0.0, -1.0, 0.5 );
    constant float4 Ci = float4(0.25, 0.25, 0.25, 0.25);
    constant float3 v2f = float3(65536, 256, 1);
    constant float3 Yx = float3(0.2627, 0.6780, 0.0593);

    static float4 LTE(float4 a, float4 b) { return step(a, b); }
    static float4 LT(float4 a, float4 b) { return float4(a < b); }
    static float4 NOT(float4 a) { return 1.0 - a; }
    static float4 diffv(float4 a, float4 b) { return float4(a != b); }
    static float distc(float3 a, float3 b) { return dot(abs(a - b), Yx); }
    static float4 dist4(float4x3 a, float4x3 b) { return float4(distc(a[0], b[0]), distc(a[1], b[1]), distc(a[2], b[2]), distc(a[3], b[3])); }
    static float4 eq4(float4x3 a, float4x3 b) { return step(dist4(a, b), float4(XBR_EQ_THRESHOLD)); }
    static float4 neq4(float4x3 a, float4x3 b) { return 1.0 - eq4(a, b); }
    static float4 wdist(float4x3 a, float4x3 b, float4x3 c, float4x3 d, float4x3 e, float4x3 f, float4x3 g, float4x3 h) {
        return dist4(a,b) + dist4(a,c) + dist4(d,e) + dist4(d,f) + 4.0 * dist4(g,h);
    }
    static float4 code(float4x3 m) { return float4(dot(v2f, m[0]), dot(v2f, m[1]), dot(v2f, m[2]), dot(v2f, m[3])); }
    static float3 px(texture2d<float> t, int2 p) {
        p = clamp(p, int2(0), int2(t.get_width() - 1, t.get_height() - 1));
        return t.read(uint2(p)).rgb;
    }

    fragment float4 scale_xbr_lv2(CanvasOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                  constant ScaleUniforms &u [[buffer(0)]]) {
        float2 texel = sourceUV(in.uv, u) * u.sourceSize;
        int2 p = int2(floor(texel));
        float2 fp = fract(texel);
        float aa_factor = 2.0 * u.region.z * u.sourceSize.x / u.outputSize.x;

        float3 A1 = px(tex, p + int2(-1,-2)), B1 = px(tex, p + int2(0,-2)), C1 = px(tex, p + int2(1,-2));
        float3 A  = px(tex, p + int2(-1,-1)), B  = px(tex, p + int2(0,-1)), C  = px(tex, p + int2(1,-1));
        float3 D  = px(tex, p + int2(-1, 0)), E  = px(tex, p),             F  = px(tex, p + int2(1, 0));
        float3 G  = px(tex, p + int2(-1, 1)), H  = px(tex, p + int2(0, 1)), I  = px(tex, p + int2(1, 1));
        float3 G5 = px(tex, p + int2(-1, 2)), H5 = px(tex, p + int2(0, 2)), I5 = px(tex, p + int2(1, 2));
        float3 A0 = px(tex, p + int2(-2,-1)), D0 = px(tex, p + int2(-2, 0)), G0 = px(tex, p + int2(-2, 1));
        float3 C4 = px(tex, p + int2( 2,-1)), F4 = px(tex, p + int2( 2, 0)), I4 = px(tex, p + int2( 2, 1));

        float4x3 b = float4x3(B, D, H, F), c = float4x3(C, A, G, I), d = float4x3(D, H, F, B);
        float4x3 e = float4x3(E, E, E, E), f = float4x3(F, B, D, H), g = float4x3(G, I, C, A);
        float4x3 h = float4x3(H, F, B, D), i = float4x3(I, C, A, G);
        float4x3 i4 = float4x3(I4, C1, A0, G5), i5 = float4x3(I5, C4, A1, G0);
        float4x3 h5 = float4x3(H5, F4, B1, D0), f4 = float4x3(F4, B1, D0, H5);

        float4 b_ = code(b), c_ = code(c), e_ = code(e);
        float4 d_ = b_.yzwx, f_ = b_.wxyz, g_ = c_.zwxy, h_ = b_.zwxy;

        float4 fx   = Ao * fp.y + Bo * fp.x;
        float4 fx_l = Ax * fp.y + Bx * fp.x;
        float4 fx_u = Ay * fp.y + By * fp.x;

        float4 irlv0 = diffv(e_, f_) * diffv(e_, h_);
        float4 irlv1 = saturate(irlv0 * (neq4(f,b) * neq4(f,c) + neq4(h,d) * neq4(h,g)
                       + eq4(e,i) * (neq4(f,f4) * neq4(f,i4) + neq4(h,h5) * neq4(h,i5)) + eq4(e,g) + eq4(e,c)));
        float4 irlv2l = diffv(e_, g_) * diffv(d_, g_);
        float4 irlv2u = diffv(e_, c_) * diffv(b_, c_);

        float4 delta  = float4(aa_factor);
        float4 deltaL = float4(0.5, 1.0, 0.5, 1.0) * aa_factor;
        float4 deltaU = deltaL.yxwz;
        float4 fx45i = saturate(0.5 + (fx   - Co - Ci) / delta);
        float4 fx45  = saturate(0.5 + (fx   - Co     ) / delta);
        float4 fx30  = saturate(0.5 + (fx_l - Cx     ) / deltaL);
        float4 fx60  = saturate(0.5 + (fx_u - Cy     ) / deltaU);

        float4 wd1 = wdist(e, c, g, i, h5, f4, h, f);
        float4 wd2 = wdist(h, d, i5, f, i4, b, e, i);
        float4 d_fg = dist4(f, g);
        float4 d_hc = dist4(h, c);

        float4 edri  = LTE(wd1, wd2) * irlv0;
        float4 edr   = LT(wd1, wd2) * irlv1 * NOT(edri.yzwx * edri.wxyz);
        float4 edr_l = LTE(lv2_cf * d_fg, d_hc) * irlv2l * edr * (NOT(edri.yzwx) * eq4(e, c));
        float4 edr_u = LTE(lv2_cf * d_hc, d_fg) * irlv2u * edr * (NOT(edri.wxyz) * eq4(e, g));

        fx45i = edri * fx45i;
        fx45  = edr * fx45;
        fx30  = edr_l * fx30;
        fx60  = edr_u * fx60;

        float4 pxs = LTE(dist4(e, f), dist4(e, h));
        float4 maximos = max(max(fx30, fx60), max(fx45, fx45i));

        float3 res1 = mix(E, mix(H, F, pxs.x), maximos.x);
        float3 res2 = mix(E, mix(B, D, pxs.z), maximos.z);
        float3 res1a = mix(res1, res2, step(distc(E, res1), distc(E, res2)));
        res1 = mix(E, mix(F, B, pxs.y), maximos.y);
        res2 = mix(E, mix(D, H, pxs.w), maximos.w);
        float3 res1b = mix(res1, res2, step(distc(E, res1), distc(E, res2)));
        float3 res = mix(res1a, res1b, step(distc(E, res1a), distc(E, res1b)));
        return float4(res, 1.0);
    }

    // ---- Super-xBR (Hyllian), mode "Normal/Details", edge strength 3. ----
    // Pictures are read by whole pixels; each pass's sample positions are those of the original
    // passes, written as pixel offsets.
    constant float3 Ys = float3(0.2126, 0.7152, 0.0722);
    static float df(float a, float b) { return abs(a - b); }
    static float d_wd(float wp1, float wp2, float wp3, float wp4, float wp5, float wp6,
                      float b0, float b1, float c0, float c1, float c2, float d0, float d1, float d2, float d3,
                      float e1, float e2, float e3, float f2, float f3) {
        return wp1*(df(c1,c2) + df(c1,c0) + df(e2,e1) + df(e2,e3)) + wp2*(df(d2,d3) + df(d0,d1))
             + wp3*(df(d1,d3) + df(d0,d2)) + wp4*df(d1,d2) + wp5*(df(c0,c2) + df(e1,e3)) + wp6*(df(b0,b1) + df(f2,f3));
    }
    static float hv_wd(float wp1, float wp3, float wp4,
                       float i1, float i2, float i3, float i4, float e1, float e2, float e3, float e4) {
        return wp4*(df(i1,i2) + df(i3,i4)) + wp1*(df(i1,e1) + df(i2,e2) + df(i3,e3) + df(i4,e4))
             + wp3*(df(i1,e2) + df(i3,e4) + df(e1,i2) + df(e3,i4));
    }

    // The 16 samples, named as in the original (see its diagram), and the shared filter.
    struct SX { float3 P0, P1, P2, P3, B, C, D, E, F, G, H, I, F4, I4, H5, I5; };
    static float3 sxbr(SX s, float wp1, float wp2, float wp3, float wp4, float wp5, float wp6,
                       float weight1, float weight2, float strength) {
        float p0 = dot(s.P0, Ys), p1 = dot(s.P1, Ys), p2 = dot(s.P2, Ys), p3 = dot(s.P3, Ys);
        float b = dot(s.B, Ys), c = dot(s.C, Ys), d = dot(s.D, Ys), e = dot(s.E, Ys);
        float f = dot(s.F, Ys), g = dot(s.G, Ys), h = dot(s.H, Ys), i = dot(s.I, Ys);
        float f4 = dot(s.F4, Ys), i4 = dot(s.I4, Ys), h5 = dot(s.H5, Ys), i5 = dot(s.I5, Ys);
        float d_edge = d_wd(wp1, wp2, wp3, wp4, wp5, wp6, d, b, g, e, c, p2, h, f, p1, h5, i, f4, i5, i4)
                     - d_wd(wp1, wp2, wp3, wp4, wp5, wp6, c, f4, b, f, i4, p0, e, i, p3, d, h, i5, g, h5);
        float hv_edge = hv_wd(wp1, wp3, wp4, f, i, e, h, c, i5, b, h5) - hv_wd(wp1, wp3, wp4, e, f, h, i, d, f4, g, i4);
        float edge_strength = smoothstep(0.0, strength + 0.000001, abs(d_edge));
        float4 w1 = float4(-weight1, weight1 + 0.5, weight1 + 0.5, -weight1);
        float4 w2 = float4(-weight2, weight2 + 0.25, weight2 + 0.25, -weight2);
        float3 c3 = w2.x*(s.D + s.G) + w2.y*(s.E + s.H) + w2.z*(s.F + s.I) + w2.w*(s.F4 + s.I4);
        float3 c4 = w2.x*(s.C + s.B) + w2.y*(s.F + s.E) + w2.z*(s.I + s.H) + w2.w*(s.I5 + s.H5);
        float3 c1 = w1.x*s.P2 + w1.y*s.H + w1.z*s.F + w1.w*s.P1;
        float3 c2 = w1.x*s.P0 + w1.y*s.E + w1.z*s.I + w1.w*s.P3;
        float3 color = mix(mix(c1, c2, step(0.0, d_edge)), mix(c3, c4, step(0.0, hv_edge)), 1.0 - edge_strength);
        float3 lo = min(min(s.E, s.F), min(s.H, s.I)), hi = max(max(s.E, s.F), max(s.H, s.I));
        return clamp(color, lo, hi);
    }
    constant float W1 = 1.29633 / 10.0;          // the filter weights at full strength
    constant float W2 = 1.75068 / 10.0 / 2.0;

    // Pass 0, at the source's size: the new pixel at the corner between four source pixels.
    fragment float4 sxbr_pass0(CanvasOut in [[stage_in]], texture2d<float> src [[texture(0)]]) {
        int2 p = int2(in.position.xy);
        SX s;
        s.P0 = px(src, p + int2(-1,-1)); s.P1 = px(src, p + int2(2,-1)); s.P2 = px(src, p + int2(-1,2)); s.P3 = px(src, p + int2(2,2));
        s.B  = px(src, p + int2(0,-1));  s.C  = px(src, p + int2(1,-1)); s.H5 = px(src, p + int2(0,2));  s.I5 = px(src, p + int2(1,2));
        s.D  = px(src, p + int2(-1,0));  s.F4 = px(src, p + int2(2,0));  s.G  = px(src, p + int2(-1,1)); s.I4 = px(src, p + int2(2,1));
        s.E  = px(src, p);               s.F  = px(src, p + int2(1,0));  s.H  = px(src, p + int2(0,1));  s.I  = px(src, p + int2(1,1));
        return float4(sxbr(s, 2.0, 1.0, -1.0, 4.0, -1.0, 1.0, 0.0, 0.0, 3.0), 1.0);
    }

    // The doubled picture as pass 1 sees it, at a position whose x + y is even: original pixels at
    // (even, even), pass 0's corner pixels at (odd, odd).
    static float3 known(texture2d<float> src, texture2d<float> corners, int2 q) {
        int2 limit = int2(src.get_width(), src.get_height()) * 2 - 1;
        q = clamp(q, int2(0), limit);
        if ((q.x & 1) == 0 && (q.y & 1) == 0) return px(src, q / 2);
        if ((q.x & 1) == 1 && (q.y & 1) == 1) return px(corners, (q - 1) / 2);
        return px(src, q / 2);   // only at the picture's edge, after clamping
    }

    // Pass 1, at twice the size: the two remaining new pixels of each 2x2 block, from a grid turned 45 degrees.
    fragment float4 sxbr_pass1(CanvasOut in [[stage_in]], texture2d<float> src [[texture(0)]],
                               texture2d<float> corners [[texture(1)]]) {
        int2 q = int2(in.position.xy);
        if (((q.x + q.y) & 1) == 0) return float4(known(src, corners, q), 1.0);
        int2 g1 = (q.x & 1) ? int2(1, 0) : int2(0, 1);
        int2 g2 = (q.x & 1) ? int2(0, 1) : int2(1, 0);
        SX s;
        s.P0 = known(src, corners, q - 3*g1);      s.P1 = known(src, corners, q - 3*g2);
        s.P2 = known(src, corners, q + 3*g2);      s.P3 = known(src, corners, q + 3*g1);
        s.B  = known(src, corners, q - 2*g1 - g2); s.C  = known(src, corners, q - g1 - 2*g2);
        s.D  = known(src, corners, q - 2*g1 + g2); s.E  = known(src, corners, q - g1);
        s.F  = known(src, corners, q - g2);        s.G  = known(src, corners, q - g1 + 2*g2);
        s.H  = known(src, corners, q + g2);        s.I  = known(src, corners, q + g1);
        s.F4 = known(src, corners, q + g1 - 2*g2); s.I4 = known(src, corners, q + 2*g1 - g2);
        s.H5 = known(src, corners, q + g1 + 2*g2); s.I5 = known(src, corners, q + 2*g1 + g2);
        return float4(sxbr(s, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, W1, W2, 3.0), 1.0);
    }

    // Pass 2, at twice the size: every pixel refined once more (and the half-pixel shift undone).
    fragment float4 sxbr_pass2(CanvasOut in [[stage_in]], texture2d<float> src [[texture(0)]]) {
        int2 p = int2(in.position.xy);
        SX s;
        s.P0 = px(src, p + int2(-2,-2)); s.P1 = px(src, p + int2(1,-2)); s.P2 = px(src, p + int2(-2,1)); s.P3 = px(src, p + int2(1,1));
        s.B  = px(src, p + int2(-1,-2)); s.C  = px(src, p + int2(0,-2)); s.H5 = px(src, p + int2(-1,1)); s.I5 = px(src, p + int2(0,1));
        s.D  = px(src, p + int2(-2,-1)); s.F4 = px(src, p + int2(1,-1)); s.G  = px(src, p + int2(-2,0)); s.I4 = px(src, p + int2(1,0));
        s.E  = px(src, p + int2(-1,-1)); s.F  = px(src, p + int2(0,-1)); s.H  = px(src, p + int2(-1,0)); s.I  = px(src, p);
        return float4(sxbr(s, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, W1, W2, 3.0), 1.0);
    }
    """
}
