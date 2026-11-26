import Foundation
import Metal

/// Self-test checks for the Plasma inside Play Demo (run by `CoreChecks.run`; the scene's own checks are
/// in `App/SelfTest.swift`).
extension CoreChecks {
    // MARK: - Plasma inside Play Demo (added 2026-11-25)

    static func plasmaInDemo(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("plasma"))
        // Loop step i is the script's (i + 1)th step after the one that showed the scene; `music[i]` is what
        // the script and the scene both see on it.
        var music: [DemoMusicState] = [], falls: [Int] = [], sections: [Int] = [], nextAt = -1, cuedAt = -1
        var whiteWhileWaiting = true, palettes: [Int: [UInt8]] = [:], counters: [Int] = [], endedAt = -1, emptyAtEnd = false
        for step in 0..<3000 {
            music.append(run.musicState)
            run.tick()
            guard let plasma = run.sceneShowing as? PlasmaScene else {
                if run.sceneShowing is PlasmaCubeScene { nextAt = step }
                break
            }
            let model = plasma.model
            if model.cued && cuedAt < 0 { cuedAt = step }
            // White is a property of the palette (all 768 levels at 63): every pixel then shows white.
            if (cuedAt < 0 || cuedAt == step) && model.shownPalette.contains(where: { $0 != 63 }) { whiteWhileWaiting = false }
            if model.dropCounter == 2 { falls.append(step) }
            if sections.last != model.section { sections.append(model.section) }
            if model.ended && endedAt < 0 { endedAt = step }
            counters.append(model.dropCounter)
            palettes[step] = model.shownPalette
            if model.ended { emptyAtEnd = !plasma.classicReferenceFrame().contains { $0 != 0 } }
        }
        // The script's line: `until { plus >= 0 }, .resetFrameCounter, until { ticks > 1875 }, .frames(65)`.
        // The counter counts music ticks; in a full run it passes 723, 1491 and 1875 on the cue + 974,
        // + 2007 and + 2524.
        let none = -9
        let scriptCue = music.indices.first { music[$0].plus >= 0 } ?? none
        let scriptLast = music.indices.first { $0 > scriptCue && music[$0].ticks > 1875 } ?? none
        // The earlier falls are not in the script: PLZ.C's `timetable`. The program sees the counter pass
        // the number on one refresh; the band has moved on the next.
        let expectedFalls = PlasmaModel.timetable.map { limit in (music.indices.first { $0 > scriptCue && music[$0].ticks > limit } ?? none) + 1 }
        check("Play Demo: the plasma's screen is white until the script's cue (music plus >= 0) and on that step; its band falls a refresh after the music's tick counter passes 723, 1491 and the script's 1875 (cue + 975, 2008, 2525); the third fall ends it, as in the released program, and the plasma cube follows 65 steps after the script's wait, with no second run",
              scriptCue > 0 && whiteWhileWaiting && cuedAt == scriptCue && falls == expectedFalls && falls.last == scriptLast + 1
                && PlasmaModel.timetable == [723, 1491, 1875] && falls.map { $0 - scriptCue } == [975, 2008, 2525] && sections == [0, 1, 2] && endedAt == scriptLast + 64 && emptyAtEnd && nextAt == scriptLast + 65,
              "cue \(scriptCue), started \(cuedAt), falls \(falls) (expected \(expectedFalls)), sections \(sections), ended \(endedAt), next \(nextAt)")
        // The first fade: 127 refreshes down from white, shown a refresh late. The released program's
        // fade memory starts as zeros, so it ends ONE LEVEL ABOVE the palette (none of whose levels is 63).
        let palette0 = PlasmaModel.palettes[0].flatMap { [UInt8($0.x), UInt8($0.y), UInt8($0.z)] }
        let exact = palette0.map { $0 + 1 }
        let firstStep = palettes[scriptCue + 2] ?? []
        // (The levels are whole numbers, so they reach their last values a few refreshes before the fade's end.)
        let half = palettes[scriptCue + 64] ?? [], before = palettes[scriptCue + 100] ?? [], after = palettes[scriptCue + 128] ?? []
        check("Play Demo: the plasma's first palette fades down from white in 127 refreshes (the borders with it), white on its first step, and ends one level above the palette, as the released program's zeroed fade memory makes it",
              half.count == 768 && half[0] > 20 && half[0] < 45 && before != exact && after == exact
                && (palette0.max() ?? 63) <= 62 && firstStep.count == 768 && !firstStep.contains { $0 < 62 }
                && scriptCue + 128 < counters.count && counters[scriptCue + 127] == 255 && counters[scriptCue + 128] == 0,
              "colour 0 half-way \(half.first ?? 0), one above the palette at +128: \(after == exact), at +100: \(before == exact), lowest level on the first step \(firstStep.min() ?? 0), colour 0 ends at \(after.first ?? 99)")
    }
}
