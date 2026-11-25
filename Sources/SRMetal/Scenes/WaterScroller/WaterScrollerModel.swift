import Foundation
import simd

/// The water scroller's original files (`Data/Water`, see its README): the background with its colour
/// numbers, the sword picture with the part's palette, and the three position tables.
struct WaterData {
    static let folder = DataFolder.find(resource: "Water", devPath: "Data/Water", marker: "WAT1.DAT")
    static let columns = 158, rows = 34, swordWidth = 400
    static let fileNames = ["WAT1.DAT", "WAT2.DAT", "WAT3.DAT", "BKG.CLX", "MIEKKA.SCI"]
    /// Connected regions of fewer table pixels than this are the tiny reflections (see `ScrollTables.smoothMap`).
    static let smallRegion = 1000

    /// The part's 256 colours, VGA levels 0...63, as 768 bytes: the SWORD picture's palette (the
    /// background file's own differs in 192...255, the sword's colours, and is not used).
    let palette: [UInt8]
    /// 320x200 colour numbers (0...191).
    let background: [UInt8]
    /// 400x34 colour numbers, 0 = nothing.
    let sword: [UInt8]
    let tables: [ScrollTables.Table]

    static func bytes(_ name: String) -> [UInt8]? {
        guard let url = folder?.appendingPathComponent(name), let data = try? Data(contentsOf: url) else { return nil }
        return [UInt8](data)
    }

    /// nil if a file is missing or is not what the part expects.
    static func load() -> WaterData? {
        guard let bkg = bytes("BKG.CLX"), bkg.count == 778 + 64000,
              let miekka = bytes("MIEKKA.SCI"), miekka.count >= 778 + swordWidth * rows else { return nil }
        var tables: [ScrollTables.Table] = []
        for n in 1...3 {
            guard let d = bytes("WAT\(n).DAT"), let table = ScrollTables.parse(d, columns: columns, rows: rows) else { return nil }
            tables.append(table)
        }
        return WaterData(palette: vgaLevels(miekka[10..<778]), background: Array(bkg[778...]),
                         sword: Array(miekka[778..<(778 + swordWidth * rows)]), tables: tables)
    }

    func colour(_ number: Int) -> SIMD3<Int> {
        SIMD3(Int(palette[3 * number]), Int(palette[3 * number + 1]), Int(palette[3 * number + 2]))
    }

    /// The Modern look's map (see `ScrollTables.smoothMap`): u is the window column (0...158), v the
    /// sword's row (0...34).
    func smoothMap() -> ScrollTables.SmoothMap {
        ScrollTables(columns: Self.columns, rows: Self.rows, tables: tables).smoothMap(smallRegion: Self.smallRegion)
    }
}

/// The water scroller (part 13, `WATER/DEMO.PAS` and `ROUTINES.ASM`, Trug): a sword slides over ray-traced
/// water and is mirrored in two chrome balls. The same technique as the mountain scroller.
///
/// - Nothing is ray-traced while it runs, and there is no text: the "scroller" is one picture of a sword,
///   400 columns by 34 rows of colour numbers. A window of it, 158 columns wide, is laid over the picture
///   through three position tables: for each window cell the screen pixels it lands on (on the water and
///   in each reflection). A pixel shows the cell's colour, or the background again where the cell is empty.
/// - One table is drawn per refresh (1, 2, 3, 1, ...); after table 3 the window moves one column. The
///   window starts empty; the sword comes in at the far end. Its last 40 columns are empty, and the
///   column counter stops at 390, so nothing smears.
/// - Colours: one fade-in for the whole picture, 127 refreshes, a level every second one. Both fades step
///   through four bytes per colour instead of three, so each colour's RED moves twice a round: the
///   picture comes in pinkish and goes out bluish. (And the fade-in loop never sets its finished
///   palette, so green and blue stop at 62 of 63 until the fade-out sets them.)
/// - In the demo the part first waits for "music plus" ≥ 0 (black), fades in, then shows the still picture
///   until the music reaches row 16 of its next section (about 7.4 s); the scroll runs until "music
///   plus" = −11, then everything fades out over 65 refreshes while the sword keeps moving.
///
/// Step pairing (as the mountain scroller): step 0 is black; the fade's pass y shows on step y + 1;
/// scroll draw k shows on the step after the one that met the cue, + k.
/// On its own: no black wait; the still picture is held as long as in the demo and the fade-out starts
/// on the same scroll draw as in the demo; then it starts again (2,044 steps).
struct WaterScrollerModel {
    static let width = 320, height = 200
    static let fadeInSteps = 127
    static let fadeOutSteps = 65
    /// On its own: the still steps between the fade-in and the scroll. In Play Demo the music takes
    /// exactly this long (checked by the self-test against the script).
    static let standaloneHold = 519
    /// On its own: the scroll draw on which the fade-out starts; in Play Demo "music plus" = −11 arrives
    /// on this very draw (checked the same way).
    static let standaloneFadeDraw = 1332
    static let startCue = 0, endCue = -11, sectionRow = 16
    static let lastColumn = 390

    let data: WaterData

    // State.
    /// Steps since the scene began.
    private(set) var step = 0
    /// The step that shows the fade-in's first pass (nil while waiting for the music).
    private(set) var fadeBegin: Int?
    /// The step that shows scroll draw 0 (nil until the scroll has been started).
    private(set) var scrollStart: Int?
    /// The step that shows the fade-out's first setting.
    private(set) var fadeStart: Int?
    /// The 1993 screen: colour numbers, kept from draw to draw.
    private(set) var screen: [UInt8]
    /// The 768 palette bytes as last given to the VGA card (0...63).
    private(set) var shown: [UInt8]
    /// DEMO.PAS's `pal`, the palette being faded (769 bytes, as declared), and `tmppal`, its target.
    private var working: [UInt8]
    private let target: [UInt8]
    /// The window on the sword, 158 x 34 and one byte more (DEMO.PAS's `fbuf`).
    private var window: [UInt8]
    private var nextColumn = 0
    private var table = 0
    private var notedSection = 0
    /// Inside Play Demo: the music, given before each step. nil on its own.
    private(set) var music: DemoMusicState?

    init(data: WaterData) {
        self.data = data
        target = data.palette + [0]
        screen = data.background
        shown = []
        working = []
        window = []
        reset()
    }

    mutating func reset() {
        step = 0
        fadeBegin = nil
        scrollStart = nil
        fadeStart = nil
        screen = data.background
        shown = [UInt8](repeating: 0, count: 768)
        working = [UInt8](repeating: 0, count: 769)
        window = [UInt8](repeating: 0, count: WaterData.columns * WaterData.rows + 1)
        nextColumn = 0
        table = 0
    }

    /// Play Demo's music, before each step; `justShown` on the step the scene appears.
    mutating func update(music: DemoMusicState, justShown: Bool) {
        self.music = music
        // The script tests its first cue on the very step it shows the scene.
        if justShown, music.plus >= Self.startCue { beginFade(at: 1) }
    }

    private mutating func beginFade(at step: Int) {
        fadeBegin = step
        notedSection = music?.order ?? 0
    }

    mutating func tick() {
        if let fade = fadeStart, step >= fade + Self.fadeOutSteps - 1 {
            if music == nil { reset() }   // in the demo: stays black until the next part
            return
        }
        step += 1
        if fadeBegin == nil {
            if let music {
                // The part's first loop: black until "music plus" ≥ 0; it notes the section playing.
                if music.plus >= Self.startCue { beginFade(at: step + 1) }
                return
            }
            fadeBegin = step
        }
        guard let begin = fadeBegin, step >= begin else { return }
        let pass = step - begin
        if pass < Self.fadeInSteps { fadeInPass(pass) }
        guard let start = scrollStart else {
            // After the fade-in: a loop with no refresh wait in it, until the music is in another section
            // at row 16 or later. The scroll's first draw shows a step later.
            guard pass >= Self.fadeInSteps - 1 else { return }
            let go = music.map { $0.order != notedSection && $0.row >= Self.sectionRow }
                ?? (pass >= Self.fadeInSteps - 1 + Self.standaloneHold)
            if go {
                scrollStart = step + 1
                table = 0
                nextColumn = 0
            }
            return
        }
        let draw = step - start
        if fadeStart == nil, music.map({ $0.plus == Self.endCue }) ?? (draw >= Self.standaloneFadeDraw) {
            fadeStart = step
        }
        drawTable(fading: fadeStart != nil)
    }

    /// One pass of the fade-in loop. On odd passes: every colour is set as it stands, then raised a level.
    /// `for pf := 0 to 3`: four bytes, so the next colour's red is raised too, before it is set.
    private mutating func fadeInPass(_ pass: Int) {
        if pass & 1 == 1 {
            for x in 0..<256 {
                for k in 0..<3 { shown[3 * x + k] = working[3 * x + k] }
                for pf in 0...3 where working[3 * x + pf] < target[3 * x + pf] { working[3 * x + pf] += 1 }
            }
        }
        putTable()   // the window is still empty: the background again
        table = table == 2 ? 0 : table + 1
    }

    /// `putrouts1`: every pixel of one table shows its cell, or the background where the cell is empty.
    private mutating func putTable() {
        let t = data.tables[table]
        let background = data.background
        for cell in 0..<(WaterData.columns * WaterData.rows) {
            let from = t.starts[cell], to = t.starts[cell + 1]
            if from == to { continue }
            let value = window[cell]
            for i in from..<to {
                let address = Int(t.addresses[i])
                screen[address] = value != 0 ? value : background[address]
            }
        }
    }

    /// One pass of the main loop: the fade-out's palette (if it has begun), one table, and after the third
    /// table the window moves a column.
    private mutating func drawTable(fading: Bool) {
        if fading {
            for x in 0..<256 {
                for k in 0..<3 { shown[3 * x + k] = working[3 * x + k] }
                for pf in 0...3 where working[3 * x + pf] > 0 { working[3 * x + pf] -= 1 }
            }
        }
        putTable()
        if table == 2 {
            table = 0
            // move(fbuf[1], fbuf, sizeof(fbuf)), then the new column at index 158 + row x 158: the NEXT
            // row's first cell (the last row's lands on the array's extra byte); the next move brings it to
            // its own row's last cell.
            window.removeFirst()
            window.append(0)
            for row in 0..<WaterData.rows {
                window[WaterData.columns + row * WaterData.columns] = data.sword[row * WaterData.swordWidth + nextColumn]
            }
            if nextColumn < Self.lastColumn { nextColumn += 1 }
        } else {
            table += 1
        }
    }

    /// The 256 colours showing now, VGA levels.
    var palette: [SIMD3<Int>] {
        var colours: [SIMD3<Int>] = []
        colours.reserveCapacity(256)
        for colour in 0..<256 {
            let at = 3 * colour
            colours.append(SIMD3<Int>(Int(shown[at]), Int(shown[at + 1]), Int(shown[at + 2])))
        }
        return colours
    }

    // MARK: The Modern look

    /// What the Modern look draws, `alpha` of a step on.
    struct ModernView {
        /// How far everything has faded in, and out: levels 0...63 (unrounded). Green and blue are held
        /// to `fadeIn` and lowered by `fadeOut`; red by twice as much, as in the original.
        var fadeIn: Float
        var fadeOut: Float
        /// How far the sword has moved, in columns (the window's column c shows sword column
        /// c − 159 + shift); nil before the scroll.
        var shift: Float?
    }

    func modernView(alpha: Float) -> ModernView {
        let now = Float(step) + alpha
        var view = ModernView(fadeIn: 0, fadeOut: 0, shift: nil)
        // Pass y sets level (y − 1)/2 on odd y.
        if let begin = fadeBegin { view.fadeIn = min(max((now - Float(begin) - 1) / 2, 0), 63) }
        // Draw j brings table j mod 3 up to date; the pixels of table k sit (2 − k)/3 of a column on.
        if let start = scrollStart, step >= start { view.shift = (now - Float(start) - 2) / 3 }
        if let fade = fadeStart { view.fadeOut = min(max(now - Float(fade), 0), 64) }
        return view
    }
}
