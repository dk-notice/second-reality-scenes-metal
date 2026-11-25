import Foundation

/// The three number tables of the original VISU engine (ADATASIN.INC, AVISTAN.INC, AFILLDIV.INC),
/// calculated with the formulas of the little programs that wrote those files (DOSIN.C, DOTAN.C,
/// DOFILL.C). Each reproduces its file exactly; the self-test checks that by checksum.
enum VisuTables {
    /// One sine wave in 4096 entries, 16384 tall. 16384 is the engine's "1" (see `VisuMatrix.unit`).
    static let sine: [Int16] = (0..<4096).map { r in
        Int16(sin(2.0 * 3.1415926535897932384626 * Double(r) / 4096.0) * 16384.0 + 0.5)
    }

    /// For the field of view: 256 / tan(angle), for 256 angles from 0 to a quarter turn.
    /// (DOTAN.C used a 13-digit pi; the first two entries are simply "as large as possible".)
    static let tangent: [UInt16] = (0..<256).map { a in
        a < 2 ? 32767 : UInt16(Int(256.0 * (1.0 / tan(Double(a) * 2.0 * 3.141592653589 / 1024.0))))
    }

    /// 65536 / n, so the Gouraud filler can divide by a row's length with one multiplication.
    static let fillDivide: [UInt16] = (0..<512).map { n in
        UInt16(min(65536 / max(n, 1), 65535))
    }
}

/// VISU's "rmatrix": a turn (nine numbers, 16384 meaning 1) and a position. It says where an
/// object, or the camera, is and which way it faces.
struct VisuMatrix: Equatable {
    /// The turn, row by row: `m[row * 3 + column]`.
    var m: [Int32] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
    var x: Int32 = 0
    var y: Int32 = 0
    var z: Int32 = 0

    /// The engine's fixed-point "1": numbers are whole, and 16384 stands for 1.0 (14 binary places).
    static let unit: Int32 = 16384
    static let unitShift: Int32 = 14

    static let zero = VisuMatrix()
    static var identity: VisuMatrix {
        var r = VisuMatrix()
        r.m[0] = unit; r.m[4] = unit; r.m[8] = unit
        return r
    }
}

/// The matrix routines of ACALC.ASM, with the original's 16-, 32- and 64-bit arithmetic.
/// Angles are 0...65535 for one full turn.
enum VisuMath {
    /// ACALC `sin`: the table has 4096 entries, so the angle's lowest 4 bits are dropped.
    static func sine(_ angle: UInt16) -> Int32 { Int32(VisuTables.sine[Int(angle >> 4)]) }
    static func cosine(_ angle: UInt16) -> Int32 { Int32(VisuTables.sine[(Int(angle >> 4) + 1024) & 4095]) }

    /// ACALC `mulmatrices`: a * b for two turns. Each product keeps only its low 32 bits, the sum
    /// of three wraps at 32 bits, then an arithmetic shift right by 14.
    static func multiply(_ a: [Int32], _ b: [Int32]) -> [Int32] {
        var r = [Int32](repeating: 0, count: 9)
        for row in 0..<3 {
            for col in 0..<3 {
                let sum = (a[row * 3] &* b[col]) &+ (a[row * 3 + 1] &* b[3 + col]) &+ (a[row * 3 + 2] &* b[6 + col])
                r[row * 3 + col] = sum >> 14
            }
        }
        return r
    }

    /// ACALC `calcmatrixsep`: the three single-axis turns. Each uses the NEGATED angle. And the
    /// original pops its saved angles in the wrong order (it pushes y then z, and pops into "y"
    /// first), so the turn about the y axis uses the z angle and the turn about z uses the y angle.
    /// Kept, because that is what the routine does. (The two scenes never call it: their turns
    /// come ready-made from the animation data. Only the engine's test cases use it.)
    static func axisTurns(x: UInt16, y: UInt16, z: UInt16) -> (x: [Int32], y: [Int32], z: [Int32]) {
        let (xs, xc) = (sine(0 &- x), cosine(0 &- x))
        let (ys, yc) = (sine(0 &- z), cosine(0 &- z))
        let (zs, zc) = (sine(0 &- y), cosine(0 &- y))
        let u = VisuMatrix.unit
        return ([u, 0, 0, 0, xc, xs, 0, -xs, xc],
                [yc, 0, -ys, 0, u, 0, ys, 0, yc],
                [zc, zs, 0, -zs, zc, 0, 0, 0, u])
    }

    /// `calc_setrmatrix_rotyxz`: (Y * X) * Z.
    static func rotationYXZ(x: UInt16, y: UInt16, z: UInt16) -> [Int32] {
        let t = axisTurns(x: x, y: y, z: z)
        return multiply(multiply(t.y, t.x), t.z)
    }

    /// ACALC `rotatesingle`: one position through a turn. Full 64-bit products and sum, shifted
    /// right by 14, of which the low 32 bits are kept.
    static func turn(_ m: [Int32], _ x: Int32, _ y: Int32, _ z: Int32) -> (Int32, Int32, Int32) {
        func row(_ i: Int) -> Int32 {
            let sum = Int64(x) &* Int64(m[i]) &+ Int64(y) &* Int64(m[i + 1]) &+ Int64(z) &* Int64(m[i + 2])
            return Int32(truncatingIfNeeded: sum >> 14)
        }
        return (row(0), row(3), row(6))
    }

    /// `calc_applyrmatrix(dest, apply)`: `dest` is an object's own turn and position, `apply` is the
    /// camera's. Afterwards `dest` takes the object's points straight to camera space.
    static func apply(_ dest: inout VisuMatrix, camera apply: VisuMatrix) {
        dest.m = multiply(apply.m, dest.m)
        let p = turn(apply.m, dest.x, dest.y, dest.z)
        dest.x = p.0 &+ apply.x
        dest.y = p.1 &+ apply.y
        dest.z = p.2 &+ apply.z
    }

    /// `calc_singlez`: how far in front of the camera one point ends up (used to order objects).
    /// Unlike `calc_rotate`, this uses the matrix's full 32-bit numbers.
    static func depth(of point: (x: Int32, y: Int32, z: Int32), through r: VisuMatrix) -> Int32 {
        let sum = Int64(r.m[6]) &* Int64(point.x) &+ Int64(r.m[7]) &* Int64(point.y) &+ Int64(r.m[8]) &* Int64(point.z)
        return Int32(truncatingIfNeeded: sum >> 14) &+ r.z
    }
}
