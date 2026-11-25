import Foundation
import simd

/// The mountain scroller's original files (`Data/Mountain`, see its README): the background with its
/// colour numbers and palette, the text picture, and the three position tables.
struct MountainData {
    static let folder = DataFolder.find(resource: "Mountain", devPath: "Data/Mountain", marker: "POS1.DAT")
    static let columns = 237, rows = 31, textWidth = 640
    static let fileNames = ["POS1.DAT", "POS2.DAT", "POS3.DAT", "HILLBACK.CLX", "O2.SCI"]

    /// One position table: cell i (row x 237 + column) owns `addresses[starts[i]..<starts[i + 1]]`.
    struct Table {
        var starts: [Int]
        var addresses: [UInt16]
    }

    /// The 256 colours, VGA levels 0...63.
    let palette: [SIMD3<Int>]
    /// 320x200 colour numbers.
    let background: [UInt8]
    /// 640x31 values 0...7.
    let text: [UInt8]
    let tables: [Table]

    static func bytes(_ name: String) -> [UInt8]? {
        guard let url = folder?.appendingPathComponent(name), let data = try? Data(contentsOf: url) else { return nil }
        return [UInt8](data)
    }

    /// nil if a file is missing or is not what the part expects.
    static func load() -> MountainData? {
        guard let hills = bytes("HILLBACK.CLX"), hills.count == 778 + 64000,
              let o2 = bytes("O2.SCI"), o2.count >= 778 + textWidth * rows else { return nil }
        var tables: [Table] = []
        for n in 1...3 {
            guard let d = bytes("POS\(n).DAT") else { return nil }
            var table = Table(starts: [0], addresses: [])
            var p = 0
            for _ in 0..<(columns * rows) {
                guard p + 2 <= d.count else { return nil }
                let count = Int(d[p]) | Int(d[p + 1]) << 8
                p += 2
                guard p + 2 * count <= d.count else { return nil }
                for k in 0..<count {
                    let address = UInt16(d[p + 2 * k]) | UInt16(d[p + 2 * k + 1]) << 8
                    guard address < 64000 else { return nil }
                    table.addresses.append(address)
                }
                p += 2 * count
                table.starts.append(table.addresses.count)
            }
            guard p == d.count else { return nil }
            tables.append(table)
        }
        var palette: [SIMD3<Int>] = []
        for colour in 0..<256 {
            let at = 10 + 3 * colour
            palette.append(SIMD3<Int>(Int(hills[at]), Int(hills[at + 1]), Int(hills[at + 2])))
        }
        let textEnd = 778 + textWidth * rows
        return MountainData(palette: palette, background: Array(hills[778...]), text: Array(o2[778..<textEnd]), tables: tables)
    }

    /// The Modern look's map: for every screen pixel a plane through the text coordinates around it,
    /// `u = a + b·dx + c·dy` and the same for v (dx, dy from the pixel's centre, in pixels). u is the
    /// window column (0...237), v the text row (0...31).
    ///
    /// Where the coordinates come from: a pixel that table k (0...2) lists at window column c covers the
    /// third of a column from u = c + (2 − k)/3 (the tables are the hills ray-traced three times with the
    /// text moved a third of a column; `tools/mountain_reference.py` shows the order), and its cell's row
    /// is v. Both are known only in steps (thirds of a column, whole rows), but where two neighbouring
    /// pixels are one step apart, the line between them is where the coordinate crosses that step: an
    /// exact value at a known place. Each pixel gets the weighted best-fit plane through such crossings
    /// around it on the same stretch of hill (and, weakly, through the pixels' own middles). The map is
    /// then grown three pixels outwards, so the text's edges are cut by the plane (a straight edge), not
    /// by the pixel grid.
    struct SmoothMap {
        /// Per pixel: a, b, c, and 1 if the pixel has a plane (else 0).
        var u: [Float]
        /// Per pixel: a, b, c, 0.
        var v: [Float]
    }

    func smoothMap() -> SmoothMap {
        let w = 320, h = 200, none = -1
        // Per pixel: its third of a column (3c + 2 − k) and its row.
        var third = [Int](repeating: none, count: w * h), row = third
        for (k, table) in tables.enumerated() {
            for cell in 0..<(Self.columns * Self.rows) {
                for i in table.starts[cell]..<table.starts[cell + 1] {
                    let a = Int(table.addresses[i])
                    third[a] = 3 * (cell % Self.columns) + 2 - k
                    row[a] = cell / Self.columns
                }
            }
        }
        // Crossings between a pixel and its right (0) and lower (1) neighbour: the coordinate's value on
        // the line between them, or nil.
        var crossU = [Float?](repeating: nil, count: w * h * 2), crossV = crossU
        for y in 0..<h {
            for x in 0..<w {
                let a = y * w + x
                for (side, b) in [(0, x + 1 < w ? a + 1 : -1), (1, y + 1 < h ? a + w : -1)] where b >= 0 {
                    let here = third[a] != none, there = third[b] != none
                    if here && there {
                        let dt = abs(third[a] - third[b]), dr = abs(row[a] - row[b])
                        guard dt <= 3, dr <= 1 else { continue }     // further apart: another fold of the hills
                        if dt >= 1 { crossU[2 * a + side] = Float(third[a] + third[b] + 1) / 6 }
                        if dr == 1 { crossV[2 * a + side] = Float(max(row[a], row[b])) }
                    } else if here != there {
                        // The edge of the text's band: its first row starts and its last row ends here
                        // (unless this is the band's left or right end instead).
                        let inside = here ? a : b
                        guard third[inside] > 6, third[inside] < 3 * Self.columns - 7 else { continue }
                        if row[inside] == 0 { crossV[2 * a + side] = 0 }
                        if row[inside] == Self.rows - 1 { crossV[2 * a + side] = Float(Self.rows) }
                    }
                }
            }
        }
        // Least squares for value = a + b·dx + c·dy.
        typealias Sample = (dx: Float, dy: Float, value: Float, weight: Float)
        func fit(_ points: [Sample]) -> SIMD3<Float>? {
            var m = simd_double3x3(0), r = SIMD3<Double>(0, 0, 0)
            for p in points {
                let b = SIMD3<Double>(1, Double(p.dx), Double(p.dy)), wt = Double(p.weight)
                m += simd_double3x3(columns: (b * b.x * wt, b * b.y * wt, b * b.z * wt))
                r += b * Double(p.value) * wt
            }
            guard abs(m.determinant) > 1e-2 else { return nil }
            return SIMD3<Float>(m.inverse * r)
        }
        var map = SmoothMap(u: [Float](repeating: 0, count: w * h * 4), v: [Float](repeating: 0, count: w * h * 4))
        let radius = 5
        for y in 0..<h {
            for x in 0..<w where third[y * w + x] != none {
                let t0 = third[y * w + x], r0 = row[y * w + x]
                let u0 = (Float(t0) + 0.5) / 3, v0 = Float(r0) + 0.5
                var pu: [Sample] = [], pv: [Sample] = []
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let xx = x + dx, yy = y + dy
                        guard xx >= 0, yy >= 0, xx < w, yy < h else { continue }
                        let b = yy * w + xx
                        guard third[b] != none else { continue }
                        // The same stretch of hill: the coordinates may not jump on the way there.
                        let reach = abs(dx) + abs(dy)
                        guard abs(third[b] - t0) <= 4 * reach + 3, abs(row[b] - r0) <= reach + 1 else { continue }
                        let fx = Float(dx), fy = Float(dy)
                        let weight = exp(-(fx * fx + fy * fy) / 10)
                        pu.append((fx, fy, (Float(third[b]) + 0.5) / 3, weight * 0.05))
                        pv.append((fx, fy, Float(row[b]) + 0.5, weight * 0.05))
                        for side in 0...1 {
                            let mx = fx + (side == 0 ? 0.5 : 0), my = fy + (side == 1 ? 0.5 : 0)
                            let mw = exp(-(mx * mx + my * my) / 10)
                            if let value = crossU[2 * b + side] { pu.append((mx, my, value, mw)) }
                            if let value = crossV[2 * b + side] { pv.append((mx, my, value, mw)) }
                        }
                    }
                }
                // The crossings to this pixel's left and above belong to those neighbours even when they
                // are outside the band.
                for (b, side, mx, my) in [(y * w + x - 1, 0, Float(-0.5), Float(0)), (y * w + x - w, 1, Float(0), Float(-0.5))]
                where b >= 0 && third[b] == none {
                    if let value = crossV[2 * b + side] { pv.append((mx, my, value, 1)) }
                }
                var planeU = SIMD3<Float>(u0, 0, 0), planeV = SIMD3<Float>(v0, 0, 0)
                if pu.count >= 8, let a = fit(pu) { planeU = a }
                if pv.count >= 8, let b = fit(pv) { planeV = b }
                // A fit may not carry the pixel out of its own step by much.
                planeU.x = min(max(planeU.x, Float(t0) / 3 - 0.2), Float(t0 + 1) / 3 + 0.2)
                planeV.x = min(max(planeV.x, Float(r0) - 0.3), Float(r0 + 1) + 0.3)
                let i = 4 * (y * w + x)
                map.u[i] = planeU.x; map.u[i + 1] = planeU.y; map.u[i + 2] = planeU.z; map.u[i + 3] = 1
                map.v[i] = planeV.x; map.v[i + 1] = planeV.y; map.v[i + 2] = planeV.z
            }
        }
        for _ in 0..<3 {
            var next = map
            for y in 0..<h {
                for x in 0..<w where map.u[4 * (y * w + x) + 3] == 0 {
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let xx = x + dx, yy = y + dy
                        guard xx >= 0, yy >= 0, xx < w, yy < h, map.u[4 * (yy * w + xx) + 3] == 1 else { continue }
                        let from = 4 * (yy * w + xx), to = 4 * (y * w + x)
                        // The neighbour's plane, re-centred on this pixel.
                        next.u[to] = map.u[from] - map.u[from + 1] * Float(dx) - map.u[from + 2] * Float(dy)
                        next.u[to + 1] = map.u[from + 1]; next.u[to + 2] = map.u[from + 2]; next.u[to + 3] = 1
                        next.v[to] = map.v[from] - map.v[from + 1] * Float(dx) - map.v[from + 2] * Float(dy)
                        next.v[to + 1] = map.v[from + 1]; next.v[to + 2] = map.v[from + 2]
                        break
                    }
                }
            }
            map = next
        }
        return map
    }
}

/// The mountain scroller (part 9, `FOREST/READ2.PAS` and `ROUTINES.ASM`, Trug): "ANOTHER WAY TO SCROLL"
/// flows over the hills behind a tree's leaves.
///
/// - No font and no text string: the text is one picture, 640 columns by 31 rows of values 0...7. A window
///   of it, 237 columns wide, is laid over the hills through three position tables: for each window cell
///   the screen pixels it lands on. A pixel shows background + cell, where a cell is the text's value + 128
///   (0 where there is no text): the hills' colours 0...31 have copies "with text on" at 128...159.
/// - One table is drawn per refresh (1, 2, 3, 1, ...); after table 3 the window moves one text column. The
///   three tables share no pixel, each holding the pixels a third of a column further on, so the text
///   creeps in thirds of a column although the window moves in whole ones.
/// - The window starts with text columns 0...132 at its columns 104...236. When the text runs out its last
///   column (inked: the final L's bar) keeps coming in, a streak that follows the text off.
/// - Colours: the leaves fade in alone (64 refreshes: every colour but 0...31 and 128...159 rises one level
///   a refresh). In the demo the part then waits for "music plus" ≥ 0. The hills and the text fade in
///   during the first 127 scroll refreshes (a level every second refresh; it stops at 62 of 63, because the
///   loop never sets the finished palette). On "music plus" = −11 everything fades to black, a level a
///   refresh (65 refreshes).
///
/// Step pairing (as the jelly logo): what the program set up before its n-th wait shows on step n − 1.
/// So step 0 is black, step s (1...64) shows the leaves at level s − 1, and scroll draw j shows on step
/// 65 + j (plus however long the music wait took).
/// On its own: no wait; the fade-out starts on the same scroll draw as in the demo; then it starts again
/// (2,036 steps).
struct MountainScrollerModel {
    static let width = 320, height = 200
    static let fadeInSteps = 64
    static let hillFadeDraws = 127
    static let fadeOutSteps = 65
    /// On its own: the scroll draw on which the fade-out starts. In Play Demo "music plus" = −11 arrives
    /// on this very draw (checked by the self-test against the script).
    static let standaloneFadeDraw = 1906
    static let startCue = 0, endCue = -11
    /// Where text column 0 sits in the window at the start.
    static let firstColumn = 104

    let data: MountainData
    /// The text with 128 added where it is inked (READ2.PAS's `fbuf`).
    private let inked: [UInt8]

    // State.
    /// Steps since the scene began.
    private(set) var step = 0
    /// The step that shows scroll draw 0 (nil until the scroll has been started).
    private(set) var scrollStart: Int?
    /// The step that shows fade-out level 0.
    private(set) var fadeStart: Int?
    /// The 1993 screen: colour numbers, kept from draw to draw.
    private(set) var screen: [UInt8]
    /// The window on the text, 237 x 31 (READ2.PAS's `font`).
    private var window: [UInt8]
    private var nextColumn = 133
    private var table = 0
    /// Scroll draws done.
    private(set) var draws = 0
    /// Inside Play Demo: the music's "music plus", given before each step. nil on its own.
    var musicPlus: Int?

    init(data: MountainData) {
        self.data = data
        inked = data.text.map { $0 == 0 ? 0 : $0 &+ 128 }
        screen = data.background
        window = []
        reset()
    }

    mutating func reset() {
        step = 0
        scrollStart = nil
        fadeStart = nil
        screen = data.background
        window = [UInt8](repeating: 0, count: MountainData.columns * MountainData.rows)
        for row in 0..<MountainData.rows {
            for column in 0..<133 {
                window[row * MountainData.columns + Self.firstColumn + column] = inked[row * MountainData.textWidth + column]
            }
        }
        nextColumn = 133
        table = 0
        draws = 0
    }

    mutating func tick() {
        if let fade = fadeStart, step >= fade + Self.fadeOutSteps - 1 {
            if musicPlus == nil { reset() }   // in the demo: stays black until the next part
            return
        }
        step += 1
        guard let start = scrollStart else {
            // The leaves are in; the scroll starts once the music allows (a loop with no wait in it), and
            // its first draw shows a step later.
            if step >= Self.fadeInSteps, musicPlus.map({ $0 >= Self.startCue }) ?? true { scrollStart = step + 1 }
            return
        }
        guard step >= start else { return }
        let draw = step - start
        // The fade-out is looked for only in the main loop, after the 127 draws of the hills' fade.
        if fadeStart == nil, draw >= Self.hillFadeDraws,
           musicPlus.map({ $0 == Self.endCue }) ?? (draw >= Self.standaloneFadeDraw) {
            fadeStart = step
        }
        drawTable()
    }

    /// `scr`: one table through `putrouts`; after the third, the window moves a column.
    private mutating func drawTable() {
        let t = data.tables[table]
        let background = data.background
        for cell in 0..<(MountainData.columns * MountainData.rows) {
            let from = t.starts[cell], to = t.starts[cell + 1]
            if from == to { continue }
            let value = window[cell]
            for i in from..<to {
                let address = Int(t.addresses[i])
                screen[address] = background[address] &+ value
            }
        }
        draws += 1
        if table == 2 {
            // move(font[1], font[0], ...): every row's first column falls off, the next row's comes in at
            // its end and is overwritten by the new column at once.
            window.removeFirst()
            window.append(0)
            for row in 0..<MountainData.rows {
                window[row * MountainData.columns + MountainData.columns - 1] = inked[row * MountainData.textWidth + nextColumn]
            }
            if nextColumn < MountainData.textWidth - 1 { nextColumn += 1 }
            table = 0
        } else {
            table += 1
        }
    }

    /// The hills, and the hills with text on.
    static func isHill(_ colour: Int) -> Bool { colour < 32 || (128..<160).contains(colour) }

    /// The 256 colours showing now, VGA levels.
    var palette: [SIMD3<Int>] {
        if step == 0 { return [SIMD3<Int>](repeating: .zero, count: 256) }
        let draw = scrollStart.map { step - $0 } ?? -1
        return data.palette.enumerated().map { colour, target in
            if let fade = fadeStart { return pointwiseMax(target &- SIMD3(repeating: step - fade), .zero) }
            if Self.isHill(colour) {
                return draw <= 0 ? .zero : pointwiseMin(target, SIMD3(repeating: min((draw - 1) / 2, 62)))
            }
            return draw < 0 ? pointwiseMin(target, SIMD3(repeating: step - 1)) : target
        }
    }

    // MARK: The Modern look

    /// What the Modern look draws, `alpha` of a step on.
    struct ModernView {
        /// How far the leaves and the hills have faded in, and everything out: levels 0...63 (unrounded).
        var leaves: Float
        var hills: Float
        var fadeOut: Float
        /// How far the text has moved, in columns (the window's column c shows text column
        /// c − 104 + shift); nil before the scroll.
        var shift: Float?
    }

    func modernView(alpha: Float) -> ModernView {
        let now = Float(step) + alpha
        var view = ModernView(leaves: min(max(now - 1, 0), 63), hills: 0, fadeOut: 0, shift: nil)
        if let start = scrollStart, step >= start {
            let draw = now - Float(start)
            view.leaves = 63
            view.hills = min(max((draw - 1) / 2, 0), 63)
            // Draw j brings table j mod 3 up to date; the pixels of table k sit (2 − k)/3 of a column on.
            view.shift = (draw - 2) / 3
        }
        if let fade = fadeStart { view.fadeOut = min(now - Float(fade), 64) }
        return view
    }
}
