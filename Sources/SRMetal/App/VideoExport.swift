import Foundation
import Metal

/// `--export-video`: the whole of Play Demo as the raw material of a video file, in the Modern look.
///
///     SRMetal --export-video plan
///     SRMetal --export-video sound <file.wav> [seconds]
///     SRMetal --export-video pictures [seconds] > frames
///
/// `sound` writes the demo's sound as a WAV file (16-bit stereo, 44,100 a second); `pictures` writes
/// every picture to its standard output (2880x2160, 60 a second, four bytes a pixel: blue, green, red,
/// unused; top row first) and reports its progress on the standard error. `tools/export_video.py` runs
/// both and hands them to ffmpeg, which makes the .mov file; this program knows nothing of ffmpeg.
/// `seconds` stops early (for a trial, and for proving the checks). A fourth form, `stills`, writes
/// single pictures of the export as PNG files, for `tools/check_video.py` to compare the file with.
///
/// HOW SOUND AND PICTURE STAY IN STEP. Nothing here follows a clock. The demo is stepped 70 times a
/// second of ITS time with silently rendered music (`SilentMusic`, as `--demo-timeline`): every step
/// renders exactly 630 sample pairs. Picture k belongs at k/60 s, which is 7k/6 steps: the demo is
/// stepped 7k div 6 times and drawn (7k mod 6)/6 of the way to the next step, and its sound starts at
/// sample pair 735k. All whole numbers, so nothing can drift. No sound device is involved, so the
/// allowance for the output's delay (Music > Allow for Output Delay) cannot come into it.
enum VideoExport {
    static let width = 2880
    static let height = 2160
    static let framesPerSecond = 60
    /// Sample pairs of sound per picture: 44,100 / 60.
    static let samplesPerFrame = SilentMusic.sampleRate / framesPerSecond
    /// The fade to black at the very end: 2 seconds.
    static let fadeFrames = 2 * framesPerSecond

    /// When picture `frame` is: after how many steps, and how far on towards the next (0, 1/6 ... 5/6).
    static func moment(frame: Int) -> (step: Int, blend: Float) {
        (7 * frame / 6, Float(7 * frame % 6) / 6)
    }

    /// How bright picture `frame` of `total` is: 1 until the last two seconds, then falling evenly to 0
    /// on the last picture.
    static func fade(frame: Int, of total: Int) -> Float {
        let left = total - 1 - frame
        return left >= fadeFrames ? 1 : Float(max(left, 0)) / Float(fadeFrames)
    }

    /// The length of the export, worked out from the script, the music and the end scroller's text.
    struct Plan {
        /// The step the end scroller starts on.
        var scrollerStart: Int
        /// The first step in which the last song gave no more sound.
        var musicEnd: Int
        /// The step by which the last row with text in it has left the top of the screen.
        var textGone: Int
        /// The step on which the text starts again from the top.
        var passEnd: Int
        /// Pictures in the whole export (a multiple of 6, so it ends on a whole step).
        var frames: Int
        var steps: Int { frames * 7 / 6 }
    }

    static let plan: Plan = {
        // The script, silently, to the end scroller and on until the music runs out.
        let music = SilentMusic()
        let sequencer = DemoSequencer(music: music)
        while !sequencer.finished && sequencer.time < 70 * 60 * 15 { sequencer.tick() }
        let scrollerStart = sequencer.partStarts.last?.step ?? 0
        while music.lastRendered == SilentMusic.framesPerStep && sequencer.time < 70 * 60 * 40 { sequencer.tick() }
        let musicEnd = sequencer.time - 1
        // The end scroller's text, one pass. The scene has its first step two steps after the script
        // shows it (the step that shows it, then `DemoRunScene.tick` moves the scene before the script).
        var textGone = scrollerStart, passEnd = scrollerStart
        if var model = try? EndScrollerModel.load() {
            // `ticks`: the scene's steps before the one that draws the first row of the second pass.
            var ticks = 0, lastTextRow = -1
            while ticks < 70 * 60 * 30 {
                var next = model
                next.tick()
                if next.passes > 0 { break }
                model = next
                lastTextRow = model.lastTextRow
                ticks += 1
            }
            passEnd = scrollerStart + 1 + ticks
            textGone = scrollerStart + 1 + (lastTextRow + EndScrollerModel.height + 1) * EndScrollerModel.stepsPerRow
        }
        let end = passEnd
        return Plan(scrollerStart: scrollerStart, musicEnd: musicEnd, textGone: textGone, passEnd: passEnd,
                    frames: 6 * ((end + 6) / 7))
    }()

    // MARK: - The command

    static let usage = """
        usage: SRMetal --export-video plan
               SRMetal --export-video sound <file.wav> [seconds]
               SRMetal --export-video pictures [seconds] > frames
               SRMetal --export-video stills <folder> <seconds|all> <picture number> ...
        (tools/export_video.py runs these and makes the video file; tools/check_video.py checks it)
        """

    static func run(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: "--export-video"), flag + 1 < arguments.count else {
            print(usage)
            return false
        }
        let rest = Array(arguments[(flag + 2)...])
        /// The number of pictures: all of them, or those of the first `seconds` (nil: not a number).
        func frames(_ word: String?) -> Int? {
            guard let word else { return plan.frames }
            guard let seconds = Int(word), seconds > 0 else { return nil }
            return min(plan.frames, seconds * framesPerSecond)
        }
        switch arguments[flag + 1] {
        case "plan" where rest.isEmpty:
            printPlan()
            return true
        case "sound" where (1...2).contains(rest.count):
            guard let frames = frames(rest.count > 1 ? rest[1] : nil) else { break }
            do {
                try wav(sound(frames: frames)).write(to: URL(fileURLWithPath: rest[0]))
                print("\(frames * samplesPerFrame) sample pairs (\(frames) pictures' worth) written to \(rest[0])")
                return true
            } catch {
                print("Could not write \(rest[0]): \(error)")
                return false
            }
        case "pictures" where rest.count <= 1:
            guard let frames = frames(rest.first) else { break }
            guard isatty(1) == 0 else {
                print("The pictures go to the standard output, which is the terminal here.")
                break
            }
            // The pictures go where the standard output pointed; from here on anything printed (by any
            // part of the program) goes to the standard error instead, so it cannot land among the pictures.
            let pictures = dup(1)
            dup2(2, 1)
            signal(SIGPIPE, SIG_IGN)
            do {
                try export(frames: frames, pictures: pictures)
                return true
            } catch {
                note("\nThe export stopped: \(error)\n")
                return false
            }
        case "stills" where rest.count >= 3:
            // For `tools/check_video.py`: single pictures of the export, as PNG files.
            guard let frames = frames(rest[1] == "all" ? nil : rest[1]) else { break }
            let wanted = rest[2...].compactMap { Int($0) }
            guard wanted.count == rest.count - 2, wanted == wanted.sorted(), wanted.allSatisfy({ (0..<frames).contains($0) }) else {
                print("The pictures' numbers must be in rising order, from 0 to \(frames - 1).")
                break
            }
            do {
                let run = try Run(width: width, height: height)
                var pixels = [UInt8](repeating: 0, count: width * height * 4)
                for frame in wanted {
                    try run.draw(frame: frame, into: &pixels)
                    darken(&pixels, level: fade(frame: frame, of: frames))
                    let file = URL(fileURLWithPath: rest[0]).appendingPathComponent(String(format: "frame-%06d.png", frame))
                    guard let image = Snapshot.image(bgra: pixels, width: width, height: height),
                          Snapshot.writePNG(image, to: file) else { return false }
                }
                return true
            } catch {
                print("Could not draw: \(error)")
                return false
            }
        default:
            break
        }
        print(usage)
        return false
    }

    static func printPlan() {
        let p = plan
        func at(_ step: Int) -> String { "step \(step), \(DemoTimelineCommand.time(step))" }
        print("width \(width)\nheight \(height)\nrate \(framesPerSecond)\nframes \(p.frames)\nsamples \(p.frames * samplesPerFrame)")
        print("The end scroller starts at \(at(p.scrollerStart)).")
        print("The music runs out at \(at(p.musicEnd)).")
        print("The last text leaves the screen at \(at(p.textGone)).")
        print("The text starts again at \(at(p.passEnd)).")
        print("The export: \(p.frames) pictures, \(DemoTimelineCommand.time(p.steps)), the last \(fadeFrames / framesPerSecond) s fading to black.")
    }

    enum Failure: Error, CustomStringConvertible {
        case couldNotWrite(String)
        var description: String {
            switch self {
            case .couldNotWrite(let what): return "could not write \(what) (did ffmpeg stop?)"
            }
        }
    }

    static func note(_ text: String) { FileHandle.standardError.write(Data(text.utf8)) }

    // MARK: - The sound

    /// The sound of the first `frames` pictures: 735 sample pairs each (left, right, ...), as the WAV
    /// file holds them. It is what the script hears: the same sequencer and silent music as
    /// `--demo-timeline`, 630 pairs a step, with the same fade as the pictures at the end.
    static func sound(frames: Int) -> [Int16] {
        let music = SilentMusic()
        var samples = [Int16]()
        samples.reserveCapacity((frames * 7 / 6 + 1) * SilentMusic.framesPerStep * 2)
        music.onSound = { step in samples.append(contentsOf: step.map(sample16)) }
        let sequencer = DemoSequencer(music: music)
        while samples.count < frames * samplesPerFrame * 2 { sequencer.tick() }
        samples.removeLast(samples.count - frames * samplesPerFrame * 2)
        for frame in max(0, frames - fadeFrames)..<frames {
            let level = fade(frame: frame, of: frames)
            for index in frame * samplesPerFrame * 2..<(frame + 1) * samplesPerFrame * 2 {
                samples[index] = Int16((Float(samples[index]) * level).rounded())
            }
        }
        return samples
    }

    /// A sample as the WAV file holds it.
    static func sample16(_ value: Float) -> Int16 { Int16((max(-1, min(1, value)) * 32767).rounded()) }

    /// A standard WAV file of 16-bit stereo samples at 44,100 a second.
    static func wav(_ samples: [Int16]) -> Data {
        var file = Data()
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { file.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { file.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        file.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); file.append(contentsOf: Array("WAVE".utf8))
        file.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(2)
        u32(SilentMusic.sampleRate); u32(SilentMusic.sampleRate * 4); u16(4); u16(16)
        file.append(contentsOf: Array("data".utf8)); u32(bytes)
        samples.withUnsafeBytes { file.append(contentsOf: $0) }   // (this Mac's byte order is the file's: low byte first)
        return file
    }

    // MARK: - The pictures

    /// Play Demo drawn picture by picture without a window: what the export writes, at any size (the
    /// self-test uses a small one).
    final class Run {
        let width: Int
        let height: Int
        let scene: DemoRunScene
        private(set) var steps = 0
        private let queue: MTLCommandQueue
        private let texture: MTLTexture

        init(width: Int, height: Int) throws {
            self.width = width
            self.height = height
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
                throw Snapshot.Failure.noGraphicsDevice
            }
            self.queue = queue
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: Renderer.pixelFormat, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw Snapshot.Failure.couldNotDraw }
            self.texture = texture
            scene = try DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic())
        }

        /// Draws picture `frame` into `pixels` (blue, green, red, unused; top row first), as the app's
        /// window draws the Modern look, at that picture's exact moment. Pictures are asked for in order.
        func draw(frame: Int, into pixels: inout [UInt8]) throws {
            let moment = VideoExport.moment(frame: frame)
            while steps < moment.step { scene.tick(); steps += 1 }
            try autoreleasepool {
                let info = FrameInfo(look: .modern, alpha: moment.blend,
                                     canvasSize: scene.currentCanvasSize ?? SIMD2(320, 200),
                                     targetSize: SIMD2(Float(width), Float(height)))
                guard let commands = queue.makeCommandBuffer() else { throw Snapshot.Failure.couldNotDraw }
                scene.prepare(commands: commands, frame: info)
                guard let encoder = commands.makeRenderCommandEncoder(descriptor: Renderer.clearPass(into: texture))
                else { throw Snapshot.Failure.couldNotDraw }
                scene.draw(into: encoder, frame: info)
                encoder.endEncoding()
                commands.commit()
                commands.waitUntilCompleted()
                texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
        }
    }

    /// Darkens a picture's bytes for the fade (`level` 0...1; 1 leaves them alone).
    static func darken(_ pixels: inout [UInt8], level: Float) {
        guard level < 1 else { return }
        let table = (0..<256).map { UInt8((Float($0) * level).rounded()) }
        pixels.withUnsafeMutableBufferPointer { bytes in
            for index in bytes.indices { bytes[index] = table[Int(bytes[index])] }
        }
    }

    static func export(frames: Int, pictures: Int32) throws {
        let run = try Run(width: width, height: height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let began = Date()
        var lastNote = Date.distantPast
        for frame in 0..<frames {
            try run.draw(frame: frame, into: &pixels)
            darken(&pixels, level: fade(frame: frame, of: frames))
            try pixels.withUnsafeBytes { bytes in
                var done = 0
                while done < bytes.count {
                    let wrote = write(pictures, bytes.baseAddress! + done, bytes.count - done)
                    if wrote <= 0 {
                        if wrote < 0 && errno == EINTR { continue }
                        throw Failure.couldNotWrite("picture \(frame)")
                    }
                    done += wrote
                }
            }
            let now = Date()
            if now.timeIntervalSince(lastNote) >= 0.5 || frame == frames - 1 {
                lastNote = now
                let speed = Double(frame + 1) / max(now.timeIntervalSince(began), 0.001)
                let left = Int((Double(frames - frame - 1) / speed).rounded())
                note(String(format: "\rFrame %d of %d (%.1f%%)  %.0f frames/s  %d min %02d s left  %@\u{1B}[K",
                            frame + 1, frames, Double(frame + 1) * 100 / Double(frames), speed, left / 60, left % 60,
                            run.scene.currentPart ?? ""))
            }
        }
        close(pictures)
        let took = Date().timeIntervalSince(began)
        note(String(format: "\n%d pictures in %d min %02d s.\n", frames, Int(took) / 60, Int(took) % 60))
    }
}
