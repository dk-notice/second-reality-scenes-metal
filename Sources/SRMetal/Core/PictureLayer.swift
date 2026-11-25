import Foundation
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

    /// Makes the Modern look's version now, so that showing it later costs nothing.
    func prepareUpscaled() { _ = upscaled }

    /// Makes the Modern look's version on a background thread (for a picture shown soon).
    func prepareUpscaledInBackground() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in prepareUpscaled() }
    }

    /// Lets go of the Modern look's version (it is made again if needed).
    func dropUpscaled() {
        lock.lock()
        upscaledCopy = nil
        lock.unlock()
    }

    var isUpscaled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return upscaledCopy != nil
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

/// How far a picture has faded towards white or black, by the 1993 rule: each colour level c (0...63)
/// became (target * a + (64 - a) * c) / 64, a = 0 (none) to 63 (the PAM explosion's `pal` table;
/// fades elsewhere in the demo work the same way).
struct PictureFade {
    var amount: Float            // a: 0...63; may be fractional in the Modern look (smooth fades)
    var towardWhite: Bool

    static let none = PictureFade(amount: 0, towardWhite: true)
    static func white(_ amount: Float) -> PictureFade { PictureFade(amount: amount, towardWhite: true) }
    static func black(_ amount: Float) -> PictureFade { PictureFade(amount: amount, towardWhite: false) }

    /// The 1993 result for one colour level, worked out on the processor (for checks and references).
    func classicLevel(_ level: Int) -> Int {
        let a = Int(amount.rounded(.down)), target = towardWhite ? 63 : 0
        return (target * a + (64 - a) * level) / 64
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
        var amount: Float
        var target: Float
        var classic: Float
        var unused: Float = 0
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.source)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("picture_layer_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        func sampler(_ filter: MTLSamplerMinMagFilter) throws -> MTLSamplerState {
            let d = MTLSamplerDescriptor()
            d.minFilter = filter
            d.magFilter = filter
            d.mipFilter = filter == .linear ? .linear : .notMipmapped
            d.sAddressMode = .clampToEdge
            d.tAddressMode = .clampToEdge
            guard let state = device.makeSamplerState(descriptor: d) else { throw RendererError.noSampler }
            return state
        }
        smooth = try sampler(.linear)
        nearest = try sampler(.nearest)
    }

    func draw(_ picture: ScenePicture, into encoder: MTLRenderCommandEncoder, look: Look, fade: PictureFade = .none) {
        let classic = look == .classic
        var uniforms = Uniforms(amount: classic ? fade.amount.rounded(.down) : fade.amount,
                                target: fade.towardWhite ? 63 : 0, classic: classic ? 1 : 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(classic ? picture.original : picture.upscaled, index: 0)
        encoder.setFragmentSamplerState(classic ? nearest : smooth, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    static let source = """
    struct PictureFadeUniforms {
        float amount;    // 0...63
        float target;    // 63 (white) or 0 (black), in 1993 colour levels
        float classic;   // 1: whole 1993 levels and the original's rounding; 0: smooth
        float unused;
    };

    fragment float4 picture_layer_fragment(CanvasOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                           sampler smp [[sampler(0)]], constant PictureFadeUniforms &u [[buffer(0)]]) {
        float3 c = tex.sample(smp, in.uv).rgb;
        if (u.classic > 0.5) {
            // Back to the 1993 level (0...63), faded with whole numbers as the original did, and shown
            // as the VGA card showed that level.
            float3 level = round(c * 63.0);
            float3 faded = floor((u.target * u.amount + (64.0 - u.amount) * level) / 64.0);
            return float4(round(faded * 255.0 / 63.0) / 255.0, 1.0);
        }
        float3 target = float3(u.target / 63.0);
        return float4(mix(c, target, u.amount / 64.0), 1.0);
    }
    """
}
