import CoreGraphics
import Foundation
import Metal
import simd

/// Self-test checks for the lens (run by `CoreChecks.run`; see `App/CoreChecks.swift`).
extension CoreChecks {
    // MARK: - The lens (added 2026-11-24)

    static func lens(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        func bytes(_ words: [UInt16]) -> [UInt8] { words.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] } }
        // CRC-32 of the original LENS.EX1, EX2, EX3 (made by CALC.C) and EX4 (kept as data).
        if let shape = LensTables.shape() {
            let sums = LensTables.calculated(shape: shape).map { SelfTest.crc32(bytes($0)) }
            check("Lens: tables 1-3 worked out from the lens shape (CALC.C, Microsoft C's random numbers) equal LENS.EX1-EX3",
                  sums == [1_001_590_135, 627_125_013, 3_430_398_850], "\(sums)")
        } else {
            check("Lens: the lens shape picture is there", false, "")
        }
        let ring = LensTables.ringTable().map { SelfTest.crc32(bytes($0)) }
        check("Lens: table 4 (Data/Lens/LENS.EX4) is the original file", ring == 224_138_840, "\(String(describing: ring))")
        // A damaged table must be turned away at load, not crash the first time the lens is drawn.
        let whole = LensTables.ringTable().map(bytes) ?? []
        var wrongCount = whole
        if wrongCount.count > 3 { wrongCount[2] = 0xFF; wrongCount[3] = 0xFF }      // row 0: 65,535 entries
        check("Lens: a damaged table 4 is turned away (empty, cut short, a row's count past the end)",
              !whole.isEmpty && LensTables.ringTable(bytes: whole) != nil && LensTables.ringTable(bytes: []) == nil
                && LensTables.ringTable(bytes: Array(whole.prefix(whole.count / 2 & ~1))) == nil
                && LensTables.ringTable(bytes: wrongCount) == nil,
              "\(whole.count) bytes")
        var path: [UInt8] = []
        for p in LensModel.path { path += bytes([UInt16(bitPattern: Int16(p.x)), UInt16(bitPattern: Int16(p.y))]) }
        check("Lens: the bounce path worked out from MAIN.C's formulas equals all 715 positions of LENS.EXP",
              SelfTest.crc32(path) == 559_201_181, "\(SelfTest.crc32(path))")

        // The 1993 pictures against tools/lens_reference.py (which uses the original table files).
        let scene = try LensScene(device: device, pixelFormat: Renderer.pixelFormat)
        let steps = [0, 34, 35, 36, 40, 60, 100, 114, 115, 200, 334, 335, 340, 366, 367, 400, 430, 500, 600, 700, 800,
                     900, 975, 1000, 1049, 1054, 1055, 1089]
        let expected: [UInt32] = [2_441_567_436, 2_441_567_436, 1_291_542_035, 4_155_724_161, 1_922_081_443,
                                  3_156_001_777, 293_539_554, 293_539_554, 293_539_554, 293_539_554, 293_539_554,
                                  1_668_326_939, 3_552_366_031, 4_035_894_649, 3_533_491_179, 1_718_687_769,
                                  381_870_674, 1_957_270_634, 2_240_968_228, 935_523_674, 3_310_632_696,
                                  2_392_859_912, 3_610_631_330, 136_985_401, 293_539_554, 293_539_554,
                                  293_539_554, 293_539_554]
        var sums: [UInt32] = []
        for step in 0...steps.last! {
            if steps.contains(step) { sums.append(SelfTest.crc32(scene.classicReferenceFrame())) }
            scene.tick()
        }
        check("Lens: 1993 pictures match tools/lens_reference.py at steps \(steps)", sums == expected, "\(sums)")
        check("Lens: on its own it starts again after 1090 steps", scene.model.phase == .black && scene.model.phaseStep == 0,
              "\(scene.model.phase) \(scene.model.phaseStep)")

        // Inside Play Demo the scene follows the music cues on the same steps as the script: the lens
        // starts exactly 720 steps before the script shows the rotozoomer, the uncovering at least 300 before.
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic())
        var shownAt = -1, revealAt = -1, lensAt = -1, rotozoomerAt = -1, cueAtStart = false
        var plusAt: [Int] = []   // the music each step's checks saw
        for step in 0..<22_000 {
            let plus = run.musicPlus   // the music this step's checks see (silent music moves on at its end)
            plusAt.append(plus)
            run.tick()
            if let lens = run.sceneShowing as? LensScene {
                if shownAt < 0 { shownAt = step; cueAtStart = plus >= LensModel.startCue }
                if revealAt < 0 && lens.model.phase == .reveal { revealAt = step }
                if lensAt < 0 && lens.model.phase == .lens { lensAt = step }
            } else if run.sceneShowing is RotozoomerScene, rotozoomerAt < 0 {
                rotozoomerAt = step
                break
            }
        }
        // The steps the script itself gets past its waits: "until plus >= -6" (then 300 steps), "until plus
        // >= -20" (then 720 steps, then the rotozoomer). Made exact by the review (2026-11-24).
        func firstStep(from: Int, where cue: (Int) -> Bool) -> Int {
            guard from >= 0 else { return -2 }
            return (from..<plusAt.count).first { cue(plusAt[$0]) } ?? -2
        }
        let scriptReveal = firstStep(from: shownAt) { $0 >= LensModel.startCue }
        let scriptLens = firstStep(from: scriptReveal + LensModel.revealSteps) { $0 >= LensModel.lensCue }
        check("Play Demo: the lens follows the script's music cues to the step (black, uncovering, lens, then the rotozoomer 720 steps later)",
              shownAt >= 0 && revealAt == scriptReveal && lensAt == scriptLens && rotozoomerAt == scriptLens + LensModel.lensSteps,
              "shown \(shownAt) (cue already \(cueAtStart)), uncovering \(revealAt) (script \(scriptReveal)), lens \(lensAt) (script \(scriptLens)), rotozoomer \(rotozoomerAt)")
    }
}
