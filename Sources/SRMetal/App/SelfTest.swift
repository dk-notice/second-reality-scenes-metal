import Foundation
import Metal
import simd

/// Checks run with `SRMetal --selftest`. No window is opened.
///
/// The main check, for every scene: draw the classic look on the graphics chip, read the picture back,
/// and compare it pixel by pixel with the same frame worked out on the processor using the 1993 rules.
enum SelfTest {
    /// `--selftest <word>`: only the groups of checks whose label contains the word (scene ids and
    /// titles, topics such as "demo", "music", "core"); nil runs them all. For working on one area;
    /// the full self-test is still run before every commit.
    static var only: String?

    /// Whether a group of checks with this label runs.
    static func wants(_ label: String) -> Bool {
        guard let only else { return true }
        return label.lowercased().contains(only.lowercased())
    }

    /// Whether a scene's checks run (its id or its title contains the word).
    static func wants(_ entry: SceneEntry) -> Bool { wants(entry.id + " " + entry.title) }

    /// How many checks the full self-test runs. A check that silently stops running (its set-up failed, a
    /// name it looked up is gone) makes the count wrong, and the run fails. Change it with each check
    /// added or removed.
    static let expectedChecks = 639

    static func run() -> Bool {
        var ok = true
        var checksRun = 0
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            print("\(passed ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
            checksRun += 1
            if !passed { ok = false }
        }

        // ===== CORE AND APP CHECKS (code review, 2026-11-14): see CoreChecks.swift. =====
        // Checks of the shared code and the command line go there, not among the scenes' checks below.
        CoreChecks.run { name, passed, detail in check(name, passed, detail) }
        // ===== END OF CORE AND APP CHECKS =====

        // Used by several sections below.
        func words(_ table: [UInt16]) -> [UInt8] { table.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] } }
        if SelfTest.wants("tables sine tunnel interference plasma") {
            // Tables and pictures that replace the original's data files. The expected values were taken
            // from those files (SINIT.DAT, SIN1024.INC, _CIRCLE.OBK, _CIRCLE2.OBK).
            let sinT = DotTunnelModel.sinTable
            let cosT = DotTunnelModel.cosTable
            check("tunnel sine table matches original spot values",
                  Array(sinT[1000...1003]) == [-13, -12, -12, -11] && Array(sinT[4090...4096]) == [-14, -12, -9, -7, -5, -2, 0])
            check("tunnel cosine table matches original spot values",
                  Array(cosT[1000...1003]) == [52, 52, 53, 54] && cosT[2048] == 128)
            check("shared sine table matches original spot values",
                  Array(SinTable.sin1024[0...5]) == [0, 1, 3, 4, 6, 7] && SinTable.sin1024[256] == 256 && SinTable.sin1024[768] == -256)
            check("interference ring picture matches original file",
                  crc32(quarter(of: InterferenceModel.ringPicture)) == 3_479_151_390)
            check("interference stripe picture matches original file",
                  crc32(quarter(of: InterferenceModel.stripePicture)) == 990_890_590)

            // The plasma's four tables, against checksums of the original PSINI.INC, LSINI16.INC, LSINI4.INC
            // and PTAU.INC (16-bit tables as low byte, high byte).
            check("plasma sine table matches original file", crc32(PlasmaModel.psini) == 942_993_316)
            check("plasma bend table 16 matches original file", crc32(words(PlasmaModel.lsini16)) == 3_664_524_141)
            check("plasma bend table 4 matches original file", crc32(words(PlasmaModel.lsini4)) == 3_446_065_726)
            check("plasma brightness ramp matches original file",
                  crc32(PlasmaModel.ptau.map { UInt8($0) }) == 404_302_250)
        }

        if SelfTest.wants("techno-bars techno bars raster") {
            // The bar-filling routine: a plain 40x20 rectangle must fill exactly 800 pixels,
            // left and top edges included, right and bottom edges not (the original's rule).
            var raster = BarRasteriser()
            raster.add([.init(x: 10, y: 10), .init(x: 50, y: 10), .init(x: 50, y: 30), .init(x: 10, y: 30)])
            let filled = raster.filled()
            check("bar fill: rectangle fills the expected pixels",
                  filled.reduce(0) { $0 + Int($1) } == 800 && filled[10 * 320 + 10] == 1 && filled[29 * 320 + 49] == 1
                      && filled[10 * 320 + 50] == 0 && filled[30 * 320 + 10] == 0)
        }

        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            check("Metal device available", false)
            return false
        }

        for entry in SceneCatalog.all where SelfTest.wants(entry) {
            do {
                let scene = try entry.make(device, Renderer.pixelFormat)
                let width = Int(entry.canvasSize.x)
                let height = Int(entry.canvasSize.y)
                guard let texture = Renderer.makeClassicTexture(device: device, canvasSize: entry.canvasSize) else {
                    check("\(entry.title): classic texture created", false)
                    continue
                }

                var tick = 0
                var litCheckpoints = 0
                for target in entry.checkpoints {
                    while tick < target {
                        scene.tick()
                        tick += 1
                    }
                    guard let commands = queue.makeCommandBuffer() else {
                        check("\(entry.title), step \(target): graphics chip matches 1993 reference", false, "no command buffer")
                        continue
                    }
                    Renderer.drawClassic(scene: scene, canvasSize: entry.canvasSize, into: texture, commands: commands)
                    commands.commit()
                    commands.waitUntilCompleted()

                    // The picture comes back as blue, green, red, alpha for each pixel.
                    var pixels = [UInt8](repeating: 0, count: width * height * 4)
                    texture.getBytes(&pixels, bytesPerRow: width * 4,
                                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

                    let reference = scene.classicReferenceFrame()
                    var lit = 0
                    var wrong = 0
                    for i in 0..<(width * height) {
                        let expected = (Int(reference[i * 3]), Int(reference[i * 3 + 1]), Int(reference[i * 3 + 2]))
                        let drawn = (Int(pixels[i * 4 + 2]), Int(pixels[i * 4 + 1]), Int(pixels[i * 4]))
                        if expected != (0, 0, 0) { lit += 1 }
                        // Allow 1 level of difference for rounding 0...63 up to 0...255.
                        if abs(drawn.0 - expected.0) > 1 || abs(drawn.1 - expected.1) > 1 || abs(drawn.2 - expected.2) > 1 {
                            wrong += 1
                        }
                    }
                    check("\(entry.title), step \(target): graphics chip matches 1993 reference", wrong == 0,
                          "\(lit) lit pixels, \(wrong) wrong")
                    if lit > 0 { litCheckpoints += 1 }
                }
                // Two all-black pictures match each other, so a scene that drew nothing and whose
                // reference was empty would pass every line above. At least half of a scene's
                // checkpoints must show a picture.
                check("\(entry.title): at least half of its checkpoints show a picture (not black against black)",
                      litCheckpoints * 2 >= entry.checkpoints.count, "\(litCheckpoints) of \(entry.checkpoints.count)")
            } catch {
                check("\(entry.title) starts", false, "\(error)")
            }
        }

        if SelfTest.wants("dot-tunnel dot tunnel") {
            // The tunnel should loop back to an empty tunnel after its full run.
            var tunnel = DotTunnelModel()
            let tunnelStart = tunnel.classicReferenceFrame()
            for _ in 0..<(DotTunnelModel.lengthInTicks - 1) { tunnel.tick() }
            let tunnelEnd = tunnel.classicReferenceFrame()
            tunnel.tick()
            check("Dot Tunnel loops after \(DotTunnelModel.lengthInTicks) steps", tunnel.tickCount == 0
                  && !tunnelEnd.contains { $0 != 0 } && tunnel.classicReferenceFrame() == tunnelStart)

            // Dot Tunnel, 1993 look, against a separate re-run of the original's loop (TUN10.PAS: each dot
            // blanks its old pixel just before it is drawn, with the screen never cleared), written in
            // Python and reading the original TUNNEL.DAT and SINIT.DAT. The sums are of the screen's colour
            // numbers. Clearing and redrawing instead (as this scene did before its code review) gives
            // different pictures at every one of these steps: the original loses about one dot in twenty.
            do {
                let table = DotTunnelModel.circleTable
                check("tunnel circle table matches original spot values",
                      table.count == 138 && table[0][0] == SIMD2(160, 110) && table[0][16] == SIMD2(177, 100)
                          && table[137][5] == SIMD2(278, 230) && table[100][40] == SIMD2(28, 22))
                var replay = DotTunnelModel()
                var sums: [UInt32] = []
                var litNearEnd = 0
                for step in 1..<DotTunnelModel.lengthInTicks {
                    replay.tick()
                    if [60, 250, 500, 777, 900, 1000].contains(step) { sums.append(crc32(replay.classicIndices())) }
                    if step >= 1054 { litNearEnd += replay.classicReferenceFrame().reduce(0) { $0 + ($1 != 0 ? 1 : 0) } }
                }
                check("Dot Tunnel pictures match the re-run of the original's erase-and-draw loop at steps 60, 250, 500, 777, 900, 1000",
                      sums == [2_581_361_537, 231_369_616, 2_597_006_008, 2_878_197_779, 1_960_365_762, 637_159_662],
                      "\(sums)")
                check("Dot Tunnel leaves no dots behind when it empties (steps 1054...1059)", litNearEnd == 0,
                      "\(litNearEnd) lit pixels")
            }
        }

        if SelfTest.wants("techno-bars techno bars") {
            // Techno Bars, modern look, over one whole loop and into the next. Within a section the bars only
            // spin forwards, by at most about 85/1024 of a turn per step, and their thickness by under
            // about a pixel. At a section change they jump (by 833/1024 of a turn backwards into section two).
            // So a glide that goes backwards, or spins more than 1/8 turn, or changes thickness by more than
            // 3 pixels, has crossed a section change. Also: whenever the 1993 look shows bars, the modern look
            // must show the current bars too (not only ghosts, and not nothing).
            do {
                var bars = TechnoBarsModel()
                var seenSectionThree = false
                var stepsAfterLoop = -1
                var steps = 0
                var worstBackward = 0.0, worstForward = 0.0, worstThickness = 0.0
                var badGlides: [String] = []
                var missingCurrent: [Int] = []
                while stepsAfterLoop < 40 && steps < 5000 {
                    bars.tick()
                    steps += 1
                    if bars.section == .three { seenSectionThree = true }
                    if seenSectionThree && bars.section == .one && stepsAfterLoop < 0 { stepsAfterLoop = 0 }
                    if stepsAfterLoop >= 0 { stepsAfterLoop += 1 }

                    let start = bars.modernParameters(alpha: 0).snapshots
                    let end = bars.modernParameters(alpha: 1).snapshots
                    for ghost in 0..<4 where start[ghost].weight > 0 {
                        let spin = end[ghost].state.rotation - start[ghost].state.rotation
                        let thickness = abs(end[ghost].state.halfThickness - start[ghost].state.halfThickness)
                        worstBackward = min(worstBackward, spin)
                        worstForward = max(worstForward, spin)
                        worstThickness = max(worstThickness, thickness)
                        if (spin < 0 || spin > 128 || thickness > 3) && badGlides.count < 5 {
                            badGlides.append("step \(steps) ghost \(ghost)")
                        }
                    }
                    if bars.classicIndices().contains(where: { $0 != 0 }) && start[0].weight == 0 {
                        missingCurrent.append(steps)
                    }
                }
                check("Techno Bars modern look never glides across a section change (one loop of \(steps) steps)",
                      seenSectionThree && stepsAfterLoop >= 40 && badGlides.isEmpty,
                      badGlides.isEmpty
                          ? "spin per glide \(worstBackward)...\(worstForward), thickness change up to \(String(format: "%.2f", worstThickness))"
                          : badGlides.joined(separator: ", "))
                check("Techno Bars modern look shows the current bars whenever the 1993 look shows bars",
                      missingCurrent.isEmpty, missingCurrent.prefix(5).map { "step \($0)" }.joined(separator: ", "))
            }
        }

        if SelfTest.wants("interference") {
            // Interference should loop seamlessly: after one full run it is back at its first frame, and the
            // last step before the loop differs from the first frame no more than any two neighbouring steps do.
            func changed(_ a: [UInt8], _ b: [UInt8]) -> Int {
                var count = 0
                for i in stride(from: 0, to: a.count, by: 3) where a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] {
                    count += 1
                }
                return count
            }
            var interference = InterferenceModel(part: .interference)
            let firstFrame = interference.classicReferenceFrame()
            interference.tick()
            let secondFrame = interference.classicReferenceFrame()
            for _ in 1..<(InterferenceModel.interferenceTicks - 1) { interference.tick() }
            let lastFrame = interference.classicReferenceFrame()
            interference.tick()
            check("Interference returns to its first frame after \(InterferenceModel.interferenceTicks) steps",
                  interference.classicReferenceFrame() == firstFrame)
            let ordinaryStep = changed(firstFrame, secondFrame)
            let loopStep = changed(lastFrame, firstFrame)
            check("Interference loop point is no bigger a jump than an ordinary step",
                  loopStep <= ordinaryStep * 11 / 10,
                  "\(loopStep) pixels change across the loop, \(ordinaryStep) across an ordinary step")
        }

        if SelfTest.wants("bouncing-dots bouncing dots") {
            // Bouncing Dots, modern look, over one whole loop and into the next. A dot glides from where it
            // was a step ago to where it is now, unless it is marked as jumping. In ordinary motion no dot
            // or shadow moves more than about 27 canvas pixels in a step. A longer glide means the dot has
            // been slid between two places it was never between: from a placeholder on the first step with
            // dots (511 dots, 164 pixels, before the code review), or across the screen when its 16-bit
            // height wraps round (up to 718 pixels). Also: the smooth fade must stay within 0...64 and must
            // not snap at a step boundary (it used to dip below 0 at the end of the fade-in).
            do {
                var dots = BouncingDotsModel()
                var longest = 0.0
                var longGlides: [String] = []
                var fadeLow = 64.0, fadeHigh = 0.0, fadeSnap = 0.0
                let steps = BouncingDotsModel.fadeInTicks + BouncingDotsModel.mainTicks + 300
                for step in 1...steps {
                    let fadeBefore = dots.smoothFade(alpha: 0.999)
                    dots.tick()
                    fadeSnap = max(fadeSnap, abs(dots.smoothFade(alpha: 0) - fadeBefore))
                    for alpha in [0, 0.5, 0.999] {
                        fadeLow = min(fadeLow, dots.smoothFade(alpha: alpha))
                        fadeHigh = max(fadeHigh, dots.smoothFade(alpha: alpha))
                    }
                    guard dots.ticks > BouncingDotsModel.fadeInTicks else { continue }
                    for i in 0..<BouncingDotsModel.dotCount where !dots.current[i].jumped {
                        let now = dots.current[i], before = dots.previous[i]
                        let glide = max(abs(now.position.x - before.position.x), abs(now.position.y - before.position.y),
                                        abs(now.shadowY - before.shadowY))
                        longest = max(longest, glide)
                        if glide > 50 && longGlides.count < 5 { longGlides.append("step \(step) dot \(i): \(Int(glide))") }
                    }
                }
                check("Bouncing Dots modern look never glides a dot from a placeholder or across a height wrap (\(steps) steps)",
                      longGlides.isEmpty && longest > 5,
                      longGlides.isEmpty ? String(format: "longest glide %.1f canvas pixels", longest) : longGlides.joined(separator: ", "))
                check("Bouncing Dots modern fade stays within 0...64 and does not snap between steps",
                      fadeLow >= 0 && fadeHigh <= 64 && fadeSnap < 0.6,
                      String(format: "range %.2f...%.2f, largest change across a step boundary %.3f", fadeLow, fadeHigh, fadeSnap))
            }
        }

        if SelfTest.wants("plasma") {
            // Plasma should loop exactly: any moment and the same moment one full run later look identical,
            // and the loop point itself is black (the band has fallen away; the next palette has not begun).
            var plasma = PlasmaModel()
            for _ in 0..<400 { plasma.tick() }
            let plasmaBefore = plasma.classicReferenceFrame()
            for _ in 0..<(PlasmaModel.lengthInTicks - 400) { plasma.tick() }
            check("Plasma is black at its loop point", !plasma.classicReferenceFrame().contains { $0 != 0 })
            for _ in 0..<400 { plasma.tick() }
            check("Plasma repeats exactly after \(PlasmaModel.lengthInTicks) steps",
                  plasma.classicReferenceFrame() == plasmaBefore && plasmaBefore.contains { $0 != 0 })

            // On its own the scene follows the RELEASED part: three sections and palettes (PLZ.C's fourth
            // is never reached), each as long as the timetable's music ticks last at song 2's rate.
            do {
                var alone = PlasmaModel()
                var falls: [Int] = [], sections = [alone.section]
                for step in 1..<PlasmaModel.lengthInTicks {
                    alone.tick()
                    if alone.dropCounter == 2 { falls.append(step) }
                    if sections.last != alone.section { sections.append(alone.section) }
                }
                check("Plasma on its own shows the released part's three palettes: its band falls at steps 976, 2009 and 2526 (723, 1491 and 1875 music ticks) and it repeats after 2588",
                      falls == [976, 2009, 2526] && sections == [0, 1, 2, 0] && PlasmaModel.lengthInTicks == 2588
                        && PlasmaModel.palettes.count == 3 && PlasmaModel.startParameters.count == 3,
                      "falls \(falls), sections \(sections), length \(PlasmaModel.lengthInTicks), \(PlasmaModel.palettes.count) palettes")
            }

            // Plasma, 1993 look: which sideways shift goes with which line (code review, 2026-11-14). The
            // original chose line and shift together but the shift reached the video card one frame late
            // (DIS/DISINT.ASM, MAIN/COPPER.ASM), so line 60 is seen with no shift and line 61 with 2 pixels.
            // `plasma` is at step 400 here: flowing normally. Step 10 of a fresh run is mid-fade, where
            // both alternating frames use line 60.
            var fadingPlasma = PlasmaModel()
            for _ in 0..<10 { fadingPlasma.tick() }
            check("Plasma pairs line 60 with no shift and line 61 with the 2-pixel shift",
                  plasma.fields.map { [$0.top, $0.pan] } == [[61, 0], [62, 2]]
                      && fadingPlasma.fields.map { [$0.top, $0.pan] } == [[61, 0], [61, 2]],
                  "flowing \(plasma.fields.map { [$0.top, $0.pan] }), fading \(fadingPlasma.fields.map { [$0.top, $0.pan] })")

            // Plasma, modern look, over one whole loop and into the next: the end of every step's glide must
            // be where the next step starts (band position, the eight plasma numbers, the palette). The only
            // places allowed to differ are where nothing can be seen: the band hidden or wholly below the
            // screen on one side, and hidden or black on the other.
            do {
                var model = PlasmaModel()
                var worstTop: Float = 0, worstNumber: Float = 0, worstColour: Float = 0
                var broken: [String] = []
                func invisible(_ p: PlasmaModel.ModernParameters) -> Bool {
                    p.hidden || p.top >= Float(PlasmaModel.canvasHeight)
                        || !p.palette.contains { $0.x > 0 || $0.y > 0 || $0.z > 0 }
                }
                func wrapped(_ difference: SIMD4<Float>) -> Float {
                    // The plasma numbers go round every 4096.
                    (0..<4).map { abs(difference[$0] - 4096 * (difference[$0] / 4096).rounded()) }.max() ?? 0
                }
                for step in 0..<(PlasmaModel.lengthInTicks + 40) {
                    let end = model.modernParameters(alpha: 1)
                    model.tick()
                    let start = model.modernParameters(alpha: 0)
                    if invisible(end) && invisible(start) { continue }
                    let top = abs(end.top - start.top)
                    let number = max(wrapped(end.k - start.k), wrapped(end.l - start.l))
                    let colour = zip(end.palette, start.palette).map { simd_reduce_max(abs($0 - $1)) }.max() ?? 0
                    worstTop = max(worstTop, top)
                    worstNumber = max(worstNumber, number)
                    worstColour = max(worstColour, colour)
                    if (invisible(end) != invisible(start) || top > 0.01 || number > 0.01 || colour > 0.001)
                        && broken.count < 5 {
                        broken.append("into step \(step + 1)")
                    }
                }
                check("Plasma modern look glides without a jump through the whole loop", broken.isEmpty,
                      "worst: band \(worstTop) lines, numbers \(worstNumber), colour \(worstColour); \(broken.joined(separator: ", "))")
            }
        }

        if SelfTest.wants("starfield") {
            // Hidden Starfield. The original worked its tables out when it started, so there is no data file
            // to compare with. The expected numbers here come from running the original's own routines
            // (random, the table set-up, staradd, staradd2 in STARS.ASM) one instruction at a time in a small
            // interpreter (tools/starfield_reference.py). Until the 2026-11-14 review they came from a Python
            // re-write that shared a misreading with the Swift (see docs/scenes/starfield.md).
            check("Starfield scale tables match the assembly's formula",
                  Array(StarfieldModel.scaleY[0...2]) == [23592, 22980, 22398] && StarfieldModel.scaleY[255] == 3024
                      && Array(StarfieldModel.scaleX[0...2]) == [31457, 30640, 29864] && StarfieldModel.scaleX[255] == 4032)
            var starfield = StarfieldModel()
            check("Starfield random numbers give the expected first stars (after the 100 warm-up steps)",
                  starfield.stars[0...3].map { [Int($0.depth), $0.x, $0.y] }
                      == [[55, -512, -386], [54, 120, -278], [53, 278, 244], [52, 125, 182]])
            let starfieldStart = starfield.classicIndices()
            var starfieldSums: [UInt32] = []
            var starfieldScreens: [UInt32] = []
            let starfieldSteps = [1, 2, 33, 64, 500, 900, 901, 1200, 1201, 1217, 1499, 1500, 1501, 1700, 1984]
            for step in 1...StarfieldModel.lengthInTicks {
                starfield.tick()
                if [1, 900, 1200, 1500].contains(step) { starfieldSums.append(crc32(starfield.currentPicture)) }
                if starfieldSteps.contains(step) { starfieldScreens.append(crc32(starfield.classicIndices())) }
            }
            check("Starfield pictures match the original assembly at steps 1, 900, 1200, 1500",
                  starfieldSums == [3_540_269_994, 2_667_235_922, 2_123_349_935, 3_777_362_598], "\(starfieldSums)")
            // The whole 320x400 screen (both halves, so two pictures of the ring at once), at more steps:
            // either side of every mark in the timetable. This is the check that catches a dot placed with
            // the wrong depth: with the old "depth before the step" rule every one of these differs.
            check("Starfield screens match the original assembly at steps \(starfieldSteps)",
                  starfieldScreens == [2_333_570_087, 2_924_147_294, 3_046_112_483, 1_249_645_176, 1_714_077_540,
                                       2_633_477_184, 2_714_334_314, 1_125_324_415, 3_486_042_079, 854_166_899,
                                       739_869_190, 902_598_680, 1_200_130_203, 2_883_636_437, 1_268_624_448],
                  "\(starfieldScreens)")
            check("Starfield loops after \(StarfieldModel.lengthInTicks) steps",
                  starfield.ticks == 0 && starfield.classicIndices() == starfieldStart
                      && StarfieldModel.fadeLevel(tick: StarfieldModel.lengthInTicks - 1) == 1)
        }

        // Used by several sections below.
        func words16(_ values: [Int16]) -> [UInt8] {
            values.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }
        }
        if SelfTest.wants("sine-landscape landscape") {
            // 3D Sine Landscape. Its tables are calculated; the expected checksums are those of the
            // original's WAVE.H, W1DTA.BIN and W2DTA.BIN, and of the constants in the generated THELOOP.INC.
            check("landscape wave shape matches original WAVE.H",
                  crc32(words16(SineLandscapeModel.waveSin.map { Int16($0) })) == 717_965_942)
            check("landscape height table 1 matches original W1DTA.BIN (random roughness included)",
                  crc32(words16(SineLandscapeModel.waves.first)) == 3_057_778_354)
            check("landscape height table 2 matches original W2DTA.BIN",
                  crc32(words16(SineLandscapeModel.waves.second)) == 2_437_580_373)
            let raySteps = SineLandscapeModel.raySteps
            let riseBytes = raySteps.flatMap { step in (0..<4).map { UInt8(truncatingIfNeeded: step.rise >> ($0 * 8)) } }
            check("landscape ray-step constants match the original's generated code",
                  raySteps.count == 128
                      && crc32(words16(raySteps.map { $0.terrainAdd })) == 456_993_559
                      && crc32(words16(raySteps.map { $0.colourAdd })) == 1_790_154_188
                      && crc32(riseBytes) == 109_985_885)
            // The 1993 pictures, against the original's own assembly text (THELOOP.INC) run instruction by
            // instruction in a small interpreter (tools/landscape_reference.py).
            var landscape = SineLandscapeModel()
            var landscapeSums: [UInt32] = []
            for step in 1..<SineLandscapeModel.lengthInTicks {
                landscape.tick()
                if [100, 200, 700, 1300, 1978, 2046].contains(step) { landscapeSums.append(crc32(landscape.classicIndices())) }
            }
            check("Landscape pictures match the original assembly at steps 100, 200, 700, 1300, 1978, 2046",
                  landscapeSums == [3_772_065_790, 1_058_285_202, 2_259_277_037, 2_267_902_942, 3_774_399_680, 2_109_903_275],
                  "\(landscapeSums)")
            landscape.tick()
            check("Landscape loops from black after \(SineLandscapeModel.lengthInTicks) steps",
                  landscape.ticks == 0 && !landscape.classicIndices().contains { $0 != 0 })
            // Landscape, modern look, over one whole loop and into the next: the camera's glide must be
            // continuous. Where one step's glide ends, the next one's must begin (a picture is drawn only every
            // second step, so each glide spans two steps). The one place the camera may jump is the restart,
            // and there the land must be out of sight on both sides (pushed down 130 lines or more).
            do {
                var land = SineLandscapeModel()
                var breaks: [String] = []
                var visibleJump = false
                var worstMove = 0.0, worstTurn = 0.0
                for step in 1...(SineLandscapeModel.lengthInTicks + 40) {
                    let before = land.camera(alpha: 1)
                    land.tick()
                    let after = land.camera(alpha: 0)
                    let moved = simd_length(after.position - before.position)
                    let same = moved < 1e-9 && abs(after.heading - before.heading) < 1e-9
                        && abs(after.startRise - before.startRise) < 1e-9
                    if !same {
                        if before.startRise >= 130 && after.startRise >= 130 { continue }
                        visibleJump = true
                        if breaks.count < 5 { breaks.append("step \(step)") }
                    }
                    let end = land.camera(alpha: 1)
                    worstMove = max(worstMove, simd_length(end.position - after.position))
                    worstTurn = max(worstTurn, abs(end.heading - after.heading))
                }
                check("Landscape modern camera glides without a break over one loop and into the next",
                      !visibleJump && worstMove < 600 && worstTurn < 2,
                      breaks.isEmpty ? "per step: moves up to \(String(format: "%.0f", worstMove)) units, turns up to \(String(format: "%.2f", worstTurn))/1024" : breaks.joined(separator: ", "))
            }
        }

        if SelfTest.wants("plasma-cube plasma cube") {
            // Plasma Cube. Two tables are the original's own numbers (no formula reproduces them), checked
            // here against checksums of SINIT.INC and SPLINE.INC; the path points against RATA.INC as the
            // assembler lays it out. The texture, shift table and palette were calculated by the original
            // when it started, so there is no file: their sums come from tools/plasmacube_reference.py.
            check("cube sine table matches original SINIT.INC",
                  crc32(words16(PlasmaCubeTables.sine)) == 1_587_716_556)
            check("cube path blend table matches original SPLINE.INC",
                  crc32(words16(PlasmaCubeTables.blend)) == 3_882_426_550)
            check("cube path points match original RATA.INC",
                  crc32(words16((0..<40).flatMap { PlasmaCubeModel.pathPoint($0).map { Int16($0) } })) == 606_685_329)
            check("cube texture, shift table and palette match the reference tool",
                  crc32(PlasmaCubeModel.texture) == 2_722_653_712
                      && crc32((0..<128).map { PlasmaCubeModel.sideShift[$0 * 256] }) == 88_279_259
                      && crc32(PlasmaCubeModel.basePalette) == 1_269_355_970)
            // The 1993 pictures, against the original's own assembly text (PLZA.ASM, SPLINE.ASM) run
            // instruction by instruction (tools/plasmacube_reference.py): the screen's colour numbers for
            // both of the alternating two-pixel shifts, and the lit palette.
            var cube = PlasmaCubeModel()
            let cubeSteps = [16, 60, 100, 416, 800, 1200, 1600, 1916, 2010, 2047]
            var cubeSums: [[UInt32]] = [[], [], []]
            let cubeStart = cube.classicReferenceFrame()
            for step in 1..<PlasmaCubeModel.lengthInTicks {
                cube.tick()
                if cubeSteps.contains(step) {
                    cubeSums[0].append(crc32(cube.cards[0].screen()))
                    cubeSums[1].append(crc32(cube.cards[1].screen()))
                    cubeSums[2].append(crc32(cube.palette))
                }
            }
            check("Cube pictures match the original assembly at steps \(cubeSteps) (first shift)",
                  cubeSums[0] == [217_181_906, 4_126_692_819, 198_132_681, 3_130_113_999, 4_202_209_341,
                                  2_873_010_333, 1_548_758_970, 822_199_749, 3_872_210_463, 181_403_106],
                  "\(cubeSums[0])")
            check("Cube pictures match the original assembly at the same steps (second shift)",
                  cubeSums[1] == [2_463_643_729, 42_824_033, 3_142_962_629, 1_658_347_174, 2_796_845_361,
                                  1_627_954_972, 3_747_529_998, 2_744_917_341, 3_381_679_536, 1_660_630_442],
                  "\(cubeSums[1])")
            check("Cube palettes match the original assembly at the same steps",
                  cubeSums[2] == [2_077_809_398, 3_645_965_777, 3_631_874_327, 86_136_016, 1_160_387_906,
                                  2_103_546_921, 2_231_204_868, 3_079_804_970, 2_007_781_427, 898_134_552],
                  "\(cubeSums[2])")
            let cubeEnd = cube.classicReferenceFrame()
            cube.tick()
            check("Cube is black at both ends and loops after \(PlasmaCubeModel.lengthInTicks) steps",
                  cube.ticks == 0 && !cubeStart.contains { $0 != 0 } && !cubeEnd.contains { $0 != 0 }
                      && cube.classicReferenceFrame() == cubeStart)

            // Plasma Cube, modern look against the 1993 replay, at every step of the loop (code review,
            // 2026-11-14). The modern look works the path, the turn and the light out again in floating
            // point, so this is the check that it is the same cube: the same faces drawn, every corner
            // within 5 units of where the 1993 whole-number arithmetic puts it (the cube is 250 units
            // across; that arithmetic cuts the path's angles to whole 1/1024ths of a turn and its nine
            // turn numbers to 1/256, and is measured to be up to 4.3 units out), and each face's light
            // within 2 of the 64 levels. A face seen almost exactly
            // edge-on may be drawn by one look and not the other; those steps are counted and must be rare.
            do {
                var model = PlasmaCubeModel()
                var worstCorner = 0.0, worstLight = 0.0
                var differentFaces = 0, lightChecked = 0
                for _ in 0..<PlasmaCubeModel.lengthInTicks {
                    let modern = model.modernState(alpha: 0)
                    let classicFaces = model.visibleFaces.map { PlasmaCubeModel.faces[$0] }
                    if modern.faces.count != classicFaces.count
                        || zip(modern.faces, classicFaces).contains(where: { $0.group != $1.group }) {
                        differentFaces += 1
                    } else {
                        for (face, classic) in zip(modern.faces, classicFaces) {
                            for (corner, index) in zip(face.corners, classic.corners) {
                                let off = SIMD3<Double>(corner) - SIMD3<Double>(model.turned[index])
                                worstCorner = max(worstCorner, simd_reduce_max(abs(off)))
                            }
                        }
                        // The 1993 light level, read back from the brightest colour of each colour range,
                        // where exactly one face of that range is drawn.
                        for face in modern.faces where modern.faces.filter({ $0.group == face.group }).count == 1 {
                            let brightest = face.group * 192 + 63 * 3 + [2, 0, 1][face.group]
                            let base = Double(PlasmaCubeModel.basePalette[brightest])
                            let level = Double(model.palette[brightest]) * 64 / base
                            worstLight = max(worstLight, abs(Double(face.light) * 64 - level))
                            lightChecked += 1
                        }
                    }
                    model.tick()
                }
                check("Cube modern look is the same cube as the 1993 look at every step",
                      worstCorner <= 5 && worstLight <= 2 && differentFaces <= 20 && lightChecked > 1000,
                      "worst corner \(worstCorner) units, worst light \(worstLight) of 64 (\(lightChecked) checked), "
                          + "\(differentFaces) steps with a different set of faces")
            }
        }

        if SelfTest.wants("glenz-vectors glenz") {
            // Glenz Vectors. The 3600-step sine table against a checksum of MATHSIN.INC; the plate
            // picture (original artwork, kept as data) against checksums of FC.UH, which is byte for
            // byte what the program linked in as _FC.OBK.
            check("glenz sine table matches original MATHSIN.INC",
                  crc32(words16(GlenzModel.sine.map { Int16($0) })) == 1_760_842_562)
            check("glenz plate picture and its colours match original FC.UH",
                  crc32(GlenzFloorArt.pixels) == 1_371_256_604 && crc32(GlenzFloorArt.palette) == 294_416_773)
            // The 1993 pictures, against the original's own assembly text (MATH.ASM, VEC.ASM, NEW.ASM)
            // run instruction by instruction (tools/glenz_reference.py): the screen's colour numbers
            // and all 256 colours.
            var glenz = GlenzModel()
            let glenzSteps = [1, 100, 177, 214, 330, 420, 440, 600, 800, 925, 960, 980, 1000, 1014, 1100, 1300, 1500, 1700, 1900, 2050, 2100, 2200, 2250, 2300, 2340, 2359]
            var glenzSums: [[UInt32]] = [[], []]
            let glenzStart = glenz.classicReferenceFrame()
            for step in 1..<GlenzModel.lengthInTicks {
                glenz.tick()
                if glenzSteps.contains(step) {
                    glenzSums[0].append(crc32(glenz.screen))
                    glenzSums[1].append(crc32(glenz.colours))
                }
            }
            check("Glenz pictures match the original assembly at steps \(glenzSteps)",
                  glenzSums[0] == [1_475_827_238, 1_198_900_278, 2_128_776_517, 2_128_776_517, 2_049_735_344, 97_443_243, 1_267_192_796, 389_018_312, 3_701_128_063, 1_434_470_769, 55_326_528, 2_908_534_221, 1_887_063_064, 3_036_571_660, 1_212_644_248, 723_950_535, 1_740_146_126, 563_560_407, 1_355_435_813, 4_020_491_463, 1_814_432_785, 2_258_457_995, 959_312_536, 3_804_102_944, 3_645_819_784, 3_750_939_033],
                  "\(glenzSums[0])")
            check("Glenz palettes match the original assembly at the same steps",
                  glenzSums[1] == [598_395_524, 598_395_524, 598_395_524, 1_068_706_964, 239_537_398, 857_862_542, 2_809_852_906, 1_788_019_199, 2_608_372_831, 1_774_669_999, 2_266_534_623, 2_114_222_140, 2_022_150_290, 4_156_311_231, 1_274_690_563, 2_422_693_122, 752_574_599, 1_118_943_418, 3_632_057_437, 2_921_458_546, 610_749_747, 1_277_248_279, 2_860_270_479, 1_769_274_053, 4_017_522_155, 3_807_903_798],
                  "\(glenzSums[1])")
            let glenzEnd = glenz.classicReferenceFrame()
            glenz.tick()
            check("Glenz is black at both ends and loops after \(GlenzModel.lengthInTicks) steps",
                  glenz.ticks == 0 && !glenzStart.contains { $0 != 0 } && !glenzEnd.contains { $0 != 0 }
                      && glenz.classicReferenceFrame() == glenzStart)
            // Glenz, modern look in motion, over one whole loop and into the next.
            //  1. At the start of every step the modern look's corners are where the 1993 look's are (the 1993
            //     ones are rounded to whole pixels and use a squash rounded to whole steps, so "within 3 pixels").
            //  2. Where one step's glide ends the next one's begins. With 1, that means every glide runs from
            //     the 1993 position at one step to the 1993 position at the next, and never across anything else.
            //  3. The plate never moves further in a step than it is falling (it used to snap up by most of a
            //     row on the step it settled).
            do {
                var g = GlenzModel()
                var worstOffset: Float = 0, worstBreak: Float = 0, worstPlate: Float = 0
                var compared = 0
                var problems: [String] = []
                var plateProblems: [String] = []
                func note(_ text: String, in list: inout [String]) { if list.count < 5 { list.append(text) } }
                for step in 1...(GlenzModel.lengthInTicks + 250) {
                    let endOfGlide = [false, true].map { g.modernCorners(second: $0, alpha: 1) }
                    let plateEnd = g.modernPlateRow(alpha: 1)
                    let speedBefore = abs(g.plateSpeed)
                    g.tick()
                    if let end = plateEnd, let start = g.modernPlateRow(alpha: 0), abs(end - start) > 1e-4 {
                        note("plate breaks at step \(step)", in: &plateProblems)
                    }
                    if let start = g.modernPlateRow(alpha: 0), let end = g.modernPlateRow(alpha: 1), !g.mainStarted {
                        let moved = abs(end - start)
                        worstPlate = max(worstPlate, moved)
                        // The fall's speed is in sixteenths of a row per step and changes by one a step.
                        if moved > Float(max(speedBefore, abs(g.plateSpeed)) + 1) / 16 {
                            note("plate moves \(moved) rows in step \(step)", in: &plateProblems)
                        }
                    }
                    for second in [false, true] {
                        let drawn = g.mainStarted && g.script.frame >= 1
                            && (second ? g.script.frame > 800 && g.script.bscale > 4 : g.script.xscale > 4)
                        let now = g.modernCorners(second: second, alpha: 0)
                        if drawn != (now != nil) { note("step \(step): drawn in one look only", in: &problems) }
                        guard let now else { continue }
                        let classic = g.screenCorners(second: second)
                        for (a, b) in zip(now, classic) {
                            worstOffset = max(worstOffset, simd_length(a - SIMD2(Float(b.x), Float(b.y))))
                        }
                        compared += 1
                        if let end = endOfGlide[second ? 1 : 0] {
                            let gap = zip(now, end).map { simd_length($0 - $1) }.max() ?? 0
                            worstBreak = max(worstBreak, gap)
                            if gap > 0.1 { note("step \(step): glide breaks by \(gap) pixels", in: &problems) }
                        }
                    }
                }
                check("Glenz modern look follows the 1993 corners and glides without a break (\(compared) glenz-steps)",
                      problems.isEmpty && worstOffset < 3 && compared > 3000,
                      problems.isEmpty
                          ? "furthest from the 1993 corner \(String(format: "%.2f", worstOffset)) pixels, largest break \(String(format: "%.4f", worstBreak))"
                          : problems.joined(separator: "; "))
                check("Glenz modern plate never moves faster than it is falling",
                      plateProblems.isEmpty && worstPlate > 1,
                      plateProblems.isEmpty ? "largest move in a step \(String(format: "%.2f", worstPlate)) rows" : plateProblems.joined(separator: "; "))
            }

        }

        if SelfTest.wants("visu 3d engine ships city") {
            // The VISU 3D engine by itself (the Ships Fly-by and 3D City scenes, further down, are built on it).
            // Expected numbers come from tools/visu_reference.py, which runs the original assembly.
            check("VISU sine table matches the original file", crc32(words16(VisuTables.sine)) == 2_483_307_983)
            check("VISU field-of-view table matches the original file",
                  crc32(words(VisuTables.tangent)) == 2_796_670_327)
            check("VISU fill-division table matches the original file",
                  crc32(words(VisuTables.fillDivide)) == 1_375_704_783)
            do {
                var wrong: [String] = []
                var faults = 0
                for test in VisuTestCases.all {
                    let result = try VisuTest.classicPicture(test.kind)
                    faults += result.faults
                    if crc32(result.pixels) != test.checksum { wrong.append(test.name) }
                }
                check("VISU engine replay matches the original assembly in \(VisuTestCases.all.count) test pictures",
                      wrong.isEmpty, wrong.isEmpty ? "" : "differ: \(wrong.joined(separator: " "))")
                check("VISU engine replay met nothing the original would have crashed on", faults == 0,
                      faults == 0 ? "" : "\(faults) faults")
                let ships = try VisuWorld(name: "U2A"), city = try VisuWorld(name: "U2E")
                check("VISU scene data loads: ships 5 objects and 521 frames, city 57 objects and 1801 frames",
                      ships.objects.count == 6 && ships.frameCount == 521 && city.objects.count == 58 && city.frameCount == 1801,
                      "\(ships.objects.count - 1) / \(ships.frameCount), \(city.objects.count - 1) / \(city.frameCount)")

                // The modern look of the engine (triangles on the graphics chip) has no exact reference,
                // so it is held to the 1993 picture loosely: the average difference per colour channel
                // must stay small. (Measured over all cases when written: 5.0 at most, out of 255.)
                var far: [String] = []
                for name in ["ship-turn1", "ships-0060", "bigship-1", "logo-1", "city-0100", "city-0800", "city-1420"] {
                    guard let test = VisuTestCases.all.first(where: { $0.name == name }) else {
                        far.append("\(name): no such test case")
                        continue
                    }
                    let difference = try VisuTestCommand.difference(test.kind)
                    if difference > 8 { far.append("\(name) \(difference)") }
                }
                check("VISU modern look stays close to the 1993 picture in 7 test cases", far.isEmpty, far.joined(separator: ", "))
                let glides = "VISU modern look glides between animation frames"
                if let test = VisuTestCases.all.first(where: { $0.name == "city-0800" }) {
                    let still = try VisuTestCommand.modern(test.kind, blend: 0)
                    let between = try VisuTestCommand.modern(test.kind, blend: 0.5)
                    let moved = zip(still, between).reduce(0) { $0 + ($1.0 != $1.1 ? 1 : 0) }
                    check(glides, moved > 1000 && moved < still.count / 2, "\(moved) bytes differ")
                } else {
                    check(glides, false, "no test case city-0800")
                }
                // The recording scales the big ship down as it leaves, and the original's light dims
                // with that scale. The modern look must do the same (it once normalised the scale away:
                // +4.5 here, against +0.7 now).
                let lights = "VISU modern look lights a scaled object as the 1993 rule does (the big ship, ships frame 100)"
                if let test = VisuTestCases.all.first(where: { $0.name == "ships-0100" }) {
                    let lean = try VisuTestCommand.brightnessLean(test.kind)
                    check(lights, lean.pixels > 50_000 && abs(lean.lean) < 2.5,
                          String(format: "modern is %+.2f of 255 brighter on average over %d ship pixels", lean.lean, lean.pixels))
                } else {
                    check(lights, false, "no test case ships-0100")
                }

                // Both whole animations, every frame, through the 1993 replay: nothing the original
                // would have crashed on, and one engine drawing every frame in turn gives exactly the
                // pictures a fresh engine gives for each frame alone (so what the engine carries over
                // from picture to picture, see docs/visu-engine.md "Kept quirks", changes no pixel).
                var loopFaults = 0, carriedOver: [String] = [], framesDrawn = 0
                for scene in ["U2A", "U2E"] {
                    let world = try VisuWorld(name: scene)
                    if scene == "U2E" { world.distanceRule = VisuWorld.cityOrdering }
                    let one = VisuEngine()
                    VisuWorld.setSceneWindow(one)
                    while world.advance() {
                        one.clear(to: 0)
                        world.draw(with: one)
                        let fresh = VisuEngine()
                        VisuWorld.setSceneWindow(fresh)
                        world.draw(with: fresh)
                        loopFaults += fresh.faults
                        framesDrawn += 1
                        if fresh.pixels != one.pixels && carriedOver.count < 5 { carriedOver.append("\(scene) frame \(world.frame)") }
                    }
                    loopFaults += one.faults
                }
                check("VISU replay of both whole animations meets nothing the original would have crashed on",
                      framesDrawn == 2322 && loopFaults == 0, "\(framesDrawn) frames, \(loopFaults) faults")
                check("VISU replay: what the engine carries from picture to picture changes no pixel in either animation",
                      framesDrawn == 2322 && carriedOver.isEmpty, carriedOver.joined(separator: ", "))

                // Damaged data files must be turned away with an error, or load and draw, but never
                // crash; and the engine must hold a polygon that clipping would grow without end.
                let damaged = try VisuDamagedFiles.run()
                check("VISU loader turns damaged data files away instead of crashing",
                      damaged.tried > 2000 && damaged.refused > 500 && damaged.loaded > 500 && damaged.wronglyAccepted.isEmpty
                        && damaged.named == 32,
                      damaged.wronglyAccepted.isEmpty ? damaged.summary : "not turned away: \(damaged.wronglyAccepted.joined(separator: ", "))")
                // A palette byte above 63 (a damaged file): a VGA card used only its low six bits.
                let loud = try VisuWorld(name: "U2A") { name in
                    var file = try VisuData.load(name)
                    if name.hasSuffix(".00M") { for i in 16..<(16 + 768) { file[i] |= 0xC0 } }
                    return file
                }
                check("VISU loader keeps only the six bits of a palette level a VGA card used",
                      loud.palette == ships.palette && ships.palette.allSatisfy { $0 < 64 }, "")
                check("VISU engine stops a scribbled polygon growing past its record while being clipped",
                      damaged.scribblesStopped > 0, "\(damaged.scribblesStopped) corners refused")
            } catch {
                check("VISU engine test cases could be set up", false, "\(error)")
            }
        }

        if SelfTest.wants("ships-flyby ships visu") {
            // Ships Fly-by. The scene's 1993 pictures against the engine test pictures that match the
            // original assembly (drawn there into an empty screen by a fresh engine): wherever the test
            // picture has a ship pixel the scene must have the same colour number, and everywhere else
            // the scene must show its background picture untouched.
            do {
                let ships = try ShipsFlybyModel()
                let pause = ShipsFlybyModel.pauseSteps, length = ShipsFlybyModel.lengthInSteps
                let background = ships.background
                let firstPicture = ships.screen
                var expected: [Int: [UInt8]] = [:]
                for test in VisuTestCases.all {
                    if case .frame(let scene, let frame) = test.kind, scene == "U2A" {
                        expected[frame] = try VisuTest.classicPicture(test.kind).pixels
                    }
                }
                var differ: [Int] = []
                var pauseTouched = 0
                var firstShown = 0, lastShown = 0, shownAtEnd = 0, mostChanged = 0
                var glideGap: Float = 0, halfwayGap: Float = 0
                var glided = 0
                var previous = ships.screen
                for step in 1..<length {
                    let predicted = ships.pose(alpha: 1)
                    // Half-way through the glide every object must be half-way (not already at the
                    // next frame, and not still at this one).
                    let halfway = ships.pose(alpha: 0.5)
                    for item in halfway.items {
                        guard let from = ships.currentPose.items.first(where: { $0.object === item.object }),
                              let to = ships.nextPose.items.first(where: { $0.object === item.object }) else { continue }
                        for c in 0..<4 {
                            let middle = (from.matrix[c] + to.matrix[c]) * 0.5
                            halfwayGap = max(halfwayGap, simd_reduce_max(simd_abs(item.matrix[c] - middle)))
                        }
                        if from.matrix != to.matrix { glided += 1 }
                    }
                    ships.tick()
                    let frame = ShipsFlybyModel.animationFrame(atStep: step)
                    let screen = ships.screen
                    let shipPixels = zip(screen, background).reduce(0) { $0 + ($1.0 != $1.1 ? 1 : 0) }
                    if step <= pause { pauseTouched += shipPixels }
                    if shipPixels > 0 { if firstShown == 0 { firstShown = frame }; lastShown = frame }
                    if step == length - 1 { shownAtEnd = shipPixels }
                    // The biggest change between neighbouring pictures at the start and the end of the
                    // pass: a ship popping into view, rather than sliding in over the top edge at a few
                    // pixel rows a step, would show here.
                    if frame < 40 || frame > 470 {
                        mostChanged = max(mostChanged, zip(screen, previous).reduce(0) { $0 + ($1.0 != $1.1 ? 1 : 0) })
                    }
                    previous = screen
                    if let test = expected[frame], step > pause {
                        let same = (0..<screen.count).allSatisfy { test[$0] != 0 ? screen[$0] == test[$0] : screen[$0] == background[$0] }
                        if !same { differ.append(frame) }
                    }
                    // The modern look glides towards a pose worked out one frame ahead; at the end of
                    // the glide it must be exactly where the next step starts (else motion would jerk).
                    let now = ships.currentPose
                    if predicted.items.count == now.items.count {
                        for (a, b) in zip(predicted.items, now.items) where a.object === b.object {
                            for c in 0..<4 { glideGap = max(glideGap, simd_reduce_max(simd_abs(a.matrix[c] - b.matrix[c]))) }
                        }
                    } else if step < length - 1 && !predicted.items.isEmpty {
                        glideGap = .infinity
                    }
                }
                check("Ships pictures match the original assembly's at \(expected.count) animation frames (over the background)",
                      expected.count == 15 && differ.isEmpty, differ.isEmpty ? "" : "frames \(differ) differ")
                check("Ships: the pause shows only the background, and the background is the original file",
                      pauseTouched == 0 && firstPicture == background && crc32(background) == 913_980_884
                          && crc32(ships.palette) == 1_218_441_595,
                      "checksums \(crc32(background)), \(crc32(ships.palette))")
                check("Ships enter and leave gently (first seen at frame \(firstShown), last at \(lastShown))",
                      firstShown > 1 && lastShown == ShipsFlybyModel.animationFrames && shownAtEnd < 16 && mostChanged < 1200,
                      "\(shownAtEnd) ship pixels on the last step; at most \(mostChanged) pixels change per step near the ends")
                check("Ships modern look ends each glide exactly where the next step starts", glideGap < 0.001, "\(glideGap)")
                check("Ships modern look is half-way between frames half-way through a step",
                      glided > 900 && halfwayGap < 0.01, "\(glided) object moves checked, largest gap \(halfwayGap)")
                ships.tick()
                check("Ships loop after \(length) steps back to the empty horizon",
                      ships.step == 0 && ships.screen == firstPicture)

                // The two looks, drawn as the app draws them (960x720), must show the same thing. The
                // background alone differs a little (smooth against hard-edged scaling of the stars).
                func picture(_ look: Look, _ step: Int) throws -> [UInt8] {
                    guard let entry = SceneCatalog.all.first(where: { $0.id == "ships-flyby" }),
                          let data = try Snapshot.render(entry: entry, look: look, step: step, width: 960, height: 720)
                            .dataProvider?.data as Data? else { throw Snapshot.Failure.couldNotDraw }
                    return [UInt8](data)
                }
                var worst = 0.0
                for step in [0, 200, 330, 345, 400] {
                    let a = try picture(.classic, step), b = try picture(.modern, step)
                    var total = 0
                    for i in stride(from: 0, to: a.count, by: 4) {
                        total += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
                    }
                    worst = max(worst, Double(total) / Double(a.count / 4 * 3))
                }
                check("Ships modern look stays close to the 1993 picture at 5 steps", worst < 8,
                      String(format: "average difference at most %.2f of 255", worst))
            } catch {
                check("Ships Fly-by scene could be set up", false, "\(error)")
            }
        }

        if SelfTest.wants("city-3d city visu") {
            // 3D City. Like the ships: the scene's 1993 pictures against the engine test pictures that
            // match the original assembly (drawn there into an empty screen of colour 0 by a fresh
            // engine; the scene clears to colour 255 and draws every frame with one engine).
            do {
                let city = try City3DModel()
                let length = City3DModel.lengthInSteps
                let firstPicture = city.screen
                var expected: [Int: [UInt8]] = [:]
                for test in VisuTestCases.all {
                    if case .frame(let scene, let frame) = test.kind, scene == "U2E" {
                        expected[frame] = try VisuTest.classicPicture(test.kind).pixels
                    }
                }
                var differ: [Int] = []
                var glideGap: Float = 0, halfwayGap: Float = 0, worstRoll: Float = 0
                var glided = 0
                var shipLast = 0, shipFrames = 0, groundFirst = true
                var seconds = 0.0, slowest = 0.0
                for step in 1..<length {
                    // Where the glide will have got to by the end of this step.
                    let predicted = city.pose(alpha: 1)
                    let start = DispatchTime.now().uptimeNanoseconds
                    city.tick()
                    let took = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
                    seconds += took
                    slowest = max(slowest, took)
                    let frame = City3DModel.animationFrame(atStep: step)
                    let now = city.pose(alpha: 0)
                    // The glide must arrive exactly where the next step starts (else motion would jerk).
                    if predicted.items.count == now.items.count {
                        for (a, b) in zip(predicted.items, now.items) where a.object === b.object {
                            // Positions run to hundreds of thousands, so gaps are measured relative to size.
                            for c in 0..<4 {
                                let size = max(simd_reduce_max(simd_abs(b.matrix[c])), 1)
                                glideGap = max(glideGap, simd_reduce_max(simd_abs(a.matrix[c] - b.matrix[c])) / size)
                            }
                        }
                    } else if !predicted.items.isEmpty && step > 2 && step < City3DModel.lastFrameStep {
                        glideGap = .infinity
                    }
                    // On the second step of a frame the glide is half-way: every object must be at the
                    // middle of its two recorded places (turned by the camera-roll smoothing).
                    if step % 2 == 1 && step < City3DModel.lastFrameStep {
                        let angle = city.roll(blend: 0.5)
                        worstRoll = max(worstRoll, abs(angle))
                        for item in now.items {
                            guard let from = city.currentPose.items.first(where: { $0.object === item.object }),
                                  let to = city.nextPose.items.first(where: { $0.object === item.object }) else { continue }
                            let middle = VisuPose(items: [VisuPose.Item(object: item.object, matrix: (from.matrix + to.matrix) * 0.5)])
                                .rolled(by: angle).items[0].matrix
                            for c in 0..<4 {
                                let size = max(simd_reduce_max(simd_abs(middle[c])), 1)
                                halfwayGap = max(halfwayGap, simd_reduce_max(simd_abs(item.matrix[c] - middle[c])) / size)
                            }
                            if from.matrix != to.matrix { glided += 1 }
                        }
                    }
                    guard step % 2 == 0 && step <= City3DModel.lastFrameStep else { continue }
                    if let test = expected[frame] {
                        let screen = city.screen
                        let same = (0..<screen.count).allSatisfy { test[$0] != 0 ? screen[$0] == test[$0] : screen[$0] == 255 }
                        if !same { differ.append(frame) }
                    }
                    // U2E.C's two ordering rules, as the scene applies them.
                    let order = city.world.prepareFrame()
                    if frame > 900 && frame < 1100, order.contains(where: { $0.mesh.name.hasPrefix("\"s01") }) {
                        shipFrames += 1
                        // "Last" as U2E.C does it: the ship counts as distance 1, so only objects whose
                        // centre is BEHIND the camera (distance below 1) can still come after it.
                        if let at = order.firstIndex(where: { $0.mesh.name.hasPrefix("\"s01") }),
                           order[(at + 1)...].allSatisfy({ $0.distance <= 1 }) { shipLast += 1 }
                    }
                    var seenOther = false
                    for object in order {
                        if object.mesh.name.hasPrefix("\"_") { if seenOther { groundFirst = false } } else { seenOther = true }
                    }
                }
                check("City pictures match the original assembly's at \(expected.count) animation frames (over colour 255)",
                      expected.count == 45 && differ.isEmpty, differ.isEmpty ? "" : "frames \(differ) differ")
                check("City palette is the original file's with U2E.C's four changes; the screen starts black",
                      crc32(city.palette) == 2_445_111_768, "checksum \(crc32(city.palette))")
                check("City draws ground plates first always, and the ship last in frames 901...1099",
                      groundFirst && shipFrames > 150 && shipLast == shipFrames,
                      "after everything in front of the camera in \(shipLast) of the \(shipFrames) frames in which it is switched on")
                check("City modern look ends each glide exactly where the next step starts", glideGap < 0.0001, "largest relative gap \(glideGap)")
                check("City modern look is half-way between frames half-way through a frame",
                      glided > 5000 && halfwayGap < 0.0001, "\(glided) object moves checked, largest relative gap \(halfwayGap)")
                check("City camera-roll smoothing stays within half a degree of the recording",
                      worstRoll > 0.001 && worstRoll <= Float(City3DModel.rollTolerance * .pi / 180) + 0.0001,
                      String(format: "largest %.3f degrees", worstRoll * 180 / .pi))
                check("City 1993 replay keeps up with 70 steps a second with room to spare",
                      seconds / Double(length) < 0.002 && slowest < 0.010,
                      String(format: "%.3f ms a step on average, %.3f ms at worst; a step is 14.286 ms", seconds / Double(length) * 1000, slowest * 1000))
                let lastBrightness = City3DModel.brightness(atStep: Float(city.step))
                city.tick()
                check("City is black at both ends and loops after \(length) steps",
                      city.step == 0 && city.screen == firstPicture && !firstPicture.contains { $0 != 255 }
                          && lastBrightness == 0 && City3DModel.brightness(atStep: 0) == 0
                          && !city.classicReferenceFrame().contains { $0 != 0 })

                func picture(_ look: Look, _ step: Int) throws -> [UInt8] {
                    guard let entry = SceneCatalog.all.first(where: { $0.id == "city-3d" }),
                          let data = try Snapshot.render(entry: entry, look: look, step: step, width: 960, height: 720)
                            .dataProvider?.data as Data? else { throw Snapshot.Failure.couldNotDraw }
                    return [UInt8](data)
                }
                var worst = 0.0
                for step in [40, 660, 1600, 2000, 2920, 3560] {
                    let a = try picture(.classic, step), b = try picture(.modern, step)
                    var total = 0
                    for i in stride(from: 0, to: a.count, by: 4) {
                        total += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
                    }
                    worst = max(worst, Double(total) / Double(a.count / 4 * 3))
                }
                check("City modern look stays close to the 1993 picture at 6 steps", worst < 8,
                      String(format: "average difference at most %.2f of 255", worst))
            } catch {
                check("3D City scene could be set up", false, "\(error)")
            }
        }

        if SelfTest.wants("ships city threads sidebar") {
            // The sidebar builds and steps scenes on a background thread (for its small pictures) while
            // the main scene runs. The two 3D scenes read files and share the engine's tables, so: built
            // and stepped on four threads at once, they must draw exactly what one alone draws.
            do {
                func shipsPicture() throws -> [UInt8] {
                    let ships = try ShipsFlybyModel()
                    for _ in 0..<350 { ships.tick() }
                    return ships.screen
                }
                func cityPicture() throws -> [UInt8] {
                    let city = try City3DModel()
                    for _ in 0..<700 { city.tick() }
                    return city.screen
                }
                let alone = [try shipsPicture(), try cityPicture()]
                let lock = NSLock()
                var together = [[UInt8]?](repeating: nil, count: 4)
                DispatchQueue.concurrentPerform(iterations: 4) { i in
                    let picture = i % 2 == 0 ? try? shipsPicture() : try? cityPicture()
                    lock.lock()
                    together[i] = picture
                    lock.unlock()
                }
                check("Ships and City built and stepped on four threads at once draw what one alone draws",
                      (0..<4).allSatisfy { together[$0] == alone[$0 % 2] } && alone[0].contains { $0 != 0 })
            } catch {
                check("Ships and City could be built for the threads check", false, "\(error)")
            }
        }

        // Restart (the toolbar button) relies on every scene's `reset()` truly going back to the first frame.
        if let device = MTLCreateSystemDefaultDevice() {
            for entry in SceneCatalog.all where SelfTest.wants(entry) {
                guard let scene = try? entry.make(device, Renderer.pixelFormat) else {
                    check("\(entry.title) restarts from its first frame", false, "could not create the scene")
                    continue
                }
                let first = scene.classicReferenceFrame()
                for _ in 0..<entry.thumbnailStep { scene.tick() }
                let later = scene.classicReferenceFrame()
                scene.reset()
                let afterReset = scene.classicReferenceFrame()
                scene.tick()
                let fresh = try? entry.make(device, Renderer.pixelFormat)
                fresh?.tick()
                check("\(entry.title) restarts from its first frame",
                      afterReset == first && later != first && scene.classicReferenceFrame() == fresh?.classicReferenceFrame())
            }
        }

        if let only {
            if checksRun == 0 {
                print("No group of checks matches \"\(only)\" (try a scene id, \"demo\", \"music\" or \"core\").")
                ok = false
            }
            print("\(checksRun) checks run: only the groups matching \"\(only)\", NOT the full self-test.")
        } else {
            print("\(checksRun) checks run.")
            if checksRun != expectedChecks {
                print("FAIL  \(checksRun) checks ran, expected \(expectedChecks): a check stopped running, or one was added or removed without changing SelfTest.expectedChecks")
                ok = false
            }
        }
        print(ok ? "All checks passed." : "Some checks FAILED.")
        return ok
    }

    /// The top-left quarter (320x200) of a 640x400 picture: the part the original stored on disk.
    private static func quarter(of picture: [UInt8]) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(320 * 200)
        for y in 0..<200 {
            result.append(contentsOf: picture[(y * 640)..<(y * 640 + 320)])
        }
        return result
    }

    /// A standard checksum (CRC-32): a single number that changes if any byte of the data changes.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}
