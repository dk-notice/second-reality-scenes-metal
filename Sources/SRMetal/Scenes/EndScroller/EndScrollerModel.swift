import Foundation

/// Finds the end scroller's data (`Data/EndScroller`, copied into the app as `Resources/EndScroller`).
enum EndScrollerData {
    static let folder = DataFolder.find(resource: "EndScroller", devPath: "Data/EndScroller", marker: "ENDSCROL.TXT")

    static func load(_ name: String) throws -> [UInt8] {
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else {
            throw EndScrollerError.missing(name)
        }
        return [UInt8](data)
    }
}

enum EndScrollerError: Error, CustomStringConvertible {
    case missing(String)
    case badFont
    var description: String {
        switch self {
        case .missing(let name): return "End scroller file \(name) not found (Resources/EndScroller or Data/EndScroller)"
        case .badFont: return "ENDFONT.BIN is not 25 rows of 1550 bytes"
        }
    }
}

/// The released end scroller's font: 25 rows, 1,550 columns, each pixel 0 or a shade 1...3.
/// Glyphs are found as the original's `init()` found them: runs of columns with ink, in `order`.
struct EndScrollerFont {
    static let rows = 25
    static let width = 1550
    /// The characters of the glyphs, left to right (the released order; see Data/EndScroller/README.md).
    static let order: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXabcdefghijklmnopqrstuvwxyz0123456789!?,.:".utf8)
        + [0x8F, 0x8F] + Array("()+-*='Z".utf8) + [0x84, 0x94] + Array("Y/&".utf8)

    let pixels: [UInt8]
    private(set) var start = [Int](repeating: 0, count: 256)
    private(set) var width = [Int](repeating: 0, count: 256)

    init(pixels: [UInt8]) throws {
        guard pixels.count == Self.rows * Self.width else { throw EndScrollerError.badFont }
        self.pixels = pixels
        func inked(_ x: Int) -> Bool { (0..<Self.rows).contains { pixels[$0 * Self.width + x] != 0 } }
        var x = 0
        for character in Self.order where x < Self.width {
            while x < Self.width && !inked(x) { x += 1 }
            let first = x
            while x < Self.width && inked(x) { x += 1 }
            start[Int(character)] = first
            width[Int(character)] = x - first
        }
        start[32] = Self.width - 20
        width[32] = 16
    }

    static func load() throws -> EndScrollerFont { try EndScrollerFont(pixels: EndScrollerData.load("ENDFONT.BIN")) }

    func pixel(row: Int, column: Int) -> UInt8 { pixels[row * Self.width + column] }

    /// Where a line starts so that it is centred, as the original worked it out: every character's
    /// width plus a 2-pixel gap (even characters with no glyph, such as the carriage return), then
    /// (639 - total) / 2.
    func lineStart(_ line: [UInt8]) -> Int {
        (639 - line.reduce(0) { $0 + width[Int($1)] + 2 }) / 2
    }
}

/// The end scroller (part 19, `ENDSCRL/MAIN.C`), as the released demo ran it.
///
/// A 640x400 screen in 4 greys. Every second screen refresh the original drew ONE new row of pixels of
/// the current text line at the bottom and moved the screen up by one row (by telling the card to start
/// reading one row later, in a ring of 401 rows). So the text creeps up 35 rows a second. Text lines are
/// 25 rows (the font's height) and centred.
///
/// Two kinds of line are marks, not text; both were read from the RELEASED program (`MAIN/DATA/ENDSCRL.EXE`,
/// unpacked with deark's pklite and then lzexe; the source release's `MAIN.C` is an earlier version):
/// - A line starting `[` draws nothing and takes (2nd character - 48) x 10 + (3rd character - 48) rows
///   (164Fh-1681h). The program does not test that they are digits: `[15` is 15 rows, and `[8`, whose
///   third character is the carriage return (13), is 80 - 35 = 45 rows, not 8.
/// - On the first row of a line starting `%` the program calls `exit(0)` (169Ah): the demo ENDS there.
///   (It does not start again; the C++ port does, and until 2026-11-26 so did this.) On its own, as a
///   scene that must loop, this version then starts the text again; Play Demo ends (`demoLength`).
struct EndScrollerModel {
    static let width = 640
    static let height = 400
    static let ringRows = 401
    /// Refreshes per new row (the original waited for two refreshes before each row).
    static let stepsPerRow = 2

    let font: EndScrollerFont
    /// The text's lines, each with its carriage return as the original kept it.
    let lines: [[UInt8]]

    /// The screen memory: 401 rows of shade numbers 0...3.
    private(set) var ring: [UInt8]
    private(set) var yscrl = 0
    /// Rows drawn so far, ever (the newest row's number is rowsDrawn - 1).
    private(set) var rowsDrawn = 0
    /// Steps since the last row was drawn (0 or 1).
    private(set) var stepsSinceRow = 0
    /// For the Modern look: each text line drawn recently, and the number of its first row.
    private(set) var placed: [(line: Int, firstRow: Int)] = []

    /// Whether the first row of the `%` line has been drawn: where the released program quit.
    private(set) var reachedEnd = false
    /// The number of the last row drawn that had any text in it (-1: none yet).
    private(set) var lastTextRow = -1

    private var nextLine = 0
    private var row = 0
    private var current: [UInt8] = []
    private var start = 0
    private var gapRows = 0          // the current line is a gap of this many rows (0: a text line)
    private var loops = false

    init(font: EndScrollerFont, text: [UInt8]) {
        self.font = font
        var lines = text.split(separator: 10, omittingEmptySubsequences: false).map { Array($0) }
        if lines.last == [] { lines.removeLast() }
        self.lines = lines.isEmpty ? [[]] : lines
        ring = [UInt8](repeating: 0, count: Self.ringRows * Self.width)
    }

    static func load() throws -> EndScrollerModel {
        try EndScrollerModel(font: EndScrollerFont.load(), text: EndScrollerData.load("ENDSCROL.TXT"))
    }

    mutating func reset() { self = EndScrollerModel(font: font, text: Array(lines.joined(separator: [10]))) }

    mutating func tick() {
        stepsSinceRow += 1
        if stepsSinceRow == Self.stepsPerRow {
            stepsSinceRow = 0
            drawRow()
        }
    }

    /// The rows a line starting `[` takes, by the released program's sum (no test for digits; a
    /// character missing counts as 0). At least 1: the program divided by this number.
    static func gapHeight(_ line: [UInt8]) -> Int {
        func value(_ index: Int) -> Int { Int(index < line.count ? line[index] : 0) - 48 }
        return max(1, value(1) * 10 + value(2))
    }

    /// `--end-scroller-steps`: a shorter run, for trying the demo's end in the window. Set (by `Main`)
    /// before `demoLength` is first read, or not at all.
    static var trialLength: Int?

    /// How many steps the scroller runs in Play Demo: up to and with the step that draws the first row
    /// of the `%` line, where the released program quit (0 if the text is missing or has no such line).
    static let demoLength: Int = {
        if let trialLength { return trialLength }
        guard var model = try? load() else { return 0 }
        var steps = 0
        while !model.reachedEnd && steps < 70 * 60 * 30 { model.tick(); steps += 1 }
        return model.reachedEnd ? steps : 0
    }()

    /// A line starting `%` shows nothing and ends the demo (one rule for both looks).
    static func isLoopLine(_ line: [UInt8]) -> Bool { line.first == UInt8(ascii: "%") }

    /// One pass of the original's `do_scroll`.
    private mutating func drawRow() {
        if row == 0 {
            let line = lines[nextLine]
            start = font.lineStart(line)
            gapRows = 0
            loops = Self.isLoopLine(line)
            if line.first == UInt8(ascii: "[") { gapRows = Self.gapHeight(line) }
            current = gapRows > 0 ? [] : line
            if gapRows == 0 { placed.append((nextLine, rowsDrawn)) }
            nextLine = (nextLine + 1) % lines.count
        }
        var pixels = [UInt8](repeating: 0, count: Self.width)
        var x = start
        for character in current {
            let glyph = font.start[Int(character)]
            for column in 0..<font.width[Int(character)] {
                if (0..<Self.width).contains(x) { pixels[x] = font.pixel(row: row, column: glyph + column) }
                x += 1
            }
            x += 2
        }
        if pixels.contains(where: { $0 != 0 }) { lastTextRow = rowsDrawn }
        ring.replaceSubrange(yscrl * Self.width..<(yscrl + 1) * Self.width, with: pixels)
        yscrl = (yscrl + 1) % Self.ringRows
        rowsDrawn += 1
        row = (row + 1) % (gapRows > 0 ? gapRows : EndScrollerFont.rows)
        if loops { nextLine = 0; reachedEnd = true }
        // Lines that have scrolled off the top are no longer needed.
        placed.removeAll { $0.firstRow + EndScrollerFont.rows < rowsDrawn - Self.height - 1 }
    }

    /// The screen: 400 rows of shade numbers, top to bottom. The original showed the ring from the row
    /// after the one about to be drawn, so the newest row is the bottom one.
    var screen: [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(Self.width * Self.height)
        for r in 0..<Self.height {
            let ringRow = (yscrl + 1 + r) % Self.ringRows
            out += ring[ringRow * Self.width..<(ringRow + 1) * Self.width]
        }
        return out
    }

    /// The four greys, as 1993 colour levels (`setrgbpalette` in MAIN.C: 1 = 20, 2 = 40, 3 and up = 60).
    static let levels = [0, 20, 40, 60]
}
