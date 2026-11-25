import Foundation

/// Finds the opening credits' data (`Data/OpeningCredits`, copied into the app as `Resources/OpeningCredits`).
enum OpeningCreditsData {
    static let folder = DataFolder.find(resource: "OpeningCredits", devPath: "Data/OpeningCredits", marker: "HORIZON.BIN")

    static func load(_ name: String) throws -> [UInt8] {
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else {
            throw CreditsError.missing("OpeningCredits/" + name)
        }
        return [UInt8](data)
    }
}

/// The opening credits (part 1, `ALKU/MAIN.C` with `TWEAK.ASM`, `ASMYT.ASM`, `COPPER.ASM`), as RELEASED.
/// No drawing here.
///
/// Three titles on black, each fading in on a music cue (DIS's sync value 1, 2, 3; or as soon as the one
/// before has faded out): "A Future Crew Production", "First Presented at Assembly 93", "in" and a Dolby
/// Surround logo. On sync 4 a night horizon fades in and starts scrolling, 1 pixel every 9 steps for 320
/// pixels; four pages of credits fade in over it, each on its cue (sync 5...8), the text still while the
/// landscape slides under it. The part ends 2,947 steps after sync 4, on the horizon's right half: the
/// very picture the ships part starts on.
///
/// Steps are counted from the part's start (song 1 from section 0). Inside Play Demo the music's sync
/// value comes from the script each step; on its own the scene uses the steps the script's silent run
/// gives (`cues`) and starts 70 steps before the first title. How the 1993 screen was made is in
/// `tools/alku_reference.py`, which this follows, and `docs/scenes/opening-credits.md`.
struct OpeningCreditsModel {
    /// The steps on which the music's sync value reaches 1...9 (song 1 from section 0, rendered silently
    /// 1/70 s a step; the self-test checks the script sees the same).
    static let cues = [1128, 1688, 2099, 2658, 3218, 3777, 4337, 4897, 5045]
    /// A title from its cue: fading in 63 steps, held to 363, fading out to 427.
    static let titleSteps = 427
    /// Refreshes per pixel of scroll (`SCRLF`).
    static let scrollStep = 9
    /// From sync 4: 320 scroll steps (2,881), the last fade (64) and the hand-over to the ships (2).
    static let endAfterSync4 = 2947
    /// On its own the scene starts here (the 16 s of music before the first title are left out).
    static let standaloneStart = cues[0] - 70
    /// The part's length in Play Demo with the measured cues; on its own the scene runs from
    /// `standaloneStart` to here, then starts again.
    static let demoLength = 5605
    static var standaloneLength: Int { demoLength - standaloneStart }

    /// The canvas: 320 pixels across, the card's 400 lines down (each a memory row of its own).
    static let width = 320
    static let height = 400

    /// Each line: the line its glyphs' top row is on (in 400), and the text. "[" and "]" are the two halves
    /// of the Dolby Surround logo; they overlap.
    static let titles: [[(top: Int, text: String)]] = [
        [(120, "A"), (160, "Future Crew"), (200, "Production")],
        [(160, "First Presented"), (200, "at Assembly 93")],
        [(120, "in"), (160, "["), (179, "]")],
    ]
    /// The pages over the horizon (a fifth, empty one waits for sync 9 and shows nothing). The line is
    /// the top of the glyphs in the text buffer, which shows from line 100.
    static let pages: [[(top: Int, text: String)]] = [
        [(50, "Graphics"), (90, "Marvel"), (130, "Pixel")],
        [(50, "Music"), (90, "Purple Motion"), (130, "Skaven")],
        [(30, "Code"), (70, "Psi"), (110, "Trug"), (148, "Wildfire")],
        [(50, "Additional Design"), (90, "Abyss"), (130, "Gore")],
    ]

    // MARK: - The data

    /// The horizon: 768 palette levels and 640 x 200 colour numbers (0...63); rows 0...149 are shown.
    let palette: [UInt8]
    let pixels: [UInt8]

    /// The font: 30 rows of 1,500 shades (0...3) as the program reads it; rows 30 and 31 are zeros.
    struct Font {
        static let stride = 1500
        static let order = "ABCDEFGHIJKLMNOPQRSTUVWXabcdefghijklmnopqrstuvwxyz0123456789!?,.:&()+-*=/[]"
        let shades: [UInt8]
        let glyphs: [Character: (start: Int, width: Int)]

        init(shades: [UInt8]) throws {
            guard shades.count == 30 * Self.stride else { throw CreditsError.badData("OpeningCredits FONT.BIN size \(shades.count)") }
            self.shades = shades + [UInt8](repeating: 0, count: 2 * Self.stride)
            // init(): the release scans the top 29 rows for empty columns (the source 32).
            func inked(_ x: Int) -> Bool { (0..<29).contains { shades[$0 * Self.stride + x] & 3 != 0 } }
            var glyphs: [Character: (Int, Int)] = [:]
            var x = 0
            for ch in Self.order {
                while x < Self.stride && !inked(x) { x += 1 }
                let start = x
                while x < Self.stride && inked(x) { x += 1 }
                glyphs[ch] = (start, x - start)
            }
            glyphs[" "] = (1480, 16)
            self.glyphs = glyphs
        }

        /// As the program holds it after init(): rows 0...28 turned into 64 x shade; the rows below left as
        /// they are (only the logo has ink in row 29, and only the titles draw it, with 29 rows).
        func bits(_ ch: Character, column: Int, row: Int) -> UInt8 {
            guard let glyph = glyphs[ch] else { return 0 }
            let v = shades[row * Self.stride + glyph.start + column]
            return row < 29 ? (v & 3) << 6 : v
        }

        /// A line's width as `prtc` and `addtext` count it (each character and 2 pixels after it).
        func width(_ line: String) -> Int { line.reduce(0) { $0 + (glyphs[$1]?.width ?? 0) + 2 } }
    }

    let font: Font
    /// The text as ORed into video memory, 320 x 400 (64 x shade): the titles (29 font rows, at their
    /// place) and the pages (32 rows, from line 100, shown 2 pixels right: see `tools/alku_reference.py`).
    let titleBits: [[UInt8]]
    let pageBits: [[UInt8]]

    static func load() throws -> OpeningCreditsModel {
        let horizon = try OpeningCreditsData.load("HORIZON.BIN")
        guard horizon.count == 784 + 640 * 200, horizon[0] == 252, horizon[1] == 252 else {
            throw CreditsError.badData("OpeningCredits HORIZON.BIN")
        }
        let font = try Font(shades: OpeningCreditsData.load("FONT.BIN"))
        return OpeningCreditsModel(palette: vgaLevels(horizon[16..<784]), pixels: Array(horizon[784...]), font: font)
    }

    init(palette: [UInt8], pixels: [UInt8], font: Font) {
        self.palette = palette
        self.pixels = pixels
        self.font = font
        titleBits = Self.titles.map { Self.textBits($0, font: font, rows: 29, down: 0, right: 0) }
        pageBits = Self.pages.map { Self.textBits($0, font: font, rows: 32, down: 100, right: 2) }
        (normal, withText, titleColours) = Self.palettes(palette)
        step = Self.standaloneStart
        reset()
    }

    /// Centred lines (both `prtc` and `addtext` start at 160 - sum(width + 2) / 2), ORed together.
    static func textBits(_ lines: [(top: Int, text: String)], font: Font, rows: Int, down: Int, right: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height)
        for (top, text) in lines {
            var x = 160 - font.width(text) / 2 + right
            for ch in text {
                let w = font.glyphs[ch]?.width ?? 0
                for column in 0..<w {
                    for row in 0..<rows {
                        let v = font.bits(ch, column: column, row: row)
                        if v != 0 { out[(down + top + row) * width + x + column] |= v }
                    }
                }
                x += w + 2
            }
        }
        return out
    }

    // MARK: - The palettes

    /// `palette` (64...255 repeat 0...63: text invisible), `palette2` (text shade s over colour c), `fade2`
    /// (text shades plain, everything else black: the titles). VGA levels, 768 each.
    let normal: [Int]
    let withText: [Int]
    let titleColours: [Int]

    static func palettes(_ p: [UInt8]) -> ([Int], [Int], [Int]) {
        let P = p.map(Int.init)
        var pal2 = [Int](repeating: 0, count: 768), fade2 = [Int](repeating: 0, count: 768)
        for i in stride(from: 0, to: 768, by: 3) {
            let s = i / 192
            for c in 0..<3 {
                if s == 0 { pal2[i + c] = P[i + c]; continue }
                let text = P[s * 3 + c]
                fade2[i + c] = text
                pal2[i + c] = (text * 63 + P[i % 192 + c] * (63 - text)) >> 6
            }
        }
        let normal = (0..<4).flatMap { _ in P[0..<192] }
        return (normal, pal2, fade2)
    }

    /// The copper's fade (ALKU/COPPER.ASM `copper3`): 8.8 fixed point, (target - start) x 256 / frames added
    /// `k` times (the C division rounds towards zero).
    static func copperFade(_ start: [Int], _ target: [Int], _ k: Int, _ frames: Int) -> [Int] {
        zip(start, target).map { s, t in
            let delta = (t - s) * 256 / frames
            return (s * 256 + k * delta) >> 8
        }
    }

    // MARK: - Where things are

    /// The step, counted from the part's start (Play Demo's step 0).
    private(set) var step: Int
    /// Inside Play Demo: the sync value the script gives for the coming step. nil: on its own (the cues).
    private var liveSync: Int?

    /// The schedule worked out so far: when each title started, sync 4, each page's R (the step whose scroll
    /// step its fade-in starts on; it shows from R + 1).
    private(set) var titleStarts: [Int] = []
    private(set) var sync4: Int?
    private(set) var pageR: [Int] = []

    /// On its own: back to `standaloneStart` (or step 0, for checks), following the cues. The schedule is
    /// built from `first` on, so `first` must not be later than the first cue.
    mutating func reset(from first: Int = standaloneStart) {
        step = first
        liveSync = nil
        titleStarts = []; sync4 = nil; pageR = []
        notice(sync: Self.sync(at: step))
    }

    /// Play Demo: the scene is shown on the part's first step, with the music's sync value then.
    mutating func startInDemo(sync: Int) {
        step = 0
        liveSync = sync
        titleStarts = []; sync4 = nil; pageR = []
        notice(sync: sync)
    }

    /// Play Demo: the sync value for the coming step.
    mutating func demoSync(_ sync: Int) { liveSync = sync }

    mutating func tick() {
        step += 1
        if liveSync == nil && step >= Self.demoLength { reset(); return }   // on its own: again
        notice(sync: liveSync ?? Self.sync(at: step))
    }

    /// The sync value on a step, from the measured cues.
    static func sync(at step: Int) -> Int { cues.filter { $0 <= step }.count }

    /// What the program does on this step, given the music's sync value now: it waits for the next title's
    /// cue (once the one before has faded out), for sync 4, or with the scroll running for the next page's cue.
    private mutating func notice(sync: Int) {
        if titleStarts.count < 3 {
            let ready = titleStarts.last.map { step >= $0 + Self.titleSteps } ?? true
            if ready && sync >= titleStarts.count + 1 { titleStarts.append(step) }
            return
        }
        guard let start4 = sync4 else {
            if step >= titleStarts[2] + Self.titleSteps && sync >= 4 { sync4 = step }
            return
        }
        guard pageR.count < Self.pages.count else { return }
        // A page is set up once the last one's fade-out has ended (the first: after the picture's fade-in,
        // which ends with scroll step 15); then the program waits for its cue and for an even position.
        let setup = pageR.last.map { $0 + 351 } ?? start4 + 15 * Self.scrollStep
        guard step >= setup, sync >= 5 + pageR.count else { return }
        var a = (step - start4) / Self.scrollStep + 1
        if a & 1 != 0 { a += 1 }
        pageR.append(start4 + Self.scrollStep * (a + 17))   // fmaketext(a + 16), then one more step
    }

    // MARK: - The 1993 screen

    enum Text: Hashable { case none, title(Int), page(Int) }

    /// What shows on a step: the palette (VGA levels), the scroll position (0...320), the text, and how far
    /// the text has faded in (0...1, for the Modern look).
    struct Shown {
        var levels: [Int]
        var position: Int
        var text: Text
        var textAmount: Float
    }

    /// Everything the screen shows on `step` (`step` itself by default), from the schedule so far.
    func shown(at: Int? = nil) -> Shown {
        let t = at ?? step
        var out = Shown(levels: [Int](repeating: 0, count: 768), position: 0, text: .none, textAmount: 0)
        for (k, start) in titleStarts.enumerated() {
            let j = t - start
            guard 1 <= j && j <= 427 else { continue }
            let a = j <= 63 ? j : j <= 363 ? 63 : 64 - (j - 364)
            out.levels = titleColours.map { ($0 * a) >> 6 }
            out.text = .title(k)
            out.textAmount = Float(a) / 64
        }
        if let start4 = sync4, t >= start4 + 2 {
            let k = min(t - start4 - 1, 128)
            out.levels = Self.copperFade([Int](repeating: 0, count: 768), normal, k, 128)
            out.position = max(0, min(320, (t - start4 - 1) / Self.scrollStep))
        }
        for (k, r) in pageR.enumerated() {
            let j = t - r
            guard 1 <= j && j <= 343 else { continue }
            out.text = .page(k)
            if j <= 64 {
                out.levels = Self.copperFade(normal, withText, j, 64); out.textAmount = Float(j) / 64
            } else if j <= 279 {
                out.levels = withText; out.textAmount = 1
            } else {
                out.levels = Self.copperFade(withText, normal, j - 279, 64); out.textAmount = Float(343 - j) / 64
            }
        }
        return out
    }

    /// The 1993 screen on a step: 320 x 400 colour numbers (the horizon on lines 50...349, each picture row
    /// on two; the text's bits ORed in), and its palette.
    func classicScreen(at: Int? = nil) -> (numbers: [UInt8], levels: [Int]) {
        let now = shown(at: at)
        var out = [UInt8](repeating: 0, count: Self.width * Self.height)
        for line in 50..<350 {
            let row = (line - 50) / 2
            for x in 0..<Self.width { out[line * Self.width + x] = pixels[row * 640 + x + now.position] }
        }
        let bits: [UInt8]?
        switch now.text {
        case .none: bits = nil
        case .title(let k): bits = titleBits[k]
        case .page(let k): bits = pageBits[k]
        }
        if let bits { for i in 0..<out.count { out[i] |= bits[i] } }
        return (out, now.levels)
    }
}
