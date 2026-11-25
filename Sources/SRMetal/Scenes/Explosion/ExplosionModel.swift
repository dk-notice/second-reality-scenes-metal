/// The explosion's timing, from `PAM/OUTTAA.C` (Trug and Wildfire, 1993).
///
/// The original set an all-white palette, then ran 45 rounds of 4 screen refreshes: in round f it showed
/// animation frame f (frames 1...40; rounds 41...45 keep frame 40) and faded the palette towards white by
/// `whiteFade[f]` out of 64. So it flashes white, fades the animation in, plays it, and fades back to white.
/// 45 x 4 = 180 steps of 1/70 s. Shown on its own, the scene then starts again.
struct ExplosionModel {
    static let frameCount = 40
    static let stepsPerRound = 4
    static let rounds = 45
    static let length = rounds * stepsPerRound

    /// `wfade` in OUTTAA.C: how far towards white (0...63) the palette is in each round. Round 0 is the
    /// all-white screen before the first frame.
    static let whiteFade: [Int] = [63, 32, 16, 8, 4, 2, 1, 0, 0, 0,
                                   0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                   0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                   1, 2, 4, 6, 9, 14, 20, 28, 37, 46,
                                   56, 63, 63, 63, 63, 63]

    private(set) var step = 0

    mutating func reset() { step = 0 }
    mutating func tick() { step = (step + 1) % Self.length }

    /// The round showing at a step: 0 (white, before the first frame) to 45.
    static func round(at step: Int) -> Int { min(step / stepsPerRound, rounds) }

    /// The animation frame showing (1...40). Round 0 shows the first frame, faded fully to white.
    static func frame(at step: Int) -> Int { min(max(round(at: step), 1), frameCount) }

    /// How far towards white, 1993 look: whole steps, changing every 4 steps.
    static func fade(at step: Int) -> Int { whiteFade[round(at: step)] }

    /// Modern look: the same fade gliding from one round's value to the next, `alpha` of a step on.
    static func smoothFade(at step: Int, alpha: Double) -> Double {
        let time = Double(step) + alpha
        let r = min(Int(time) / stepsPerRound, rounds)
        let next = min(r + 1, rounds)
        let within = (time - Double(r * stepsPerRound)) / Double(stepsPerRound)
        return Double(whiteFade[r]) + (Double(whiteFade[next]) - Double(whiteFade[r])) * min(max(within, 0), 1)
    }

    /// The picture name of an animation frame (1...40), as exported in `artwork/original/rgb/explosion`.
    static func pictureName(_ frame: Int) -> String {
        "explosion/frame-" + (frame < 10 ? "0" : "") + String(frame)
    }
}
