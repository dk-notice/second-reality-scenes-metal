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

    /// `asInDemo`: load the song as the demo did. For song 1 that means tempo 120 instead of the
    /// file's 125 (`MAIN/STARTMUS.C` set byte 50 of the module, its starting tempo, to 0x78), which
    /// makes every section of it last exactly 8 seconds. Song 2 is loaded unchanged either way.
    init(_ song: Song, asInDemo: Bool = true) throws {
        self.song = song
        var bytes = try MusicData.unscrambled(song)
        if asInDemo, let tempo = song.demoTempo { bytes[Self.tempoOffset] = tempo }
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

    /// Where in an S3M file its starting tempo is kept.
    static let tempoOffset = 0x32

    /// Starts playing from the beginning of section `order` (the demo started song 1 again from
    /// section 18 for the city). Call after `playWholeSong`, which resets the position.
    func start(atOrder order: Int) {
        openmpt_module_set_position_order_row(module, Int32(order), 0)
    }

    var currentOrder: Int { Int(openmpt_module_get_current_order(module)) }
    var currentRow: Int { Int(openmpt_module_get_current_row(module)) }

    /// The two sounds, matching the app's two looks. `.classic` turns off smoothing between a
    /// sample's points (libopenmpt's "interpolation filter length" 1, nearest point): grittier, closer
    /// to a 1993 sound card. `.modern` uses libopenmpt's default, smooth filter.
    func setSound(_ look: Look) {
        openmpt_module_set_render_param(module, OPENMPT_MODULE_RENDER_INTERPOLATIONFILTER_LENGTH, look == .classic ? 1 : 0)
    }

    /// Plays every sub-song in turn instead of only the first (MUSIC0 is split into 5 by its "---" marks).
    func playWholeSong() {
        openmpt_module_select_subsong(module, -1)
    }

    /// The whole song (as the demo loaded it), ready to play from the beginning of section `order`.
    static func wholeSong(_ song: Song, fromOrder order: Int) throws -> TrackerSong {
        let tracker = try TrackerSong(song)
        tracker.playWholeSong()
        if order > 0 { tracker.start(atOrder: order) }
        return tracker
    }

    /// How far into the song playback has got, in seconds.
    var positionSeconds: Double { openmpt_module_get_position_seconds(module) }

    /// Renders the next `frames` sample pairs into two separate channels, without allocating memory
    /// (safe to call from the audio thread). Returns how many were rendered: fewer at the end.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int, sampleRate: Int) -> Int {
        Int(openmpt_module_read_float_stereo(module, Int32(sampleRate), frames, left, right))
    }

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
