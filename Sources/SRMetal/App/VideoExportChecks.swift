import CoreGraphics
import Foundation
import Metal

/// Self-test checks for the video export (`--export-video`; run by `CoreChecks.run`): that every
/// picture is drawn at its own moment of the same script whose sound it goes with. The finished FILE
/// is checked by `tools/check_video.py`.
extension CoreChecks {
    static func videoExport(_ check: (String, Bool, String) -> Void) {
        // Picture k belongs at k/60 s = 7k/6 steps, and its sound starts at sample pair 735k.
        var wrong: [Int] = []
        for frame in 0..<60_000 {
            let moment = VideoExport.moment(frame: frame)
            let sixths = (moment.blend * 6).rounded()
            let exact = abs(moment.blend * 6 - sixths) < 1e-4 && (0...5).contains(Int(sixths))
            if !exact || 6 * moment.step + Int(sixths) != 7 * frame
                || 6 * VideoExport.samplesPerFrame * frame != SilentMusic.framesPerStep * (6 * moment.step + Int(sixths)) {
                wrong.append(frame)
            }
        }
        check("Video export: picture k is drawn after 7k div 6 steps, (7k mod 6)/6 on, where its 735 sample pairs start",
              wrong.isEmpty && VideoExport.moment(frame: 6) == (7, 0) && VideoExport.moment(frame: 5).step == 5
                && VideoExport.samplesPerFrame == 735,
              "first wrong pictures: \(wrong.prefix(5))")

        // The sound: 630 pairs for every step whatever the music does, so it can never slip.
        let plan = VideoExport.plan
        let sound = VideoExport.sound(frames: plan.frames)
        let silent = SilentMusic()
        var counts: [Int] = [], heard = false
        silent.onSound = { counts.append($0.count); if $0.contains(where: { $0 != 0 }) { heard = true } }
        for _ in 0..<3 { silent.stepPassed() }
        let afterEnd = (plan.musicEnd + 1) * SilentMusic.framesPerStep * 2
        let lastSound = sound.lastIndex { $0 != 0 } ?? -1
        check("Video export: every step gives 630 sample pairs, silence before a song and after the last one ends",
              sound.count == plan.frames * VideoExport.samplesPerFrame * 2 && counts == [1260, 1260, 1260] && !heard
                && lastSound < afterEnd && lastSound > afterEnd - 2 * SilentMusic.sampleRate * 2,
              "\(sound.count) samples, the last sound at \(lastSound), the music ends by \(afterEnd); no song: \(counts), heard \(heard)")

        // No delay anywhere: song 2, which the script starts on the Glenz part's step, begins on
        // exactly that step's first sample pair.
        let glenz = DemoTimelineCommand.expected.first { $0.name == "Glenz vectors" }?.step ?? 0
        var alone: [Int16] = []
        if let song = try? TrackerSong.wholeSong(.second, fromOrder: 0) {
            var buffer = [Float]()
            for _ in 0..<70 {
                song.render(into: &buffer, frames: SilentMusic.framesPerStep, sampleRate: SilentMusic.sampleRate)
                alone += buffer.prefix(SilentMusic.framesPerStep * 2).map(VideoExport.sample16)
            }
        }
        let from = glenz * SilentMusic.framesPerStep * 2
        check("Video export: song 2 begins at sample pair 7,624 x 630, the step the script starts it on (no delay)",
              glenz == 7624 && alone.count == 88_200 && alone.contains { $0 != 0 }
                && Array(sound[from..<from + alone.count]) == alone,
              "the Glenz part at step \(glenz); \(alone.count) samples of the song alone")

        guard let device = MTLCreateSystemDefaultDevice() else {
            check("Video export: Metal device available", false, "")
            return
        }
        // Where it ends: with the demo (the end scroller's "%" line), on a whole step and a whole picture.
        let bare = DemoSequencer(music: SilentMusic())
        while !bare.finished && bare.time < 70 * 60 * 20 { bare.tick() }
        check("Video export: it runs to the demo's end (16:21.1) and no further: 58,866 pictures on 68,677 steps",
              bare.finished && plan.end == bare.time && plan.end == plan.scrollerStart + 1 + EndScrollerModel.demoLength
                && plan.frames % 6 == 0 && plan.steps >= plan.end && plan.steps < plan.end + 7
                && plan.scrollerStart == 45_670 && plan.musicEnd == 67_036 && plan.musicEnd < plan.textGone && plan.textGone < plan.end,
              "\(plan); the script ends after \(bare.time) steps")

        // The pictures: six in a row (every blend), each what `--snapshot play-demo` draws at that step
        // and blend, and the demo then at the same place in the script as a bare run of that many steps.
        let same = "Video export: pictures 8,898 to 8,903 are what --snapshot draws at their steps and blends, all different"
        let place = "Video export: the demo drawn is at the same place in the script as the sound (step 10,386)"
        do {
            let run = try VideoExport.Run(width: 96, height: 72)
            var pixels = [UInt8](repeating: 0, count: 96 * 72 * 4)
            var differing: [Int] = [], drawn: [[UInt8]] = []
            for frame in 8898...8903 {
                try run.draw(frame: frame, into: &pixels)
                let moment = VideoExport.moment(frame: frame)
                let image = try Snapshot.render(entry: DemoTimelineCommand.silentEntry, look: .modern, step: moment.step,
                                                width: 96, height: 72, alpha: moment.blend)
                let wanted = image.dataProvider?.data.map { [UInt8]($0 as Data) } ?? []
                if wanted != pixels { differing.append(frame) }
                drawn.append(pixels)
            }
            check(same, differing.isEmpty && Set(drawn).count == 6 && VideoExport.moment(frame: 8898).blend == 0,
                  "differ from the snapshot: \(differing); \(Set(drawn).count) different pictures of 6")
            let alone = DemoSequencer(music: SilentMusic())
            for _ in 0..<run.steps { alone.tick() }
            let a = run.scene.musicState, b = alone.musicState
            check(place, run.steps == 10_386 && a.order == b.order && a.row == b.row && a.ticks == b.ticks && a.plus == b.plus
                    && run.scene.currentPart == alone.currentPart,
                  "\(run.steps) steps; drawn: \(a); bare: \(b)")
        } catch {
            check(same, false, "\(error)")
            check(place, false, "\(error)")
        }
    }
}
