import Foundation
import Metal

/// Self-test checks for the Interference inside Play Demo (run by `CoreChecks.run`; the scene's own checks
/// are in `App/SelfTest.swift`).
extension CoreChecks {
    // MARK: - Interference inside Play Demo (added 2026-11-25)

    static func interferenceInDemo(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("interference"))
        // Loop step i is the script's (i + 1)th step after the one that showed the scene; `music[i]` is what
        // the script and the scene both see on it.
        var music: [DemoMusicState] = [], frames: [Int] = [], powers: [Int] = [], firstColour: [Int] = []
        var shownFor = -1
        for step in 0..<1200 {
            music.append(run.musicState)
            run.tick()
            guard let scene = run.sceneShowing as? InterferenceScene else { shownFor = step; break }
            let model = scene.model
            guard case .interference(let frame) = model.phase else { break }
            frames.append(frame)
            powers.append(InterferenceModel.wobblePower(frame: frame, inDemo: model.inDemo))
            firstColour.append(model.classicPalette()[1].x)   // lower ramp's 60 at the start, rotated
        }
        // The script's line: `until { ticks >= 925 }, .frames(5)`. On the step the cue is met (loop step
        // 988, measured from the script's silent run: 989 pictures counting the show step) the flash begins:
        // the picture holds and its palette goes 32, 64, 192, 256 of the way to white, then stays.
        let cue = music.indices.first { music[$0].ticks >= 925 } ?? -9
        let held = cue > 0 && frames[cue...].allSatisfy { $0 == frames[cue - 1] } && frames[cue - 1] == cue
        let lastColour = cue > 0 ? firstColour[cue - 1] : -1
        let expected = [32, 64, 192, 256, 256].map { InterferenceModel.flashed(SIMD3(repeating: lastColour), mix: $0).x }
        let flash = cue > 0 ? Array(firstColour[cue...]) : []
        check("Play Demo: the interference runs to the script's 925 music ticks with the wobble at full (no shrinking back, no loop), then holds its last picture while the palette flashes 32, 64, 192, 256 of the way to white over the script's 5 steps",
              cue + 1 == 989 && shownFor == cue + 5 && held && powers[cue - 1] == 15 && powers[700...].allSatisfy { $0 == 15 }
                && flash == expected,
              "cue at \(cue), shown for \(shownFor), last frame \(cue > 0 ? frames[cue - 1] : -1), wobble \(cue > 0 ? powers[cue - 1] : -1), flash \(flash) (expected \(expected))")
    }
}
