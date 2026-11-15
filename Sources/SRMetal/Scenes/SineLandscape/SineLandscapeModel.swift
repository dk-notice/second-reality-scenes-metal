import Foundation
import simd

/// The rules of the 3D Sine Landscape (COMAN/MAIN.C, ASM.ASM and the generated THELOOP.INC, by Psi).
/// No graphics here.
///
/// The landscape's height at any spot is simply wave1[x] + wave2[y]: two one-dimensional wave tables
/// added together. The picture is made one screen column at a time: a ray is sent out from the eye
/// along the ground, and wherever the ground is higher than the ray, pixels are drawn up the column
/// until the ray clears it (the method of the helicopter game Comanche, hence the folder name).
///
/// The 1993 look replays the original's inner loop on the processor, with the original's 16- and
/// 32-bit arithmetic, into the same off-screen column buffer, which the original only partly cleared
/// between frames. The modern look only needs the camera, which `camera(alpha:)` provides.
struct SineLandscapeModel {
    static let width = 320
    static let height = 200
    /// Columns cast per frame. Each is shown two screen pixels wide.
    static let columns = 160
    /// The whole scene, then it loops: rise from below, fly, sink away.
    static let lengthInTicks = 2048
    /// The step after which the landscape starts sinking again.
    static let sinkStart = lengthInTicks - 130

    // MARK: Tables (all calculated; each reproduces the original's data exactly, see the self-test)

    /// WAVE.H, made by the original's KOE.C: one and a half sine waves that swell and then die away.
    static let waveSin: [Int] = (0..<1024).map { (x: Int) -> Int in
        let wave = Foundation.sin(Double(x) * 3.1415926535 * 3.0 / 1024.0)
        var swell = Double(x) / 700
        if swell > 1 { swell = 2 - swell }
        return Int(wave * swell * swell * 400.0)
    }

    /// W1DTA.BIN and W2DTA.BIN: the two 32768-entry height tables (the `CALCW12` code in MAIN.C).
    /// The first has a little random roughness mixed in, from Microsoft C's `rand()` starting at seed 1.
    static let waves: (first: [Int16], second: [Int16]) = {
        var first = [Int16](repeating: 0, count: 32768)
        var second = [Int16](repeating: 0, count: 32768)
        var seed: UInt32 = 1
        for u in 0..<32768 {
            seed = seed &* 214_013 &+ 2_531_011
            let random = Int((seed >> 16) & 0x7FFF)
            let a = u & 255
            var j = waveSin[((u * 1024 * 7) >> 15) & 1023] / 8
            j += waveSin[((u * 1024 * 3) >> 15) & 1023] / 7 + (random & 7) * a / 256
            first[u] = Int16(j * 5 / 9)
            j = waveSin[((u * 1024 * 5) >> 15) & 1023] / 5
            j += waveSin[((u * 1024 * 2) >> 15) & 1023] / 6
            second[u] = Int16(j * 7 / 9)
        }
        return (first, second)
    }()

    /// One step of a ray away from the eye. The original had no loop here: a small program (DOLOOP.C)
    /// wrote out the machine code for all 128 steps one after another, each with its own constants.
    struct RayStep {
        /// Added to the ground height: 240 below the eye, plus a ripple that depends on distance.
        var terrainAdd: Int16
        /// Added to the height to get the colour; far ground is a little darker.
        var colourAdd: Int16
        /// How much the ray rises for each pixel drawn at this distance (integer part in the low
        /// 16 bits, fraction in the high 16 bits: the original's "flipped" fixed-point layout).
        var rise: UInt32
        /// The far half of the ray moves two units per step.
        var double: Bool
    }

    static let raySteps: [RayStep] = {
        var steps: [RayStep] = []
        var j = 0
        while j < 192 {
            let ripple = Int(16.0 * Foundation.sin(Double(j) * 3.1415926535 * 2.0 * 3.0 / 192.0))
            let double = j >= 64
            steps.append(RayStep(
                terrainAdd: Int16(ripple - 240),
                // The shipped DOLOOP.C says 120 here; the generated code that was actually built says 140.
                colourAdd: Int16(140 - j / 8),
                rise: flipped(Int32(j * 2560)),
                double: double))
            j += double ? 2 : 1
        }
        return steps
    }()

    /// A 16.16 fixed-point number with its two halves swapped, as the original kept them.
    static func flipped(_ value: Int32) -> UInt32 {
        let bits = UInt32(bitPattern: value)
        return (bits << 16) | (bits >> 16)
    }

    /// Slope of the ray for the bottom pixel of a column, and the change for each pixel higher.
    private static let firstRayDirection = flipped(-(200 - 70) * 2560)
    private static let slopePerPixel = flipped(2560)
    private static let slopePerThreePixels = flipped(3 * 2560)

    /// The palette, 0...63 per channel, built as MAIN.C builds it. Only colours 0...127 are ever drawn.
    static let palette: [SIMD3<Int>] = {
        var p = [Int](repeating: 0, count: 768)
        for a in 0..<256 {
            let uc = (223 - a * 22 / 26) * 3
            var b = (230 - a) / 4 + SinTable.sin(a * 4) / 32
            p[uc + 1] = min(max(b, 0), 63)
            p[uc + 2] = min((255 - a) / 3, 63)
            b = 40 - min(abs(a - 220), 40)
            p[uc] = b / 3
        }
        for i in 0..<(768 - 16 * 3) { p[i] = min(p[i] * 9 / 6, 63) }
        for a in 0..<24 {
            let uc = (255 - a) * 3
            p[uc] = max(a - 4, 0) / 2
            p[uc + 1] = 0
            p[uc + 2] = 0
        }
        // (The original then filled colours 240...255 from memory beyond a 16-byte array, the remains
        // of a dropped background picture. Those colours are never drawn, so that step is left out.)
        return (0..<256).map { SIMD3(p[$0 * 3], p[$0 * 3 + 1], p[$0 * 3 + 2]) }
    }()

    // MARK: State

    private(set) var ticks = 0
    /// How many lines the picture is pushed down: 160 (out of sight) at the start, 0 when fully risen.
    private(set) var startRise = 160
    private var rot = 0
    private var rot2 = 0
    /// Position over the landscape. 16-bit in the original, so it wraps: the landscape repeats.
    private var xwav: Int16 = 0
    private var ywav: Int16 = 0
    /// The original's off-screen column buffer: a 64K block used as 160 bytes per line. Columns are
    /// stored even ones first, then odd ones, ready to be copied to the VGA's bit planes.
    private var columnBuffer = [UInt8](repeating: 0, count: 65536)
    /// The screen as colour numbers, as last copied from the column buffer.
    private var screen = [UInt8](repeating: 0, count: width * height)

    /// What the modern look needs to know about one frame.
    struct Camera {
        /// Position in table units (not wrapped, so two cameras can be blended).
        var position: SIMD2<Double>
        /// Heading, in 1024ths of a turn.
        var heading: Double
        var startRise: Double
    }
    private var camera = Camera(position: .zero, heading: 0, startRise: 160)
    private var previousCamera = Camera(position: .zero, heading: 0, startRise: 160)
    private var travelled = SIMD2<Double>(0, 0)

    mutating func reset() { self = SineLandscapeModel() }

    /// One frame of the original's main loop.
    mutating func tick() {
        ticks += 1
        if ticks >= Self.lengthInTicks {
            // Everything is out of sight by now, so starting again cannot be seen.
            reset()
            return
        }

        if ticks > Self.sinkStart {
            if startRise < 160 { startRise += 1 }
        } else if startRise > 0 {
            startRise -= 1
        }

        // The heading swings from side to side: `rot` is a running total of a sine wave.
        rot2 += 4
        rot += SinTable.sin(rot2) / 15
        let r = rot >> 3
        let rsin = SinTable.sin(r)
        let rcos = SinTable.cos(r)
        // The second axis is turned a further 177/1024 of a turn, so the ground grid is skewed.
        let rsin2 = SinTable.sin(r + 177)
        let rcos2 = SinTable.cos(r + 177)

        previousCamera = camera
        camera = Camera(position: travelled, heading: Double(rot) / 8, startRise: Double(startRise))

        let xw = xwav
        let yw = ywav
        for a in 0..<Self.columns {
            let x = a - 80
            let y = 160
            let xa = (x * rcos + y * rsin) / 256
            let ya = (y * rcos2 - x * rsin2) / 256
            castColumn(xw: xw, yw: yw, xa: xa, ya: ya, bottom: (a & 1) * 80 + (a >> 1) + 199 * 160)
            if a == 80 {
                // Fly forward along the middle column's ray.
                xwav = xwav &+ Int16(truncatingIfNeeded: xa * 4)
                ywav = ywav &+ Int16(truncatingIfNeeded: ya * 4)
                travelled += SIMD2(Double(xa * 4), Double(ya * 4))
            }
        }

        copyToScreen()
        // The original cleared only lines 68...97 of the column buffer. Lower lines are always drawn
        // over; higher ones would keep whatever a tall hill once left there.
        for i in (68 * 160)..<(98 * 160) { columnBuffer[i] = 0 }
    }

    /// `theloop`: sends one ray out and draws one screen column, bottom to top.
    /// Register names in comments are the original's.
    private mutating func castColumn(xw: Int16, yw: Int16, xa: Int, ya: Int, bottom: Int) {
        var si = UInt16(bitPattern: xw) & 0xFFFE
        var di = UInt16(bitPattern: yw) & 0xFFFE
        let xStep = UInt16(truncatingIfNeeded: xa) & 0xFFFE
        let yStep = UInt16(truncatingIfNeeded: ya) & 0xFFFE
        var bp = UInt16(bottom)
        var eax: UInt32 = 0                        // ray height
        var ecx = Self.firstRayDirection           // ray slope
        let first = Self.waves.first
        let second = Self.waves.second

        /// `add reg,value` then `adc reg16,extra`: adds two flipped numbers, carrying from the
        /// fraction (high half) round into the whole part (low half).
        func add(_ register: inout UInt32, _ value: UInt32, carryIn: Bool = false, extra: UInt16 = 0) {
            let sum = UInt64(register) + UInt64(value) + (carryIn ? 1 : 0)
            let low = UInt16(truncatingIfNeeded: sum) &+ extra &+ (sum > 0xFFFF_FFFF ? 1 : 0)
            register = (UInt32(truncatingIfNeeded: sum) & 0xFFFF_0000) | UInt32(low)
        }
        func ax() -> Int16 { Int16(truncatingIfNeeded: eax) }

        for step in Self.raySteps {
            si = si &+ (step.double ? xStep &* 2 : xStep)
            di = di &+ (step.double ? yStep &* 2 : yStep)
            // bx: height of the ground here
            let bx = first[Int(si >> 1)] &+ second[Int(di >> 1)] &+ step.terrainAdd
            if ax() < bx {
                let colour = UInt8(truncatingIfNeeded: bx &+ step.colourAdd) >> 1
                while true {
                    add(&eax, step.rise)
                    columnBuffer[Int(bp)] = colour
                    if ax() >= bx {
                        // One pixel drawn. The original's comment says the carry flag is clear here;
                        // in fact it is whatever the comparison left (set if ax is below bx as
                        // unsigned numbers). Kept as the machine would do it.
                        let carry = UInt16(bitPattern: ax()) < UInt16(bitPattern: bx)
                        add(&ecx, Self.slopePerPixel, carryIn: carry)
                        bp = bp &- 160
                        break
                    }
                    add(&eax, step.rise)
                    columnBuffer[Int(bp &- 160)] = colour
                    if ax() >= bx {
                        // Two pixels drawn.
                        let sum = UInt64(ecx) + UInt64(Self.slopePerPixel)
                        ecx = UInt32(truncatingIfNeeded: sum)
                        add(&ecx, Self.slopePerPixel, carryIn: sum > 0xFFFF_FFFF)
                        bp = bp &- 320
                        break
                    }
                    add(&eax, step.rise)
                    columnBuffer[Int(bp &- 320)] = colour
                    add(&ecx, Self.slopePerThreePixels)
                    bp = bp &- 480
                    if ax() >= bx { break }
                }
            }
            // Move the ray on to the next distance. (`adc ax,-1`: the ray also drops one whole
            // unit per step, which is what tips the view down towards the ground.)
            if step.double {
                let sum = UInt64(eax) + UInt64(ecx)
                eax = UInt32(truncatingIfNeeded: sum)
                add(&eax, ecx, carryIn: sum > 0xFFFF_FFFF, extra: 0xFFFF)
            } else {
                add(&eax, ecx, extra: 0xFFFF)
            }
        }
    }

    /// `docopy`: lines 60...199 of the column buffer go to screen lines 70 + startRise and down;
    /// whatever falls below line 199 is not seen. Everything above is black.
    private mutating func copyToScreen() {
        for i in screen.indices { screen[i] = 0 }
        for k in 0..<140 {
            let line = 70 + startRise + k
            if line >= Self.height { break }
            let row = (60 + k) * 160
            for a in 0..<Self.columns {
                let colour = columnBuffer[row + (a & 1) * 80 + (a >> 1)]
                screen[line * Self.width + a * 2] = colour
                screen[line * Self.width + a * 2 + 1] = colour
            }
        }
    }

    // MARK: Output

    /// The 1993 screen as colour numbers, 320x200.
    func classicIndices() -> [UInt8] { screen }

    func classicReferenceFrame() -> [UInt8] {
        var frame = [UInt8]()
        frame.reserveCapacity(Self.width * Self.height * 3)
        for index in screen {
            let colour = Self.palette[Int(index)]
            frame.append(byteFromVGA(colour.x))
            frame.append(byteFromVGA(colour.y))
            frame.append(byteFromVGA(colour.z))
        }
        return frame
    }

    /// The camera, gliding from the previous step's to this step's.
    func camera(alpha: Double) -> Camera {
        Camera(
            position: previousCamera.position + (camera.position - previousCamera.position) * alpha,
            heading: previousCamera.heading + (camera.heading - previousCamera.heading) * alpha,
            startRise: previousCamera.startRise + (camera.startRise - previousCamera.startRise) * alpha)
    }
}
