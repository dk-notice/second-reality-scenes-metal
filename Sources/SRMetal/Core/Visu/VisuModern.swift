import Metal
import simd

/// Where every object of a scene is at one moment, ready to draw: the modern look's input.
/// Take one after each animation frame (`VisuWorld.pose()`), keep the previous one, and draw the
/// blend of the two for smooth motion between frames.
struct VisuPose {
    struct Item {
        let object: VisuObject
        /// Takes the object's own coordinates to camera space.
        var matrix: simd_float4x4
    }
    /// In the 1993 drawing order: farthest first.
    var items: [Item]

    /// The pose `alpha` (0...1) of the way from `self` to `next`. Objects are matched up by
    /// identity; one that is only in `next` (just switched on) is shown where `next` has it, and
    /// one that is only in `self` (just switched off) is dropped. The drawing order is `next`'s.
    func blended(to next: VisuPose, alpha: Float) -> VisuPose {
        var mine: [ObjectIdentifier: simd_float4x4] = [:]
        for item in items { mine[ObjectIdentifier(item.object)] = item.matrix }
        return VisuPose(items: next.items.map { item in
            guard let from = mine[ObjectIdentifier(item.object)] else { return item }
            let m = simd_float4x4(columns: (
                simd_mix(from.columns.0, item.matrix.columns.0, SIMD4(repeating: alpha)),
                simd_mix(from.columns.1, item.matrix.columns.1, SIMD4(repeating: alpha)),
                simd_mix(from.columns.2, item.matrix.columns.2, SIMD4(repeating: alpha)),
                simd_mix(from.columns.3, item.matrix.columns.3, SIMD4(repeating: alpha))))
            return Item(object: item.object, matrix: m)
        })
    }

    /// The same pose seen by a camera rolled by `angle` (radians) about its line of sight.
    func rolled(by angle: Float) -> VisuPose {
        if angle == 0 { return self }
        let c = cos(angle), s = sin(angle)
        let roll = simd_float4x4(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
        return VisuPose(items: items.map { Item(object: $0.object, matrix: roll * $0.matrix) })
    }
}

extension VisuMatrix {
    /// The same turn and position in ordinary decimals, as a matrix for the graphics chip:
    /// `matrix * float4(point, 1)`. (Like `calc_rotate`, it reads only the low 16 bits of each
    /// turn number.)
    var float4x4: simd_float4x4 {
        let f = m.map { Float(Int16(truncatingIfNeeded: $0)) / Float(VisuMatrix.unit) }
        return simd_float4x4(columns: (
            SIMD4(f[0], f[3], f[6], 0),
            SIMD4(f[1], f[4], f[7], 0),
            SIMD4(f[2], f[5], f[8], 0),
            SIMD4(Float(x), Float(y), Float(z), 1)))
    }
}

extension VisuWorld {
    /// The current frame as a pose for the modern look (same objects and order as `draw(with:)`).
    func pose() -> VisuPose {
        VisuPose(items: prepareFrame().map { VisuPose.Item(object: $0, matrix: $0.inCamera.float4x4) })
    }
}

/// The view the modern look draws through: the 1993 engine's projection numbers, as decimals.
struct VisuView {
    /// Perspective: canvas x = centre.x + focal.x * x / z (canvas pixels, 320x200).
    var focal: SIMD2<Float>
    var centre: SIMD2<Float>
    /// The window on the canvas that is drawn into: left, top, right, bottom (right/bottom exclusive).
    var window: SIMD4<Float>
    /// Nothing nearer than this is drawn.
    var near: Float
}

extension VisuEngine {
    /// The engine's current window and field of view, for the modern look.
    var view: VisuView {
        VisuView(focal: SIMD2(Float(mulX), Float(mulY)),
                 centre: SIMD2(Float(addX), Float(addY)),
                 window: SIMD4(Float(clipX.min), Float(clipY.min), Float(clipX.max + 1), Float(clipY.max + 1)),
                 near: Float(clipZ.min))
    }
}

/// Draws VISU objects as real triangles on the graphics chip: the modern look of the engine.
///
/// What differs from the 1993 replay (`VisuEngine`):
/// - corners stay in decimals instead of snapping to whole pixels, at the display's resolution;
/// - BETWEEN objects, a depth buffer (a per-pixel record of distance) decides what is in front,
///   pixel by pixel, instead of drawing whole objects back to front by one centre point each.
///   WITHIN an object the polygons are still drawn back to front in the original's own order
///   lists, because the models rely on it: details such as the big ship's panels float just off
///   the surface behind them, and in places sit slightly inside it;
/// - the light on a surface is worked out in the shader by the original's rule but without rounding
///   to a whole colour number, and the colour is blended between neighbouring palette entries;
/// - edges are smoothed (4 samples per pixel);
/// - hidden faces are dropped by the original's own test (face normal against the direction to
///   the polygon's first corner), and the near plane is the original's.
///
/// It draws into its own off-screen picture first (`render`, before the main pass: a depth buffer
/// and multisampling cannot be added to the app's main pass without changing every scene), then
/// lays that picture over whatever the scene has already drawn (`composite`).
final class VisuModernRenderer {
    static let samples = 4
    static let canvasSize = SIMD2<Float>(Float(VisuEngine.width), Float(VisuEngine.height))

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let pipeline: MTLRenderPipelineState
    private let depthOnlyPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    /// Tests against the depth of the objects drawn so far, without recording its own.
    private let testOnly: MTLDepthStencilState
    /// Tests and records depth.
    private let testAndWrite: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private let paletteBuffer: MTLBuffer

    private struct MeshBuffer {
        let buffer: MTLBuffer
        let vertexCount: Int
        /// For each of the mesh's order lists: its triangles in that list's back-to-front order.
        let orders: [(buffer: MTLBuffer, count: Int)]
    }
    private var meshes: [ObjectIdentifier: MeshBuffer] = [:]

    private var colourTarget: MTLTexture?      // multisampled
    private var depthTarget: MTLTexture?       // multisampled
    private var resolved: MTLTexture?          // what `composite` shows

    /// One corner of a triangle, as the shader reads it (16 numbers).
    private struct Vertex {
        var position: (Float, Float, Float)
        var faceNormal: (Float, Float, Float)
        var lightNormal: (Float, Float, Float)
        var firstCorner: (Float, Float, Float)
        var baseColour: Float
        var divisor: Float
        var maxShade: Float
        var twoSided: Float
    }

    private struct Uniforms {
        var projection: simd_float4x4
        var toCamera: simd_float4x4
        var light: SIMD4<Float>
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        self.pixelFormat = pixelFormat

        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + Self.source)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("visu_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("visu_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = Self.samples
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.colorAttachments[0].writeMask = []
        depthOnlyPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let over = MTLRenderPipelineDescriptor()
        over.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        over.fragmentFunction = try Shaders.function("visu_composite_fragment", in: library)
        over.colorAttachments[0].pixelFormat = pixelFormat
        // The off-screen picture's colours are already multiplied by its coverage ("premultiplied").
        over.colorAttachments[0].isBlendingEnabled = true
        over.colorAttachments[0].sourceRGBBlendFactor = .one
        over.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        over.colorAttachments[0].sourceAlphaBlendFactor = .one
        over.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        compositePipeline = try device.makeRenderPipelineState(descriptor: over)

        // Depth is stored as near / distance: 1 at the near plane, towards 0 far away. Kept that
        // way round, the numbers stay precise over the city's huge range of distances. Nearer or
        // EQUAL wins, so two surfaces at exactly the same depth resolve as the 1993 version did:
        // the one drawn later shows.
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .greaterEqual
        depth.isDepthWriteEnabled = false
        guard let testOnly = device.makeDepthStencilState(descriptor: depth) else { throw SceneError.textureFailed }
        self.testOnly = testOnly
        depth.isDepthWriteEnabled = true
        guard let testAndWrite = device.makeDepthStencilState(descriptor: depth) else { throw SceneError.textureFailed }
        self.testAndWrite = testAndWrite

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor),
              let paletteBuffer = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * 256, options: .storageModeShared)
        else { throw SceneError.textureFailed }
        self.sampler = sampler
        self.paletteBuffer = paletteBuffer
    }

    /// The triangles of one mesh. Every polygon is cut into a fan of triangles from its first corner.
    private func buffer(for mesh: VisuMesh) -> MeshBuffer? {
        if let made = meshes[ObjectIdentifier(mesh)] { return made }
        var vertices: [Vertex] = []
        var ranges: [Int: Range<Int>] = [:]          // polygon offset -> its corners in `vertices`
        func position(_ i: Int) -> (Float, Float, Float) { (Float(mesh.x[i]), Float(mesh.y[i]), Float(mesh.z[i])) }
        func normal(_ i: Int) -> (Float, Float, Float) {
            guard i < mesh.normals.count else { return (0, 0, 1) }
            let n = mesh.normals[i]
            return (Float(n.x) / 16384, Float(n.y) / 16384, Float(n.z) / 16384)
        }
        for polygon in mesh.polygons where polygon.vertices.count >= 3 && polygon.vertices.allSatisfy({ $0 < mesh.vertexCount }) {
            let shades = polygon.shades
            func corner(_ v: Int) -> Vertex {
                Vertex(position: position(v),
                       faceNormal: normal(polygon.normal),
                       lightNormal: normal(polygon.isGouraud ? mesh.vertexNormal[v] : polygon.normal),
                       firstCorner: position(polygon.vertices[0]),
                       baseColour: Float(polygon.colour),
                       // brightness 0...255 divided by this gives the shade within the colour range
                       divisor: shades == 0 ? 0 : Float(256 / shades),
                       maxShade: Float(min(30, max(shades - 1, 1))),
                       twoSided: polygon.flags & VisuFlags.twoSided != 0 ? 1 : 0)
            }
            let start = vertices.count
            for i in 1..<polygon.vertices.count - 1 {
                vertices.append(corner(polygon.vertices[0]))
                vertices.append(corner(polygon.vertices[i]))
                vertices.append(corner(polygon.vertices[i + 1]))
            }
            ranges[polygon.offset] = start..<vertices.count
        }
        guard !vertices.isEmpty,
              let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count,
                                             options: .storageModeShared)
        else { return nil }
        var orders: [(buffer: MTLBuffer, count: Int)] = []
        for list in mesh.orders {
            var indices: [UInt32] = []
            for offset in list.dropFirst(2) {
                if offset == 0 { break }
                if let range = ranges[offset] { indices += range.map { UInt32($0) } }
            }
            if indices.isEmpty { indices = [0, 0, 0] }
            guard let indexBuffer = device.makeBuffer(bytes: indices, length: 4 * indices.count, options: .storageModeShared)
            else { return nil }
            orders.append((indexBuffer, indices.count))
        }
        let made = MeshBuffer(buffer: buffer, vertexCount: vertices.count, orders: orders)
        meshes[ObjectIdentifier(mesh)] = made
        return made
    }

    private func makeTargets(width: Int, height: Int) -> Bool {
        if let resolved, resolved.width == width, resolved.height == height { return true }
        let colour = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        colour.textureType = .type2DMultisample
        colour.sampleCount = Self.samples
        colour.usage = .renderTarget
        colour.storageMode = .private
        let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        depth.textureType = .type2DMultisample
        depth.sampleCount = Self.samples
        depth.usage = .renderTarget
        depth.storageMode = .private
        let single = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        single.usage = [.renderTarget, .shaderRead]
        single.storageMode = .private
        colourTarget = device.makeTexture(descriptor: colour)
        depthTarget = device.makeTexture(descriptor: depth)
        resolved = device.makeTexture(descriptor: single)
        return colourTarget != nil && depthTarget != nil && resolved != nil
    }

    /// Step 1, BEFORE the main pass begins (from a scene's `prepare`): draws the pose into the
    /// off-screen picture. `targetSize` is the size in real pixels of the area the canvas will
    /// cover; `palette` is the scene's 256 colours (0...1 per channel).
    func render(_ pose: VisuPose, view: VisuView, palette: [SIMD4<Float>], targetSize: SIMD2<Float>,
                commands: MTLCommandBuffer) {
        let width = max(Int(targetSize.x), 1), height = max(Int(targetSize.y), 1)
        guard makeTargets(width: width, height: height) else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = colourTarget
        pass.colorAttachments[0].resolveTexture = resolved
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = depthTarget
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 0
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }

        // Only the engine's window is drawn into (the two scenes use a 320x150 band).
        let scale = SIMD2(Float(width), Float(height)) / Self.canvasSize
        let x0 = min(max(Int((view.window.x * scale.x).rounded()), 0), width)
        let y0 = min(max(Int((view.window.y * scale.y).rounded()), 0), height)
        let x1 = min(max(Int((view.window.z * scale.x).rounded()), x0), width)
        let y1 = min(max(Int((view.window.w * scale.y).rounded()), y0), height)
        guard x1 > x0, y1 > y0 else { encoder.endEncoding(); return }
        encoder.setScissorRect(MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))

        palette.prefix(256).withUnsafeBytes { bytes in
            paletteBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
        encoder.setFragmentBuffer(paletteBuffer, offset: 0, index: 0)

        let projection = Math3D.perspectiveNearOverZ(focal: view.focal, centre: view.centre,
                                                     canvasSize: Self.canvasSize, near: view.near)
        let l = VisuEngine.light
        let light = simd_normalize(SIMD3(Float(l.x), Float(l.y), Float(l.z)))
        for item in pose.items where item.object.flags & VisuFlags.visible != 0 {
            guard let mesh = buffer(for: item.object.mesh) else { continue }
            var uniforms = Uniforms(projection: projection, toCamera: item.matrix, light: SIMD4(light, 0))
            encoder.setVertexBuffer(mesh.buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

            // As `vis_drawobject`: the order list whose direction vertex is nearest the camera.
            let shape = item.object.mesh
            var list = 0
            var nearest = Float.infinity
            for b in 1..<shape.orders.count {
                let v = shape.orders[b][1]
                guard v < shape.vertexCount else { continue }
                let z = (item.matrix * SIMD4(Float(shape.x[v]), Float(shape.y[v]), Float(shape.z[v]), 1)).z
                if z < nearest { nearest = z; list = b }
            }

            // 1. Colour: the object's polygons back to front, hidden only by objects drawn before.
            encoder.setRenderPipelineState(pipeline)
            encoder.setDepthStencilState(testOnly)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.orders[list].count, indexType: .uint32,
                                          indexBuffer: mesh.orders[list].buffer, indexBufferOffset: 0)
            // 2. Depth: now record where this object is, for the objects still to come.
            encoder.setRenderPipelineState(depthOnlyPipeline)
            encoder.setDepthStencilState(testAndWrite)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
        }
        encoder.endEncoding()
    }

    /// Step 2, inside the main pass (from a scene's `draw`): lays the off-screen picture over
    /// what has been drawn so far (the scene's background). The viewport must be the canvas area.
    func composite(into encoder: MTLRenderCommandEncoder) {
        guard let resolved else { return }
        encoder.setRenderPipelineState(compositePipeline)
        encoder.setFragmentTexture(resolved, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    private static let source = """
    struct VisuVertex {
        packed_float3 position;
        packed_float3 faceNormal;
        packed_float3 lightNormal;
        packed_float3 firstCorner;
        float baseColour;
        float divisor;
        float maxShade;
        float twoSided;
    };

    struct VisuUniforms {
        float4x4 projection;
        float4x4 toCamera;
        float4 light;
    };

    struct VisuOut {
        float4 position [[position]];
        float colour;      // palette position, with a fraction
    };

    vertex VisuOut visu_vertex(uint vid [[vertex_id]],
                               const device VisuVertex *vertices [[buffer(0)]],
                               constant VisuUniforms &u [[buffer(1)]]) {
        VisuVertex v = vertices[vid];
        float3x3 turn = float3x3(u.toCamera[0].xyz, u.toCamera[1].xyz, u.toCamera[2].xyz);
        float3 inCamera = (u.toCamera * float4(float3(v.position), 1.0)).xyz;

        VisuOut out;
        out.position = u.projection * float4(inCamera, 1.0);

        // The original's hidden-face test: the face's normal against the direction from the eye to
        // the polygon's first corner. All corners of a polygon get the same answer, so a hidden
        // polygon collapses to nothing.
        float3 first = (u.toCamera * float4(float3(v.firstCorner), 1.0)).xyz;
        if (v.twoSided < 0.5 && dot(turn * float3(v.faceNormal), first) >= 0.0) {
            out.position = float4(0.0, 0.0, -1.0, 1.0);
        }

        // The original's light: brightness 0...255 = 128 + 128 * cos(angle to the light), then
        // divided down to the polygon's colour range and held to 1...30 (or the range's end).
        // The 1993 code dropped the fraction; taking half off here keeps the same average.
        // The turned normal is NOT brought back to length 1, because the original did not: the
        // recordings scale some objects (the big ship shrinks to a fifth as it leaves; one city
        // building is stretched to twice its depth), and the original's light on them weakens or
        // strengthens with the scale. Normalising here made the big ship lighter than in 1993.
        float brightness = clamp(128.0 + 128.0 * dot(turn * float3(v.lightNormal), u.light.xyz), 0.0, 255.0);
        float shade = v.divisor > 0.0 ? clamp(brightness / v.divisor - 0.5, 1.0, v.maxShade) : 1.0;
        out.colour = v.baseColour + shade;
        return out;
    }

    fragment float4 visu_fragment(VisuOut in [[stage_in]],
                                  const device float4 *palette [[buffer(0)]]) {
        float c = clamp(in.colour, 0.0, 255.0);
        uint low = uint(floor(c));
        float3 colour = mix(palette[low].rgb, palette[min(low + 1, 255u)].rgb, c - floor(c));
        return float4(colour, 1.0);
    }

    fragment float4 visu_composite_fragment(CanvasOut in [[stage_in]],
                                            texture2d<float> picture [[texture(0)]],
                                            sampler smp [[sampler(0)]]) {
        return picture.sample(smp, in.uv);
    }
    """
}
