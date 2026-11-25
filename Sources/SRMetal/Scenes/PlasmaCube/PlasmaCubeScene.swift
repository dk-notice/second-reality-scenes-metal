import Foundation
import Metal
import simd

/// Draws the Plasma Cube.
///
///  - Classic look: the processor replays the original's line-by-line filling into a model of the
///    VGA card's memory (see `CubeVideoCard`), and the graphics chip turns the colour numbers into
///    colours. The original's alternating two-pixel shift is shown as the even mix of both.
///  - Modern look: the cube is handed to the graphics chip as real 3D triangles. The chip does the
///    perspective, and works the texture out afresh for every screen pixel from the same wave
///    formulas, with smooth edges and with position, turn, light and flow gliding between steps.
final class PlasmaCubeScene: DemoScene {
    private(set) var model = PlasmaCubeModel()
    private let indexedCanvas: IndexedCanvas
    private let pipeline: MTLRenderPipelineState

    /// Must match `CubeVertex` in the shader source below.
    private struct Vertex {
        /// Position in front of the camera; w is unused.
        var position: SIMD4<Float>
        /// Texture position across the face (0...1 each way), colour range, light level.
        var data: SIMD4<Float>
    }

    /// Must match `CubeUniforms` in the shader source below.
    private struct Uniforms {
        var projection: simd_float4x4
        /// x = how far the texture's sideways shift has scrolled, in texture rows.
        var flow: SIMD4<Float>
    }

    /// The original's projection, on this scene's 320x400 canvas: 256 pixels per unit across, 142
    /// rows (426 lines) per unit down, centred on pixel 160 of row 66. The halves aim at pixel centres.
    static let projection = Math3D.perspective(
        focal: SIMD2(256, 142 * 3), centre: SIMD2(160.5, 66.5 * 3),
        canvasSize: SIMD2(Float(PlasmaCubeModel.width), Float(PlasmaCubeModel.canvasHeight)),
        near: 1, far: 4000)

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        indexedCanvas = try IndexedCanvas(
            device: device, pixelFormat: pixelFormat,
            width: PlasmaCubeModel.width, height: PlasmaCubeModel.canvasHeight)

        let library = try Shaders.library(device: device, source: Self.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("cube_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("cube_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        // Faces are laid over what is already there in proportion to how much of the pixel they
        // cover; that is what makes the edges smooth.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func reset() { model.reset() }
    func tick() { model.tick() }
    func demoUpdate(_ context: DemoContext) { model.update(music: context.music, justShown: context.justShown) }
    func classicReferenceFrame() -> [UInt8] { model.classicReferenceFrame() }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        if model.waiting { return }   // inside Play Demo, before the music's cue: the cleared screen
        if frame.look == .classic {
            let pictures = model.classicPictures()
            let palette = (0..<256).map { (i: Int) -> SIMD4<Float> in
                SIMD4(Float(model.palette[i * 3]), Float(model.palette[i * 3 + 1]), Float(model.palette[i * 3 + 2]), 63) / 63
            }
            indexedCanvas.draw(into: encoder, indices: pictures.first, blendedWith: pictures.second, palette: palette)
            return
        }

        let state = model.modernState(alpha: frame.alpha)
        var vertices: [Vertex] = []
        for face in state.faces {
            let c = face.corners
            // Each face is drawn a little larger than it is, so there is room for its edge to fade
            // out over one screen pixel. `margin` is that extra, as a fraction of the face's width.
            let p0 = Math3D.project(c[0], with: Self.projection, targetSize: frame.targetSize)
            let p1 = Math3D.project(c[1], with: Self.projection, targetSize: frame.targetSize)
            let p2 = Math3D.project(c[2], with: Self.projection, targetSize: frame.targetSize)
            let p3 = Math3D.project(c[3], with: Self.projection, targetSize: frame.targetSize)
            let shortest = min(min(simd_distance(p0, p1), simd_distance(p3, p2)),
                               min(simd_distance(p0, p3), simd_distance(p1, p2)))
            let margin = min(3 / max(shortest, 0.001), 1)

            func corner(_ u: Float, _ v: Float) -> Vertex {
                let position = c[0] + (c[1] - c[0]) * u + (c[3] - c[0]) * v
                return Vertex(position: SIMD4(position, 1), data: SIMD4(u, v, Float(face.group), face.light))
            }
            let (low, high) = (-margin, 1 + margin)
            let quad = [corner(low, low), corner(high, low), corner(high, high), corner(low, high)]
            vertices += [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]
        }
        guard !vertices.isEmpty else { return }

        var uniforms = Uniforms(projection: Self.projection, flow: SIMD4(state.scroll, 0, 0, 0))
        encoder.setRenderPipelineState(pipeline)
        encoder.setCullMode(.none)
        encoder.setVertexBytes(vertices, length: MemoryLayout<Vertex>.stride * vertices.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct CubeVertex {
        float4 position;   // in front of the camera
        float4 data;       // texture position u, v; colour range; light
    };

    struct CubeUniforms {
        float4x4 projection;
        float4 flow;       // x = scroll of the sideways shift, in texture rows
    };

    struct CubeVaryings {
        float4 position [[position]];
        float2 uv;
        float group [[flat]];
        float light [[flat]];
    };

    vertex CubeVaryings cube_vertex(uint vid [[vertex_id]],
                                    const device CubeVertex *vertices [[buffer(0)]],
                                    constant CubeUniforms &u [[buffer(1)]]) {
        CubeVertex v = vertices[vid];
        CubeVaryings out;
        out.position = u.projection * float4(v.position.xyz, 1.0);
        out.uv = v.data.xy;
        out.group = v.data.z;
        out.light = v.data.w;
        return out;
    }

    // The original's three 64-colour ranges (PLZFILL.C), without the rounding to 64 steps.
    // a runs 0...63 through a range.
    static float3 rangeColour(int group, float a) {
        float upper = max(a - 32.0, 0.0);
        if (group == 0) return float3(2.0 * upper, 2.0 * upper, min(2.0 * a, 63.0));      // black, blue, white
        if (group == 1) return float3(min(2.0 * a, 63.0), 2.0 * upper, 0.0);              // black, red, yellow
        return float3(a < 32.0 ? a : 63.0 - a, 2.0 * upper, min(a * 2.0 / 3.0, 21.0));    // black, purple, green
    }

    fragment float4 cube_fragment(CubeVaryings in [[stage_in]],
                                  constant CubeUniforms &u [[buffer(1)]]) {
        // How many screen pixels this point is inside the face's nearest edge (negative: outside).
        float2 inside = min(in.uv, 1.0 - in.uv) / max(fwidth(in.uv), 1e-6);
        float cover = clamp(min(inside.x, inside.y) + 1.0, 0.0, 1.0);
        if (cover <= 0.0) discard_fragment();

        // Texture position, in the original's units: columns 64...190, rows 4...60 of its texture.
        float2 t = clamp(in.uv, 0.0, 1.0);
        float column = 64.0 + 126.0 * t.x;
        float row = 4.0 + 56.0 * t.y;
        const float turn = 6.2831853;

        // Each row is shifted sideways by a wave that scrolls down the face (the original's dist1)...
        float shifted = column + (127.0 / 3.0) * sin((row + u.flow.x) * (turn / 64.0));
        // ...and the texture itself is bands that snake up and down across the width (kuva1).
        float snake = 127.0 * sin(shifted * (turn / 256.0));
        float value = 32.0 + (127.0 / 4.0) * sin((4.0 * row + snake) * (turn / 512.0));

        float3 colour = rangeColour(int(in.group + 0.5), value) / 63.0 * in.light;
        return float4(colour * cover, cover);
    }
    """
}
