import CoreGraphics
import Foundation
import Metal
import simd

/// Self-test checks for Play Demo: its running order against the music, and starting part-way (run by `CoreChecks.run`; see `App/CoreChecks.swift`).
extension CoreChecks {
    // MARK: - Play Demo's running order

    /// Play Demo's running order (added 2026-11-24): the script, run silently against the music,
    /// starts every part at the step the research simulation (`tools/demo_timeline.py`) gives.
    static func demoTimeline(_ check: (String, Bool, String) -> Void) {
        let (sequencer, problem) = DemoTimelineCommand.simulate()
        let wrong = DemoTimelineCommand.differences(sequencer.partStarts)
        check("Play Demo: all \(DemoTimelineCommand.expected.count) parts start on the step tools/demo_timeline.py gives (credits end 10:52.4)",
              wrong.isEmpty && problem == nil, problem ?? wrong.prefix(3).joined(separator: "; "))
        let ids = Set(SceneCatalog.all.map(\.id))
        let scenes = DemoScript.steps.compactMap { step -> String? in
            if case .show(.scene(let id)) = step { return id } else { return nil }
        }
        let unknown = scenes.filter { !ids.contains($0) }
        check("Play Demo: every scene it shows exists (\(scenes.count) uses)", unknown.isEmpty, unknown.joined(separator: ", "))
        // A scene can follow the music inside Play Demo: Techno Bars flashes on rows 7, 15, 23 ... of
        // the music it is given (KOE.C `waitborder`), once per row change, and the flash then dies away.
        var bars = TechnoBarsModel()
        var flashes: [Int] = []
        for row in [5, 6, 7, 7, 8, 14, 15] {
            bars.musicRow = row
            bars.tick()
            flashes.append(bars.shownFlash)
        }
        check("Play Demo: Techno Bars flashes on the music rows it is given (7, 15, ...), not on its own estimate",
              flashes == [0, 0, 15, 14, 13, 12, 15], "\(flashes)")
        // And Play Demo does give it the music: run the demo silently into the techno bars.
        if let device = MTLCreateSystemDefaultDevice(),
           let run = try? DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic()) {
            var agreed = 0, compared = 0
            for _ in 0..<14_500 {
                run.tick()
                if let techno = run.sceneShowing as? TechnoBarsScene {
                    compared += 1
                    // Given before the step, so at most one row behind (63 is one row behind 0). On the
                    // step the scene appears it has not been updated yet.
                    if let given = techno.model.musicRow {
                        if [0, 1].contains((run.musicRow - given + 64) % 64) { agreed += 1 }
                    } else if compared == 1 { agreed += 1 }
                }
            }
            check("Play Demo: a scene is told the music's position each step (Techno Bars, \(compared) steps)",
                  compared > 1000 && agreed == compared, "\(agreed) of \(compared)")
        }
        // The title and end pictures: fully in after 161 and 163 steps (as the demo script counts), and
        // inside Play Demo the end picture holds until "music plus" goes above -16, then fades to black.
        var title = FadingPictureModel(timing: FadingPictureScene.titleTiming)
        for _ in 0..<160 { title.tick() }
        let titleAlmost = title.fade().keep
        title.tick()
        var end = FadingPictureModel(timing: FadingPictureScene.endTiming)
        end.musicPlus = -32
        for _ in 0..<163 { end.tick() }
        let holding = end.phase
        for _ in 0..<2000 { end.tick() }
        let stillHolding = end.phase
        end.musicPlus = -10
        end.tick()
        check("Play Demo: the title picture is fully in after 161 steps, the end picture after 163, then holds for the music cue and fades out",
              titleAlmost == 128 && title.phase == .end && holding == .hold && stillHolding == .hold && end.phase == .fadeOut,
              "\(titleAlmost) \(title.phase) \(holding) \(stillHolding) \(end.phase)")
        // The troll: from the music cue, the scroll takes 53 refreshes and the shake 50 (as in the timing
        // research, tools/demo_timeline.py's "53 + 50"); the flash is 45 on the shake's second refresh.
        var troll = TrollModel()
        troll.musicCue = true
        var scrollSteps = 0, shakeSteps = 0, firstFlash = -1
        for _ in 0..<400 {
            troll.tick()
            if troll.phase == .scroll { scrollSteps += 1 }
            if troll.phase == .shake { shakeSteps += 1; if firstFlash < 0 && troll.flash > 0 { firstFlash = troll.flash } }
        }
        // On its own the troll starts again after its hold: the Modern look must not glide towards the
        // restart on the last step (it did: the troll showed half-way off the screen for one step).
        var alone = TrollModel()
        var glidesBack: [Int] = [], restartAt = -1
        for step in 1...600 where restartAt < 0 {
            let before = alone
            alone.tick()
            if before.phase == .hold && alone.phase == .wait { restartAt = step }
            if let after = before.next(), after.xpos < before.xpos - 100 { glidesBack.append(step) }
        }
        check("Troll: on its own it starts again after 438 steps, and the Modern look does not glide back across the restart",
              restartAt == 438 && glidesBack.isEmpty && TrollModel().next() != nil,
              "restart at \(restartAt), glides back on steps \(glidesBack)")
        check("Play Demo: the troll scrolls in over 53 refreshes, then shakes for 50 with a flash from 45",
              scrollSteps == 53 && shakeSteps == 50 && firstFlash == 45 && troll.xpos == 320,
              "\(scrollSteps) + \(shakeSteps), flash \(firstFlash), ends at \(troll.xpos)")
        // The switch-off: bands 32, 26 ... 3 (each 5/6 of the last), one line at refresh 14, a dot from 61,
        // 191 refreshes in all (121 + the original's sleep(1)).
        let line = SwitchOffModel.frame(at: 14), dot = SwitchOffModel.frame(at: 61)
        check("Play Demo: the screen switch-off collapses through bands 32, 26, 21, 17, 14, 11, 9, 7, 5, 4, 3 to a line and a dot, 191 refreshes",
              SwitchOffModel.bands == [32, 26, 21, 17, 14, 11, 9, 7, 5, 4, 3] && SwitchOffModel.length == 191
                && line.rows.filter { $0 >= 0 }.count == 2 && line.rows[200] == 133 && dot.dot == 63
                && SwitchOffModel.frame(at: 1).colour0 == 63, "\(SwitchOffModel.bands)")
        // SHUTDOWN.C waits once more (a third dis_waitb) after the quarter squash and before the band loop,
        // whose first wait comes before band 32: so refresh 3 still shows the quarter squash, band 32 is at
        // refresh 4 and band 4 at 13. Band 3 is made after the 14th wait and at once cut to the line, so it
        // never shows. (Found in the code review of 2026-11-24: the bands had been one refresh early.)
        func bandHeight(_ s: Int) -> Float { SwitchOffModel.frame(at: s).band.y }
        check("Play Demo: the switch-off's quarter squash shows for refreshes 2 and 3, bands 32 ... 4 at refreshes 4 ... 13 (SHUTDOWN.C's waits)",
              SwitchOffModel.frame(at: 3) == SwitchOffModel.frame(at: 2) && bandHeight(4) == 64 && bandHeight(13) == 8
                && SwitchOffModel.frame(at: 4).whiteFade == 31 && SwitchOffModel.frame(at: 13).whiteFade == 59,
              "refresh 3 band \(bandHeight(3)), 4: \(bandHeight(4)), 13: \(bandHeight(13))")
        // The end scroller (released text and font): a row every 2 refreshes, lines centred by the original's
        // rule, "[nn" = nn blank rows, "%" = back to the first line; the font has Y, Z and ä.
        if var scroller = try? EndScrollerModel.load() {
            let font = scroller.font
            let glyphs = [UInt8]("YZa".utf8) + [0x84]
            let firstLine = scroller.lines[0]
            let fresh = scroller
            for _ in 0..<(2 * 30) { scroller.tick() }
            let rows = scroller.rowsDrawn
            // The newest row (the 30th) is the bottom one, so row 5 of the first line is 24 rows above it.
            let screen = scroller.screen
            let r = EndScrollerModel.height - 1 - 24
            let firstInk = (0..<EndScrollerModel.width).first { screen[r * EndScrollerModel.width + $0] != 0 }
            // Find a gap line and the loop line, and check how many rows they take.
            let gapIndex = scroller.lines.firstIndex { $0.first == UInt8(ascii: "[") }
            let loopIndex = scroller.lines.firstIndex { $0.first == UInt8(ascii: "%") }
            var looped = false
            var probe = fresh
            var seenLoop = false
            for _ in 0..<(2 * 40_000) {
                probe.tick()
                if let last = probe.placed.last, last.line == loopIndex { seenLoop = true }
                if seenLoop, let last = probe.placed.last, last.line == 0 { looped = true; break }
            }
            check("End scroller: a row every 2 refreshes, the first line centred as the original did, the font has Y, Z, ä; the text loops at its % line",
                  rows == 30 && glyphs.allSatisfy { font.width[Int($0)] > 0 } && gapIndex != nil && loopIndex != nil && looped
                    && firstInk.map { $0 >= font.lineStart(firstLine) } == true,
                  "rows \(rows), first ink \(firstInk ?? -1) from \(font.lineStart(firstLine)), loop line \(loopIndex ?? -1), looped \(looped)")
            let blank = scroller.lines.first { $0 == [13] }
            check("End scroller: the Modern look draws no \"%\" for the loop line and nothing for blank lines, and keeps the text of the others",
                  loopIndex.map { EndScrollerScene.modernText(scroller.lines[$0]) } == "" && blank.map(EndScrollerScene.modernText) == ""
                    && EndScrollerScene.modernText([UInt8]("A\tb\r".utf8)) == "Ab"
                    && scroller.lines.filter { !EndScrollerScene.modernText($0).contains("%") }.count == scroller.lines.count,
                  "loop line: \"\(loopIndex.map { EndScrollerScene.modernText(scroller.lines[$0]) } ?? "none")\"")
            if let gapIndex {
                var gap = fresh
                while gap.placed.last.map({ $0.line != gapIndex - 1 }) ?? true { gap.tick() }
                // The line before the gap started; it takes 25 rows, then the gap, then the next line.
                let before = gap.placed.last!.firstRow
                while gap.placed.last!.firstRow == before { gap.tick() }
                let next = gap.placed.last!
                let height = Int(String(bytes: gap.lines[gapIndex][1...2], encoding: .ascii) ?? "") ?? -1
                check("End scroller: a \"[nn\" line is nn blank rows (line \(gapIndex): \(height))",
                      next.line == gapIndex + 1 && next.firstRow - before == EndScrollerFont.rows + height,
                      "next line \(next.line) after \(next.firstRow - before) rows")
            }
        } else {
            check("End scroller: its text and font are there", false, "")
        }
        demoTechnoTicks(check)
        let missing = DemoScript.pictures.filter { DemoPictures.url($0) == nil }
        check("Play Demo: every picture it shows is there (\(DemoScript.pictures.count) pictures)",
              missing.isEmpty, missing.joined(separator: ", "))
    }

    /// The music frame counter counts music ticks, not screen refreshes (found 2026-11-25 in the player's
    /// library, `MAIN/STMIK.300`), and the techno part reads it that way: the interference runs until 925
    /// ticks after the rings began, the bars until 2520.
    static func demoTechnoTicks(_ check: (String, Bool, String) -> Void) {
        // The rate: a tick when the 16-bit sum of the player's speed adjust overflows, once a refresh.
        let script: [DemoStep] = [.playSong(.second, order: 0), .frames(70 * 60), .playSong(.first, order: 0), .frames(70 * 60), .hold]
        let rate = DemoSequencer(music: SilentMusic(), steps: script)
        var perMinute: [Int] = []
        for step in 1...(70 * 120) {
            rate.tick()
            if step == 70 * 60 || step == 70 * 120 { perMinute.append(rate.tickCounter) }
        }
        check("Play Demo: the music frame counter counts music ticks, 52 a second in song 2 and 48 in song 1 (speed adjust 48700, 45000)",
              perMinute == [3121, 2883], "\(perMinute) in a minute each")
        // The techno part in a silent run: what shows, from which step, for how long.
        let sequencer = DemoSequencer(music: SilentMusic())
        var shows: [(visual: DemoVisual, step: Int)] = []
        var cue = -1
        sequencer.onShow = { [unowned sequencer] visual in shows.append((visual, sequencer.time)) }
        while !sequencer.finished && sequencer.time < 70 * 60 * 15 {
            if cue < 0, shows.last?.visual == .scene("interference"), sequencer.musicState.ticks >= 925 { cue = sequencer.time }
            sequencer.tick()
        }
        func length(_ id: String) -> Int {
            guard let i = shows.firstIndex(where: { $0.visual == .scene(id) }), i + 1 < shows.count else { return -1 }
            return shows[i + 1].step - shows[i].step
        }
        let shownAt = shows.first { $0.visual == .scene("interference") }?.step ?? 0
        // Measured from this silent run (2026-11-25). Counting refreshes gave 669 and 1,260 (section three
        // never seen); with ticks the interference ends on the beat before the lead-in's cue and the bars
        // just before the troll's.
        let interference = cue - shownAt, bars = length("techno-bars")
        let barsSectionThree = bars - TechnoBarsModel.sectionOneTicks - TechnoBarsModel.sectionTwoTicks
        check("Play Demo: the interference runs 989 steps to 925 music ticks, the techno bars 1,955 (their third section 695, to 2520 ticks)",
              interference == 989 && bars == 1955 && barsSectionThree == 695,
              "interference \(interference), bars \(bars)")
    }

    // MARK: - Play Demo from here (added 2026-11-24)

    /// Starting part-way: the script is run silently to the start, then carried on with music started
    /// that far into the song. From every scene the demo shows and every part, every later part must
    /// start on exactly the step a full run gives (this checks the hand-over and the music jump together).
    static func demoFromHere(_ check: (String, Bool, String) -> Void) {
        let starts = DemoScript.sceneIDs.map { DemoStart.scene($0) } + (1..<DemoScript.partNames.count).map { DemoStart.part($0) }
        var wrong: [String] = []
        for start in starts {
            guard let ahead = DemoSequencer.fastForward(to: start) else { wrong.append("\(start): never reached"); continue }
            let music = SilentMusic()
            let sequencer = DemoSequencer(continuing: ahead.sequencer, music: music)
            if let song = ahead.song { music.play(song, fromOrder: ahead.order, skipping: ahead.seconds) }
            while !sequencer.finished && sequencer.time < 70 * 60 * 15 { sequencer.tick() }
            let differences = DemoTimelineCommand.differences(sequencer.partStarts)
            if !differences.isEmpty || music.problem != nil {
                wrong.append("\(start): \(music.problem ?? differences.prefix(2).joined(separator: "; "))")
            }
        }
        check("Play Demo from here: started at each of \(starts.count) points (\(DemoScript.sceneIDs.count) scenes, \(DemoScript.partNames.count - 1) parts), every later part starts on the same step as a full run",
              wrong.isEmpty, wrong.prefix(3).joined(separator: " | "))
        // Found by the review (2026-11-24): a part that starts on the same step as the one after it (all its
        // waits already met) was never found, so the demo fell back to its beginning.
        let quick: [DemoStep] = [.part("A"), .show(.black), .frames(5), .part("B"), .part("C"), .show(.card("C")),
                                 .frames(5), .hold]
        let both = DemoSequencer.fastForward(to: .part(1), steps: quick)
        check("Play Demo from here: a part that starts on the same step as the next one is still found",
              both?.sequencer.partStarts.map(\.name) == ["A", "B", "C"] && both?.visual == .card("C"),
              "\(String(describing: both?.sequencer.partStarts.map(\.name)))")
        check("Play Demo from here: the command line takes scene ids and part numbers, and refuses others",
              DemoStart(argument: "troll") == .scene("troll") && DemoStart(argument: "11") == .part(10)
                && DemoStart(argument: "starfield") == nil && DemoStart(argument: "0") == nil
                && DemoStart(argument: "\(DemoScript.partNames.count + 1)") == nil, "")

        // The music jump itself: 2 seconds after skipping into a song are the same samples as those 2
        // seconds reached by playing the song through (song 2 at the troll and late, song 1 started from
        // section 18 as for the city).
        var report: [String] = []
        var good = true
        for (song, order, seconds) in [(Song.second, 0, 207.3), (Song.second, 0, 360.0), (Song.first, 18, 43.4)] {
            guard let straight = try? TrackerSong.wholeSong(song, fromOrder: order),
                  let jumped = try? TrackerSong.wholeSong(song, fromOrder: order) else { good = false; continue }
            var skip = [Float]()
            for _ in 0..<Int((seconds * 70).rounded()) { straight.render(into: &skip, frames: 630, sampleRate: 44_100) }
            jumped.skip(seconds: seconds, sampleRate: 44_100)
            var a = [Float](), b = [Float]()
            straight.render(into: &a, frames: 88_200, sampleRate: 44_100)
            jumped.render(into: &b, frames: 88_200, sampleRate: 44_100)
            let loud = a.contains { abs($0) > 0.01 }
            report.append("\(song.rawValue) from section \(order) + \(seconds) s: \(a == b ? "identical" : "different")\(loud ? "" : " (silent!)")")
            if a != b || !loud { good = false }
        }
        check("Play Demo from here: music skipped into is sample for sample what playing it through gives", good,
              report.joined(separator: "; "))
    }

    /// Play Demo started at a scene shows that scene at once, and the lens (whose cue is already met when
    /// it first shows) starts its uncovering on that first step, as in a full run.
    static func demoFromHereShown(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        let troll = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("troll"))
        let lens = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(), from: .scene("lens"))
        let lensPhase = (lens.sceneShowing as? LensScene)?.model.phase
        let credits = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic(),
                                       from: .part(DemoScript.partNames.firstIndex(of: "Credits") ?? 0))
        // Found by the review (2026-11-24): the music started before the first scene was built, so the song
        // ran ahead of the picture by the building time. The music must start with the scene already there.
        let recorder = RecordingMusic()
        let run = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: recorder, from: .scene("troll"))
        recorder.run = run
        run.reset()   // a restart starts part-way again, through the same steps as the first start
        check("Play Demo from here: the music starts only once the first scene is built",
              recorder.sceneShownAtPlay == [true], "\(recorder.sceneShownAtPlay)")
        check("Play Demo from here: starts showing the chosen scene (troll), the lens uncovering at once, and a part by number (credits)",
              troll.sceneShowing is TrollScene && troll.currentPart == "Rings, interference, techno bars, troll"
                && lensPhase == .reveal && credits.currentPart == "Credits" && credits.sceneShowing is CreditsScene,
              "troll: \(troll.currentPart ?? "-"), lens: \(String(describing: lensPhase)), credits: \(credits.currentPart ?? "-")")
    }
}

/// A music source for checks: silent music that notes, each time a song is started, whether Play Demo
/// already shows a scene.
private final class RecordingMusic: DemoMusicSource {
    private let silent = SilentMusic()
    weak var run: DemoRunScene?
    private(set) var sceneShownAtPlay: [Bool] = []
    func play(_ song: Song, fromOrder order: Int, skipping seconds: Double) {
        if run != nil { sceneShownAtPlay.append(run?.sceneShowing != nil) }
        silent.play(song, fromOrder: order, skipping: seconds)
    }
    var position: MusicPosition { silent.position }
    var orderList: [Int] { silent.orderList }
    func stepPassed() { silent.stepPassed() }
}
