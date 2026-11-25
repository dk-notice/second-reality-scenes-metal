import Foundation

/// Finds the credits' data (`Data/Credits`, copied into the app as `Resources/Credits`).
enum CreditsData {
    static let folder = DataFolder.find(resource: "Credits", devPath: "Data/Credits", marker: "CREDPICS.BIN")

    static func load(_ name: String) throws -> [UInt8] {
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else {
            throw CreditsError.missing(name)
        }
        return [UInt8](data)
    }
}

enum CreditsError: Error, CustomStringConvertible {
    case missing(String)
    case badData(String)
    var description: String {
        switch self {
        case .missing(let name): return "Credits file \(name) not found (Resources/Credits or Data/Credits)"
        case .badData(let what): return "Credits data is not as expected: \(what)"
        }
    }
}

/// The credits (part 18, `CREDITS/MAIN.C` with `TWEAK.ASM`), as RELEASED: 21 screens, each a small
/// picture of a part and who made it. No drawing here.
///
/// Each screen takes 362 steps: one wait (the screen cleared), the picture sliding in from the right into
/// the top half while the text rises from the bottom (102 steps, slowing down), 200 steps still, then both
/// sliding away, speeding up (59). The whole is 7,602 steps; on its own the scene then starts again.
///
/// How the 1993 screen was made, and why the text shows only every other row of its font, is in
/// `tools/credits_reference.py` (which this follows) and `docs/scenes/credits.md`.
struct CreditsModel {
    static let screens = 21
    static let stepsPerScreen = 362
    static let length = screens * stepsPerScreen
    static let slideInSteps = 102
    static let holdSteps = 200
    static let slideOutSteps = 59

    /// The canvas: 320 pixels across, the card's 400 lines down (each display row is 2 lines).
    static let width = 320
    static let height = 400

    /// The released texts (they differ from the source's MAIN.C), one list of lines per screen. A
    /// first line that is empty is printed as an empty line, moving the rest down one line.
    static let texts: [[String]] = [
        ["GRAPHICS - MARVEL", "MUSIC - SKAVEN", "CODE - WILDFIRE"],
        ["GRAPHICS - MARVEL", "MUSIC - SKAVEN", "CODE - PSI", "OBJECTS - WILDFIRE"],
        ["GRAPHICS - MARVEL", "MUSIC - SKAVEN", "CODE - WILDFIRE", "ANIMATION - TRUG"],
        ["", "GRAPHICS - PIXEL"],
        ["GRAPHICS - PIXEL", "MUSIC - PURPLE MOTION", "CODE - PSI"],
        ["", "MUSIC - PURPLE MOTION", "CODE - TRUG"],
        ["", "MUSIC - PURPLE MOTION", "CODE - PSI"],
        ["", "MUSIC - PURPLE MOTION", "CODE - PSI"],
        ["", "GRAPHICS - PIXEL", "MUSIC - PURPLE MOTION"],
        ["GRAPHICS - PIXEL", "MUSIC - PURPLE MOTION", "CODE - TRUG", "RENDERING - TRUG"],
        ["SKETCH - SKAVEN", "GRAPHICS - PIXEL", "MUSIC - PURPLE MOTION", "CODE - PSI"],
        ["SKETCH - SKAVEN", "GRAPHICS - PIXEL", "MUSIC - PURPLE MOTION", "CODE - PSI"],
        ["", "MUSIC - PURPLE MOTION", "CODE - WILDFIRE"],
        ["", "MUSIC - PURPLE MOTION", "CODE - WILDFIRE"],
        ["", "MUSIC - PURPLE MOTION", "CODE - PSI"],
        ["GRAPHICS - PIXEL", "MUSIC - PURPLE MOTION", "CODE - TRUG", "RENDERING - TRUG"],
        ["", "MUSIC - PURPLE MOTION", "CODE - PSI"],
        ["GRAPHICS - MARVEL", "MUSIC - PURPLE MOTION", "CODE - PSI"],
        ["MUSIC - SKAVEN", "CODE - PSI", "WORLD - TRUG"],
        ["GRAPHICS - PIXEL", "MUSIC - SKAVEN"],
        ["GRAPHICS - PIXEL", "MUSIC - SKAVEN", "CODE - WILDFIRE"],
    ]

    /// The pictures' names in `artwork/` (the same pictures, exported), for the Modern look's stand-ins.
    static let pictureNames = DemoScript.creditsPictures

    /// What each picture is in the Modern look (user, 2026-11-25): the scene it shows, captured in its
    /// Modern look at the step whose 1993 look is most like the released picture (`--credits-match`;
    /// the ships by eye, as no step matches their picture well; the opening credits within the page the
    /// picture shows, as dimmer steps match its darker colours better). `build.sh` renders them into the
    /// app (`--credits-captures`). nil: the released picture through Super-xBR (none now). Picture 21
    /// shows this very screen: it is this scene's own Modern screen 21, captured with that picture made
    /// the plain way.
    static let captures: [(scene: String, step: Int)?] = [
        ("opening-credits", 3664), ("ships-flyby", 360), ("explosion", 124), ("title-picture", 158), ("glenz-vectors", 594),
        ("dot-tunnel", 745), ("interference", 218), ("techno-bars", 68), ("troll", 87),
        ("mountain-scroller", 338), ("lens", 456), ("rotozoomer", 3400), ("plasma", 726),
        ("plasma-cube", 458), ("bouncing-dots", 1527), ("water-scroller", 1013), ("sine-landscape", 546),
        ("jelly-logo", 264), ("city-3d", 858), ("end-picture", 160), ("credits", 20 * stepsPerScreen + 250),
    ]

    /// The captures' size (4:3, like the 1993 picture at its shown shape).
    static let captureSize = (width: 1280, height: 960)

    static func captureName(_ index: Int) -> String { String(format: "cap%02d.png", index + 1) }

    // MARK: - The data

    struct Picture {
        /// 768 VGA levels (0...63).
        var palette: [UInt8]
        /// 160 x 100 colour numbers, 0...239.
        var pixels: [UInt8]
    }

    /// The font: 40 rows of 1,500 shades (0...9); the program uses the top 32.
    struct Font {
        static let rows = 32
        static let stride = 1500
        let shades: [UInt8]
        /// Where each character starts in the font, and how wide it is (MAIN.C `init`).
        let glyphs: [Character: (start: Int, width: Int)]

        static let order = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/?!:,.\"()+-"

        init(shades: [UInt8]) throws {
            guard shades.count == 40 * Self.stride else { throw CreditsError.badData("CREDFONT.BIN size \(shades.count)") }
            self.shades = shades
            func inked(_ x: Int) -> Bool { (0..<Self.rows).contains { shades[$0 * Self.stride + x] != 0 } }
            var glyphs: [Character: (Int, Int)] = [:]
            var x = 0
            for ch in Self.order {
                while x < Self.stride && !inked(x) { x += 1 }
                let start = x
                while x < Self.stride && inked(x) { x += 1 }
                glyphs[ch] = (start, x - start)
            }
            glyphs[" "] = (Self.stride - 32, 8)
            self.glyphs = glyphs
        }

        func shade(_ ch: Character, column: Int, row: Int) -> UInt8 {
            guard let glyph = glyphs[ch] else { return 0 }
            return shades[row * Self.stride + glyph.start + column]
        }

        /// A line's width as `prtc` counts it (each character and 2 pixels after it).
        func width(_ line: String) -> Int { line.reduce(0) { $0 + (glyphs[$1]?.width ?? 0) + 2 } }
    }

    let pictures: [Picture]
    let font: Font

    static func load() throws -> CreditsModel {
        let data = try CreditsData.load("CREDPICS.BIN")
        let size = 16 + 768 + 16000
        guard data.count == screens * size else { throw CreditsError.badData("CREDPICS.BIN size \(data.count)") }
        let pictures = (0..<screens).map { k -> Picture in
            let s = k * size
            return Picture(palette: Array(data[(s + 16)..<(s + 784)]), pixels: Array(data[(s + 784)..<(s + size)]))
        }
        guard pictures.allSatisfy({ $0.palette.allSatisfy { $0 < 64 } }) else { throw CreditsError.badData("palette levels") }
        return CreditsModel(pictures: pictures, font: try Font(shades: CreditsData.load("CREDFONT.BIN")))
    }

    // MARK: - Where things are

    private(set) var step = 0

    mutating func reset() { step = 0 }
    mutating func tick() { step = (step + 1) % Self.length }

    var screen: Int { step / Self.stepsPerScreen }
    var local: Int { step % Self.stepsPerScreen }

    /// The card's registers as shown on a screen's step (0...361): the split line (in the 400 lines;
    /// 400 is none), the fine scroll's yy and the start address's yy (the picture's window starts yy
    /// pixels into the 640-wide memory). The start address written after a wait shows a refresh later
    /// (see `tools/credits_reference.py`).
    struct Registers: Equatable {
        var split: Int
        var pan: Int
        var start: Int
        /// Where the top half's window starts, in pixels of video memory.
        var view: Int { 4 * (start / 4) + (pan & 3) }
    }

    /// How many steps the two slides really take (the tables' lengths), for the self-test to hold the
    /// constants above to.
    static var slideLengths: (in: Int, out: Int) { (slideIn.count, slideOut.count) }

    private static let slideIn: [Int] = {
        var ys: [Int] = []
        var y = 200 * 128
        while y > 0 { ys.append(y); y = y * 12 / 13 }
        return ys
    }()

    private static let slideOut: [Int] = {
        var ys: [Int] = []
        var y = 0, v = 0
        while y < 128 * 200 { ys.append(y); y += v; v += 15 }
        return ys
    }()

    /// The y values as they were set, for the Modern look (which slides smoothly between them): the
    /// text's rise (split line) and the picture's slide follow them.
    static func registers(local: Int) -> Registers {
        if local == 0 { return Registers(split: 400, pan: 0, start: 0) }
        var j = local - 1
        if j < slideIn.count {
            return Registers(split: slideIn[j] / 128 + 200, pan: 320 - slideIn[j] / 80,
                             start: j == 0 ? 0 : 320 - slideIn[j - 1] / 80)
        }
        j -= slideIn.count
        let held = 320 - slideIn[slideIn.count - 1] / 80
        if j < holdSteps { return Registers(split: slideIn[slideIn.count - 1] / 128 + 200, pan: held, start: held) }
        j -= holdSteps
        return Registers(split: slideOut[j] / 128 + 200, pan: 320 + slideOut[j] / 80,
                         start: j == 0 ? held : 320 + slideOut[j - 1] / 80)
    }

    var registers: Registers { Self.registers(local: local) }

    // MARK: - The 1993 picture

    /// The 256 colours of screen k: the picture's colours moved up 16 (MAIN.C `init`), colours 0...9 the
    /// text's greys (7 x shade), 10...15 the picture's own first colours.
    func palette(screen k: Int) -> [UInt8] {
        let own = pictures[k].palette
        var levels = Array(own[0..<48]) + Array(own[0..<720])
        for a in 0..<10 { levels[a * 3] = UInt8(7 * a); levels[a * 3 + 1] = UInt8(7 * a); levels[a * 3 + 2] = UInt8(7 * a) }
        return levels
    }

    /// Video memory for screen k (just what is drawn): the text as `tw_putpixel` put it (80 bytes a row
    /// into 160-byte rows, so font row y lands on display row y / 2, at x + 320 when y is odd), and the
    /// picture at display rows 200...299, x 400...559. 640 x 300 colour numbers.
    func memory(screen k: Int) -> [UInt8] {
        var memory = [UInt8](repeating: 0, count: 640 * 300)
        var y = 16
        for line in Self.texts[k] {
            var x = 160 - font.width(line) / 2
            for ch in line {
                let width = font.glyphs[ch]?.width ?? 0
                for column in 0..<width {
                    let x2 = x + column
                    for row in 0..<Font.rows {
                        let address = 80 * (y + row) + x2 / 4
                        memory[(address / 160) * 640 + (address % 160) * 4 + (x2 & 3)] = font.shade(ch, column: column, row: row)
                    }
                }
                x += width + 2
            }
            y += Font.rows + 10
        }
        let picture = pictures[k].pixels
        for py in 0..<100 {
            for px in 0..<160 { memory[(200 + py) * 640 + 400 + px] = picture[py * 160 + px] + 16 }
        }
        return memory
    }

    /// The 1993 screen now: 320 x 400 colour numbers (each display row on 2 lines).
    func classicScreen() -> [UInt8] {
        let memory = memory(screen: screen)
        let r = registers
        var out = [UInt8](repeating: 0, count: Self.width * Self.height)
        for line in 0..<Self.height {
            // Above and on the split line: display rows from 200, scrolled; below it, rows from 0, not.
            let (row, x0) = line <= r.split ? (200 + line / 2, r.view) : ((line - r.split - 1) / 2, 0)
            for c in 0..<Self.width {
                let x = x0 + c
                let rr = row + x / 640, xx = x % 640
                if rr < 300 { out[line * Self.width + c] = memory[rr * 640 + xx] }
            }
        }
        return out
    }
}
