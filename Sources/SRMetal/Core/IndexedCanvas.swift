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
    /// A few textures used in turn, so a new frame is never written into one still being displayed.
    private var textures: [MTLTexture] = []
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

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Uint, width: width, height: height, mipmapped: false)
        for _ in 0..<3 {
            guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
                throw SceneError.textureFailed
            }
            textures.append(texture)
        }
    }

    /// `indices`: one byte per pixel, row by row. `palette`: the colour for each index, 0...1 per channel.
    func draw(into encoder: MTLRenderCommandEncoder, indices: [UInt8], palette: [SIMD4<Float>]) {
        precondition(indices.count == width * height, "IndexedCanvas: wrong picture size")
        let texture = textures[next]
        next = (next + 1) % textures.count
        indices.withUnsafeBytes { buffer in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: buffer.baseAddress!, bytesPerRow: width)
        }

        var colours = palette
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&colours, length: MemoryLayout<SIMD4<Float>>.stride * colours.count, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
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
    """
}
