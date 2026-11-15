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
/// What is this version's own: the start and the end. The original came out of a white screen and
/// left through a white flash; here the picture fades up from black, fades back to black over the
/// animation's last frames, waits a moment and starts again.
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

    /// Steps since the start of the loop, 0..<lengthInSteps.
    private(set) var step = 0

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
    /// from one frame to the next, about 190 times during the flight, instead of turning evenly.
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
        let level = Self.brightness(atStep: Float(step))
        if level >= 1 { return palette }
        return palette.map { UInt8(Float($0) * level) }
    }

    /// The 1993 picture as red, green, blue bytes (0...255), for the self-test.
    func classicReferenceFrame() -> [UInt8] { VisuPlayback.rgb(engine.pixels, palette: classicPalette) }
}
