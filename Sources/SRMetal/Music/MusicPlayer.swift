import AVFoundation
import os

/// Plays one of the demo's songs through the Mac's sound output, using macOS's own audio system
/// (`AVAudioEngine`). libopenmpt renders the music a small block at a time, on demand, on the
/// audio system's own thread.
///
/// That thread must never wait: if it misses its moment the sound clicks. So the song it reads from
/// is guarded by a lock the audio thread only TRIES to take; in the rare moment the menu is
/// changing the song, it plays a block of silence instead of waiting. Songs are loaded and
/// freed on the main thread, never on the audio thread.
///
/// After each block the audio thread also notes the song position it has reached (section and
/// row), for Play Demo, whose parts wait on the music. It writes that into a second lock, again
/// only if it is free at that moment; if not, the next block (a few milliseconds later) does.
final class MusicPlayer {
    /// What the audio thread works from. `@unchecked Sendable`: only touched while holding `shared`.
    private final class Shared: @unchecked Sendable {
        var song: TrackerSong?
        var look: Look = .modern
        var lookChanged = false
        var finished = false
    }

    private let shared = OSAllocatedUnfairLock(initialState: Shared())
    /// The position the audio thread last reached. Always taken after `shared`, never before it.
    private let reached = OSAllocatedUnfairLock(initialState: MusicPosition.silent)
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var sampleRate = 48_000

    /// The song now playing (nil when stopped or finished). Main thread only.
    private(set) var nowPlaying: Song?
    /// The order list of the song now playing (empty when stopped). Main thread only.
    private(set) var orderList: [Int] = []
    /// Called on the main thread when a song plays to its end.
    var onFinished: (() -> Void)?

    /// Starts `song` from the beginning of section `order` (normally 0), in the given sound,
    /// replacing whatever was playing. Song 1 plays at the demo's tempo (see `TrackerSong.init`).
    func play(_ song: Song, look: Look, fromOrder order: Int = 0) throws {
        let tracker = try TrackerSong(song)
        tracker.playWholeSong()
        if order > 0 { tracker.start(atOrder: order) }
        tracker.setSound(look)
        let list = tracker.orderList
        try startEngineIfNeeded()
        // Swap the new song in; the old one is released here, on the main thread, after the swap.
        let old = shared.withLock { state -> TrackerSong? in
            let old = state.song
            state.song = tracker
            state.look = look
            state.lookChanged = false
            state.finished = false
            // Inside `shared`, so no block of the old song can report its position after this.
            reached.withLock { $0 = MusicPosition(song: song, order: order, row: 0) }
            return old
        }
        _ = old
        nowPlaying = song
        orderList = list
    }

    func stop() {
        let old = shared.withLock { state -> TrackerSong? in
            let old = state.song
            state.song = nil
            reached.withLock { $0 = .silent }
            return old
        }
        _ = old
        nowPlaying = nil
        orderList = []
        engine.pause()
    }

    /// The song position the sound output has reached (`.silent` when stopped). Main thread.
    var position: MusicPosition {
        reached.withLock { $0 }
    }

    /// How far into the song the sound output has got, in seconds (0 when stopped). Main thread.
    var positionSeconds: Double {
        shared.withLockUnchecked { state in state.song?.positionSeconds ?? 0 }
    }

    /// Switches between the clean and the gritty sound while playing (takes effect within a block).
    func setSound(_ look: Look) {
        shared.withLock { state in
            state.look = look
            state.lookChanged = true
        }
    }

    private func startEngineIfNeeded() throws {
        if source == nil {
            // Render at whatever rate the Mac's output runs at, so macOS does not have to convert it.
            let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            sampleRate = rate > 0 ? Int(rate) : 48_000
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2) else {
                throw MusicError.libopenmpt("the sound output", "no stereo format at \(sampleRate) Hz")
            }
            let node = AVAudioSourceNode(format: format, renderBlock: makeRenderBlock())
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            source = node
        }
        if !engine.isRunning {
            try engine.start()
        }
    }

    /// The code the audio thread runs for every block of sound (a few milliseconds' worth).
    private func makeRenderBlock() -> AVAudioSourceNodeRenderBlock {
        let shared = self.shared
        let reached = self.reached
        let rate = sampleRate
        return { [weak self] isSilence, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let frames = Int(frameCount)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            var finishedSong: ObjectIdentifier?
            let rendered = shared.withLockIfAvailableUnchecked { state -> Int in
                guard let song = state.song, !state.finished else { return 0 }
                if state.lookChanged {
                    song.setSound(state.look)
                    state.lookChanged = false
                }
                let count = song.render(left: left, right: right, frames: frames, sampleRate: rate)
                let now = MusicPosition(song: song.song, order: song.currentOrder, row: song.currentRow)
                _ = reached.withLockIfAvailable { $0 = now }
                if count < frames {
                    state.finished = true
                    finishedSong = ObjectIdentifier(song)
                }
                return count
            } ?? 0
            if rendered < frames {
                (left + rendered).update(repeating: 0, count: frames - rendered)
                (right + rendered).update(repeating: 0, count: frames - rendered)
            }
            if rendered == 0 { isSilence.pointee = true }
            if let finishedSong {
                // Once per song: tell the main thread (this allocates, which is acceptable this rarely).
                DispatchQueue.main.async { self?.songFinished(finishedSong) }
            }
            return noErr
        }
    }

    /// A song reached its end. Only stops if that song is still the one loaded: the menu may have
    /// started another in the meantime.
    private func songFinished(_ which: ObjectIdentifier) {
        let stillLoaded = shared.withLock { state in state.song.map(ObjectIdentifier.init) == which }
        guard stillLoaded else { return }
        stop()
        onFinished?()
    }
}
