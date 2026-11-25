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
    /// DIS's music frame counter (`dis_getmframe`): steps since the part last reset it.
    var frame: Int
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
    func play(_ song: Song, fromOrder order: Int)
    var position: MusicPosition { get }
    var orderList: [Int] { get }
    /// Called once at the end of every step (silent music renders 1/70 s here; real music plays on its own).
    func stepPassed()
}

extension DemoMusicSource {
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
        s += [.part("Opening credits"), .playSong(.first, order: 0), .show(.card("Opening credits")),
              until { $0.sync >= 9 }, .frames(60)]
        s += [.part("Ships fly-by"), .show(.picture("02-ships-horizon")),
              until { $0.order > 10 && $0.row > 46 }, .show(.scene("ships-flyby")),
              until(cap: 521) { $0.order > 11 && $0.row > 54 }]
        s += [.part("Explosion"), .show(.card("Explosion")), until { $0.sync >= 10 }, .frames(45 * 4)]
        s += [.part("Title picture"), .show(.picture("04-title")), .frames(161)]
        // ---- Song 2 (MUSIC1) from section 0 ----
        s += [.part("Glenz vectors"), .playSong(.second, order: 0), .show(.scene("glenz-vectors")),
              .frames(47), until { $0.plus >= -19 }, .resetFrameCounter, .frames(177),
              until { $0.frame >= 333 }, until(cap: 7000) { -16 < $0.plus && $0.plus < 0 }]
        s += [.part("Dot tunnel"), .show(.scene("dot-tunnel")), .frames(1060)]
        // TECHNO: rings, interference, the lead-in to the bars on four beats, the bars, the troll.
        s += [.part("Rings, interference, techno bars, troll"), .show(.black), until { $0.plus >= -4 },
              .show(.scene("rings")), .resetFrameCounter, .frames(256),
              .show(.scene("interference")), until { $0.frame >= 925 },
              .show(.black), .frames(5), until { $0.plus >= -3 }, until { $0.row & 7 == 7 }]
        for _ in 0..<4 { s += [.frames(21), until { $0.row & 7 == 7 }, .frames(4)] }
        s += [.show(.scene("techno-bars")), .frames(420), .frames(840), until(cap: 700) { $0.frame > 2520 },
              .show(.picture("07-troll")), until { $0.order > 35 || ($0.order == 35 && $0.row > 48) },
              .frames(53 + 50), until(cap: 420) { -6 < $0.plus && $0.plus < 16 }]
        s += [.part("Screen switches off"), .show(.card("Screen switches off")), .frames(121 + 70)]
        s += [.part("Loader waits for the music"), .show(.black), until { $0.plus < 0 }, until { $0.plus > 0 }]
        s += [.part("Mountain scroller"), .show(.picture("09-mountain-background")), .frames(64),
              until { $0.plus >= 0 }, .frames(127), until { $0.plus == -11 }, .frames(65)]
        s += [.part("Lens, then rotozoomer"), .show(.picture("10-lens-picture")), until { $0.plus >= -6 },
              .resetFrameCounter, .frames(300), until { $0.plus >= -20 }, .frames(720),
              .show(.card("Rotozoomer")), until(cap: 2000) { $0.plus > -4 }]
        s += [.part("Plasma"), .show(.scene("plasma")), until { $0.plus >= 0 }, .resetFrameCounter,
              until { $0.frame > 2259 }, .frames(65)]
        s += [.part("Plasma cube"), .show(.scene("plasma-cube")), until { $0.plus >= 13 },
              until { -4 <= $0.plus && $0.plus < 0 }]
        s += [.part("Bouncing dots"), .show(.scene("bouncing-dots")), .frames(130),
              until(cap: 2450) { -3 <= $0.plus && $0.plus <= -1 }]
        s += [.part("Water scroller"), .show(.picture("13-water-background")), until { $0.plus >= 0 },
              .noteSection, .frames(127), until { $0.order != $0.noted && $0.row >= 16 },
              until { $0.plus == -11 }, .frames(65)]
        s += [.part("3D sine landscape"), .show(.scene("sine-landscape")), until { $0.plus >= 0 },
              until(cap: 4444) { -7 <= $0.plus && $0.plus <= -1 }]
        s += [.part("Jelly logo"), .show(.picture("15-jelly-logo")), .frames(86), until { $0.plus >= 4 }, .frames(700)]
        // ---- Song 1 again, from section 18 ----
        s += [.part("3D city"), .playSong(.first, order: 18), .show(.scene("city-3d")), .frames(100),
              until { $0.order > 18 }, .frames(1801 * 2 + 16)]
        s += [.part("End picture"), .show(.picture("17-end-picture")), .frames(163),
              until(cap: 5000) { $0.plus > -16 }, .frames(64)]
        s += [.part("Credits")]
        for picture in creditsPictures { s += [.show(.picture(picture)), .frames(362)] }
        s += [.part("End scroller"), .show(.card("End scroller")), .hold]
        return s
    }()

    /// The pictures the script shows, in order.
    static let pictures: [String] = steps.compactMap { if case .show(.picture(let name)) = $0 { return name } else { return nil } }

    static var partCount: Int { steps.filter { if case .part = $0 { return true } else { return false } }.count }
}

/// Follows `DemoScript.steps`. Call `tick()` once per 1/70 s step.
final class DemoSequencer {
    let music: DemoMusicSource
    /// Called when the screen should change.
    var onShow: ((DemoVisual) -> Void)?

    /// Steps since the demo started.
    private(set) var time = 0
    /// Each part's name and the step it started at.
    private(set) var partStarts: [(name: String, step: Int)] = []
    private(set) var visual: DemoVisual = .black
    private(set) var finished = false

    private var index = 0
    /// Steps already spent on the current step (for `.frames` and an `.until`'s cap).
    private var spent = 0
    private var frameCounter = 0
    private var noted = 0

    init(music: DemoMusicSource) { self.music = music }

    var currentPart: String? { partStarts.last?.name }

    /// The music as the parts saw it right now.
    var musicState: DemoMusicState {
        let p = music.position
        return DemoMusicState(order: p.order, row: p.row,
                              plus: MusicPosition.plus(orderList: music.orderList, order: p.order, row: p.row),
                              sync: MusicPosition.sync(order: p.order, row: p.row),
                              frame: frameCounter, noted: noted)
    }

    /// One 1/70 s step: does every step of the script that takes no time, up to the first one that
    /// has to wait, then spends this step waiting on it. (As the Python simulation: conditions are
    /// read before the step's time passes.)
    func tick() {
        while index < DemoScript.steps.count {
            let step = DemoScript.steps[index]
            switch step {
            case .part(let name):
                partStarts.append((name, time))
            case .show(let what):
                visual = what
                onShow?(what)
            case .playSong(let song, let order):
                music.play(song, fromOrder: order)
                frameCounter = 0   // a new song: DIS's counter starts again
            case .resetFrameCounter:
                frameCounter = 0
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
        music.stepPassed()
    }
}
