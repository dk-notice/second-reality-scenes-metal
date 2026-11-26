import Foundation
import simd

/// The state and rules of the Plasma scene, with no drawing code.
///
/// Based on Wildfire's original (PLZPART/PLZ.C, ASMYT.ASM and COPPER.ASM in the Second Reality source).
/// The 1993 version worked like this:
///
///  - The screen was a 320x400 mode (twice the usual number of lines). The plasma is a band 280 lines
///    tall in the middle of it.
///  - A plasma value is the sum of two lookups in a wavy sine table, where the position looked up is
///    itself bent by two more wavy sine tables. Four numbers ("parameters") slide the lookups along a
///    little every frame, which is what makes the plasma flow.
///  - Only 84 values are worked out per line: each is 4 screen pixels wide. But TWO plasmas with different
///    parameters ("K" and "L") are drawn, interleaved like the squares of a chessboard, and the picture is
///    nudged by one line on alternate frames so the squares swap. At 70 frames per second the eye sees
///    the two mixed.
///  - Colours come from a 256-colour palette. Three times in the scene the plasma band falls off the
///    bottom of the screen; after the first two it reappears at once with a new palette fading up from
///    black, and the third was the part's end (here, on its own, it leads back to the first palette).
///    PLZ.C as published has a fourth section and palette; the released program never reaches them.
///
/// Inside Play Demo it follows the part as RELEASED (PLZ.C 68-95, COPPER.ASM `do_drop`, and the unpacked
/// PLZPART.EXE where it differs): the whole screen is white (left by the rotozoomer, and set again by
/// `init_plz`) until "music plus" >= 0; the music's frame counter starts there, and the n-th step after
/// the cue is the part's n-th refresh. The first palette fades DOWN from white over 127 refreshes
/// (`cop_drop` starts at 128), colour 0 and so the borders with it. The band falls when the frame
/// counter, which counts MUSIC TICKS (52 a second), passes 723, 1491 and 1875 (`timetable`). The released
/// program leaves its loop when `curpal` is 4 (PLZ.C as published says 5), so the THIRD fall is the end:
/// three palettes show, and the screen stays empty until the script moves on. No second run.
struct PlasmaModel {
    // MARK: - Tables

    /// The original's own value of two pi (PLZ.C, `DPII`). Using exactly this constant, not the
    /// processor's more precise pi, is what makes the tables below come out identical to the original files.
    private static let twoPi: Double = 3.1415926535 * 2.0

    /// PSINI.INC: 16384 entries, a big sine wave with two small faster ones riding on it. Values 2...125.
    static let psini: [UInt8] = (0..<16384).map { (a: Int) -> UInt8 in
        let t: Double = Double(a) * twoPi / 4096
        let value: Double = sin(t) * 55 + sin(t * 6) * 5 + sin(t * 21) * 4 + 64
        return UInt8(Int(value))
    }

    /// LSINI16.INC: 8192 entries, a similar wave, 16 times as tall. Used to bend the first lookup.
    static let lsini16: [UInt16] = (0..<8192).map { (a: Int) -> UInt16 in
        let t: Double = Double(a) * twoPi / 4096
        let value: Double = (sin(t) * 55 + sin(t * 4) * 5 + sin(t * 17) * 3 + 64) * 16
        return UInt16(Int(value))
    }

    /// LSINI4.INC: 8192 entries, 8 times as tall. Used to bend the second lookup.
    ///
    /// Two entries (3072 and 7168) are set by hand. There the true value is exactly 24, a whole number;
    /// the 1993 maths library landed a hair under it and the file says 23. Every other entry follows
    /// the formula.
    static let lsini4: [UInt16] = {
        var table: [UInt16] = (0..<8192).map { (a: Int) -> UInt16 in
            let t: Double = Double(a) * twoPi / 4096
            let value: Double = (sin(t) * 55 + sin(t * 5) * 8 + sin(t * 15) * 2 + 64) * 8
            return UInt16(Int(value))
        }
        table[3072] = 23
        table[7168] = 23
        return table
    }()

    /// PTAU.INC: a smooth 0...63 brightness ramp (half a cosine wave), used to build the palettes.
    static let ptau: [Int] = [0] + (1...128).map { (a: Int) -> Int in
        Int(cos(Double(a) * twoPi / 128 + 3.1415926535) * 31 + 32)
    }

    /// The three palettes the plasma shows, in order: 256 colours each, red/green/blue 0...63.
    /// (The original built two more: "RB-white", red through white to blue, which PLZ.C's fourth section
    /// would have shown but the released program never reaches, and one only the plasma cube used.)
    static let palettes: [[SIMD3<Int>]] = {
        let p = ptau
        var redBlue = [SIMD3<Int>(0, 0, 0)]
        for a in 1..<64 { redBlue.append(SIMD3(p[a], 0, 0)) }
        for a in 0..<64 { redBlue.append(SIMD3(p[63 - a], 0, 0)) }
        for a in 0..<64 { redBlue.append(SIMD3(0, 0, p[a])) }
        for a in 0..<64 { redBlue.append(SIMD3(p[a], 0, p[63 - a])) }

        var rainbow = [SIMD3<Int>(0, 0, 0)]
        for a in 1..<64 { rainbow.append(SIMD3(p[a], 0, 0)) }
        for a in 0..<64 { rainbow.append(SIMD3(p[63 - a], 0, p[a])) }
        for a in 0..<64 { rainbow.append(SIMD3(0, p[a], p[63 - a])) }
        for a in 0..<64 { rainbow.append(SIMD3(p[a], p[63], p[a])) }

        var grey = [SIMD3<Int>(0, 0, 0)]
        for _ in 1..<64 { grey.append(SIMD3(0, 0, 0)) }
        for a in 0..<64 { grey.append(SIMD3(repeating: p[a] / 2)) }
        for a in 0..<64 { grey.append(SIMD3(repeating: p[63 - a] / 2)) }
        for _ in 0..<64 { grey.append(SIMD3(0, 0, 0)) }

        return [redBlue, rainbow, grey]
    }()

    /// Starting parameters for each of the three sections: L plasma, then K plasma (PLZ.C `inittable`).
    static let startParameters: [(l: SIMD4<Int32>, k: SIMD4<Int32>)] = [
        (SIMD4(1000, 2000, 3000, 4000), SIMD4(3500, 2300, 3900, 3670)),
        (SIMD4(1000, 2000, 4000, 4000), SIMD4(1500, 2300, 3900, 1670)),
        (SIMD4(3500, 1000, 3000, 1000), SIMD4(3500, 3300, 2900, 2670))
    ]
    /// How far each parameter moves per step (COPPER.ASM `moveplz`).
    static let kSpeed = SIMD4<Int32>(-3, -2, 1, 2)
    static let lSpeed = SIMD4<Int32>(-1, -2, 2, 3)

    /// The music frame counter values (ticks) after which the band falls (PLZ.C `timetable`: 64 rows x
    /// 6 ticks x 2, 4 and 5 patterns, less 45). The last is the released part's end.
    static let timetable = [723, 1491, 1875]
    /// On its own (no music): the steps at which the band starts to fall, and which section follows.
    /// The timetable's ticks counted as the player counted them, 48700/65536 of a tick a step from 0
    /// (`DemoSequencer.speedAdjust`): the step the count first passes the entry, plus one because the band
    /// moves a refresh after the program notices. That is steps 976, 2009 and 2526; inside Play Demo,
    /// where the count is part-way to its next tick at the cue, each comes a step sooner. The last entry
    /// is the original's ending; here it leads back to section 0.
    static let drops: [(step: Int, nextSection: Int)] = timetable.enumerated().map { index, limit in
        let rate = DemoSequencer.speedAdjust(.second)
        return (((limit + 1) * 65_536 + rate - 1) / rate + 1, (index + 1) % timetable.count)
    }
    /// The scene repeats after this many steps (2,588, about 37 seconds): the last fall's 62 steps on.
    static let lengthInTicks = (drops.last?.step ?? 0) + 62

    static let canvasWidth = 320
    static let canvasHeight = 400
    /// Lines of plasma drawn.
    static let bandHeight = 280
    /// Number of steps a new palette takes to fade up from black.
    static let fadeSteps = 31

    /// Where the band's top edge is while it falls, by step of the fall (COPPER.ASM `dtau`): 60 plus
    /// a distance that grows with the square of time, as a falling object's does.
    static func lineCompare(fallStep: Int) -> Int {
        fallStep * fallStep / 4 * 43 / 128 + 60
    }

    // MARK: - State

    private(set) var ticks = 0
    private(set) var section = 0
    private(set) var k = startParameters[0].k
    private(set) var l = startParameters[0].l
    /// The original's `cop_drop` counter: 0 = plasma flowing normally, 1...64 = band falling,
    /// 65 = hidden while the parameters are reset, 66...96 = new palette fading in.
    private(set) var dropCounter = 64
    /// The palette being faded: each colour part as a 16-bit number whose top 8 bits are the VGA value.
    private var fadePalette = [UInt16](repeating: 0, count: 768)
    /// The palette the video card currently has (0...63 per part). It lags `fadePalette` by one step,
    /// because the original sent it to the card at the start of the following frame.
    private(set) var shownPalette = [UInt8](repeating: 0, count: 768)
    private var paletteWaiting = false

    /// Inside Play Demo: the music, given before each step. nil on its own.
    private(set) var music: DemoMusicState?
    /// Inside Play Demo: whether the start cue has been met, and whether the last fall is over.
    private(set) var cued = false
    private(set) var ended = false
    private var ending = false
    /// Inside Play Demo: falls begun so far, and whether the counter had passed the next `timetable`
    /// entry on the step before this one (the program sees it on one refresh; the band has moved on the next).
    private var fallsBegun = 0
    private var fallDue = false
    static let startCue = 0
    /// The original's `cop_drop` at the start of the part: 129...255 fade the first palette down from white,
    /// to one level above it (see `update`).
    static let firstFade = 128

    mutating func reset() { self = PlasmaModel() }

    /// Play Demo's music, before each step; `justShown` on the step the scene appears.
    mutating func update(music: DemoMusicState, justShown: Bool) {
        if justShown {
            self = PlasmaModel()
            // Every colour white: the rotozoomer's last palette, and `init_plz`'s first.
            shownPalette = [UInt8](repeating: 63, count: 768)
            // The fade's own memory (`fadepal`) starts as ZEROS in the released PLZPART.EXE, not at white:
            // the first step takes every level below zero, the card keeps only the low six bits (white
            // again), and the fade ends one level above the palette (0 shows as 1, 62 as 63).
            fadePalette = [UInt16](repeating: 0, count: 768)
            dropCounter = Self.firstFade
            // The script tests the cue on the very step it shows the scene.
            cued = music.plus >= Self.startCue
        }
        self.music = music
    }

    mutating func tick() {
        if let music {
            guard cued else {
                if music.plus >= Self.startCue { cued = true }
                return
            }
            if ended { return }
            ticks += 1
        } else {
            ticks += 1
            if ticks == Self.lengthInTicks {
                reset()
                return
            }
        }

        if paletteWaiting {
            shownPalette = fadePalette.map { Self.cardLevel($0) }
            paletteWaiting = false
        }

        k = (k &+ Self.kSpeed) & 4095
        l = (l &+ Self.lSpeed) & 4095

        // The main program notices it is time: on its own at fixed steps, inside Play Demo by the music.
        var fall: (nextSection: Int, last: Bool)?
        if let music {
            if fallDue {
                fallsBegun += 1
                fall = (fallsBegun, fallsBegun == Self.timetable.count)   // the last fall is the end
            }
            // (From the second step after the cue: the script sets the counter to 0 on the cue step,
            // after the scene has read it.)
            fallDue = ticks >= 2 && fallsBegun < Self.timetable.count && music.ticks > Self.timetable[fallsBegun]
        } else if let drop = Self.drops.first(where: { $0.step == ticks }) {
            fall = (drop.nextSection, false)
        }
        if let fall {
            // Clear the fade and start the fall.
            for i in 0..<768 { fadePalette[i] &= 0x00FF }
            dropCounter = 1
            if fall.last { ending = true } else { section = fall.nextSection }
        }

        guard dropCounter != 0 else { return }
        dropCounter += 1
        if dropCounter <= 64 {
            return                      // falling; `fields` works out where the band is
        }
        if dropCounter > Self.firstFade {
            // The part's first fade (Play Demo only): 127 refreshes down from white.
            if dropCounter >= 256 {
                dropCounter = 0
                return
            }
            paletteWaiting = true
            let target = Self.palettes[0]
            for i in 0..<256 {
                for part in 0..<3 {
                    fadePalette[i * 3 + part] &+= UInt16(truncatingIfNeeded: (target[i][part] - 63) * 2)
                }
            }
            return
        }
        if ending && dropCounter == 65 {
            ended = true                // hidden (`fields`), and it stays so
            return
        }
        if dropCounter > 64 + 32 {
            dropCounter = 0             // fade finished
            return
        }
        paletteWaiting = true
        if dropCounter == 65 {
            k = Self.startParameters[section].k
            l = Self.startParameters[section].l
        } else {
            let target = Self.palettes[section]
            for i in 0..<256 {
                for part in 0..<3 {
                    fadePalette[i * 3 + part] &+= UInt16(Self.fadeIncrement(section: section, value: target[i][part]))
                }
            }
        }
    }

    /// What the video card shows for a fade value: its top byte, of which the card keeps six bits.
    static func cardLevel(_ value: UInt16) -> UInt8 { UInt8(value >> 8) & 63 }

    /// How much one fade step adds, in 1/256ths of a VGA level.
    ///
    /// The original added value x 8 for 31 steps, which stops at 31/32 of full brightness. Sections 1
    /// and 2 do exactly that. Section 0 in the original faded down from white instead and ended on the exact
    /// palette, so here it gets the smallest increment that reaches the exact value in 31 steps from black.
    private static func fadeIncrement(section: Int, value: Int) -> Int {
        section == 0 ? (value * 256 + fadeSteps - 1) / fadeSteps : value * 8
    }

    // MARK: - The 1993 look

    /// One of the two alternating frames ("fields") the original showed.
    struct Field {
        /// Screen line of the band's first row.
        var top: Int
        /// How many pixels the picture is shifted left.
        var pan: Int
    }

    /// The two fields for the current state. Normally the video card was told to start the band at line
    /// 60 with no sideways shift on one frame, and at line 61 with a 2-pixel shift on the next. While the
    /// band falls or a palette fades in, both frames use the same line (the shift still alternates).
    ///
    /// Why 60 goes with "no shift": `pompota` (run during the screen's retrace, COPPER.ASM `copper2`)
    /// picks the line and the shift together, as 60 with 2 pixels or 61 with none. The line number goes
    /// to the card at once and applies to the frame about to be drawn. The shift is only stored; it is
    /// sent to the card by `copper1`, which the demo's interrupt server (DIS/DISINT.ASM, MAIN/COPPER.ASM
    /// `copper_end`) runs just before the NEXT retrace. So each frame is drawn with its own line and the
    /// previous frame's shift.
    var fields: [Field] {
        let fixedLine: Int?
        switch dropCounter {
        case 0: fixedLine = nil
        case 1...64: fixedLine = Self.lineCompare(fallStep: dropCounter)
        case 65: fixedLine = 400                 // below the last screen line: nothing shows
        default: fixedLine = 60
        }
        // The band begins on the line after the one the card was given.
        return [Field(top: (fixedLine ?? 60) + 1, pan: 0), Field(top: (fixedLine ?? 61) + 1, pan: 2)]
    }

    /// The plasma value (a palette number) for one 4-pixel-wide column of one band row.
    /// This is `plzline` from ASMYT.ASM: two lookups in `psini`, each bent by another table.
    static func value(column c: Int, row y: Int, _ p: SIMD4<Int32>) -> Int {
        let bend1 = Int(lsini16[y + Int(p.y) + 4 * (80 - c)])
        let first = Int(psini[c * 8 + bend1 + Int(p.x)])
        let bend2 = Int(lsini4[y + Int(p.w) + 16 * c])
        let second = Int(psini[2 * y + bend2 + Int(p.z) + 4 * (80 - c)])
        return (first + second) & 255
    }

    /// The palette number at one screen pixel in one field. 0 (black) outside the band.
    func colourNumber(x: Int, line: Int, field: Field) -> Int {
        let row = line - field.top
        guard row >= 0, row < Self.bandHeight else { return 0 }
        let memoryX = x + field.pan
        // Chessboard: which of the two plasmas owns this pixel.
        let parameters = (memoryX + row) & 1 == 1 ? k : l
        return Self.value(column: memoryX >> 2, row: row, parameters)
    }

    /// The 1993 picture for the current state: red, green, blue bytes for each of 320x400 pixels.
    /// It is the average of the two fields, which is what a monitor's glow and the eye made of them.
    func classicReferenceFrame() -> [UInt8] {
        let bothFields = fields
        var result = [UInt8]()
        result.reserveCapacity(Self.canvasWidth * Self.canvasHeight * 3)
        for line in 0..<Self.canvasHeight {
            for x in 0..<Self.canvasWidth {
                let a = colourNumber(x: x, line: line, field: bothFields[0]) * 3
                let b = colourNumber(x: x, line: line, field: bothFields[1]) * 3
                for part in 0..<3 {
                    let sum = Int(shownPalette[a + part]) + Int(shownPalette[b + part])
                    result.append(UInt8((Double(sum) * 255 / 126).rounded()))
                }
            }
        }
        return result
    }

    // MARK: - The modern look

    struct ModernParameters {
        var k: SIMD4<Float>
        var l: SIMD4<Float>
        /// 256 colours, each part 0...1.
        var palette: [SIMD4<Float>]
        /// Canvas line of the band's top edge.
        var top: Float
        var hidden: Bool
    }

    /// The state for the modern look, `alpha` (0..<1) of the way towards the next step.
    func modernParameters(alpha: Float) -> ModernParameters {
        // The palette the next step will show, so the fade can glide.
        let next: [UInt8] = paletteWaiting ? fadePalette.map { Self.cardLevel($0) } : shownPalette
        var palette = [SIMD4<Float>]()
        palette.reserveCapacity(256)
        for i in 0..<256 {
            let now = SIMD3<Float>(Float(shownPalette[i * 3]), Float(shownPalette[i * 3 + 1]), Float(shownPalette[i * 3 + 2]))
            let then = SIMD3<Float>(Float(next[i * 3]), Float(next[i * 3 + 1]), Float(next[i * 3 + 2]))
            palette.append(SIMD4((now + (then - now) * alpha) / 63, 1))
        }

        // The band rests midway between its two alternating positions (lines 61 and 62),
        // and falls by the same square-of-time rule, without the whole-number rounding.
        var top: Float = 61.5
        if (1..<64).contains(dropCounter) {
            let t = Float(dropCounter) + alpha
            top += t * t * 43 / 512
        } else if dropCounter == 0, music != nil ? fallDue : Self.drops.contains(where: { $0.step == ticks + 1 }) {
            // The fall begins on the next step, where the counter goes straight from 0 to 2 (the
            // main program sets 1 and the refresh routine adds 1 in the same frame). Glide towards
            // that, or the band would sit still and then hop a third of a line.
            let t = 2 * alpha
            top += t * t * 43 / 512
        }
        return ModernParameters(
            k: SIMD4<Float>(k) + SIMD4<Float>(Self.kSpeed) * alpha,
            l: SIMD4<Float>(l) + SIMD4<Float>(Self.lSpeed) * alpha,
            palette: palette,
            top: top,
            hidden: dropCounter == 64 || dropCounter == 65)
    }
}
