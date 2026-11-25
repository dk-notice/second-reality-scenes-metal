import AppKit
import CoreText
import MetalKit
import simd

/// Shows `CreditsModel`.
///
/// - 1993 look: the original's screen, worked out on the processor (`CreditsModel.classicScreen`) and
///   shown through its palette: the released pictures and the original font, of which only every other
///   row reached the screen.
/// - Modern look (chosen by the user, 2026-11-25): the same layout and motion, gliding between steps and
///   without the 1993 scroll's one-refresh slip. The pictures are this project's own scenes captured in
///   their Modern look (`CreditsModel.captures`, made by `build.sh`); the text is DIN Condensed Bold (a
///   macOS font), white, its capitals as tall as the 1993 letters (15 rows) and centred the same way.
final class CreditsScene: DemoScene {
    private(set) var model: CreditsModel
    private let device: MTLDevice
    private let canvas: IndexedCanvas
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let loader: MTKTextureLoader
    /// The palette of the screen showing (1993 look), worked out once per screen.
    private var paletteScreen = -1
    private var screenPalette: [SIMD4<Float>] = []
    /// The Modern look's picture and text of the screen showing.
    private var modernScreen = -1
    private var modernPicture: MTLTexture?
    private var modernText: MTLTexture?
    /// Pictures made the plain way (the released picture through Super-xBR) are kept here.
    private var upscaled: [Int: ScenePicture] = [:]

    static let fontName = "DINCondensed-Bold"
    /// The text's picture: this many pixels per canvas pixel across (the 320 x 200-line text area).
    static let textScale: CGFloat = 4

    /// Must match `CreditsQuad` in the shader.
    private struct Quad {
        var rect: SIMD4<Float>       // left, top, right, bottom, in canvas pixels
        var clip: SIMD2<Float>       // only canvas lines from .x to .y are drawn
        var canvas: SIMD2<Float>
        /// x: 1 for a one-channel picture (the text), shown as grey.
        var options = SIMD4<Float>(0, 0, 0, 0)
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        model = try CreditsModel.load()
        canvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat,
                                   width: CreditsModel.width, height: CreditsModel.height)
        loader = MTKTextureLoader(device: device)
        let library = try Shaders.library(device: device, source: Self.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("credits_quad_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("credits_quad_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        sampler = try Shaders.sampler(device: device, smooth: true)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }

    // MARK: - 1993 look

    private func palette() -> [SIMD4<Float>] {
        if paletteScreen != model.screen {
            paletteScreen = model.screen
            let levels = model.palette(screen: model.screen)
            screenPalette = (0..<256).map { (c: Int) -> SIMD4<Float> in
                let rgb = SIMD3<Float>(Float(levels[c * 3]), Float(levels[c * 3 + 1]), Float(levels[c * 3 + 2])) / 63
                return SIMD4<Float>(rgb, 1)
            }
        }
        return screenPalette
    }

    func classicReferenceFrame() -> [UInt8] {
        let levels = model.palette(screen: model.screen)
        return model.classicScreen().flatMap { c in (0..<3).map { byteFromVGA(Int(levels[Int(c) * 3 + $0])) } }
    }

    // MARK: - Drawing

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            canvas.draw(into: encoder, indices: model.classicScreen(), palette: palette())
            return
        }
        // Modern. A screen's first step is black (the original cleared the screen and waited).
        let local = model.local
        guard local > 0 else { return }
        prepareModern()
        // Glide towards the next step's places: the text's top and the picture's window (the fine
        // scroll's value; the 1993 look's slower start address is left out).
        let layout = Self.modernLayout(local: local, alpha: frame.alpha)
        let size = SIMD2<Float>(Float(CreditsModel.width), Float(CreditsModel.height))

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)
        // The picture: display rows 200...299 of memory at x 400...559, seen through a window starting
        // yy pixels in; on screen above the split line only.
        if let picture = modernPicture {
            var quad = Quad(rect: layout.picture, clip: SIMD2(0, layout.textTop), canvas: size)
            draw(picture, quad: &quad, encoder: encoder)
        }
        // The text: memory from row 0, shown from the line after the split.
        if let text = modernText {
            var quad = Quad(rect: SIMD4(0, layout.textTop, 320, layout.textTop + 200), clip: SIMD2(layout.textTop, size.y), canvas: size,
                            options: SIMD4(1, 0, 0, 0))
            draw(text, quad: &quad, encoder: encoder)
        }
    }

    /// Where the Modern look draws on a screen's step (1...361), `alpha` of the way to the next: the picture
    /// (left, top, right, bottom in canvas pixels: memory x 400...559 seen through a window starting at
    /// the fine scroll's yy, 200 lines tall), shown above `textTop`; the text area from `textTop` (the
    /// line after the split) down. The 1993 look's slower start address is left out.
    static func modernLayout(local: Int, alpha: Float) -> (picture: SIMD4<Float>, textTop: Float) {
        let now = CreditsModel.registers(local: local)
        let next = local + 1 < CreditsModel.stepsPerScreen ? CreditsModel.registers(local: local + 1) : now
        let split = Float(now.split) + Float(next.split - now.split) * alpha
        let yy = Float(now.pan) + Float(next.pan - now.pan) * alpha
        return (SIMD4(400 - yy, 0, 560 - yy, 200), split + 1)
    }

    private func draw(_ texture: MTLTexture, quad: inout Quad, encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBytes(&quad, length: MemoryLayout<Quad>.stride, index: 0)
        encoder.setFragmentBytes(&quad, length: MemoryLayout<Quad>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// The Modern picture and text of the screen showing, made when it first shows.
    private func prepareModern() {
        let k = model.screen
        guard modernScreen != k else { return }
        modernScreen = k
        modernPicture = Self.capture(k).flatMap {
            try? loader.newTexture(URL: $0, options: ScenePicture.textLoadOptions)
        } ?? plainPicture(k)
        modernText = Self.textImage(CreditsModel.texts[k]).flatMap {
            try? loader.newTexture(cgImage: $0, options: ScenePicture.textLoadOptions)
        }
    }

    /// The captured picture's file, if `build.sh` made it (`Resources/Credits/Modern`).
    static func capture(_ index: Int) -> URL? {
        guard CreditsModel.captures[index] != nil,
              let url = CreditsData.folder?.appendingPathComponent("Modern").appendingPathComponent(CreditsModel.captureName(index)),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The released picture through Super-xBR (any capture not made).
    private func plainPicture(_ index: Int) -> MTLTexture? {
        if let made = upscaled[index] { return made.upscaled }
        guard let picture = try? ScenePicture(named: CreditsModel.pictureNames[index], device: device) else { return nil }
        upscaled[index] = picture
        return picture.upscaled
    }

    /// A screen's text in DIN Condensed Bold, white on black: the 320 x 200-line area below the split,
    /// 4 pixels a canvas pixel across and 2.4 down (a line is 0.6 as tall as a pixel is wide). Line i's
    /// capitals go from line 16 + 42 i of the area (display row 8 + 21 i), 30 lines (15 rows) tall.
    static func textImage(_ lines: [String]) -> CGImage? {
        let scale = textScale, down = textScale * 0.6
        let width = Int(320 * scale), height = Int(200 * down)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(true)
        let probe = CTFontCreateWithName(fontName as CFString, 100, nil)
        let capHeight = 30 * down
        let font = CTFontCreateWithName(fontName as CFString, 100 * capHeight / CTFontGetCapHeight(probe), nil)
        for (i, line) in lines.enumerated() where !line.isEmpty {
            let attributed = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: CGColor(gray: 1, alpha: 1)])
            let ct = CTLineCreateWithAttributedString(attributed)
            let textWidth = CTLineGetTypographicBounds(ct, nil, nil, nil)
            let baseline = CGFloat(16 + 42 * i) * down + capHeight       // from the top
            context.textPosition = CGPoint(x: CGFloat(width) / 2 - textWidth / 2, y: CGFloat(height) - baseline)
            CTLineDraw(ct, context)
        }
        return context.makeImage()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct CreditsQuad {
        float4 rect;     // left, top, right, bottom in canvas pixels
        float2 clip;     // canvas lines drawn: from .x up to .y
        float2 canvas;
        float4 options;  // x: 1 for a one-channel picture, shown as grey
    };

    struct QuadOut {
        float4 position [[position]];
        float2 uv;
        float line;
    };

    vertex QuadOut credits_quad_vertex(uint vid [[vertex_id]], constant CreditsQuad &u [[buffer(0)]]) {
        float2 corner = float2(vid & 1, vid >> 1);                    // (0,0) (1,0) (0,1) (1,1)
        float2 p = mix(u.rect.xy, u.rect.zw, corner);
        QuadOut out;
        out.position = float4(p.x / u.canvas.x * 2.0 - 1.0, 1.0 - p.y / u.canvas.y * 2.0, 0.0, 1.0);
        out.uv = corner;
        out.line = p.y;
        return out;
    }

    fragment float4 credits_quad_fragment(QuadOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                          sampler smp [[sampler(0)]], constant CreditsQuad &u [[buffer(0)]]) {
        if (in.line < u.clip.x || in.line >= u.clip.y) discard_fragment();
        float4 c = tex.sample(smp, in.uv);
        return float4(u.options.x > 0.5 ? float3(c.r) : c.rgb, 1.0);
    }
    """
}
