import Foundation
import simd

/// The state and rules of two scenes that share the same ring pictures, with no drawing code:
/// "Rings" (one set of teal rings) and "Interference" (two sets sliding over each other).
/// In the original these ran back to back as the opening of the techno part.
///
/// Based on Psi's original (TECHNO/KOEA.ASM and KOEB.ASM in the Second Reality source). The 1993 version
/// used two pictures of concentric rings, each 640x400, twice the size of the screen:
///
///  - an 8-colour picture whose rings get thinner further out, and
///  - a 1-bit picture of plain stripes-in-a-circle, 12 pixels wide.
///
/// The screen was a 320x200 window sliding around on the first picture. The second picture was copied
/// over it every frame at a different offset, into the one spare "bit plane" (a 16-colour video mode
/// stores each pixel as 4 separate bits; the first picture used 3 of them). Where the second picture's
/// bit was set, the video card used colours 8-15 instead of 0-7. Rotating the colour table made the
/// rings flow. So the whole effect was: slide two pictures, rotate 16 colours.
struct InterferenceModel {
    /// Which of the two scenes this is.
    enum Part {
        /// A single set of rings fades in from black and keeps flowing.
        case rings
        /// Two sets of rings interfere.
        case interference
    }

    /// The Rings scene takes this many steps to fade in from black.
    static let ringsFadeTicks = 128
    /// Length of the Interference scene before it loops. The original ran about 980 steps and then cut
    /// away on a music cue. We use 1024 so the loop is seamless: the two pictures' circular paths (which
    /// advance 5 and 7 table places per step, in a 1024-place table), the row wave and the colour rotation
    /// all arrive back exactly where they started.
    static let interferenceTicks = 1024
    /// In Interference, each row starts being pushed sideways by a wave after this many steps...
    static let wobbleStartTick = 350
    /// ...and the wave grows one notch (of 15) every this many steps. It shrinks again at the same
    /// rate at the end, so it is back to nothing when the scene loops. (The shrinking is our addition.)
    static let wobbleGrowTicks = 16

    /// Inside Play Demo the original's interference ended when the music's frame counter, started with
    /// the rings, reached this many music ticks (`TECHNO/KOEA.ASM` 900-904)...
    static let demoEndTicks = 925
    /// ...and then the screen went to white over four refreshes, each mixing the last palette this
    /// much of 256 towards white (`KOE.C` 224-228, `flash`). White then stays until the lead-in.
    static let flashMixes = [32, 64, 192, 256]

    static let pictureWidth = 640
    static let pictureHeight = 400

    enum Phase {
        case rings(frame: Int)
        case interference(frame: Int)
    }

    let part: Part
    private(set) var ticks = 0
    /// Inside Play Demo (set by the scene): the interference runs as the original's did, the wobble
    /// growing to full and staying there, no loop.
    var inDemo = false
    /// Inside Play Demo, once the music's cue has come: refreshes of the flash to white so far (the
    /// picture stays at its last step meanwhile). nil before.
    private(set) var flashSteps: Int?

    init(part: Part) {
        self.part = part
    }

    var phase: Phase {
        part == .rings ? .rings(frame: ticks) : .interference(frame: ticks)
    }

    mutating func reset() { ticks = 0; flashSteps = nil }

    /// Play Demo's cue: from the next tick, the flash to white instead of the next step.
    mutating func startFlash() { if flashSteps == nil { flashSteps = 0 } }

    /// How far (of 256) the palette is mixed towards white: 0 before the flash, then 32, 64, 192, 256.
    var flashMix: Int {
        guard let flashSteps, flashSteps > 0 else { return 0 }
        return Self.flashMixes[min(flashSteps, Self.flashMixes.count) - 1]
    }

    /// The same one step earlier (the Modern look glides from it).
    var previousFlashMix: Int {
        guard let flashSteps, flashSteps > 1 else { return 0 }
        return Self.flashMixes[min(flashSteps - 1, Self.flashMixes.count) - 1]
    }

    /// A colour mixed `mix` of 256 towards white, as `flash` did: (colour x (256 - mix) + 63 x mix) / 256.
    static func flashed(_ colour: Colour, mix: Int) -> Colour {
        (colour &* (256 - mix) &+ Colour(repeating: 63 * mix)) &>> 8
    }

    mutating func tick() {
        if let flashSteps { self.flashSteps = flashSteps + 1; return }
        ticks += 1
        switch part {
        case .rings:
            // Rings never ends. Once faded in, only the colour rotation matters, and that repeats
            // every 8 steps, so step back 8 to keep the counter small.
            if ticks >= 2 * Self.ringsFadeTicks { ticks -= 8 }
        case .interference:
            if ticks == Self.interferenceTicks && !inDemo { ticks = 0 }
        }
    }

    // MARK: - The two pictures

    /// Distance of a picture pixel from the picture's centre, the way the original pictures measured it.
    /// (They were stored as one quarter and mirrored, so the centre falls between four pixels.)
    private static func distance(x: Int, y: Int) -> Double {
        let dx = Double(x < 320 ? 320 - x : x - 319)
        let dy = Double(y < 200 ? 200 - y : y - 199)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Ring number of the 8-colour picture at a distance from its centre. Rings get thinner further out.
    /// The original shipped this picture as data; this formula reproduces that data exactly.
    static func ringNumber(distance: Double) -> Int {
        Int(pow(distance, 1.4) / 16)
    }

    /// The 1-bit picture: rings exactly 12 pixels wide, alternately off and on. Also exact.
    static func stripeBit(distance: Double) -> Int {
        Int(distance / 12) & 1
    }

    /// The 8-colour picture, one byte (0...7) per pixel, 640x400.
    static let ringPicture: [UInt8] = {
        var picture = [UInt8](repeating: 0, count: pictureWidth * pictureHeight)
        for y in 0..<pictureHeight {
            for x in 0..<pictureWidth {
                picture[y * pictureWidth + x] = UInt8(ringNumber(distance: distance(x: x, y: y)) & 7)
            }
        }
        return picture
    }()

    /// The 1-bit picture, one byte (0 or 1) per pixel, 640x400.
    static let stripePicture: [UInt8] = {
        var picture = [UInt8](repeating: 0, count: pictureWidth * pictureHeight)
        for y in 0..<pictureHeight {
            for x in 0..<pictureWidth {
                picture[y * pictureWidth + x] = UInt8(stripeBit(distance: distance(x: x, y: y)))
            }
        }
        return picture
    }()

    // MARK: - Colours (VGA scale, 0...63 per channel)

    typealias Colour = SIMD3<Int>

    /// Rings scene: one ring in eight is teal, the rest are black.
    static let ringsRamp: [Colour] = [Colour(0, 30, 40)] + [Colour](repeating: Colour(0, 0, 0), count: 7)

    /// Interference scene, where the stripe picture's bit is off: a purple-grey ramp.
    static let lowerRamp: [Colour] = [30, 60, 50, 40, 30, 20, 10, 0].map { Colour($0, $0 * 8 / 9, $0) }

    /// Interference scene, where the stripe picture's bit is on: a different ramp, slightly more purple.
    static let upperRamp: [Colour] = [0, 10, 20, 30, 40, 50, 60, 30].map { Colour($0, $0 * 7 / 9, $0) }

    /// The Rings scene's brightness control, 0...256: scales colours up from black.
    /// (The original carried on past 256, adding white until the whole screen burned out. We stop at full.)
    static func faded(_ colour: Colour, fader: Int) -> Colour {
        (colour &* fader) &>> 8
    }

    /// Brightness control value at a given Rings frame.
    static func fader(frame: Int) -> Int {
        min(2 * (frame + 1), 256)
    }

    /// How far the colour table has rotated at a given frame: one place per frame.
    static func cycle(frame: Int) -> Int {
        (8 - (frame + 1) % 8) % 8
    }

    /// The 16 colours the video card holds for the current frame.
    func classicPalette() -> [Colour] {
        switch phase {
        case .rings(let frame):
            let rotation = Self.cycle(frame: frame)
            let fader = Self.fader(frame: frame)
            let eight = (0..<8).map { Self.faded(Self.ringsRamp[(rotation + $0) & 7], fader: fader) }
            return eight + eight
        case .interference(let frame):
            let rotation = Self.cycle(frame: frame)
            let mix = flashMix
            return ((0..<8).map { Self.lowerRamp[(rotation + $0) & 7] }
                  + (0..<8).map { Self.upperRamp[(rotation + $0) & 7] }).map { Self.flashed($0, mix: mix) }
        }
    }

    // MARK: - Where the two pictures sit

    struct ClassicLayout {
        /// Top-left corner of the screen window on the 8-colour picture.
        var ringScroll: SIMD2<Int>
        /// Top-left corner of the screen window on the 1-bit picture, before the wobble. nil in the Rings scene.
        var stripeScroll: SIMD2<Int>?
        /// Extra sideways shift of the 1-bit picture for each of the 200 screen rows.
        var wobble: [Int]
    }

    /// Strength of the row wobble, 0...15, at a given Interference frame. On its own the scene shrinks
    /// it back so it can loop; inside Play Demo (`inDemo`) it stays at full, as the original's did.
    static func wobblePower(frame: Int, inDemo: Bool = false) -> Int {
        let growing = (frame - wobbleStartTick) / wobbleGrowTicks
        let shrinking = inDemo ? 15 : (interferenceTicks - frame) / wobbleGrowTicks
        return min(15, max(0, min(growing, shrinking)))
    }

    func classicLayout() -> ClassicLayout {
        switch phase {
        case .rings:
            // The Rings scene holds the window still, centred on the picture.
            return ClassicLayout(ringScroll: SIMD2(160, 100), stripeScroll: nil,
                                 wobble: [Int](repeating: 0, count: 200))
        case .interference(let frame):
            // Each picture's window moves in its own circle, at a different speed.
            let ringTurn = 5 * frame
            let stripeTurn = 211 + 7 * frame
            let power = Self.wobblePower(frame: frame, inDemo: inDemo)
            let wobble = (0..<200).map { row -> Int in
                let wave = SinTable.sin(7 * (frame + 1) + 9 * (row + 1)) >> 3
                return power == 15 ? wave : wave * power / 15
            }
            return ClassicLayout(
                ringScroll: SIMD2((SinTable.sin(ringTurn) >> 2) + 160, (SinTable.cos(ringTurn) >> 2) + 100),
                // The -7 falls out of how the original shifted the picture a bit at a time.
                stripeScroll: SIMD2((SinTable.sin(stripeTurn) >> 2) + 160 - 7, (SinTable.cos(stripeTurn) >> 2) + 100),
                wobble: wobble)
        }
    }

    /// The classic-look picture worked out on the processor by the 1993 rules: red, green, blue
    /// (0...63 each) for every pixel of the 320x200 screen.
    func classicReferenceFrame() -> [UInt8] {
        let palette = classicPalette()
        let layout = classicLayout()
        let width = Self.pictureWidth
        var frame = [UInt8]()
        frame.reserveCapacity(320 * 200 * 3)
        for row in 0..<200 {
            for column in 0..<320 {
                let ring = Int(Self.ringPicture[(row + layout.ringScroll.y) * width + column + layout.ringScroll.x])
                var bit = 0
                if let stripe = layout.stripeScroll {
                    bit = Int(Self.stripePicture[(row + stripe.y) * width + column + stripe.x + layout.wobble[row]])
                }
                let colour = palette[bit * 8 + ring]
                frame.append(UInt8(colour.x))
                frame.append(UInt8(colour.y))
                frame.append(UInt8(colour.z))
            }
        }
        return frame
    }

    // MARK: - The modern look: the same motion without the whole-number steps

    struct ModernParameters {
        /// 16 colours, 0...1 per channel: the ramp used where the stripe bit is off, then where it is on.
        /// Not rotated; `cycle` carries the rotation so the rings can glide instead of jumping.
        var ramps: [SIMD3<Float>]
        var cycle: Float
        var ringScroll: SIMD2<Float>
        var stripeScroll: SIMD2<Float>
        var stripesOn: Bool
        /// Row wobble: size in pixels, and where the wave is at the top of the screen (in 1/1024 turns).
        var wobbleAmplitude: Float
        var wobblePhase: Float
    }

    func modernParameters(alpha: Double) -> ModernParameters {
        func unit(_ colours: [SIMD3<Double>]) -> [SIMD3<Float>] {
            colours.map { SIMD3<Float>($0 / 63) }
        }
        func wave(_ turn: Double) -> Double { sin(turn * .pi / 512) * 64 }
        func rotation(_ frame: Double) -> Float {
            let r = (-(frame + 1)).truncatingRemainder(dividingBy: 8)
            return Float(r < 0 ? r + 8 : r)
        }

        switch phase {
        case .rings(let whole):
            let frame = Double(whole) + alpha
            let fader = min(2 * (frame + 1), 256)
            let faded = Self.ringsRamp.map { SIMD3<Double>($0) * fader / 256 }
            return ModernParameters(
                ramps: unit(faded + faded), cycle: rotation(frame),
                ringScroll: SIMD2(160, 100), stripeScroll: SIMD2(0, 0), stripesOn: false,
                wobbleAmplitude: 0, wobblePhase: 0)

        case .interference(let whole):
            // During Play Demo's flash the picture holds still and only the palette moves.
            let frame = Double(whole) + (flashSteps == nil ? alpha : 0)
            let ringTurn = 5 * frame
            let stripeTurn = 211 + 7 * frame
            let growing = (frame - Double(Self.wobbleStartTick)) / Double(Self.wobbleGrowTicks)
            let shrinking = inDemo ? 15 : (Double(Self.interferenceTicks) - frame) / Double(Self.wobbleGrowTicks)
            let power = min(15, max(0, min(growing, shrinking)))
            // The flash glides between its four mixes.
            let mix = Double(previousFlashMix) + Double(flashMix - previousFlashMix) * alpha
            let white = SIMD3<Double>(repeating: 63)
            let flash = { (c: SIMD3<Double>) in (c * (256 - mix) + white * mix) / 256 }
            return ModernParameters(
                ramps: unit((Self.lowerRamp.map { SIMD3<Double>($0) } + Self.upperRamp.map { SIMD3<Double>($0) }).map(flash)),
                cycle: rotation(frame),
                ringScroll: SIMD2(Float(wave(ringTurn) + 160), Float(wave(ringTurn + 256) + 100)),
                stripeScroll: SIMD2(Float(wave(stripeTurn) + 160 - 7), Float(wave(stripeTurn + 256) + 100)),
                stripesOn: true,
                wobbleAmplitude: Float(32 * power / 15),
                wobblePhase: Float(7 * (frame + 1)))
        }
    }
}
