import Foundation

/// One scene's objects, camera and recorded animation: the state the original scene programs
/// (U2A.C for the ships, U2E.C for the city) kept, and the steps of their main loops.
///
/// A scene is a family of files with one name (see docs/visu-engine.md for the formats):
/// `NAME.00M` (palette + object list), `NAME.001`... (objects), `NAME.0AA` (list of animations)
/// and `NAME.0AB` (the animation: a stream of small changes to object positions, frame by frame).
final class VisuWorld {
    let name: String
    /// 256 colours as the file has them: red, green, blue, each 0...63.
    let palette: [UInt8]
    /// Byte 15 of the `.00M` file: `C` or `R` switched on special object ordering in U2A.C.
    /// It is 0 in both shipped scenes, so those rules never ran.
    let orderingFlag: UInt8
    /// `objects[0]` is the camera (it has no shape); the rest are the scene's objects.
    private(set) var objects: [VisuObject?]
    /// The camera's turn and position.
    private(set) var camera = VisuMatrix.zero
    /// Field of view as the animation last set it (0...65535 = a full turn).
    private(set) var fieldOfView: UInt16 = 0
    /// How many animation frames have been read.
    private(set) var frame = 0
    private(set) var ended = false

    private let stream: [UInt8]
    private var position = 0

    /// A rule that replaces an object's distance when the objects of a frame are ordered:
    /// (object, its index, animation frame) -> distance, or nil to keep the measured one.
    /// Bigger distances are drawn first. See `cityOrdering`.
    var distanceRule: ((VisuObject, Int, Int) -> Int32?)?

    /// The total number of frames in the animation (found by reading it through once).
    private(set) lazy var frameCount: Int = {
        let copy = VisuWorld(copying: self)
        var count = 0
        while copy.advance() { count += 1 }
        return count
    }()

    /// `load` reads one of the scene's files by name. It is the app's data folder unless something
    /// else is handed in (the self-test hands in deliberately damaged files).
    init(name: String, load: (String) throws -> [UInt8] = VisuData.load) throws {
        self.name = name
        let materials = try load("\(name).00M")
        guard materials.count >= 16 + 768 else { throw VisuError.badFile("\(name).00M", "too short") }
        let m = VisuBytes(bytes: materials)
        // Colour levels are 0...63; a VGA card ignored a level's top two bits, so a damaged byte cannot
        // become a level the rest of the app is not ready for.
        palette = materials[16..<16 + 768].map { $0 & 63 }
        orderingFlag = materials[15]

        // The object list: a count (which includes the camera), then one file number per object.
        // A number seen before means "another copy of that object".
        // Both numbers come from the file; they are checked before anything is read by them.
        // (U2A.C / U2E.C have room for 256 objects, `MAXOBJ`.)
        let list = m.u32(4)
        guard list + 2 <= materials.count else {
            throw VisuError.badFile("\(name).00M", "the object list is placed outside the file (\(list))")
        }
        let count = m.u16(list)
        guard count >= 1, count <= 256, list + count * 2 <= materials.count else {
            throw VisuError.badFile("\(name).00M", "the object list cannot hold \(count) objects")
        }
        var objects: [VisuObject?] = [nil]
        var meshes: [Int: VisuMesh] = [:]
        for c in 1..<count {
            let number = m.u16(list + c * 2)
            if meshes[number] == nil {
                let file = String(format: "%@.%03d", name, number)
                meshes[number] = try VisuMesh(file: file, bytes: try load(file))
            }
            objects.append(VisuObject(mesh: meshes[number]!, fileNumber: number))
        }
        self.objects = objects

        // The list of animations: pairs of words, ended by -1. Both scenes have exactly one.
        let animations = VisuBytes(bytes: try load("\(name).0AA"))
        guard animations.bytes.count >= 2 else { throw VisuError.badFile("\(name).0AA", "too short") }
        let first = animations.u16(0)
        // The number becomes two letters, A...Z each (U2A.C: `a/10+'A'`, `a%10+'A'`).
        guard first < 260 else { throw VisuError.badFile("\(name).0AA", "animation number \(first)") }
        let letters = String(UnicodeScalar(UInt8(65 + first / 10))) + String(UnicodeScalar(UInt8(65 + first % 10)))
        stream = try load("\(name).0\(letters)")
    }

    /// The camera's turn and position in every frame of the animation: element 0 is before the
    /// first frame (all zero), element n is animation frame n. Found by reading the animation
    /// through once on a copy; this world is not touched.
    func cameraTrack() -> [VisuMatrix] {
        let copy = VisuWorld(copying: self)
        var track = [copy.camera]
        while copy.advance() { track.append(copy.camera) }
        return track
    }

    private init(copying other: VisuWorld) {
        name = other.name
        palette = other.palette
        orderingFlag = other.orderingFlag
        objects = other.objects.map { $0.map { VisuObject(mesh: $0.mesh, fileNumber: $0.fileNumber) } }
        stream = other.stream
    }

    /// Back to the start: every object off and at zero, the camera at zero.
    func restart() {
        position = 0
        frame = 0
        ended = false
        fieldOfView = 0
        camera = .zero
        for object in objects {
            object?.placement = .zero
            object?.inCamera = .zero
            object?.isOn = false
        }
    }

    /// The first object made from object file `number`.
    func object(fileNumber number: Int) -> VisuObject? {
        objects.compactMap { $0 }.first { $0.fileNumber == number }
    }

    // MARK: The animation stream

    /// Reads one frame of the animation. Returns false (and changes nothing more) once the
    /// stream's end marker has been reached.
    ///
    /// A frame is a run of records, one per object that changed. Each record names an object
    /// (0 = the camera), may switch it on or off, and holds only the DIFFERENCES from the frame
    /// before, each stored in as few bytes as it needs. The frame ends with FF + the field of view.
    @discardableResult
    func advance() -> Bool {
        if ended { return false }
        var number = 0
        // The stream is followed byte by byte with nothing to say how long a frame is, so every
        // read checks that it is still inside the file. A stream that stops early (a damaged
        // file) simply ends the animation there.
        while true {
            guard var a = nextByte() else { ended = true; return false }
            if a == 0xFF {
                guard let b = nextByte() else { ended = true; return false }
                a = b
                if a <= 0x7F {
                    fieldOfView = UInt16(a) << 8
                    break
                } else if a == 0xFF {
                    ended = true
                    return false
                }
            }
            if a & 0xC0 == 0xC0 {
                number = (a & 0x3F) << 4
                guard let b = nextByte() else { ended = true; return false }
                a = b
            }
            number = (number & 0xFF0) | (a & 0xF)
            guard number < objects.count else { ended = true; return false }
            switch a & 0xC0 {
            case 0x80: objects[number]?.isOn = true
            case 0x40: objects[number]?.isOn = false
            default: break
            }

            var r = number == 0 ? camera : objects[number]!.placement
            var changed = 0
            for i in 0..<((a & 0x30) >> 4) {
                guard let b = nextByte() else { ended = true; return false }
                changed |= b << (8 * i)
            }
            // How many bytes the changes themselves take, to check them all at once.
            let size = changed & 0x40 != 0 ? 2 : 1
            var bytes = 0
            for shift in [0, 2, 4] { bytes += [0, 1, 2, 4][(changed >> shift) & 3] }
            for b in 0..<9 where changed & (0x80 << b) != 0 { bytes += size }
            guard position + bytes <= stream.count else { ended = true; return false }

            r.x = r.x &+ signed(bytes: changed & 3)
            r.y = r.y &+ signed(bytes: (changed >> 2) & 3)
            r.z = r.z &+ signed(bytes: (changed >> 4) & 3)
            for b in 0..<9 where changed & (0x80 << b) != 0 {
                r.m[b] = r.m[b] &+ signed(bytes: size)
            }
            if number == 0 { camera = r } else { objects[number]!.placement = r }
        }
        frame += 1
        return true
    }

    /// The stream's next byte, or nil at its end.
    private func nextByte() -> Int? {
        guard position < stream.count else { return nil }
        defer { position += 1 }
        return Int(stream[position])
    }

    /// `lsget`: a signed number stored in 0, 1, 2 or 4 bytes (`code` 0, 1, 2, 3). The caller has
    /// checked that the bytes are there.
    private func signed(bytes code: Int) -> Int32 {
        switch code {
        case 1:
            defer { position += 1 }
            return Int32(Int8(bitPattern: stream[position]))
        case 2:
            defer { position += 2 }
            return Int32(Int16(bitPattern: UInt16(stream[position]) | UInt16(stream[position + 1]) << 8))
        case 3:
            defer { position += 4 }
            let v = UInt32(stream[position]) | UInt32(stream[position + 1]) << 8
                | UInt32(stream[position + 2]) << 16 | UInt32(stream[position + 3]) << 24
            return Int32(bitPattern: v)
        default:
            return 0
        }
    }

    // MARK: Drawing a frame

    /// What the scene programs do for each picture, after clearing the screen: set the field of
    /// view, bring each switched-on object into camera space, order the objects farthest first by
    /// the depth of each one's centre point, and return them in drawing order.
    func prepareFrame() -> [VisuObject] {
        var order: [Int] = []
        for a in 1..<objects.count {
            guard let o = objects[a], o.isOn else { continue }
            order.append(a)
            o.inCamera = o.placement
            VisuMath.apply(&o.inCamera, camera: camera)
            let c = o.mesh.centreVertex
            o.distance = VisuMath.depth(of: (o.mesh.x[c], o.mesh.y[c], o.mesh.z[c]), through: o.inCamera)
            if let replaced = distanceRule?(o, a, frame) { o.distance = replaced }
        }
        // The original's insertion sort: objects at equal distance keep their list order.
        for a in 0..<order.count {
            let c = order[a]
            let distance = objects[c]!.distance
            var b = a - 1
            while b >= 0 && distance > objects[order[b]]!.distance {
                order[b + 1] = order[b]
                b -= 1
            }
            order[b + 1] = c
        }
        return order.map { objects[$0]! }
    }

    /// Draws the current state with the 1993 engine into `engine.pixels` (which the caller has
    /// cleared or filled with a background first).
    func draw(with engine: VisuEngine) {
        engine.setCameraAngle(fieldOfView)
        for object in prepareFrame() {
            engine.draw(object.mesh, matrix: object.inCamera, flags: object.flags)
        }
    }

    // MARK: The two scene programs' settings

    /// Both U2A.C and U2E.C: `vid_window(0L,319L,25L,174L,512L,9999999L)`: a 320x150 band in the
    /// middle of the 320x200 screen, nothing nearer than 512.
    static func setSceneWindow(_ engine: VisuEngine) {
        engine.setWindow(x1: 0, x2: 319, y1: 25, y2: 174, z1: 512, z2: 9_999_999)
    }

    /// U2E.C's ordering rules: objects whose name starts with an underscore (ground plates) are
    /// always drawn first; and for animation frames 901...1099 the ship ("s01") is always drawn
    /// last. (U2E.C tests `currframe`, which counts in twos: 900*2 < currframe < 1100*2.)
    static let cityOrdering: (VisuObject, Int, Int) -> Int32? = { object, _, frame in
        let name = Array(object.mesh.name.utf8)             // names are stored WITH their quotes: "s01"
        var result: Int32? = nil
        if name.count > 1, name[1] == UInt8(ascii: "_") { result = 1_000_000_000 }
        if frame > 900, frame < 1100, name.count > 3,
           name[1] == UInt8(ascii: "s"), name[2] == UInt8(ascii: "0"), name[3] == UInt8(ascii: "1") {
            result = 1
        }
        return result
    }
}
