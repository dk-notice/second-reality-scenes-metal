import Foundation
import simd

/// The state and rules of the techno bars, with no graphics-chip code.
///
/// Based on Psi's original (TECHNO/KOE.C `doit1`, `doit2`, `doit3`). Eleven parallel bars spin about
/// the middle of the screen while their thickness bounces.
///
/// The trails are the clever part. A 16-colour VGA mode stores each pixel as four separate on/off
/// layers. Each frame, the original drew the bars as a one-colour picture into just ONE layer of one
/// of 8 screen pages, then showed that page. The other three layers of that page still held the bars
/// from 8, 16 and 24 frames earlier. The colour table simply made a pixel brighter the more layers
/// had it switched on. So ghost trails and overlap shading cost nothing: they were old frames nobody
/// had erased.
struct TechnoBarsModel {
    static let width = 320
    static let height = 200

    /// The three sections of the original, in steps (1/70 s each).
    enum Section {
        /// Slow steady spin, thickness bouncing gently. 6 seconds.
        case one
        /// Spin keeps accelerating; bars shrink to nothing and bounce back. 12 seconds.
        case two
        /// The same, with the whole set of bars circling the screen; finally it slides off to the right.
        case three
    }
    static let sectionOneTicks = 70 * 6
    static let sectionTwoTicks = 70 * 12
    static let sectionThreeTicks = 70 * 14
    /// Section three starts sliding off when this many of its steps are left.
    static let slideWhenTicksLeft = 333

    /// The original flashed the bars on every 8th row of the music. Without the music, the beat is
    /// recreated from the song's settings (speed 3, tempo 130): one row lasts this many steps.
    static let musicRowInTicks = 3.0 * 2.5 / 130.0 * 70.0

    /// Inside Play Demo: the music's real row, given each step before `tick` (then the flash comes on
    /// the real beat, as in the original). nil when the scene runs on its own: the row is estimated.
    var musicRow: Int?

    /// What a frame's bars looked like, kept for the modern look to glide between.
    struct BarState {
        /// Angle, in 1/1024 turns. Keeps counting up rather than wrapping.
        var rotation: Double
        /// Half the thickness of a bar, in pixels. Bars and gaps are the same width.
        var halfThickness: Double
        var centre: SIMD2<Double>
        /// How far the picture has slid to the right (section three's exit).
        var slide: Double
        /// True for the first step of a section. The bars jump there (new angle, new thickness), so the
        /// modern look must not glide into this step from the one before.
        var startsSection = false
    }

    private(set) var section = Section.one
    private var passes = 0              // loop passes done in this section
    private var rot = 45
    private var rota = 10
    private var rot2 = 0
    private var vm = 50
    private var vma = 0
    private var xpos = 320
    private var xposa = 0

    /// 8 screen pages, one byte per pixel; the low 4 bits are the four layers.
    private var pages = [[UInt8]](repeating: [UInt8](repeating: 0, count: width * height), count: 8)
    private var pageIndex = 0
    private var layerBit: UInt8 = 1
    private var shownPage = 0
    private var shownSlide = 0

    private var sceneTicks = 0
    private var lastRow = -1
    private var flash = 0               // counts down from 15 after each beat
    private(set) var shownFlash = 0

    private(set) var history: [BarState] = []
    private var raster = BarRasteriser()
    /// The next step drawn is the first of its section (see `BarState.startsSection`).
    private var startsSection = true
    /// Section three has slid off: the next step is the black one before the scene starts again.
    private var endsAfterThisStep = false

    mutating func reset() {
        self = TechnoBarsModel()
    }

    // MARK: - One step

    /// One pass of the original's loop. A page drawn in one pass only appeared on screen at the screen
    /// refresh inside the NEXT pass. Just before that refresh, the original set the slide; just after it,
    /// it set the flash colours. So each page was seen with the next pass's slide and flash. The end of
    /// this function does that next-pass work early, so the page and the values it was seen with stay together.
    mutating func tick() {
        if endsAfterThisStep {
            // Slid right off: the original went on to the next picture. We show one black step and start again.
            reset()
            return
        }

        var centre = SIMD2(160, 100)
        var thicknessScale = vm                 // section one uses vm directly

        switch section {
        case .one:
            break
        case .two:
            thicknessScale = vm / 64
        case .three:
            thicknessScale = vm / 64
            if rot2 < 32 {
                centre = SIMD2(SinTable.sin(rot2) * rot2 / 8 + 160, SinTable.cos(rot2) * rot2 / 8 + 100)
            } else {
                centre = SIMD2(SinTable.sin(rot2) / 4 + 160, SinTable.cos(rot2) / 4 + 100)
            }
            rot2 += 17
        }

        // Draw this frame's bars as a one-colour picture.
        raster.clear()
        for quad in Self.bars(rot: rot, thicknessScale: thicknessScale, centre: centre) {
            raster.add(quad)
        }
        let picture = raster.filled()

        var drawn = BarState(
            rotation: Double(rot),
            halfThickness: 0.16 * (section == .one ? Double(vm) : Double(vm) / 64),
            centre: SIMD2(Double(centre.x), Double(centre.y)),
            slide: 0,
            startsSection: startsSection)
        startsSection = false

        // Move on: spin, and bounce the thickness as if under gravity.
        switch section {
        case .one:
            rot += 2
            vm += vma
            if vm < 25 {
                vm -= vma
                vma = -vma
            }
            vma -= 1
        case .two, .three:
            rot += rota / 10
            vm += vma
            if vm < 0 {
                vm -= vma
                vma = -vma
            }
            vma -= 1
            rota += 1
        }

        // Put the picture into one layer of the current page, and show that page.
        let clearMask = ~layerBit
        for i in picture.indices {
            pages[pageIndex][i] = (pages[pageIndex][i] & clearMask) | (picture[i] != 0 ? layerBit : 0)
        }
        shownPage = pageIndex

        // Next page; after a full round of pages, next layer. Section three uses every other page.
        pageIndex = (pageIndex + (section == .three ? 2 : 1)) & 7
        if pageIndex == 0 {
            layerBit = layerBit == 8 ? 1 : layerBit << 1
        }

        passes += 1

        // The start of the next pass, up to the screen refresh that shows this page.
        // Section three's slide (KOE.C `doit3`): `passes` now counts the next pass.
        if section == .three && Self.sectionThreeTicks - passes < Self.slideWhenTicksLeft {
            let before = xpos
            xpos -= xposa / 4
            if xpos < 0 { xpos = 0 } else { xposa += 1 }
            if xpos == 0 {
                // The original stopped here without showing a slide of 0, so this page keeps the last one.
                xpos = before
                endsAfterThisStep = true
            }
        }
        shownSlide = 320 - xpos
        // The beat flash, set just after the refresh (KOE.C `waitborder`).
        sceneTicks += 1
        let row = musicRow ?? Int(Double(sceneTicks) / Self.musicRowInTicks)
        if row != lastRow {
            lastRow = row
            if row & 7 == 7 { flash = 15 }
        }
        shownFlash = flash
        if flash > 0 { flash -= 1 }

        drawn.slide = Double(shownSlide)
        history.append(drawn)
        if history.count > 64 { history.removeFirst(history.count - 64) }

        switch section {
        case .one where passes == Self.sectionOneTicks:
            // The pages are NOT cleared here, so section one's last frames linger as ghosts.
            section = .two
            passes = 0
            rot = 50; rota = 10; vm = 100 * 64; vma = 0
            pageIndex = 0; layerBit = 1
            startsSection = true
        case .two where passes == Self.sectionTwoTicks:
            section = .three
            passes = 0
            rot = 45; rota = 10; rot2 = 0; vm = 100 * 64; vma = 0
            xpos = 320; xposa = 0
            pageIndex = 0; layerBit = 1
            for i in pages.indices {
                pages[i] = [UInt8](repeating: 0, count: Self.width * Self.height)
            }
            history.removeAll()
            startsSection = true
        default:
            break
        }
    }

    /// The four corners of each of the 11 bars, using the original's whole-number arithmetic.
    static func bars(rot: Int, thicknessScale: Int, centre: SIMD2<Int>) -> [[BarRasteriser.Point]] {
        // h runs along a bar (long enough to leave the screen); v runs across it.
        // The 6/5 stretches x because 320x200 pixels were taller than wide. Units are 1/16 pixel.
        let hx = SinTable.sin(rot) * 16 * 6 / 5
        let hy = SinTable.sin(rot + 256) * 16
        let vx = (SinTable.sin(rot + 256) * 6 / 5) * thicknessScale / 100
        let vy = SinTable.sin(rot + 512) * thicknessScale / 100

        var result: [[BarRasteriser.Point]] = []
        for c in stride(from: -10, through: 10, by: 2) {
            let cx = vx * c * 2
            let cy = vy * c * 2
            result.append([
                .init(x: (-hx - vx + cx) / 16 + centre.x, y: (-hy - vy + cy) / 16 + centre.y),
                .init(x: (-hx + vx + cx) / 16 + centre.x, y: (-hy + vy + cy) / 16 + centre.y),
                .init(x: (+hx + vx + cx) / 16 + centre.x, y: (+hy + vy + cy) / 16 + centre.y),
                .init(x: (+hx - vx + cx) / 16 + centre.x, y: (+hy - vy + cy) / 16 + centre.y),
            ])
        }
        return result
    }

    // MARK: - Colours (VGA scale, 0...63 per channel)

    /// Colour by how many layers are on at a pixel: 0 (black) up to 4 (brightest).
    static let levelColours: [SIMD3<Int>] = [
        SIMD3(0, 0, 0),
        SIMD3(38 * 64 / 111, 33 * 64 / 111, 44 * 64 / 111),
        SIMD3(52 * 64 / 111, 45 * 64 / 111, 58 * 64 / 111),
        SIMD3(67 * 64 / 111, 61 * 64 / 111, 73 * 64 / 111),
        SIMD3(83 * 64 / 111, 77 * 64 / 111, 89 * 64 / 111),
    ]

    /// The five level colours brightened by a beat flash (0 = none, 15 = just hit).
    static func flashedLevels(flash: Int) -> [SIMD3<Int>] {
        levelColours.map { colour in
            SIMD3(min(colour.x * (10 + flash * 9 / 9) / 10, 63),
                  min(colour.y * (10 + flash * 7 / 9) / 10, 63),
                  min(colour.z * (10 + flash * 5 / 9) / 10, 63))
        }
    }

    /// The 16 colours the video card holds for the frame on screen.
    func classicPalette() -> [SIMD3<Int>] {
        let levels = Self.flashedLevels(flash: shownFlash)
        return (0..<16).map { levels[$0.nonzeroBitCount] }
    }

    /// The frame on screen as colour numbers (0...15), one byte per pixel.
    func classicIndices() -> [UInt8] {
        let page = pages[shownPage]
        if shownSlide == 0 { return page }
        // Section three's exit: the picture has slid right, leaving black behind it.
        var shifted = [UInt8](repeating: 0, count: page.count)
        for y in 0..<Self.height {
            for x in shownSlide..<Self.width {
                shifted[y * Self.width + x] = page[y * Self.width + x - shownSlide]
            }
        }
        return shifted
    }

    // MARK: - The modern look

    struct ModernParameters {
        /// The current bars plus three ghosts. `weight` is 0 for a ghost that does not exist yet.
        var snapshots: [(state: BarState, weight: Float)]
        /// Five colours, 0...1 per channel, for 0 to 4 overlapping sets of bars.
        var levels: [SIMD3<Float>]
        var slide: Float
    }

    func modernParameters(alpha: Double) -> ModernParameters {
        // Ghosts are 8 steps apart, or 4 in section three, as the page flipping made them.
        let gap = section == .three ? 4 : 8
        let newest = history.count - 1
        var snapshots: [(state: BarState, weight: Float)] = []
        var slide = 0.0
        for ghost in 0..<4 {
            let later = newest - ghost * gap
            guard later >= 0 else {
                snapshots.append((BarState(rotation: 0, halfThickness: 0, centre: SIMD2(0, 0), slide: 0), 0))
                continue
            }
            // Glide between two neighbouring steps. A step that begins a section is held still instead:
            // the bars jump there, and gliding across the jump would sweep them through angles never drawn.
            // The very first step has nothing before it, so it is held still too.
            let b = history[later]
            let a = later > 0 && !b.startsSection ? history[later - 1] : b
            let state = BarState(
                rotation: a.rotation + (b.rotation - a.rotation) * alpha,
                halfThickness: a.halfThickness + (b.halfThickness - a.halfThickness) * alpha,
                centre: a.centre + (b.centre - a.centre) * alpha,
                slide: a.slide + (b.slide - a.slide) * alpha)
            if ghost == 0 { slide = state.slide }
            snapshots.append((state, 1))
        }

        let flash = max(0, Double(shownFlash) - (shownFlash > 0 ? alpha : 0))
        let levels = Self.levelColours.map { colour -> SIMD3<Float> in
            let c = SIMD3<Double>(colour)
            let scaled = SIMD3(c.x * (10 + flash) / 10, c.y * (10 + flash * 7 / 9) / 10, c.z * (10 + flash * 5 / 9) / 10)
            return SIMD3<Float>(simd.min(scaled, SIMD3<Double>(repeating: 63)) / 63)
        }
        return ModernParameters(snapshots: snapshots, levels: levels, slide: Float(slide))
    }
}
