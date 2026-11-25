import AppKit
import CoreText
import MetalKit
import simd

/// Shows `OpeningCreditsModel`.
///
/// - 1993 look: the original's 320 x 400 screen, worked out on the processor (`classicScreen`) and shown
///   through its palette: the released horizon and font.
/// - Modern look (chosen by the user, 2026-11-25): the same moments and places, gliding between steps. The
///   horizon is the original through Super-xBR, fading in smoothly and scrolling 1/9 pixel a step instead
///   of a pixel every 9; the text is Superclarendon (a macOS font) in white, its capitals as tall as the 1993
///   ones (14 of 400 lines) on the same lines, each line stretched sideways to the 1993 line's width (the
///   1993 letters were very wide); the Dolby Surround logo is a picture (the original pixels through
///   Super-xBR), not text.
final class OpeningCreditsScene: DemoScene {
    private(set) var model: OpeningCreditsModel
    private let canvas: IndexedCanvas
    private let picturePipeline: MTLRenderPipelineState
    private let overlayPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    /// The Modern look's horizon and logo, and its text pictures (one per title and page). All are made
    /// with the scene, not when first shown: each first shows on a music cue, the worst moment for a
    /// picture to be late. The horizon's and the logo's Super-xBR versions are made on a background thread.
    private let horizon: ScenePicture?
    private let logo: ScenePicture?
    private let texts: [OpeningCreditsModel.Text: MTLTexture]

    static let fontName = "Superclarendon-Regular"
    /// The text pictures: this many pixels per canvas pixel across, and per line down (a line is 0.6 as tall
    /// as a pixel is wide: 400 lines shown 4:3).
    static let across: CGFloat = 4
    static let down: CGFloat = across * 0.6
    /// The logo's lines (the third title's "[" from line 160 and "]" from 179, 29 rows each).
    static let logoLines = 160..<208

    /// Must match `OpeningQuad` in the shader.
    private struct Quad {
        var rect: SIMD4<Float>       // left, top, right, bottom, in canvas pixels
        var uv: SIMD4<Float>         // the texture's part: left, top, right, bottom (0...1)
        var canvas: SIMD2<Float>
        var amount: Float            // the picture's brightness, or the overlay's strength
        /// 1: a one-channel picture (the text), shown as grey.
        var grey: Float = 0
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        model = try OpeningCreditsModel.load()
        canvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat,
                                   width: OpeningCreditsModel.width, height: OpeningCreditsModel.height)
        let library = try Shaders.library(device: device, source: Self.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("opening_quad_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("opening_picture_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        picturePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = try Shaders.function("opening_overlay_fragment", in: library)
        let blend = descriptor.colorAttachments[0]!
        blend.isBlendingEnabled = true
        blend.sourceRGBBlendFactor = .one
        blend.destinationRGBBlendFactor = .oneMinusSourceAlpha
        blend.sourceAlphaBlendFactor = .one
        blend.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        overlayPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        sampler = try Shaders.sampler(device: device, smooth: true)

        horizon = try? ScenePicture.shared(named: "01-opening-horizon", device: device)
        logo = Self.logoPicture(model, device: device)
        horizon?.prepareUpscaledInBackground()
        logo?.prepareUpscaledInBackground()
        let loader = MTKTextureLoader(device: device)
        var texts: [OpeningCreditsModel.Text: MTLTexture] = [:]
        for text in Self.allTexts {
            guard let image = Self.textImage(text, font: model.font) else { continue }
            texts[text] = try? loader.newTexture(cgImage: image, options: ScenePicture.textLoadOptions)
        }
        self.texts = texts
    }

    /// How many of the Modern look's pictures are ready: the texts, the horizon, the logo (for checks).
    var modernPictures: (texts: Int, horizon: Bool, logo: Bool) { (texts.count, horizon != nil, logo != nil) }

    /// Every text the part shows: the three titles and the four pages.
    static let allTexts: [OpeningCreditsModel.Text] = OpeningCreditsModel.titles.indices.map { .title($0) }
        + OpeningCreditsModel.pages.indices.map { .page($0) }

    func reset() { model.reset() }
    func tick() { model.tick() }

    func demoUpdate(_ context: DemoContext) {
        if context.justShown { model.startInDemo(sync: context.music.sync) } else { model.demoSync(context.music.sync) }
    }

    // MARK: - 1993 look

    func classicReferenceFrame() -> [UInt8] {
        let (numbers, levels) = model.classicScreen()
        return numbers.flatMap { c in (0..<3).map { byteFromVGA(levels[Int(c) * 3 + $0]) } }
    }

    // MARK: - Drawing

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            let (numbers, levels) = model.classicScreen()
            let palette = (0..<256).map { (c: Int) -> SIMD4<Float> in
                let rgb = SIMD3<Float>(Float(levels[c * 3]), Float(levels[c * 3 + 1]), Float(levels[c * 3 + 2])) / 63
                return SIMD4<Float>(rgb, 1)
            }
            canvas.draw(into: encoder, indices: numbers, palette: palette)
            return
        }
        let layout = Self.modernLayout(model, alpha: frame.alpha)
        let size = SIMD2<Float>(Float(OpeningCreditsModel.width), Float(OpeningCreditsModel.height))
        encoder.setFragmentSamplerState(sampler, index: 0)
        if layout.brightness > 0, let horizon {
            // Picture rows 0...149 on lines 50...349, columns from the scroll position.
            var quad = Quad(rect: SIMD4(0, 50, 320, 350),
                            uv: SIMD4(layout.position / 640, 0, (layout.position + 320) / 640, 150 / 200),
                            canvas: size, amount: layout.brightness)
            encoder.setRenderPipelineState(picturePipeline)
            draw(horizon.upscaled, quad: &quad, encoder: encoder)
        }
        guard layout.text != .none, layout.textAmount > 0 else { return }
        encoder.setRenderPipelineState(overlayPipeline)
        if let text = texts[layout.text] {
            var quad = Quad(rect: SIMD4(0, 0, 320, 400), uv: SIMD4(0, 0, 1, 1), canvas: size, amount: layout.textAmount, grey: 1)
            draw(text, quad: &quad, encoder: encoder)
        }
        if layout.text == .title(2), let logo {
            let lines = Self.logoLines
            var quad = Quad(rect: SIMD4(0, Float(lines.lowerBound), 320, Float(lines.upperBound)), uv: SIMD4(0, 0, 1, 1),
                            canvas: size, amount: layout.textAmount)
            draw(logo.upscaled, quad: &quad, encoder: encoder)
        }
    }

    /// What the Modern look shows, `alpha` of the way to the next step: the scroll position (pixels, gliding
    /// 1/9 pixel a step), the horizon's brightness and the text's strength (0...1, fading smoothly).
    static func modernLayout(_ model: OpeningCreditsModel, alpha: Float) -> (position: Float, brightness: Float,
                                                                           text: OpeningCreditsModel.Text, textAmount: Float) {
        let now = model.shown(), next = model.shown(at: model.step + 1)
        var position: Float = 0, brightness: Float = 0
        if let start4 = model.sync4 {
            let t = Float(model.step - start4 - 1) + alpha
            position = min(max(t / Float(OpeningCreditsModel.scrollStep), 0), 320)
            brightness = min(max(t / 128, 0), 1)
        }
        // The text glides between this step's strength and the next one's (same text only).
        let amount = now.text == next.text ? now.textAmount + (next.textAmount - now.textAmount) * alpha : now.textAmount
        return (position, brightness, now.text, amount)
    }

    private func draw(_ texture: MTLTexture, quad: inout Quad, encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBytes(&quad, length: MemoryLayout<Quad>.stride, index: 0)
        encoder.setFragmentBytes(&quad, length: MemoryLayout<Quad>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // MARK: - The Modern look's pictures

    /// The Dolby Surround logo as the 1993 title showed it (greys 10, 30 and 63 of 63), through Super-xBR.
    private static func logoPicture(_ model: OpeningCreditsModel, device: MTLDevice) -> ScenePicture? {
        let lines = Self.logoLines, w = OpeningCreditsModel.width
        let bits = model.titleBits[2]
        var rgba = [UInt8](repeating: 0, count: w * lines.count * 4)
        for (row, line) in lines.enumerated() {
            for x in 0..<w {
                let s = Int(bits[line * w + x] >> 6)
                let level = byteFromVGA(model.titleColours[64 * s * 3])
                let i = (row * w + x) * 4
                rgba[i] = level; rgba[i + 1] = level; rgba[i + 2] = level; rgba[i + 3] = 255
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: lines.count, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, w, lines.count), mipmapLevel: 0, withBytes: rgba, bytesPerRow: w * 4)
        return ScenePicture(texture, device: device)
    }

    /// A title's or page's text in Superclarendon, white on black, over the whole 320 x 400 canvas (1280 x
    /// 960). Each line's capitals are 14 lines tall from the 1993 glyphs' top line, and the line is stretched
    /// sideways to cover exactly the 1993 line's ink (pages are shown 2 pixels right, as in 1993). The logo
    /// ("[" and "]") is left out: it is drawn as a picture.
    static func textImage(_ text: OpeningCreditsModel.Text, font: OpeningCreditsModel.Font) -> CGImage? {
        let lines: [(top: Int, text: String)], down0: Int, right: Int
        switch text {
        case .none: return nil
        case .title(let k): lines = OpeningCreditsModel.titles[k]; down0 = 0; right = 0
        case .page(let k): lines = OpeningCreditsModel.pages[k]; down0 = 100; right = 2
        }
        let width = Int(320 * across), height = Int(400 * down)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(true)
        let probe = CTFontCreateWithName(fontName as CFString, 100, nil)
        let capHeight = 14 * down
        let ctFont = CTFontCreateWithName(fontName as CFString, 100 * capHeight / CTFontGetCapHeight(probe), nil)
        for (top, line) in lines where line != "[" && line != "]" {
            let attributed = NSAttributedString(string: line, attributes: [.font: ctFont, .foregroundColor: CGColor(gray: 1, alpha: 1)])
            let ct = CTLineCreateWithAttributedString(attributed)
            context.textPosition = .zero            // (the bounds are measured from the current text position)
            let ink = CTLineGetImageBounds(ct, context)
            // The 1993 line's ink: from 160 - width / 2 (+ 2 on pages), width - 2 pixels wide.
            let left = CGFloat(160 - font.width(line) / 2 + right) * across
            let wanted = CGFloat(font.width(line) - 2) * across
            let baseline = CGFloat(down0 + top + 14) * down
            context.saveGState()
            context.translateBy(x: left, y: CGFloat(height) - baseline)
            context.scaleBy(x: wanted / ink.width, y: 1)
            context.textPosition = CGPoint(x: -ink.minX, y: 0)
            CTLineDraw(ct, context)
            context.restoreGState()
        }
        return context.makeImage()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct OpeningQuad {
        float4 rect;     // left, top, right, bottom in canvas pixels
        float4 uv;       // the texture's part
        float2 canvas;
        float amount;
        float grey;
    };

    struct QuadOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex QuadOut opening_quad_vertex(uint vid [[vertex_id]], constant OpeningQuad &u [[buffer(0)]]) {
        float2 corner = float2(vid & 1, vid >> 1);                    // (0,0) (1,0) (0,1) (1,1)
        float2 p = mix(u.rect.xy, u.rect.zw, corner);
        QuadOut out;
        out.position = float4(p.x / u.canvas.x * 2.0 - 1.0, 1.0 - p.y / u.canvas.y * 2.0, 0.0, 1.0);
        out.uv = mix(u.uv.xy, u.uv.zw, corner);
        return out;
    }

    // The horizon, at a brightness (its fade from black).
    fragment float4 opening_picture_fragment(QuadOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                             sampler smp [[sampler(0)]], constant OpeningQuad &u [[buffer(0)]]) {
        return float4(tex.sample(smp, in.uv).rgb * u.amount, 1.0);
    }

    // Text or logo (light on black) laid over what is there: its brightness is how much it covers.
    fragment float4 opening_overlay_fragment(QuadOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                             sampler smp [[sampler(0)]], constant OpeningQuad &u [[buffer(0)]]) {
        float4 t = tex.sample(smp, in.uv);
        float3 c = (u.grey > 0.5 ? float3(t.r) : t.rgb) * u.amount;
        return float4(c, max(c.r, max(c.g, c.b)));
    }
    """
}
