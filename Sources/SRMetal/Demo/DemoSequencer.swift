/// The whole demo's running order, as a script of small steps, and the sequencer that follows it
/// one 1/70 s step at a time. No drawing here: `DemoRunScene` shows what the script asks for, and
/// the self-test runs the same script against the music without a window.
///
/// The script is `tools/demo_timeline.py` written again in Swift, step for step, so the app runs
/// exactly what the research simulated. Every condition comes from the original source; see
/// `docs/demo-timeline.md` ("Sources of each condition") for where.

/// What the screen shows. Everything is a stand-in for now, except the scenes this project has built.
enum DemoVisual: Equatable {
    /// One of the project's scenes (an id from `SceneCatalog.all`), started from its beginning.
    case scene(String)
    /// A picture from `artwork/` by its base name, e.g. "04-title".
    case picture(String)
    /// A title card naming a part that is not built yet.
    case card(String)
    case black
}

/// What the music is doing, as the parts saw it.
struct DemoMusicState {
    var order: Int
    var row: Int
    /// DIS's "music plus" (see `MusicPosition.plus`).
    var plus: Int
    /// DIS's sync value (see `MusicPosition.sync`).
    var sync: Int
    /// Screen refreshes since the part last reset DIS's music frame counter. Glenz and the plasma
    /// still read the counter this way (an open question: see `docs/demo-timeline.md`).
    var frame: Int
    /// DIS's music frame counter (`dis_getmframe`) as the player really kept it: MUSIC TICKS since the
    /// part last reset it (see `DemoSequencer.tickCounter`). The techno part reads this.
    var ticks: Int
    /// A section number a part noted down (the water scroller waits for the next section).
    var noted: Int
}

enum DemoStep {
    /// A new part starts here (the name is how the timeline and the window name it).
    case part(String)
    case show(DemoVisual)
    /// Starts a song from the beginning of a section.
    case playSong(Song, order: Int)
    /// Waits this many steps.
    case frames(Int)
    /// Waits until the condition holds, or (if given) at most `cap` steps.
    case until(cap: Int?, (DemoMusicState) -> Bool)
    case resetFrameCounter
    case noteSection
    /// The end: waits for ever (the end scroller ran until a key was pressed).
    case hold
}

/// Where the sequencer gets the music from: the real player, or (for checks) a song rendered silently.
protocol DemoMusicSource: AnyObject {
    /// Starts `song` from the beginning of section `order`, `skipping` that many seconds of it (to the
    /// sample): Play Demo started part-way through.
    func play(_ song: Song, fromOrder order: Int, skipping seconds: Double)
    var position: MusicPosition { get }
    var orderList: [Int] { get }
    /// Called once at the end of every step (silent music renders 1/70 s here; real music plays on its own).
    func stepPassed()
}

extension DemoMusicSource {
    func play(_ song: Song, fromOrder order: Int) { play(song, fromOrder: order, skipping: 0) }
    func stepPassed() {}
}

enum DemoScript {
    static func until(_ condition: @escaping (DemoMusicState) -> Bool) -> DemoStep { .until(cap: nil, condition) }
    static func until(cap: Int, _ condition: @escaping (DemoMusicState) -> Bool) -> DemoStep { .until(cap: cap, condition) }

    /// The 21 credits pictures, in the order `CREDITS/MAIN.C` shows them.
    static let creditsPictures = ["01", "02", "03", "04", "05", "05b", "06", "07", "08", "09", "10", "10b",
                                  "11", "12", "13", "14", "14b", "15", "16", "17", "18"].map { "18-credits-pic\($0)" }

    static let steps: [DemoStep] = {
        var s: [DemoStep] = []
        // ---- Song 1 (MUSIC0, tempo 120) from section 0 ----
        // ALKU (as released): three titles, each on its sync (1-3) or when the one before has faded out;
        // the scroll from sync 4 to its end and the hand-over to the ships (see OpeningCreditsModel).
        s += [.part("Opening credits"), .playSong(.first, order: 0), .show(.card("Opening credits"))]
        for cue in 1...3 { s += [until { $0.sync >= cue }, .frames(427)] }
        s += [until { $0.sync >= 4 }, .frames(2947)]
        s += [.part("Ships fly-by"), .show(.picture("02-ships-horizon")),
              until { $0.order > 10 && $0.row > 46 }, .show(.scene("ships-flyby")),
              until(cap: 521) { $0.order > 11 && $0.row > 54 }]
        // While the original waited for its cue, the screen still showed the ships' horizon.
        s += [.part("Explosion"), .show(.picture("02-ships-horizon")), until { $0.sync >= 10 },
              .show(.scene("explosion")), .frames(ExplosionModel.length)]
        s += [.part("Title picture"), .show(.scene("title-picture")), .frames(161)]
        // ---- Song 2 (MUSIC1) from section 0 ----
        s += [.part("Glenz vectors"), .playSong(.second, order: 0), .show(.scene("glenz-vectors")),
              .frames(47), until { $0.plus >= -19 }, .resetFrameCounter, .frames(177),
              until { $0.frame >= 333 }, until(cap: 7000) { -16 < $0.plus && $0.plus < 0 }]
        s += [.part("Dot tunnel"), .show(.scene("dot-tunnel")), .frames(1060)]
        // TECHNO: rings, interference, the lead-in to the bars on four beats, the bars, the troll. The
        // interference scene shows the lead-in itself (`TechnoLeadIn`, which follows these same waits).
        s += [.part("Rings, interference, techno bars, troll"), .show(.black), until { $0.plus >= -4 },
              .show(.scene("rings")), .resetFrameCounter, .frames(256),
              .show(.scene("interference")), until { $0.ticks >= InterferenceModel.demoEndTicks },
              .frames(5), until { $0.plus >= -3 }, until { $0.row & 7 == 7 }]
        for _ in 0..<4 { s += [.frames(21), until { $0.row & 7 == 7 }, .frames(4)] }
        s += [.show(.scene("techno-bars")), .frames(420), .frames(840), until(cap: 700) { $0.ticks > 2520 },
              .show(.scene("troll")), until { $0.order > 35 || ($0.order == 35 && $0.row > 48) },
              .frames(53 + 50), until(cap: 420) { -6 < $0.plus && $0.plus < 16 }]
        s += [.part("Screen switches off"), .show(.scene("switch-off")), .frames(SwitchOffModel.length)]
        s += [.part("Loader waits for the music"), .show(.black), until { $0.plus < 0 }, until { $0.plus > 0 }]
        s += [.part("Mountain scroller"), .show(.scene("mountain-scroller")), .frames(64),
              until { $0.plus >= 0 }, .frames(127), until { $0.plus == -11 }, .frames(65)]
        s += [.part("Lens, then rotozoomer"), .show(.scene("lens")), until { $0.plus >= -6 },
              .resetFrameCounter, .frames(300), until { $0.plus >= -20 }, .frames(720),
              .show(.scene("rotozoomer")), until(cap: 2000) { $0.plus > -4 }]
        s += [.part("Plasma"), .show(.scene("plasma")), until { $0.plus >= 0 }, .resetFrameCounter,
              until { $0.frame > 2259 }, .frames(65)]
        s += [.part("Plasma cube"), .show(.scene("plasma-cube")), until { $0.plus >= 13 },
              until { -4 <= $0.plus && $0.plus < 0 }]
        s += [.part("Bouncing dots"), .show(.scene("bouncing-dots")), .frames(130),
              until(cap: 2450) { -3 <= $0.plus && $0.plus <= -1 }]
        s += [.part("Water scroller"), .show(.scene("water-scroller")), until { $0.plus >= 0 },
              .noteSection, .frames(127), until { $0.order != $0.noted && $0.row >= 16 },
              until { $0.plus == -11 }, .frames(65)]
        s += [.part("3D sine landscape"), .show(.scene("sine-landscape")), until { $0.plus >= 0 },
              until(cap: 4444) { -7 <= $0.plus && $0.plus <= -1 }]
        s += [.part("Jelly logo"), .show(.scene("jelly-logo")), .frames(86), until { $0.plus >= 4 }, .frames(700)]
        // ---- Song 1 again, from section 18 ----
        s += [.part("3D city"), .playSong(.first, order: 18), .show(.scene("city-3d")), .frames(100),
              until { $0.order > 18 }, .frames(1801 * 2 + 16)]
        s += [.part("End picture"), .show(.scene("end-picture")), .frames(163),
              until(cap: 5000) { $0.plus > -16 }, .frames(64)]
        // CREDITS/MAIN.C: 21 screens of 362 refreshes (see CreditsModel), shown by the Credits scene.
        s += [.part("Credits"), .show(.scene("credits")), .frames(creditsPictures.count * 362)]
        s += [.part("End scroller"), .show(.scene("end-scroller")), .hold]   // until the demo is stopped (a key, in 1993)
        return s
    }()

    /// The parts' names, in order.
    static let partNames: [String] = steps.compactMap { if case .part(let name) = $0 { return name } else { return nil } }

    /// The scenes the script shows, in order (each shows once).
    static let sceneIDs: [String] = steps.compactMap { if case .show(.scene(let id)) = $0 { return id } else { return nil } }

    /// The pictures the script shows, in order.
    static let pictures: [String] = steps.compactMap { if case .show(.picture(let name)) = $0 { return name } else { return nil } }
}

/// Where Play Demo starts, when not from the beginning: where a scene first shows, or a part begins.
enum DemoStart: Equatable {
    case scene(String)
    /// A part by its number in `DemoScript.partNames`, from 0.
    case part(Int)

    /// From the command line: a scene id, or a part number from 1 (as `--demo-timeline` lists them).
    init?(argument: String) {
        if let number = Int(argument), (1...DemoScript.partNames.count).contains(number) { self = .part(number - 1) }
        else if DemoScript.sceneIDs.contains(argument) { self = .scene(argument) }
        else { return nil }
    }
}

/// The demo run silently up to a starting point, ready to be continued with the real music.
struct DemoFastForward {
    /// The sequencer just after the step on which the start was shown (its music is silent).
    let sequencer: DemoSequencer
    /// What that step showed, and the music as the script saw it then (for the scene's `justShown`).
    let visual: DemoVisual
    let musicAtShow: DemoMusicState
    /// The song playing, the section the script started it from, and how long it has played, to the
    /// sample, when the next step begins.
    let song: Song?
    let order: Int
    let seconds: Double
}

/// Follows `DemoScript.steps`. Call `tick()` once per 1/70 s step.
final class DemoSequencer {
    let music: DemoMusicSource
    /// The script followed: the demo's (checks may give a small one of their own).
    let steps: [DemoStep]
    /// Called when the screen should change.
    var onShow: ((DemoVisual) -> Void)?

    /// Steps since the demo started.
    private(set) var time = 0
    /// Each part's name and the step it started at.
    private(set) var partStarts: [(name: String, step: Int)] = []
    private(set) var finished = false

    private var index = 0
    /// Steps already spent on the current step (for `.frames` and an `.until`'s cap).
    private var spent = 0
    private var frameCounter = 0
    /// The player's music frame counter (`np_zframe`), which counts music ticks: found in the player's
    /// library (`MAIN/STMIK.300`, the routine at 4353h that also moves the song on a row). With a
    /// Gravis Ultrasound or no sound card the player was polled once a screen refresh and ran a tick
    /// only when a 16-bit sum of its "speed adjust" overflowed (5165h); `MAIN/U2.ASM` 769-774 sets that
    /// to 45000 for song 1 and 48700 for song 2: 48.07 and 52.02 ticks a second (tempo 120 and 130).
    private(set) var tickCounter = 0
    private var tickSum = 0
    private var tickAdjust = 0
    private var noted = 0

    /// The player's "speed adjust" for each song (`MAIN/U2.ASM` 769-774).
    static func speedAdjust(_ song: Song) -> Int { song == .first ? 45_000 : 48_700 }

    init(music: DemoMusicSource, steps: [DemoStep] = DemoScript.steps) {
        self.music = music
        self.steps = steps
    }

    /// Carries on where `other` is, with `music` instead of its music (which the caller starts at the
    /// same place).
    init(continuing other: DemoSequencer, music: DemoMusicSource) {
        self.music = music
        steps = other.steps
        time = other.time
        partStarts = other.partStarts
        finished = other.finished
        index = other.index
        spent = other.spent
        frameCounter = other.frameCounter
        tickCounter = other.tickCounter
        tickSum = other.tickSum
        tickAdjust = other.tickAdjust
        noted = other.noted
    }

    /// Runs the script silently (without drawing anything, so quickly: the whole demo takes about
    /// 0.2 s) up to the step on which `start` shows. nil if the script never gets there.
    static func fastForward(to start: DemoStart, steps: [DemoStep] = DemoScript.steps) -> DemoFastForward? {
        let music = SilentMusic()
        let sequencer = DemoSequencer(music: music, steps: steps)
        var found: (DemoVisual, DemoMusicState)?
        var last: (DemoVisual, DemoMusicState)?
        sequencer.onShow = { [unowned sequencer] visual in
            last = (visual, sequencer.musicState)
            if case .scene(let wanted) = start, case .scene(let id) = visual, id == wanted { found = last }
        }
        while found == nil && !sequencer.finished && sequencer.time < 70 * 60 * 15 {
            sequencer.tick()
            if case .part(let number) = start, sequencer.partStarts.count >= number + 1 { found = last }
        }
        sequencer.onShow = nil
        guard let (visual, state) = found else { return nil }
        let playing = music.playing
        return DemoFastForward(sequencer: sequencer, visual: visual, musicAtShow: state,
                               song: playing?.song, order: playing?.order ?? 0, seconds: playing?.seconds ?? 0)
    }

    var currentPart: String? { partStarts.last?.name }

    /// The music as the parts saw it right now.
    var musicState: DemoMusicState {
        let p = music.position
        return DemoMusicState(order: p.order, row: p.row,
                              plus: MusicPosition.plus(orderList: music.orderList, order: p.order, row: p.row),
                              sync: MusicPosition.sync(order: p.order, row: p.row),
                              frame: frameCounter, ticks: tickCounter, noted: noted)
    }

    /// One 1/70 s step: does every step of the script that takes no time, up to the first one that
    /// has to wait, then spends this step waiting on it. (As the Python simulation: conditions are
    /// read before the step's time passes.)
    func tick() {
        while index < steps.count {
            let step = steps[index]
            switch step {
            case .part(let name):
                partStarts.append((name, time))
            case .show(let what):
                onShow?(what)
            case .playSong(let song, let order):
                music.play(song, fromOrder: order)
                frameCounter = 0   // a new song: DIS's counter starts again
                tickCounter = 0
                tickSum = 0
                tickAdjust = Self.speedAdjust(song)
            case .resetFrameCounter:
                frameCounter = 0
                tickCounter = 0   // the sum runs on: the part sets only the counter
            case .noteSection:
                noted = music.position.order
            case .frames(let count):
                if spent < count { spent += 1; passTime(); return }
            case .until(let cap, let condition):
                if !condition(musicState) && spent < (cap ?? Int.max) { spent += 1; passTime(); return }
            case .hold:
                finished = true
                passTime()
                return
            }
            index += 1
            spent = 0
        }
    }

    private func passTime() {
        time += 1
        frameCounter += 1
        tickSum += tickAdjust
        if tickSum >= 65_536 { tickSum -= 65_536; tickCounter += 1 }
        music.stepPassed()
    }
}
