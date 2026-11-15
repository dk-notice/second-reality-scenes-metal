import simd

/// Small helpers for scenes made of real 3D shapes (first used by the Plasma Cube).
///
/// The convention is the original demo's: the camera sits at (0, 0, 0) looking along +z, x runs to
/// the right and y runs DOWN, like screen lines. A point "in camera space" is one already turned and
/// moved so that it is expressed relative to that camera.
enum Math3D {
    /// The matrix that puts camera-space points on the canvas the way the original 3D parts did:
    /// a point (X, Y, Z) lands on canvas position
    ///
    ///     (centre.x + focal.x * X / Z,  centre.y + focal.y * Y / Z)
    ///
    /// measured in canvas pixels from the top-left corner. Give it to a vertex shader and multiply:
    /// `position = matrix * float4(X, Y, Z, 1)`. The graphics chip does the divide by Z itself, which
    /// is also what lets it stretch textures correctly across a face seen at an angle.
    ///
    /// `near` and `far` are the nearest and farthest Z that can be drawn. They also spread depth
    /// values over 0...1, ready for a depth buffer (a per-pixel record of distance, which scenes
    /// with overlapping shapes will need; a single cube does not).
    static func perspective(focal: SIMD2<Float>, centre: SIMD2<Float>, canvasSize: SIMD2<Float>,
                            near: Float, far: Float) -> simd_float4x4 {
        let depth = far / (far - near)
        return simd_float4x4(columns: (
            SIMD4(2 * focal.x / canvasSize.x, 0, 0, 0),
            SIMD4(0, -2 * focal.y / canvasSize.y, 0, 0),
            SIMD4(2 * centre.x / canvasSize.x - 1, 1 - 2 * centre.y / canvasSize.y, depth, 1),
            SIMD4(0, 0, -near * depth, 0)))
    }

    /// The same projection as `perspective`, for scenes that use a depth buffer over a very large
    /// range of distances (the VISU engine's city: from 512 to millions). Depth comes out as
    /// `near / Z`: exactly 1 at the near plane, falling towards 0 with distance, and there is no far
    /// limit. Stored that way round, depth numbers stay precise far away, where the usual
    /// arrangement runs out of digits. Use it with a depth buffer cleared to 0 and the test
    /// "greater (or equal) wins".
    static func perspectiveNearOverZ(focal: SIMD2<Float>, centre: SIMD2<Float>, canvasSize: SIMD2<Float>,
                                     near: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(2 * focal.x / canvasSize.x, 0, 0, 0),
            SIMD4(0, -2 * focal.y / canvasSize.y, 0, 0),
            SIMD4(2 * centre.x / canvasSize.x - 1, 1 - 2 * centre.y / canvasSize.y, 0, 1),
            SIMD4(0, 0, near, 0)))
    }

    /// Where a camera-space point lands, in pixels of a drawing area `targetSize` big.
    static func project(_ point: SIMD3<Float>, with matrix: simd_float4x4, targetSize: SIMD2<Float>) -> SIMD2<Float> {
        let clip = matrix * SIMD4(point, 1)
        let x = (clip.x / clip.w * 0.5 + 0.5) * targetSize.x
        let y = (0.5 - clip.y / clip.w * 0.5) * targetSize.y
        return SIMD2(x, y)
    }

    /// Turns about the x, y and z axes, by an angle in radians. Multiply a point by the result.
    static func rotationX(_ angle: Float) -> simd_float3x3 {
        let (s, c) = (sin(angle), cos(angle))
        return simd_float3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, c, -s), SIMD3(0, s, c)])
    }

    static func rotationY(_ angle: Float) -> simd_float3x3 {
        let (s, c) = (sin(angle), cos(angle))
        return simd_float3x3(rows: [SIMD3(c, 0, s), SIMD3(0, 1, 0), SIMD3(-s, 0, c)])
    }

    static func rotationZ(_ angle: Float) -> simd_float3x3 {
        let (s, c) = (sin(angle), cos(angle))
        return simd_float3x3(rows: [SIMD3(c, -s, 0), SIMD3(s, c, 0), SIMD3(0, 0, 1)])
    }

    /// One matrix that turns a point and then moves it: `matrix * float4(point, 1)`.
    static func transform(rotation: simd_float3x3, translation: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(rotation.columns.0, 0), SIMD4(rotation.columns.1, 0), SIMD4(rotation.columns.2, 0),
            SIMD4(translation, 1)))
    }

    /// True if a flat shape faces the camera. `a`, `b`, `c` are three of its corners in camera space,
    /// in the order the original listed them. This is the original's test: the shape's "normal" (the
    /// direction it faces, from the cross product of two edges) against the direction to the eye.
    static func facesCamera(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Bool {
        simd_dot(a, simd_cross(b - a, c - a)) >= 0
    }

    /// The turn matrix of the original's MATH.ASM `calcmatrix` ("rY*rX*rZ"), used by Glenz Vectors.
    /// Angles in radians. Multiply a point by the result. (The 1993 code stored each number as a
    /// 16-bit fraction of 32768; this is the same matrix in ordinary decimals.)
    static func rotationYXZ(x: Float, y: Float, z: Float) -> simd_float3x3 {
        let (xs, xc) = (sin(x), cos(x))
        let (ys, yc) = (sin(y), cos(y))
        let (zs, zc) = (sin(z), cos(z))
        return simd_float3x3(rows: [
            SIMD3(yc * zc - xs * ys * zs, xs * ys * zc + yc * zs, -xc * ys),
            SIMD3(-xc * zs, xc * zc, xs),
            SIMD3(xs * yc * zs + ys * zc, ys * zs - xs * yc * zc, xc * yc)])
    }

    /// Where a camera-space point lands on the canvas by the original's rule
    /// "centre + focal * (x, y) / z", with z held to at least `near` as the original did.
    static func canvasPosition(_ point: SIMD3<Float>, focal: SIMD2<Float>, centre: SIMD2<Float>,
                               near: Float) -> SIMD2<Float> {
        centre + focal * SIMD2(point.x, point.y) / max(point.z, near)
    }

    /// Twice the area of a triangle on the canvas, with a sign: positive or zero when the corners run
    /// the way the original's front faces do. The 2D form of the "which faces show" test, used by
    /// the parts that test faces after projecting them (GLENZ `checkhiddenbx`).
    static func screenFacing(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
        (a.x - b.x) * (a.y - c.y) - (a.y - b.y) * (a.x - c.x)
    }
}
