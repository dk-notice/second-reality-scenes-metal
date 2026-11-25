import Foundation

/// The music for a run of the demo without sound: libopenmpt renders each song silently, 1/70 s
/// (630 samples at 44,100 Hz) per step, exactly as `tools/music_steps.c` does for the Python simulation.
final class SilentMusic: DemoMusicSource {
    private var song: TrackerSong?
    private var buffer = [Float]()
    private(set) var orderList: [Int] = []
    private(set) var problem: String?

    func play(_ which: Song, fromOrder order: Int) {
        do {
            let tracker = try TrackerSong.wholeSong(which, fromOrder: order)
            song = tracker
            orderList = tracker.orderList
        } catch {
            problem = "\(error)"
        }
    }

    var position: MusicPosition {
        guard let song else { return .silent }
        return MusicPosition(song: song.song, order: song.currentOrder, row: song.currentRow)
    }

    /// Lets 1/70 s of music pass.
    func stepPassed() {
        song?.render(into: &buffer, frames: 630, sampleRate: 44_100)
    }
}

/// `--demo-timeline`: runs the whole of Play Demo's script against the music, silently and much
/// faster than real time, and checks every part starts at the step `tools/demo_timeline.py` gives.
enum DemoTimelineCommand {
    /// Each part's start, in 1/70 s steps, from `tools/demo_timeline.py <folder> 0 frames`
    /// (2026-11-24). The last number is when the credits end and the end scroller starts: 10:52.4.
    static let expected: [(name: String, step: Int)] = [
        ("Opening credits", 0), ("Ships fly-by", 5105), ("Explosion", 7087), ("Title picture", 7463),
        ("Glenz vectors", 7624), ("Dot tunnel", 10681), ("Rings, interference, techno bars, troll", 11741),
        ("Screen switches off", 15727), ("Loader waits for the music", 15918), ("Mountain scroller", 16177),
        ("Lens, then rotozoomer", 18213), ("Plasma", 21393), ("Plasma cube", 23792), ("Bouncing dots", 26103),
        ("Water scroller", 28683), ("3D sine landscape", 30747), ("Jelly logo", 32782), ("3D city", 33571),
        ("End picture", 37469), ("Credits", 38068), ("End scroller", 45670)
    ]

    /// Play Demo as a scene with silent music, for `--snapshot play-demo`.
    static let silentEntry = SceneEntry(
        id: "play-demo", title: "Play Demo", credit: "Future Crew", canvasSize: SIMD2(320, 200),
        checkpoints: [], thumbnailStep: 0,
        make: { device, format in try DemoRunScene(device: device, pixelFormat: format, music: SilentMusic()) })

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
        let seconds = Double(step) / 70
        return String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
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
}
