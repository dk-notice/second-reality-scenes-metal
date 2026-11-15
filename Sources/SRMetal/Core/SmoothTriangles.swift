import Metal
import simd

/// Flat-coloured triangles with smooth (anti-aliased) edges, for scenes made of polygons.
///
/// The graphics chip normally gives a triangle hard, stair-stepped edges. Here each triangle is
/// drawn one pixel larger all round, and every pixel works out how far inside the TRUE triangle it
/// is; pixels on the edge are faded in proportion. Two triangles that share an edge fade in
/// opposite directions across it, so their coverages always add up to exactly one there and no
/// seam shows, provided the blending in use adds things up (see Glenz Vectors for an example).
///
/// Positions are in pixels of the area being drawn into, (0,0) at the top left. The scene does the
/// 3D work itself (with `Math3D`) and hands over triangles already placed on the screen.
enum SmoothTriangles {
    /// Must match `SmoothVertex` in `shaderSource`.
    struct Vertex {
        var position: SIMD2<Float>
        /// Distance in pixels from this corner to each of the true triangle's three edges
        /// (positive inside). The chip blends these across the triangle.
        var edges: SIMD3<Float>
        /// What the fragment shader returns at full coverage (it is multiplied by the coverage).
        var colour: SIMD4<Float>
    }

    /// Adds one triangle to `list`. Corners may be given in either order.
    static func append(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>, _ p2: SIMD2<Float>,
                       colour: SIMD4<Float>, to list: inout [Vertex]) {
        var p = [p0, p1, p2]
        let doubleArea = (p[1].x - p[0].x) * (p[2].y - p[0].y) - (p[1].y - p[0].y) * (p[2].x - p[0].x)
        // Thinner than a hundredth of a pixel: nothing to see.
        if abs(doubleArea) < 0.01 { return }
        if doubleArea < 0 { p.swapAt(1, 2) }

        // Each edge as a line: `normal . point + offset` is the distance inside that edge.
        var normals: [SIMD2<Float>] = []
        var offsets: [Float] = []
        for i in 0..<3 {
            let a = p[i], b = p[(i + 1) % 3]
            let along = simd_normalize(b - a)
            let normal = SIMD2(-along.y, along.x)
            normals.append(normal)
            offsets.append(-simd_dot(normal, a))
        }
        for i in 0..<3 {
            // Push this corner out along the line that splits its angle, far enough to clear both
            // of its edges by one pixel (but never more than 8 pixels, for needle-thin corners).
            let before = normals[(i + 2) % 3], after = normals[i]
            let outward = -(before + after)
            let length = simd_length(outward)
            var corner = p[i]
            if length > 1e-4 {
                let direction = outward / length
                let clearance = max(-simd_dot(direction, after), 0.125)
                corner += direction * min(1 / clearance, 8)
            }
            let distances = SIMD3(simd_dot(normals[0], corner) + offsets[0],
                                  simd_dot(normals[1], corner) + offsets[1],
                                  simd_dot(normals[2], corner) + offsets[2])
            list.append(Vertex(position: corner, edges: distances, colour: colour))
        }
    }

    /// Shader functions `smooth_vertex` and `smooth_fragment`. The vertex function expects the
    /// vertex list in buffer 0 and the size of the drawing area (a `float2`, in pixels) in buffer 1.
    static let shaderSource = """
    struct SmoothVertex {
        float2 position;
        float3 edges;
        float4 colour;
    };

    struct SmoothVaryings {
        float4 position [[position]];
        float3 edges;
        float4 colour [[flat]];
    };

    vertex SmoothVaryings smooth_vertex(uint vid [[vertex_id]],
                                        const device SmoothVertex *vertices [[buffer(0)]],
                                        constant float2 &targetSize [[buffer(1)]]) {
        SmoothVertex v = vertices[vid];
        SmoothVaryings out;
        out.position = float4(v.position.x / targetSize.x * 2.0 - 1.0,
                              1.0 - v.position.y / targetSize.y * 2.0, 0.0, 1.0);
        out.edges = v.edges;
        out.colour = v.colour;
        return out;
    }

    fragment float4 smooth_fragment(SmoothVaryings in [[stage_in]]) {
        // Half a pixel outside the true edge is "not covered", half a pixel inside is "fully covered".
        float cover = clamp(min(in.edges.x, min(in.edges.y, in.edges.z)) + 0.5, 0.0, 1.0);
        if (cover <= 0.0) discard_fragment();
        return in.colour * cover;
    }

    """
}
