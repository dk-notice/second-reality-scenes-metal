import Foundation
import Metal

/// Self-test checks for the Plasma Cube inside Play Demo (run by `CoreChecks.run`; the scene's own
/// checks are in `App/SelfTest.swift`).
extension CoreChecks {
    // MARK: - Plasma Cube inside Play Demo (added 2026-11-25)

    static func plasmaCubeInDemo(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("plasma-cube"))
        // Loop step i is the script's (i + 1)th step after the one that showed the scene; `music[i]` is what
        // the script and the scene both see on it.
        var music: [DemoMusicState] = [], frames: [Int] = [], waiting: [Bool] = [], nextAt = -1
        var blackWhileWaiting = true, firstPictureLit = false, lastLit = -1
        for step in 0..<3000 {
            music.append(run.musicState)
            run.tick()
            guard let cube = run.sceneShowing as? PlasmaCubeScene else {
                if run.sceneShowing is BouncingDotsScene { nextAt = step }
                break
            }
            frames.append(cube.model.frames)
            waiting.append(cube.model.waiting)
            let lit = cube.classicReferenceFrame().contains { $0 != 0 }
            if cube.model.waiting && lit { blackWhileWaiting = false }
            if cube.model.frames == 1 && !cube.model.waiting { firstPictureLit = lit }
            if lit { lastLit = cube.model.frames }
        }
        // The script's line: `until { plus >= 13 }, until { -4 <= plus && plus < 0 }`.
        let none = -9
        let scriptCue = music.indices.first { music[$0].plus >= 13 } ?? none
        let scriptEnd = music.indices.first { $0 > scriptCue && -4 <= music[$0].plus && music[$0].plus < 0 } ?? none
        let stillWaiting = waiting.lastIndex(of: true) ?? none
        let wrong = frames.indices.first { $0 > scriptCue && frames[$0] != $0 - scriptCue }
        check("Play Demo: the plasma cube's screen is empty until the script's cue (music plus >= 13) and on that step; the n-th step after it shows the original's frame n, to the script's end cue (-4 ... -1), with no second run",
              scriptCue > 0 && blackWhileWaiting && stillWaiting == scriptCue && wrong == nil && firstPictureLit
                && nextAt == scriptEnd && (frames.last ?? 0) == scriptEnd - 1 - scriptCue,
              "cue \(scriptCue), empty to \(stillWaiting), first wrong \(wrong.map(String.init) ?? "none"), end \(scriptEnd), next \(nextAt), last frame \(frames.last ?? none)")
        check("Play Demo: the plasma cube has gone black before the cut (the original's cube is black from frame 1995)",
              lastLit > 1900 && lastLit < 1995 && (frames.last ?? 0) >= 1995, "last lit frame \(lastLit), last frame \(frames.last ?? none)")
    }
}
