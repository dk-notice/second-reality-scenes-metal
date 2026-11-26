import Foundation

/// The music for a run of the demo without sound: libopenmpt renders each song silently, 1/70 s
/// (630 samples at 44,100 Hz) per step, exactly as `tools/music_steps.c` does for the Python simulation.
final class SilentMusic: DemoMusicSource {
    static let sampleRate = 44_100
    static let framesPerStep = 630
    private var song: TrackerSong?
    private var buffer = [Float]()
    private(set) var orderList: [Int] = []
    private(set) var problem: String?
    /// The section the song was started from, and how many sample pairs have passed since.
    private var startOrder = 0
    private var framesSinceStart = 0

    func play(_ which: Song, fromOrder order: Int, skipping seconds: Double) {
        do {
            let tracker = try TrackerSong.wholeSong(which, fromOrder: order)
            let frames = Int((seconds * Double(Self.sampleRate)).rounded())
            tracker.skip(seconds: seconds, sampleRate: Self.sampleRate)
            song = tracker
            orderList = tracker.orderList
            startOrder = order
            framesSinceStart = frames
        } catch {
            problem = "\(error)"
        }
    }

    var position: MusicPosition {
        guard let song else { return .silent }
        return MusicPosition(song: song.song, order: song.currentOrder, row: song.currentRow)
    }

    /// The song playing, the section it was started from and exactly how long it has played since
    /// (to the sample), or nil.
    var playing: (song: Song, order: Int, seconds: Double)? {
        song.map { ($0.song, startOrder, Double(framesSinceStart) / Double(Self.sampleRate)) }
    }

    /// Lets 1/70 s of music pass.
    func stepPassed() {
        guard let song else { return }
        song.render(into: &buffer, frames: Self.framesPerStep, sampleRate: Self.sampleRate)
        framesSinceStart += Self.framesPerStep
    }
}

/// `--demo-timeline`: runs the whole of Play Demo's script against the music, silently and much
/// faster than real time, and checks every part starts at the step `tools/demo_timeline.py` gives.
enum DemoTimelineCommand {
    /// Each part's start, in 1/70 s steps: the "Part starts (steps)" line of
    /// `tools/demo_timeline.py <folder> 0 frames`. The last number is when the credits end and the end
    /// scroller starts: 10:52.4.
    static let expected: [(name: String, step: Int)] = [
        ("Opening credits", 0), ("Ships fly-by", 5605), ("Explosion", 7087), ("Title picture", 7463),
        ("Glenz vectors", 7624), ("Dot tunnel", 10681), ("Rings, interference, techno bars, troll", 11741),
        ("Screen switches off", 15727), ("Loader waits for the music", 15918), ("Mountain scroller", 16177),
        ("Lens, then rotozoomer", 18213), ("Plasma", 21393), ("Plasma cube", 24056), ("Bouncing dots", 26103),
        ("Water scroller", 28683), ("3D sine landscape", 30747), ("Jelly logo", 32782), ("3D city", 33571),
        ("End picture", 37469), ("Credits", 38068), ("End scroller", 45670)
    ]

    /// Play Demo as a scene with silent music, for `--snapshot play-demo`.
    static let silentEntry = DemoRunScene.entry(music: { SilentMusic() })

    /// Runs the script until it reaches its end (or gives up after 15 minutes of demo time).
    static func simulate() -> (sequencer: DemoSequencer, problem: String?) {
        let music = SilentMusic()
        let sequencer = DemoSequencer(music: music)
        while !sequencer.finished && sequencer.time < 70 * 60 * 15 {
            sequencer.tick()
        }
        return (sequencer, music.problem)
    }

    /// The differences from `expected`, in words (empty when every part is on time).
    static func differences(_ starts: [(name: String, step: Int)]) -> [String] {
        var out: [String] = []
        if starts.count != expected.count { out.append("\(starts.count) parts, expected \(expected.count)") }
        for (got, want) in zip(starts, expected) where got.name != want.name || got.step != want.step {
            out.append("\(got.name) at \(got.step), expected \(want.name) at \(want.step)")
        }
        return out
    }

    static func time(_ step: Int) -> String {
        // Rounded to tenths first, so 59.96 s shows as 1:00.0, not 0:60.0.
        let tenths = Int((Double(step) / 7).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths % 600 / 10, tenths % 10)
    }

    static func run(arguments: [String]) -> Bool {
        let started = Date()
        let (sequencer, problem) = simulate()
        if let problem { print("Music problem: \(problem)") }
        let starts = sequencer.partStarts
        for (number, part) in starts.enumerated() {
            let end = number + 1 < starts.count ? time(starts[number + 1].step) : "until a key"
            print(String(format: "%2d  %@  %@ -> %@", number + 1, part.name.padding(toLength: 40, withPad: " ", startingAt: 0),
                         time(part.step), end))
        }
        let wrong = differences(starts)
        for line in wrong { print("DIFFERENT: \(line)") }
        print(String(format: "Simulated %@ of demo in %.1f s. ", time(sequencer.time), Date().timeIntervalSince(started))
              + (wrong.isEmpty ? "Every part starts at the step tools/demo_timeline.py gives." : "\(wrong.count) differences."))
        return wrong.isEmpty && problem == nil
    }

    /// `--demo-live <scene id | part number> <seconds> [sound] [pause <at> <for>]`: Play Demo's script from
    /// that point with the REAL music player (muted unless `sound` is given), stepped by the clock, nothing
    /// drawn. Prints when each part starts against the full run's step: proof the live music, started
    /// part-way, keeps the demo on time (the app's own window only steps while it is on screen).
    /// `pause <at> <for>`: after `at` seconds the music and the steps are paused together for `for` seconds,
    /// as the app does while its window cannot be seen; the parts after it must still be on time, and the
    /// music must not have moved meanwhile.
    /// `rebuild <at>`: after `at` seconds the sound output is made again, as when macOS reports that the
    /// output device changed; the music must carry on from its place and the parts after it be on time.
    static func live(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: "--demo-live"), flag + 2 < arguments.count,
              let start = DemoStart(argument: arguments[flag + 1]), let seconds = Double(arguments[flag + 2]) else {
            print("Usage: SRMetal --demo-live <scene id | part number 1-\(DemoScript.partNames.count)> <seconds> [sound] [delay] [pause <at seconds> <for seconds>] [rebuild <at seconds>]")
            return false
        }
        var rebuildAt: Double?
        if let word = arguments.firstIndex(of: "rebuild") {
            guard word + 1 < arguments.count, let at = Double(arguments[word + 1]), at >= 0 else {
                print("rebuild needs a number: after how many seconds")
                return false
            }
            rebuildAt = at
        }
        var pause: (at: Double, length: Double)?
        if let word = arguments.firstIndex(of: "pause") {
            guard word + 2 < arguments.count, let at = Double(arguments[word + 1]), let length = Double(arguments[word + 2]),
                  at >= 0, length > 0 else {
                print("pause needs two numbers: after how many seconds, and for how long")
                return false
            }
            pause = (at, length)
        }
        guard let ahead = DemoSequencer.fastForward(to: start) else { print("The demo never reaches \(start)"); return false }
        let player = MusicPlayer()
        player.muted = !arguments.contains("sound")
        // `delay`: follow the music as heard (the output device's delay allowed for, as the app does by
        // default); every music cue then comes that much later than in the silent full run.
        player.allowsForOutputDelay = arguments.contains("delay")
        let music = LiveDemoMusic(player: player, look: { .modern })
        let sequencer = DemoSequencer(continuing: ahead.sequencer, music: music)
        let began = Date()
        if let song = ahead.song { music.play(song, fromOrder: ahead.order, skipping: ahead.seconds) }
        print(String(format: "Started at %@ (step %d, %@), %@ from section %d + %.3f s (music ready in %.0f ms)",
                     "\(start)", sequencer.time, time(sequencer.time), ahead.song?.rawValue ?? "no song", ahead.order,
                     ahead.seconds, Date().timeIntervalSince(began) * 1000))
        let firstStep = sequencer.time
        var parts = sequencer.partStarts.count
        var worst = 0
        var clock = Date()
        var movedWhilePaused: Double?
        var carriedOn = true
        while Date().timeIntervalSince(clock) < seconds {
            if let at = rebuildAt, Date().timeIntervalSince(clock) >= at {
                rebuildAt = nil
                let before = player.positionSeconds
                let began = Date()
                player.rebuildOutput()
                let took = Date().timeIntervalSince(began)
                usleep(500_000)
                let moved = player.positionSeconds - before
                // Half a second later the song is about half a second on: it neither stopped nor jumped.
                carriedOn = moved > 0.3 && moved < 0.8 && player.problem == nil
                print(String(format: "  sound output made again at %.1f s (%.0f ms): 0.5 s later the music is %.3f s on%@",
                             at, took * 1000, moved, player.problem.map { ", problem: \($0)" } ?? ""))
            }
            if let now = pause, Date().timeIntervalSince(clock) >= now.at {
                // Music and steps stop together; afterwards the step clock carries on from where it stopped.
                pause = nil
                player.paused = true
                usleep(200_000)                       // (sound already handed to the output plays out)
                let before = player.positionSeconds
                usleep(UInt32(now.length * 1_000_000))
                movedWhilePaused = player.positionSeconds - before
                player.paused = false
                clock = clock.addingTimeInterval(now.length + 0.2)
                print(String(format: "  paused %.1f s at %.1f s: the music moved %.3f s meanwhile", now.length, now.at, movedWhilePaused ?? -1))
            }
            let due = firstStep + Int(Date().timeIntervalSince(clock) * 70)
            while sequencer.time < due {
                sequencer.tick()
                if sequencer.partStarts.count != parts, let part = sequencer.partStarts.last {
                    parts = sequencer.partStarts.count
                    let want = expected.first { $0.name == part.name }?.step ?? -1
                    worst = max(worst, abs(part.step - want))
                    let p = player.position
                    print(String(format: "  %-40@ step %d, full run %d (%+d steps = %+.2f s); music section %d row %d",
                                 part.name, part.step, want, part.step - want, Double(part.step - want) / 70, p.order, p.row))
                }
            }
            usleep(2_000)
        }
        player.stop()
        print("Worst difference: \(worst) steps (\(String(format: "%.2f", Double(worst) / 70)) s)")
        print(String(format: "Output delay reported by macOS: %.1f ms (%@)", player.outputDelay * 1000,
                     player.allowsForOutputDelay ? "allowed for: cues come that much later" : "not allowed for; add `delay` to follow the music as heard"))
        return worst <= 35 && (movedWhilePaused ?? 0) == 0 && carriedOn
    }
}
