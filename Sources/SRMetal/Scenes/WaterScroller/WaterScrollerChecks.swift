import CoreGraphics
import Foundation
import Metal
import simd

/// Self-test checks for the water scroller (run by `CoreChecks.run`; see `App/CoreChecks.swift`).
extension CoreChecks {
    // MARK: - The water scroller (added 2026-11-25)

    static func water(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        // The numbers below are printed by tools/water_reference.py from the original files.
        let files = WaterData.fileNames.map { WaterData.bytes($0).map { SelfTest.crc32($0) } ?? 0 }
        check("Water scroller: the five files in Data/Water are the original ones (three position tables, background, sword)",
              files == [1_270_191_672, 1_767_181_635, 2_160_772_262, 2_488_653_010, 3_553_595_596], "\(files)")
        guard let data = WaterData.load() else {
            check("Water scroller: its data loads", false, "")
            return
        }
        var owners = [Int](repeating: 0, count: 64000)
        for table in data.tables { for address in table.addresses { owners[Int(address)] += 1 } }
        let covered = owners.filter { $0 > 0 }.count, shared = owners.filter { $0 > 1 }.count
        check("Water scroller: the three tables share no pixel and together cover 20,858, as the tool finds",
              covered == 20_858 && shared == 0, "covered \(covered), shared \(shared)")

        // The Modern look's smooth map against the tables it is fitted to: on the sea and the large
        // reflection nearly every pixel's fitted place lies inside its own third of a column and its own
        // row; the tiny reflections' pixels (437, the tool's regions under 1,000) keep their cell's middle.
        let map = data.smoothMap()
        var inThird = 0, inRow = 0, planes = 0, small = 0, smallExact = 0
        for (k, table) in data.tables.enumerated() {
            for cell in 0..<(WaterData.columns * WaterData.rows) {
                for i in table.starts[cell]..<table.starts[cell + 1] {
                    let a = 4 * Int(table.addresses[i])
                    let third = Float(3 * (cell % WaterData.columns) + 2 - k) / 3, row = Float(cell / WaterData.columns)
                    if map.u[a + 3] == 2 {
                        small += 1
                        if abs(map.u[a] - third - 1.0 / 6) < 1e-4 && map.v[a] == row + 0.5 { smallExact += 1 }
                        continue
                    }
                    planes += 1
                    if map.u[a] >= third - 0.02 && map.u[a] <= third + 1.0 / 3 + 0.02 { inThird += 1 }
                    if map.v[a] >= row - 0.05 && map.v[a] <= row + 1.05 { inRow += 1 }
                }
            }
        }
        check("Water scroller: the Modern look's smooth map keeps at least 90% of the large regions' pixels inside their own third of a column and 98% inside their own row; the 437 pixels of the tiny reflections keep their own cell",
              inThird * 100 >= planes * 90 && inRow * 100 >= planes * 98 && small == 437 && smallExact == 437 && planes == 20_421,
              "third \(inThird), row \(inRow) of \(planes); small \(small), exact \(smallExact)")

        // The 1993 pictures against tools/water_reference.py (which replays the original files).
        let scene = try WaterScrollerScene(device: device, pixelFormat: Renderer.pixelFormat)
        let steps = [0, 1, 2, 3, 4, 5, 60, 61, 126, 127, 128, 300, 646, 647, 648, 649, 650, 655, 656, 700, 800, 1000, 1100, 1300, 1500, 1700, 1900, 1978, 1979, 1980, 1981, 2000, 2010, 2042, 2043]
        let expected: [UInt32] = [2441567436, 2441567436, 3538537506, 3538537506, 2375702125, 2375702125, 11846585, 11846585, 3302024643, 3302024643, 3302024643, 3302024643, 3302024643, 3302024643, 3302024643, 3302024643, 3302024643, 3302024643, 3302024643, 2088295904, 1165861665, 1088841768, 3212939654, 1113160670, 3360058019, 3402440222, 2437343223, 2088000132, 2029415100, 2237330666, 117771015, 328882099, 161504151, 2441567436, 2441567436]
        var sums: [UInt32] = [], palettes: [UInt32] = []
        for step in 0...steps.last! {
            if steps.contains(step) { sums.append(SelfTest.crc32(scene.classicReferenceFrame())) }
            if [61, 127, 1990].contains(step) { palettes.append(SelfTest.crc32(scene.model.shown)) }
            scene.tick()
        }
        check("Water scroller: 1993 pictures match tools/water_reference.py at steps \(steps)", sums == expected, "\(sums)")
        check("Water scroller: the palette with red fading twice as fast matches the tool at steps 61, 127 and 1990",
              palettes == [3_445_701_644, 367_137_592, 2_587_062_819], "\(palettes)")
        check("Water scroller: on its own it starts again after 2,044 steps", scene.model.step == 0 && scene.model.scrollStart == nil,
              "step \(scene.model.step)")

        // Inside Play Demo, against the script's own steps: the fade-in starts when the script gets past
        // "music plus >= 0", the scroll when (127 steps on) it gets past "another section, row >= 16", the
        // fade-out when it gets past "music plus = -11", and the sine landscape follows 65 steps later.
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("water-scroller"))
        var music: [DemoMusicState] = [], fadeInAt = -1, scrollAt = -1, fadeAt = -1, nextAt = -1
        for step in 0..<3000 {
            music.append(run.musicState)
            run.tick()
            if let water = run.sceneShowing as? WaterScrollerScene {
                fadeInAt = water.model.fadeBegin ?? -1
                scrollAt = water.model.scrollStart ?? -1
                fadeAt = water.model.fadeStart ?? -1
            }
            if run.sceneShowing is SineLandscapeScene { nextAt = step; break }
        }
        // Loop step i takes the scene to its step i + 1 and is the script's (i + 1)th step after the one that
        // showed the scene. The script's cue steps, from the script's own numbers (`DemoScript.steps`, the
        // water scroller's line), not the model's:
        let none = -9
        let scriptPlus = music.indices.first { music[$0].plus >= 0 } ?? none
        let noted = scriptPlus >= 0 ? music[scriptPlus].order : none
        let scriptSection = music.indices.first { $0 >= scriptPlus + 127 && music[$0].order != noted && music[$0].row >= 16 } ?? none
        let scriptFade = music.indices.first { $0 >= scriptSection && music[$0].plus == -11 } ?? none
        check("Play Demo: the water scroller follows the script to the step (fade-in on the first cue, scroll on the new section's row 16, fade-out on the third cue, then the sine landscape)",
              scriptPlus > 0 && fadeInAt == scriptPlus + 2 && scrollAt == scriptSection + 2 && fadeAt == scriptFade + 1
                && nextAt == scriptFade + 65,
              "fade-in \(fadeInAt) (script \(scriptPlus)), scroll \(scrollAt) (script \(scriptSection)), fade \(fadeAt) (script \(scriptFade)), next \(nextAt)")
        check("Water scroller: on its own the still picture is held as long, and the fade-out starts on the same scroll draw, as in the demo",
              scrollAt - fadeInAt - WaterScrollerModel.fadeInSteps == WaterScrollerModel.standaloneHold
                && fadeAt - scrollAt == WaterScrollerModel.standaloneFadeDraw,
              "hold \(scrollAt - fadeInAt - WaterScrollerModel.fadeInSteps), fade draw \(fadeAt - scrollAt)")
    }
}
