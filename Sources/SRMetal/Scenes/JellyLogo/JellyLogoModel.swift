import Foundation

/// The jelly logo (part 15, `JPLOGO/JP.C`, `ASM.ASM` and `ZOOM.INC`, Psi): a tall picture drops in from
/// the top, then wobbles like jelly as it lands, squashed and stretched with every row resized.
///
/// - The screen: 320x400 (a tweaked mode). The picture is columns 70...253 of `15-jelly-logo` plus one
///   white column at its right edge (JP.C's `row[y][184] = 65`; colour 65 is white in its palette).
/// - Slide-in (86 refreshes, as the original's 86 waits): the picture is drawn once, full width (184),
///   and the screen's start row moves from 400 (nothing) to 0, `y -= a; a += 6` in 1/64 rows.
/// - Wait: in the demo, until "music plus" ≥ 4 (about 3 steps; on its own: none).
/// - Jelly (700 refreshes): the top and bottom edges follow a small bounce worked out in JP.C (200
///   frames in 1/16 pixels, spread over 800 refreshes so that each value shows twice; still from refresh
///   379). Rows between the edges show source row b = (y − y1)·400 / (y2 − y1) at width
///   184 + (sin1024[b·32/25]·xsc + 32) / 64 (even), xsc = (400 − (y2 − y1)) / 8: squashed, the middle
///   bulges; stretched, it thins. A row keeps its old drawing when its source row and width have not
///   changed, and that memory is not cleared when a row is blanked, so a few rows stay black
///   (134 row-refreshes in all, as in 1993).
/// - Line stretching: `ZOOM.INC`'s routines, written by `DOL.C`: width w (clamped to 140...244) puts
///   source column ((x − le)·185 + c/2) / c at screen columns le = 160 − w/2 ... 160 + w/2 (c = w + 1),
///   black elsewhere in columns 32...287.
///
/// Step pairing (as the switch-off): what the program set up before its n-th wait shows on step n − 1;
/// jelly step j shows the rows drawn after `doit`'s j-th wait (j = 0: the slide-in's picture).
/// On its own: slide-in, jelly, 35 steps holding the last picture, then again (821 steps).
struct JellyLogoModel {
    static let slideSteps = 86
    /// On its own there is no music to wait for: the jelly starts as the picture lands.
    static let standaloneWait = 0
    static let jellySteps = 700
    static let holdSteps = 35
    static let musicCue = 4
    static let width = 320, height = 400
    /// The columns every line routine writes (DOL.C's BEG/END band).
    static let band = 32..<288
    /// Colour numbers on the 1993 screen: blank black, the white edge column, then the picture's colours.
    static let blankColour: UInt8 = 0, edgeColour: UInt8 = 1, firstPictureColour = 2

    enum Phase: Equatable { case slide, wait, jelly, hold }

    /// JPLOGO's own sine table: unlike the other parts' copies, clamped to −255...255.
    static let sine: [Int] = SinTable.sin1024.map { min(max($0, -255), 255) }

    /// The slide-in's start row, 1/64 rows, after each of its 83 moves (the last is 0).
    static let slidePath: [Int] = {
        var out: [Int] = [], y = 400 * 64, a = 64
        while y > 0 {
            y -= a; a += 6
            y = max(y, 0)
            out.append(y)
        }
        return out
    }()

    /// JP.C main's bounce: the top and bottom edges for 200 frames, in 1/16 pixels.
    static let bounce: (top: [Int], bottom: [Int]) = {
        func cdiv(_ a: Int, _ b: Int) -> Int { a / b }   // Swift's / rounds towards zero, as C's
        var y1 = 0, y1a = 500, y2 = 399 * 16, y2a = 500, mika = 1, halt = false, a = 0
        var top: [Int] = [], bottom: [Int] = []
        for frame in 0..<200 {
            if !halt {
                y1 += y1a; y2 += y2a
                y2a += 16
                if y2 > 400 * 16 {
                    y2 -= y2a
                    y2a = cdiv(-y2a * mika, 8)
                    if mika < 4 { mika += 3 }
                }
                y1a += 16
                let la = a
                a = (y2 - y1) - 400 * 16
                if (a & 0x8000) ^ (la & 0x8000) != 0 { y1a = cdiv(y1a * 7, 8) }   // 16-bit sign bits
                y1a += cdiv(a, 8)
                y2a -= cdiv(a, 8)
            }
            if frame > 90 {
                if y2 >= 399 * 16 { y2 = 400 * 16; halt = true } else { y2a = 8 }
                y1 = y2 - 400 * 16
            }
            top.append(y1); bottom.append(y2)
        }
        return (top, bottom)
    }()

    /// The edges `doit` uses at refresh `frame` (1...511), whole pixels: framey1t / framey2t, where
    /// (f[b]·(3 − c) + f[b + 1]·c) / 3 with c = 3 already gives f[b + 1], so every value shows twice.
    static func edges(frame: Int) -> (top: Int, bottom: Int) {
        let f = min(frame, 511), b = f / 4, c = f & 3
        let t = (bounce.top[b] * (3 - c) + bounce.top[b + 1] * c) / 3
        let u = (bounce.bottom[b] * (3 - c) + bounce.bottom[b + 1] * c) / 3
        return (t / 16, u / 16)
    }

    /// The Modern look's edges at jelly step `j` (unrounded pixels): the bounce spread evenly over its 4
    /// refreshes (no value twice), the slide-in's picture at j = 0.
    static func smoothEdges(_ j: Float) -> SIMD2<Float> {
        func spread(_ r: Float) -> SIMD2<Float> {
            let r = min(r, 796), b = Int(r / 4), c = r / 4 - Float(b)
            func at(_ list: [Int]) -> Float { (Float(list[b]) + (Float(list[min(b + 1, 199)]) - Float(list[b])) * c) / 16 }
            return SIMD2(at(bounce.top), at(bounce.bottom))
        }
        let start = SIMD2<Float>(0, 400)
        if j <= 0 { return start }
        return j < 1 ? start + (spread(1) - start) * j : spread(j)
    }

    /// DOL.C's columns for a call with `width`: per screen column the source column (0...184), −1 for
    /// black, −2 for left alone. Index by width / 2 (widths 0...318).
    static let columns: [[Int16]] = (0..<160).map { half -> [Int16] in
        let width = half * 2
        var xt = [Int16](repeating: -2, count: 320)
        if width == 0 {
            for x in band { xt[x] = -1 }
            return xt
        }
        let w = min(max(width, 140), 244)
        let le = 160 - w / 2, ri = 160 + w / 2, c = ri - le + 1
        for x in band { xt[x] = (x < le || x > ri) ? -1 : Int16(((x - le) * 185 + c / 2) / c) }
        return xt
    }

    // Fixed data.
    /// 400 source rows of 185 colour numbers (the picture's columns 70...253, then the white edge).
    private let rows: [UInt8]

    // State.
    private(set) var phase = Phase.slide
    /// Steps into the current phase (in the jelly: which `doit` refresh shows).
    private(set) var phaseStep = 0
    /// The picture's 400 rows of video memory (the rows below them are always black).
    private(set) var memory = [UInt8](repeating: 0, count: 320 * 400)
    /// The screen's start row.
    private(set) var startRow = 0
    private var lastRow = [Int](repeating: -1, count: 400)
    private var lastWidth = [Int](repeating: -1, count: 400)
    private var blank = [Bool](repeating: true, count: 400)
    private var edges = (top: 0, bottom: 0)
    /// Row-refreshes the row cache left black (a check; 134 in a whole run).
    private(set) var rowsLeftBlack = 0
    /// Inside Play Demo: the music's "music plus", given before each step. nil on its own.
    var musicPlus: Int?

    /// `picture`: 320x400 colour numbers, where the picture's own colour k is `firstPictureColour + k`.
    init(picture: [UInt8]) {
        precondition(picture.count == 320 * 400)
        var rows = [UInt8](repeating: Self.edgeColour, count: 400 * 185)
        for y in 0..<400 {
            for x in 0..<184 { rows[y * 185 + x] = picture[y * 320 + 70 + x] }
        }
        self.rows = rows
        reset()
    }

    mutating func reset() {
        phase = .slide
        phaseStep = 0
        memory = [UInt8](repeating: Self.blankColour, count: 320 * 400)
        startRow = 0
        lastRow = [Int](repeating: -1, count: 400)
        lastWidth = [Int](repeating: -1, count: 400)
        blank = [Bool](repeating: true, count: 400)
        rowsLeftBlack = 0
    }

    mutating func tick() {
        phaseStep += 1
        switch phase {
        case .slide:
            let s = phaseStep
            if s == 1 { startRow = 400 }
            if s == 2 { for y in 0..<400 { zoomLine(y, row: y, width: 184) } }   // drawn after the second wait
            if (2...Self.slideSteps - 2).contains(s) { startRow = Self.slidePath[s - 2] / 64 }
            if s == Self.slideSteps - 1 { startRow = 0 }
            if s >= Self.slideSteps {
                phase = .wait
                phaseStep = 0
                startIfCued()
            }
        case .wait:
            startIfCued()
        case .jelly:
            if phaseStep >= Self.jellySteps {
                if musicPlus == nil { phase = .hold; phaseStep = 0 } else { phaseStep = Self.jellySteps - 1 }
            } else {
                doitFrame(phaseStep)
            }
        case .hold:
            if phaseStep >= Self.holdSteps { reset() }
        }
    }

    /// `doit` starts once "music plus" is 4 or more (a loop with no wait in it, so on the very step).
    private mutating func startIfCued() {
        if musicPlus.map({ $0 >= Self.musicCue }) ?? (phaseStep >= Self.standaloneWait) {
            phase = .jelly
            phaseStep = 0
        }
    }

    /// One pass of `doit`'s row loop, for refresh `frame`.
    private mutating func doitFrame(_ frame: Int) {
        if frame <= 511 { edges = Self.edges(frame: frame) }
        let (y1, y2) = edges
        let xsc = (400 - (y2 - y1)) / 8
        for y in 0..<400 {
            if y < y1 || y >= y2 {
                zoomLine(y, row: nil, width: 0)
                blank[y] = true
                continue
            }
            let b = (y - y1) * 400 / (y2 - y1)
            let a = (184 + (Self.sine[b * 32 / 25] * xsc + 32) / 64) & ~1
            if lastRow[y] != b || lastWidth[y] != a {
                zoomLine(y, row: b, width: a)
                lastRow[y] = b
                lastWidth[y] = a
                blank[y] = false
            } else if blank[y] {
                rowsLeftBlack += 1
            }
        }
    }

    /// `linezoom`: one row of video memory from source row `row` (nil: black) at `width`.
    private mutating func zoomLine(_ y: Int, row: Int?, width: Int) {
        let xt = Self.columns[(min(width, 318) & ~1) / 2]
        for x in Self.band {
            let v = xt[x]
            if v == -2 { continue }
            memory[y * 320 + x] = (v == -1 || row == nil) ? Self.blankColour : rows[row! * 185 + Int(v)]
        }
    }

    /// The 1993 screen as shown: colour numbers, 320x400.
    var screen: [UInt8] {
        var out = [UInt8](repeating: Self.blankColour, count: 320 * 400)
        let shown = max(0, 400 - startRow)
        if shown > 0 { out.replaceSubrange(0..<(shown * 320), with: memory[(startRow * 320)..<(400 * 320)]) }
        return out
    }

    // MARK: The Modern look

    /// What the Modern look draws, `alpha` of a step on: nil (black), or the start row (unrounded) with
    /// the picture flat, or the edges of the jelly.
    enum ModernView: Equatable {
        case black
        case slide(startRow: Float)
        case jelly(top: Float, bottom: Float)
    }

    func modernView(alpha: Float) -> ModernView {
        switch phase {
        case .slide:
            let s = phaseStep
            if s == 0 { return .black }
            func row(_ s: Int) -> Float {
                if s <= 1 { return 400 }
                if s >= Self.slideSteps - 1 { return 0 }
                return Float(Self.slidePath[s - 2]) / 64
            }
            return .slide(startRow: row(s) + (row(s + 1) - row(s)) * alpha)
        case .wait:
            return .slide(startRow: 0)
        case .jelly, .hold:
            let j = phase == .hold ? Float(Self.jellySteps - 1) : min(Float(phaseStep) + alpha, Float(Self.jellySteps - 1))
            let e = Self.smoothEdges(j)
            return .jelly(top: e.x, bottom: e.y)
        }
    }
}
