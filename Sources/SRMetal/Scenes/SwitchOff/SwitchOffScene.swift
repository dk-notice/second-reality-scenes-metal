import Foundation
import Metal

/// The screen "switching off" like an old TV (part 8, `PANIC/SHUTDOWN.C`, Wildfire), refresh by refresh.
///
/// The original played tricks with the VGA card's registers on the troll left on screen by the techno part:
/// showing every memory row twice, then skipping every other row, then copying ever fewer rows of the
/// troll into a band in the middle, while the palette washed out towards white (colour 0, the black, kept).
/// What it shows, refresh by refresh (s = refreshes since the part began):
///
/// - s = 0: the troll as the techno part left it.
/// - s = 1: the troll squashed to half height in the middle of a WHITE screen (colour 0 set to white),
///   palette 3/64 towards white.
/// - s = 2, 3: squashed to a quarter, black around, 20/64 towards white (the original waits twice here).
/// - s = 4...13: squashed into a band of 2a screen rows, a = 32, 26, 21, 17, 14, 11, 9, 7, 5, 4 (each
///   ×5/6), palette (63 − a)/64 towards white; troll row 400·b/a in band row b.
/// - s = 14: one line left across the middle (troll row 133), 60/64 towards white. (The last band, a = 3,
///   is made after this refresh's wait and cut to the line at once, so it never shows.)
/// - s = 15...61: the line is wiped from both ends inwards: 4 pixels a side blanked per refresh, moving in 3.
/// - s = 61...190: a single dot (colour 1) in the middle, which blinks twice (its brightness follows a
///   cosine over 60 refreshes), then a second (`sleep(1)`, 70 refreshes) with the dot almost dark.
struct SwitchOffModel {
    static let length = 191
    /// The band heights of the collapse.
    static let bands: [Int] = {
        var out: [Int] = []
        var a = 32
        while a > 2 { out.append(a); a = a * 5 / 6 }
        return out
    }()
    /// On its own: the troll is shown for a second first (in the demo it is already on screen).
    static let standaloneLeadIn = 70

    private(set) var step = 0
    /// Steps of lead-in still to show (none inside Play Demo).
    private(set) var leadIn = standaloneLeadIn

    mutating func reset() {
        step = 0
        leadIn = Self.standaloneLeadIn
    }

    mutating func tick() {
        if leadIn > 0 { leadIn -= 1; return }
        step += 1
        if step >= Self.length { reset() }
    }

    /// Inside Play Demo there is no lead-in.
    mutating func skipLeadIn() { if step == 0 { leadIn = 0 } }

    /// What one refresh shows.
    struct Frame: Equatable {
        /// For each of the 400 screen rows, the troll row shown there, or -1 for colour 0.
        var rows: [Int32]
        /// Palette washed this far towards white, in 64ths (`fadepals`); colour 0 is not washed.
        var whiteFade: Int
        /// Colour 0's level: 63 at s = 1 (white), otherwise 0.
        var colour0: Int
        /// Pixels of the line (screen rows 200 and 201) already wiped to colour 0: two ranges, x0...x1.
        var wiped: SIMD4<Int32>
        /// The dot's level (colour 1) at x = 160, rows 200 and 201; -1 for none.
        var dot: Int
        /// For the Modern look: the band the troll is squashed into (top row, height) and which part of
        /// the troll it shows (top, height, 0...1).
        var band: SIMD4<Float>
    }

    var frame: Frame { leadIn > 0 ? Self.frame(at: 0) : Self.frame(at: step) }

    static func frame(at s: Int) -> Frame {
        let none = SIMD4<Int32>(1, 0, 1, 0)   // empty ranges
        func rows(_ f: (Int) -> Int) -> [Int32] { (0..<400).map { Int32(f($0)) } }
        switch s {
        case 0:
            return Frame(rows: rows { $0 }, whiteFade: 0, colour0: 0, wiped: none, dot: -1, band: SIMD4(0, 400, 0, 1))
        case 1:
            // Memory row 100 + y/2 shown (rows doubled); the squashed troll is in memory rows 150...249.
            return Frame(rows: rows { y in let m = 100 + y / 2; return (150...249).contains(m) ? (m - 150) * 4 : -1 },
                         whiteFade: 3, colour0: 63, wiped: none, dot: -1, band: SIMD4(100, 200, 0, 1))
        case 2, 3:
            // Memory row 2·(y/2) shown. The original waits once more before the band loop, so refresh 3
            // still shows this.
            return Frame(rows: rows { y in let m = 2 * (y / 2); return (150...249).contains(m) ? (m - 150) * 4 : -1 },
                         whiteFade: 20, colour0: 0, wiped: none, dot: -1, band: SIMD4(150, 100, 0, 1))
        case 4..<(3 + bands.count):
            // Band a is made just after the refresh it shows in. The last band (a = 3) is made after
            // refresh 14's wait and cut to the line straight away, so it never shows.
            let a = bands[s - 4], top = 100 - a / 2
            return Frame(rows: rows { y in let b = y / 2 - top; return (0..<a).contains(b) ? 400 * b / a : -1 },
                         whiteFade: 63 - a, colour0: 0, wiped: none, dot: -1,
                         band: SIMD4(Float(2 * top), Float(2 * a), 0, 1))
        default:
            let line = rows { ($0 == 200 || $0 == 201) ? 133 : -1 }
            let wipes = min(max(s - 14, 0), 47)
            var wiped = none
            if wipes > 0 {
                let x = 20 + 3 * (wipes - 1)
                wiped = SIMD4(20, Int32(x + 3), Int32(317 - x), 300)
            }
            var dot = -1
            if s >= 61 {
                // Colour 1 is white in the troll's palette, so washed 60/64 towards white it is still 63.
                let a = min(s - 62, 59)
                dot = a < 0 ? 63 : Int(cos(Double(a) / 120 * 3 * 2 * 3.1415926535) * 31 + 32)
            }
            return Frame(rows: line, whiteFade: 60, colour0: 0, wiped: wiped, dot: dot,
                         band: SIMD4(200, 2, 133.0 / 400, 1.0 / 400))
        }
    }
}

/// Draws `SwitchOffModel`. 1993 look: exactly the original's rows, colours and pixels. Modern look: the
/// troll 8x by Super-xBR squashed smoothly into the same bands, the same colours, a soft dot.
final class SwitchOffScene: DemoScene {
    private(set) var model = SwitchOffModel()
    private let picture: ScenePicture
    private let pipeline: MTLRenderPipelineState
    private let smooth: MTLSamplerState
    private let nearest: MTLSamplerState

    /// Must match `SwitchOffUniforms` in the shader.
    private struct Uniforms {
        var wiped: SIMD4<Int32>
        var band: SIMD4<Float>
        var keep: Float
        var colour0: Float
        var dot: Float
        var classic: Float
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        picture = try ScenePicture.shared(named: "07-troll", device: device)
        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("switch_off_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        // Squashed up and down only: smooth vertically without blurring sideways.
        smooth = try Shaders.sampler(device: device, smooth: true, anisotropy: 16)
        nearest = try Shaders.sampler(device: device, smooth: false)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func demoUpdate(_ context: DemoContext) { model.skipLeadIn() }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        let shown = model.frame
        let classic = frame.look == .classic
        var uniforms = Uniforms(wiped: shown.wiped, band: shown.band, keep: Float(64 - shown.whiteFade),
                                colour0: Float(shown.colour0), dot: Float(shown.dot), classic: classic ? 1 : 0)
        var rows = shown.rows
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(classic ? picture.original : picture.upscaled, index: 0)
        encoder.setFragmentSamplerState(classic ? nearest : smooth, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&rows, length: rows.count * MemoryLayout<Int32>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// The 1993 picture worked out on the processor, by the same rules.
    func classicReferenceFrame() -> [UInt8] {
        guard let rgb = ScenePicture.pixels("07-troll") else { return [] }
        let shown = model.frame
        let fade = PictureFade.white(Float(shown.whiteFade))
        var out = [UInt8]()
        out.reserveCapacity(320 * 400 * 3)
        for y in 0..<400 {
            for x in 0..<320 {
                var levels = [shown.colour0, shown.colour0, shown.colour0]
                let row = Int(shown.rows[y])
                let onLine = y == 200 || y == 201
                let w = shown.wiped
                func within(_ from: Int32, _ to: Int32) -> Bool { Int(from) <= x && x <= Int(to) }
                let wiped = onLine && (within(w.x, w.y) || within(w.z, w.w))
                if onLine && x == 160 && shown.dot >= 0 {
                    levels = [shown.dot, shown.dot, shown.dot]
                } else if row >= 0 && !wiped {
                    let i = (row * 320 + x) * 3
                    let source = (0..<3).map { vgaFromByte(rgb[i + $0]) }
                    // Colour 0 (the only pure black in the troll's palette) is never washed out.
                    if source != [0, 0, 0] { levels = source.map { fade.classicLevel($0) } }
                }
                out += levels.map { byteFromVGA($0) }
            }
        }
        return out
    }

    private static let shaderSource = """
    struct SwitchOffUniforms {
        int4 wiped;      // wiped ranges of the line: x0, x1, x2, x3 (empty when x1 < x0)
        float4 band;     // Modern look: band top row, height; part of the troll: top, height (0...1)
        float keep;      // palette washed out: keep this many 64ths of each colour, the rest white
        float colour0;   // level of colour 0 (0 black, 63 white)
        float dot;       // the dot's level, or -1
        float classic;
    };

    fragment float4 switch_off_fragment(CanvasOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                        sampler smp [[sampler(0)]], constant SwitchOffUniforms &u [[buffer(0)]],
                                        constant int *rows [[buffer(1)]]) {
        float2 p = in.uv * float2(320.0, 400.0);     // canvas position
        // How fast the troll picture is crossed per screen pixel, worked out here (before any early
        // return) from the band, so the right smoothing is chosen even at the band's edges.
        float2 alongX = float2(dfdx(in.uv.x), 0.0);
        float2 alongY = float2(0.0, dfdy(p.y) / u.band.y * u.band.w);
        int x = int(p.x), y = int(p.y);
        bool onLine = (y == 200 || y == 201);
        bool wiped = onLine && ((x >= u.wiped.x && x <= u.wiped.y) || (x >= u.wiped.z && x <= u.wiped.w));
        float bg = u.colour0 / 63.0;
        if (u.classic > 0.5) {
            if (onLine && x == 160 && u.dot >= 0.0) return float4(float3(round(u.dot * 255.0 / 63.0) / 255.0), 1.0);
            int row = rows[clamp(y, 0, 399)];
            if (row < 0 || wiped) return float4(float3(round(u.colour0 * 255.0 / 63.0) / 255.0), 1.0);
            float3 c = tex.sample(smp, float2((float(x) + 0.5) / 320.0, (float(row) + 0.5) / 400.0)).rgb;
            float3 level = round(c * 63.0);
            if (all(level == 0.0)) return float4(float3(round(u.colour0 * 255.0 / 63.0) / 255.0), 1.0);
            float3 faded = floor((63.0 * (64.0 - u.keep) + level * u.keep) / 64.0);
            return float4(round(faded * 255.0 / 63.0) / 255.0, 1.0);
        }
        // Modern look: a soft round dot, and the troll squashed smoothly into the band.
        if (u.dot >= 0.0) {
            float d = length((p - float2(160.5, 201.0)) * float2(1.0, 0.6));
            float glow = 1.0 - smoothstep(0.6, 1.6, d);
            if (glow > 0.0) return float4(float3(u.dot / 63.0 * glow), 1.0);
        }
        float t = (p.y - u.band.x) / u.band.y;
        if (t < 0.0 || t >= 1.0 || wiped) return float4(float3(bg), 1.0);
        float3 c = tex.sample(smp, float2(in.uv.x, u.band.z + t * u.band.w), gradient2d(alongX, alongY)).rgb;
        // Black (colour 0) is not washed out: blend by how dark the pixel is, so smooth edges stay smooth.
        float notBlack = smoothstep(0.0, 0.05, max(c.r, max(c.g, c.b)));
        float3 washed = mix(float3(1.0), c, u.keep / 64.0);
        return float4(mix(float3(bg), washed, notBlack), 1.0);
    }
    """
}
