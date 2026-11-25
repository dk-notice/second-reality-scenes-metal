import Foundation
import simd

/// The rules and state of the 3D City scene (the original's U2E.C), with no graphics-chip code.
///
/// Almost everything is the shared VISU engine (`Core/Visu/`, see docs/visu-engine.md): the 42
/// models, the recorded 1,801-frame flight and the 1993 drawing. What U2E.C adds, and this keeps:
///
/// - the screen is filled with colour 255 (black) before every picture (`vid_clear255`);
/// - the palette is the scene file's, with colours 252 and 255 set to black and 253, 254 to white;
/// - two ordering rules (`VisuWorld.cityOrdering`): ground plates are always drawn first, and
///   during animation frames 901...1099 the ship is always drawn last;
/// - the pace: ONE animation frame every TWO 1/70-second steps (U2E.C counts screen refreshes
///   and reads `(refreshes late + 1) / 2` frames, so the pace did not depend on the PC's speed).
///
/// What is this version's own, on its own: the start and the end. The original came out of a white
/// screen and left through a white flash; here the picture fades up from black, fades back to black over
/// the animation's last frames, waits a moment and starts again.
///
/// Inside Play Demo it follows U2E.C (lines 285-366, 540-555) instead; step n is the n-th after the one
/// the scene is shown on, and what is set up after the program's n-th wait shows on step n:
/// - the lead-in, 100 steps over the jelly logo's last screen and palette (`DemoHandover`): colours
///   1...253 rise 2 levels a step for 33 steps (white; colour 0, the blank, stays); 16 steps;
///   `fadeset` draws a white window with black borders over the first 200 rows of memory (step 49, still
///   in the 400-line mode), the next step the mode doubles its lines (200 lines); 16 steps; colours
///   1...252 fall 2 levels a step and 253, 254 rise, 33 steps, and with the last the city's palette is set;
/// - the wait for music section 19, the window still showing; the step that meets it shows the window
///   again and so does the next (the first page shown is the one the window was drawn in);
/// - the flight from there: animation frame f on the 2f-th step after the cue, as on its own;
/// - after frame 1801, 16 steps of whitening: every colour 4 levels a step brighter, but written to the
///   card from colour 255 on, so each colour shows the one after it (colour 255, the background, shows
///   colour 0). The script moves on with the 16th.
final class City3DModel {
    static let width = VisuEngine.width
    static let height = VisuEngine.height

    /// Steps each animation frame is shown for (U2E.C: one frame per two screen refreshes).
    static let stepsPerFrame = 2
    /// Frames in the recorded animation (U2E.0AB).
    static let animationFrames = 1801

    /// The three numbers to change by eye (70 steps = one second):
    /// how long the picture takes to fade up from black at the start,
    static let fadeInSteps = 70
    /// how long it takes to fade to black at the end (over the animation's LAST steps),
    static let fadeOutSteps = 105
    /// and how long the screen then stays black before the flight starts again.
    static let darkSteps = 35

    /// Whether the modern look evens out the recorded camera's roll (see `rollCorrections`).
    static let smoothCameraRoll = true
    /// The most the modern look's camera may be rolled away from the recording, in degrees: half
    /// of the recording's one-degree roll steps.
    static let rollTolerance = 0.5

    /// The step on which the animation's last frame is first shown.
    static let lastFrameStep = animationFrames * stepsPerFrame
    /// The first black step after the animation.
    static let endStep = lastFrameStep + stepsPerFrame
    /// One whole loop.
    static let lengthInSteps = endStep + darkSteps

    /// The animation frame showing at a given step (0 = before the first: nothing is switched on).
    static func animationFrame(atStep step: Int) -> Int { min(step / stepsPerFrame, animationFrames) }

    /// How bright the picture is at a moment of the loop, 0...1 (`step` may carry a fraction, for
    /// the modern look between steps). Frame 1 arrives on step 2, where the fade-in starts.
    static func brightness(atStep step: Float) -> Float {
        let start = Float(stepsPerFrame), end = Float(endStep)
        if step <= start || step >= end { return 0 }
        let up = (step - start) / Float(max(fadeInSteps, 1))
        let down = (end - step) / Float(max(fadeOutSteps, 1))
        return min(1, up, down)
    }

    /// The animation being played, with the engine that draws it and the look-ahead for the
    /// modern look's glide (shared with Ships Fly-by: `Core/Visu/VisuPlayback.swift`).
    private let playback: VisuPlayback
    var world: VisuWorld { playback.world }
    var engine: VisuEngine { playback.engine }
    /// 256 colours at full brightness, red green blue, each 0...63.
    let palette: [UInt8]

    /// For each animation frame, how far (radians) the modern look rolls its camera away from the
    /// recorded one. See `rollCorrections(for:)`.
    let rollCorrection: [Float]

    /// Steps since the start of the loop, 0..<lengthInSteps. Inside Play Demo: steps since the music's
    /// cue (0 until then).
    private(set) var step = 0

    // MARK: Inside Play Demo

    static let leadInSteps = 100, whiteSteps = 33, holdSteps = 16, darkSteps2 = 33
    /// The step `fadeset` first shows (in the 400-line mode), and the step the lines double.
    static let windowStep = whiteSteps + holdSteps, doubledStep = windowStep + 1
    /// The step the fade to black (and to white for 253, 254) begins.
    static let fadeOutStart = doubledStep + 1 + holdSteps + 1
    static let cueSection = 18
    static let whiteningSteps = 16

    struct Demo {
        /// Steps since the scene was shown.
        var shown = 0
        /// The step (counted as `shown`) that met "section > 18".
        var cue: Int?
        var music: DemoMusicState?
        var previous: DemoHandover
        /// Memory's first 200 rows after `fadeset` (320x200): the window, and what it leaves alone.
        var window: [UInt8]
    }
    private(set) var demo: Demo?

    /// Play Demo's music, before each step; on the step the scene is shown with what the last part left.
    func update(music: DemoMusicState, justShown: Bool, previous: DemoHandover?) {
        if justShown {
            // No previous part (Play Demo started here): a white screen.
            let handover = previous.flatMap { $0.height == 400 && $0.numbers.count == 320 * 400 ? $0 : nil }
                ?? DemoHandover(numbers: [UInt8](repeating: 1, count: 320 * 400), height: 400,
                                levels: [SIMD3(0, 0, 0)] + Array(repeating: SIMD3(63, 63, 63), count: 255), drawModern: nil)
            demo = Demo(previous: handover, window: Self.fadeset(Array(handover.numbers[0..<(320 * 200)])))
            reset()
        }
        demo?.music = music
    }

    /// U2E.C `fadeset` on one page (unchained memory: byte b of a row is pixels 4b...4b + 3). Rows 25...174:
    /// colour 254, columns 68...252 colour 253. The other rows: colour 0, columns 68...252 colour 252, and in
    /// rows 0...24 columns 256...319 are not written (the routine writes 16 bytes 252 bytes on instead, into
    /// a row it rewrites later).
    static func fadeset(_ memory: [UInt8]) -> [UInt8] {
        var m = memory
        func fill(_ y: Int, _ x0: Int, _ x1: Int, _ c: UInt8) { for x in x0...x1 { m[y * 320 + x] = c } }
        for y in 0..<200 {
            let window = (25..<175).contains(y)
            fill(y, 0, 67, window ? 254 : 0)
            fill(y, 68, 255, window ? 253 : 252)
            fill(y, 253, 255, window ? 254 : 0)
            if y >= 25 { fill(y, 256, 319, window ? 254 : 0) }
        }
        return m
    }

    init() throws {
        playback = try VisuPlayback(name: "U2E", distanceRule: VisuWorld.cityOrdering)
        // U2E.C: colours 255 and 252 black, 253 and 254 white (used by its lead-in; 255 is the
        // colour the screen is cleared to).
        var colours = playback.world.palette
        for (colour, value) in [(255, 0), (252, 0), (253, 63), (254, 63)] {
            for k in 0..<3 { colours[colour * 3 + k] = UInt8(value) }
        }
        palette = colours
        rollCorrection = Self.smoothCameraRoll
            ? Self.rollCorrections(for: playback.world.cameraTrack())
            : [Float](repeating: 0, count: Self.animationFrames + 1)
        playback.engine.clear(to: 255)
    }

    /// The recording stores the camera's ROLL (its tilt about the line of sight) only to the
    /// nearest whole degree. Whenever the roll changes, the camera therefore snaps by one degree
    /// from one frame to the next, hundreds of times during the flight, instead of turning evenly.
    /// At 320x200 that is the original's look; in the smooth modern look it shows as a twitch.
    ///
    /// This works out, for each frame, a small extra roll that turns the staircase back into a
    /// smooth curve: the smoothest roll that stays within `rollTolerance` (half a degree, the most
    /// the rounding can have lost) of the recorded one. Only the modern look uses it.
    static func rollCorrections(for track: [VisuMatrix]) -> [Float] {
        let count = track.count
        guard count > 3 else { return [Float](repeating: 0, count: count) }
        func row(_ m: VisuMatrix, _ r: Int) -> SIMD3<Double> {
            SIMD3(Double(Int16(truncatingIfNeeded: m.m[r * 3])), Double(Int16(truncatingIfNeeded: m.m[r * 3 + 1])),
                  Double(Int16(truncatingIfNeeded: m.m[r * 3 + 2])))
        }
        // The recorded roll, added up frame by frame: how far the camera's "right" and "down"
        // directions turn about its line of sight from each frame to the next. (Frame 0 is
        // before the animation: all zero.)
        var recorded = [Double](repeating: 0, count: count)
        for n in 1..<count - 1 {
            let x0 = row(track[n], 0), y0 = row(track[n], 1), x1 = row(track[n + 1], 0), y1 = row(track[n + 1], 1)
            let sine = simd_dot(y1, x0) - simd_dot(x1, y0)
            let cosine = simd_dot(x1, x0) + simd_dot(y1, y0)
            recorded[n + 1] = recorded[n] + atan2(sine, cosine)
        }
        // Smooth it, never straying further from the recording than the tolerance: blur a little,
        // pull back inside the allowed band, and repeat until it settles.
        let tolerance = rollTolerance * .pi / 180
        var smooth = recorded
        for _ in 0..<100 {
            var blurred = smooth
            for n in 2..<count - 1 { blurred[n] = (smooth[n - 1] + 2 * smooth[n] + smooth[n + 1]) / 4 }
            for n in 0..<count { smooth[n] = min(max(blurred[n], recorded[n] - tolerance), recorded[n] + tolerance) }
        }
        return (0..<count).map { Float(smooth[$0] - recorded[$0]) }
    }

    func reset() {
        playback.restart()
        step = 0
        playback.engine.clear(to: 255)
    }

    func tick() {
        if demo != nil {
            demoTick()
            return
        }
        step += 1
        if step >= Self.lengthInSteps {
            reset()
            return
        }
        // A new animation frame on every second step, until the animation has run out.
        let newFrame = step % Self.stepsPerFrame == 0 && step <= Self.lastFrameStep
        playback.step(advancing: newFrame, lookingAhead: step < Self.lastFrameStep)
        if newFrame {
            // U2E.C's main loop for one picture: fill with colour 255, then draw the objects.
            // Every animation frame is drawn exactly once, in whichever look is showing, so that
            // what the engine carries from one picture to the next depends only on the step.
            engine.clear(to: 255)
            world.draw(with: engine)
        } else if step == Self.endStep {
            engine.clear(to: 255)
        }
    }

    private func demoTick() {
        guard var d = demo else { return }
        d.shown += 1
        if d.shown == Self.windowStep { d.previous.drawModern = nil }   // the last part's picture is gone
        if d.cue == nil, d.shown >= Self.leadInSteps, let music = d.music, music.order > Self.cueSection { d.cue = d.shown }
        demo = d
        guard let cue = d.cue else { return }
        step = d.shown - cue
        guard step > 0 else { return }
        let newFrame = step % Self.stepsPerFrame == 0 && step <= Self.lastFrameStep
        playback.step(advancing: newFrame, lookingAhead: step < Self.lastFrameStep)
        if newFrame {
            engine.clear(to: 255)
            world.draw(with: engine)
        }
    }

    /// Inside Play Demo, before the flight: the 1993 picture as colour numbers (320 wide), its height and
    /// its 256 colours. nil during the flight (then `screen` and `classicPalette`).
    var demoPicture: (numbers: [UInt8], height: Int, levels: [UInt8])? {
        guard let d = demo, step < Self.stepsPerFrame else { return nil }
        let n = d.shown
        if n < Self.windowStep { return (d.previous.numbers, 400, leadInLevels(n)) }
        if n == Self.windowStep {
            return (d.window + d.previous.numbers[(320 * 200)...], 400, leadInLevels(n))
        }
        return (d.window, 200, n >= Self.leadInSteps ? palette : leadInLevels(n))
    }

    /// The lead-in's palette on step n (before the city's own, which comes with step 100).
    func leadInLevels(_ n: Int) -> [UInt8] {
        guard let d = demo else { return palette }
        var levels = d.previous.levels.flatMap { [$0.x, $0.y, $0.z] }
        let up = min(n, Self.whiteSteps)
        for i in 3..<(768 - 6) { levels[i] = min(levels[i] + 2 * up, 63) }   // U2E.C: a = 3 ... 768 - 7
        let down = min(max(n - Self.fadeOutStart + 1, 0), Self.darkSteps2)
        for _ in 0..<down {
            for i in 3..<(768 - 9) { levels[i] = max(levels[i] - 2, 0) }
            for i in (768 - 9)..<(768 - 3) { levels[i] = min(levels[i] + 2, 63) }
        }
        return levels.map { UInt8($0) }
    }

    /// Inside Play Demo, the lift (levels) the Modern look adds to the last part's picture, `alpha` of a
    /// step on; nil once that picture is gone.
    func demoLift(alpha: Float) -> Float? {
        guard let d = demo, d.previous.drawModern != nil, d.shown < Self.windowStep else { return nil }
        return min(2 * (Float(d.shown) + alpha), 2 * Float(Self.whiteSteps))
    }

    /// The flight's palette inside Play Demo: the city's, then the whitening (`alpha` of a step on, for
    /// the Modern look).
    func demoFlightPalette(alpha: Float = 0) -> [UInt8] {
        let k = step - Self.lastFrameStep
        guard k >= 1 else { return palette }
        let lift = min(4 * (Float(k) + alpha), 64)
        // Written from colour 255 on: colour i shows colour i + 1 (255 shows 0).
        return (0..<768).map { i in
            let from = ((i / 3 + 1) % 256) * 3 + i % 3
            return UInt8(min(Float(palette[from]) + lift, 63).rounded(.down))
        }
    }

    /// The 1993 picture as colour numbers.
    var screen: [UInt8] { engine.pixels }

    /// How far (0...1) the modern look is from the animation frame now showing towards the next,
    /// `alpha` (0...1) of the way through this step. A frame lasts two steps, so the glide runs
    /// across both.
    func blend(alpha: Float) -> Float {
        (Float(step % Self.stepsPerFrame) + alpha) / Float(Self.stepsPerFrame)
    }

    /// The pose to draw `alpha` (0...1) of the way from this step to the next. On the first step
    /// of an animation frame, at alpha 0, it is exactly what the 1993 look shows.
    /// (That is true of where everything is; the camera's roll is evened out as well, see
    /// `rollCorrections`, which can tilt the modern picture up to half a degree from the 1993 one.)
    func pose(alpha: Float) -> VisuPose {
        let blend = blend(alpha: alpha)
        return playback.pose(alpha: blend).rolled(by: roll(blend: blend))
    }

    /// The extra camera roll (radians) `blend` of the way from the frame now showing to the next.
    func roll(blend: Float) -> Float {
        let frame = Self.animationFrame(atStep: step)
        let now = rollCorrection[min(frame, rollCorrection.count - 1)]
        let next = rollCorrection[min(frame + 1, rollCorrection.count - 1)]
        return now + (next - now) * blend
    }
    var currentPose: VisuPose { playback.currentPose }
    var nextPose: VisuPose { playback.nextPose }

    /// The palette as the 1993 look shows it at this step: every value scaled down by the fade
    /// and cut to a whole number 0...63, as a VGA palette fade did.
    var classicPalette: [UInt8] {
        if demo != nil { return demoFlightPalette() }
        let level = Self.brightness(atStep: Float(step))
        if level >= 1 { return palette }
        return palette.map { UInt8(Float($0) * level) }
    }

    /// The 1993 picture as red, green, blue bytes (0...255), for the self-test.
    func classicReferenceFrame() -> [UInt8] {
        if let picture = demoPicture { return VisuPlayback.rgb(picture.numbers, palette: picture.levels) }
        return VisuPlayback.rgb(engine.pixels, palette: classicPalette)
    }
}
