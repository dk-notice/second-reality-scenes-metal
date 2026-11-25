import AppKit
import CoreText
import Foundation
import Metal

/// Self-test checks for the Opening Credits (run by `CoreChecks.run`; the scene's generic checks are in
/// `App/SelfTest.swift`).
extension CoreChecks {
    // MARK: - Opening credits (added 2026-11-25)

    static func openingCredits(_ check: (String, Bool, String) -> Void) {
        guard var model = try? OpeningCreditsModel.load() else {
            check("Opening credits: the released horizon and font load (Data/OpeningCredits)", false, "")
            return
        }
        // Against tools/alku_reference.py, which reads the released ALKU.EXE itself: CRC-32 of the 320x400
        // screen as VGA levels (red, green, blue), at steps counted from the part's start.
        let expected: [Int: UInt32] = [
            0: 4_134_909_808, 1128: 4_134_909_808, 1129: 4_134_909_808, 1158: 685_308_022, 1328: 2_385_917_007,
            1528: 3_803_357_441, 1555: 4_134_909_808, 1788: 3_878_147_216, 2179: 583_426_660, 2315: 583_426_660,
            2659: 4_134_909_808, 2660: 4_134_909_808, 2667: 331_545_143, 2668: 1_198_869_722, 2728: 2_428_043_535,
            2787: 4_238_211_454, 3387: 3_870_567_871, 3388: 3_371_959_433, 3419: 455_770_835, 3587: 1_529_167_386,
            3687: 1_717_398_282, 3730: 2_158_112_333, 4095: 3_700_753_731, 4653: 2_925_712_286, 5211: 537_088_689,
            5538: 251_311_783, 5539: 1_208_166_210, 5604: 1_208_166_210,
        ]
        model.reset(from: 0)
        var wrong: [String] = []
        for step in expected.keys.sorted() {
            while model.step < step { model.tick() }
            let (numbers, levels) = model.classicScreen()
            let sum = SelfTest.crc32(numbers.flatMap { c in (0..<3).map { UInt8(levels[Int(c) * 3 + $0]) } })
            if sum != expected[step] { wrong.append("step \(step): \(sum)") }
        }
        check("Opening credits: 1993 screens match tools/alku_reference.py (released horizon and font, titles, pages, scroll) at \(expected.count) steps",
              wrong.isEmpty, wrong.prefix(3).joined(separator: "; "))

        // The schedule from the measured cues, as the reference works it out; the part's length.
        check("Opening credits: titles on steps 1128, 1688 and 2115 (the third waits for the second to fade out), sync 4 on 2658, pages from 3388, 3946, 4504, 5062; 5,605 steps",
              model.titleStarts == [1128, 1688, 2115] && model.sync4 == 2658 && model.pageR == [3387, 3945, 4503, 5061]
                && OpeningCreditsModel.demoLength == 2658 + OpeningCreditsModel.endAfterSync4,
              "titles \(model.titleStarts), sync 4 \(String(describing: model.sync4)), pages \(model.pageR)")

        // On its own: from 70 steps before the first title to the part's end, then again.
        var alone = model
        alone.reset()
        let first = alone.step
        for _ in 0..<OpeningCreditsModel.standaloneLength { alone.tick() }
        check("Opening credits: on its own it runs \(OpeningCreditsModel.standaloneLength) steps from 70 before the first title, then starts again",
              first == 1058 && alone.step == first && alone.titleStarts.isEmpty, "from \(first), back at \(alone.step)")

        // The text at full height: tw_putpixel and the card both use 176-byte rows, so font rows 0 and 1 of a
        // letter are on lines next to each other (in the credits only every other row reached the screen).
        let g = model.font.glyphs["G"]!
        let x = 160 - model.font.width("Graphics") / 2 + 2, top = 100 + 50
        let row0 = (0..<g.width).map { model.pageBits[0][top * 320 + x + $0] }
        let row1 = (0..<g.width).map { model.pageBits[0][(top + 1) * 320 + x + $0] }
        check("Opening credits: the text shows every font row (176-byte rows for both the pixel routine and the card), 2 pixels right on pages",
              row0 == (0..<g.width).map { model.font.bits("G", column: $0, row: 0) }
                && row1 == (0..<g.width).map { model.font.bits("G", column: $0, row: 1) } && row0 != row1, "")

        // The end is the ships' start: the horizon's right half, on the lines the ships' picture uses.
        while model.step < 5604 { model.tick() }
        let (numbers, levels) = model.classicScreen()
        var same = numbers.count == 320 * 400
        if let ships = ScenePicture.pixels("02-ships-horizon"), ships.count >= 320 * 200 * 3 {
            for y in 0..<200 where same {
                for x in 0..<320 {
                    let c = Int(numbers[(2 * y) * 320 + x])
                    for ch in 0..<3 where vgaFromByte(ships[(y * 320 + x) * 3 + ch]) != levels[c * 3 + ch] { same = false }
                }
            }
        } else { same = false }
        check("Opening credits: the last screen is the ships' horizon exactly (the released ALKU hands its screen over)", same, "")

        openingCreditsModern(check, model: model)
    }

    /// The Modern look's text: Superclarendon, capitals 14 lines tall on the 1993 glyphs' lines, each line as
    /// wide as the 1993 line's ink: every line of all three titles and all four pages. And the logo's place.
    static func openingCreditsModern(_ check: (String, Bool, String) -> Void, model: OpeningCreditsModel) {
        let down = OpeningCreditsScene.down, across = OpeningCreditsScene.across
        let logo = OpeningCreditsScene.logoLines
        var worst = "", ok = true, linesMeasured = 0, logoClear = false
        for text in OpeningCreditsScene.allTexts {
            guard let image = OpeningCreditsScene.textImage(text, font: model.font), let data = image.dataProvider?.data,
                  let bytes = CFDataGetBytePtr(data) else {
                ok = false; worst = "no picture for \(text)"
                continue
            }
            // Titles are drawn from line 0 and centred; pages from line 100 and 2 pixels right.
            let lines: [(top: Int, text: String)], first: Int, right: Int
            switch text {
            case .title(let k): (lines, first, right) = (OpeningCreditsModel.titles[k], 0, 0)
            case .page(let k): (lines, first, right) = (OpeningCreditsModel.pages[k], 100, 2)
            case .none: continue
            }
            func inked(_ y: Int) -> Bool { (0..<image.width).contains { bytes[y * image.bytesPerRow + $0] > 128 } }
            // Each line: capitals from its line (+ 14 to the baseline) of the 400; ink across the 1993 line's width.
            for (top, line) in lines where line != "[" && line != "]" {
                let wantTop = CGFloat(first + top) * down, wantFoot = CGFloat(first + top + 14) * down
                let band = Int(wantTop) - 4..<Int(wantFoot) + 4
                let rows = band.filter(inked)
                let columns = (0..<image.width).filter { x in band.contains { bytes[$0 * image.bytesPerRow + x] > 128 } }
                let left = CGFloat(160 - model.font.width(line) / 2 + right) * across
                let rightEdge = left + CGFloat(model.font.width(line) - 2) * across
                // (A line with no capital, "in", has no ink at the capitals' top: only its foot is measured.
                // The typeface's f, l and d rise a little above its capitals, "Wildfire" by 2.2 picture rows,
                // under one of the 400 lines: allowed for, 3 rows above.)
                let above = wantTop - CGFloat(rows.first ?? 0)
                let topGood = !line.contains(where: \.isUppercase) || (above >= -2 && above <= 3)
                let good = topGood && abs(CGFloat(rows.last ?? 0) - wantFoot) <= 3
                    && abs(CGFloat(columns.first ?? 0) - left) <= 3 && abs(CGFloat((columns.last ?? 0) + 1) - rightEdge) <= 3
                if !good || worst.isEmpty {
                    worst += (worst.isEmpty ? "" : "; ") + "\(line): rows \(rows.first ?? -1)...\(rows.last ?? -1) (want \(Int(wantTop))...\(Int(wantFoot))), x \(columns.first ?? -1)...\(columns.last ?? -1) (want \(Int(left))...\(Int(rightEdge)))"
                }
                ok = ok && good
                linesMeasured += 1
            }
            // The third title's logo is a picture, not text: no letters where it goes.
            if text == .title(2) {
                logoClear = !(Int(CGFloat(logo.lowerBound) * down)..<Int(CGFloat(logo.upperBound) * down)).contains(where: inked)
            }
        }
        check("Opening credits: Modern text in Superclarendon, capitals as tall as the 1993 ones (14 lines) on the same lines, each line as wide as the 1993 line (all 19 lines of the 3 titles and 4 pages)",
              CTFontCopyPostScriptName(CTFontCreateWithName(OpeningCreditsScene.fontName as CFString, 10, nil)) as String == "Superclarendon-Regular"
                && ok && linesMeasured == 19,
              "\(linesMeasured) lines measured; " + worst)

        // The logo's picture covers exactly the lines the 1993 title has ink on below its "in".
        let bits = model.titleBits[2], w = OpeningCreditsModel.width
        let inkLines = (150..<OpeningCreditsModel.height).filter { y in (0..<w).contains { bits[y * w + $0] != 0 } }
        // (Its two glyphs are drawn from lines 160 and 179, 29 rows each; their last rows are empty.)
        check("Opening credits: the Modern logo is placed on the 1993 logo's lines (the two glyphs' rows, \(logo.lowerBound)...\(logo.upperBound - 1)), with no Modern text under it",
              logo == 160..<(179 + 29) && inkLines.first == logo.lowerBound && (inkLines.last ?? 999) < logo.upperBound && logoClear,
              "1993 ink on lines \(inkLines.first ?? -1)...\(inkLines.last ?? -1), text clear of it: \(logoClear)")
    }

    /// Inside Play Demo the scene shows from the part's first step for the script's steps, its model in step
    /// with the script, the music's cues on the steps the scene assumes on its own; then the ships' horizon.
    static func openingCreditsInDemo(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic())
        run.reset()
        // The script's own length for the part: the sum of its fixed waits and of its waits for cues.
        var shown = 0, inStep = true, cues: [Int] = [], lastSync = 0
        var scene = run.sceneShowing as? OpeningCreditsScene
        if scene == nil { run.tick(); scene = run.sceneShowing as? OpeningCreditsScene }
        let startStep = scene?.model.step ?? -1
        // The Modern look's pictures exist as soon as the scene does: none is left to be made on the frame it
        // first shows (each first shows on a music cue).
        let ready = scene?.modernPictures
        check("Opening credits: the Modern look's 7 text pictures, horizon and logo are made with the scene, not when first shown",
              ready?.texts == 7 && ready?.horizon == true && ready?.logo == true,
              "\(ready?.texts ?? -1) texts, horizon \(ready?.horizon ?? false), logo \(ready?.logo ?? false)")
        var schedule = ""
        for _ in 0..<7000 {
            guard let opening = run.sceneShowing as? OpeningCreditsScene else { break }
            schedule = "\(opening.model.titleStarts) \(String(describing: opening.model.sync4)) \(opening.model.pageR)"
            if opening.model.step != shown { inStep = false }
            let sync = run.musicState.sync
            if sync > lastSync { cues.append(shown + 1); lastSync = sync }   // (the music state for the coming step)
            shown += 1
            run.tick()
        }
        let after = run.pictureShowing
        let ends = DemoTimelineCommand.expected.first { $0.name == "Ships fly-by" }?.step ?? -1
        check("Play Demo: the opening credits show as their scene from step 0 for the script's \(ends) steps, in step with it, the music's sync rising on the steps the scene uses on its own; then the ships' horizon",
              startStep == 0 && shown == ends && inStep && Array(cues.prefix(9)) == OpeningCreditsModel.cues
                && after == "02-ships-horizon" && run.currentPart == "Ships fly-by" && schedule == "[1128, 1688, 2115] Optional(2658) [3387, 3945, 4503, 5061]",
              "schedule \(schedule), from \(startStep), shown \(shown), in step \(inStep), cues \(cues.prefix(9)), then \(run.currentPart ?? "?") showing \(after ?? "no picture")")
    }
}
