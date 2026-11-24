/// Where in a song the music is: what the original parts of the demo waited on.
/// See `docs/demo-timeline.md`, "How the music is used".
struct MusicPosition: Equatable {
    /// The song this position belongs to (nil when nothing is playing).
    var song: Song?
    /// The position in the song's order list (the "section"), counting "+++" separators.
    var order: Int
    /// The row within that section's pattern, 0...63.
    var row: Int

    static let silent = MusicPosition(song: nil, order: 0, row: 0)

    /// DIS's "music plus" (`dis_musplus`, DIS/DISINT.ASM `muscode_6`): counts rows towards and
    /// after a "+++" separator in the order list. -32 normally; in the section just before a
    /// separator, row minus 64 (-31...-1 over its last 31 rows); in the section just after one,
    /// the row (0...31). Same rule as `tools/demo_timeline.py`.
    static func plus(orderList: [Int], order: Int, row: Int) -> Int {
        func isSeparator(_ index: Int) -> Bool {
            index >= 0 && index < orderList.count && orderList[index] == TrackerSong.separatorMarker
        }
        let before = isSeparator(order + 1), after = isSeparator(order - 1)
        let towards = max(row - 64, -32)           // counting up to the separator
        let past = row < 32 ? row : -32            // counting on after it
        switch (before, after) {
        case (false, false): return -32
        case (true, false): return towards
        case (false, true): return past
        case (true, true): return row > 32 ? towards : past
        }
    }

    /// DIS's sync value (`dis_sync`): a fixed table of song positions (section << 8 | row) and the
    /// number reported once each is passed. Used by the opening credits and the explosion.
    static let syncTable: [(position: Int, value: Int)] = [
        (0x0000, 0), (0x0200, 1), (0x0300, 2), (0x032F, 3), (0x042F, 4), (0x052F, 5), (0x062F, 6),
        (0x072F, 7), (0x082F, 8), (0x0900, 9), (0x0D00, 10), (0x3D00, 1), (0x3F00, 2), (0x4100, 3), (0x4200, 4)
    ]

    static func sync(order: Int, row: Int) -> Int {
        let position = order << 8 | row
        for (index, entry) in syncTable.enumerated() where position <= entry.position {
            return index == 0 ? 0 : syncTable[index - 1].value
        }
        return syncTable[syncTable.count - 1].value
    }
}
