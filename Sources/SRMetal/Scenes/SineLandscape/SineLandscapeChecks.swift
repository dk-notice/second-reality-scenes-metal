import Foundation
import Metal

/// Self-test checks for the 3D Sine Landscape inside Play Demo (run by `CoreChecks.run`; the scene's own
/// checks are in `App/SelfTest.swift`).
extension CoreChecks {
    // MARK: - 3D Sine Landscape inside Play Demo (added 2026-11-25)

    static func landscapeInDemo(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("sine-landscape"))
        // Loop step i is the script's (i + 1)th step after the one that showed the scene; `music[i]` is what
        // the script and the scene both see on it.
        var music: [DemoMusicState] = [], ticks: [Int] = [], rise: [Int] = [], startedAt = -1, nextAt = -1
        var blackBefore = true
        for step in 0..<3000 {
            music.append(run.musicState)
            run.tick()
            guard let land = run.sceneShowing as? SineLandscapeScene else {
                if run.sceneShowing is JellyLogoScene { nextAt = step }
                break
            }
            if land.model.started && startedAt < 0 { startedAt = step }
            if startedAt < 0 && land.classicReferenceFrame().contains(where: { $0 != 0 }) { blackBefore = false }
            ticks.append(land.model.ticks)
            rise.append(land.model.startRise)
        }
        // The script's line: `until { plus >= 0 }, until(cap: 4444) { -7 <= plus && plus <= -1 }`.
        let none = -9
        let scriptCue = music.indices.first { music[$0].plus >= 0 } ?? none
        let scriptEnd = music.indices.first { $0 > scriptCue && -7 <= music[$0].plus && music[$0].plus <= -1 } ?? none
        // The sinking is not in the script: MAIN.C line 62, `a>-30 && a<0`, read at the top of a pass. A
        // pass begins on the scene's odd steps, and its picture (two lines lower) shows a step later.
        let sourceSink = music.indices.first { $0 > scriptCue && -30 < music[$0].plus && music[$0].plus < 0 } ?? none
        let pass = (sourceSink - scriptCue) % 2 == 1 ? sourceSink : sourceSink + 1
        let risenAt = rise.firstIndex(of: 0) ?? none
        let sinkAt = rise.indices.first { $0 > risenAt && rise[$0] > 0 } ?? none
        let sunkAt = rise.indices.first { $0 > sinkAt && rise[$0] == 160 } ?? none
        check("Play Demo: the sine landscape is black until the script's cue (music plus >= 0), its first picture comes two steps later, and it is cut on the script's end cue (-7 ... -1) without starting again",
              scriptCue > 0 && blackBefore && startedAt == scriptCue && ticks.firstIndex(of: 2) == scriptCue + 2
                && nextAt == scriptEnd && (ticks.last ?? 0) == scriptEnd - 1 - scriptCue,
              "cue \(scriptCue), started \(startedAt), first picture \(ticks.firstIndex(of: 2) ?? none), end \(scriptEnd), next \(nextAt), last step \(ticks.last ?? none)")
        check("Play Demo: the sine landscape rises in 160 steps, starts sinking on the first pass that reads music plus above -30, and is out of sight before the cut",
              risenAt == scriptCue + 160 && sinkAt == pass + 1 && sunkAt == sinkAt + 158 && sunkAt < nextAt,
              "risen \(risenAt), sink cue \(sourceSink), sinking \(sinkAt), sunk \(sunkAt), cut \(nextAt)")
    }
}
