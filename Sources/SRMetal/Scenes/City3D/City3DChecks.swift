import Foundation
import Metal

/// Self-test checks for the 3D City inside Play Demo (run by `CoreChecks.run`; the scene's own checks are
/// in `App/SelfTest.swift`).
extension CoreChecks {
    // MARK: - 3D City inside Play Demo (added 2026-11-25)

    static func cityInDemo(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        // From the jelly logo, so the city gets its last screen. Loop step i is the city's step i - shownAt,
        // and the music given to it then, music[i], is what the script reads on that step.
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("jelly-logo"))
        var music: [DemoMusicState] = [], shownAt = -1, jelly: JellyLogoScene?, startsOnJelly = false
        var pictures: [Int: (numbers: [UInt8], height: Int, levels: [UInt8])] = [:]
        var frameAt: [Int: Int] = [:], cue: Int?, nextAt = -1, whitening: [UInt8] = []
        for i in 0..<5000 {
            music.append(run.musicState)
            run.tick()
            if let j = run.sceneShowing as? JellyLogoScene { jelly = j; continue }
            guard let city = run.sceneShowing as? City3DScene else {
                if shownAt >= 0, run.sceneShowing is FadingPictureScene { nextAt = i - shownAt }
                if shownAt >= 0 { break } else { continue }
            }
            if shownAt < 0 {
                shownAt = i
                startsOnJelly = jelly.map { city.classicReferenceFrame() == $0.classicReferenceFrame() } ?? false
            }
            let n = i - shownAt
            if let picture = city.model.demoPicture { pictures[n] = picture }
            let frame = city.model.world.frame
            if frameAt[frame] == nil { frameAt[frame] = n }
            cue = city.model.demo?.cue
            if city.model.step == 1801 * 2 + 1 { whitening = city.model.classicPalette }
        }
        let city = try City3DModel()   // its palette, U2E.C's `cp`
        // The script's line: `.frames(100), until { order > 18 }, .frames(1801 * 2 + 16)`.
        let none = -9
        let scriptCue = shownAt < 0 ? none : (100..<(music.count - shownAt)).first { music[shownAt + $0].order > 18 } ?? none
        func level(_ n: Int, _ colour: Int) -> Int { pictures[n].map { Int($0.levels[colour * 3]) } ?? none }
        check("Play Demo: the 3D City's lead-in starts on the jelly logo's last picture, whitens colours 1-253 2 levels a step (not the blank), draws its window on step 49 in 400 lines, doubles the lines on 50, fades 252 out from step 68 and has the city's palette on the script's step 100",
              startsOnJelly && level(10, 0) == level(0, 0) && level(10, 2) == min(level(0, 2) + 20, 63) && level(33, 2) == 63 && level(33, 254) == level(0, 254)
                && pictures[48]?.height == 400 && pictures[49]?.height == 400 && pictures[50]?.height == 200
                && pictures[49]?.numbers[30 * 320] == 254 && pictures[48]?.numbers[30 * 320] != 254
                && level(67, 252) == 63 && level(68, 252) == 61 && pictures[99]?.levels != city.palette && pictures[100]?.levels == city.palette,
              "starts on jelly \(startsOnJelly), colour 252 at 67/68: \(level(67, 252))/\(level(68, 252)), heights 48/49/50: \(pictures[48]?.height ?? none)/\(pictures[49]?.height ?? none)/\(pictures[50]?.height ?? none)")
        check("Play Demo: the 3D City waits for the script's cue (section > 18) with its window showing, shows animation frame 1 two steps later and frame 1801 1801 x 2 steps after the cue, then whitens for 16 steps until the end picture",
              scriptCue > 100 && cue == scriptCue && pictures[scriptCue + 1]?.height == 200 && pictures[scriptCue + 2] == nil
                && frameAt[1] == scriptCue + 2 && frameAt[1801] == scriptCue + 1801 * 2 && nextAt == scriptCue + 1801 * 2 + 16,
              "cue \(cue ?? none) (script \(scriptCue)), frame 1 at \(frameAt[1] ?? none), frame 1801 at \(frameAt[1801] ?? none), end picture at \(nextAt)")
        // The whitening's first step: written from colour 255 on, so 255 shows colour 0 + 4 and 1 shows 2 + 4.
        let cp = city.palette
        check("Play Demo: the 3D City's whitening starts 4 levels up with every colour showing the next one (U2E.C writes the palette from colour 255)",
              whitening.count == 768 && whitening[255 * 3] == min(cp[0] + 4, 63) && whitening[3] == min(cp[6] + 4, 63)
                && whitening[3 * 100 + 1] == min(cp[3 * 101 + 1] + 4, 63),
              "colour 255 \(whitening.count == 768 ? Int(whitening[765]) : none) from colour 0 \(cp[0])")
    }
}
