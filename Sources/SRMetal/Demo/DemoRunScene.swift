import AppKit
import CoreText
import MetalKit

/// Finds the demo's pictures: the original pictures at their own size, exported from the 1993 demo
/// (`artwork/original/rgb`). `./build.sh` copies them into the app as `Resources/Artwork`; run some
/// other way, the `artwork` folder next to or above the program is used.
enum DemoPictures {
    static let folder = DataFolder.find(resource: "Artwork", devPath: "artwork/original/rgb", marker: "04-title.png")

    /// The picture's file, or nil if it is not there.
    static func url(_ name: String) -> URL? {
        guard let url = folder?.appendingPathComponent(name + ".png"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}

enum DemoError: Error, CustomStringConvertible {
    case noSuchStart(String)
    var description: String {
        switch self {
        case .noSuchStart(let what): return "Play Demo never reaches \(what)"
        }
    }
}

/// The music player as the sequencer's music source.
final class LiveDemoMusic: DemoMusicSource {
    let player: MusicPlayer
    /// The sound to start songs in (it follows the look).
    let look: () -> Look

    init(player: MusicPlayer, look: @escaping () -> Look) {
        self.player = player
        self.look = look
    }

    func play(_ song: Song, fromOrder order: Int, skipping seconds: Double) {
        do {
            try player.play(song, look: look(), fromOrder: order, skipping: seconds)
        } catch {
            NSLog("SR Metal: Play Demo could not start \(song.rawValue): \(error)")
        }
    }

    var position: MusicPosition { player.position }
    var orderList: [Int] { player.orderList }
}

/// Play Demo: the whole demo, part after part, following `DemoScript` with the original music.
/// To the window it is one more scene; inside, it shows whichever scene or picture the script asks for.
final class DemoRunScene: DemoScene {
    /// Play Demo's id on the command line (`--scene play-demo`, `--snapshot play-demo ...`).
    static let id = "play-demo"

    /// Play Demo as a scene the window or a command can show. Not in `SceneCatalog.all`: it is not in
    /// the sidebar or the per-scene checks. `configure` sets up each new run (the app's hooks).
    static func entry(music: @escaping () -> DemoMusicSource, start: @escaping () -> DemoStart? = { nil },
                      configure: @escaping (DemoRunScene) -> Void = { _ in }) -> SceneEntry {
        SceneEntry(id: id, title: "Play Demo", credit: "Future Crew", canvasSize: SIMD2(320, 200),
                   checkpoints: [], thumbnailStep: 0,
                   make: { device, format in
                       let scene = try DemoRunScene(device: device, pixelFormat: format, music: music(), from: start())
                       scene.startProvider = start
                       configure(scene)
                       return scene
                   })
    }

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let music: DemoMusicSource
    /// Called with each part's name as it starts.
    var onPart: ((String) -> Void)?
    /// Whether each part change is written to the log (the running app; not checks or snapshots).
    var logsParts = false

    private var sequencer: DemoSequencer
    private enum Shown {
        case scene(DemoScene, SIMD2<Float>)
        case picture(String)
        case card(String)
        case black
    }
    private var shown = Shown.black
    private var partsStarted = 0

    private let loader: MTKTextureLoader

    /// Pictures and title cards are shown through the shared toolkit (`PictureLayer`). Only the last
    /// picture shown is kept, and its Modern-look version (up to 2560x3200, made when first drawn) only
    /// while it shows.
    private let pictureLayer: PictureLayer
    private var picture: (name: String, picture: ScenePicture)?
    private var cards: [String: ScenePicture] = [:]

    /// `start`: where to begin, if not at the start. The script is run silently up to there (quickly,
    /// drawing nothing), then carries on with `music`, started at the same place to the sample.
    init(device: MTLDevice, pixelFormat: MTLPixelFormat, music: DemoMusicSource, from start: DemoStart? = nil) throws {
        self.device = device
        self.pixelFormat = pixelFormat
        self.music = music
        self.sequencer = DemoSequencer(music: music)
        self.loader = MTKTextureLoader(device: device)
        self.pictureLayer = try PictureLayer.shared(device: device, pixelFormat: pixelFormat)
        self.start = start

        hookUp()
        if let start { try resume(at: start) }
    }

    /// Where this run began (nil: the start of the demo).
    private(set) var start: DemoStart?
    /// Asked again on each restart, so a restart can begin somewhere else (the app's "Play Demo from").
    var startProvider: (() -> DemoStart?)?

    private func resume(at start: DemoStart) throws {
        guard let ahead = DemoSequencer.fastForward(to: start) else { throw DemoError.noSuchStart("\(start)") }
        sequencer = DemoSequencer(continuing: ahead.sequencer, music: music)
        hookUp()
        show(ahead.visual, musicAtShow: ahead.musicAtShow)
        partsStarted = sequencer.partStarts.count
        pendingPartNotice = true
        // The music last: building the scene takes time (pictures made 8x, tables), and the song must not
        // run ahead of the picture meanwhile. (The window's clock starts at its next frame, just after.)
        if let song = ahead.song { music.play(song, fromOrder: ahead.order, skipping: ahead.seconds) }
    }

    /// After a resume, the part already playing is announced on the first step (the app's hooks are
    /// set up after the scene is made).
    private var pendingPartNotice = false

    private func hookUp() {
        sequencer.onShow = { [weak self] visual in self?.show(visual) }
    }

    /// The part playing now.
    var currentPart: String? { sequencer.currentPart }
    /// The scene showing now, if the part shows one (for checks).
    var sceneShowing: DemoScene? { if case .scene(let scene, _) = shown { return scene } else { return nil } }
    /// The picture showing now, by its name in `artwork/`, if the part shows one (for checks).
    var pictureShowing: String? { if case .picture(let name) = shown { return name } else { return nil } }
    /// The music's row as the parts see it now (for checks).
    var musicRow: Int { sequencer.musicState.row }
    /// The music as the parts see it now (for checks).
    var musicState: DemoMusicState { sequencer.musicState }
    /// The music's "music plus" as the parts see it now (for checks).
    var musicPlus: Int { sequencer.musicState.plus }

    // MARK: - DemoScene

    /// The music plays on while the picture stalls (a scene being made at a part change, a hitch), so the
    /// missed steps are made up, not dropped: dropped, every later step would lag the music by that much
    /// until the next cue. Five seconds covers any stall while the window shows; when it does not show,
    /// the app pauses Play Demo and its music (`AppModel`), so there is nothing to make up.
    static let longestCatchUp = 5.0
    var longestCatchUp: Double { Self.longestCatchUp }

    func reset() {
        sequencer = DemoSequencer(music: music)
        shown = .black
        partsStarted = 0
        pendingPartNotice = false
        hookUp()
        if let startProvider { start = startProvider() }
        if let start {
            do { try resume(at: start) } catch { NSLog("SR Metal: Play Demo could not start at \(start): \(error)") }
        }
    }

    func tick() {
        // The scene showing moves on first, so a scene the script starts now is seen at its first step.
        if case .scene(let scene, _) = shown {
            scene.demoUpdate(DemoContext(music: sequencer.musicState))
            scene.tick()
        }
        sequencer.tick()
        if pendingPartNotice, let (name, step) = sequencer.partStarts.last {
            pendingPartNotice = false
            if logsParts { NSLog("SR Metal: Play Demo started at part %d \"%@\" (began at step %d, %@)",
                                 sequencer.partStarts.count, name, step, DemoTimelineCommand.time(step)) }
            onPart?(name)
        }
        if sequencer.partStarts.count != partsStarted {
            partsStarted = sequencer.partStarts.count
            if let (name, step) = sequencer.partStarts.last {
                let p = music.position
                if logsParts { NSLog("SR Metal: Play Demo part %d \"%@\" at step %d (%@); music section %d row %d",
                      partsStarted, name, step, DemoTimelineCommand.time(step), p.order, p.row) }
                onPart?(name)
            }
        }
    }

    var currentCanvasSize: SIMD2<Float>? {
        switch shown {
        case .scene(_, let size): return size
        case .picture(let name): return picture(name)?.size ?? SIMD2(320, 200)
        case .card, .black: return SIMD2(320, 200)
        }
    }

    func prepare(commands: MTLCommandBuffer, frame: FrameInfo) {
        if case .scene(let scene, _) = shown { scene.prepare(commands: commands, frame: frame) }
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        let still: ScenePicture?
        switch shown {
        case .scene(let scene, _):
            scene.draw(into: encoder, frame: frame)
            return
        case .black: return
        case .picture(let name): still = picture(name)
        case .card(let title): still = card(title)
        }
        if let still { pictureLayer.draw(still, into: encoder, look: frame.look) }
    }

    /// Play Demo has no 1993 reference picture of its own: each scene it shows has one.
    func classicReferenceFrame() -> [UInt8] { [] }

    // MARK: - Changing what is shown

    private func show(_ visual: DemoVisual, musicAtShow: DemoMusicState? = nil) {
        // The last picture's Modern-look version is let go; its small original stays (the ships'
        // horizon is shown twice in a row).
        if case .picture(let name) = visual, picture?.name == name {} else { picture?.picture.dropUpscaled() }
        switch visual {
        case .scene(let id):
            guard let entry = SceneCatalog.all.first(where: { $0.id == id }) else { shown = .black; return }
            do {
                let previous = sceneShowing?.handover
                let scene = try entry.make(device, pixelFormat)
                // Told the music on the step it first shows (before the script checks its next cue), so a
                // scene that waits for a cue already met starts on the same step as the script.
                scene.demoUpdate(DemoContext(music: musicAtShow ?? sequencer.musicState, justShown: true, previous: previous))
                shown = .scene(scene, entry.canvasSize)
            } catch {
                NSLog("SR Metal: Play Demo could not start scene \(id): \(error)")
                shown = .card(entry.title)
            }
        case .picture(let name):
            shown = .picture(name)
        case .card(let title):
            shown = .card(title)
        case .black:
            shown = .black
        }
    }

    private func picture(_ name: String) -> ScenePicture? {
        if let picture, picture.name == name { return picture.picture }
        guard let made = try? ScenePicture(named: name, device: device) else { return nil }
        picture = (name, made)
        return made
    }

    /// A title card naming a scene that could not be started (the reason is in the log), drawn once per look.
    private func card(_ title: String) -> ScenePicture? {
        if let card = cards[title] { return card }
        guard let big = Self.cardImage(title, width: 1600, height: 1200, smooth: true),
              let small = Self.cardImage(title, width: 320, height: 200, smooth: false),
              let modern = try? loader.newTexture(cgImage: big, options: ScenePicture.loadOptions),
              let classic = try? loader.newTexture(cgImage: small, options: ScenePicture.loadOptions) else { return nil }
        cards[title] = ScenePicture(classic, modern: modern, device: device)
        return cards[title]
    }

    static func cardImage(_ title: String, width: Int, height: Int, smooth: Bool) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(smooth)
        context.setAllowsFontSmoothing(smooth)
        let scale = CGFloat(height) / 200
        func line(_ text: String, size: CGFloat, grey: CGFloat, y: CGFloat) {
            let font = CTFontCreateWithName("Helvetica Neue" as CFString, size * scale, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: CGColor(red: grey, green: grey, blue: grey, alpha: 1)
            ]
            let ct = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let bounds = CTLineGetBoundsWithOptions(ct, [])
            context.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2 - bounds.minX, y: y * scale)
            CTLineDraw(ct, context)
        }
        line(title, size: 22, grey: 0.92, y: 104)
        line("could not be started", size: 10, grey: 0.5, y: 84)
        return context.makeImage()
    }
}
