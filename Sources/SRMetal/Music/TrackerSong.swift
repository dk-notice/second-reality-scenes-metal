import COpenMPT
import Foundation

/// One of the demo's songs, loaded into libopenmpt (the tracker-music library built into the
/// program; see `ThirdParty/README.md`). It renders the music and reports where in the song it
/// is: the position the original parts synchronised on.
///
/// Not safe to share between threads: give each user its own `TrackerSong`.
final class TrackerSong {
    let song: Song
    private let module: OpaquePointer

    init(_ song: Song) throws {
        self.song = song
        let bytes = try MusicData.unscrambled(song)
        var error: Int32 = 0
        var message: UnsafePointer<CChar>?
        let module = bytes.withUnsafeBytes { buffer in
            openmpt_module_create_from_memory2(buffer.baseAddress, buffer.count,
                                               openmpt_log_func_silent, nil, openmpt_error_func_ignore, nil,
                                               &error, &message, nil)
        }
        guard let module else {
            let why = message.map { String(cString: $0) } ?? String(cString: openmpt_error_string(error))
            if let message { openmpt_free_string(message) }
            throw MusicError.libopenmpt(song.rawValue, why)
        }
        if let message { openmpt_free_string(message) }
        self.module = module
    }

    deinit {
        openmpt_module_destroy(module)
    }

    /// The version of libopenmpt built into the program, e.g. "0.8.10".
    static var libraryVersion: String {
        let v = openmpt_get_library_version()
        return "\(v >> 24).\((v >> 16) & 0xFF).\(v & 0xFFFF)"
    }

    var title: String { metadata("title") }
    var tracker: String { metadata("tracker") }
    var durationSeconds: Double { openmpt_module_get_duration_seconds(module) }
    var channels: Int { Int(openmpt_module_get_num_channels(module)) }
    var orders: Int { Int(openmpt_module_get_num_orders(module)) }
    var patterns: Int { Int(openmpt_module_get_num_patterns(module)) }
    var instruments: Int { Int(openmpt_module_get_num_instruments(module)) }
    var samples: Int { Int(openmpt_module_get_num_samples(module)) }
    var subsongs: Int { Int(openmpt_module_get_num_subsongs(module)) }

    /// libopenmpt's numbers for the two kinds of marker in an order list (the file itself uses 254
    /// and 255): "+++", a separator, skipped when playing; "---", the end of a (sub-)song.
    static let separatorMarker = 0xFFFE
    static let endMarker = 0xFFFF

    /// The song's order list ("sequence"): the pattern played at each position, or one of the two
    /// markers above. libopenmpt leaves out "---" markers at the very end of the list.
    var orderList: [Int] { (0..<orders).map { Int(openmpt_module_get_order_pattern(module, Int32($0))) } }

    var currentOrder: Int { Int(openmpt_module_get_current_order(module)) }
    var currentRow: Int { Int(openmpt_module_get_current_row(module)) }

    /// Renders the next `frames` stereo sample pairs at `sampleRate` into `buffer` (left, right,
    /// left, right ...; -1...1). Returns how many pairs were rendered: fewer at the end of the song.
    @discardableResult
    func render(into buffer: inout [Float], frames: Int, sampleRate: Int) -> Int {
        if buffer.count < frames * 2 { buffer = [Float](repeating: 0, count: frames * 2) }
        return buffer.withUnsafeMutableBufferPointer { out in
            Int(openmpt_module_read_interleaved_float_stereo(module, Int32(sampleRate), frames, out.baseAddress))
        }
    }

    private func metadata(_ key: String) -> String {
        guard let text = openmpt_module_get_metadata(module, key) else { return "" }
        defer { openmpt_free_string(text) }
        return String(cString: text)
    }
}
