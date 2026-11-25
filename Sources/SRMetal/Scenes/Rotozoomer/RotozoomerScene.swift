import Metal

/// Draws `RotozoomerModel`. 1993 look: the original's 160x100 screen worked out exactly as `_rotate` did
/// it (whole-number camera, the turned tile, the 16-bit carry), coloured through the faded palette.
/// Modern look: every screen pixel works out its own point on the picture from the unrounded camera,
/// gliding between steps, and samples the lens picture made 8x by Super-xBR; the fades glide too.
///
/// THIS SCENE USES ORIGINAL ARTWORK (`artwork/original/rgb/10-lens-picture.png`).
final class RotozoomerScene: DemoScene {
    static let pictureName = "10-lens-picture"
    private(set) var model = RotozoomerModel()
    private let canvas: IndexedCanvas
    private let picture: ScenePicture
    private let pipeline: MTLRenderPipelineState
    private let smooth: MTLSamplerState
    /// The picture's distinct colours (VGA levels); `tile` and `turnedTile` hold numbers into this list.
    private let colours: [SIMD3<Int>]
    private let tile: [UInt8]
    private let turnedTile: [UInt8]
    private var screenCache: (step: Int, screen: [UInt8])?

    /// Must match `RotozoomerUniforms` in the shader.
    private struct Uniforms {
        var camera: SIMD4<Float>     // x, y, xa, ya
        var keep: Float
        var outOf: Float
        var add: Float
        var unused: Float = 0
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        canvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat, width: 160, height: 100)
        picture = try ScenePicture.shared(named: Self.pictureName, device: device)
        guard let indexed = ScenePicture.colourNumbers(Self.pictureName), indexed.numbers.count == 320 * 200 else {
            throw PictureError.missing(Self.pictureName)
        }
        colours = indexed.colours
        let back = indexed.numbers
        tile = RotozoomerModel.tile(fromPicture: back)
        turnedTile = RotozoomerModel.turned(tile)

        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("rotozoomer_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        smooth = try Shaders.sampler(device: device, smooth: true, anisotropy: 16)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func demoUpdate(_ context: DemoContext) { model.musicPlus = context.music.plus }

    /// The 1993 screen (colour numbers) for the current step.
    var classicScreen: [UInt8] {
        let s = min(model.step, RotozoomerModel.pathSteps - 1)
        if let cache = screenCache, cache.step == s { return cache.screen }
        let screen = RotozoomerModel.rotate(RotozoomerModel.path[s], tile: tile, turnedTile: turnedTile)
        screenCache = (s, screen)
        return screen
    }

    private func classicLevels() -> [SIMD3<Int>] {
        let fade = model.fade()
        return colours.map { SIMD3(fade.classicLevel($0.x), fade.classicLevel($0.y), fade.classicLevel($0.z)) }
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            let palette = classicLevels().map { SIMD4<Float>(SIMD3<Float>($0) / 63, 1) }
            canvas.draw(into: encoder, indices: classicScreen, palette: palette)
            return
        }
        let fade = model.fade(alpha: frame.alpha, smooth: true)
        var uniforms = Uniforms(camera: SIMD4<Float>(model.exactCamera(alpha: frame.alpha)),
                                keep: fade.keep, outOf: fade.outOf, add: fade.add)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(picture.upscaled, index: 0)
        encoder.setFragmentSamplerState(smooth, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    func classicReferenceFrame() -> [UInt8] {
        let levels = classicLevels()
        var out = [UInt8]()
        out.reserveCapacity(160 * 100 * 3)
        for n in classicScreen {
            let c = levels[Int(n)]
            out += [byteFromVGA(c.x), byteFromVGA(c.y), byteFromVGA(c.z)]
        }
        return out
    }

    private static let shaderSource = """
    struct RotozoomerUniforms {
        float4 camera;   // x, y (tile pixels), xa, ya (1/1024 tile pixel per screen pixel), unrounded
        float keep;      // fade: keep this much of the picture's colour ...
        float outOf;     // ... out of this; the rest white
        float add;       // levels added afterwards (the flash in)
        float unused;
    };

    fragment float4 rotozoomer_fragment(CanvasOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                        sampler smp [[sampler(0)]], constant RotozoomerUniforms &u [[buffer(0)]]) {
        // Screen column i, row j of the original's 160x100 (centres at whole numbers).
        float2 p = in.uv * float2(160.0, 100.0) - 0.5;
        float xadd = u.camera.z / 1024.0, yadd = u.camera.w / 1024.0;
        const float shape = 307.0 / 256.0;      // rows step 307/256 as far as columns (the pixel shape)
        float tu = u.camera.x + (p.y + 1.0) * xadd * shape + (p.x + 1.0) * yadd;
        float tv = u.camera.y + (p.y + 1.0) * yadd * shape - (p.x + 1.0) * xadd;
        // How fast the picture is crossed per screen pixel, from the unbroken coordinates (the wrap-around
        // below would make the graphics chip's own estimate jump at the tile's edges).
        float2 scaleToPicture = float2(1.0 / 320.0, 10.0 / 11.0 / 200.0);
        float2 gx = float2(dfdx(tu), dfdx(tv)) * scaleToPicture;
        float2 gy = float2(dfdy(tu), dfdy(tv)) * scaleToPicture;
        // The tile repeats every 256; tile column x is picture column 32 + x, tile row y picture row
        // y·10/11 − 18, and rows outside the picture show its row 0.
        float x = tu - 256.0 * floor(tu / 256.0);
        float y = tv - 256.0 * floor(tv / 256.0);
        float row = y * 10.0 / 11.0 - 18.0;
        if (row < 0.0 || row >= 200.0) row = 0.5;
        float3 c = tex.sample(smp, float2((32.0 + x) / 320.0, row / 200.0), gradient2d(gx, gy)).rgb;
        return float4(min(mix(float3(1.0), c, u.keep / u.outOf) + u.add / 63.0, 1.0), 1.0);
    }
    """
}
