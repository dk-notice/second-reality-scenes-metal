/// The song positions the sound output has rendered lately, each with the moment its sound leaves the
/// Mac for the output device. Play Demo's parts wait on the music as it is HEARD, and some outputs
/// (Bluetooth headphones above all) play a fraction of a second late: the player then reports the
/// position of that much earlier (`MusicPlayer.allowsForOutputDelay`).
///
/// A fixed ring, so the audio thread, which writes it, never has to ask for memory. A position is kept
/// only when it differs from the one before: a new row comes about every 0.12 s, so 64 entries are
/// several seconds.
struct PositionHistory {
    static let capacity = 64
    private var times = [Double](repeating: 0, count: capacity)
    private var positions = [MusicPosition](repeating: .silent, count: capacity)
    /// How many entries are in use, and where the next one goes.
    private var count = 0, next = 0

    init(start: MusicPosition = .silent) { restart(start) }

    /// Forgets everything: the music is at `position`, and was for as long as anyone asks.
    mutating func restart(_ position: MusicPosition) {
        count = 0
        next = 0
        record(position, at: -.infinity)
    }

    /// The newest position rendered (what the player reported before it allowed for the delay).
    var newest: MusicPosition { positions[(next + Self.capacity - 1) % Self.capacity] }

    /// Notes that the music is at `position` from `time` (seconds) on.
    mutating func record(_ position: MusicPosition, at time: Double) {
        if count > 0 && newest == position { return }
        positions[next] = position
        times[next] = time
        next = (next + 1) % Self.capacity
        count = min(count + 1, Self.capacity)
    }

    /// Where the music was at `time`: the newest entry not later than it, or the oldest still kept.
    func position(at time: Double) -> MusicPosition {
        var index = (next + Self.capacity - 1) % Self.capacity
        for _ in 1..<max(count, 1) {
            if times[index] <= time { break }
            index = (index + Self.capacity - 1) % Self.capacity
        }
        return positions[index]
    }
}
