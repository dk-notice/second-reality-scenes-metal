import simd

/// What the original's techno part showed between the interference and the techno bars, inside Play
/// Demo only (`TECHNO/KOE.C` 224-316): the interference's flash to white, white until the music's cue,
/// then on each of four beats one quarter of the screen wiped to black from the top, falling faster and
/// faster, while the white fades to a blue-grey; between beats a flash back to white. The bars start out
/// of the last white.
///
/// The screen then held one picture of colour numbers: colour 15 everywhere (`memset(vram,255,8000)`),
/// colour 0 where the wipe has passed. Column b is bytes b x 10 ... b x 10 + 9 of each 40-byte row, so
/// pixels 80b ... 80b + 79. Only the palette's two colours change otherwise.
///
/// No drawing here. The steps follow the same waits as Play Demo's script (`DemoScript.steps`, the
/// techno part) and are run the same way, with the music the scene is told each step.
struct TechnoLeadIn {
    enum Op: Equatable {
        /// The interference's flash to white (KOE.C 224-228), the script's `.frames(5)`.
        case flash
        /// `while(dis_musplus() < -3)` (KOE.C 275).
        case untilPlus
        /// `while((dis_musrow() & 7) != 7)` (KOE.C 277-281, 303-307): busy waits, no refresh passes.
        case untilBeat
        /// Column b wiped: 21 passes, each ending with `flash(a)` and its wait (KOE.C 288-301).
        case column(Int)
        /// `flash(32)`, `flash(64)`, `flash(192)`, `flash(256)` after each column (KOE.C 309-313).
        case flashBack(Int)
    }

    /// The order of the waits, as the script has them.
    static let ops: [Op] = [.flash, .untilPlus, .untilBeat]
        + (0..<4).flatMap { [Op.column($0), .untilBeat, .flashBack($0)] }

    static func steps(_ op: Op) -> Int? {
        switch op {
        case .flash: return 5
        case .column: return 21
        case .flashBack: return 4
        case .untilPlus, .untilBeat: return nil
        }
    }

    /// The interference's four flash mixes; the script's fifth step stays white.
    static let flashMixes = InterferenceModel.flashMixes + [256]
    /// The flash back to white between columns.
    static let flashBackMixes = [32, 64, 192, 256]
    /// The palette the wipe fades to (KOE.C 268-273: colour a is a x 6/2, a x 7/2, a x 8/2): colour 0
    /// black, colour 15 this blue-grey.
    static let light = SIMD3<Int>(15 * 6 / 2, 15 * 7 / 2, 15 * 8 / 2)
    static let dark = SIMD3<Int>(0, 0, 0)

    /// Rows wiped in a column after pass j (0...20): `zy`, which grows by 1, 2, 3 ... (at most the screen).
    static func wipedRows(pass j: Int) -> Int { min((j + 1) * (j + 2) / 2, 200) }
    /// The palette mix towards white after pass j: `a` = 256, 224 ... 32, then 0.
    static func wipeMix(pass j: Int) -> Int { max(256 - 32 * j, 0) }

    /// What the screen shows on one step.
    struct Screen: Equatable {
        /// Still the interference's picture (during its flash), with its palette mixed this far to white.
        var interference: Bool
        /// Columns wiped completely, and rows wiped of the next one.
        var columns: Int
        var rows: Int
        /// How far (of 256) the palette is mixed towards white.
        var mix: Int

        /// Colours 0 and 15 as the card held them (VGA levels 0...63), as `flash` worked them out.
        var colours: (dark: SIMD3<Int>, light: SIMD3<Int>) {
            (InterferenceModel.flashed(TechnoLeadIn.dark, mix: mix), InterferenceModel.flashed(TechnoLeadIn.light, mix: mix))
        }

        /// Whether pixel (x, y) shows colour 0.
        func isDark(x: Int, y: Int) -> Bool {
            let column = x / 80
            return column < columns || (column == columns && y < rows)
        }
    }

    private(set) var index = 0
    private(set) var spent = 0
    /// The screen on the step before (the Modern look glides from it).
    private(set) var previous: Screen?

    var finished: Bool { index >= Self.ops.count }

    /// One step, as the script's sequencer takes it: every wait already met is passed, then the step is
    /// spent on the first one that is not.
    mutating func step(music: DemoMusicState) {
        previous = screen
        while index < Self.ops.count {
            let op = Self.ops[index]
            if let count = Self.steps(op) {
                if spent < count { spent += 1; return }
            } else {
                let met = op == .untilPlus ? music.plus >= -3 : music.row & 7 == 7
                if !met { spent += 1; return }
            }
            index += 1
            spent = 0
        }
    }

    var screen: Screen {
        guard index < Self.ops.count else { return Screen(interference: false, columns: 4, rows: 0, mix: 256) }
        switch Self.ops[index] {
        case .flash:
            return Screen(interference: true, columns: 0, rows: 0, mix: Self.flashMixes[max(spent, 1) - 1])
        case .untilPlus:
            return Screen(interference: false, columns: 0, rows: 0, mix: 256)
        case .untilBeat:
            // Before the first column: still white. After column b: that column wiped, the palette at 0.
            let done = Self.ops[..<index].filter { if case .column = $0 { return true } else { return false } }.count
            return Screen(interference: false, columns: done, rows: 0, mix: done == 0 ? 256 : 0)
        case .column(let b):
            let j = max(spent, 1) - 1
            return Screen(interference: false, columns: b, rows: Self.wipedRows(pass: j), mix: Self.wipeMix(pass: j))
        case .flashBack(let b):
            return Screen(interference: false, columns: b + 1, rows: 0, mix: Self.flashBackMixes[max(spent, 1) - 1])
        }
    }

    /// The 1993 picture (VGA levels, red, green, blue for each of 320 x 200 pixels), when not the
    /// interference's.
    func classicFrame() -> [UInt8] {
        let s = screen, (dark, light) = s.colours
        var frame = [UInt8]()
        frame.reserveCapacity(320 * 200 * 3)
        for y in 0..<200 {
            for x in 0..<320 {
                let c = s.isDark(x: x, y: y) ? dark : light
                frame += [UInt8(c.x), UInt8(c.y), UInt8(c.z)]
            }
        }
        return frame
    }
}
