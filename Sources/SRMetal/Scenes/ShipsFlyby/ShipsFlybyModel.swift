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

    let world: VisuWorld
    /// A second copy of the animation kept one frame AHEAD, so the modern look knows where
    /// everything is going and can glide towards it. It is never drawn.
    private let ahead: VisuWorld
    let engine = VisuEngine()
    /// The background picture: 320x200 colour numbers (192...242 in the picture's band).
    let background: [UInt8]
    /// 256 colours, red green blue, each 0...63.
    let palette: [UInt8]

    /// Steps since the start of the loop, 0..<lengthInSteps.
    private(set) var step = 0
    /// Where everything is at this step and at the next one, for the modern look to glide between.
    private(set) var currentPose = VisuPose(items: [])
    private(set) var nextPose = VisuPose(items: [])

    /// The animation frame showing at a given step.
    static func animationFrame(atStep step: Int) -> Int { max(0, step - pauseSteps) }

    init() throws {
        world = try VisuWorld(name: "U2A")
        ahead = try VisuWorld(name: "U2A")
        let file = try VisuData.load("U2ABG.UH")
        // 16 header bytes, 768 palette bytes, then the pixels.
        guard file.count >= 16 + 768 + Self.width * Self.height else { throw VisuError.badFile("U2ABG.UH", "too short") }
        background = Array(file[784..<784 + Self.width * Self.height])
        // U2A.C: memcpy(scene0+16+192*3, bg+16, 64*3)
        var colours = world.palette
        colours.replaceSubrange(192 * 3..<256 * 3, with: file[16..<16 + 64 * 3])
        palette = colours
        VisuWorld.setSceneWindow(engine)
        drawClassic()
    }

    func reset() {
        world.restart()
        ahead.restart()
        // The engine remembers things from polygon to polygon (see docs/visu-engine.md, "Kept
        // quirks"), so it has to go back to its start too for a restart to be exact.
        engine.resetClipper()
        step = 0
        currentPose = VisuPose(items: [])
        nextPose = currentPose
        drawClassic()
    }

    func tick() {
        step += 1
        if step >= Self.lengthInSteps {
            reset()
            return
        }
        if step > Self.pauseSteps { world.advance() }
        currentPose = world.pose()
        // The step after this one shows the next animation frame, unless this is the pause or the
        // last step of the loop.
        if step >= Self.pauseSteps && step + 1 < Self.lengthInSteps {
            ahead.advance()
            nextPose = ahead.pose()
        } else {
            nextPose = currentPose
        }
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
    func pose(alpha: Float) -> VisuPose {
        alpha <= 0 ? currentPose : currentPose.blended(to: nextPose, alpha: alpha)
    }

    /// The 1993 picture as red, green, blue bytes (0...255), for the self-test.
    func classicReferenceFrame() -> [UInt8] {
        var result = [UInt8](repeating: 0, count: Self.width * Self.height * 3)
        for (i, colour) in engine.pixels.enumerated() {
            for k in 0..<3 { result[i * 3 + k] = byteFromVGA(Int(palette[Int(colour) * 3 + k])) }
        }
        return result
    }
}
