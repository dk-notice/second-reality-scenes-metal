import CoreGraphics
import Foundation
import Metal
import simd

/// Self-test checks for the music: libopenmpt, the demo's songs and the song position Play Demo waits on (run by `CoreChecks.run`; see `App/CoreChecks.swift`).
extension CoreChecks {
    // MARK: - The music (libopenmpt and the demo's songs; added 2026-11-24)

    static func music(_ check: (String, Bool, String) -> Void) {
        // The song files as shipped in the original source, and unscrambled. The unscrambled MUSIC0
        // matched a widely circulated unscrambled copy byte for byte, except that copy's edited order
        // list (checked 2026-11-24); these numbers pin that result down.
        do {
            let originals = try Song.allCases.map { SelfTest.crc32(try MusicData.original($0)) }
            check("Music: the song files are the originals", originals == [2_761_269_977, 607_687_703], "\(originals)")
            let unscrambled = try Song.allCases.map { SelfTest.crc32(try MusicData.unscrambled($0)) }
            check("Music: both songs unscramble to standard S3M files, every pattern 64 rows",
                  unscrambled == [1_538_452_661, 2_143_406_352], "\(unscrambled)")
        } catch {
            check("Music: the song files can be read and unscrambled", false, "\(error)")
            return
        }
        // A damaged file must be refused, not crash. The unscrambler can only notice damage that
        // breaks a pattern's structure (a changed note still unscrambles to a valid pattern), so
        // the damage here is a pattern block whose length is one byte too long.
        if var damaged = try? MusicData.original(.first) {
            let pointers = 0x60 + Int(damaged[0x20]) + Int(damaged[0x21]) << 8 + 2 * (Int(damaged[0x22]) + Int(damaged[0x23]) << 8)
            let pattern = (Int(damaged[pointers]) | Int(damaged[pointers + 1]) << 8) * 16
            damaged[pattern] &+= 1
            let refused = (try? MusicData.unscramble(damaged, name: "damaged")) == nil
            check("Music: a song with a pattern block of the wrong length is refused", refused, "")
        }
        // libopenmpt, built into the program, opens both songs and sees what the demo relied on.
        do {
            let first = try TrackerSong(.first), second = try TrackerSong(.second)
            check("Music: libopenmpt is built in", !TrackerSong.libraryVersion.isEmpty, TrackerSong.libraryVersion)
            check("Music: libopenmpt reads both songs (8 channels; 78 and 99 orders)",
                  [first.channels, second.channels, first.orders, second.orders] == [8, 8, 78, 99],
                  "\([first.channels, second.channels, first.orders, second.orders])")
            check("Music: the demo's \"+++\" and \"---\" order-list markers are visible",
                  first.orderList.contains(TrackerSong.separatorMarker) && first.orderList.contains(TrackerSong.endMarker)
                      && second.orderList.contains(TrackerSong.separatorMarker), "")
            // Rendering is repeatable (a fresh song gives the same sound twice) and not silent.
            var a = [Float](), b = [Float]()
            let other = try TrackerSong(.first)
            first.render(into: &a, frames: 44_100, sampleRate: 44_100)
            other.render(into: &b, frames: 44_100, sampleRate: 44_100)
            let loudest = a.map(abs).max() ?? 0
            check("Music: the first second of MUSIC0 renders the same twice, and is not silent",
                  a == b && loudest > 0.01, "loudest \(loudest)")
            // The player's two sounds (they follow the look) really differ, and "the whole song"
            // goes on past the first "---" mark: MUSIC0's first sub-song is only about 2 minutes.
            let smooth = try TrackerSong(.first), gritty = try TrackerSong(.first)
            smooth.setSound(.modern)
            gritty.setSound(.classic)
            var c = [Float](), d = [Float]()
            smooth.render(into: &c, frames: 44_100, sampleRate: 44_100)
            gritty.render(into: &d, frames: 44_100, sampleRate: 44_100)
            let difference = zip(c, d).map { abs($0 - $1) }.max() ?? 0
            check("Music: the Modern and 1993 sounds differ", difference > 0.001, "largest difference \(difference)")
            let firstPart = smooth.durationSeconds
            smooth.playWholeSong()
            check("Music: playing the whole of MUSIC0 lasts longer than its first sub-song",
                  smooth.durationSeconds > firstPart + 60,
                  "\(Int(firstPart)) s -> \(Int(smooth.durationSeconds)) s")
        } catch {
            check("Music: libopenmpt opens both songs", false, "\(error)")
        }
        musicPosition(check)
    }

    /// The song position Play Demo waits on (added 2026-11-24 with Play Demo).
    static func musicPosition(_ check: (String, Bool, String) -> Void) {
        // Song 1 plays at tempo 120, as in the demo: its first section lasts 8 s = 560 steps of 1/70 s.
        func stepsInFirstSection(_ song: TrackerSong) -> Int {
            var buffer = [Float](), steps = 0
            while song.currentOrder == 0 && steps < 2000 {
                song.render(into: &buffer, frames: 630, sampleRate: 44_100)
                steps += 1
            }
            return steps
        }
        do {
            let demo = try TrackerSong(.first), file = try TrackerSong(.first, asInDemo: false)
            let a = stepsInFirstSection(demo), b = stepsInFirstSection(file)
            check("Music: song 1 is loaded at the demo's tempo 120 (first section 8 s), not the file's 125",
                  (559...561).contains(a) && b < a - 10, "\(a) and \(b) steps")
            let later = try TrackerSong(.first)
            later.playWholeSong()
            later.start(atOrder: 18)
            var buffer = [Float]()
            later.render(into: &buffer, frames: 630, sampleRate: 44_100)
            check("Music: a song can start from section 18 (the city)",
                  later.currentOrder == 18 && later.currentRow == 0, "\(later.currentOrder)/\(later.currentRow)")
        } catch {
            check("Music: song 1 opens at the demo's tempo", false, "\(error)")
        }
        // "Music plus" around a separator, on a made-up order list: 5, +++, 6, 7.
        let sep = TrackerSong.separatorMarker
        let list = [5, sep, 6, 7]
        let plus = [(0, 10), (0, 40), (0, 63), (2, 0), (2, 31), (2, 32), (3, 10)].map {
            MusicPosition.plus(orderList: list, order: $0.0, row: $0.1)
        }
        check("Music: \"music plus\" counts up to a \"+++\" and on after it",
              plus == [-32, -24, -1, 0, 31, -32, -32], "\(plus)")
        let both = [0, 31, 33, 63].map { MusicPosition.plus(orderList: [1, sep, 2, sep, 3], order: 2, row: $0) }
        check("Music: \"music plus\" between two separators counts after the first, then towards the second",
              both == [0, 31, -31, -1], "\(both)")
        let sync = [(0, 0), (2, 0), (2, 1), (3, 0x2F), (3, 0x30), (13, 1), (40, 0), (62, 0), (70, 0)].map {
            MusicPosition.sync(order: $0.0, row: $0.1)
        }
        check("Music: the sync table gives the original's numbers", sync == [0, 0, 1, 2, 3, 10, 10, 1, 4], "\(sync)")
    }
}
