import AppKit
import CoreText
import MetalKit

/// Shows `EndScrollerModel`.
///
/// - 1993 look: the original's 640x400 screen of four greys, drawn in the released 25-row font.
/// - Modern look: the same lines at the same places, moving up smoothly instead of a row every second
///   refresh, drawn in SuperClarendon (a Clarendon-style typeface that comes with macOS; chosen by the user
///   2026-11-24 as the closest match): capitals as tall as the original's 14 rows, the original's 1.2:1
///   pixel shape kept, the font's own letter spacing, in the original's light grey. Each line is drawn once
///   into a picture of its own and moved as it scrolls.
final class EndScrollerScene: DemoScene {
    private(set) var model: EndScrollerModel
    private let device: MTLDevice
    private let canvas: IndexedCanvas
    private let linePipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let loader: MTKTextureLoader
    /// Pictures of the text lines on screen (Modern look), by line number.
    private var lineTextures: [Int: MTLTexture] = [:]

    static let fontName = "SuperClarendon-Regular"
    /// Each line's picture: this many pixels per original pixel across (and 1.2 times as many down).
    static let lineScale: CGFloat = 4
    /// Rows above and below the 25-row line that a picture also covers (accents and descenders).
    static let linePadding = 6

    /// Must match `EndScrollerLine` in the shader.
    private struct LineUniforms {
        var rect: SIMD4<Float>     // left, top, right, bottom, in canvas pixels
        var grey: Float
        var unused = SIMD3<Float>(0, 0, 0)
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        model = try EndScrollerModel.load()
        canvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat,
                                   width: EndScrollerModel.width, height: EndScrollerModel.height)
        loader = MTKTextureLoader(device: device)
        let library = try Shaders.library(device: device, source: Self.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("end_scroller_line_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("end_scroller_line_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        // Lines may overlap a little (accents, descenders): add them, on black.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        linePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.mipFilter = .linear
        s.sAddressMode = .clampToEdge
        s.tAddressMode = .clampToEdge
        guard let state = device.makeSamplerState(descriptor: s) else { throw RendererError.noSampler }
        sampler = state
    }

    func reset() {
        model.reset()
        lineTextures = [:]
    }

    func tick() { model.tick() }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            canvas.draw(into: encoder, indices: model.screen, palette: Self.palette)
            return
        }
        // Modern look. The screen's top row is the row drawn 400 rows before the newest; between rows
        // the text glides up, a whole row every 2 steps.
        let glide = (Float(model.stepsSinceRow) + frame.alpha) / Float(EndScrollerModel.stepsPerRow)
        let topRow = Float(model.rowsDrawn - EndScrollerModel.height) + glide
        var keep: Set<Int> = []
        encoder.setRenderPipelineState(linePipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)
        for placed in model.placed {
            let top = Float(placed.firstRow) - topRow
            guard top < Float(EndScrollerModel.height), top + Float(EndScrollerFont.rows) > 0 else { continue }
            keep.insert(placed.line)
            guard let texture = lineTexture(placed.line) else { continue }
            let pad = Float(Self.linePadding)
            var uniforms = LineUniforms(rect: SIMD4(0, top - pad, Float(EndScrollerModel.width), top + Float(EndScrollerFont.rows) + pad),
                                        grey: Float(EndScrollerModel.levels[3]) / 63)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LineUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LineUniforms>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        lineTextures = lineTextures.filter { keep.contains($0.key) }
    }

    /// One text line drawn in SuperClarendon, white on black, the whole 640-pixel width (made once).
    private func lineTexture(_ index: Int) -> MTLTexture? {
        if let made = lineTextures[index] { return made }
        guard let image = Self.lineImage(model.lines[index]),
              let texture = try? loader.newTexture(cgImage: image, options: [
                .SRGB: false, .generateMipmaps: true, .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue]) else { return nil }
        lineTextures[index] = texture
        return texture
    }

    static func lineImage(_ line: [UInt8]) -> CGImage? {
        let scale = lineScale, tall = lineScale * 1.2
        let width = Int(CGFloat(EndScrollerModel.width) * scale)
        let height = Int(CGFloat(EndScrollerFont.rows + 2 * linePadding) * tall)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // The text as the DOS character set had it (0x84 is "ä"), without its carriage return.
        let text = String(String.UnicodeScalarView(line.filter { $0 != 13 }.compactMap { UnicodeScalar(dosCharacter($0)) }))
        guard !text.isEmpty else { return context.makeImage() }
        let probe = CTFontCreateWithName(fontName as CFString, 100, nil)
        let font = CTFontCreateWithName(fontName as CFString, 100 * 14 / CTFontGetCapHeight(probe) * scale, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: CGColor(gray: 1, alpha: 1), .ligature: 0])
        let ct = CTLineCreateWithAttributedString(attributed)
        let textWidth = CTLineGetTypographicBounds(ct, nil, nil, nil)
        context.setShouldAntialias(true)
        context.translateBy(x: CGFloat(width) / 2 - textWidth / 2,
                            y: CGFloat(height) - CGFloat(linePadding + 14) * tall)   // baseline on row 14
        context.scaleBy(x: 1, y: tall / scale)                                         // the 1993 pixel shape
        context.textPosition = .zero
        CTLineDraw(ct, context)
        return context.makeImage()
    }

    /// The few non-ASCII bytes the text uses, from the DOS character set.
    static func dosCharacter(_ byte: UInt8) -> UInt32 {
        switch byte {
        case 0x84: return 0xE4   // ä
        case 0x94: return 0xF6   // ö
        case 0x8F: return 0xC5   // Å
        default: return byte < 0x80 ? UInt32(byte) : 0x3F
        }
    }

    static let palette: [SIMD4<Float>] = (0..<256).map { index in
        let level = Float(EndScrollerModel.levels[min(index, 3)])
        let byte = Float(byteFromVGA(Int(level)))
        return SIMD4(byte / 255, byte / 255, byte / 255, 1)
    }

    func classicReferenceFrame() -> [UInt8] {
        model.screen.flatMap { shade -> [UInt8] in
            let byte = byteFromVGA(EndScrollerModel.levels[min(Int(shade), 3)])
            return [byte, byte, byte]
        }
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct EndScrollerLine {
        float4 rect;     // left, top, right, bottom in canvas pixels (640 x 400)
        float grey;
        float3 unused;
    };

    struct LineOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex LineOut end_scroller_line_vertex(uint vid [[vertex_id]], constant EndScrollerLine &u [[buffer(0)]]) {
        float2 corner = float2(vid & 1, vid >> 1);                    // (0,0) (1,0) (0,1) (1,1)
        float2 canvas = mix(u.rect.xy, u.rect.zw, corner);
        LineOut out;
        out.position = float4(canvas.x / 320.0 - 1.0, 1.0 - canvas.y / 200.0, 0.0, 1.0);
        out.uv = corner;
        return out;
    }

    fragment float4 end_scroller_line_fragment(LineOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                               sampler smp [[sampler(0)]], constant EndScrollerLine &u [[buffer(0)]]) {
        return float4(float3(tex.sample(smp, in.uv).r * u.grey), 1.0);
    }
    """
}
