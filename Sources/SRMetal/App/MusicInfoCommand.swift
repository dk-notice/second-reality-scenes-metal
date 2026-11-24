import Foundation

/// `--music-info`: loads both of the demo's songs into libopenmpt and prints what it finds, without
/// playing anything. `--music-info --write <folder>` also saves each song unscrambled, as a
/// standard S3M file any tracker or player can open.
enum MusicInfoCommand {
    static func run(arguments: [String]) -> Bool {
        print("libopenmpt \(TrackerSong.libraryVersion) (built into the program)")
        var writeFolder: URL?
        if let flag = arguments.firstIndex(of: "--write") {
            guard arguments.count > flag + 1 else {
                print("usage: SRMetal --music-info [--write <folder>]")
                return false
            }
            writeFolder = URL(fileURLWithPath: arguments[flag + 1])
        }
        var ok = true
        for song in Song.allCases {
            do {
                let tracker = try TrackerSong(song)
                let minutes = Int(tracker.durationSeconds) / 60
                let seconds = tracker.durationSeconds - Double(minutes * 60)
                print("\(song.rawValue): \"\(tracker.title)\" (\(tracker.tracker))")
                print("  \(tracker.channels) channels, \(tracker.orders) orders, \(tracker.patterns) patterns, "
                      + "\(tracker.samples) samples, \(tracker.subsongs) sub-songs")
                print("  first sub-song plays for \(minutes) min \(String(format: "%.1f", seconds)) s")
                print("  order list: " + tracker.orderList.map {
                    $0 == TrackerSong.separatorMarker ? "+++" : $0 == TrackerSong.endMarker ? "---" : String($0)
                }
                    .joined(separator: " "))
                if let writeFolder {
                    try FileManager.default.createDirectory(at: writeFolder, withIntermediateDirectories: true)
                    let file = writeFolder.appendingPathComponent(song.rawValue.replacingOccurrences(of: ".S3M", with: "-unscrambled.s3m"))
                    try Data(MusicData.unscrambled(song)).write(to: file)
                    print("  written: \(file.path)")
                }
            } catch {
                print("\(song.rawValue): \(error)")
                ok = false
            }
        }
        return ok
    }
}
