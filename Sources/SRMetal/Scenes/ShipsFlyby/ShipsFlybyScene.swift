import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

/// Draws the Ships Fly-by: the original's ships (3D models and recorded animation, through the
/// shared VISU engine in `Core/Visu/`) passing over the horizon picture from the demo's opening.
///
///  - Classic look: the processor copies the background picture into a 320x200 screen of colour
///    numbers and the engine's 1993 replay draws the ships over it (`ShipsFlybyModel`); the
///    graphics chip only looks the colours up (`IndexedCanvas`).
///  - Modern look: the background picture scaled up smoothly, then the ships as real triangles at
///    full resolution (`VisuModernRenderer`), gliding between animation frames.
///
/// THIS SCENE USES ORIGINAL ARTWORK AND DATA: the background picture and the ship models and
/// animation are Future Crew's files (see docs/scenes/ships-flyby.md and Data/Visu/README.md).
final class ShipsFlybyScene: DemoScene {
    /// A higher-resolution picture to use as the MODERN look's background instead of the scaled-up
    /// original, if a file of this name is in the data folder (`Data/Visu/`, which `./build.sh`
    /// copies into the app). It must show the WHOLE 320x200 screen (so 4:3 on a monitor, black
    /// bars included); any pixel size will do. The 1993 look never uses it.
    static let modernBackgroundFile = "U2ABG-modern.png"

    let model: ShipsFlybyModel
    private let indexedCanvas: IndexedCanvas
    private let renderer: VisuModernRenderer
    private let backgroundPipeline: MTLRenderPipelineState
    private let backgroundTexture: MTLTexture
    private let backgroundSampler: MTLSamplerState
    /// The scene's 256 colours as the graphics chip wants them (0...1).
    private let palette: [SIMD4<Float>]

    /// Must match `ShipsBackground` in the shader source below.
    private struct BackgroundUniforms {
        /// Top and bottom of the picture's band (0...1 down the canvas), half a picture row, unused.
        var band: SIMD4<Float>
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        model = try ShipsFlybyModel()
        indexedCanvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat,
                                          width: ShipsFlybyModel.width, height: ShipsFlybyModel.height)
        renderer = try VisuModernRenderer(device: device, pixelFormat: pixelFormat)
        palette = VisuPlayback.colours(model.palette)

        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("ships_background_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        backgroundPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        backgroundTexture = try Self.replacementBackground(device: device)
            ?? Self.originalBackground(model: model, device: device)

        // "Linear" blends neighbouring picture pixels, so the scaled-up picture is smooth.
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { throw SceneError.textureFailed }
        backgroundSampler = sampler
    }

    /// The original 320x200 picture with its own colours, as a picture the graphics chip can scale.
    private static func originalBackground(model: ShipsFlybyModel, device: MTLDevice) throws -> MTLTexture {
        let width = ShipsFlybyModel.width, height = ShipsFlybyModel.height
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for pixel in model.background {
            for k in 0..<3 { bytes.append(byteFromVGA(Int(model.palette[Int(pixel) * 3 + k]))) }
            bytes.append(255)
        }
        return try texture(device: device, width: width, height: height, rgba: bytes, smaller: false)
    }

    /// The optional replacement picture (see `modernBackgroundFile`), or nil if there is none.
    private static func replacementBackground(device: MTLDevice) throws -> MTLTexture? {
        guard let url = VisuData.folder?.appendingPathComponent(modernBackgroundFile),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0, image.width <= 8192, image.height <= 8192
        else { return nil }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // A big picture shown small needs ready-made smaller copies of itself to stay smooth.
        return try texture(device: device, width: width, height: height, rgba: bytes, smaller: true)
    }

    private static func texture(device: MTLDevice, width: Int, height: Int, rgba: [UInt8], smaller: Bool) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: smaller)
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw SceneError.textureFailed }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: rgba, bytesPerRow: width * 4)
        if smaller, texture.mipmapLevelCount > 1,
           let commands = device.makeCommandQueue()?.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
        }
        return texture
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func classicReferenceFrame() -> [UInt8] { model.classicReferenceFrame() }

    /// The modern look's ships are drawn into the engine's own off-screen picture first, because
    /// they need a depth buffer and smoothed edges that the app's main drawing pass does not have.
    func prepare(commands: MTLCommandBuffer, frame: FrameInfo) {
        guard frame.look == .modern else { return }
        renderer.render(model.pose(alpha: frame.alpha), view: model.engine.view, palette: palette,
                        targetSize: frame.targetSize, commands: commands)
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if frame.look == .classic {
            indexedCanvas.draw(into: encoder, indices: model.screen, palette: palette)
            return
        }

        // 1. The background picture. Only rows 25...174 of the screen hold picture; the rest is black.
        let window = model.engine.view.window
        let top = window.y / Float(ShipsFlybyModel.height), bottom = window.w / Float(ShipsFlybyModel.height)
        var uniforms = BackgroundUniforms(band: SIMD4(top, bottom, 0.5 / Float(backgroundTexture.height), 0))
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BackgroundUniforms>.stride, index: 0)
        encoder.setFragmentTexture(backgroundTexture, index: 0)
        encoder.setFragmentSamplerState(backgroundSampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        // 2. The ships, laid over it.
        renderer.composite(into: encoder)
    }

    private static let shaderSource = """
    struct ShipsBackground {
        float4 band;   // top and bottom of the picture's band (0...1 down the canvas), half a picture row
    };

    // The background picture, scaled smoothly. Outside the band the screen is black, and the
    // band's top and bottom edges are kept sharp (the smooth scaling must not blend picture
    // with the black bar next to it).
    fragment float4 ships_background_fragment(CanvasOut in [[stage_in]],
                                              constant ShipsBackground &u [[buffer(0)]],
                                              texture2d<float> picture [[texture(0)]],
                                              sampler smp [[sampler(0)]]) {
        if (in.uv.y < u.band.x || in.uv.y >= u.band.y) return float4(0.0, 0.0, 0.0, 1.0);
        float v = clamp(in.uv.y, u.band.x + u.band.z, u.band.y - u.band.z);
        return float4(picture.sample(smp, float2(in.uv.x, v)).rgb, 1.0);
    }
    """
}
