import Foundation

/// The state and rules of the hidden starfield, with no drawing code.
///
/// This follows Psi's original (DDSTARS/STARS.ASM in the Second Reality source, "Desert Dream Stars")
/// step for step. The trick in it: the stars are not drawn to the screen. They are drawn into a ring of
/// 64 small off-screen pictures, one picture per step, and the pictures are NEVER wiped. The screen just
/// shows the 64 pictures in turn, over and over. Every time round, each picture has gained the dots of
/// whichever stars were flying at that moment, so the 64-step film loop gets denser and denser while the
/// program only ever moves 512 (later 1024) stars per step.
struct StarfieldModel {
    /// The screen: EGA mode 0Dh (320 across, 16 colours) with line-doubling switched off, giving 400 lines.
    static let width = 320
    static let height = 400
    /// Each off-screen picture is 320x100. It fills the top half of the screen on every second line;
    /// an older picture, upside down, fills the bottom half.
    static let rows = 100
    static let pictureCount = 64
    static let starCount = 1024

    /// The original ran until the viewer left. This version stops adding stars here, plays the finished
    /// 64-step loop once more while fading out, and starts again. (See docs/scenes/starfield.md.)
    static let lastAddTick = 1984
    static let lengthInTicks = 2048
    /// The original's fade-in took 33 steps. The fade-out here is the same fade backwards.
    static let fadeSteps = 33

    /// The original's timetable, in steps.
    static let firstPartEnds = 900        // 512 stars are added up to here...
    static let secondPartStarts = 1200    // ...then nothing until here, then 1024 stars, each drawn twice
    static let restartRampAt = 1500       // the stars are switched off and let back in, 4 per step
    /// In the second part every dot is also put into the picture 17 places further round the ring.
    static let echoOffset = 17
    /// The bottom half of the screen shows the picture half-way round the ring.
    static let mirrorOffset = 32

    /// The original built these two tables when it started: "216 (or 288) divided by distance", as a
    /// fixed-point number. Distance is 150 + 4 * depth. They are not stored in any data file.
    static let scaleY: [Int] = (0..<256).map { ((108 << 16) / (150 + 4 * $0)) >> 1 }
    static let scaleX: [Int] = (0..<256).map { ((144 << 16) / (150 + 4 * $0)) >> 1 }

    /// The original's own random numbers: the well-known multiplier and increment of Microsoft C's
    /// `rand()`, but returning a different part of the product (bits 32-47 of the 64-bit result).
    struct Random {
        var seed: UInt32 = 0
        mutating func next() -> Int {
            let product = UInt64(0x343FD) * UInt64(seed)
            seed = UInt32(truncatingIfNeeded: product) &+ 0x269EC3
            return Int((product >> 32) & 0xFFFF)
        }
        /// A star coordinate, -512...511.
        mutating func coordinate() -> Int { (next() & 1023) - 512 }
    }

    struct Star {
        /// Depth, one byte: 255 is far, 0 is near. Drops by 2 a step; when it runs out the star is given
        /// a new random place and starts again from the far end.
        var depth: UInt8
        var x: Int
        var y: Int
        /// Which flight (below) this star is currently adding to, or -1.
        var flight: Int = -1
        /// Whether that flight has an echo twin (second part of the scene).
        var flightHasTwin = false
    }

    /// One unbroken run of a star being drawn, kept for the modern look only. The classic look needs just
    /// the pictures; the modern look needs to know where each dot came from so it can glide.
    /// A star in a flight is at depth `startDepth - 2 * (step - start)` for `start <= step < end`.
    struct Flight {
        var x: Float
        var y: Float
        var start: Float
        var startDepth: Float
        var end: Float
        // Padding so the graphics chip sees 8 numbers per flight.
        var unused0: Float = 0
        var unused1: Float = 0
        var unused2: Float = 0
    }
    static let openEnded: Float = 1e9

    private(set) var stars: [Star] = []
    /// The 64 pictures. One byte per pixel, 0...3 (the original kept two bit planes; this is the same thing).
    private(set) var pictures = [[UInt8]](repeating: [UInt8](repeating: 0, count: width * rows), count: pictureCount)
    private(set) var flights: [Flight] = []
    private(set) var ticks = 0
    /// The picture being drawn into and shown.
    private(set) var page = 0
    /// Stars are let in gradually: star number i is drawn only once `count - i >= limit`.
    private var limit = 512
    private var random = Random()
    private var wasAdding = false

    init() {
        // Depths count down through the list; places are random.
        for i in 0..<Self.starCount {
            let depth = UInt8((1023 - i) & 255)
            let x = random.coordinate()
            let y = random.coordinate()
            stars.append(Star(depth: depth, x: x, y: y))
        }
        // The original ran 100 steps before showing anything, so the first picture is not empty.
        for step in -99...0 {
            page = (page + 1) & 63
            addStars(count: 512, echo: false, limitStep: 1, step: step)
        }
    }

    mutating func reset() {
        self = StarfieldModel()
    }

    mutating func tick() {
        ticks += 1
        if ticks == Self.lengthInTicks {
            reset()
            return
        }
        if ticks == Self.restartRampAt { limit = Self.starCount }
        page = (page + 1) & 63

        let adding: Bool
        if ticks > Self.lastAddTick {
            adding = false
        } else if ticks > Self.secondPartStarts {
            addStars(count: Self.starCount, echo: true, limitStep: 4, step: ticks)
            adding = true
        } else if ticks <= Self.firstPartEnds {
            addStars(count: 512, echo: false, limitStep: 1, step: ticks)
            adding = true
        } else {
            adding = false
        }
        if wasAdding && !adding { closeAllFlights(at: ticks) }
        wasAdding = adding
    }

    /// The original's `staradd` (and `staradd2` when `echo` is on): move every star one step nearer and
    /// add its dot to the current picture.
    private mutating func addStars(count: Int, echo: Bool, limitStep: Int, step: Int) {
        if limit != 0 { limit -= limitStep }
        let echoPage = (page + Self.echoOffset) & 63
        for i in 0..<count {
            let oldDepth = Int(stars[i].depth)
            stars[i].depth = UInt8((oldDepth - 2) & 255)
            let newDepth = oldDepth - 2
            if oldDepth < 2 {
                // Flown past: a new random place. Not drawn this step.
                closeFlight(of: i, at: step)
                stars[i].x = random.coordinate()
                stars[i].y = random.coordinate()
                continue
            }
            // Only stars above the horizon are ever drawn.
            if count - i < limit || stars[i].y >= 0 {
                closeFlight(of: i, at: step)
                continue
            }
            if stars[i].flight < 0 {
                stars[i].flight = flights.count
                let flight = Flight(x: Float(stars[i].x), y: Float(stars[i].y), start: Float(step),
                                    startDepth: Float(newDepth), end: Self.openEnded)
                flights.append(flight)
                stars[i].flightHasTwin = echo
                if echo {
                    var twin = flight
                    twin.start += Float(Self.echoOffset)
                    flights.append(twin)
                }
            }

            // Perspective, with the original's whole-number rounding. Position and colour both use the
            // depth from AFTER this step: the assembly does `movzx bx,[si]` / `sub bl,2` and then uses BX
            // to look up the tables. (Until the 2026-11-14 review this used the depth from before the
            // step for the position, which put every dot where the original drew it one step earlier.)
            let row = ((stars[i].y * Self.scaleY[newDepth]) >> 14) + 100
            guard row >= 0, row <= 99 else { continue }
            let column = ((stars[i].x * Self.scaleX[newDepth]) >> 14) + 160
            guard column >= 0, column <= 319 else { continue }
            let colour = Self.colour(depth: newDepth)
            let offset = row * Self.width + column
            // Dots are OR-ed in, so two stars on one pixel combine their colour numbers.
            pictures[page][offset] |= colour
            if echo { pictures[echoPage][offset] |= colour }
        }
    }

    /// Far stars are colour 1 (dim), middle ones colour 2, near ones colour 3 (bright).
    static func colour(depth: Int) -> UInt8 {
        depth >= 180 ? 1 : depth >= 110 ? 2 : 3
    }

    private mutating func closeFlight(of star: Int, at step: Int) {
        let index = stars[star].flight
        guard index >= 0 else { return }
        stars[star].flight = -1
        flights[index].end = Float(step)
        // An echo twin sits right after its flight and runs 17 steps later.
        if stars[star].flightHasTwin {
            flights[index + 1].end = Float(step + Self.echoOffset)
        }
    }

    private mutating func closeAllFlights(at step: Int) {
        for i in stars.indices { closeFlight(of: i, at: step) }
    }

    // MARK: - The 1993 picture

    /// How far the fade has got, 0...33, for the picture now on screen.
    static func fadeLevel(tick: Int) -> Int {
        guard tick > 0 else { return 0 }
        // The original's palette ran one step ahead of the picture it was showing.
        return max(0, min(tick + 1, fadeSteps, lengthInTicks - tick))
    }

    /// The palette (0...63 per channel) at a fade level. Colours 1-3 are three shades of blue-grey.
    static func palette(level: Int) -> [SIMD3<Int>] {
        let brightness = min(level * 8, 255)
        let full: [SIMD3<Int>] = [
            SIMD3(0, 0, 0),
            SIMD3(25 * 70 / 100, 31 * 70 / 100, 38 * 70 / 100),
            SIMD3(45 * 56 / 100, 58 * 56 / 100, 69 * 56 / 100),
            SIMD3(67 * 64 / 100, 84 * 64 / 100, 99 * 64 / 100)
        ]
        return full.map { colour in
            SIMD3((colour.x * brightness) >> 8, (colour.y * brightness) >> 8, (colour.z * brightness) >> 8)
        }
    }

    func classicPalette() -> [SIMD3<Int>] {
        Self.palette(level: Self.fadeLevel(tick: ticks))
    }

    /// The picture being added to this step (320x100, values 0...3).
    var currentPicture: [UInt8] { pictures[page] }

    /// The 320x400 screen as colour numbers: the current picture on the even lines of the top half, and
    /// the picture from half-way round the ring, upside down, on the even lines of the bottom half.
    /// Odd lines are never written and stay black.
    func classicIndices() -> [UInt8] {
        var screen = [UInt8](repeating: 0, count: Self.width * Self.height)
        guard ticks > 0 else { return screen }
        let top = pictures[page]
        let bottom = pictures[(page + Self.mirrorOffset) & 63]
        for row in 0..<Self.rows {
            let source = row * Self.width
            let topLine = (2 * row) * Self.width
            let bottomLine = (200 + 2 * (99 - row)) * Self.width
            for x in 0..<Self.width {
                screen[topLine + x] = top[source + x]
                screen[bottomLine + x] = bottom[source + x]
            }
        }
        return screen
    }
}
