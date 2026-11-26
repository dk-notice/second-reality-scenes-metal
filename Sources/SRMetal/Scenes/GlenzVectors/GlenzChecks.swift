import Foundation
import Metal

/// Self-test checks for Glenz Vectors inside Play Demo (run by `CoreChecks.run`; the scene's own checks
/// are in `App/SelfTest.swift`).
extension CoreChecks {
    // MARK: - Glenz Vectors inside Play Demo (added 2026-11-25)

    static func glenzInDemo(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        // From the title picture, so the hand-over can be compared. Loop step i is the glenz's step
        // i - shownAt, and music[i] is what the script reads on that step.
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("title-picture"))
        var music: [DemoMusicState] = [], shownAt = -1, titleScene: FadingPictureScene?, startsOnTitle = false
        var frames: [Int] = [], plateAt: [Int] = [], bars: [Int: [UInt8]] = [:], held = true, cue: Int?, nextAt = -1, grey = false
        var firstHold: [UInt8] = [], settledAt = -1
        for i in 0..<4000 {
            music.append(run.musicState)
            run.tick()
            if let t = run.sceneShowing as? FadingPictureScene, shownAt < 0 { titleScene = t; continue }
            guard let glenz = run.sceneShowing as? GlenzScene else {
                if shownAt >= 0 { if run.sceneShowing is DotTunnelScene { nextAt = i - shownAt }; break } else { continue }
            }
            let picture = glenz.classicReferenceFrame()
            if shownAt < 0 {
                shownAt = i
                startsOnTitle = titleScene.map { picture == $0.classicReferenceFrame() } ?? false
                firstHold = picture
            }
            let n = i - shownAt
            cue = glenz.leadIn?.cue
            if cue == nil && picture != firstHold { held = false }
            if let pass = glenz.leadIn?.wipePass, pass < 47, let numbers = glenz.leadIn?.classic.numbers {
                bars[pass] = [numbers[0], numbers[260 * 320], numbers[261 * 320 + 100], numbers[273 * 320 + 100], numbers[274 * 320], numbers[399 * 320]]
                if pass == 33, let lead = glenz.leadIn { grey = lead.classic.levels[0..<(lead.levels.count * 3)].allSatisfy { $0 == 30 } }
            }
            frames.append(glenz.inLeadIn ? -1 : glenz.model.script.frame)
            plateAt.append(glenz.inLeadIn ? -1 : glenz.model.plateShown ?? -1)
            if settledAt < 0 && glenz.model.plateSettled { settledAt = n }
        }
        // The script's line: `.frames(47), until { plus >= -19 }, .resetFrameCounter, .frames(177),
        // until { ticks >= 333 }, until(cap: 7000) { -16 < plus && plus < 0 }`. The counter counts music
        // ticks from the cue step, so the script's wait ends about 448 steps after the cue.
        let none = -9
        let scriptCue = shownAt < 0 ? none : (47..<(music.count - shownAt)).first { music[shownAt + $0].plus >= -19 } ?? none
        let firstPlate = plateAt.firstIndex { $0 >= 0 } ?? none
        let firstFrame = frames.firstIndex(of: 1) ?? none
        let scriptPauseEnd = shownAt < 0 || scriptCue < 0 ? none
            : ((scriptCue + 1)..<(music.count - shownAt)).first { music[shownAt + $0].ticks >= 333 } ?? none
        // (Pass 0's six sample points; empty if the wipe never ran, which fails the check.)
        let pass0 = bars[0] ?? []
        check("Play Demo: Glenz holds the title picture as the title part left it until the script's cue (music plus >= -19), then wipes it in 47 steps (black bars to rows 260 and 274 of 400, the picture greyed to level 30 from step 33)",
              startsOnTitle && held && scriptCue > 47 && cue == scriptCue
                && pass0.count == 6 && pass0[0] == 255 && pass0[5] == 255 && pass0[1] != 255
                && bars[46].map { $0[0] == 255 && $0[1] == 255 && $0[2] != 255 && $0[3] != 255 && $0[4] == 255 && $0[5] == 255 } == true && grey,
              "on title \(startsOnTitle), held \(held), cue \(cue ?? none) (script \(scriptCue)), pass 46 rows 0/260/261/273/274/399: \(bars[46] ?? []), grey \(grey)")
        check("Play Demo: Glenz's plate drops from the cue + 47 and settles after the script's 177 steps, the first glenz frame comes two steps after the music's tick counter reaches the script's 333 (cue + 450 in a full run: 448 steps of ticks), and the tunnel follows on the script's end cue with no second run",
              firstPlate == scriptCue + 47 && settledAt == scriptCue + 47 + 177 && scriptPauseEnd == scriptCue + 448
                && firstFrame == scriptPauseEnd + 2 && nextAt > firstFrame && frames.last == nextAt - firstFrame,
              "plate from \(firstPlate), settled at \(settledAt), counter 333 at cue + \(scriptPauseEnd - scriptCue), frame 1 at \(firstFrame), tunnel at \(nextAt), last frame \(frames.last ?? none)")
    }
}
