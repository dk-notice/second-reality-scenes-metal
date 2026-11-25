import Foundation
import ImageIO
import MetalKit

/// A picture from the 1993 demo, ready for both looks: the original pixels (1993 look) and the same made
/// `PictureScaler.modernScale` times larger by Super-xBR (Modern look, made on first use, or ahead of
/// time on a background thread with `prepareUpscaledInBackground`). Safe to use from several threads.
final class ScenePicture: @unchecked Sendable {
    let original: MTLTexture
    private let device: MTLDevice
    private let lock = NSLock()
    private var upscaledCopy: MTLTexture?

    init(_ original: MTLTexture, device: MTLDevice) {
        self.original = original
        self.device = device
    }

    /// One of the exported pictures by name (as in `artwork/original/rgb`, without ".png"), e.g. "04-title",
    /// or a path below that folder, e.g. "explosion/frame-01".
    convenience init(named name: String, device: MTLDevice) throws {
        guard let url = DemoPictures.url(name) else { throw PictureError.missing(name) }
        let texture = try MTKTextureLoader(device: device).newTexture(URL: url, options: Self.loadOptions)
        self.init(texture, device: device)
    }

    static let loadOptions: [MTKTextureLoader.Option: Any] = [
        .SRGB: false,                       // the bytes as they are, like every scene's colours
        .textureUsage: MTLTextureUsage.shaderRead.rawValue,
        .textureStorageMode: MTLStorageMode.private.rawValue,
        .generateMipmaps: false
    ]

    var size: SIMD2<Float> { SIMD2(Float(original.width), Float(original.height)) }

    /// The Modern look's version (made now if it is not made yet; a few milliseconds).
    var upscaled: MTLTexture {
        lock.lock()
        defer { lock.unlock() }
        if let made = upscaledCopy { return made }
        let made = (try? PictureScaler.upscaled(original, device: device)) ?? original
        upscaledCopy = made
        return made
    }

    /// Makes the Modern look's version on a background thread (for a picture shown soon).
    func prepareUpscaledInBackground() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in _ = upscaled }
    }

    /// Lets go of the Modern look's version (it is made again if needed).
    func dropUpscaled() {
        lock.lock()
        upscaledCopy = nil
        lock.unlock()
    }

    /// A picture's red, green, blue bytes (for 1993-look references worked out on the processor), row by row, read from its file.
    static func pixels(_ name: String) -> [UInt8]? {
        guard let url = DemoPictures.url(name), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,   // no conversion
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var rgb = [UInt8]()
        rgb.reserveCapacity(width * height * 3)
        for i in 0..<(width * height) { rgb += [rgba[4 * i], rgba[4 * i + 1], rgba[4 * i + 2]] }
        return rgb
    }
}

enum PictureError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let name): return "Picture \(name) not found (looked in the app's Resources/Artwork and artwork/original/rgb)"
        }
    }
}

/// How far a picture has faded towards white or black, by the 1993 rule the demo's parts used: each
/// colour level c (0...63) became (target · (outOf − keep) + c · keep) / outOf in whole numbers, keeping
/// `keep` parts in `outOf` of the picture's colour. The explosion faded in 64ths (`PAM/OUTTAA.C`), the
/// title and end pictures faded in from white in 128ths and the end picture out to black in 64ths
/// (`BEG/BEG.C`, `END/END.C`).
struct PictureFade {
    var towardWhite: Bool
    var keep: Float              // may be fractional in the Modern look (smooth fades)
    var outOf: Float
    /// Added to every colour level afterwards, at most 63 (the troll's landing flash: `palfade` in
    /// TECHNO/KOE.C adds 45, 42, ... 0).
    var add: Float = 0

    static let none = PictureFade(towardWhite: true, keep: 1, outOf: 1)
    /// `amount` (0...63) of the way towards white in 64ths, as the explosion's table gives it.
    static func white(_ amount: Float) -> PictureFade { PictureFade(towardWhite: true, keep: 64 - amount, outOf: 64) }
    /// Keeping `keep` of `outOf` parts of the picture, the rest white.
    static func fromWhite(keep: Float, outOf: Float) -> PictureFade { PictureFade(towardWhite: true, keep: keep, outOf: outOf) }
    /// Keeping `keep` of `outOf` parts of the picture, the rest black.
    static func toBlack(keep: Float, outOf: Float) -> PictureFade { PictureFade(towardWhite: false, keep: keep, outOf: outOf) }

    /// Brightened by `add` levels (0...63), as the troll's flash did.
    static func brighten(_ add: Float) -> PictureFade { PictureFade(towardWhite: true, keep: 1, outOf: 1, add: add) }

    /// The 1993 result for one colour level, worked out on the processor (for checks and references).
    func classicLevel(_ level: Int) -> Int {
        let k = Int(keep.rounded(.down)), n = Int(outOf), target = towardWhite ? 63 : 0
        return min((target * (n - k) + level * k) / n + Int(add.rounded(.down)), 63)
    }
}

/// Draws a `ScenePicture` over the whole canvas, with a fade: in the 1993 look exactly by the original's
/// rule, as hard-edged pixels; in the Modern look the Super-xBR version, smoothly, the fade laid on top.
final class PictureLayer {
    private let pipeline: MTLRenderPipelineState
    private let smooth: MTLSamplerState
    private let nearest: MTLSamplerState

    /// Must match `PictureFadeUniforms` below.
    private struct Uniforms {
        var keep: Float
        var outOf: Float
        var target: Float
        var classic: Float
        var add: Float
        var offsetX: Float
        var unused = SIMD2<Float>(0, 0)
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.source)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("picture_layer_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        smooth = try Shaders.sampler(device: device, smooth: true)
        nearest = try Shaders.sampler(device: device, smooth: false)
    }

    /// `offsetX`: how far the picture is moved left, in canvas pixels (the troll scrolling in); what
    /// lies beyond the picture's edges is black (colour level 0), and is faded like the picture.
    func draw(_ picture: ScenePicture, into encoder: MTLRenderCommandEncoder, look: Look, fade: PictureFade = .none,
              offsetX: Float = 0) {
        let classic = look == .classic
        var uniforms = Uniforms(keep: classic ? fade.keep.rounded(.down) : fade.keep, outOf: fade.outOf,
                                target: fade.towardWhite ? 63 : 0, classic: classic ? 1 : 0,
                                add: classic ? fade.add.rounded(.down) : fade.add,
                                offsetX: offsetX / picture.size.x)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(classic ? picture.original : picture.upscaled, index: 0)
        encoder.setFragmentSamplerState(classic ? nearest : smooth, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    static let source = """
    struct PictureFadeUniforms {
        float keep;      // parts of the picture's colour kept ...
        float outOf;     // ... out of this many; the rest is the target
        float target;    // 63 (white) or 0 (black), in 1993 colour levels
        float classic;   // 1: whole 1993 levels and the original's rounding; 0: smooth
        float add;       // levels added afterwards (at most 63)
        float offsetX;   // the picture moved left by this much of its width
        float2 unused;
    };

    fragment float4 picture_layer_fragment(CanvasOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                           sampler smp [[sampler(0)]], constant PictureFadeUniforms &u [[buffer(0)]]) {
        float2 uv = float2(in.uv.x + u.offsetX, in.uv.y);
        float3 c = (uv.x < 0.0 || uv.x >= 1.0) ? float3(0.0) : tex.sample(smp, uv).rgb;
        if (u.classic > 0.5) {
            // Back to the 1993 level (0...63), faded with whole numbers as the original did, and shown
            // as the VGA card showed that level.
            float3 level = round(c * 63.0);
            float3 faded = min(floor((u.target * (u.outOf - u.keep) + level * u.keep) / u.outOf) + u.add, 63.0);
            return float4(round(faded * 255.0 / 63.0) / 255.0, 1.0);
        }
        float3 target = float3(u.target / 63.0);
        return float4(min(mix(target, c, u.keep / u.outOf) + u.add / 63.0, 1.0), 1.0);
    }
    """
}
