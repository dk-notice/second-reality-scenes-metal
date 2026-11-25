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
        var shownFor = -1, screens: [TechnoLeadIn.Screen?] = [], gpu: [String] = [], waiting: [UInt8] = []
        let queue = device.makeCommandQueue()
        let texture = Renderer.makeClassicTexture(device: device, canvasSize: SIMD2(320, 200))
        for step in 0..<1600 {
            music.append(run.musicState)
            run.tick()
            guard let scene = run.sceneShowing as? InterferenceScene else { shownFor = step; break }
            let model = scene.model
            guard case .interference(let frame) = model.phase else { break }
            frames.append(frame)
            powers.append(InterferenceModel.wobblePower(frame: frame, inDemo: model.inDemo))
            firstColour.append(model.classicPalette()[1].x)   // lower ramp's 60 at the start, rotated
            screens.append(model.showsLeadIn ? model.leadIn?.screen : nil)
            if waiting.isEmpty, let screen = screens.last ?? nil, screen.columns == 1, screen.mix == 0 {
                let frame = model.classicReferenceFrame()
                waiting = [10, 300].flatMap { x in (0..<3).map { frame[(100 * 320 + x) * 3 + $0] } }
            }
            // The graphics chip draws the lead-in as the 1993 rules give it: a few steps of the wipes.
            if let screen = screens.last ?? nil, [6, 28, 120].contains(screen.rows) || (screen.columns == 4 && screen.mix == 0),
               let queue, let texture, let commands = queue.makeCommandBuffer() {
                Renderer.drawClassic(scene: scene, canvasSize: SIMD2(320, 200), into: texture, commands: commands)
                commands.commit()
                commands.waitUntilCompleted()
                var pixels = [UInt8](repeating: 0, count: 320 * 200 * 4)
                texture.getBytes(&pixels, bytesPerRow: 320 * 4, from: MTLRegionMake2D(0, 0, 320, 200), mipmapLevel: 0)
                let reference = scene.classicReferenceFrame()
                let wrong = (0..<(320 * 200)).filter { i in
                    (0..<3).contains { abs(Int(pixels[i * 4 + 2 - $0]) - Int(reference[i * 3 + $0])) > 1 }
                }.count
                gpu.append("\(screen.columns)/\(screen.rows)/\(screen.mix): \(wrong) wrong")
            }
        }
        // The script's line: `until { ticks >= 925 }, .frames(5)`. On the step the cue is met (loop step
        // 988, measured from the script's silent run: 989 pictures counting the show step) the flash begins:
        // the picture holds and its palette goes 32, 64, 192, 256 of the way to white, then stays.
        let cue = music.indices.first { music[$0].ticks >= 925 } ?? -9
        let held = cue > 0 && frames[cue...].allSatisfy { $0 == frames[cue - 1] } && frames[cue - 1] == cue
        let lastColour = cue > 0 ? firstColour[cue - 1] : -1
        let expected = [32, 64, 192, 256, 256].map { InterferenceModel.flashed(SIMD3(repeating: lastColour), mix: $0).x }
        let flash = cue > 0 ? Array(firstColour[cue..<(cue + 5)]) : []
        check("Play Demo: the interference runs to the script's 925 music ticks with the wobble at full (no shrinking back, no loop), then holds its last picture while the palette flashes 32, 64, 192, 256 of the way to white over the script's 5 steps",
              cue + 1 == 989 && held && powers[cue - 1] == 15 && powers[700...].allSatisfy { $0 == 15 }
                && flash == expected,
              "cue at \(cue), last frame \(cue > 0 ? frames[cue - 1] : -1), wobble \(cue > 0 ? powers[cue - 1] : -1), flash \(flash) (expected \(expected))")

        // The lead-in (KOE.C 230-316) follows the script's waits after those 5 steps: white until "music
        // plus" >= -3 and a row ending in 7; then each column takes the script's 21 steps (rows 1, 3, 6 ...
        // wiped, the palette 256, 224 ... 0 of the way to white), waits for the next such row, flashes
        // back over the script's 4 steps; the bars show on the step after the fourth flash.
        let start = cue + 5
        func firstBeat(from i: Int, needPlus: Bool) -> Int {
            (i..<music.count).first { (!needPlus || music[$0].plus >= -3) && music[$0].row & 7 == 7 } ?? -9
        }
        var expectedScreens: [TechnoLeadIn.Screen] = []
        var i = start
        let beat = firstBeat(from: start, needPlus: true)
        while i < beat { expectedScreens.append(.init(interference: false, columns: 0, rows: 0, mix: 256)); i += 1 }
        for b in 0..<4 {
            // KOE.C 287-301, worked out here as the original did: zya grows by one, zy by zya; a falls by 32.
            var zy = 0, zya = 0
            for a in stride(from: 256, to: -400, by: -32) {
                zya += 1; zy += zya
                expectedScreens.append(.init(interference: false, columns: b, rows: min(zy, 200), mix: max(a, 0))); i += 1
            }
            let next = firstBeat(from: i, needPlus: false)
            while i < next { expectedScreens.append(.init(interference: false, columns: b + 1, rows: 0, mix: 0)); i += 1 }
            for m in [32, 64, 192, 256] { expectedScreens.append(.init(interference: false, columns: b + 1, rows: 0, mix: m)); i += 1 }
        }
        let got = cue > 0 && start <= screens.count ? Array(screens[start...]).map { $0 ?? .init(interference: true, columns: -1, rows: -1, mix: -1) } : []
        let firstWrong = zip(got, expectedScreens).enumerated().first { $0.element.0 != $0.element.1 }
        check("Play Demo: after the flash the interference scene shows the techno lead-in on the script's waits: white until the cue, four columns wiped from the top on four beats (rows 1, 3, 6 ... in 21 steps, white fading to blue-grey), a flash back to white after each, the techno bars on the script's next step",
              !got.isEmpty && got == expectedScreens && shownFor == i,
              "\(got.count) steps, expected \(expectedScreens.count); bars at \(shownFor), expected \(i)"
                + (firstWrong.map { "; first difference at lead-in step \($0.offset): \($0.element.0) vs \($0.element.1)" } ?? ""))
        check("Play Demo: waiting for the beat after the first column, the wiped quarter is black and the rest blue-grey (45, 52, 60: KOE.C 270-272)",
              waiting == [0, 0, 0, 45, 52, 60], "\(waiting)")
        check("Play Demo: the graphics chip draws the techno lead-in as the 1993 rules give it (\(gpu.count) steps)",
              gpu.count >= 12 && gpu.allSatisfy { $0.hasSuffix(": 0 wrong") }, gpu.filter { !$0.hasSuffix(": 0 wrong") }.prefix(3).joined(separator: "; "))
    }
}
