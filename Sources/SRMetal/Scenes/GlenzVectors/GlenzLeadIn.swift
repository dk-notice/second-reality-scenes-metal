import Foundation

/// Inside Play Demo, what GLENZ shows before its plate (GLENZ/MAIN.C 288-293 and ZOOMER.C `zoomer2`).
///
/// - Until "music plus" >= -19 the screen is the title picture as BEG left it (fully in). The music frame
///   counter starts on that step.
/// - `zoomer2`, 47 passes: black bars (colour 255, black in BEG's palette) grow from the top of the
///   400-line screen (to row 260) and from its bottom (from row 274, 125/260 as fast), while colours
///   0...127, the whole title picture, fade to grey level 30 over the first 32 passes:
///   (level · (32 − c) + 30 · c) >> 5. Then the screen is cleared and the plate's loop begins.
/// - Step pairing (as the jelly logo): what a pass draws before its wait shows on the step it is drawn in,
///   so pass f's bars show on the cue step + f; the palette set after wait f, worked out with c = f − 1,
///   shows on the same step. The plate's first picture shows on the cue step + 47.
/// - The pause after the plate is longer than on its own: the glenz waits until the music's frame counter,
///   set to 0 on the cue step, reaches 333 (MAIN.C 400; the released GLENZ.EXE is this source). The counter
///   counts MUSIC TICKS (52 a second), so that is about 448 steps after the cue: with the wipe's 47 and
///   the plate's 177, some 226 steps without a new picture. The scene reads the counter (`pauseOver`).
struct GlenzLeadIn {
    static let musicCue = -19
    static let wipeSteps = 47
    static let greyLevel = 30, fadeParts = 32
    /// The music frame counter (ticks) the glenz waits for.
    static let pauseEnd = 333
    static let barColour: UInt8 = 255

    /// The title picture: 320x400 colour numbers and their colours (VGA levels).
    let title: [UInt8]
    let levels: [SIMD3<Int>]

    /// Steps since the scene was shown, and the one that met the music cue.
    private(set) var shown = 0
    private(set) var cue: Int?
    private var music: DemoMusicState?
    /// The counter had reached `pauseEnd` on the step before this one: the program has left its wait.
    private(set) var pauseOver = false

    init(title: [UInt8], levels: [SIMD3<Int>]) {
        self.title = title
        self.levels = levels
    }

    /// Play Demo's music, before each step; `justShown` on the step the scene appears (MAIN.C waits from
    /// its first moment, so a cue already met there counts).
    mutating func update(music: DemoMusicState, justShown: Bool) {
        self.music = music
        if justShown { shown = 0; cue = music.plus >= Self.musicCue ? 0 : nil; pauseOver = false }
    }

    mutating func tick() {
        shown += 1
        // The script sets the counter to 0 on the cue step, after this step has read it: only later
        // steps see the part's own count.
        if let cue, shown > cue + 1, let music, music.ticks >= Self.pauseEnd { pauseOver = true }
        if cue == nil, let music, music.plus >= Self.musicCue { cue = shown }
    }

    /// The wipe's pass showing now (0...46), or ≥ 47 once the plate has taken over; nil before the cue.
    var wipePass: Int? { cue.map { shown - $0 } }
    var finished: Bool { (wipePass ?? 0) >= Self.wipeSteps }

    /// After pass f: the top bar covers rows 0...top, the bottom bar rows bottom...399 (of 400).
    static func bars(_ f: Int) -> (top: Int, bottom: Int) {
        var zy = 0, zya = 0
        for _ in 0...max(f, 0) {
            zya += 1
            zy = min(zy + zya / 4, 260)
        }
        return (zy, 399 - 125 * zy / 260)
    }

    /// The fade (c of 32 parts grey) showing with pass f.
    static func fade(_ f: Int) -> Int { min(max(f - 1, 0), fadeParts) }

    /// The 1993 screen: colour numbers (320x400) and 256 colours (VGA levels, red green blue).
    var classic: (numbers: [UInt8], levels: [UInt8]) {
        var numbers = title
        var c = 0
        if let f = wipePass {
            c = Self.fade(f)
            let (top, bottom) = Self.bars(f)
            for row in Array(0...top) + Array(bottom...399) {
                for x in 0..<320 { numbers[row * 320 + x] = Self.barColour }
            }
        }
        var out = [UInt8](repeating: 0, count: 768)
        for (i, colour) in levels.enumerated() where i < 255 {
            for k in 0..<3 {
                out[i * 3 + k] = UInt8((colour[k] * (Self.fadeParts - c) + Self.greyLevel * c) >> 5)
            }
        }
        return (numbers, out)
    }

    /// For the Modern look, `alpha` of a step on: the grey parts (0...32, fractional) and the bars' edges
    /// in canvas rows of 200 (top bar 0...top, bottom bar bottom...200); nil bars before the cue.
    func modern(alpha: Float) -> (grey: Float, bars: (top: Float, bottom: Float)?) {
        guard let f = wipePass else { return (0, nil) }
        let next = min(f + 1, Self.wipeSteps - 1)
        func mix(_ a: Int, _ b: Int) -> Float { Float(a) + (Float(b) - Float(a)) * alpha }
        let now = Self.bars(f), then = Self.bars(next)
        return (mix(Self.fade(f), Self.fade(next)),
                (mix(now.top + 1, then.top + 1) / 2, mix(now.bottom, then.bottom) / 2))
    }
}
