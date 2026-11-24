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

/// `--music-render <1|2> <seconds> <file.wav> [modern|classic]`: renders the start of a song to a
/// WAV sound file (16-bit stereo, 44,100 per second) without playing it, in the Modern (smooth) or
/// 1993 (gritty) sound. For listening to in Finder's Quick Look, and for checking by program.
enum MusicRenderCommand {
    static let usage = "usage: SRMetal --music-render <1|2> <seconds> <file.wav> [modern|classic]"

    static func run(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: "--music-render"), arguments.count >= flag + 4,
              let number = Int(arguments[flag + 1]), (1...2).contains(number),
              let seconds = Double(arguments[flag + 2]), seconds > 0, seconds <= 1200 else {
            print(usage)
            return false
        }
        let file = URL(fileURLWithPath: arguments[flag + 3])
        let lookWord = arguments.count > flag + 4 ? arguments[flag + 4] : "modern"
        guard let look = Look(rawValue: lookWord) else {
            print("unknown sound '\(lookWord)'; " + usage)
            return false
        }
        let song: Song = number == 1 ? .first : .second
        do {
            let tracker = try TrackerSong(song)
            tracker.playWholeSong()
            tracker.setSound(look)
            let rate = 44_100
            var samples = [Float]()
            let rendered = tracker.render(into: &samples, frames: Int(seconds * Double(rate)), sampleRate: rate)
            try wav(samples.prefix(rendered * 2), sampleRate: rate).write(to: file)
            print("\(song.rawValue), \(look.rawValue) sound: \(String(format: "%.1f", Double(rendered) / Double(rate))) s written to \(file.path)")
            return true
        } catch {
            print("\(song.rawValue): \(error)")
            return false
        }
    }

    /// A standard WAV file: 16-bit stereo samples, interleaved (left, right, ...).
    static func wav(_ samples: ArraySlice<Float>, sampleRate: Int) -> Data {
        var data = Data()
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(2); u32(sampleRate); u32(sampleRate * 4); u16(4); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(bytes)
        for sample in samples {
            let value = Int16((max(-1, min(1, sample)) * 32767).rounded())
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}

/// `--music-play <1|2> <seconds> [modern|classic]`: plays the start of a song through the Mac's
/// sound output with the app's music player, then reports how far the sound output got (which
/// shows the audio system really pulled music from libopenmpt).
enum MusicPlayCommand {
    static let usage = "usage: SRMetal --music-play <1|2> <seconds> [modern|classic]"

    static func run(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: "--music-play"), arguments.count >= flag + 3,
              let number = Int(arguments[flag + 1]), (1...2).contains(number),
              let seconds = Double(arguments[flag + 2]), seconds > 0, seconds <= 1200 else {
            print(usage)
            return false
        }
        let lookWord = arguments.count > flag + 3 ? arguments[flag + 3] : "modern"
        guard let look = Look(rawValue: lookWord) else {
            print("unknown sound '\(lookWord)'; " + usage)
            return false
        }
        let song: Song = number == 1 ? .first : .second
        let player = MusicPlayer()
        do {
            try player.play(song, look: look)
        } catch {
            print("\(song.rawValue): \(error)")
            return false
        }
        print("Playing \(song.menuTitle), \(look.rawValue) sound, for \(seconds) s ...")
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        let reached = player.positionSeconds
        let position = player.position
        let plus = MusicPosition.plus(orderList: player.orderList, order: position.order, row: position.row)
        player.stop()
        print("Position read from the audio thread: section \(position.order), row \(position.row), music plus \(plus).")
        print("The sound output reached \(String(format: "%.2f", reached)) s into the song.")
        // The output renders a little ahead of what is heard, so allow some slack either way.
        return reached > seconds * 0.8
    }
}
