import Foundation

/// The lens's four tables (`LENS.EX1`...`EX4`): for each of 120 rows a byte offset and a count, then
/// the rows' lists (16-bit words). Tables 1-3 are worked out here from the lens shape, exactly as
/// `LENS/CALC.C` made them; table 4 (the wiping ring) is the original file (see `Data/Lens/README.md`).
enum LensTables {
    static let folder = DataFolder.find(resource: "Lens", devPath: "Data/Lens", marker: "LENS.EX4")
    /// The lens shape's zone numbers (0 outside, 1-3 the lens, 4 the ring) from the exported picture's
    /// colours (`LENS.LBM`'s colours 0-4).
    static let zoneColours: [SIMD3<UInt8>: UInt8] = [
        SIMD3(0, 0, 0): 0, SIMD3(71, 91, 127): 1, SIMD3(75, 103, 171): 2, SIMD3(71, 107, 219): 3, SIMD3(51, 51, 51): 4
    ]
    static let shapeName = "10-lens-shape"

    /// The shape, 320x200 zone numbers.
    static func shape() -> [UInt8]? {
        guard let rgb = ScenePicture.pixels(shapeName), rgb.count == 320 * 200 * 3 else { return nil }
        var out = [UInt8](repeating: 0, count: 320 * 200)
        for i in 0..<(320 * 200) {
            guard let zone = zoneColours[SIMD3(rgb[3 * i], rgb[3 * i + 1], rgb[3 * i + 2])] else { return nil }
            out[i] = zone
        }
        return out
    }

    /// Table 4 from its file. nil if the file is missing or damaged: `LensModel.drawRow` reads by the
    /// table's own offsets and counts, so they are checked here, once.
    static func ringTable() -> [UInt16]? {
        guard let url = folder?.appendingPathComponent("LENS.EX4"), let data = try? Data(contentsOf: url) else { return nil }
        return ringTable(bytes: [UInt8](data))
    }

    static func ringTable(bytes: [UInt8]) -> [UInt16]? {
        guard bytes.count % 2 == 0 else { return nil }
        let table = stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
        // Every row the lens draws: its header is there, and its list (a first word, then `count` words)
        // lies inside the table.
        guard table.count >= 2 * LensModel.lensHeight else { return nil }
        for row in 0..<LensModel.lensHeight {
            let start = Int(table[2 * row]) / 2, count = Int(table[2 * row + 1])
            guard start + 1 + count <= table.count else { return nil }
        }
        return table
    }

    /// CALC.C's tables 1-3 from the shape. Microsoft C's `rand()` (seed 1, never reseeded) gives each
    /// pixel a small random wobble; the four passes share one sequence (pass 4 draws none).
    static func calculated(shape: [UInt8]) -> [[UInt16]] {
        var seed: UInt32 = 1
        func rand() -> Int {
            seed = seed &* 214013 &+ 2531011
            return Int((seed >> 16) & 0x7FFF)
        }
        let cx = 76, cy = 58, ymax = 120, xmax = 150
        let full = Double(59 * 59 + 50 * 50)
        func lenscalc(_ x: Int, _ y: Int) -> (Int, Int) {
            let yy = y * 9 / 8                       // C: truncates towards zero, as Swift does
            var now = full - Double(x * x + yy * yy)
            if now < 1 { now = 1 }
            let new = 250.0 / pow(now, 0.69)
            let fx = Double(rand() - 16384) / 30000.0
            let fy = Double(rand() - 16384) / 30000.0
            return (Int((Double(x) + fx) * new), Int((Double(y) + fy) * new))
        }
        var tables: [[UInt16]] = []
        for col in 1...3 {
            var rd: [Int] = []
            var rowbeg = [Int](repeating: 0, count: ymax), rowcnt = [Int](repeating: 0, count: ymax)
            for y in 0..<ymax {
                var z = -1
                rowbeg[y] = rd.count
                for x in 0..<xmax {
                    let v = shape[x + y * 320]
                    let wanted = col == 1 ? (v != 0 && v != 4) : Int(v) == col
                    guard wanted else { continue }
                    if z == -1 { rd.append(x); z = x + y * 320 }
                    let (x2, y2) = lenscalc(x - cx, y - cy)
                    if col != 1 { rd.append(x + y * 320 - z) }
                    rd.append((cx + x2) + (cy + y2) * 320 - z)
                }
                let c = max(rd.count - rowbeg[y] - 1, 0)
                rowcnt[y] = col == 1 ? c : c / 2
            }
            var words: [UInt16] = []
            for a in 0..<ymax {
                words.append(UInt16(truncatingIfNeeded: rowbeg[a] * 2 + ymax * 4))
                words.append(UInt16(truncatingIfNeeded: rowcnt[a]))
            }
            words += rd.map { UInt16(truncatingIfNeeded: $0) }
            tables.append(words)
        }
        return tables
    }
}

/// The lens (parts 1 and 2 of the lens part, `LENS/MAIN.C` and `LENS/ASM.ASM`, Psi):
///
/// 1. Part 1, 300 refreshes: the picture is uncovered by two sweeps on every row, 6 moves per refresh for
///    the first 80 refreshes. Row b's sweeps start at (170·64 + (100 − b)·50) / 64 and move right by
///    ((23 + b/5) & ~7) / 64 and left by ((23 + (199 − b)/5) rounded up to 8) / 64 per move; each move
///    copies the picture's pixel at row·320 + x, so a sweep that runs past a row's end carries on into the
///    next row. MAIN.C's ints are 16-bit, and the bottom rows' right sweep overflows near the end.
/// 2. Part 2, 720 refreshes: the lens bounces in along a path (worked out from the SAVEPATH formulas;
///    all 715 positions equal `LENS.EXP`). Each refresh it is drawn over the screen as it is: table 1
///    puts every lens pixel (zones 1-3) bent and tinted (colour + 64), tables 2 and 3 redraw zones 2 and 3
///    bent again and tinted more (+128, +192), table 4 repaints the ring around it with the picture
///    (wiping where the lens was). For the first 96 refreshes colours 64-255 fade from the tint alone to
///    the tinted picture (from refresh 32, in 32 steps of 2).
///
/// On its own: 35 black steps, part 1, part 2, 35 steps of the last picture, then again. Inside Play
/// Demo: black until "music plus" ≥ −6, part 1, the picture until "music plus" ≥ −20, part 2.
struct LensModel {
    static let blackSteps = 35
    static let revealSteps = 300
    static let sweepSteps = 80
    static let movesPerStep = 6
    static let lensSteps = 720
    static let pathSteps = 715
    static let holdSteps = 35
    static let startCue = -6
    static let lensCue = -20
    /// The lens's size (`LENS.EX0`: 152 wide, 116 tall) and its three tints.
    static let lensWidth = 152, lensHeight = 116
    static let tints: [SIMD3<Int>] = [SIMD3(0, 5, 15), SIMD3(0, 7, 26), SIMD3(0, 9, 37)]

    enum Phase: Equatable { case black, reveal, waitLens, lens, hold }

    /// The path (whole pixels, as played) and the same in 1/64 pixels before rounding (Modern look).
    struct PathPoint: Equatable { var x: Int, y: Int, x64: Int, y64: Int }

    /// MAIN.C part2's SAVEPATH branch.
    static let path: [PathPoint] = {
        var x = 65 * 64, y = -50 * 64, xa = 64, ya = 64, first = true
        var out: [PathPoint] = []
        for frame in 0..<pathSteps {
            out.append(PathPoint(x: x / 64, y: y / 64, x64: x, y64: y))
            x += xa; y += ya
            if x > 256 * 64 || x < 60 * 64 { xa = -xa }
            if y > 150 * 64 && frame < 600 {
                y -= ya
                if first { ya = -ya * 2 / 3; first = false } else { ya = -ya * 9 / 10 }
            }
            ya += 2
        }
        return out
    }()

    // Fixed data.
    /// The picture's colour numbers, 64 KB (beyond 64,000: a copy of the last 1,536, as MAIN.C makes it).
    private let back: [UInt8]
    /// The picture's colours (VGA levels), at most 64.
    let colours: [SIMD3<Int>]
    private let tables: [[UInt16]]
    /// Colours 0-255 before part 2's fade: the picture's, then three tinted copies.
    private let fullPalette: [SIMD3<Int>]
    /// Part 2's 32 fades of colours 64-255.
    private let fades: [[SIMD3<Int>]]

    // State.
    private(set) var phase = Phase.black
    /// Steps into the current phase.
    private(set) var phaseStep = 0
    /// The 1993 screen: 64 KB of colour numbers (the first 64,000 show).
    private(set) var screen = [UInt8](repeating: 0, count: 65536)
    private(set) var palette: [SIMD3<Int>]
    private var sweepRight: [Int16] = []
    private var sweepLeft: [Int16] = []
    /// Inside Play Demo: the music's "music plus", given before each step. nil on its own.
    var musicPlus: Int?

    /// `picture`: 320x200 colour numbers into `colours`. `tables`: the four lens tables.
    init(picture: [UInt8], colours: [SIMD3<Int>], tables: [[UInt16]]) {
        precondition(picture.count == 64000 && colours.count <= 64 && tables.count == 4)
        var back = [UInt8](repeating: 0, count: 65536)
        back.replaceSubrange(0..<64000, with: picture)
        back.replaceSubrange(64000..<65536, with: picture[(64000 - 1536)..<64000])
        self.back = back
        self.colours = colours
        self.tables = tables
        var full = [SIMD3<Int>](repeating: .zero, count: 256)
        for n in 0..<colours.count {
            full[n] = colours[n]
            for i in 1...3 { full[64 * i + n] = pointwiseMin(colours[n] &+ Self.tints[i - 1], SIMD3(repeating: 63)) }
        }
        fullPalette = full
        // fade2: colour − base·(31 − x)/31, per level, in whole numbers.
        fades = (0..<32).map { x in
            (64..<256).map { c in
                let base = full[c % 64]
                return SIMD3((0..<3).map { full[c][$0] - base[$0] * (31 - x) / 31 })
            }
        }
        palette = full
        reset()
    }

    mutating func reset() {
        phase = .black
        phaseStep = 0
        screen = [UInt8](repeating: 0, count: 65536)
        palette = fullPalette
        sweepRight = (0..<200).map { Int16(170 * 64 + (100 - $0) * 50) }
        sweepLeft = sweepRight
    }

    mutating func tick() {
        phaseStep += 1
        switch phase {
        case .black:
            if let plus = musicPlus { if plus >= Self.startCue { startReveal() } } else if phaseStep >= Self.blackSteps { startReveal() }
        case .reveal:
            if phaseStep >= Self.revealSteps {
                phase = .waitLens
                phaseStep = 0
                waitForLens()
            } else if phaseStep < Self.sweepSteps {
                sweepStep()
            }
        case .waitLens:
            waitForLens()
        case .lens:
            if phaseStep >= Self.lensSteps {
                if musicPlus == nil { phase = .hold; phaseStep = 0 } else { phaseStep = Self.lensSteps - 1 }
            } else {
                lensStep(phaseStep)
            }
        case .hold:
            if phaseStep >= Self.holdSteps { reset() }
        }
    }

    /// Inside Play Demo, on the step the scene is first shown: if the music's start cue is already met,
    /// the uncovering starts on this very step (as the original's wait then takes no time).
    mutating func startIfCued() {
        if phase == .black && phaseStep == 0, let plus = musicPlus, plus >= Self.startCue { startReveal() }
    }

    private mutating func startReveal() {
        phase = .reveal
        phaseStep = 0
        sweepStep()
    }

    /// Between the parts the original waits for "music plus" ≥ −20 (on its own: no wait).
    private mutating func waitForLens() {
        if musicPlus.map({ $0 >= Self.lensCue }) ?? true {
            phase = .lens
            phaseStep = 0
            lensStep(0)
        }
    }

    // MARK: The 1993 drawing

    /// One refresh of part 1: six moves of both sweeps on every row.
    private mutating func sweepStep() {
        for _ in 0..<Self.movesPerStep {
            for y in 0..<200 {
                for x in [sweepRight[y], sweepLeft[y]] {
                    let a = (y * 320 + Int(x >> 6)) & 0xFFFF   // >> on a signed number: rounds down, as sar
                    screen[a] = back[a]
                }
                sweepRight[y] = sweepRight[y] &+ Int16((23 + y / 5) & ~7)
                sweepLeft[y] = sweepLeft[y] &+ Int16(-(23 + (199 - y) / 5) & ~7)
            }
        }
    }

    private mutating func lensStep(_ k: Int) {
        if k < 96 {
            let a = max((k - 32) / 2, 0)
            palette.replaceSubrange(64..<256, with: fades[a])
        }
        if k < Self.pathSteps { drawLens(Self.path[k].x, Self.path[k].y) }
    }

    /// `drawlens`: the top half row by row downwards and the bottom half upwards, each row only if its
    /// screen address is within 0...64000. Row 116 of the tables is never drawn (the lens is 116 tall).
    mutating func drawLens(_ x0: Int, _ y0: Int) {
        let xs = Self.lensWidth / 2, ys = Self.lensHeight / 2
        var u1 = (x0 - xs) + (y0 - ys) * 320
        var u2 = (x0 - xs) + (y0 + ys - 1) * 320
        let last = Self.lensHeight - 1
        for y in 0..<ys {
            if u1 >= 0 && u1 <= 64000 { drawRow(u1, y) }
            u1 += 320
            if u2 >= 0 && u2 <= 64000 { drawRow(u2, last - y) }
            u2 -= 320
        }
    }

    private mutating func drawRow(_ u: Int, _ y: Int) {
        screen.withUnsafeMutableBufferPointer { scr in
            back.withUnsafeBufferPointer { pic in
                func header(_ t: [UInt16]) -> (start: Int, count: Int) { (Int(t[2 * y]) / 2, Int(t[2 * y + 1])) }
                // dorow (table 1): rows of fewer than 4 pixels are skipped; destination pixels side by side.
                let t1 = tables[0]
                let (s1, n1) = header(t1)
                if n1 >= 4 {
                    let di = u + Int(t1[s1])
                    for k in 0..<n1 { scr[(di + k) & 0xFFFF] = pic[(di + Int(t1[s1 + 1 + k])) & 0xFFFF] | 0x40 }
                }
                // dorow2 (tables 2, 3): (destination, source) pairs.
                for (t, or) in [(tables[1], UInt8(0x80)), (tables[2], UInt8(0xC0))] {
                    let (s, n) = header(t)
                    guard n > 0 else { continue }
                    let di = u + Int(t[s])
                    for p in 0..<n {
                        scr[(di + Int(t[s + 1 + 2 * p])) & 0xFFFF] = pic[(di + Int(t[s + 2 + 2 * p])) & 0xFFFF] | or
                    }
                }
                // dorow3 (table 4): the ring, repainted with the picture.
                let t4 = tables[3]
                let (s4, n4) = header(t4)
                if n4 > 0 {
                    let di = u + Int(t4[s4])
                    for k in 0..<n4 {
                        let a = (di + Int(t4[s4 + 1 + k])) & 0xFFFF
                        scr[a] = pic[a]
                    }
                }
            }
        }
    }

    // MARK: The Modern look

    /// Sweep moves done so far, `alpha` of a step on (480 when the picture is fully uncovered).
    func sweepMoves(alpha: Float) -> Float {
        switch phase {
        case .black: return 0
        case .reveal: return Float(Self.movesPerStep) * min(Float(phaseStep + 1) + alpha, Float(Self.sweepSteps))
        default: return Float(Self.movesPerStep * Self.sweepSteps)
        }
    }

    /// The lens's centre in pixels (unrounded, `alpha` of a step on), or nil when no lens shows.
    func lensCentre(alpha: Float) -> SIMD2<Float>? {
        guard phase == .lens, phaseStep < Self.pathSteps else { return nil }
        let a = Self.path[phaseStep], b = Self.path[min(phaseStep + 1, Self.pathSteps - 1)]
        let pa = SIMD2<Float>(Float(a.x64), Float(a.y64)) / 64, pb = SIMD2<Float>(Float(b.x64), Float(b.y64)) / 64
        return pa + (pb - pa) * alpha
    }

    /// How much of the picture shows through the lens: 0 (the tint alone) ... 1 (the tinted picture).
    func glass(alpha: Float) -> Float {
        guard phase == .lens else { return 1 }
        return min(max((Float(phaseStep) + alpha - 32) / 2, 0), 31) / 31
    }
}
