import Foundation

/// The rules and state of the Ships Fly-by scene (the original's U2A.C), with no graphics-chip code.
///
/// Almost everything is the shared VISU engine (`Core/Visu/`, see docs/visu-engine.md): the
/// models, the recorded animation and the 1993 drawing. What is left for the scene is small:
///
/// - the background picture (original artwork, `U2ABG.UH`), copied over the whole screen before
///   every frame, exactly as U2A.C's `vid_clearbg(bg)` did;
/// - the palette: the scene file's colours, with the picture's 64 colours copied into 192...255;
/// - the timetable: one animation frame per 1/70-second step (the original tied the animation to
///   the screen's refresh, not to how fast the PC drew), and a pause on the empty horizon between
///   passes, which is this version's own (the original waited for the music instead).
///
/// Inside Play Demo there is no pause: the script shows the scene on the step the music's cue is met
/// (U2A.C 229-240), and the part's loop draws before it reads the animation, so the step the scene
/// appears on shows frame 0 (the empty horizon) and the n-th step after it frame n. The part lasts the
/// animation's 521 refreshes (the music's end cue, U2A.C 268-276, comes later), so frames 0...520 show.
final class ShipsFlybyModel {
    static let width = VisuEngine.width
    static let height = VisuEngine.height

    /// How long the empty horizon is held before the animation starts again, in steps (70 = one
    /// second). This is the one number to change if the gap between passes feels wrong. Note that
    /// the recorded animation itself shows nothing for its first 22 frames, and only a far-off
    /// speck for its last second, so the horizon looks empty for longer than this number says.
    static let pauseSteps = 70

    /// Frames in the recorded animation (U2A.0AB).
    static let animationFrames = 521
    /// One whole loop: the pause (showing frame 0, nothing switched on), then frames 1...521.
    static let lengthInSteps = pauseSteps + animationFrames + 1

    /// The animation being played, with the engine that draws it and the look-ahead for the
    /// modern look's glide (shared with the 3D City: `Core/Visu/VisuPlayback.swift`).
    private let playback: VisuPlayback
    var world: VisuWorld { playback.world }
    var engine: VisuEngine { playback.engine }
    /// The background picture: 320x200 colour numbers (192...242 in the picture's band).
    let background: [UInt8]
    /// 256 colours, red green blue, each 0...63.
    let palette: [UInt8]

    /// Steps since the start of the loop, 0..<lengthInSteps.
    private(set) var step = 0
    /// The pause before the animation, in steps: `pauseSteps` on its own, none inside Play Demo.
    private(set) var pause = ShipsFlybyModel.pauseSteps
    /// Inside Play Demo: no pause, and no second pass (the last frame stays until the part is cut).
    private(set) var inDemo = false
    /// The animation frame showing now.
    var animationFrame: Int { world.frame }
    /// Where everything is at this step and at the next one, for the modern look to glide between.
    var currentPose: VisuPose { playback.currentPose }
    var nextPose: VisuPose { playback.nextPose }

    /// The animation frame showing at a given step.
    static func animationFrame(atStep step: Int) -> Int { max(0, step - pauseSteps) }

    init() throws {
        playback = try VisuPlayback(name: "U2A")
        let file = try VisuData.load("U2ABG.UH")
        // 16 header bytes, 768 palette bytes, then the pixels.
        guard file.count >= 16 + 768 + Self.width * Self.height else { throw VisuError.badFile("U2ABG.UH", "too short") }
        background = Array(file[784..<784 + Self.width * Self.height])
        // U2A.C: memcpy(scene0+16+192*3, bg+16, 64*3)
        var colours = playback.world.palette
        colours.replaceSubrange(192 * 3..<256 * 3, with: file[16..<16 + 64 * 3])
        palette = colours
        drawClassic()
    }

    /// Play Demo, on the step it shows the scene: the flight starts at once.
    func enterDemo() {
        inDemo = true
        pause = 0
    }

    func reset() {
        playback.restart()
        step = 0
        drawClassic()
    }

    func tick() {
        let length = pause + Self.animationFrames + 1
        if step + 1 >= length {
            if !inDemo { reset() }
            return
        }
        step += 1
        // A new animation frame on every step after the pause. The step after this one shows the
        // next animation frame, unless this is the pause or the last step of the loop.
        playback.step(advancing: step > pause,
                      lookingAhead: step >= pause && step + 1 < length)
        // The 1993 picture is drawn on every step, in whichever look is showing, so that what the
        // engine carries from one picture to the next depends only on the step number.
        drawClassic()
    }

    /// U2A.C's main loop for one picture: copy the background in, then draw the objects.
    private func drawClassic() {
        engine.pixels = background
        world.draw(with: engine)
    }

    /// The 1993 picture as colour numbers.
    var screen: [UInt8] { engine.pixels }

    /// The pose to draw `alpha` (0...1) of the way from this step to the next. At 0 it is exactly
    /// what the 1993 look shows.
    func pose(alpha: Float) -> VisuPose { playback.pose(alpha: alpha) }

    /// The 1993 picture as red, green, blue bytes (0...255), for the self-test.
    func classicReferenceFrame() -> [UInt8] { VisuPlayback.rgb(engine.pixels, palette: palette) }
}
