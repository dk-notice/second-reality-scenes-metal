import Foundation

/// Self-test checks for the Credits (run by `CoreChecks.run`; the scene's generic checks are in
/// `App/SelfTest.swift`).
extension CoreChecks {
    // MARK: - Credits (added 2026-11-25)

    static func credits(_ check: (String, Bool, String) -> Void) {
        guard var model = try? CreditsModel.load() else {
            check("Credits: the released pictures and font load (Data/Credits)", false, "")
            return
        }
        // Against tools/credits_reference.py, which reads the released CRED.EXE itself (texts included):
        // CRC-32 of the 320x400 colour numbers, then the 768 palette levels.
        let expected: [Int: UInt32] = [
            0: 2_530_590_397, 1: 2_530_590_397, 2: 2_530_590_397, 10: 1_052_288_804, 50: 1_500_975_436,
            102: 1_356_099_243, 103: 1_356_099_243, 200: 1_356_099_243, 302: 1_356_099_243, 303: 1_356_099_243,
            304: 1_356_099_243, 330: 1_167_217_481, 361: 2_530_590_397, 362: 161_915_687, 3298: 1_893_235_030,
            3578: 2_943_402_910, 7390: 4_143_171_263, 7601: 1_874_785_026,
            // Every screen, held (step 250 of each): its picture, palette and released text.
            250: 1_356_099_243, 612: 2_262_592_141, 974: 573_360_732, 1336: 3_603_103_470, 1698: 2_015_040_808,
            2060: 2_398_083_192, 2422: 652_177_206, 2784: 3_721_136_725, 3146: 2_296_035_344, 3508: 187_913_537,
            3870: 4_105_834_506, 4232: 318_436_170, 4594: 637_592_050, 4956: 2_832_375_973, 5318: 3_292_934_523,
            5680: 670_706_359, 6042: 3_959_177_235, 6404: 516_142_990, 6766: 1_742_348_054, 7128: 3_254_020_165,
            7490: 4_143_171_263,
        ]
        var wrong: [String] = []
        for step in expected.keys.sorted() {
            while model.step < step { model.tick() }
            let sum = SelfTest.crc32(model.classicScreen() + model.palette(screen: model.screen))
            if sum != expected[step] { wrong.append("step \(step): \(sum)") }
        }
        check("Credits: 1993 screens match tools/credits_reference.py (released texts, pictures and font) at \(expected.count) steps",
              wrong.isEmpty, wrong.prefix(3).joined(separator: "; "))
        model.tick()
        check("Credits: 21 screens of 362 steps (1 + 102 sliding in + 200 still + 59 sliding out), then it starts again",
              CreditsModel.length == 7602 && model.step == 0
                && 1 + CreditsModel.slideInSteps + CreditsModel.holdSteps + CreditsModel.slideOutSteps == 362
                && CreditsModel.registers(local: 103) == CreditsModel.registers(local: 302),
              "\(CreditsModel.length) steps, back to \(model.step)")
        // The text is written with 320-wide rows into 640-wide video memory: only the font's even rows
        // reach the left half. Font row 1 of a line's first letter is on the right half (x + 320).
        let memory = model.memory(screen: 0)
        let a = model.font.glyphs["G"]!, x = 160 - model.font.width("GRAPHICS - MARVEL") / 2
        let evenRow = (0..<a.width).map { memory[8 * 640 + x + $0] }
        let oddRow = (0..<a.width).map { memory[8 * 640 + 320 + x + $0] }
        check("Credits: the text shows every other font row (written with 320-wide rows into 640-wide video memory)",
              evenRow == (0..<a.width).map { model.font.shade("G", column: $0, row: 0) }
                && oddRow == (0..<a.width).map { model.font.shade("G", column: $0, row: 1) } && evenRow != oddRow, "")
    }
}
