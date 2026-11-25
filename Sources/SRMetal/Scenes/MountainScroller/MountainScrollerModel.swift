import Foundation
import simd

/// The mountain scroller's original files (`Data/Mountain`, see its README): the background with its
/// colour numbers and palette, the text picture, and the three position tables.
struct MountainData {
    static let folder = DataFolder.find(resource: "Mountain", devPath: "Data/Mountain", marker: "POS1.DAT")
    static let columns = 237, rows = 31, textWidth = 640
    static let fileNames = ["POS1.DAT", "POS2.DAT", "POS3.DAT", "HILLBACK.CLX", "O2.SCI"]

    typealias Table = ScrollTables.Table

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
    /// (`bytes` reads a file by name: the data folder's, unless a check hands in damaged ones.)
    static func load(bytes: (String) -> [UInt8]? = MountainData.bytes) -> MountainData? {
        guard let hills = bytes("HILLBACK.CLX"), hills.count == 778 + 64000,
              let o2 = bytes("O2.SCI"), o2.count >= 778 + textWidth * rows,
              // The text's values are 0...7 (the scene multiplies them by 36 into a byte).
              o2[778..<(778 + textWidth * rows)].allSatisfy({ $0 < 8 }) else { return nil }
        var tables: [Table] = []
        for n in 1...3 {
            guard let d = bytes("POS\(n).DAT"), let table = ScrollTables.parse(d, columns: columns, rows: rows) else { return nil }
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

    /// The Modern look's map (see `ScrollTables.smoothMap`): u is the window column (0...237), v the text
    /// row (0...31).
    func smoothMap() -> ScrollTables.SmoothMap {
        ScrollTables(columns: Self.columns, rows: Self.rows, tables: tables).smoothMap()
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
