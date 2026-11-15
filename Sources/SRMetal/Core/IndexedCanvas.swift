import Foundation
import Metal
import simd

/// Shows a picture the way a VGA card did: every pixel is a small number, and a colour table
/// (the palette) says what colour each number means.
///
/// Scenes whose 1993 version is best re-created by running the original steps on the processor
/// (drawing into video memory, flipping pages) use this for their classic look: they hand over
/// the finished pixel numbers and the palette, and this puts them on screen.
final class IndexedCanvas {
    let width: Int
    let height: Int
    private let pipeline: MTLRenderPipelineState
    /// For `draw(...blendedWith:...)`: shows the even mix of two pictures.
    private let pairPipeline: MTLRenderPipelineState
    private var secondTextures: [MTLTexture] = []
    /// A few textures used in turn, so a new frame is never written into one still being displayed.
    private var textures: [MTLTexture] = []
    private var paletteBuffers: [MTLBuffer] = []
    private var next = 0

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, width: Int, height: Int) throws {
        self.width = width
        self.height = height

        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.fragmentSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("indexed_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = try Shaders.function("indexed_pair_fragment", in: library)
        pairPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Uint, width: width, height: height, mipmapped: false)
        for _ in 0..<3 {
            guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
                throw SceneError.textureFailed
            }
            textures.append(texture)
            guard let second = device.makeTexture(descriptor: textureDescriptor) else {
                throw SceneError.textureFailed
            }
            secondTextures.append(second)
            // Room for the largest palette a VGA card had: 256 colours.
            guard let buffer = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * 256,
                                                 options: .storageModeShared) else {
                throw SceneError.textureFailed
            }
            paletteBuffers.append(buffer)
        }
    }

    /// `indices`: one byte per pixel, row by row. `palette`: the colour for each index, 0...1 per channel.
    ///
    /// `second`, if given, is another picture of the same size: each pixel is then shown as the even
    /// mix of its colour in the two pictures. This is for originals that showed two slightly different
    /// pictures on alternate frames and left the eye to blend them.
    func draw(into encoder: MTLRenderCommandEncoder, indices: [UInt8], blendedWith second: [UInt8]? = nil,
              palette: [SIMD4<Float>]) {
        precondition(indices.count == width * height, "IndexedCanvas: wrong picture size")
        precondition(second == nil || second!.count == width * height, "IndexedCanvas: wrong second picture size")
        precondition(palette.count <= 256, "IndexedCanvas: a palette has at most 256 colours")
        let texture = textures[next]
        let secondTexture = secondTextures[next]
        let paletteBuffer = paletteBuffers[next]
        next = (next + 1) % textures.count
        indices.withUnsafeBytes { buffer in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: buffer.baseAddress!, bytesPerRow: width)
        }
        second?.withUnsafeBytes { buffer in
            secondTexture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                                  withBytes: buffer.baseAddress!, bytesPerRow: width)
        }

        // The buffers are used in turn and keep what an earlier frame put in them. So after this
        // frame's colours, blank the rest: a colour number beyond a short palette then shows black,
        // not whatever colour a longer palette left there three frames ago.
        palette.withUnsafeBytes { bytes in
            if let colours = bytes.baseAddress {
                paletteBuffer.contents().copyMemory(from: colours, byteCount: bytes.count)
            }
            if bytes.count < paletteBuffer.length {
                memset(paletteBuffer.contents() + bytes.count, 0, paletteBuffer.length - bytes.count)
            }
        }
        encoder.setRenderPipelineState(second == nil ? pipeline : pairPipeline)
        encoder.setFragmentBuffer(paletteBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        if second != nil { encoder.setFragmentTexture(secondTexture, index: 1) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    private static let fragmentSource = """
    fragment float4 indexed_fragment(CanvasOut in [[stage_in]],
                                     const device float4 *palette [[buffer(0)]],
                                     texture2d<uint> picture [[texture(0)]]) {
        uint2 size = uint2(picture.get_width(), picture.get_height());
        uint2 pixel = min(uint2(in.uv * float2(size)), size - 1);
        return float4(palette[picture.read(pixel).r].rgb, 1.0);
    }

    fragment float4 indexed_pair_fragment(CanvasOut in [[stage_in]],
                                          const device float4 *palette [[buffer(0)]],
                                          texture2d<uint> picture [[texture(0)]],
                                          texture2d<uint> second [[texture(1)]]) {
        uint2 size = uint2(picture.get_width(), picture.get_height());
        uint2 pixel = min(uint2(in.uv * float2(size)), size - 1);
        float3 mixed = (palette[picture.read(pixel).r].rgb + palette[second.read(pixel).r].rgb) * 0.5;
        return float4(mixed, 1.0);
    }
    """
}
