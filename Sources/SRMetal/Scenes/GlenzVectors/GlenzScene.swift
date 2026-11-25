import Foundation
import Metal
import simd

/// Draws Glenz Vectors.
///
///  - Classic look: the processor replays the original's filler into a model of the 256-colour
///    screen and of the video card's colour table (see `GlenzModel`, `GlenzFiller`); the graphics
///    chip only looks the colours up.
///  - Modern look: the same faces as real triangles with smooth edges, at full resolution, gliding
///    between steps, mixed by real blending arranged to follow the original's colour rule:
///      * the red glenz's faces ADD their tints (the palette's reds were made to add up);
///      * the "4" bit, which two different kinds of face toggle, is kept as an on/off value in the
///        picture's spare fourth channel with an XOR-style blend, then turned into its tint;
///      * a front face of the blue-and-white glenz shows its own lit colour plus a QUARTER of
///        whatever is behind it, which is exactly what its 16 palette entries held.
final class GlenzScene: DemoScene {
    private(set) var model = GlenzModel()
    /// Inside Play Demo: the title picture held and wiped away before the plate (nil on its own).
    private(set) var leadIn: GlenzLeadIn?
    private let title: ScenePicture?
    private let titleNumbers: (colours: [SIMD3<Int>], numbers: [UInt8])?
    private let pictureLayer: PictureLayer
    private let tallCanvas: IndexedCanvas
    private let blackenPipeline: MTLRenderPipelineState
    private let indexedCanvas: IndexedCanvas
    private let floorTexture: MTLTexture
    private let floorSampler: MTLSamplerState

    private let floorPipeline: MTLRenderPipelineState
    /// Sets the spare (alpha) channel of the whole canvas to a given value.
    private let spareSetPipeline: MTLRenderPipelineState
    /// Faces toggle the spare channel: on where one covers, off again where two do.
    private let togglePipeline: MTLRenderPipelineState
    /// Adds a tint wherever the spare channel is on.
    private let toggleTintPipeline: MTLRenderPipelineState
    /// Faces add their colour to the picture.
    private let addPipeline: MTLRenderPipelineState
    /// Faces add three quarters of their coverage to the spare channel...
    private let coverPipeline: MTLRenderPipelineState
    /// ...and this dims the picture by that much, leaving a quarter under a front face.
    private let dimPipeline: MTLRenderPipelineState

    /// Must match `FloorUniforms` in the shader source below.
    private struct FloorUniforms {
        /// Canvas rows of the plate's far edge and near edge; brightness; unused.
        var rows: SIMD4<Float>
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        indexedCanvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat,
                                          width: GlenzModel.width, height: GlenzModel.height)

        // The plate picture with its own colours, for the modern look.
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: GlenzFloorArt.width, height: GlenzFloorArt.height, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { throw SceneError.textureFailed }
        var bytes = [UInt8]()
        bytes.reserveCapacity(GlenzFloorArt.pixels.count * 4)
        for pixel in GlenzFloorArt.pixels {
            for k in 0..<3 { bytes.append(byteFromVGA(Int(GlenzFloorArt.palette[Int(pixel) * 3 + k]))) }
            bytes.append(255)
        }
        texture.replace(region: MTLRegionMake2D(0, 0, GlenzFloorArt.width, GlenzFloorArt.height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: GlenzFloorArt.width * 4)
        // Made 8x larger by Super-xBR (see `PictureScaler`), then scaled smoothly to the screen.
        floorTexture = try PictureScaler.upscaled(texture, device: device)
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { throw SceneError.textureFailed }
        floorSampler = sampler

        let library = try Shaders.library(
            device: device, source: Shaders.canvasVertexSource + SmoothTriangles.shaderSource + Self.shaderSource)
        let canvasVertex = try Shaders.function("canvas_vertex", in: library)
        let smoothVertex = try Shaders.function("smooth_vertex", in: library)
        let smoothFragment = try Shaders.function("smooth_fragment", in: library)
        let constantFragment = try Shaders.function("glenz_constant_fragment", in: library)
        let colourOnly: MTLColorWriteMask = [.red, .green, .blue]

        func pipeline(_ vertex: MTLFunction, _ fragment: MTLFunction, writes: MTLColorWriteMask,
                      blend: ((MTLRenderPipelineColorAttachmentDescriptor) -> Void)? = nil) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = pixelFormat
            attachment.writeMask = writes
            if let blend {
                attachment.isBlendingEnabled = true
                blend(attachment)
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        floorPipeline = try pipeline(canvasVertex, try Shaders.function("glenz_floor_fragment", in: library), writes: colourOnly)
        spareSetPipeline = try pipeline(canvasVertex, constantFragment, writes: .alpha)
        togglePipeline = try pipeline(smoothVertex, smoothFragment, writes: .alpha) {
            // new = face * (1 - old) + old * (1 - face): XOR for on/off values.
            $0.sourceAlphaBlendFactor = .oneMinusDestinationAlpha
            $0.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        toggleTintPipeline = try pipeline(canvasVertex, constantFragment, writes: colourOnly) {
            $0.sourceRGBBlendFactor = .destinationAlpha
            $0.destinationRGBBlendFactor = .one
        }
        addPipeline = try pipeline(smoothVertex, smoothFragment, writes: colourOnly) {
            $0.sourceRGBBlendFactor = .one
            $0.destinationRGBBlendFactor = .one
        }
        coverPipeline = try pipeline(smoothVertex, smoothFragment, writes: .alpha) {
            $0.sourceAlphaBlendFactor = .one
            $0.destinationAlphaBlendFactor = .one
        }
        dimPipeline = try pipeline(canvasVertex, constantFragment, writes: colourOnly) {
            $0.sourceRGBBlendFactor = .zero
            $0.destinationRGBBlendFactor = .oneMinusDestinationAlpha
        }
        blackenPipeline = try pipeline(smoothVertex, smoothFragment, writes: colourOnly) {
            // Black where covered: what is behind is kept by 1 - coverage.
            $0.sourceRGBBlendFactor = .one
            $0.destinationRGBBlendFactor = .oneMinusSourceAlpha
        }
        // Play Demo's lead-in: the title picture (the title part has usually made its Modern version already).
        title = try? ScenePicture.shared(named: Self.titleName, device: device)   // only Play Demo needs it
        titleNumbers = ScenePicture.colourNumbers(Self.titleName, limit: 255)
        pictureLayer = try PictureLayer.shared(device: device, pixelFormat: pixelFormat)
        tallCanvas = try IndexedCanvas(device: device, pixelFormat: pixelFormat, width: 320, height: 400)
    }

    static let titleName = "04-title"

    var inLeadIn: Bool { leadIn.map { !$0.finished } ?? false }

    func demoUpdate(_ context: DemoContext) {
        if context.justShown, let titleNumbers, titleNumbers.numbers.count == 320 * 400 {
            leadIn = GlenzLeadIn(title: titleNumbers.numbers, levels: titleNumbers.colours)
            model.configureForDemo()
        }
        leadIn?.update(music: context.music, justShown: context.justShown)
    }

    func reset() { model.reset() }
    func tick() {
        if leadIn != nil {
            leadIn!.tick()
            if leadIn!.finished { model.tick() }   // the plate's first picture comes with pass 47
            return
        }
        model.tick()
    }

    func classicReferenceFrame() -> [UInt8] {
        if inLeadIn, let classic = leadIn?.classic {
            return classic.numbers.flatMap { n -> [UInt8] in
                (0..<3).map { byteFromVGA(Int(classic.levels[Int(n) * 3 + $0])) }
            }
        }
        return model.classicReferenceFrame()
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if inLeadIn, let leadIn {
            drawLeadIn(leadIn, into: encoder, frame: frame)
            return
        }
        if frame.look == .classic {
            let palette = (0..<256).map { (i: Int) -> SIMD4<Float> in
                SIMD4(Float(model.colours[i * 3]), Float(model.colours[i * 3 + 1]), Float(model.colours[i * 3 + 2]), 63) / 63
            }
            indexedCanvas.draw(into: encoder, indices: model.screen, palette: palette)
            return
        }

        let state = model.modernState(alpha: frame.alpha)
        let toPixels = frame.targetSize / frame.canvasSize
        var targetSize = frame.targetSize

        func wholeCanvas(_ pipeline: MTLRenderPipelineState, colour: SIMD4<Float>) {
            var colour = colour
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&colour, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        func triangles(_ pipeline: MTLRenderPipelineState, _ list: [SmoothTriangles.Vertex]) {
            guard !list.isEmpty else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(list, length: MemoryLayout<SmoothTriangles.Vertex>.stride * list.count, index: 0)
            encoder.setVertexBytes(&targetSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: list.count)
        }
        func vertices(_ faces: [(corners: [SIMD2<Float>], colour: SIMD4<Float>)]) -> [SmoothTriangles.Vertex] {
            var list: [SmoothTriangles.Vertex] = []
            for face in faces {
                SmoothTriangles.append(face.corners[0] * toPixels, face.corners[1] * toPixels, face.corners[2] * toPixels,
                                       colour: face.colour, to: &list)
            }
            return list
        }

        // 1. The plate.
        if let plate = state.plate {
            var uniforms = FloorUniforms(rows: SIMD4(plate.top, plate.bottom, plate.brightness, 0))
            encoder.setRenderPipelineState(floorPipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FloorUniforms>.stride, index: 0)
            encoder.setFragmentTexture(floorTexture, index: 0)
            encoder.setFragmentSamplerState(floorSampler, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        let nothingToDraw = state.front.isEmpty && state.tinted.isEmpty && state.toggling.isEmpty
        if nothingToDraw { return }

        // 2. The "4" bit: toggled in the spare channel, then shown as its tint.
        wholeCanvas(spareSetPipeline, colour: SIMD4(0, 0, 0, 0))
        triangles(togglePipeline, vertices(state.toggling.map { ($0, SIMD4(0, 0, 0, 1)) }))
        wholeCanvas(toggleTintPipeline, colour: SIMD4(state.toggleTint, 0))

        // 3. The faces that simply add their tint.
        triangles(addPipeline, vertices(state.tinted.map { ($0.corners, SIMD4($0.colour, 0)) }))

        // 4. Front faces of the blue-and-white glenz: keep a quarter of what is behind, add the face.
        wholeCanvas(spareSetPipeline, colour: SIMD4(0, 0, 0, 0))
        triangles(coverPipeline, vertices(state.front.map { ($0.corners, SIMD4(0, 0, 0, 0.75)) }))
        wholeCanvas(dimPipeline, colour: SIMD4(0, 0, 0, 0))
        triangles(addPipeline, vertices(state.front.map { ($0.corners, SIMD4($0.colour, 0)) }))

        // 5. Leave the spare channel as the rest of the app expects it.
        wholeCanvas(spareSetPipeline, colour: SIMD4(0, 0, 0, 1))
    }

    /// Play Demo's lead-in: the title picture, then the wipe (see `GlenzLeadIn`).
    private func drawLeadIn(_ leadIn: GlenzLeadIn, into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        guard frame.look == .modern, let title else {
            let classic = leadIn.classic
            let palette = (0..<256).map { (i: Int) -> SIMD4<Float> in
                SIMD4(Float(classic.levels[i * 3]), Float(classic.levels[i * 3 + 1]), Float(classic.levels[i * 3 + 2]), 63) / 63
            }
            tallCanvas.draw(into: encoder, indices: classic.numbers, palette: palette)
            return
        }
        let view = leadIn.modern(alpha: frame.alpha)
        var fade = PictureFade(towardWhite: false, keep: Float(GlenzLeadIn.fadeParts) - view.grey, outOf: Float(GlenzLeadIn.fadeParts))
        fade.targetLevel = Float(GlenzLeadIn.greyLevel)
        pictureLayer.draw(title, into: encoder, look: .modern, fade: fade)
        guard let bars = view.bars else { return }
        let toPixels = frame.targetSize / frame.canvasSize
        var list: [SmoothTriangles.Vertex] = []
        // One triangle per bar, its other two edges far outside the canvas: two triangles would leave a
        // faint seam along their shared edge (this blending multiplies, it does not add up).
        func bar(edge: Float, away: Float) {
            SmoothTriangles.append(SIMD2<Float>(-2000, edge) * toPixels, SIMD2<Float>(2320, edge) * toPixels,
                                   SIMD2<Float>(160, away) * toPixels, colour: SIMD4(0, 0, 0, 1), to: &list)
        }
        bar(edge: bars.top, away: -4000)
        bar(edge: bars.bottom, away: 4200)
        var targetSize = frame.targetSize
        encoder.setRenderPipelineState(blackenPipeline)
        encoder.setVertexBytes(list, length: MemoryLayout<SmoothTriangles.Vertex>.stride * list.count, index: 0)
        encoder.setVertexBytes(&targetSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: list.count)
    }

    private static let shaderSource = """
    struct FloorUniforms {
        float4 rows;   // canvas row of the plate's far edge, of its near edge; brightness
    };

    // The plate: the picture's top 100 rows squeezed between the two edges, then its 8-row front.
    fragment float4 glenz_floor_fragment(CanvasOut in [[stage_in]],
                                         constant FloorUniforms &u [[buffer(0)]],
                                         texture2d<float> picture [[texture(0)]],
                                         sampler smp [[sampler(0)]]) {
        float y = in.uv.y * 200.0;
        float top = u.rows.x, bottom = u.rows.y;
        float row;
        if (y < top || y >= bottom + 8.0) discard_fragment();
        if (y < bottom) row = (y - top) / max(bottom - top, 1e-4) * 100.0;
        else row = 100.0 + (y - bottom);
        float3 colour = picture.sample(smp, float2(in.uv.x, row / 108.0)).rgb;
        return float4(colour * u.rows.z, 1.0);
    }

    fragment float4 glenz_constant_fragment(CanvasOut in [[stage_in]], constant float4 &colour [[buffer(0)]]) {
        return colour;
    }
    """
}
