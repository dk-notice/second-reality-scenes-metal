import Foundation

/// A check that damaged data files cannot crash the program.
///
/// The 3D engine's files (`Data/Visu`; other scenes' data files have their own load checks) are full of counts
/// and positions that the loader has to trust: "this block is so long", "this polygon uses corner
/// number so-and-so". A file cut short, or with one number wrong, must be turned away with a clear
/// error (`VisuError.badFile`); and whatever does get through must draw without stepping outside
/// any list. This feeds the loader deliberately damaged copies of the real ships files and plays
/// and draws everything that loads. It can only fail by crashing, so "it came back" is the test.
///
/// Used by the self-test and by `--visu-test damaged`.
enum VisuDamagedFiles {
    struct Result {
        /// Damaged files tried, how many were turned away with an error, how many loaded.
        var tried = 0, refused = 0, loaded = 0
        /// How many of those were the named cases (one known kind of damage each).
        var named = 0
        /// Named cases that were expected to be turned away but loaded.
        var wronglyAccepted: [String] = []
        /// Made-up scribble polygons drawn, and how often the engine stopped one growing.
        var scribbles = 0, scribblesStopped = 0
        var summary: String {
            "\(tried) damaged files (\(named) named cases): \(refused) turned away, \(loaded) loaded and drawn; "
                + "\(scribbles) scribbled polygons drawn, \(scribblesStopped) corners refused"
        }
    }

    /// Whole numbers in a fixed "random" order, the same on every run.
    private struct Dice {
        var state: UInt32 = 12345
        mutating func roll(_ below: Int) -> Int {
            state = state &* 1_103_515_245 &+ 12345
            return Int((state >> 8) % UInt32(max(below, 1)))
        }
    }

    /// Where a block's contents start in an object file, and how long they are.
    private static func block(_ tag: String, in bytes: [UInt8]) -> (body: Int, length: Int)? {
        let b = VisuBytes(bytes: bytes)
        var at = 0
        while at + 8 <= bytes.count {
            let length = b.u32(at + 4)
            if b.tag(at) == tag { return (at + 8, length) }
            at += 8 + length
        }
        return nil
    }

    private static func setWord(_ bytes: inout [UInt8], _ at: Int, _ value: Int) {
        bytes[at] = UInt8(value & 255); bytes[at + 1] = UInt8((value >> 8) & 255)
    }

    /// Object files damaged in one chosen way each. All of these must be turned away.
    static func namedObjectCases(_ original: [UInt8]) -> [(name: String, bytes: [UInt8])] {
        var cases: [(String, [UInt8])] = []
        func damaged(_ name: String, _ change: (inout [UInt8]) -> Void) {
            var copy = original
            change(&copy)
            cases.append((name, copy))
        }
        guard let name = block("NAME", in: original), let vert = block("VERT", in: original),
              let norm = block("NORM", in: original), let poly = block("POLY", in: original),
              let ord0 = block("ORD0", in: original), let orde = block("ORDE", in: original) else { return [] }
        let firstPolygon = poly.body + VisuBytes(bytes: original).u16(ord0.body + 4)
        damaged("name without an end") { for i in name.body..<name.body + name.length { $0[i] = 120 } }
        damaged("more corners than the block holds") { setWord(&$0, vert.body, 0xFFFF) }
        damaged("more normals than the block holds") { setWord(&$0, norm.body, 0xFFFF) }
        damaged("more face normals than normals") { setWord(&$0, norm.body + 2, 0xFFFF) }
        damaged("centre point that is not a corner") { setWord(&$0, ord0.body + 2, 0xFFFF) }
        damaged("direction point that is not a corner") { setWord(&$0, orde.body + 2, 0xFFFF) }
        damaged("polygon position outside the polygon block") { setWord(&$0, ord0.body + 4, 0xFFF0) }
        damaged("polygon position at the block's last byte") { setWord(&$0, ord0.body + 4, poly.length - 1) }
        damaged("polygon with 200 corners") { $0[firstPolygon] = 200 }
        damaged("polygon with no corners") { $0[firstPolygon] = 0 }
        damaged("polygon corner that does not exist") { setWord(&$0, firstPolygon + 6, 0xFFFF) }
        damaged("polygon normal that does not exist") { setWord(&$0, firstPolygon + 4, 0xFFFF) }
        damaged("block longer than the file") { setWord(&$0, vert.body - 2, 0x7FFF) }
        damaged("order list of one word") { setWord(&$0, ord0.body - 4, 2); setWord(&$0, ord0.body - 2, 0) }
        damaged("cut off in the first block") { $0.removeSubrange(6...) }
        damaged("cut off before the END block") { $0.removeLast(8) }
        damaged("empty file") { $0.removeAll() }
        return cases
    }

    /// Scene files damaged in one chosen way each: (which file, new contents, must be turned away).
    static func namedSceneCases(_ files: [String: [UInt8]], scene: String) -> [(name: String, file: String, bytes: [UInt8], mustRefuse: Bool)] {
        var cases: [(String, String, [UInt8], Bool)] = []
        func damaged(_ name: String, _ file: String, mustRefuse: Bool = true, _ change: (inout [UInt8]) -> Void) {
            guard var copy = files[file] else { return }
            change(&copy)
            cases.append((name, file, copy, mustRefuse))
        }
        let list = 784
        damaged("object list placed outside the file", "\(scene).00M") { setWord(&$0, 4, 0xFFFF); setWord(&$0, 6, 0x00FF) }
        damaged("object list placed at the last byte", "\(scene).00M") { setWord(&$0, 4, $0.count - 1) }
        damaged("no objects, not even the camera", "\(scene).00M") { setWord(&$0, list, 0) }
        damaged("more objects than the file lists", "\(scene).00M") { setWord(&$0, list, 300) }
        damaged("scene file cut off in the palette", "\(scene).00M") { $0.removeSubrange(500...) }
        damaged("scene file cut off in the object list", "\(scene).00M") { $0.removeLast(3) }
        damaged("empty list of animations", "\(scene).0AA") { $0.removeAll() }
        damaged("one-byte list of animations", "\(scene).0AA") { $0.removeSubrange(1...) }
        damaged("animation number with no file letters", "\(scene).0AA") { setWord(&$0, 0, 5000) }
        // A damaged animation is not turned away (finding the damage means playing it); it must
        // simply stop where the damage is.
        damaged("animation cut off inside a record", "\(scene).0AB", mustRefuse: false) { $0.removeSubrange(10...) }
        damaged("animation cut off after an FF", "\(scene).0AB", mustRefuse: false) { $0.removeSubrange(40...); $0.append(0xFF) }
        damaged("animation cut off inside a long number", "\(scene).0AB", mustRefuse: false) {
            $0.removeSubrange(4...); $0 += [0x30, 0xFF, 0xFF, 0xFF, 0x01]
        }
        damaged("animation naming an object that does not exist", "\(scene).0AB", mustRefuse: false) { $0.insert(contentsOf: [0xFF, 0x80, 0x0F], at: 0) }
        damaged("animation without its end mark", "\(scene).0AB", mustRefuse: false) { $0.removeLast(2) }
        damaged("empty animation", "\(scene).0AB", mustRefuse: false) { $0.removeAll() }
        return cases
    }

    /// An object file made up here: ONE flat, two-sided polygon of 16 corners at the given places
    /// (all at the same distance, 2000), plus a centre point. Real polygons are convex; these are
    /// scribbles, which is the point (see `VisuEngine.mostClippedCorners`).
    static func scribble(_ corners: [(x: Int32, y: Int32)]) -> [UInt8] {
        var file: [UInt8] = []
        func word(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255)] }
        func long(_ v: Int32) -> [UInt8] { let u = UInt32(bitPattern: v); return word(Int(u & 0xFFFF)) + word(Int(u >> 16)) }
        func block(_ tag: String, _ body: [UInt8]) {
            file += Array(tag.utf8) + word(body.count) + word(0) + body
        }
        block("VERS", word(0x100))
        block("NAME", Array("\"scribble\"".utf8) + [0])
        var vertices = word(corners.count + 1) + word(0)
        for c in corners + [(x: 0, y: 0)] { vertices += long(c.x) + long(c.y) + long(2000) + word(0) + word(0) }
        block("VERT", vertices)
        block("NORM", word(1) + word(1) + word(0) + word(0) + word(-16384 & 0xFFFF) + word(0))
        // corners, flags (two-sided, 16 shades), colour, unused, normal, then the corner numbers
        var polygon = word(0) + [UInt8(corners.count), 0x0A, 32, 0] + word(0)
        for i in 0..<corners.count { polygon += word(i) }
        block("POLY", polygon)
        block("ORD0", word(4) + word(corners.count) + word(2) + word(0))
        block("END ", [])
        return file
    }

    /// A scribble found by search (during the code review of 2026-11-14) that the four window
    /// edges cut into more than 40 corners. Before the engine limited that growth, drawing it
    /// wrote past the end of the engine's polygon records and the program stopped.
    static let worstScribble: [(x: Int32, y: Int32)] = [
        (930, 112), (-2393, 1316), (1771, -1055), (-2688, 2026), (544, -1980), (-1739, 1522), (1274, -739), (-1854, 1127),
        (1485, -1441), (-1984, 1079), (2899, -970), (-1252, 64), (2130, 790), (-2405, -1167), (275, 554), (-1524, -903)]

    /// Draws the worst scribble and `count` made-up ones. Returns how many corners the engine
    /// refused (each counted as a fault): more than none shows the limit was reached and held.
    static func drawScribbles(_ count: Int, with engine: VisuEngine) throws -> Int {
        var dice = Dice(state: 777)
        let before = engine.faults
        engine.setCameraAngle(8704)
        engine.draw(try VisuMesh(file: "scribble", bytes: scribble(worstScribble)), matrix: .identity)
        for _ in 0..<count {
            let corners = (0..<16).map { _ in (x: Int32(dice.roll(6000) - 3000), y: Int32(dice.roll(4000) - 2000)) }
            let mesh = try VisuMesh(file: "scribble", bytes: scribble(corners))
            engine.draw(mesh, matrix: .identity)
        }
        return engine.faults - before
    }

    /// Draws a freshly loaded object twice: far away, and across the near plane and window edges.
    private static func draw(_ mesh: VisuMesh, with engine: VisuEngine) {
        var far = VisuMatrix.identity
        far.z = 3000
        var near = VisuMatrix()
        near.m = VisuMath.rotationYXZ(x: 8000, y: 20000, z: 3000)
        near.x = 150; near.y = -80; near.z = 560
        engine.setCameraAngle(8704)
        engine.draw(mesh, matrix: far)
        engine.draw(mesh, matrix: near)
        let c = mesh.centreVertex
        _ = VisuMath.depth(of: (mesh.x[c], mesh.y[c], mesh.z[c]), through: near)
    }

    /// Plays a scene to its end, drawing every 16th frame.
    private static func play(_ world: VisuWorld, with engine: VisuEngine) {
        var frames = 0
        while world.advance() && frames < 3000 {
            frames += 1
            if frames % 16 == 0 {
                engine.clear(to: 0)
                world.draw(with: engine)
                _ = world.pose()
            }
        }
    }

    /// Runs everything. `only` limits it to the named cases whose name contains that text (for
    /// `--visu-test damaged <text>`); `report` is called with one line per named case.
    static func run(only: String? = nil, report: (String) -> Void = { _ in }) throws -> Result {
        var result = Result()
        var dice = Dice()
        let engine = VisuEngine()
        VisuWorld.setSceneWindow(engine)
        let scene = "U2A"
        var files: [String: [UInt8]] = [:]
        for name in ["\(scene).00M", "\(scene).001", "\(scene).002", "\(scene).003", "\(scene).0AA", "\(scene).0AB"] {
            files[name] = try VisuData.load(name)
        }

        func tryObject(_ label: String?, _ bytes: [UInt8], mustRefuse: Bool) {
            result.tried += 1
            do {
                let mesh = try VisuMesh(file: "damaged", bytes: bytes)
                result.loaded += 1
                draw(mesh, with: engine)
                if let label {
                    if mustRefuse { result.wronglyAccepted.append(label) }
                    report("loaded   \(label)")
                }
            } catch {
                result.refused += 1
                if let label { report("refused  \(label): \(error)") }
            }
        }
        func tryScene(_ label: String?, file: String, _ bytes: [UInt8], mustRefuse: Bool) {
            result.tried += 1
            do {
                let world = try VisuWorld(name: scene) { name in
                    if name == file { return bytes }
                    guard let original = files[name] else { throw VisuError.missingFile(name) }
                    return original
                }
                result.loaded += 1
                play(world, with: engine)
                if let label {
                    if mustRefuse { result.wronglyAccepted.append(label) }
                    report("loaded   \(label): played \(world.frame) frames")
                }
            } catch {
                result.refused += 1
                if let label { report("refused  \(label): \(error)") }
            }
        }

        // 1. Named cases: one known kind of damage each.
        for (name, bytes) in namedObjectCases(files["\(scene).001"]!) where only == nil || name.contains(only!) {
            tryObject(name, bytes, mustRefuse: true)
            result.named += 1
        }
        for (name, file, bytes, mustRefuse) in namedSceneCases(files, scene: scene) where only == nil || name.contains(only!) {
            tryScene(name, file: file, bytes, mustRefuse: mustRefuse)
            result.named += 1
        }
        if let only {
            if "scribble".contains(only) {
                result.scribbles = 1
                result.scribblesStopped = try drawScribbles(0, with: engine)
            }
            return result
        }

        // 2. Polygons no real file holds: zig-zags that gain corners every time they are cut.
        result.scribbles = 401
        result.scribblesStopped = try drawScribbles(400, with: engine)

        // 3. Blind damage, the same on every run: files cut short at many lengths, and files with
        //    one byte or one two-byte number changed.
        for name in ["\(scene).001", "\(scene).002"] {
            let original = files[name]!
            for length in Array(0..<48) + (0..<120).map({ _ in dice.roll(original.count) }) {
                tryObject(nil, Array(original[..<length]), mustRefuse: false)
            }
            for _ in 0..<700 {
                var copy = original
                let at = dice.roll(copy.count - 1)
                switch dice.roll(4) {
                case 0: copy[at] = UInt8(dice.roll(256))
                case 1: setWord(&copy, at, 0xFFFF)
                case 2: setWord(&copy, at, 0)
                default: setWord(&copy, at, dice.roll(65536))
                }
                tryObject(nil, copy, mustRefuse: false)
            }
        }
        for name in ["\(scene).00M", "\(scene).0AA", "\(scene).0AB"] {
            let original = files[name]!
            let tail = name.hasSuffix("00M") ? 784 : 0          // nothing before the object list matters
            var lengths = Array(0..<min(24, original.count)) + (0..<60).map { _ in tail + dice.roll(original.count - tail) }
            if tail > 0 { lengths += Array(tail..<original.count) }
            for length in lengths {
                tryScene(nil, file: name, Array(original[..<length]), mustRefuse: false)
            }
            for _ in 0..<150 {
                var copy = original
                let at = name.hasSuffix("00M") && dice.roll(2) == 0 ? (dice.roll(2) == 0 ? 4 + dice.roll(4) : tail + dice.roll(original.count - tail))
                                                                    : dice.roll(copy.count)
                copy[at] = UInt8(dice.roll(256))
                tryScene(nil, file: name, copy, mustRefuse: false)
            }
        }
        return result
    }
}
