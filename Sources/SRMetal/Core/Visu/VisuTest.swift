import Foundation

/// Sets up and draws the engine's test cases (`VisuTestCases`), for the self-test and for the
/// `--visu-test` command-line option. Scenes do not draw through this; it exists so the engine can be
/// checked and looked at by itself.
enum VisuTest {
    /// A test case made ready to draw: the scene's objects with the things to draw placed in
    /// camera space, and the view settings.
    struct Prepared {
        let world: VisuWorld
        /// What to draw, in the 1993 drawing order (farthest first).
        let objects: [VisuObject]
        let fieldOfView: UInt16
        /// 0 = the scenes' window, 1 = the whole screen (see `VisuTestCases.Kind.object`).
        let window: Int
    }

    private static var worlds: [String: VisuWorld] = [:]

    /// A scene's files, loaded once and reused (loading parses up to 42 object files).
    static func world(_ scene: String) throws -> VisuWorld {
        if let world = worlds[scene] { return world }
        let world = try VisuWorld(name: scene)
        if scene == "U2E" { world.distanceRule = VisuWorld.cityOrdering }
        worlds[scene] = world
        return world
    }

    static func prepare(_ kind: VisuTestCases.Kind) throws -> Prepared {
        switch kind {
        case .frame(let scene, let frame):
            let world = try world(scene)
            world.restart()
            for _ in 0..<frame {
                guard world.advance() else { throw VisuError.badFile(scene, "the animation ends before frame \(frame)") }
            }
            return Prepared(world: world, objects: world.prepareFrame(), fieldOfView: world.fieldOfView, window: 0)

        case .run(let scene, let first, _, _):
            return try prepare(.frame(scene: scene, frame: first))

        case .object(let scene, let file, let fieldOfView, let turn, let position, let window):
            let world = try world(scene)
            world.restart()
            guard let object = world.object(fileNumber: file) else {
                throw VisuError.badFile(scene, "no object from file \(file)")
            }
            var r = VisuMatrix()
            r.m = VisuMath.rotationYXZ(x: turn.0, y: turn.1, z: turn.2)
            // Place the object so that its centre point lands on `position`.
            let c = object.mesh.centreVertex
            let (cx, cy, cz) = (Int64(object.mesh.x[c]), Int64(object.mesh.y[c]), Int64(object.mesh.z[c]))
            func offset(_ row: Int) -> Int32 {
                Int32(truncatingIfNeeded: (Int64(r.m[row * 3]) * cx + Int64(r.m[row * 3 + 1]) * cy + Int64(r.m[row * 3 + 2]) * cz) >> 14)
            }
            r.x = position.0 &- offset(0)
            r.y = position.1 &- offset(1)
            r.z = position.2 &- offset(2)
            object.inCamera = r
            return Prepared(world: world, objects: [object], fieldOfView: fieldOfView, window: window)
        }
    }

    static func setWindow(_ window: Int, on engine: VisuEngine) {
        if window == 0 {
            VisuWorld.setSceneWindow(engine)
        } else {
            engine.setWindow(x1: 0, x2: 319, y1: 0, y2: 199, z1: 256, z2: 1_000_000_000)
        }
    }

    /// The 1993 picture of a test case: 320x200 colour numbers, drawn by the engine replay from a
    /// fresh start into a screen of colour 0. Also returns how many faults the engine counted.
    static func classicPicture(_ kind: VisuTestCases.Kind) throws -> (pixels: [UInt8], faults: Int) {
        if case .run(let scene, let first, let last, let every) = kind {
            // Several pictures by one engine; all of them are returned, one after another.
            let world = try world(scene)
            world.restart()
            let engine = VisuEngine()
            VisuWorld.setSceneWindow(engine)
            var all: [UInt8] = []
            while world.frame < last {
                guard world.advance() else { throw VisuError.badFile(scene, "the animation ends before frame \(last)") }
                if world.frame >= first && (world.frame - first) % every == 0 {
                    engine.clear(to: 0)
                    world.draw(with: engine)
                    all += engine.pixels
                }
            }
            return (all, engine.faults)
        }
        let prepared = try prepare(kind)
        let engine = VisuEngine()
        setWindow(prepared.window, on: engine)
        engine.setCameraAngle(prepared.fieldOfView)
        for object in prepared.objects {
            engine.draw(object.mesh, matrix: object.inCamera, flags: object.flags)
        }
        return (engine.pixels, engine.faults)
    }

    /// The palette to show a scene's pictures with: the scene's own 256 colours, as bytes 0...63.
    /// For the ships, U2A.C copies the background picture's first 64 colours into 192...255.
    static func palette(for world: VisuWorld) -> [UInt8] {
        var palette = world.palette
        if world.name == "U2A", let background = try? VisuData.load("U2ABG.UH"), background.count >= 16 + 192 {
            palette.replaceSubrange(192 * 3..<256 * 3, with: background[16..<16 + 192])
        }
        return palette
    }
}
