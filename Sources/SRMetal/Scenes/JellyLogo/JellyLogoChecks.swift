import CoreGraphics
import Foundation
import Metal
import simd

/// Self-test checks for the jelly logo (run by `CoreChecks.run`; see `App/CoreChecks.swift`).
extension CoreChecks {
    // MARK: - The jelly logo (added 2026-11-25)

    static func jellyLogo(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        func words(_ values: [Int]) -> [UInt8] {
            values.flatMap { v -> [UInt8] in let w = UInt16(bitPattern: Int16(v)); return [UInt8(w & 255), UInt8(w >> 8)] }
        }
        // The numbers below are printed by tools/jelly_reference.py from the original files.
        let sine = SelfTest.crc32(words(JellyLogoModel.sine))
        check("Jelly logo: its sine table (sin x 256, clamped to -255...255) equals JPLOGO's own SIN1024.INC",
              sine == 2_044_361_076, "\(sine)")
        let bounce = SelfTest.crc32(words(JellyLogoModel.bounce.top + JellyLogoModel.bounce.bottom))
        check("Jelly logo: the bounce worked out as JP.C does it gives the tool's 400 values", bounce == 4_110_166_704, "\(bounce)")
        let columns = SelfTest.crc32(words(JellyLogoModel.columns.flatMap { $0.map(Int.init) }))
        check("Jelly logo: the line-stretching columns (DOL.C's formula; the tool runs ZOOM.INC itself and finds the same)",
              columns == 1_153_435_020, "\(columns)")

        let scene = try JellyLogoScene(device: device, pixelFormat: Renderer.pixelFormat)
        let steps = [0, 1, 2, 3, 10, 40, 80, 84, 85, 86, 87, 90, 95, 105, 111, 115, 165, 225, 265, 365, 465, 470, 471,
                     565, 665, 785, 820]
        let expected: [UInt32] = [4_134_909_808, 4_134_909_808, 1_164_394_403, 3_628_095_181, 1_675_425_856,
                                  4_020_317_361, 2_810_486_268, 2_225_043_609, 2_225_043_609, 2_225_043_609,
                                  1_110_850_231, 2_223_395_136, 3_519_608_714, 1_789_395_902, 4_134_689_268,
                                  4_095_844_505, 411_417_014, 2_598_630_677, 2_836_110_265, 314_974_713,
                                  2_225_043_609, 2_225_043_609, 2_225_043_609, 2_225_043_609, 2_225_043_609,
                                  2_225_043_609, 2_225_043_609]
        var sums: [UInt32] = []
        var leftBlack = -1
        for step in 0...steps.last! {
            if steps.contains(step) { sums.append(SelfTest.crc32(scene.classicReferenceFrame())) }
            if step == 785 { leftBlack = scene.model.rowsLeftBlack }
            scene.tick()
        }
        check("Jelly logo: 1993 pictures match tools/jelly_reference.py at steps \(steps)", sums == expected, "\(sums)")
        check("Jelly logo: the row cache leaves 134 row-refreshes black, as the tool finds", leftBlack == 134, "\(leftBlack)")
        check("Jelly logo: on its own it starts again after 821 steps", scene.model.phase == .slide && scene.model.phaseStep == 0,
              "\(scene.model.phase) \(scene.model.phaseStep)")

        // Inside Play Demo: the jelly starts on the step the script gets past "music plus >= 4" (after its 86
        // steps of slide-in), and the city follows exactly 700 steps later.
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("jelly-logo"))
        var plusAt: [Int] = [], jellyAt = -1, cityAt = -1
        for step in 0..<2000 {
            plusAt.append(run.musicPlus)
            run.tick()
            if let jelly = run.sceneShowing as? JellyLogoScene, jellyAt < 0, jelly.model.phase == .jelly { jellyAt = step }
            if run.sceneShowing is City3DScene { cityAt = step; break }
        }
        // Loop step i is the (i + 1)th step after the one that showed the scene; the script waits 86 steps.
        let scriptJelly = (JellyLogoModel.slideSteps - 1..<plusAt.count).first { plusAt[$0] >= JellyLogoModel.musicCue } ?? -2
        check("Play Demo: the jelly logo follows the script to the step (slide-in, music cue, 700 steps, then the city)",
              jellyAt == scriptJelly && cityAt == scriptJelly + JellyLogoModel.jellySteps,
              "jelly \(jellyAt) (script \(scriptJelly)), city \(cityAt)")
    }
}
