import CoreGraphics
import Foundation
import Metal
import simd

/// Self-test checks for the mountain scroller (run by `CoreChecks.run`; see `App/CoreChecks.swift`).
extension CoreChecks {
    // MARK: - The mountain scroller (added 2026-11-25)

    static func mountain(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        // The numbers below are printed by tools/mountain_reference.py from the original files.
        let files = MountainData.fileNames.map { MountainData.bytes($0).map { SelfTest.crc32($0) } ?? 0 }
        check("Mountain scroller: the five files in Data/Mountain are the original ones (three position tables, background, text)",
              files == [378_142_248, 549_755_147, 2_732_334_271, 3_079_163_799, 4_166_226_341], "\(files)")
        guard let data = MountainData.load() else {
            check("Mountain scroller: its data loads", false, "")
            return
        }
        var owners = [Int](repeating: 0, count: 64000)
        for table in data.tables { for address in table.addresses { owners[Int(address)] += 1 } }
        let covered = owners.filter { $0 > 0 }.count, shared = owners.filter { $0 > 1 }.count
        check("Mountain scroller: the three tables share no pixel and together cover 15,592, as the tool finds",
              covered == 15_592 && shared == 0, "covered \(covered), shared \(shared)")

        // The Modern look's smooth map must agree with the tables it is fitted to: nearly every pixel's
        // fitted place lies inside its own third of a column and its own row.
        let map = data.smoothMap()
        var inThird = 0, inRow = 0
        for (k, table) in data.tables.enumerated() {
            for cell in 0..<(MountainData.columns * MountainData.rows) {
                for i in table.starts[cell]..<table.starts[cell + 1] {
                    let a = 4 * Int(table.addresses[i])
                    let third = Float(3 * (cell % MountainData.columns) + 2 - k) / 3, row = Float(cell / MountainData.columns)
                    if map.u[a] >= third - 0.02 && map.u[a] <= third + 1.0 / 3 + 0.02 { inThird += 1 }
                    if map.v[a] >= row - 0.05 && map.v[a] <= row + 1.05 { inRow += 1 }
                }
            }
        }
        check("Mountain scroller: the Modern look's smooth map keeps at least 85% of pixels inside their own third of a column and 95% inside their own row",
              inThird * 100 >= covered * 85 && inRow * 100 >= covered * 95, "third \(inThird), row \(inRow) of \(covered)")

        // The 1993 pictures against tools/mountain_reference.py (which replays the original files).
        let scene = try MountainScrollerScene(device: device, pixelFormat: Renderer.pixelFormat)
        let steps = [0, 1, 2, 33, 64, 65, 66, 67, 68, 70, 100, 150, 191, 192, 193, 400, 665, 1000, 1500, 1582, 1583, 1700, 1900, 1970, 1971, 1972, 1996, 2034, 2035]
        let expected: [UInt32] = [2441567436, 2441567436, 3620416002, 1242589623, 1242589623, 2647547826, 3626339823, 2500024216, 414966309, 1147760666, 2010288732, 3524332719, 2475179971, 400418958, 3879815575, 187692020, 2750253389, 4038711580, 3370711746, 9793332, 2647389365, 1578821385, 345458478, 4035520847, 3768542423, 757525783, 4139471472, 2441567436, 2441567436]
        var sums: [UInt32] = []
        for step in 0...steps.last! {
            if steps.contains(step) { sums.append(SelfTest.crc32(scene.classicReferenceFrame())) }
            scene.tick()
        }
        check("Mountain scroller: 1993 pictures match tools/mountain_reference.py at steps \(steps)", sums == expected, "\(sums)")
        check("Mountain scroller: on its own it starts again after 2,036 steps", scene.model.step == 0 && scene.model.scrollStart == nil,
              "step \(scene.model.step)")

        // Inside Play Demo, against the script's own steps: the scroll starts when the script gets past
        // "music plus >= 0" (after its 64 steps), the fade-out when it gets past "music plus = -11" (after
        // 127 more), and the lens follows 65 steps later.
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("mountain-scroller"))
        var plusAt: [Int] = [], scrollAt = -1, fadeAt = -1, lensAt = -1
        for step in 0..<3000 {
            plusAt.append(run.musicPlus)
            run.tick()
            if let mountain = run.sceneShowing as? MountainScrollerScene {
                scrollAt = mountain.model.scrollStart ?? -1
                fadeAt = mountain.model.fadeStart ?? -1
            }
            if run.sceneShowing is LensScene { lensAt = step; break }
        }
        // Loop step i takes the scene to its step i + 1 and is the script's (i + 1)th step after the one that
        // showed the scene. The script's cue steps:
        let scriptScroll = (MountainScrollerModel.fadeInSteps - 1..<plusAt.count).first { plusAt[$0] >= MountainScrollerModel.startCue } ?? -9
        let scriptFade = (scriptScroll + MountainScrollerModel.hillFadeDraws..<max(plusAt.count, scriptScroll + MountainScrollerModel.hillFadeDraws)).first {
            plusAt[$0] == MountainScrollerModel.endCue } ?? -9
        check("Play Demo: the mountain scroller follows the script to the step (scroll on the first cue, fade-out on the second, then the lens)",
              scrollAt == scriptScroll + 2 && fadeAt == scriptFade + 1 && lensAt == scriptFade + MountainScrollerModel.fadeOutSteps,
              "scroll \(scrollAt) (script \(scriptScroll)), fade \(fadeAt) (script \(scriptFade)), lens \(lensAt)")
        check("Mountain scroller: on its own the fade-out starts on the same scroll draw as in the demo",
              fadeAt - scrollAt == MountainScrollerModel.standaloneFadeDraw, "\(fadeAt - scrollAt)")
    }
}
