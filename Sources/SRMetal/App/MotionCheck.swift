import Foundation
import Metal

/// The command-line option that checks a scene's MOTION by program, without opening a window:
///
///     SRMetal --motion-check <scene-id> <modern|classic> [first-step last-step] [--csv file]
///
/// Still pictures cannot show a jump or a flicker. This runs ONE copy of the scene through the
/// given steps (the whole loop by default), draws a picture at every step (the modern look also
/// half-way between steps, as the app does on a fast display), and compares neighbours:
///
/// - **change**: the average difference between a picture and the one before (0...255 per colour
///   channel). A JUMP is a change much bigger than the changes around it.
/// - **flicker**: how many pixels are unlike BOTH neighbouring pictures while those two agree with
///   each other: something that appears for one picture only. A thin edge passing by does this
///   to a few pixels; a surface popping in front of another does it to hundreds at once.
///
/// It prints the worst of each, and with `--csv` writes one line per picture for a closer look.
/// It also times the scene's steps (how long `tick()` takes), which matters for the scenes whose
/// 1993 look is replayed on the processor.
enum MotionCheck {
    /// Modern pictures are drawn at this size: big enough to show a fault, small enough to be quick.
    static let width = 480
    static let height = 360

    static func run(arguments: [String]) -> Bool {
        let csvFlag = arguments.firstIndex(of: "--csv")
        let csv = csvFlag.flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        guard let flag = arguments.firstIndex(of: "--motion-check"), arguments.count >= flag + 3,
              let entry = SceneCatalog.all.first(where: { $0.id == arguments[flag + 1] }),
              let look = Look(rawValue: arguments[flag + 2]),
              let range = stepRange(from: Array(arguments.dropFirst(flag + 3).prefix { !$0.hasPrefix("--") })),
              csvFlag == nil || csv != nil else {
            print("Usage: SRMetal --motion-check <scene-id> <modern|classic> [first-step last-step] [--csv file]")
            print("(first-step and last-step: whole numbers, 0 or more, first not after last; leave both out for the whole loop)")
            print("Scenes: " + SceneCatalog.all.map(\.id).joined(separator: ", "))
            return false
        }
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let scene = try? entry.make(device, Renderer.pixelFormat) else {
            print("Could not set up \(entry.title)")
            return false
        }

        // The scene's length is not part of the scene contract, so without a range the run goes on
        // until the scene's 1993 picture has come back to its first one after a spell of
        // differing (a loop), or 20,000 steps.
        let first = range?.first ?? 0
        let last = range?.last ?? 20_000
        let wholeLoop = range == nil

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return false }

        /// The modern picture `alpha` of the way past the current step: blue, green, red, alpha bytes.
        func modern(_ alpha: Float) -> [UInt8] {
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            guard let commands = queue.makeCommandBuffer() else { return pixels }
            let frame = FrameInfo(look: .modern, alpha: alpha, canvasSize: entry.canvasSize,
                                  targetSize: SIMD2(Float(width), Float(height)))
            scene.prepare(commands: commands, frame: frame)
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: Renderer.clearPass(into: texture)) else { return pixels }
            scene.draw(into: encoder, frame: frame)
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            return pixels
        }

        struct Row { var step: Int; var alpha: Float; var change: Double; var flicker: Int }
        var rows: [Row] = []
        var before: [UInt8] = [], current: [UInt8] = []
        let channels = look == .modern ? 4 : 3

        func add(_ picture: [UInt8], step: Int, alpha: Float) {
            if !current.isEmpty {
                var total = 0
                for i in stride(from: 0, to: picture.count, by: channels) {
                    total += abs(Int(picture[i]) - Int(current[i])) + abs(Int(picture[i + 1]) - Int(current[i + 1]))
                        + abs(Int(picture[i + 2]) - Int(current[i + 2]))
                }
                rows.append(Row(step: step, alpha: alpha, change: Double(total) / Double(picture.count / channels * 3), flicker: 0))
                if !before.isEmpty {
                    // `current` is the middle picture of three.
                    var count = 0
                    for i in stride(from: 0, to: picture.count, by: channels) {
                        func gap(_ a: [UInt8], _ b: [UInt8]) -> Int {
                            abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
                        }
                        if gap(before, picture) <= 12 && gap(current, before) >= 60 && gap(current, picture) >= 60 { count += 1 }
                    }
                    rows[rows.count - 2].flicker = count
                }
            } else {
                rows.append(Row(step: step, alpha: alpha, change: 0, flicker: 0))
            }
            before = current
            current = picture
        }

        var tickSeconds = 0.0, slowest = 0.0, ticks = 0
        func tick() {
            let start = DispatchTime.now().uptimeNanoseconds
            scene.tick()
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
            tickSeconds += seconds
            slowest = max(slowest, seconds)
            ticks += 1
        }

        for _ in 0..<first { tick() }
        let start = scene.classicReferenceFrame()
        var differed = false
        var step = first
        while step <= last {
            if look == .modern {
                add(modern(0), step: step, alpha: 0)
                add(modern(0.5), step: step, alpha: 0.5)
            } else {
                // The 1993 look only changes on a step. A scene that holds a picture for several
                // steps (the city: two) is compared picture to picture, not step to step.
                let picture = scene.classicReferenceFrame()
                if picture != current { add(picture, step: step, alpha: 0) }
            }
            tick()
            step += 1
            if wholeLoop {
                let now = scene.classicReferenceFrame()
                if now != start { differed = true } else if differed && step > 64 {
                    // Back at the first picture: one more picture so the loop point itself is compared.
                    if look == .modern { add(modern(0), step: step, alpha: 0) } else { add(now, step: step, alpha: 0) }
                    break
                }
            }
        }

        print("\(entry.title), \(look.rawValue) look: steps \(first)...\(step), \(rows.count) pictures compared")
        print(String(format: "One step takes %.3f ms on average, %.3f ms at worst (a step is 14.286 ms at 70 a second)",
                     tickSeconds / Double(max(ticks, 1)) * 1000, slowest * 1000))

        // A jump: a change much bigger than the usual change around it (the middle value of the
        // 12 pictures either side), and big enough to see.
        var jumps: [(Row, Double)] = []
        for (i, row) in rows.enumerated() {
            let around = (max(0, i - 12)...min(rows.count - 1, i + 12)).filter { $0 != i }.map { rows[$0].change }.sorted()
            let usual = around.isEmpty ? 0 : around[around.count / 2]
            if row.change > 1.5 && row.change > usual * 3 { jumps.append((row, usual)) }
        }
        print("Jumps (a change over 1.5 and over 3 times the usual change nearby): \(jumps.count)")
        for (row, usual) in jumps.sorted(by: { $0.0.change / max($0.1, 0.1) > $1.0.change / max($1.1, 0.1) }).prefix(25) {
            print(String(format: "  step %5d +%.1f  change %6.2f  usual %6.2f", row.step, row.alpha, row.change, usual))
        }
        let flickers = rows.filter { $0.flicker > 0 }.sorted { $0.flicker > $1.flicker }
        let pixels = look == .modern ? width * height : Int(entry.canvasSize.x * entry.canvasSize.y)
        print("Pictures with one-picture-only pixels: \(flickers.count) of \(rows.count); over 0.1% of the picture: "
              + "\(flickers.filter { $0.flicker * 1000 > pixels }.count)")
        for row in flickers.prefix(25) {
            print(String(format: "  step %5d +%.1f  %6d pixels (%.2f%%)", row.step, row.alpha, row.flicker,
                         Double(row.flicker) * 100 / Double(pixels)))
        }
        if let csv {
            var text = "step,alpha,change,flicker\n"
            for row in rows { text += String(format: "%d,%.1f,%.4f,%d\n", row.step, row.alpha, row.change, row.flicker) }
            do { try text.write(toFile: csv, atomically: true, encoding: .utf8) } catch {
                print("Could not write \(csv)")
                return false
            }
        }
        return true
    }

    /// The optional "first-step last-step" words of the command line. No words at all means the
    /// whole loop (the inner nil). Anything else must be exactly two whole numbers, 0 or more, the
    /// first not after the last; if not, the answer is the outer nil: the command line is wrong.
    static func stepRange(from words: [String]) -> (first: Int, last: Int)?? {
        if words.isEmpty { return .some(nil) }
        guard words.count == 2, let first = Int(words[0]), let last = Int(words[1]),
              first >= 0, first <= last else { return nil }
        return (first, last)
    }
}
