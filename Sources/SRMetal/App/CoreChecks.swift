import CoreGraphics
import Foundation
import Metal
import simd

/// Self-test checks for the code every scene shares (`Core/`) and for the app's command line.
/// Added by the code review of 2026-11-14; run first by `SelfTest.run()`.
///
/// This file has `run`, which calls every check in order, and the checks of the shared code and the
/// command line. The others live next to what they check, as extensions of this type:
/// `Scenes/<Name>/<Name>Checks.swift` (rotozoomer, lens, jelly logo, mountain scroller, water scroller),
/// `Demo/DemoChecks.swift`, `Music/MusicChecks.swift` and `Core/PictureChecks.swift`. A new scene's
/// checks go in its own folder the same way, with one line added to `run`.
///
/// Each check here either pins down a bug that review found and fixed (it fails on the code as
/// it was before), or checks a rule that the scenes rely on but nothing was testing.
enum CoreChecks {
    static func run(_ report: (String, Bool, String) -> Void) {
        func check(_ name: String, _ passed: Bool, _ detail: String = "") { report(name, passed, detail) }

        if SelfTest.wants("core catalogue scene list") { catalogue(check) }
        if SelfTest.wants("core clock") { clock(check) }
        if SelfTest.wants("core letterbox") { letterbox(check) }
        if SelfTest.wants("core app command line") { commandLine(check) }
        if SelfTest.wants("core math3d") { math3D(check) }
        if SelfTest.wants("core smooth triangles") { smoothTriangleGeometry(check) }
        if SelfTest.wants("music") { music(check) }
        if SelfTest.wants("demo play-demo timeline techno-bars interference troll switch-off end-picture title-picture end-scroller") { demoTimeline(check) }
        if SelfTest.wants("demo play-demo from here") { demoFromHere(check) }
        if SelfTest.wants("rotozoomer") { rotozoomerTiming(check) }
        if SelfTest.wants("opening-credits opening") { openingCredits(check) }
        if SelfTest.wants("credits") { credits(check) }
        if SelfTest.wants("video export demo") { videoExport(check) }

        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            check("Core: Metal device available", false)
            return
        }
        do {
            if SelfTest.wants("core indexed canvas") { try indexedCanvas(check, device: device, queue: queue) }
            if SelfTest.wants("core smooth triangles") { try smoothTrianglesDrawn(check, device: device, queue: queue) }
            if SelfTest.wants("core app snapshot") { try snapshots(check) }
            if SelfTest.wants("core picture scaler") { try pictureScaler(check, device: device, queue: queue) }
            if SelfTest.wants("core picture fades title-picture end-picture") { try pictureFades(check, device: device, queue: queue) }
            if SelfTest.wants("rotozoomer") { try rotozoomerPictures(check, device: device) }
            if SelfTest.wants("lens demo") { try lens(check, device: device) }
            if SelfTest.wants("jelly-logo jelly logo demo") { try jellyLogo(check, device: device) }
            if SelfTest.wants("mountain-scroller mountain demo") { try mountain(check, device: device) }
            if SelfTest.wants("water-scroller water demo") { try water(check, device: device) }
            if SelfTest.wants("ships-flyby ships demo") { try shipsInDemo(check, device: device) }
            if SelfTest.wants("sine-landscape landscape demo") { try landscapeInDemo(check, device: device) }
            if SelfTest.wants("plasma-cube plasma cube demo") { try plasmaCubeInDemo(check, device: device) }
            if SelfTest.wants("plasma demo") { try plasmaInDemo(check, device: device) }
            if SelfTest.wants("interference techno lead-in demo") { try interferenceInDemo(check, device: device) }
            if SelfTest.wants("opening-credits opening demo") { try openingCreditsInDemo(check, device: device) }
            if SelfTest.wants("credits demo") { try creditsInDemo(check, device: device) }
            if SelfTest.wants("city-3d city jelly-logo demo") { try cityInDemo(check, device: device) }
            if SelfTest.wants("glenz-vectors glenz title-picture demo") { try glenzInDemo(check, device: device) }
            if SelfTest.wants("demo play-demo from here troll lens credits") { try demoFromHereShown(check, device: device) }
        } catch {
            check("Core: drawing checks could be set up", false, "\(error)")
        }
    }

    // MARK: - The scene list

    private static func catalogue(_ check: (String, Bool, String) -> Void) {
        let all = SceneCatalog.all
        // The self-test's scene loops pass without checking anything if the list is empty, and
        // look scenes up by id.
        check("Core: the scene list is not empty and every scene id is different",
              !all.isEmpty && Set(all.map(\.id)).count == all.count && !all.contains { $0.id.isEmpty }, "\(all.count) scenes")
        // The checkpoint loop only ever steps forwards, so a list out of order would be compared at
        // the wrong step without saying so; and a scene with no checkpoints would not be compared at all.
        let badOrder = all.filter { entry in
            entry.checkpoints.isEmpty || entry.checkpoints[0] < 0
                || zip(entry.checkpoints, entry.checkpoints.dropFirst()).contains { $0 >= $1 }
        }
        check("Core: every scene has checkpoints, in rising order", badOrder.isEmpty,
              badOrder.map(\.id).joined(separator: ", "))
        let badSize = all.filter { entry in
            let size = entry.canvasSize
            return size.x < 1 || size.y < 1 || size.x != size.x.rounded() || size.y != size.y.rounded() || entry.thumbnailStep < 0
        }
        check("Core: every scene's canvas is a whole number of pixels and its list-picture step is not negative",
              badSize.isEmpty, badSize.map(\.id).joined(separator: ", "))
    }

    // MARK: - The clock

    private static func clock(_ check: (String, Bool, String) -> Void) {
        // Ten seconds on displays of different speeds: 700 steps each time (give or take one for
        // rounding), never more steps in one frame than the display's speed calls for, and the
        // "how far into the next step" number always from 0 up to but not including 1.
        var faults: [String] = []
        for rate in [50.0, 60.0, 70.0, 100.0, 120.0, 144.0] {
            var clock = StepClock()
            var total = 0, most = 0
            var alphaOK = true, evenOK = true
            var position = 0.0
            for _ in 0..<Int(rate * 10) {
                let due = clock.advance(by: 1 / rate)
                total += due.steps
                most = max(most, due.steps)
                if !(due.alpha >= 0 && due.alpha < 1) { alphaOK = false }
                // Steps done plus the fraction must move on by the same amount every frame:
                // that is what makes the modern look's motion even.
                let now = Double(total) + Double(due.alpha)
                if abs(now - position - 70 / rate) > 0.0001 { evenOK = false }
                position = now
            }
            if abs(total - 700) > 1 || most > Int((70 / rate).rounded(.up)) || !alphaOK || !evenOK {
                faults.append("\(Int(rate)) Hz: \(total) steps, \(most) at most in a frame, alpha ok \(alphaOK), even \(evenOK)")
            }
        }
        check("Core clock: 70 steps a second, evenly, on 50 to 144 Hz displays", faults.isEmpty, faults.joined(separator: "; "))

        // Found by the review: the fraction could round up to exactly 1.
        var nearly = StepClock()
        let justUnder = nearly.advance(by: StepClock.step.nextDown)
        check("Core clock: the fraction of a step never reaches 1", justUnder.steps == 0 && justUnder.alpha < 1,
              "\(justUnder.steps) steps, fraction \(justUnder.alpha)")

        var paused = StepClock()
        _ = paused.advance(by: 0.005)
        let afterPause = paused.advance(by: 3600)
        var backwards = StepClock()
        let negative = backwards.advance(by: -1)
        check("Core clock: after a long pause it catches up on a quarter of a second only, and never runs backwards",
              afterPause.steps == 17 && afterPause.alpha >= 0 && afterPause.alpha < 1
                  && negative.steps == 0 && negative.alpha == 0 && backwards.owed == 0,
              "\(afterPause.steps) steps after an hour's pause")
        // Play Demo's music does not stall with the picture: a stall is made up in full, to 5 seconds.
        var demo = StepClock(), demoLong = StepClock()
        let stall = demo.advance(by: 1, longest: DemoRunScene.longestCatchUp)
        let longStall = demoLong.advance(by: 3600, longest: DemoRunScene.longestCatchUp)
        let runScene = MTLCreateSystemDefaultDevice().flatMap {
            try? DemoRunScene(device: $0, pixelFormat: Renderer.pixelFormat, music: SilentMusic())
        }
        check("Core clock: inside Play Demo a 1-second stall is made up in full (70 steps; 350 at most), a scene on its own keeps the quarter second",
              stall.steps == 70 && longStall.steps == 350 && runScene?.longestCatchUp == 5
                && SceneCatalog.all.first.flatMap { e in MTLCreateSystemDefaultDevice().flatMap { try? e.make($0, Renderer.pixelFormat) } }?.longestCatchUp == 0.25,
              "\(stall.steps) steps after 1 s, \(longStall.steps) after an hour")
    }

    // MARK: - The 4:3 picture area

    private static func letterbox(_ check: (String, Bool, String) -> Void) {
        func box(_ width: Double, _ height: Double) -> [Double] {
            let b = Renderer.letterbox(width: width, height: height)
            return [b.originX, b.originY, b.width, b.height]
        }
        check("Core: the picture area is the largest centred 4:3 rectangle (exact fit, wide window, tall window, no window)",
              box(960, 720) == [0, 0, 960, 720] && box(1920, 1080) == [240, 0, 1440, 1080]
                  && box(1000, 2000) == [0, 625, 1000, 750] && box(0, 0) == [0, 0, 0, 0],
              "\(box(1920, 1080)) \(box(1000, 2000))")
    }

    // MARK: - Command lines

    private static func commandLine(_ check: (String, Bool, String) -> Void) {
        func options(_ words: String) -> StartupOptions {
            StartupOptions(arguments: ["SRMetal"] + words.split(separator: " ").map(String.init))
        }
        let good = options("--scene plasma --look classic --sidebar hidden")
        let system = options("-NSDocumentRevisionsDebugMode YES -AppleLanguages (en)")
        check("App: start-up options are understood, and macOS's own single-dash options are left alone",
              good.problems.isEmpty && good.look == .classic && good.sidebarHidden
                  && good.sceneIndex == SceneCatalog.all.firstIndex(where: { $0.id == "plasma" })
                  && options("").problems.isEmpty && options("").look == nil && options("").sceneIndex == nil
                  && system.problems.isEmpty
                  && options("--scene play-demo --from troll").problems.isEmpty
                  && options("--from 11 --scene play-demo").demoStart == .part(10),
              (good.problems + system.problems).joined(separator: "; "))
        // Demo first (user, 2026-11-25): with no scene asked for the app starts as a demo does.
        let plain = options(""), scene = options("--scene plasma"), demo = options("--scene play-demo --from troll")
        check("App: with no scene asked for it starts in Play Demo with the scene list hidden; asked for a scene it starts on it with the list showing; --sidebar decides either way",
              plain.startsWithDemo && plain.startsWithSidebarHidden && plain.demoStart == nil
                && !scene.startsWithDemo && !scene.startsWithSidebarHidden
                && demo.startsWithDemo && demo.startsWithSidebarHidden && demo.demoStart == .scene("troll")
                && !options("--sidebar shown").startsWithSidebarHidden && options("--sidebar shown").startsWithDemo
                && options("--scene plasma --sidebar hidden").startsWithSidebarHidden
                && !options("--look classic --music off").problems.contains { !$0.isEmpty }
                && options("--look classic --music off").startsWithDemo,
              "plain: demo \(plain.startsWithDemo), list hidden \(plain.startsWithSidebarHidden); scene: demo \(scene.startsWithDemo), list hidden \(scene.startsWithSidebarHidden)")
        // Stopping the demo goes over to choosing: the list opens on the scene the demo was showing.
        do {
            let model = AppModel()   // (the self-test's own command line names no scene: it starts in the demo)
            let startedInDemo = model.playingDemo && model.entry.id == DemoRunScene.id
            model.columns = .detailOnly
            model.browse(from: "troll")
            let onTroll = !model.playingDemo && model.entry.id == "troll" && model.columns == .all
            model.playDemo()
            model.columns = .detailOnly
            model.browse(from: nil)          // stopped before the demo had shown a scene
            let stays = !model.playingDemo && model.entry.id == "troll" && model.columns == .all
            model.playDemo()
            let again = model.playingDemo && model.entry.id == DemoRunScene.id
            model.sceneIndex = 0             // a scene chosen in the list
            let chosen = !model.playingDemo && model.entry.id == SceneCatalog.all[0].id
            check("App: stopping Play Demo opens the scene list on the scene the demo was showing (or the one last chosen, before its first); choosing a scene leaves the demo; Play Demo starts it again",
                  startedInDemo && onTroll && stays && again && chosen,
                  "started in the demo \(startedInDemo), on the troll \(onTroll), stays \(stays), again \(again), chosen \(chosen)")
        }

        // Found by the review: all of these used to be ignored without a word.
        let bad = ["--scene plasmacube", "--look 1993", "--scene", "--look --scene plasma", "--sidebar gone", "--selftests",
                   "--from troll", "--scene plasma --from 3"]
        let accepted = bad.filter { options($0).problems.isEmpty }
        check("App: mistyped start-up options are reported, not ignored", accepted.isEmpty,
              accepted.joined(separator: "; "))

        func snapshot(_ words: String) -> Snapshot.Request? {
            Snapshot.request(from: ["SRMetal", "--snapshot"] + words.split(separator: " ").map(String.init))
        }
        let request = snapshot("rings classic 300 out.png")
        // Found by the review: a negative step crashed the program.
        let refused = ["rings classic -5 out.png", "rings classic 3.5 out.png", "rings classic 300",
                       "nothing classic 300 out.png", "rings 1993 300 out.png", "rings modern 300 out.png half",
                       "rings modern 300 out.png nan"].filter { snapshot($0) != nil }
        check("App: --snapshot reads a good command line and refuses bad ones (negative step, unknown scene or look, bad blend)",
              request?.entry.id == "rings" && request?.look == .classic && request?.step == 300
                  && request?.output == "out.png" && request?.blend == 0
                  && snapshot("rings modern 0 out.png 0.5")?.blend == 0.5 && snapshot("rings modern 0 out.png 7")?.blend == 1
                  && refused.isEmpty,
              refused.joined(separator: "; "))

        func range(_ words: [String]) -> String {
            switch MotionCheck.stepRange(from: words) {
            case .none: return "refused"
            case .some(.none): return "whole loop"
            case .some(.some(let steps)): return "\(steps.first)...\(steps.last)"
            }
        }
        // Found by the review: one number, a mistyped number or a backwards range used to be
        // dropped and the whole loop checked instead; a negative number crashed.
        let ranges = [range([]), range(["10", "20"]), range(["7", "7"]), range(["10"]), range(["1O", "20"]),
                      range(["20", "10"]), range(["-5", "10"]), range(["1", "2", "3"])]
        check("App: --motion-check reads its step range and refuses a malformed one",
              ranges == ["whole loop", "10...20", "7...7", "refused", "refused", "refused", "refused", "refused"],
              ranges.joined(separator: ", "))
    }

    // MARK: - 3D helpers

    private static func math3D(_ check: (String, Bool, String) -> Void) {
        func close(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ tolerance: Float = 0.001) -> Bool {
            simd_reduce_max(simd_abs(a - b)) <= tolerance
        }
        func gap(_ a: simd_float3x3, _ b: simd_float3x3) -> Float {
            (0..<3).map { simd_reduce_max(simd_abs(a[$0] - b[$0])) }.max() ?? 0
        }
        let focal = SIMD2<Float>(200, 160), centre = SIMD2<Float>(150, 90), canvas = SIMD2<Float>(320, 200)
        let matrix = Math3D.perspective(focal: focal, centre: centre, canvasSize: canvas, near: 50, far: 1000)
        let point = SIMD3<Float>(10, -20, 100)
        // By hand: centre + focal * (X, Y) / Z = (150 + 200 * 0.1, 90 + 160 * -0.2) = (170, 58).
        let onCanvas = Math3D.project(point, with: matrix, targetSize: canvas)
        let onScreen = Math3D.project(point, with: matrix, targetSize: SIMD2(960, 720))
        func depth(_ m: simd_float4x4, _ z: Float) -> Float {
            let clip = m * SIMD4<Float>(0, 0, z, 1)
            return clip.z / clip.w
        }
        let nearOverZ = Math3D.perspectiveNearOverZ(focal: focal, centre: centre, canvasSize: canvas, near: 50)
        check("Math3D: the perspective matrices put a point at centre + focal * (x, y) / z, y downwards, with depth as documented",
              close(onCanvas, SIMD2(170, 58)) && close(onScreen, SIMD2(510, 208.8), 0.01)
                  && close(Math3D.project(point, with: nearOverZ, targetSize: canvas), SIMD2(170, 58))
                  && close(Math3D.canvasPosition(point, focal: focal, centre: centre, near: 50), SIMD2(170, 58))
                  && abs(depth(matrix, 50)) < 1e-5 && abs(depth(matrix, 1000) - 1) < 1e-5
                  && abs(depth(nearOverZ, 50) - 1) < 1e-6 && abs(depth(nearOverZ, 500) - 0.1) < 1e-6,
              "\(onCanvas) \(onScreen)")

        // A quarter turn about each axis, by hand: x turns y into z, y turns z into x, z turns x into y.
        let quarter = Float.pi / 2
        func turned(_ m: simd_float3x3, _ v: SIMD3<Float>, _ expected: SIMD3<Float>) -> Bool {
            simd_reduce_max(simd_abs(m * v - expected)) < 1e-6
        }
        let moved = Math3D.transform(rotation: Math3D.rotationZ(quarter), translation: SIMD3(5, 6, 7)) * SIMD4<Float>(1, 0, 0, 1)
        // The original's combined matrix: turns about y, then x, then z, each the opposite way
        // round from the three single-axis helpers. (Worked out by trying every order.)
        let (x, y, z): (Float, Float, Float) = (0.3, 0.7, -1.1)
        let combined = Math3D.rotationYXZ(x: x, y: y, z: z)
        let product = Math3D.rotationY(-y) * Math3D.rotationX(-x) * Math3D.rotationZ(-z)
        check("Math3D: turns go the documented way, turn-then-move works, and the original's combined turn is rY * rX * rZ",
              turned(Math3D.rotationX(quarter), SIMD3(0, 1, 0), SIMD3(0, 0, 1))
                  && turned(Math3D.rotationY(quarter), SIMD3(0, 0, 1), SIMD3(1, 0, 0))
                  && turned(Math3D.rotationZ(quarter), SIMD3(1, 0, 0), SIMD3(0, 1, 0))
                  && simd_reduce_max(simd_abs(moved - SIMD4<Float>(5, 7, 7, 1))) < 1e-6
                  && gap(combined, product) < 1e-6 && abs(simd_determinant(combined) - 1) < 1e-5,
              "combined turn differs from the product by \(gap(combined, product))")

        // The 3D "does this face the camera" test and the 2D one used after projecting must agree,
        // for shapes in front of the camera. Fixed made-up triangles (no random numbers: a
        // self-test must do the same thing every time).
        var disagreements = 0, facing = 0
        var seed: UInt32 = 12345
        func next(_ low: Float, _ high: Float) -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return low + (high - low) * Float(seed >> 8) / Float(1 << 24)
        }
        for _ in 0..<500 {
            let p = (0..<3).map { _ in SIMD3<Float>(next(-50, 50), next(-50, 50), next(60, 200)) }
            let q = p.map { Math3D.canvasPosition($0, focal: focal, centre: centre, near: 50) }
            let in3D = Math3D.facesCamera(p[0], p[1], p[2])
            if in3D { facing += 1 }
            if in3D != (Math3D.screenFacing(q[0], q[1], q[2]) >= 0) { disagreements += 1 }
        }
        check("Math3D: the 3D and the on-screen 'faces the camera' tests agree on 500 triangles",
              disagreements == 0 && facing > 100 && facing < 400, "\(disagreements) disagree, \(facing) face the camera")
    }

    // MARK: - Smooth triangles

    private static func smoothTriangleGeometry(_ check: (String, Bool, String) -> Void) {
        typealias Vertex = SmoothTriangles.Vertex
        // The shader reads the vertex list as { float2; float3; float4 }, which Metal lays out at
        // bytes 0, 16 and 32 of a 48-byte record. Swift must agree or every triangle is garbage.
        check("SmoothTriangles: the vertex record is laid out as the shader reads it (48 bytes; fields at 0, 16, 32)",
              MemoryLayout<Vertex>.stride == 48 && MemoryLayout<Vertex>.offset(of: \.position) == 0
                  && MemoryLayout<Vertex>.offset(of: \.edges) == 16 && MemoryLayout<Vertex>.offset(of: \.colour) == 32,
              "stride \(MemoryLayout<Vertex>.stride)")

        let colour = SIMD4<Float>(1, 1, 1, 1)
        var none: [Vertex] = []
        SmoothTriangles.append(SIMD2(10, 10), SIMD2(20, 20), SIMD2(30, 30), colour: colour, to: &none)   // a line
        SmoothTriangles.append(SIMD2(10, 10), SIMD2(10, 10), SIMD2(30, 5), colour: colour, to: &none)    // two corners the same
        SmoothTriangles.append(SIMD2(7, 7), SIMD2(7, 7), SIMD2(7, 7), colour: colour, to: &none)         // a point
        check("SmoothTriangles: a triangle with no area adds nothing (and no not-a-number values)", none.isEmpty,
              "\(none.count) corners added")

        // An ordinary triangle, corners given both ways round. Each corner handed to the chip must
        // carry its true distances to the three edges (worked out here a different way: the area
        // of the triangle it makes with the edge, divided by the edge's length), and the enlarged
        // triangle must clear the true one by a full pixel all round.
        let a = SIMD2<Float>(20, 15), b = SIMD2<Float>(90, 30), c = SIMD2<Float>(40, 80)
        var oneWay: [Vertex] = [], otherWay: [Vertex] = []
        SmoothTriangles.append(a, b, c, colour: colour, to: &oneWay)
        SmoothTriangles.append(a, c, b, colour: colour, to: &otherWay)
        func cross(_ u: SIMD2<Float>, _ v: SIMD2<Float>) -> Float { u.x * v.y - u.y * v.x }
        func inside(_ p: SIMD2<Float>, _ from: SIMD2<Float>, _ to: SIMD2<Float>, _ third: SIMD2<Float>) -> Float {
            // Positive on the side of the line from...to where `third` is.
            let side: Float = cross(to - from, third - from) >= 0 ? 1 : -1
            return side * cross(to - from, p - from) / simd_length(to - from)
        }
        var worstDistance: Float = 0, leastClearance = Float.infinity
        for list in [oneWay, otherWay] where list.count == 3 {
            // The edges in the order the list uses: the list's corners are the true corners pushed
            // outwards, so the true corner nearest each one tells which is which.
            let corners = list.map { vertex in [a, b, c].min { simd_distance($0, vertex.position) < simd_distance($1, vertex.position) }! }
            for vertex in list {
                for edge in 0..<3 {
                    let expected = inside(vertex.position, corners[edge], corners[(edge + 1) % 3], corners[(edge + 2) % 3])
                    worstDistance = max(worstDistance, abs(vertex.edges[edge] - expected))
                }
            }
            for edge in 0..<3 {
                let from = list[edge].position, to = list[(edge + 1) % 3].position, third = list[(edge + 2) % 3].position
                for corner in [a, b, c] { leastClearance = min(leastClearance, inside(corner, from, to, third)) }
            }
        }
        check("SmoothTriangles: corners carry their true edge distances, and the drawn triangle clears the true one by a pixel, either way round",
              oneWay.count == 3 && otherWay.count == 3 && worstDistance < 0.001 && leastClearance > 0.99 && leastClearance < 1.01,
              "distances off by at most \(worstDistance), clearance \(leastClearance)")
    }

    private static func smoothTrianglesDrawn(_ check: (String, Bool, String) -> Void, device: MTLDevice, queue: MTLCommandQueue) throws {
        // A 32x32 square made of two triangles that share its diagonal, a quarter of a pixel off
        // the pixel grid, added together on a black 64x64 picture. Inside, and all along the
        // shared diagonal, the colour must be exactly the square's (no seam, no double-bright
        // line); the total light must be the square's area (edges faded in proportion); and
        // nothing may be drawn away from it.
        let size = 64
        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + SmoothTriangles.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("smooth_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("smooth_fragment", in: library)
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = Renderer.pixelFormat
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .one
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        var list: [SmoothTriangles.Vertex] = []
        let colour = SIMD4<Float>(0.2, 0.6, 1, 1)
        let low: Float = 8.25, high: Float = 40.25
        SmoothTriangles.append(SIMD2(low, low), SIMD2(high, low), SIMD2(high, high), colour: colour, to: &list)
        SmoothTriangles.append(SIMD2(low, low), SIMD2(high, high), SIMD2(low, high), colour: colour, to: &list)
        let pixels = try draw(width: size, height: size, device: device, queue: queue) { encoder in
            var target = SIMD2<Float>(Float(size), Float(size))
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(list, length: MemoryLayout<SmoothTriangles.Vertex>.stride * list.count, index: 0)
            encoder.setVertexBytes(&target, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: list.count)
        }
        func pixel(_ x: Int, _ y: Int) -> [Int] {   // red, green, blue
            let at = (y * size + x) * 4
            return [Int(pixels[at + 2]), Int(pixels[at + 1]), Int(pixels[at])]
        }
        var wrongInside = 0, strayOutside = 0, blue = 0
        for y in 0..<size {
            for x in 0..<size {
                let p = pixel(x, y)
                blue += p[2]
                if (10...38).contains(x) && (10...38).contains(y) {
                    if abs(p[0] - 51) > 1 || abs(p[1] - 153) > 1 || abs(p[2] - 255) > 1 { wrongInside += 1 }
                } else if x < 7 || x > 41 || y < 7 || y > 41 {
                    if p != [0, 0, 0] { strayOutside += 1 }
                }
            }
        }
        let area = Double(blue) / 255
        check("SmoothTriangles drawn: two triangles sharing an edge make one even square with faded edges and the right area",
              list.count == 6 && wrongInside == 0 && strayOutside == 0 && abs(area - 1024) < 10,
              "\(wrongInside) wrong inside, \(strayOutside) stray, area \(String(format: "%.1f", area)) of 1024")
    }

    // MARK: - The palette picture

    private static func indexedCanvas(_ check: (String, Bool, String) -> Void, device: MTLDevice, queue: MTLCommandQueue) throws {
        // A tiny 4x2 picture (deliberately not 320x200) shown twice its size, with a full
        // 256-colour palette in which every colour is different.
        let canvas = try IndexedCanvas(device: device, pixelFormat: Renderer.pixelFormat, width: 4, height: 2)
        let full: [SIMD4<Float>] = (0..<256).map { (i: Int) -> SIMD4<Float> in
            let red = Float(i) / 255, green = Float(255 - i) / 255, blue = Float((i * 7) % 256) / 255
            return SIMD4<Float>(red, green, blue, 1)
        }
        func bytes(_ index: UInt8) -> [Int] { [Int(index), 255 - Int(index), (Int(index) * 7) % 256] }
        let first: [UInt8] = [0, 1, 2, 255, 100, 200, 50, 254]
        let second: [UInt8] = [255, 3, 2, 0, 200, 100, 51, 9]

        /// How many of the 8x4 drawn pixels are not the colour `expected` gives for their canvas pixel.
        func wrong(_ pixels: [UInt8], _ expected: (Int) -> [Int]) -> Int {
            var count = 0
            for y in 0..<4 {
                for x in 0..<8 {
                    let at = (y * 8 + x) * 4
                    let want = expected((y / 2) * 4 + x / 2)
                    if abs(Int(pixels[at + 2]) - want[0]) > 1 || abs(Int(pixels[at + 1]) - want[1]) > 1
                        || abs(Int(pixels[at]) - want[2]) > 1 { count += 1 }
                }
            }
            return count
        }
        let single = try draw(width: 8, height: 4, device: device, queue: queue) {
            canvas.draw(into: $0, indices: first, palette: full)
        }
        let singleWrong = wrong(single) { bytes(first[$0]) }
        check("IndexedCanvas: each pixel shows its palette colour, top row at the top, up to colour number 255",
              singleWrong == 0, "\(singleWrong) of 32 pixels wrong")

        let pair = try draw(width: 8, height: 4, device: device, queue: queue) {
            canvas.draw(into: $0, indices: first, blendedWith: second, palette: full)
        }
        let pairWrong = wrong(pair) { i in zip(bytes(first[i]), bytes(second[i])).map { ($0 + $1 + 1) / 2 } }
        check("IndexedCanvas: two pictures blended show the even mix of their colours", pairWrong == 0,
              "\(pairWrong) of 32 pixels wrong")

        // Found by the review. The canvas keeps three palette buffers and uses them in turn. After
        // the full palette has been through all three, a SHORT palette must not let colour numbers
        // beyond its end show the old palette's colours; and an empty palette must not crash.
        _ = try draw(width: 8, height: 4, device: device, queue: queue) { canvas.draw(into: $0, indices: first, palette: full) }
        let short = try draw(width: 8, height: 4, device: device, queue: queue) {
            canvas.draw(into: $0, indices: first, palette: [SIMD4(1, 0, 0, 1), SIMD4(0, 1, 0, 1)])
        }
        let shortWrong = wrong(short) { i in first[i] == 0 ? [255, 0, 0] : first[i] == 1 ? [0, 255, 0] : [0, 0, 0] }
        var emptyWrong = 0
        for _ in 0..<3 {
            let empty = try draw(width: 8, height: 4, device: device, queue: queue) { canvas.draw(into: $0, indices: first, palette: []) }
            emptyWrong += wrong(empty) { _ in [0, 0, 0] }
        }
        check("IndexedCanvas: colour numbers beyond a short (or empty) palette show black, not an earlier frame's colours",
              shortWrong == 0 && emptyWrong == 0, "\(shortWrong) wrong with 2 colours, \(emptyWrong) with none")
    }

    // MARK: - Pictures without a window (also what the sidebar does)

    private static func snapshots(_ check: (String, Bool, String) -> Void) throws {
        func bytes(_ image: CGImage) -> [UInt8] { image.dataProvider?.data.map { [UInt8]($0 as Data) } ?? [] }

        // The 1993 look scaled up to 960x720, for a 320x200 scene and a 320x400 one: every picture
        // pixel must be the canvas pixel it lies over (canvas rows and columns found here by
        // exact fractions rather than the renderer's whole-number sum).
        var faults: [String] = []
        for id in ["dot-tunnel", "plasma"] {
            guard let entry = SceneCatalog.all.first(where: { $0.id == id }),
                  let device = MTLCreateSystemDefaultDevice() else { faults.append("\(id) missing"); continue }
            let picture = bytes(try Snapshot.render(entry: entry, look: .classic, step: entry.thumbnailStep, width: 960, height: 720))
            let scene = try entry.make(device, Renderer.pixelFormat)
            for _ in 0..<entry.thumbnailStep { scene.tick() }
            let reference = scene.classicReferenceFrame()
            let width = Int(entry.canvasSize.x), height = Int(entry.canvasSize.y)
            guard picture.count == 960 * 720 * 4, reference.count == width * height * 3 else { faults.append("\(id) wrong size"); continue }
            var wrong = 0, lit = 0
            for y in 0..<720 {
                let row = Int((Double(y) + 0.5) / 720 * Double(height))
                for x in 0..<960 {
                    let from = (row * width + Int((Double(x) + 0.5) / 960 * Double(width))) * 3
                    let at = (y * 960 + x) * 4
                    if reference[from] != 0 || reference[from + 1] != 0 || reference[from + 2] != 0 { lit += 1 }
                    if abs(Int(picture[at + 2]) - Int(reference[from])) > 1 || abs(Int(picture[at + 1]) - Int(reference[from + 1])) > 1
                        || abs(Int(picture[at]) - Int(reference[from + 2])) > 1 { wrong += 1 }
                }
            }
            if wrong > 0 || lit < 1000 { faults.append("\(id): \(wrong) wrong, \(lit) lit") }
        }
        check("Snapshot: the 1993 look scaled up shows the right canvas pixel everywhere (320x200 and 320x400 canvases)",
              faults.isEmpty, faults.joined(separator: "; "))

        // The sidebar draws every scene's small picture on a background thread while the window's
        // scene runs on the main thread. Do the same job on two threads at once: every picture
        // must come out, must show something, and must be identical on both threads. (If scenes
        // shared something they change while running, the two threads would disturb each other.)
        func listPictures() -> [String: [UInt8]] {
            var result: [String: [UInt8]] = [:]
            for entry in SceneCatalog.all {
                if let image = try? Snapshot.render(entry: entry, look: .modern, step: entry.thumbnailStep,
                                                    width: Thumbnails.width, height: Thumbnails.height) {
                    result[entry.id] = bytes(image)
                }
            }
            return result
        }
        var elsewhere: [String: [UInt8]] = [:]
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            elsewhere = listPictures()
            done.signal()
        }
        let here = listPictures()
        done.wait()
        var listFaults: [String] = []
        for entry in SceneCatalog.all {
            guard let a = here[entry.id], let b = elsewhere[entry.id], a.count == Thumbnails.width * Thumbnails.height * 4 else {
                listFaults.append("\(entry.id) not drawn")
                continue
            }
            var litBytes = 0
            for i in stride(from: 0, to: a.count, by: 4) where a[i] != 0 || a[i + 1] != 0 || a[i + 2] != 0 { litBytes += 1 }
            if litBytes < 50 { listFaults.append("\(entry.id) is blank") }
            if a != b { listFaults.append("\(entry.id) differs between threads") }
        }
        check("Sidebar pictures: every scene's draws, shows something, and is identical when two threads draw them at once",
              listFaults.isEmpty, listFaults.joined(separator: "; "))
    }

    // MARK: - Helper

    /// Draws into a fresh black picture and returns its pixels: blue, green, red, alpha for each, top row first.
    static func draw(width: Int, height: Int, device: MTLDevice, queue: MTLCommandQueue,
                             _ body: (MTLRenderCommandEncoder) -> Void) throws -> [UInt8] {
        guard let texture = Renderer.makeClassicTexture(device: device, canvasSize: SIMD2(Float(width), Float(height))),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: Renderer.clearPass(into: texture))
        else { throw Snapshot.Failure.couldNotDraw }
        body(encoder)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }
}
