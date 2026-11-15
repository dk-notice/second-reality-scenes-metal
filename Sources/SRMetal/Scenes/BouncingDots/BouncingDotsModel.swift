import Foundation
import simd

/// The state and rules of the bouncing dots, with no graphics-chip code.
///
/// Based on Psi's original (DOTS/MAIN.C and DOTS/ASM.ASM). 512 dots fall under gravity onto a floor and
/// bounce, each with a shadow. Every step, one dot is taken out and dropped back in at a new place; the
/// rule for where changes through the scene (a spiral, a ring, a fountain, then a random cloud), which is
/// what makes the patterns. The view swings from side to side, and at the end gravity is switched off.
///
/// The classic look replays the original's drawing steps on the processor, including its way of rubbing
/// each dot out by copying the background back over its old position.
struct BouncingDotsModel {
    static let width = 320
    static let height = 200
    static let dotCount = 512

    /// The floor fades in from black for this many steps before any dots appear.
    static let fadeInTicks = 130
    /// Then the dots run for this many steps.
    static let mainTicks = 2450
    /// The picture starts fading out at this step of the main part. (The original flashed to white
    /// first, then faded to black. We skip the white and fade straight out, so the scene loops cleanly.)
    static let fadeOutStart = 2360

    // MARK: - 16-bit helpers

    /// The original ran on 16-bit whole numbers, which wrap round past 32767. This reproduces that.
    private static func wrap16(_ value: Int) -> Int {
        Int(Int16(truncatingIfNeeded: value))
    }

    /// The random numbers of the Microsoft C compiler the original was built with, so the "random"
    /// cloud of dots comes out the same as in 1993.
    private struct MicrosoftRandom {
        var state: UInt32 = 1
        mutating func next() -> Int {
            state = state &* 214013 &+ 2531011
            return Int((state >> 16) & 0x7FFF)
        }
    }

    // MARK: - State

    private var random = MicrosoftRandom()
    private var order = [Int](0..<dotCount)     // the shuffled order in which dots are re-dropped
    private var nextInOrder = 0

    private var x = [Int](repeating: 0, count: dotCount)
    private var y = [Int](repeating: 0, count: dotCount)
    private var z = [Int](repeating: 0, count: dotCount)
    private var fallSpeed = [Int](repeating: 0, count: dotCount)
    private var oldShadow = [Int](repeating: 0, count: dotCount)   // where each shadow was last drawn
    private var oldBall = [Int](repeating: 0, count: dotCount)     // where each dot was last drawn

    private(set) var ticks = 0
    private var frame = 0
    private var f = 0
    private var dropper = 22000
    private var gravity = 3
    private let bounce = 13             // sixteenths of the speed kept after a bounce
    private let floorLevel = 8105
    private var rot = 0
    private var rots = 0
    private var rota = -64

    /// Video memory and the saved background, one byte per pixel. Both have room past the end of the
    /// screen because the original's drawing ran slightly past the bottom row.
    private var screen: [UInt8]
    private let background: [UInt8]

    /// Depth-to-shade table: 0 (far, dim) ... 15 (near, bright).
    private static let shadeForDepth: [Int] = (0..<256).map { depth in
        var c = (depth - (43 + 20) / 2) * 3 / 4 + 8
        c = min(max(c, 0), 15)
        return 15 - c
    }

    /// For the modern look: where each dot is on screen, before whole-number rounding.
    struct Projected {
        var position = SIMD2<Double>(0, 0)
        var shadowY = 0.0
        var depth = 9000.0
        /// True when the dot should jump to this place rather than glide to it: it was re-dropped this
        /// step, or this is the first step with dots (there is no earlier place to glide from), or its
        /// 16-bit height wrapped round this step (from far above the screen to far below, or back).
        var jumped = true
    }
    private(set) var previous = [Projected](repeating: Projected(), count: dotCount)
    private(set) var current = [Projected](repeating: Projected(), count: dotCount)

    init() {
        // Shuffle the re-drop order, as the original did.
        for _ in 0..<500 {
            let b = random.next() % Self.dotCount
            let c = random.next() % Self.dotCount
            order.swapAt(b, c)
        }
        for i in 0..<Self.dotCount {
            y[i] = 2560 - dropper
        }
        // The original then shuffled the dots themselves. They are all identical at this point, so it
        // changes nothing, but it used up 1000 random numbers, and we must stay in step.
        for _ in 0..<1000 { _ = random.next() }

        // Background: black sky, and a floor that gets lighter towards the viewer (colours 64...163).
        var picture = [UInt8](repeating: 0, count: 65536 + 8)
        for row in 0..<100 {
            for column in 0..<Self.width {
                picture[(100 + row) * Self.width + column] = UInt8(row + 64)
            }
        }
        background = picture
        screen = picture
    }

    mutating func reset() {
        self = BouncingDotsModel()
    }

    // MARK: - One step

    mutating func tick() {
        ticks += 1
        guard ticks > Self.fadeInTicks else { return }

        frame += 1
        if frame == 500 { f = 0 }

        // Take the next dot in the shuffled order and drop it somewhere new.
        let i = order[nextInOrder]
        nextInOrder = (nextInOrder + 1) % Self.dotCount
        var dropped = true
        if frame < 500 {
            // A wandering figure high above, falling.
            x[i] = SinTable.sin(f * 11) * 40
            y[i] = SinTable.cos(f * 13) * 10 - dropper
            z[i] = SinTable.sin(f * 17) * 40
            fallSpeed[i] = 0
        } else if frame < 900 {
            // A ring, thrown upwards.
            x[i] = SinTable.cos(f * 15) * 55
            y[i] = dropper
            z[i] = SinTable.sin(f * 15) * 55
            fallSpeed[i] = -260
        } else if frame < 1700 {
            // A fountain from the floor whose width swells and shrinks.
            let radius = SinTable.sin(frame) / 8
            x[i] = SinTable.cos(f * 66) * radius
            y[i] = 8000
            z[i] = SinTable.sin(f * 66) * radius
            fallSpeed[i] = -300
        } else if frame < Self.fadeOutStart {
            // A random cloud. Gravity fades away, so the dots end up hanging in the air.
            x[i] = random.next() - 16384
            y[i] = 8000 - random.next() / 2
            z[i] = random.next() - 16384
            fallSpeed[i] = 0
            if frame > 1900 && frame & 31 == 0 && gravity > 0 { gravity -= 1 }
        } else {
            dropped = false
        }

        if dropper > 4000 { dropper -= 100 }
        let rotCos = SinTable.cos(rot) * 64
        let rotSin = SinTable.sin(rot) * 64
        rots += 2
        if frame > 1900 {
            // The view starts to spin, faster and faster.
            rot += rota / 64
            rota -= 1
        } else {
            // The view swings from side to side.
            rot = SinTable.sin(rots)
        }
        f += 1

        previous = current
        drawDots(rotSin: rotSin, rotCos: rotCos)
        if dropped { current[i].jumped = true }
        if frame == 1 {
            // The first step with dots: `previous` holds only placeholders, so nothing may glide from it.
            for dot in 0..<Self.dotCount { current[dot].jumped = true }
        }

        if frame == Self.mainTicks {
            reset()
        }
    }

    /// The original's `drawdots` routine: for every dot, work out where it is on screen, move its shadow,
    /// apply gravity and bouncing, and move the dot. Kept in the original's order and arithmetic.
    private mutating func drawDots(rotSin: Int, rotCos: Int) {
        func restore(_ position: Int, count: Int) {
            for k in 0..<count {
                let p = (position + k) & 0xFFFF
                screen[p] = background[p]
            }
        }
        func restoreBall(_ position: Int) {
            restore(position, count: 4)
            restore(position + 320, count: 4)
            restore(position + 640, count: 4)
        }

        for i in 0..<Self.dotCount {
            // Distance from the viewer. (The original took the top halves of two products separately;
            // kept that way so the rounding matches.)
            let depth = Self.wrap16(((z[i] * rotCos) >> 16) - ((x[i] * rotSin) >> 16) + 9000)
            let sideways = x[i] * rotCos + z[i] * rotSin
            let scaled = (sideways >> 8) + (sideways >> 11)
            let screenX = Self.wrap16(scaled / depth + 160)
            let shadowRow = Self.wrap16(0x80000 / depth + 100)

            current[i] = Projected(
                position: SIMD2(Double(scaled) / Double(depth) + 160, Double(y[i] * 64) / Double(depth) + 100),
                shadowY: Double(0x80000) / Double(depth) + 100,
                depth: Double(depth),
                jumped: false)

            // Off the side of the screen (or its shadow would be off the floor): rub it out and skip it.
            // Note that a skipped dot does not fall this step. That is how the original behaves.
            if screenX < 0 || screenX > 319 || shadowRow < 0 || shadowRow > 199 {
                let ball = oldBall[i]
                restoreBall(ball)
                let shadow = oldShadow[i]
                // A leftover value ended up stored as the old shadow position here in the original
                // (the last background bytes it had copied). Reproduced so later frames match.
                let p = (ball + 640) & 0xFFFF
                oldShadow[i] = Int(background[p]) | Int(background[p + 1]) << 8
                restore(shadow, count: 2)
                continue
            }

            // Shadow: put the background back where it was, draw it at the new place.
            let shadowPosition = shadowRow * Self.width + screenX
            restore(oldShadow[i], count: 2)
            screen[shadowPosition] = 87
            screen[shadowPosition + 1] = 87
            oldShadow[i] = shadowPosition

            // Gravity, and the bounce off the floor.
            fallSpeed[i] = Self.wrap16(fallSpeed[i] + gravity)
            let fallen = y[i] + fallSpeed[i]
            var newY = Self.wrap16(fallen)
            var wrapped = newY != fallen
            if newY >= floorLevel {
                fallSpeed[i] = Self.wrap16(-fallSpeed[i] * bounce) >> 4
                let bounced = newY + fallSpeed[i]
                newY = Self.wrap16(bounced)
                wrapped = wrapped || newY != bounced
            }
            y[i] = newY
            current[i].position.y = Double(newY * 64) / Double(depth) + 100
            // Once gravity is off, a rising dot keeps rising until its 16-bit height wraps round to far
            // below the floor (and usually straight back). Both places are off the screen, so the 1993
            // look never shows it; the modern look must not glide between them across the screen.
            if wrapped { current[i].jumped = true }

            let ballRow = Self.wrap16((newY << 6) / depth + 100)
            if ballRow < 0 || ballRow > 199 {
                restoreBall(oldBall[i])
                continue
            }
            let ballPosition = ballRow * Self.width + screenX
            restoreBall(oldBall[i])

            // The dot: 2 pixels, 4 pixels, 2 pixels, in a shade picked by distance.
            let shade = Self.shadeForDepth[((depth & 0xFFFF) >> 8) & 255]
            let edge = UInt8(2 + 4 * shade)
            let middle = UInt8(3 + 4 * shade)
            screen[ballPosition + 1] = edge
            screen[ballPosition + 2] = edge
            screen[ballPosition + 320] = edge
            screen[ballPosition + 321] = middle
            screen[ballPosition + 322] = middle
            screen[ballPosition + 323] = edge
            screen[ballPosition + 641] = edge
            screen[ballPosition + 642] = edge
            oldBall[i] = ballPosition
        }
    }

    // MARK: - Colours (VGA scale, 0...63 per channel)

    /// The three colours a dot is made of at a given shade (0...15): unused/black, edge, middle.
    static func dotColours(shade: Double) -> (edge: SIMD3<Double>, middle: SIMD3<Double>) {
        let brightness = 100 + shade * 9
        return (SIMD3(8, 40 * brightness / 256, 45 * brightness / 256),
                SIMD3(16, 55 * brightness / 256, 60 * brightness / 256))
    }

    /// Brightness of the floor at a given distance down from the horizon (0 = at the horizon).
    static func floorGrey(row: Double) -> Double {
        let c = 64 - 256 / (row + 4)
        return c * c / 64 / 4
    }

    static let shadowGrey = 11

    /// The full, un-faded 256-colour table.
    private static let basePalette: [SIMD3<Int>] = {
        var palette = [SIMD3<Int>](repeating: SIMD3(0, 0, 0), count: 256)
        let parts: [SIMD3<Int>] = [SIMD3(0, 0, 0), SIMD3(4, 25, 30), SIMD3(8, 40, 45), SIMD3(16, 55, 60)]
        for shade in 0..<16 {
            let brightness = 100 + shade * 9
            for part in 0..<4 {
                let c = parts[part]
                palette[shade * 4 + part] = SIMD3(c.x, c.y * brightness / 256, c.z * brightness / 256)
            }
        }
        for row in 0..<100 {
            var c = 64 - 256 / (row + 4)
            c = c * c / 64
            palette[64 + row] = SIMD3(c / 4, c / 4, c / 4)
        }
        palette[255] = SIMD3(31, 0, 15)
        return palette
    }()

    /// How much is being taken off every colour right now (0 = full brightness, 64 = black).
    /// Fades in at the start and out at the end.
    var fade: Double { Double(fadeLevel(at: Double(ticks))) }

    private func fadeLevel(at time: Double) -> Double {
        if time < Double(Self.fadeInTicks) {
            return 64 - (time / 2).rounded(.down)
        }
        let mainFrame = time - Double(Self.fadeInTicks)
        if mainFrame >= Double(Self.fadeOutStart) {
            return min(64, mainFrame - Double(Self.fadeOutStart))
        }
        return 0
    }

    /// The same, but changing smoothly between steps (for the modern look).
    func smoothFade(alpha: Double) -> Double {
        let time = Double(ticks) + alpha
        // Never below 0: the stepped fade reaches full brightness two steps before the fade-in ends.
        if time < Double(Self.fadeInTicks) { return max(0, 64 - time / 2) }
        return fadeLevel(at: time)
    }

    /// The 256 colours the video card holds for the frame on screen.
    func classicPalette() -> [SIMD3<Int>] {
        let level = Int(fade)
        return Self.basePalette.map { SIMD3(max($0.x - level, 0), max($0.y - level, 0), max($0.z - level, 0)) }
    }

    /// The frame on screen as colour numbers, one byte per pixel.
    func classicIndices() -> [UInt8] {
        Array(screen[0..<(Self.width * Self.height)])
    }
}
