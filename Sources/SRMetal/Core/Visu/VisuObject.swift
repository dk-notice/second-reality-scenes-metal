import Foundation

/// Flag bits of objects and polygons (AD.INC / CD.H). A polygon's flag byte holds the upper half
/// of these numbers (0x10 for Gouraud, and so on).
enum VisuFlags {
    static let visible: UInt16 = 0x0001
    static let flip: UInt16 = 0x0100          // defined, never used by the engine
    static let twoSided: UInt16 = 0x0200
    static let shade8: UInt16 = 0x0400
    static let shade16: UInt16 = 0x0800
    static let shade32: UInt16 = 0x0C00
    static let gouraud: UInt16 = 0x1000
    static let texture: UInt16 = 0x2000       // defined, never implemented
    /// What `vis_loadobject` gives every object: visible, every polygon feature allowed.
    static let objectDefault: UInt16 = 0xF001
}

/// One polygon of an object, as read from the file's POLY block.
struct VisuPolygon {
    /// Where its record starts inside the POLY block (the number the order lists hold).
    let offset: Int
    /// The flag byte moved up into the object-flag positions: `VisuFlags.gouraud` etc.
    let flags: UInt16
    /// First palette colour of the polygon's shade range.
    let colour: UInt8
    /// Index of the face normal.
    let normal: Int
    /// Indices of its corners, in the file's order.
    let vertices: [Int]

    var isGouraud: Bool { flags & VisuFlags.gouraud != 0 }
    /// How many shades its range has: 8, 16 or 32 (0 = not shaded).
    var shades: Int {
        switch flags & VisuFlags.shade32 {
        case VisuFlags.shade8: return 8
        case VisuFlags.shade16: return 16
        case VisuFlags.shade32: return 32
        default: return 0
        }
    }
}

/// The shape of one object: what a `.001`-style object file holds (see docs/visu-engine.md).
/// Several objects in a scene can share one mesh (the three small ships do).
final class VisuMesh {
    let name: String
    /// Corner positions, in the object's own coordinates.
    let x: [Int32]
    let y: [Int32]
    let z: [Int32]
    /// For each corner, the index of its Gouraud normal.
    let vertexNormal: [Int]
    /// Normals (directions of length 16384). The first `faceNormalCount` belong to faces, the rest
    /// to corners for Gouraud shading.
    let normals: [(x: Int16, y: Int16, z: Int16)]
    let faceNormalCount: Int
    /// The POLY block, byte for byte (the engine walks it as the original did).
    let polygonData: [UInt8]
    /// Order lists: `orders[0]` is the file's ORD0 (all polygons, unsorted), the others are the
    /// ORDE lists, each a back-to-front order for one viewing direction. Each list is words:
    /// length, a vertex index, then polygon offsets, then 0.
    let orders: [[Int]]
    /// Every polygon, decoded, in ORD0's order (for the modern look and for tools).
    let polygons: [VisuPolygon]

    var vertexCount: Int { x.count }
    /// ORD0's vertex: the object's centre point, used to order whole objects by distance.
    var centreVertex: Int { orders[0][1] }

    init(file: String, bytes: [UInt8]) throws {
        let b = VisuBytes(bytes: bytes)
        var name = ""
        var x: [Int32] = [], y: [Int32] = [], z: [Int32] = [], vertexNormal: [Int] = []
        var normals: [(x: Int16, y: Int16, z: Int16)] = []
        var faceNormalCount = 0
        var polygonData: [UInt8] = []
        var first: [Int]? = nil
        var others: [[Int]] = []

        var at = 0
        while true {
            guard at + 8 <= bytes.count else { throw VisuError.badFile(file, "no END block") }
            let tag = b.tag(at)
            let length = b.u32(at + 4)
            let body = at + 8
            guard body + length <= bytes.count else { throw VisuError.badFile(file, "block \(tag) runs past the end") }
            if tag == "END " { break }
            switch tag {
            case "VERS":
                guard b.u16(body) == 0x100 else { throw VisuError.badFile(file, "version is not 1.00") }
            case "NAME":
                var end = body
                while bytes[end] != 0 { end += 1 }
                name = String(decoding: bytes[body..<end], as: UTF8.self)
            case "VERT":
                let count = b.u16(body)
                for i in 0..<count {
                    let p = body + 4 + i * 16
                    x.append(b.s32(p)); y.append(b.s32(p + 4)); z.append(b.s32(p + 8))
                    vertexNormal.append(b.u16(p + 12))
                }
            case "NORM":
                let count = b.u16(body)
                faceNormalCount = b.u16(body + 2)
                for i in 0..<count {
                    let p = body + 4 + i * 8
                    normals.append((b.s16(p), b.s16(p + 2), b.s16(p + 4)))
                }
            case "POLY":
                polygonData = Array(bytes[body..<body + length])
            case "ORD0", "ORDE":
                let list = (0..<length / 2).map { b.u16(body + $0 * 2) }
                if tag == "ORD0" { first = list } else { others.append(list) }
            default:
                throw VisuError.badFile(file, "unknown block \(tag)")
            }
            at = body + length
        }
        guard let first, !x.isEmpty, !polygonData.isEmpty else { throw VisuError.badFile(file, "a block is missing") }

        self.name = name
        self.x = x; self.y = y; self.z = z
        self.vertexNormal = vertexNormal
        self.normals = normals
        self.faceNormalCount = faceNormalCount
        self.polygonData = polygonData
        self.orders = [first] + others

        let p = VisuBytes(bytes: polygonData)
        var polygons: [VisuPolygon] = []
        for offset in first.dropFirst(2) {
            if offset == 0 { break }
            let sides = p.u8(offset)
            polygons.append(VisuPolygon(
                offset: offset,
                flags: UInt16(p.u8(offset + 1)) << 8,
                colour: UInt8(p.u8(offset + 2)),
                normal: p.u16(offset + 4),
                vertices: (0..<sides).map { p.u16(offset + 6 + $0 * 2) }))
        }
        self.polygons = polygons
    }
}

/// One object in a scene: a shape plus where it is. (`co[]` in U2A.C / U2E.C.)
final class VisuObject {
    let mesh: VisuMesh
    /// The object file's number (the `.001` in `U2A.001`).
    let fileNumber: Int
    var flags: UInt16 = VisuFlags.objectDefault
    /// Turn and position in the world, as the animation leaves them ("r0").
    var placement = VisuMatrix.zero
    /// The same after the camera has been applied ("r"): what the engine draws with.
    var inCamera = VisuMatrix.zero
    /// Whether the animation has switched the object on. All objects start off.
    var isOn = false
    /// Distance used to order the objects of a frame.
    var distance: Int32 = 0

    init(mesh: VisuMesh, fileNumber: Int) {
        self.mesh = mesh
        self.fileNumber = fileNumber
    }
}
