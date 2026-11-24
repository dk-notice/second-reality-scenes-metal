import Foundation

enum MusicError: Error, CustomStringConvertible {
    case missingFile(String)
    case badFile(String, String)
    case libopenmpt(String, String)

    var description: String {
        switch self {
        case .missingFile(let name):
            return "Music file not found: \(name) (looked in the app's Resources/Music and in Data/Music)"
        case .badFile(let name, let why):
            return "Music file \(name) is not as expected: \(why)"
        case .libopenmpt(let name, let why):
            return "libopenmpt could not open \(name): \(why)"
        }
    }
}

/// The demo's two songs, as shipped in the original source (see `Data/Music/README.md`).
enum Song: String, CaseIterable {
    /// "UnreaL ][ - The 2ND Reality", by Skaven: the first half of the demo.
    case first = "MUSIC0.S3M"
    /// "UnreaL ][ / PM", by Purple Motion: the second half.
    case second = "MUSIC1.S3M"

    /// The starting tempo the demo forced on the song when loading it, if any (see `TrackerSong.init`).
    var demoTempo: UInt8? { self == .first ? 120 : nil }

    /// How the Music menu names the song.
    var menuTitle: String {
        switch self {
        case .first: return "Song 1: \"The 2ND Reality\" (Skaven)"
        case .second: return "Song 2: \"Unreal II\" (Purple Motion)"
        }
    }
}

/// Finds and reads the song files, and undoes Future Crew's scrambling of their patterns.
///
/// `./build.sh` copies `Data/Music` into the app as `SRMetal.app/Contents/Resources/Music`; when the
/// program is run some other way, a `Data/Music` folder next to or above it is used instead.
enum MusicData {
    static let folder: URL? = {
        let manager = FileManager.default
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Music"))
        }
        var up = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(up.appendingPathComponent("Data/Music"))
            up = up.deletingLastPathComponent()
        }
        candidates.append(URL(fileURLWithPath: manager.currentDirectoryPath).appendingPathComponent("Data/Music"))
        return candidates.first { manager.fileExists(atPath: $0.appendingPathComponent(Song.first.rawValue).path) }
    }()

    /// The song file exactly as shipped (patterns still scrambled).
    static func original(_ song: Song) throws -> [UInt8] {
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent(song.rawValue)) else {
            throw MusicError.missingFile(song.rawValue)
        }
        return [UInt8](data)
    }

    /// The song as a standard S3M file, which any tracker or player (libopenmpt included) can read.
    static func unscrambled(_ song: Song) throws -> [UInt8] {
        try unscramble(original(song), name: song.rawValue)
    }

    /// Undoes the scrambling. Only the pattern data (the notes) was scrambled: in each pattern
    /// block, every byte after the block's 2-byte length is XOR-ed with (i ^ 4i), i being the byte's
    /// position in the block. The length counts its own 2 bytes. (Worked out 2026-11-24; the
    /// result for MUSIC0 matches a widely circulated unscrambled copy byte for byte, except that
    /// copy's order list, which was edited.) Every pattern is then checked to hold exactly 64 rows.
    static func unscramble(_ file: [UInt8], name: String) throws -> [UInt8] {
        var bytes = file
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        guard bytes.count >= 0x60, String(decoding: bytes[0x2C..<0x30], as: UTF8.self) == "SCRM" else {
            throw MusicError.badFile(name, "not an S3M file")
        }
        let orders = u16(0x20), instruments = u16(0x22), patterns = u16(0x24)
        let pointers = 0x60 + orders + 2 * instruments
        guard pointers + 2 * patterns <= bytes.count else { throw MusicError.badFile(name, "header runs past the end") }
        for pattern in 0..<patterns {
            let start = u16(pointers + 2 * pattern) * 16
            if start == 0 { continue }  // an empty pattern
            guard start + 2 <= bytes.count else { throw MusicError.badFile(name, "pattern \(pattern) starts past the end") }
            let length = u16(start)
            guard length >= 2, start + length <= bytes.count else {
                throw MusicError.badFile(name, "pattern \(pattern) runs past the end")
            }
            for i in 2..<length {
                bytes[start + i] ^= UInt8(truncatingIfNeeded: i ^ (i << 2))
            }
            guard rowCount(bytes, from: start + 2, to: start + length) == 64 else {
                throw MusicError.badFile(name, "pattern \(pattern) does not unscramble to 64 rows")
            }
        }
        return bytes
    }

    /// How many complete rows the packed pattern data between `from` and `to` holds.
    static func rowCount(_ bytes: [UInt8], from: Int, to: Int) -> Int {
        var p = from, rows = 0
        while p < to {
            let what = bytes[p]
            p += 1
            if what == 0 { rows += 1; continue }
            if what & 0x20 != 0 { p += 2 }  // note and instrument
            if what & 0x40 != 0 { p += 1 }  // volume
            if what & 0x80 != 0 { p += 2 }  // effect and its value
        }
        return p == to ? rows : -1
    }
}
