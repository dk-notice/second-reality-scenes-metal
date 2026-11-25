import Foundation
import Metal

/// Self-test checks for the Ships Fly-by inside Play Demo (run by `CoreChecks.run`; the scene's own
/// checks are in `App/SelfTest.swift`).
extension CoreChecks {
    // MARK: - Ships Fly-by inside Play Demo (added 2026-11-25)

    static func shipsInDemo(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        // Against the script's own line: the scene is shown, then `until(cap: 521) { order > 11 && row > 54 }`.
        // Run tick n takes the scene to its n-th step after the one it appeared on.
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("ships-flyby"))
        var frames: [Int] = [], goneAt = -1, cueMet = false
        let shownFirst = (run.sceneShowing as? ShipsFlybyScene)?.model.animationFrame ?? -1
        for tick in 1...600 {
            let music = run.musicState
            if music.order > 11 && music.row > 54 { cueMet = true }
            run.tick()
            guard let ships = run.sceneShowing as? ShipsFlybyScene else { goneAt = tick; break }
            frames.append(ships.model.animationFrame)
        }
        let wrong = frames.indices.first { frames[$0] != $0 + 1 }
        check("Play Demo: the ships fly the whole animation, a frame a step from the step they appear (frame 0), for the script's 521 steps, with no pause and no second pass; the music's end cue has not come",
              shownFirst == 0 && wrong == nil && frames.count == 520 && goneAt == 521 && !cueMet,
              "first \(shownFirst), \(frames.count) steps, first wrong \(wrong.map(String.init) ?? "none"), gone at \(goneAt), cue met \(cueMet)")
        let alone = try ShipsFlybyModel()
        for _ in 0..<ShipsFlybyModel.pauseSteps { alone.tick() }
        let atPauseEnd = alone.animationFrame
        alone.tick()
        check("Ships: on its own the 70-step pause on the empty horizon is still there",
              atPauseEnd == 0 && alone.animationFrame == 1 && alone.pause == 70, "frame \(atPauseEnd), then \(alone.animationFrame)")
    }
}
