import AppKit
import CoreText
import MetalKit

/// Finds the demo's pictures: the original pictures at their own size, exported from the 1993 demo
/// (`artwork/original/rgb`). `./build.sh` copies them into the app as `Resources/Artwork`; run some
/// other way, the `artwork` folder next to or above the program is used.
enum DemoPictures {
    static let folder: URL? = {
        let manager = FileManager.default
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent("Artwork")) }
        var up = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(up.appendingPathComponent("artwork/original/rgb"))
            up = up.deletingLastPathComponent()
        }
        return candidates.first { manager.fileExists(atPath: $0.appendingPathComponent("04-title.png").path) }
    }()

    /// The picture's file, or nil if it is not there.
    static func url(_ name: String) -> URL? {
        guard let url = folder?.appendingPathComponent(name + ".png"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
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

    func play(_ song: Song, fromOrder order: Int) {
        do {
            try player.play(song, look: look(), fromOrder: order)
        } catch {
            NSLog("SR Metal: Play Demo could not start \(song.rawValue): \(error)")
        }
    }

    var position: MusicPosition { player.position }
    var orderList: [Int] { player.orderList }
}

/// Play Demo: the whole demo, part after part, following `DemoScript` with the original music.
/// To the window it is one more scene; inside, it shows whichever stand-in the script asks for.
final class DemoRunScene: DemoScene {
    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let music: DemoMusicSource
    /// Called with each part's name as it starts.
    var onPart: ((String) -> Void)?

    private var sequencer: DemoSequencer
    private enum Shown {
        case scene(DemoScene, SIMD2<Float>)
        case picture(String)
        case card(String)
        case black
    }
    private var shown = Shown.black
    private var partsStarted = 0

    private let pipeline: MTLRenderPipelineState
    private let smooth: MTLSamplerState
    private let nearest: MTLSamplerState
    private let loader: MTKTextureLoader

    /// The original pictures (small: kept once loaded), and for the Modern look the same made 8x
    /// larger by Super-xBR (2560x1600 or 2560x3200; made once, when first shown).
    private var pictures: [String: MTLTexture] = [:]
    private var upscaledPictures: [String: MTLTexture] = [:]
    private var cards: [String: (modern: MTLTexture, classic: MTLTexture)] = [:]

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, music: DemoMusicSource) throws {
        self.device = device
        self.pixelFormat = pixelFormat
        self.music = music
        self.sequencer = DemoSequencer(music: music)
        self.loader = MTKTextureLoader(device: device)

        let library = try Shaders.library(device: device, source: Shaders.canvasVertexSource + """
        fragment float4 picture_fragment(CanvasOut in [[stage_in]],
                                         texture2d<float> tex [[texture(0)]],
                                         sampler smp [[sampler(0)]]) {
            return float4(tex.sample(smp, in.uv).rgb, 1.0);
        }
        """)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try Shaders.function("canvas_vertex", in: library)
        descriptor.fragmentFunction = try Shaders.function("picture_fragment", in: library)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        func sampler(_ filter: MTLSamplerMinMagFilter) throws -> MTLSamplerState {
            let d = MTLSamplerDescriptor()
            d.minFilter = filter
            d.magFilter = filter
            d.mipFilter = filter == .linear ? .linear : .notMipmapped
            guard let state = device.makeSamplerState(descriptor: d) else { throw RendererError.noSampler }
            return state
        }
        smooth = try sampler(.linear)
        nearest = try sampler(.nearest)
        hookUp()
    }

    private func hookUp() {
        sequencer.onShow = { [weak self] visual in self?.show(visual) }
    }

    /// The part playing now.
    var currentPart: String? { sequencer.currentPart }

    // MARK: - DemoScene

    func reset() {
        sequencer = DemoSequencer(music: music)
        shown = .black
        partsStarted = 0
        hookUp()
    }

    func tick() {
        // The scene showing moves on first, so a scene the script starts now is seen at its first step.
        if case .scene(let scene, _) = shown { scene.tick() }
        sequencer.tick()
        if sequencer.partStarts.count != partsStarted {
            partsStarted = sequencer.partStarts.count
            if let (name, step) = sequencer.partStarts.last {
                let p = music.position
                NSLog("SR Metal: Play Demo part %d \"%@\" at step %d (%@); music section %d row %d",
                      partsStarted, name, step, DemoTimelineCommand.time(step), p.order, p.row)
                onPart?(name)
            }
        }
    }

    var currentCanvasSize: SIMD2<Float>? {
        switch shown {
        case .scene(_, let size): return size
        case .picture(let name): return picture(name).map { SIMD2(Float($0.width), Float($0.height)) } ?? SIMD2(320, 200)
        case .card, .black: return SIMD2(320, 200)
        }
    }

    func prepare(commands: MTLCommandBuffer, frame: FrameInfo) {
        if case .scene(let scene, _) = shown { scene.prepare(commands: commands, frame: frame) }
    }

    func draw(into encoder: MTLRenderCommandEncoder, frame: FrameInfo) {
        let texture: MTLTexture?
        switch shown {
        case .scene(let scene, _):
            scene.draw(into: encoder, frame: frame)
            return
        case .black:
            return
        case .picture(let name):
            texture = frame.look == .modern ? (upscaledPicture(name) ?? picture(name)) : picture(name)
        case .card(let title):
            let pair = card(title)
            texture = frame.look == .modern ? pair?.modern : pair?.classic
        }
        guard let texture else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(frame.look == .modern ? smooth : nearest, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// Play Demo has no 1993 reference picture of its own: each scene it shows has one.
    func classicReferenceFrame() -> [UInt8] { [] }

    // MARK: - Changing what is shown

    private func show(_ visual: DemoVisual) {
        switch visual {
        case .scene(let id):
            guard let entry = SceneCatalog.all.first(where: { $0.id == id }) else { shown = .black; return }
            do {
                shown = .scene(try entry.make(device, pixelFormat), entry.canvasSize)
            } catch {
                NSLog("SR Metal: Play Demo could not start scene \(id): \(error)")
                shown = .card(entry.title)
            }
        case .picture(let name):
            shown = .picture(name)
            upscaledPictures = upscaledPictures.filter { $0.key == name }   // only the one showing
        case .card(let title):
            shown = .card(title)
        case .black:
            shown = .black
        }
    }

    private static let loadOptions: [MTKTextureLoader.Option: Any] = [
        .SRGB: false,                       // the bytes as they are, like every scene's colours
        .textureUsage: MTLTextureUsage.shaderRead.rawValue,
        .textureStorageMode: MTLStorageMode.private.rawValue,
        .generateMipmaps: false
    ]

    private func upscaledPicture(_ name: String) -> MTLTexture? {
        if let texture = upscaledPictures[name] { return texture }
        guard let original = picture(name), let texture = try? PictureScaler.upscaled(original, device: device) else { return nil }
        upscaledPictures[name] = texture
        return texture
    }

    private func picture(_ name: String) -> MTLTexture? {
        if let texture = pictures[name] { return texture }
        guard let url = DemoPictures.url(name),
              let texture = try? loader.newTexture(URL: url, options: Self.loadOptions) else { return nil }
        pictures[name] = texture
        return texture
    }

    /// A title card naming a part not built yet, drawn once per look.
    private func card(_ title: String) -> (modern: MTLTexture, classic: MTLTexture)? {
        if let pair = cards[title] { return pair }
        guard let big = Self.cardImage(title, width: 1600, height: 1200, smooth: true),
              let small = Self.cardImage(title, width: 320, height: 200, smooth: false),
              let modernCard = try? loader.newTexture(cgImage: big, options: Self.loadOptions),
              let classicCard = try? loader.newTexture(cgImage: small, options: Self.loadOptions) else { return nil }
        cards[title] = (modernCard, classicCard)
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
        line("not built yet: stand-in", size: 10, grey: 0.5, y: 84)
        return context.makeImage()
    }
}
