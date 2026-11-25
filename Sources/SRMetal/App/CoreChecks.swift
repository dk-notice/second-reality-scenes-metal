import CoreGraphics
import Foundation
import Metal
import simd

/// Self-test checks for the code every scene shares (`Core/`) and for the app's command line.
/// Added by the code review of 2026-11-14; run first by `SelfTest.run()`.
///
/// Each check here either pins down a bug that review found and fixed (it fails on the code as
/// it was before), or checks a rule that the scenes rely on but nothing was testing.
enum CoreChecks {
    static func run(_ report: (String, Bool, String) -> Void) {
        func check(_ name: String, _ passed: Bool, _ detail: String = "") { report(name, passed, detail) }

        catalogue(check)
        clock(check)
        letterbox(check)
        commandLine(check)
        math3D(check)
        smoothTriangleGeometry(check)
        music(check)
        demoTimeline(check)

        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            check("Core: Metal device available", false)
            return
        }
        do {
            try indexedCanvas(check, device: device, queue: queue)
            try smoothTrianglesDrawn(check, device: device, queue: queue)
            try snapshots(check)
            try pictureScaler(check, device: device, queue: queue)
            try pictureFades(check, device: device, queue: queue)
        } catch {
            check("Core: drawing checks could be set up", false, "\(error)")
        }
    }

    // MARK: - The music (libopenmpt and the demo's songs; added 2026-11-24)

    private static func music(_ check: (String, Bool, String) -> Void) {
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

    // MARK: - The Modern look's picture scaler (Super-xBR; added 2026-11-24)

    private static func pictureScaler(_ check: (String, Bool, String) -> Void, device: MTLDevice, queue: MTLCommandQueue) throws {
        /// An 8-bit picture on the graphics chip, from red, green, blue bytes.
        func picture(_ rgb: [UInt8], width: Int, height: Int) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            var rgba = [UInt8]()
            for i in 0..<(width * height) { rgba += [rgb[3 * i], rgb[3 * i + 1], rgb[3 * i + 2], 255] }
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: rgba, bytesPerRow: width * 4)
            return texture
        }
        /// The upscaled picture's red, green, blue values (0...1), read back from the graphics chip.
        func readBack(_ texture: MTLTexture) -> [Float] {
            let w = texture.width, h = texture.height
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: w, height: h, mipmapped: false)
            descriptor.storageMode = .shared
            guard let copy = device.makeTexture(descriptor: descriptor), let commands = queue.makeCommandBuffer(),
                  let blit = commands.makeBlitCommandEncoder() else { return [] }
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, to: copy, destinationSlice: 0, destinationLevel: 0,
                      sliceCount: 1, levelCount: 1)
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            var halves = [UInt16](repeating: 0, count: w * h * 4)
            copy.getBytes(&halves, bytesPerRow: w * 8, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            var out = [Float]()
            out.reserveCapacity(w * h * 3)
            for i in 0..<(w * h) { for k in 0..<3 { out.append(floatFromHalf(halves[4 * i + k])) } }
            return out
        }

        // A flat colour stays exactly that colour.
        let flatRGB = [UInt8](repeating: 0, count: 16 * 16 * 3).enumerated().map { [UInt8(200), 90, 30][$0.offset % 3] }
        if let flat = picture(flatRGB, width: 16, height: 16) {
            let big = try PictureScaler.upscaled(flat, device: device)
            let values = readBack(big)
            let worst = zip(values, (0..<values.count).map { Float([200, 90, 30][$0 % 3]) / 255 }).map { abs($0 - $1) }.max() ?? 1
            check("Picture scaler: Super-xBR makes a picture exactly \(PictureScaler.modernScale) times larger, and leaves a flat colour unchanged",
                  big.width == 16 * PictureScaler.modernScale && big.height == 16 * PictureScaler.modernScale && worst < 0.002, "largest change \(worst)")
        }

        // On a real picture (the troll: dithering, gradients, hard edges) every new pixel stays within
        // the colours of the original pixels around it: no invented colours, no halos.
        guard let rgb = ScenePicture.pixels("07-troll") else {
            check("Picture scaler: the troll picture is there to test with", false, "")
            return
        }
        let troll = try ScenePicture(named: "07-troll", device: device).original
        let w = troll.width, h = troll.height
        func original(_ x: Int, _ y: Int, _ k: Int) -> Float {
            Float(rgb[(min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)) * 3 + k]) / 255
        }
        let big = try PictureScaler.upscaled(troll, device: device)
        let values = readBack(big)
        let scale = PictureScaler.modernScale
        // The lowest and highest value of each colour among the original pixels within 2 of each pixel.
        var lowest = [Float](repeating: 1, count: w * h * 3), highest = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                for k in 0..<3 {
                    for sy in (y - 2)...(y + 2) {
                        for sx in (x - 2)...(x + 2) {
                            let v = original(sx, sy, k)
                            lowest[(y * w + x) * 3 + k] = min(lowest[(y * w + x) * 3 + k], v)
                            highest[(y * w + x) * 3 + k] = max(highest[(y * w + x) * 3 + k], v)
                        }
                    }
                }
            }
        }
        var outside = 0, worst: Float = 0
        for y in 0..<(scale * h) {
            for x in 0..<(scale * w) {
                let near = ((y / scale) * w + x / scale) * 3
                for k in 0..<3 {
                    let v = values[(y * scale * w + x) * 3 + k]
                    let off = max(lowest[near + k] - v, v - highest[near + k])
                    if off > 0.002 { outside += 1; worst = max(worst, off) }
                }
            }
        }
        check("Picture scaler: Super-xBR on the troll keeps every new pixel within the colours of the original pixels around it",
              big.width == scale * w && big.height == scale * h && outside == 0, "\(outside) values outside, worst by \(worst)")
    }

    /// The shared picture-and-fade toolkit (added 2026-11-24): in the 1993 look a fade gives exactly the
    /// colour levels the original's whole-number rule gives, towards white and towards black.
    private static func pictureFades(_ check: (String, Bool, String) -> Void, device: MTLDevice, queue: MTLCommandQueue) throws {
        let levels = [0, 1, 2, 17, 31, 32, 33, 50, 62, 63]   // 1993 colour levels, one per pixel
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: levels.count, height: 1, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw Snapshot.Failure.couldNotDraw }
        // Red = the level, green = 63 - level, blue = a third of it: three different values per pixel.
        let rgba: [UInt8] = levels.flatMap { level -> [UInt8] in
            [byteFromVGA(level), byteFromVGA(63 - level), byteFromVGA(level / 3), 255]
        }
        texture.replace(region: MTLRegionMake2D(0, 0, levels.count, 1), mipmapLevel: 0, withBytes: rgba, bytesPerRow: levels.count * 4)
        let picture = ScenePicture(texture, device: device)
        let layer = try PictureLayer.shared(device: device, pixelFormat: Renderer.pixelFormat)
        var wrong = 0, tried = 0
        for fade in [PictureFade.none, .white(1), .white(32), .white(63), .fromWhite(keep: 0, outOf: 128),
                     .fromWhite(keep: 37, outOf: 128), .fromWhite(keep: 127, outOf: 128), .toBlack(keep: 63, outOf: 64),
                     .toBlack(keep: 20, outOf: 64), .toBlack(keep: 0, outOf: 64)] {
            let drawn = try draw(width: levels.count, height: 1, device: device, queue: queue) { encoder in
                layer.draw(picture, into: encoder, look: .classic, fade: fade)
            }
            for (x, level) in levels.enumerated() {
                let expected = [level, 63 - level, level / 3].map { byteFromVGA(fade.classicLevel($0)) }
                let got = [drawn[x * 4 + 2], drawn[x * 4 + 1], drawn[x * 4]]   // stored blue, green, red
                tried += 1
                if got != expected { wrong += 1 }
            }
        }
        check("Pictures: 1993-look fades (64ths and 128ths, to white and to black) give exactly the original rules' colours",
              wrong == 0, "\(wrong) of \(tried) pixels differ")
    }

    /// A 16-bit floating-point number (as the graphics chip stores it) as an ordinary one.
    private static func floatFromHalf(_ bits: UInt16) -> Float {
        let sign: Float = bits & 0x8000 != 0 ? -1 : 1
        let exponent = Int((bits >> 10) & 0x1F), fraction = Float(bits & 0x3FF)
        if exponent == 0 { return sign * fraction / 1024 * pow(2, -14) }
        if exponent == 31 { return fraction == 0 ? sign * .infinity : .nan }
        return sign * (1 + fraction / 1024) * pow(2, Float(exponent - 15))
    }

    /// Play Demo's running order (added 2026-11-24): the script, run silently against the music,
    /// starts every part at the step the research simulation (`tools/demo_timeline.py`) gives.
    private static func demoTimeline(_ check: (String, Bool, String) -> Void) {
        let (sequencer, problem) = DemoTimelineCommand.simulate()
        let wrong = DemoTimelineCommand.differences(sequencer.partStarts)
        check("Play Demo: all \(DemoTimelineCommand.expected.count) parts start on the step tools/demo_timeline.py gives (credits end 10:52.4)",
              wrong.isEmpty && problem == nil, problem ?? wrong.prefix(3).joined(separator: "; "))
        let ids = Set(SceneCatalog.all.map(\.id))
        let scenes = DemoScript.steps.compactMap { step -> String? in
            if case .show(.scene(let id)) = step { return id } else { return nil }
        }
        let unknown = scenes.filter { !ids.contains($0) }
        check("Play Demo: every scene it shows exists (\(scenes.count) uses)", unknown.isEmpty, unknown.joined(separator: ", "))
        // A scene can follow the music inside Play Demo: Techno Bars flashes on rows 7, 15, 23 ... of
        // the music it is given (KOE.C `waitborder`), once per row change, and the flash then dies away.
        var bars = TechnoBarsModel()
        var flashes: [Int] = []
        for row in [5, 6, 7, 7, 8, 14, 15] {
            bars.musicRow = row
            bars.tick()
            flashes.append(bars.shownFlash)
        }
        check("Play Demo: Techno Bars flashes on the music rows it is given (7, 15, ...), not on its own estimate",
              flashes == [0, 0, 15, 14, 13, 12, 15], "\(flashes)")
        // And Play Demo does give it the music: run the demo silently into the techno bars.
        if let device = MTLCreateSystemDefaultDevice(),
           let run = try? DemoRunScene(device: device, pixelFormat: Renderer.pixelFormat, music: SilentMusic()) {
            var agreed = 0, compared = 0
            for _ in 0..<14_500 {
                run.tick()
                if let techno = run.sceneShowing as? TechnoBarsScene {
                    compared += 1
                    // Given before the step, so at most one row behind (63 is one row behind 0). On the
                    // step the scene appears it has not been updated yet.
                    if let given = techno.model.musicRow {
                        if [0, 1].contains((run.musicRow - given + 64) % 64) { agreed += 1 }
                    } else if compared == 1 { agreed += 1 }
                }
            }
            check("Play Demo: a scene is told the music's position each step (Techno Bars, \(compared) steps)",
                  compared > 1000 && agreed == compared, "\(agreed) of \(compared)")
        }
        // The title and end pictures: fully in after 161 and 163 steps (as the demo script counts), and
        // inside Play Demo the end picture holds until "music plus" goes above -16, then fades to black.
        var title = FadingPictureModel(timing: FadingPictureScene.titleTiming)
        for _ in 0..<160 { title.tick() }
        let titleAlmost = title.fade().keep
        title.tick()
        var end = FadingPictureModel(timing: FadingPictureScene.endTiming)
        end.musicPlus = -32
        for _ in 0..<163 { end.tick() }
        let holding = end.phase
        for _ in 0..<2000 { end.tick() }
        let stillHolding = end.phase
        end.musicPlus = -10
        end.tick()
        check("Play Demo: the title picture is fully in after 161 steps, the end picture after 163, then holds for the music cue and fades out",
              titleAlmost == 128 && title.phase == .end && holding == .hold && stillHolding == .hold && end.phase == .fadeOut,
              "\(titleAlmost) \(title.phase) \(holding) \(stillHolding) \(end.phase)")
        // The troll: from the music cue, the scroll takes 53 refreshes and the shake 50 (as in the timing
        // research, tools/demo_timeline.py's "53 + 50"); the flash is 45 on the shake's second refresh.
        var troll = TrollModel()
        troll.musicCue = true
        var scrollSteps = 0, shakeSteps = 0, firstFlash = -1
        for _ in 0..<400 {
            troll.tick()
            if troll.phase == .scroll { scrollSteps += 1 }
            if troll.phase == .shake { shakeSteps += 1; if firstFlash < 0 && troll.flash > 0 { firstFlash = troll.flash } }
        }
        check("Play Demo: the troll scrolls in over 53 refreshes, then shakes for 50 with a flash from 45",
              scrollSteps == 53 && shakeSteps == 50 && firstFlash == 45 && troll.xpos == 320,
              "\(scrollSteps) + \(shakeSteps), flash \(firstFlash), ends at \(troll.xpos)")
        // The switch-off: bands 32, 26 ... 3 (each 5/6 of the last), one line at refresh 14, a dot from 61,
        // 191 refreshes in all (121 + the original's sleep(1)).
        let line = SwitchOffModel.frame(at: 14), dot = SwitchOffModel.frame(at: 61)
        check("Play Demo: the screen switch-off collapses through bands 32, 26, 21, 17, 14, 11, 9, 7, 5, 4, 3 to a line and a dot, 191 refreshes",
              SwitchOffModel.bands == [32, 26, 21, 17, 14, 11, 9, 7, 5, 4, 3] && SwitchOffModel.length == 191
                && line.rows.filter { $0 >= 0 }.count == 2 && line.rows[200] == 133 && dot.dot == 63
                && SwitchOffModel.frame(at: 1).colour0 == 63, "\(SwitchOffModel.bands)")
        // SHUTDOWN.C waits once more (a third dis_waitb) after the quarter squash and before the band loop,
        // whose first wait comes before band 32: so refresh 3 still shows the quarter squash, band 32 is at
        // refresh 4 and band 4 at 13. Band 3 is made after the 14th wait and at once cut to the line, so it
        // never shows. (Found in the code review of 2026-11-24: the bands had been one refresh early.)
        func bandHeight(_ s: Int) -> Float { SwitchOffModel.frame(at: s).band.y }
        check("Play Demo: the switch-off's quarter squash shows for refreshes 2 and 3, bands 32 ... 4 at refreshes 4 ... 13 (SHUTDOWN.C's waits)",
              SwitchOffModel.frame(at: 3) == SwitchOffModel.frame(at: 2) && bandHeight(4) == 64 && bandHeight(13) == 8
                && SwitchOffModel.frame(at: 4).whiteFade == 31 && SwitchOffModel.frame(at: 13).whiteFade == 59,
              "refresh 3 band \(bandHeight(3)), 4: \(bandHeight(4)), 13: \(bandHeight(13))")
        // The end scroller (released text and font): a row every 2 refreshes, lines centred by the original's
        // rule, "[nn" = nn blank rows, "%" = back to the first line; the font has Y, Z and ä.
        if var scroller = try? EndScrollerModel.load() {
            let font = scroller.font
            let glyphs = [UInt8]("YZa".utf8) + [0x84]
            let firstLine = scroller.lines[0]
            let fresh = scroller
            for _ in 0..<(2 * 30) { scroller.tick() }
            let rows = scroller.rowsDrawn
            // The newest row (the 30th) is the bottom one, so row 5 of the first line is 24 rows above it.
            let screen = scroller.screen
            let r = EndScrollerModel.height - 1 - 24
            let firstInk = (0..<EndScrollerModel.width).first { screen[r * EndScrollerModel.width + $0] != 0 }
            // Find a gap line and the loop line, and check how many rows they take.
            let gapIndex = scroller.lines.firstIndex { $0.first == UInt8(ascii: "[") }
            let loopIndex = scroller.lines.firstIndex { $0.first == UInt8(ascii: "%") }
            var looped = false
            var probe = fresh
            var seenLoop = false
            for _ in 0..<(2 * 40_000) {
                probe.tick()
                if let last = probe.placed.last, last.line == loopIndex { seenLoop = true }
                if seenLoop, let last = probe.placed.last, last.line == 0 { looped = true; break }
            }
            check("End scroller: a row every 2 refreshes, the first line centred as the original did, the font has Y, Z, ä; the text loops at its % line",
                  rows == 30 && glyphs.allSatisfy { font.width[Int($0)] > 0 } && gapIndex != nil && loopIndex != nil && looped
                    && firstInk.map { $0 >= font.lineStart(firstLine) } == true,
                  "rows \(rows), first ink \(firstInk ?? -1) from \(font.lineStart(firstLine)), loop line \(loopIndex ?? -1), looped \(looped)")
            if let gapIndex {
                var gap = fresh
                while gap.placed.last.map({ $0.line != gapIndex - 1 }) ?? true { gap.tick() }
                // The line before the gap started; it takes 25 rows, then the gap, then the next line.
                let before = gap.placed.last!.firstRow
                while gap.placed.last!.firstRow == before { gap.tick() }
                let next = gap.placed.last!
                let height = Int(String(bytes: gap.lines[gapIndex][1...2], encoding: .ascii) ?? "") ?? -1
                check("End scroller: a \"[nn\" line is nn blank rows (line \(gapIndex): \(height))",
                      next.line == gapIndex + 1 && next.firstRow - before == EndScrollerFont.rows + height,
                      "next line \(next.line) after \(next.firstRow - before) rows")
            }
        } else {
            check("End scroller: its text and font are there", false, "")
        }
        let missing = DemoScript.pictures.filter { DemoPictures.url($0) == nil }
        check("Play Demo: every picture it shows is there (\(DemoScript.pictures.count) pictures)",
              missing.isEmpty, missing.joined(separator: ", "))
    }

    /// The song position Play Demo waits on (added 2026-11-24 with Play Demo).
    private static func musicPosition(_ check: (String, Bool, String) -> Void) {
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

    // MARK: - The scene list

    private static func catalogue(_ check: (String, Bool, String) -> Void) {
        let all = SceneCatalog.all
        // The self-test's scene loops pass without checking anything if the list is empty, and
        // look scenes up by id.
        check("Core: the scene list is not empty and every scene id is different",
              !all.isEmpty && Set(all.map(\.id)).count == all.count && !all.contains { $0.id.isEmpty }, "\(all.count) scenes")
        // The checkpoint loop only ever steps forwards, so a list out of order would be compared at
        // the wrong step without saying so; and a scene with no checkpoints would not be compared at all.
        let badOrder = all.filter { entry in
            entry.checkpoints.isEmpty || entry.checkpoints[0] < 0
                || zip(entry.checkpoints, entry.checkpoints.dropFirst()).contains { $0 >= $1 }
        }
        check("Core: every scene has checkpoints, in rising order", badOrder.isEmpty,
              badOrder.map(\.id).joined(separator: ", "))
        let badSize = all.filter { entry in
            let size = entry.canvasSize
            return size.x < 1 || size.y < 1 || size.x != size.x.rounded() || size.y != size.y.rounded() || entry.thumbnailStep < 0
        }
        check("Core: every scene's canvas is a whole number of pixels and its list-picture step is not negative",
              badSize.isEmpty, badSize.map(\.id).joined(separator: ", "))
    }

    // MARK: - The clock

    private static func clock(_ check: (String, Bool, String) -> Void) {
        // Ten seconds on displays of different speeds: 700 steps each time (give or take one for
        // rounding), never more steps in one frame than the display's speed calls for, and the
        // "how far into the next step" number always from 0 up to but not including 1.
        var faults: [String] = []
        for rate in [50.0, 60.0, 70.0, 100.0, 120.0, 144.0] {
            var clock = StepClock()
            var total = 0, most = 0
            var alphaOK = true, evenOK = true
            var position = 0.0
            for _ in 0..<Int(rate * 10) {
                let due = clock.advance(by: 1 / rate)
                total += due.steps
                most = max(most, due.steps)
                if !(due.alpha >= 0 && due.alpha < 1) { alphaOK = false }
                // Steps done plus the fraction must move on by the same amount every frame:
                // that is what makes the modern look's motion even.
                let now = Double(total) + Double(due.alpha)
                if abs(now - position - 70 / rate) > 0.0001 { evenOK = false }
                position = now
            }
            if abs(total - 700) > 1 || most > Int((70 / rate).rounded(.up)) || !alphaOK || !evenOK {
                faults.append("\(Int(rate)) Hz: \(total) steps, \(most) at most in a frame, alpha ok \(alphaOK), even \(evenOK)")
            }
        }
        check("Core clock: 70 steps a second, evenly, on 50 to 144 Hz displays", faults.isEmpty, faults.joined(separator: "; "))

        // Found by the review: the fraction could round up to exactly 1.
        var nearly = StepClock()
        let justUnder = nearly.advance(by: StepClock.step.nextDown)
        check("Core clock: the fraction of a step never reaches 1", justUnder.steps == 0 && justUnder.alpha < 1,
              "\(justUnder.steps) steps, fraction \(justUnder.alpha)")

        var paused = StepClock()
        _ = paused.advance(by: 0.005)
        let afterPause = paused.advance(by: 3600)
        var backwards = StepClock()
        let negative = backwards.advance(by: -1)
        check("Core clock: after a long pause it catches up on a quarter of a second only, and never runs backwards",
              afterPause.steps == 17 && afterPause.alpha >= 0 && afterPause.alpha < 1
                  && negative.steps == 0 && negative.alpha == 0 && backwards.owed == 0,
              "\(afterPause.steps) steps after an hour's pause")
    }

    // MARK: - The 4:3 picture area

    private static func letterbox(_ check: (String, Bool, String) -> Void) {
        func box(_ width: Double, _ height: Double) -> [Double] {
            let b = Renderer.letterbox(width: width, height: height)
            return [b.originX, b.originY, b.width, b.height]
        }
        check("Core: the picture area is the largest centred 4:3 rectangle (exact fit, wide window, tall window, no window)",
              box(960, 720) == [0, 0, 960, 720] && box(1920, 1080) == [240, 0, 1440, 1080]
                  && box(1000, 2000) == [0, 625, 1000, 750] && box(0, 0) == [0, 0, 0, 0],
              "\(box(1920, 1080)) \(box(1000, 2000))")
    }

    // MARK: - Command lines

    private static func commandLine(_ check: (String, Bool, String) -> Void) {
        func options(_ words: String) -> StartupOptions {
            StartupOptions(arguments: ["SRMetal"] + words.split(separator: " ").map(String.init))
        }
        let good = options("--scene plasma --look classic --sidebar hidden")
        let system = options("-NSDocumentRevisionsDebugMode YES -AppleLanguages (en)")
        check("App: start-up options are understood, and macOS's own single-dash options are left alone",
              good.problems.isEmpty && good.look == .classic && good.sidebarHidden
                  && good.sceneIndex == SceneCatalog.all.firstIndex(where: { $0.id == "plasma" })
                  && options("").problems.isEmpty && options("").look == nil && options("").sceneIndex == nil
                  && system.problems.isEmpty,
              (good.problems + system.problems).joined(separator: "; "))
        // Found by the review: all of these used to be ignored without a word.
        let bad = ["--scene plasmacube", "--look 1993", "--scene", "--look --scene plasma", "--sidebar gone", "--selftests"]
        let accepted = bad.filter { options($0).problems.isEmpty }
        check("App: mistyped start-up options are reported, not ignored", accepted.isEmpty,
              accepted.joined(separator: "; "))

        func snapshot(_ words: String) -> Snapshot.Request? {
            Snapshot.request(from: ["SRMetal", "--snapshot"] + words.split(separator: " ").map(String.init))
        }
        let request = snapshot("rings classic 300 out.png")
        // Found by the review: a negative step crashed the program.
        let refused = ["rings classic -5 out.png", "rings classic 3.5 out.png", "rings classic 300",
                       "nothing classic 300 out.png", "rings 1993 300 out.png", "rings modern 300 out.png half",
                       "rings modern 300 out.png nan"].filter { snapshot($0) != nil }
        check("App: --snapshot reads a good command line and refuses bad ones (negative step, unknown scene or look, bad blend)",
              request?.entry.id == "rings" && request?.look == .classic && request?.step == 300
                  && request?.output == "out.png" && request?.blend == 0
                  && snapshot("rings modern 0 out.png 0.5")?.blend == 0.5 && snapshot("rings modern 0 out.png 7")?.blend == 1
                  && refused.isEmpty,
              refused.joined(separator: "; "))

        func range(_ words: [String]) -> String {
            switch MotionCheck.stepRange(from: words) {
            case .none: return "refused"
            case .some(.none): return "whole loop"
            case .some(.some(let steps)): return "\(steps.first)...\(steps.last)"
            }
        }
        // Found by the review: one number, a mistyped number or a backwards range used to be
        // dropped and the whole loop checked instead; a negative number crashed.
        let ranges = [range([]), range(["10", "20"]), range(["7", "7"]), range(["10"]), range(["1O", "20"]),
                      range(["20", "10"]), range(["-5", "10"]), range(["1", "2", "3"])]
        check("App: --motion-check reads its step range and refuses a malformed one",
              ranges == ["whole loop", "10...20", "7...7", "refused", "refused", "refused", "refused", "refused"],
              ranges.joined(separator: ", "))
    }

    // MARK: - 3D helpers

    private static func math3D(_ check: (String, Bool, String) -> Void) {
        func close(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ tolerance: Float = 0.001) -> Bool {
            simd_reduce_max(simd_abs(a - b)) <= tolerance
        }
        func gap(_ a: simd_float3x3, _ b: simd_float3x3) -> Float {
            (0..<3).map { simd_reduce_max(simd_abs(a[$0] - b[$0])) }.max() ?? 0
        }
        let focal = SIMD2<Float>(200, 160), centre = SIMD2<Float>(150, 90), canvas = SIMD2<Float>(320, 200)
        let matrix = Math3D.perspective(focal: focal, centre: centre, canvasSize: canvas, near: 50, far: 1000)
        let point = SIMD3<Float>(10, -20, 100)
        // By hand: centre + focal * (X, Y) / Z = (150 + 200 * 0.1, 90 + 160 * -0.2) = (170, 58).
        let onCanvas = Math3D.project(point, with: matrix, targetSize: canvas)
        let onScreen = Math3D.project(point, with: matrix, targetSize: SIMD2(960, 720))
        func depth(_ m: simd_float4x4, _ z: Float) -> Float {
            let clip = m * SIMD4<Float>(0, 0, z, 1)
            return clip.z / clip.w
        }
        let nearOverZ = Math3D.perspectiveNearOverZ(focal: focal, centre: centre, canvasSize: canvas, near: 50)
        check("Math3D: the perspective matrices put a point at centre + focal * (x, y) / z, y downwards, with depth as documented",
              close(onCanvas, SIMD2(170, 58)) && close(onScreen, SIMD2(510, 208.8), 0.01)
                  && close(Math3D.project(point, with: nearOverZ, targetSize: canvas), SIMD2(170, 58))
                  && close(Math3D.canvasPosition(point, focal: focal, centre: centre, near: 50), SIMD2(170, 58))
                  && abs(depth(matrix, 50)) < 1e-5 && abs(depth(matrix, 1000) - 1) < 1e-5
                  && abs(depth(nearOverZ, 50) - 1) < 1e-6 && abs(depth(nearOverZ, 500) - 0.1) < 1e-6,
              "\(onCanvas) \(onScreen)")

        // A quarter turn about each axis, by hand: x turns y into z, y turns z into x, z turns x into y.
        let quarter = Float.pi / 2
        func turned(_ m: simd_float3x3, _ v: SIMD3<Float>, _ expected: SIMD3<Float>) -> Bool {
            simd_reduce_max(simd_abs(m * v - expected)) < 1e-6
        }
        let moved = Math3D.transform(rotation: Math3D.rotationZ(quarter), translation: SIMD3(5, 6, 7)) * SIMD4<Float>(1, 0, 0, 1)
        // The original's combined matrix: turns about y, then x, then z, each the opposite way
        // round from the three single-axis helpers. (Worked out by trying every order.)
        let (x, y, z): (Float, Float, Float) = (0.3, 0.7, -1.1)
        let combined = Math3D.rotationYXZ(x: x, y: y, z: z)
        let product = Math3D.rotationY(-y) * Math3D.rotationX(-x) * Math3D.rotationZ(-z)
        check("Math3D: turns go the documented way, turn-then-move works, and the original's combined turn is rY * rX * rZ",
              turned(Math3D.rotationX(quarter), SIMD3(0, 1, 0), SIMD3(0, 0, 1))
                  && turned(Math3D.rotationY(quarter), SIMD3(0, 0, 1), SIMD3(1, 0, 0))
                  && turned(Math3D.rotationZ(quarter), SIMD3(1, 0, 0), SIMD3(0, 1, 0))
                  && simd_reduce_max(simd_abs(moved - SIMD4<Float>(5, 7, 7, 1))) < 1e-6
                  && gap(combined, product) < 1e-6 && abs(simd_determinant(combined) - 1) < 1e-5,
              "combined turn differs from the product by \(gap(combined, product))")

        // The 3D "does this face the camera" test and the 2D one used after projecting must agree,
        // for shapes in front of the camera. Fixed made-up triangles (no random numbers: a
        // self-test must do the same thing every time).
        var disagreements = 0, facing = 0
        var seed: UInt32 = 12345
        func next(_ low: Float, _ high: Float) -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return low + (high - low) * Float(seed >> 8) / Float(1 << 24)
        }
        for _ in 0..<500 {
            let p = (0..<3).map { _ in SIMD3<Float>(next(-50, 50), next(-50, 50), next(60, 200)) }
            let q = p.map { Math3D.canvasPosition($0, focal: focal, centre: centre, near: 50) }
            let in3D = Math3D.facesCamera(p[0], p[1], p[2])
            if in3D { facing += 1 }
            if in3D != (Math3D.screenFacing(q[0], q[1], q[2]) >= 0) { disagreements += 1 }
        }
        check("Math3D: the 3D and the on-screen 'faces the camera' tests agree on 500 triangles",
              disagreements == 0 && facing > 100 && facing < 400, "\(disagreements) disagree, \(facing) face the camera")
    }

    // MARK: - Smooth triangles

    private static func smoothTriangleGeometry(_ check: (String, Bool, String) -> Void) {
        typealias Vertex = SmoothTriangles.Vertex
        // The shader reads the vertex list as { float2; float3; float4 }, which Metal lays out at
        // bytes 0, 16 and 32 of a 48-byte record. Swift must agree or every triangle is garbage.
        check("SmoothTriangles: the vertex record is laid out as the shader reads it (48 bytes; fields at 0, 16, 32)",
              MemoryLayout<Vertex>.stride == 48 && MemoryLayout<Vertex>.offset(of: \.position) == 0
                  && MemoryLayout<Vertex>.offset(of: \.edges) == 16 && MemoryLayout<Vertex>.offset(of: \.colour) == 32,
              "stride \(MemoryLayout<Vertex>.stride)")

        let colour = SIMD4<Float>(1, 1, 1, 1)
        var none: [Vertex] = []
        SmoothTriangles.append(SIMD2(10, 10), SIMD2(20, 20), SIMD2(30, 30), colour: colour, to: &none)   // a line
        SmoothTriangles.append(SIMD2(10, 10), SIMD2(10, 10), SIMD2(30, 5), colour: colour, to: &none)    // two corners the same
        SmoothTriangles.append(SIMD2(7, 7), SIMD2(7, 7), SIMD2(7, 7), colour: colour, to: &none)         // a point
        check("SmoothTriangles: a triangle with no area adds nothing (and no not-a-number values)", none.isEmpty,
              "\(none.count) corners added")

        // An ordinary triangle, corners given both ways round. Each corner handed to the chip must
        // carry its true distances to the three edges (worked out here a different way: the area
        // of the triangle it makes with the edge, divided by the edge's length), and the enlarged
        // triangle must clear the true one by a full pixel all round.
        let a = SIMD2<Float>(20, 15), b = SIMD2<Float>(90, 30), c = SIMD2<Float>(40, 80)
        var oneWay: [Vertex] = [], otherWay: [Vertex] = []
        SmoothTriangles.append(a, b, c, colour: colour, to: &oneWay)
        SmoothTriangles.append(a, c, b, colour: colour, to: &otherWay)
        func cross(_ u: SIMD2<Float>, _ v: SIMD2<Float>) -> Float { u.x * v.y - u.y * v.x }
        func inside(_ p: SIMD2<Float>, _ from: SIMD2<Float>, _ to: SIMD2<Float>, _ third: SIMD2<Float>) -> Float {
            // Positive on the side of the line from...to where `third` is.
            let side: Float = cross(to - from, third - from) >= 0 ? 1 : -1
            return side * cross(to - from, p - from) / simd_length(to - from)
        }
        var worstDistance: Float = 0, leastClearance = Float.infinity
        for list in [oneWay, otherWay] where list.count == 3 {
            // The edges in the order the list uses: the list's corners are the true corners pushed
            // outwards, so the true corner nearest each one tells which is which.
            let corners = list.map { vertex in [a, b, c].min { simd_distance($0, vertex.position) < simd_distance($1, vertex.position) }! }
            for vertex in list {
                for edge in 0..<3 {
                    let expected = inside(vertex.position, corners[edge], corners[(edge + 1) % 3], corners[(edge + 2) % 3])
                    worstDistance = max(worstDistance, abs(vertex.edges[edge] - expected))
                }
            }
            for edge in 0..<3 {
                let from = list[edge].position, to = list[(edge + 1) % 3].position, third = list[(edge + 2) % 3].position
                for corner in [a, b, c] { leastClearance = min(leastClearance, inside(corner, from, to, third)) }
            }
        }
        check("SmoothTriangles: corners carry their true edge distances, and the drawn triangle clears the true one by a pixel, either way round",
              oneWay.count == 3 && otherWay.count == 3 && worstDistance < 0.001 && leastClearance > 0.99 && leastClearance < 1.01,
              "distances off by at most \(worstDistance), clearance \(leastClearance)")
    }

    private static func smoothTrianglesDrawn(_ check: (String, Bool, String) -> Void, device: MTLDevice, queue: MTLCommandQueue) throws {
        // A 32x32 square made of two triangles that share its diagonal, a quarter of a pixel off
        // the pixel grid, added together on a black 64x64 picture. Inside, and all along the
        // shared diagonal, the colour must be exactly the square's (no seam, no double-bright
        // line); the total light must be the square's area (edges faded in proportion); and
        // nothing may be drawn away from it.
        let size = 64
        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + SmoothTriangles.shaderSource)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("smooth_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("smooth_fragment", in: library)
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = Renderer.pixelFormat
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .one
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        var list: [SmoothTriangles.Vertex] = []
        let colour = SIMD4<Float>(0.2, 0.6, 1, 1)
        let low: Float = 8.25, high: Float = 40.25
        SmoothTriangles.append(SIMD2(low, low), SIMD2(high, low), SIMD2(high, high), colour: colour, to: &list)
        SmoothTriangles.append(SIMD2(low, low), SIMD2(high, high), SIMD2(low, high), colour: colour, to: &list)
        let pixels = try draw(width: size, height: size, device: device, queue: queue) { encoder in
            var target = SIMD2<Float>(Float(size), Float(size))
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(list, length: MemoryLayout<SmoothTriangles.Vertex>.stride * list.count, index: 0)
            encoder.setVertexBytes(&target, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: list.count)
        }
        func pixel(_ x: Int, _ y: Int) -> [Int] {   // red, green, blue
            let at = (y * size + x) * 4
            return [Int(pixels[at + 2]), Int(pixels[at + 1]), Int(pixels[at])]
        }
        var wrongInside = 0, strayOutside = 0, blue = 0
        for y in 0..<size {
            for x in 0..<size {
                let p = pixel(x, y)
                blue += p[2]
                if (10...38).contains(x) && (10...38).contains(y) {
                    if abs(p[0] - 51) > 1 || abs(p[1] - 153) > 1 || abs(p[2] - 255) > 1 { wrongInside += 1 }
                } else if x < 7 || x > 41 || y < 7 || y > 41 {
                    if p != [0, 0, 0] { strayOutside += 1 }
                }
            }
        }
        let area = Double(blue) / 255
        check("SmoothTriangles drawn: two triangles sharing an edge make one even square with faded edges and the right area",
              list.count == 6 && wrongInside == 0 && strayOutside == 0 && abs(area - 1024) < 10,
              "\(wrongInside) wrong inside, \(strayOutside) stray, area \(String(format: "%.1f", area)) of 1024")
    }

    // MARK: - The palette picture

    private static func indexedCanvas(_ check: (String, Bool, String) -> Void, device: MTLDevice, queue: MTLCommandQueue) throws {
        // A tiny 4x2 picture (deliberately not 320x200) shown twice its size, with a full
        // 256-colour palette in which every colour is different.
        let canvas = try IndexedCanvas(device: device, pixelFormat: Renderer.pixelFormat, width: 4, height: 2)
        let full: [SIMD4<Float>] = (0..<256).map { (i: Int) -> SIMD4<Float> in
            let red = Float(i) / 255, green = Float(255 - i) / 255, blue = Float((i * 7) % 256) / 255
            return SIMD4<Float>(red, green, blue, 1)
        }
        func bytes(_ index: UInt8) -> [Int] { [Int(index), 255 - Int(index), (Int(index) * 7) % 256] }
        let first: [UInt8] = [0, 1, 2, 255, 100, 200, 50, 254]
        let second: [UInt8] = [255, 3, 2, 0, 200, 100, 51, 9]

        /// How many of the 8x4 drawn pixels are not the colour `expected` gives for their canvas pixel.
        func wrong(_ pixels: [UInt8], _ expected: (Int) -> [Int]) -> Int {
            var count = 0
            for y in 0..<4 {
                for x in 0..<8 {
                    let at = (y * 8 + x) * 4
                    let want = expected((y / 2) * 4 + x / 2)
                    if abs(Int(pixels[at + 2]) - want[0]) > 1 || abs(Int(pixels[at + 1]) - want[1]) > 1
                        || abs(Int(pixels[at]) - want[2]) > 1 { count += 1 }
                }
            }
            return count
        }
        let single = try draw(width: 8, height: 4, device: device, queue: queue) {
            canvas.draw(into: $0, indices: first, palette: full)
        }
        let singleWrong = wrong(single) { bytes(first[$0]) }
        check("IndexedCanvas: each pixel shows its palette colour, top row at the top, up to colour number 255",
              singleWrong == 0, "\(singleWrong) of 32 pixels wrong")

        let pair = try draw(width: 8, height: 4, device: device, queue: queue) {
            canvas.draw(into: $0, indices: first, blendedWith: second, palette: full)
        }
        let pairWrong = wrong(pair) { i in zip(bytes(first[i]), bytes(second[i])).map { ($0 + $1 + 1) / 2 } }
        check("IndexedCanvas: two pictures blended show the even mix of their colours", pairWrong == 0,
              "\(pairWrong) of 32 pixels wrong")

        // Found by the review. The canvas keeps three palette buffers and uses them in turn. After
        // the full palette has been through all three, a SHORT palette must not let colour numbers
        // beyond its end show the old palette's colours; and an empty palette must not crash.
        _ = try draw(width: 8, height: 4, device: device, queue: queue) { canvas.draw(into: $0, indices: first, palette: full) }
        let short = try draw(width: 8, height: 4, device: device, queue: queue) {
            canvas.draw(into: $0, indices: first, palette: [SIMD4(1, 0, 0, 1), SIMD4(0, 1, 0, 1)])
        }
        let shortWrong = wrong(short) { i in first[i] == 0 ? [255, 0, 0] : first[i] == 1 ? [0, 255, 0] : [0, 0, 0] }
        var emptyWrong = 0
        for _ in 0..<3 {
            let empty = try draw(width: 8, height: 4, device: device, queue: queue) { canvas.draw(into: $0, indices: first, palette: []) }
            emptyWrong += wrong(empty) { _ in [0, 0, 0] }
        }
        check("IndexedCanvas: colour numbers beyond a short (or empty) palette show black, not an earlier frame's colours",
              shortWrong == 0 && emptyWrong == 0, "\(shortWrong) wrong with 2 colours, \(emptyWrong) with none")
    }

    // MARK: - Pictures without a window (also what the sidebar does)

    private static func snapshots(_ check: (String, Bool, String) -> Void) throws {
        func bytes(_ image: CGImage) -> [UInt8] { image.dataProvider?.data.map { [UInt8]($0 as Data) } ?? [] }

        // The 1993 look scaled up to 960x720, for a 320x200 scene and a 320x400 one: every picture
        // pixel must be the canvas pixel it lies over (canvas rows and columns found here by
        // exact fractions rather than the renderer's whole-number sum).
        var faults: [String] = []
        for id in ["dot-tunnel", "plasma"] {
            guard let entry = SceneCatalog.all.first(where: { $0.id == id }),
                  let device = MTLCreateSystemDefaultDevice() else { faults.append("\(id) missing"); continue }
            let picture = bytes(try Snapshot.render(entry: entry, look: .classic, step: entry.thumbnailStep, width: 960, height: 720))
            let scene = try entry.make(device, Renderer.pixelFormat)
            for _ in 0..<entry.thumbnailStep { scene.tick() }
            let reference = scene.classicReferenceFrame()
            let width = Int(entry.canvasSize.x), height = Int(entry.canvasSize.y)
            guard picture.count == 960 * 720 * 4, reference.count == width * height * 3 else { faults.append("\(id) wrong size"); continue }
            var wrong = 0, lit = 0
            for y in 0..<720 {
                let row = Int((Double(y) + 0.5) / 720 * Double(height))
                for x in 0..<960 {
                    let from = (row * width + Int((Double(x) + 0.5) / 960 * Double(width))) * 3
                    let at = (y * 960 + x) * 4
                    if reference[from] != 0 || reference[from + 1] != 0 || reference[from + 2] != 0 { lit += 1 }
                    if abs(Int(picture[at + 2]) - Int(reference[from])) > 1 || abs(Int(picture[at + 1]) - Int(reference[from + 1])) > 1
                        || abs(Int(picture[at]) - Int(reference[from + 2])) > 1 { wrong += 1 }
                }
            }
            if wrong > 0 || lit < 1000 { faults.append("\(id): \(wrong) wrong, \(lit) lit") }
        }
        check("Snapshot: the 1993 look scaled up shows the right canvas pixel everywhere (320x200 and 320x400 canvases)",
              faults.isEmpty, faults.joined(separator: "; "))

        // The sidebar draws every scene's small picture on a background thread while the window's
        // scene runs on the main thread. Do the same job on two threads at once: every picture
        // must come out, must show something, and must be identical on both threads. (If scenes
        // shared something they change while running, the two threads would disturb each other.)
        func listPictures() -> [String: [UInt8]] {
            var result: [String: [UInt8]] = [:]
            for entry in SceneCatalog.all {
                if let image = try? Snapshot.render(entry: entry, look: .modern, step: entry.thumbnailStep,
                                                    width: Thumbnails.width, height: Thumbnails.height) {
                    result[entry.id] = bytes(image)
                }
            }
            return result
        }
        var elsewhere: [String: [UInt8]] = [:]
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            elsewhere = listPictures()
            done.signal()
        }
        let here = listPictures()
        done.wait()
        var listFaults: [String] = []
        for entry in SceneCatalog.all {
            guard let a = here[entry.id], let b = elsewhere[entry.id], a.count == Thumbnails.width * Thumbnails.height * 4 else {
                listFaults.append("\(entry.id) not drawn")
                continue
            }
            var litBytes = 0
            for i in stride(from: 0, to: a.count, by: 4) where a[i] != 0 || a[i + 1] != 0 || a[i + 2] != 0 { litBytes += 1 }
            if litBytes < 50 { listFaults.append("\(entry.id) is blank") }
            if a != b { listFaults.append("\(entry.id) differs between threads") }
        }
        check("Sidebar pictures: every scene's draws, shows something, and is identical when two threads draw them at once",
              listFaults.isEmpty, listFaults.joined(separator: "; "))
    }

    // MARK: - Helper

    /// Draws into a fresh black picture and returns its pixels: blue, green, red, alpha for each, top row first.
    private static func draw(width: Int, height: Int, device: MTLDevice, queue: MTLCommandQueue,
                             _ body: (MTLRenderCommandEncoder) -> Void) throws -> [UInt8] {
        guard let texture = Renderer.makeClassicTexture(device: device, canvasSize: SIMD2(Float(width), Float(height))),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: Renderer.clearPass(into: texture))
        else { throw Snapshot.Failure.couldNotDraw }
        body(encoder)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }
}
