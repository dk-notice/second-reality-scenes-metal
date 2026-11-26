import MetalKit
import SwiftUI

/// Entry point. `--selftest` runs the checks and exits; `--snapshot` saves a picture and exits;
/// `--visu-test` saves a picture of a 3D engine test case and exits; `--motion-check` compares a
/// scene's neighbouring pictures for jumps and flicker and exits; `--music-info` describes the
/// demo's two songs and exits; `--music-render` saves a stretch of one as a sound file and exits;
/// `--music-play` plays a stretch of one through the speakers and exits; otherwise the app starts.
@main
enum Main {
    static func main() {
        if let flag = CommandLine.arguments.firstIndex(of: "--selftest") {
            // An optional word after it runs only the matching groups of checks (see `SelfTest.only`).
            let next = CommandLine.arguments.dropFirst(flag + 1).first
            if let next, !next.hasPrefix("-") { SelfTest.only = next }
            exit(SelfTest.run() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--snapshot") {
            exit(Snapshot.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--visu-test") {
            exit(VisuTestCommand.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--motion-check") {
            exit(MotionCheck.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--music-play") {
            exit(MusicPlayCommand.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--music-render") {
            exit(MusicRenderCommand.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--credits-captures") {
            exit(CreditsCapturesCommand.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--credits-match") {
            exit(CreditsMatchCommand.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--scaler-compare") {
            exit(ScalerCompareCommand.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--demo-live") {
            exit(DemoTimelineCommand.live(arguments: CommandLine.arguments) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--demo-timeline") {
            exit(DemoTimelineCommand.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--music-info") {
            exit(MusicInfoCommand.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        // A mistyped option must not quietly open the first scene (or, for a mistyped command such
        // as `--selftests`, quietly open a window): say what is wrong and stop.
        let options = StartupOptions(arguments: CommandLine.arguments)
        if !options.problems.isEmpty {
            for problem in options.problems { FileHandle.standardError.write(Data((problem + "\n").utf8)) }
            FileHandle.standardError.write(Data((StartupOptions.usage + "\n").utf8))
            exit(2)
        }
        SRMetalApp.main()
    }
}

/// The start-up choices given on the command line: `--look classic|modern`, `--scene <id>`
/// (e.g. `--scene interference`), `--from <scene id | part number>` (with `--scene play-demo`: start the
/// demo there), `--music on|off` (off: muted) and `--sidebar hidden|shown`.
///
/// With no `--scene` the app starts as a demo does: Play Demo from the beginning, with its music and
/// the scene list hidden (user, 2026-11-25). `--scene <id>` starts on that scene with the list showing.
struct StartupOptions {
    var look: Look?
    var sceneIndex: Int?
    /// `--scene play-demo`: start with Play Demo.
    var playDemo = false
    /// `--from`: where Play Demo starts.
    var demoStart: DemoStart?
    /// `--music off`: start with the music muted.
    var muted = false
    var sidebarHidden = false
    /// Whether `--sidebar` was given at all.
    var sidebarChosen = false
    /// The app starts in Play Demo: asked for, or no scene was.
    var startsWithDemo: Bool { playDemo || sceneIndex == nil }
    /// The scene list starts hidden: as `--sidebar` says, or else while the demo plays.
    var startsWithSidebarHidden: Bool { sidebarChosen ? sidebarHidden : startsWithDemo }
    /// What is wrong with the options, in words. Empty when all is well.
    var problems: [String] = []

    static var usage: String {
        """
        Options: --scene <id>  --look modern|classic  --sidebar hidden|shown  --music on|off
                 --scene play-demo --from <scene id, or part number 1-\(DemoScript.partNames.count)>
        Commands: --selftest [word], --demo-timeline, --music-info (these three just run); --snapshot, --motion-check, --visu-test, --music-render, --music-play, --demo-live, --scaler-compare, --credits-match, --credits-captures (run one of these without arguments for its usage)
        Scenes: \(SceneCatalog.all.map(\.id).joined(separator: ", ")), or \(DemoRunScene.id) for the whole demo
        """
    }

    /// `arguments` as the system gives them: the program's own path first.
    init(arguments: [String]) {
        var index = 1
        while index < arguments.count {
            let option = arguments[index]
            index += 1
            // Only options starting with two dashes are ours. macOS adds single-dash ones of its
            // own (with values) when it starts an app in some ways; those are left alone.
            guard option.hasPrefix("--") else { continue }
            guard ["--look", "--scene", "--sidebar", "--from", "--music"].contains(option) else {
                problems.append("Unknown option \(option)")
                continue
            }
            guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                problems.append("\(option) needs a value")
                continue
            }
            let value = arguments[index]
            index += 1
            switch option {
            case "--look":
                if let chosen = Look(rawValue: value) { look = chosen }
                else { problems.append("Unknown look \"\(value)\" (use modern or classic)") }
            case "--from":
                if let start = DemoStart(argument: value) { demoStart = start }
                else { problems.append("Play Demo cannot start from \"\(value)\" (a scene the demo shows, or a part number 1-\(DemoScript.partNames.count))") }
            case "--music":
                if value == "off" { muted = true }
                else if value != "on" { problems.append("Unknown music setting \"\(value)\" (use on or off)") }
            case "--scene":
                if value == DemoRunScene.id { playDemo = true }
                else if let found = SceneCatalog.all.firstIndex(where: { $0.id == value }) { sceneIndex = found }
                else { problems.append("Unknown scene \"\(value)\"") }
            default:
                sidebarChosen = true
                if value == "hidden" { sidebarHidden = true }
                else if value == "shown" { sidebarHidden = false }
                else { problems.append("Unknown sidebar setting \"\(value)\" (use hidden or shown)") }
            }
        }
        if demoStart != nil && !playDemo { problems.append("--from only works with --scene \(DemoRunScene.id)") }
    }
}

/// What the user has currently chosen. The sidebar, toolbar, menu and keys change it; the picture follows it.
final class AppModel: ObservableObject {
    @Published var look: Look = .modern {
        didSet { music.setSound(look) }   // the music's sound follows the look
    }
    @Published var sceneIndex = 0 {
        didSet { endDemo() }   // choosing a scene (sidebar, keys, menu) leaves Play Demo
    }
    /// Whether Play Demo is running (it then takes the scene's place in the window).
    @Published private(set) var playingDemo = false
    /// The demo part now playing, for the window title.
    @Published private(set) var demoPart: String?
    /// Goes up by one each time the user asks to replay the scene from its start.
    @Published private(set) var restartCount = 0
    /// Whether the sidebar is showing. The standard toolbar button changes this too.
    /// (Kept here rather than in the view with `@State`, because `@State` needs a compiler plug-in that
    /// only comes with the full Xcode, and this project builds with the Command Line Tools alone.)
    @Published var columns = NavigationSplitViewVisibility.all
    /// What `columns` was before going fullscreen, so it can be put back afterwards.
    var columnsBeforeFullscreen: NavigationSplitViewVisibility?

    private var keyMonitor: Any?

    /// Whether the scene's window can be seen at all (not minimised, fully covered or on another desktop),
    /// as the scene's view reports it, and whether the Mac is going to sleep.
    var windowVisible = true { didSet { updateHidden() } }
    private var asleep = false { didSet { updateHidden() } }
    /// Nobody can see the picture: it stops, and Play Demo's music with it, and both carry on from the same
    /// place afterwards. (The music plays on its own clock; left running, it would get ahead of a picture
    /// that is not being drawn, and Play Demo's parts would miss their cues.)
    @Published private(set) var hidden = false {
        didSet { music.paused = hidden }
    }
    private func updateHidden() {
        let now = !windowVisible || asleep
        if now != hidden { hidden = now }
    }
    private var sleepObservers: [NSObjectProtocol] = []
    private func watchSleep() {
        let centre = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            centre.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.asleep = true },
            centre.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.asleep = false },
        ]
    }

    /// The music, played by Play Demo. The scenes in the sidebar are silent.
    let music = MusicPlayer()
    /// Music muted (M). The song keeps playing underneath, so Play Demo keeps its timing.
    @Published var musicMuted = false {
        didSet { music.muted = musicMuted }
    }
    /// Play Demo follows the music as it is HEARD: it allows for the output device's delay (Bluetooth
    /// headphones play a fraction of a second late). On unless the user turned it off (remembered).
    @Published var allowsForOutputDelay = true {
        didSet {
            music.allowsForOutputDelay = allowsForOutputDelay
            UserDefaults.standard.set(allowsForOutputDelay, forKey: Self.outputDelayKey)
        }
    }
    static let outputDelayKey = "allowForOutputDelay"
    /// The delay macOS reports for the output device in use, in milliseconds (nil until music has played).
    @Published private(set) var outputDelayMilliseconds: Int?
    /// Why Play Demo has no sound (and so waits), or nil.
    @Published private(set) var musicProblem: String?
    /// Where Play Demo started (nil: the beginning). Read again on each restart.
    @Published private(set) var demoStart: DemoStart?

    init() {
        // Optional start-up choices (see `StartupOptions`).
        let options = StartupOptions(arguments: CommandLine.arguments)
        if let chosen = options.look {
            look = chosen
        }
        if let index = options.sceneIndex {
            sceneIndex = index
        }
        if options.startsWithDemo {
            demoStart = options.demoStart
            playingDemo = true
        }
        if options.muted {
            musicMuted = true
            music.muted = true   // didSet does not run inside init
        }
        if options.startsWithSidebarHidden {
            columns = .detailOnly
        }
        watchSleep()
        music.onProblem = { [weak self] problem in self?.musicProblem = problem }
        // (didSet does not run inside init: the player is told directly.)
        allowsForOutputDelay = UserDefaults.standard.object(forKey: Self.outputDelayKey) as? Bool ?? true
        music.allowsForOutputDelay = allowsForOutputDelay
        music.onOutputDelay = { [weak self] delay in self?.outputDelayMilliseconds = Int((delay * 1000).rounded()) }
    }

    var entry: SceneEntry { playingDemo ? demoEntry : SceneCatalog.all[sceneIndex] }

    /// Play Demo, as a scene the window can show, with the real music.
    private lazy var demoEntry = DemoRunScene.entry(
        music: { [unowned self] in LiveDemoMusic(player: self.music, look: { [unowned self] in self.look }) },
        start: { [unowned self] in self.demoStart },
        configure: { [weak self] scene in
            scene.onPart = { [weak self] name in self?.demoPart = name }
            scene.logsParts = true
            self?.demoRun = scene
        })
    /// The demo now running (to ask which scene it is showing when it is stopped).
    private weak var demoRun: DemoRunScene?

    /// Starts the demo with its music: from the beginning, or (`start`) where a scene first shows or a
    /// part begins, with the music jumped to that moment.
    func playDemo(from start: DemoStart? = nil) {
        demoStart = start
        if playingDemo { restartScene() }   // already running: start again (the run reads `demoStart`)
        demoPart = nil
        playingDemo = true
    }

    /// The scene chosen in the sidebar, if the demo shows it ("Play Demo from Here").
    var demoStartHere: DemoStart? {
        let id = SceneCatalog.all[sceneIndex].id
        return DemoScript.sceneIDs.contains(id) ? .scene(id) : nil
    }

    func toggleMute() { musicMuted.toggle() }

    /// Stops Play Demo and its music (nothing happens if it is not running).
    func endDemo() {
        guard playingDemo else { return }
        playingDemo = false
        demoPart = nil
        music.stop()
    }
    /// Stops Play Demo and goes over to choosing: the scene list opens on the scene the demo was
    /// showing (Escape, and Stop Demo in the menu).
    func stopDemoAndBrowse() {
        guard playingDemo else { return }
        browse(from: demoRun?.lastSceneID)
    }

    /// Leaves the demo for the scene with this id (or stays on the scene last chosen, if the demo had
    /// not shown one yet), with the list showing.
    func browse(from sceneID: String?) {
        endDemo()
        if let sceneID, let index = SceneCatalog.all.firstIndex(where: { $0.id == sceneID }) { sceneIndex = index }
        columns = .all
    }
    var hasSeveralScenes: Bool { SceneCatalog.all.count > 1 }

    func toggleLook() {
        look = (look == .modern) ? .classic : .modern
    }

    func stepScene(by offset: Int) {
        let count = SceneCatalog.all.count
        sceneIndex = (sceneIndex + offset + count) % count
    }

    func restartScene() {
        restartCount += 1
    }

    /// Makes the single-key shortcuts work wherever the keyboard focus is.
    ///
    /// L, R and the arrow keys have no Command key, so macOS offers them first to whatever part of the window
    /// has the keyboard focus. A focused sidebar list would keep them for itself (arrows move its
    /// selection, letters jump to a row by name). So the app looks at each key press before the window
    /// does, acts on these few keys itself, and lets every other key through untouched.
    func installKeyShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Leave anything with Command, Option, Control or Shift alone, and never steal typing from a text box.
            guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  !(event.window?.firstResponder is NSText) else { return event }
            switch event.keyCode {
            case 124, 125: self.stepScene(by: 1)     // right arrow, down arrow
            case 123, 126: self.stepScene(by: -1)    // left arrow, up arrow
            case 53 where self.playingDemo: self.stopDemoAndBrowse()   // Escape: from watching to choosing
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                // Not while the key is held down: the look would flip at the keyboard's repeat rate.
                case "l": if !event.isARepeat { self.toggleLook() }
                case "r": if !event.isARepeat { self.restartScene() }
                case "p": if !event.isARepeat { self.playDemo() }
                case "m": if !event.isARepeat { self.toggleMute() }
                default: return event
                }
            }
            return nil   // handled: nothing else gets this key press
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct SRMetalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var thumbnails = Thumbnails()

    var body: some Scene {
        Window("SR Metal", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(thumbnails)
        }
        // Room for the sidebar plus a 960x720 (4:3) scene picture.
        .defaultSize(width: 1180, height: 772)
        .commands {
            // Adds "Show/Hide Sidebar" to the View menu.
            SidebarCommands()

            CommandMenu("Scene") {
                Button(model.look == .modern ? "Switch to 1993 Look" : "Switch to Modern Look") {
                    model.toggleLook()
                }
                .keyboardShortcut("l", modifiers: [])

                Button("Restart Scene") { model.restartScene() }
                    .keyboardShortcut("r", modifiers: [])

                Divider()

                Button(model.playingDemo ? "Play Demo from the Start" : "Play Demo") { model.playDemo() }
                    .keyboardShortcut("p", modifiers: [])
                Button("Play Demo from Here") { model.playDemo(from: model.demoStartHere) }
                    .keyboardShortcut("p", modifiers: [.shift])
                    .disabled(model.demoStartHere == nil)
                Menu("Play Demo from Part") {
                    ForEach(Array(DemoScript.partNames.enumerated()), id: \.offset) { number, name in
                        Button("\(number + 1). \(name)") { model.playDemo(from: number == 0 ? nil : .part(number)) }
                    }
                }
                Button("Stop Demo") { model.stopDemoAndBrowse() }
                    .disabled(!model.playingDemo)

                Divider()

                Button("Next Scene") { model.stepScene(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(!model.hasSeveralScenes)
                Button("Previous Scene") { model.stepScene(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(!model.hasSeveralScenes)
            }

            // The music plays with Play Demo (the original songs, live, by libopenmpt; the sound follows
            // the look). Muting keeps the song running underneath, so the demo keeps its timing.
            CommandMenu("Music") {
                Button(model.musicMuted ? "Unmute Music" : "Mute Music") { model.toggleMute() }
                    .keyboardShortcut("m", modifiers: [])
                // Play Demo follows the music as heard: the picture waits by the output device's delay
                // (what macOS reports for it; shown once music has played).
                Toggle("Allow for Output Delay" + (model.outputDelayMilliseconds.map { " (\($0) ms)" } ?? ""),
                       isOn: Binding(get: { model.allowsForOutputDelay }, set: { model.allowsForOutputDelay = $0 }))
            }
        }
    }
}

/// The window: scene list on the left, the scene picture filling the rest, controls in the toolbar.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var thumbnails: Thumbnails

    var body: some View {
        NavigationSplitView(columnVisibility: $model.columns) {
            SceneList()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
        } detail: {
            MetalView(entry: model.entry, look: model.look, restartCount: model.restartCount, paused: model.hidden,
                      onVisibility: { [weak model] visible in model?.windowVisible = visible })
                .frame(minWidth: 480, minHeight: 360)
                .background(Color.black)
        }
        .navigationTitle(model.playingDemo
                         ? "Play Demo: \(model.demoPart ?? "starting") — \(model.look.title) look"
                            + (model.musicProblem.map { " — NO SOUND: \($0)" } ?? "")
                         : "\(model.entry.title) — \(model.look.title) look")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Look", selection: $model.look) {
                    ForEach(Look.allCases, id: \.self) { look in
                        Text(look.title).tag(look)
                    }
                }
                .pickerStyle(.segmented)
                .help("Switch between the Modern and 1993 looks (L)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.restartScene()
                } label: {
                    Label("Restart Scene", systemImage: "arrow.counterclockwise")
                }
                .help("Play this scene again from its start (R)")
            }
        }
        // In fullscreen the toolbar stays out of the way until the pointer goes to the top of the screen.
        .windowToolbarFullScreenVisibility(.onHover)
        // In fullscreen only the scene shows: hide the sidebar on the way in, put it back on the way out.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            model.columnsBeforeFullscreen = model.columns
            model.columns = .detailOnly
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            if let before = model.columnsBeforeFullscreen {
                model.columns = before
                model.columnsBeforeFullscreen = nil
            }
        }
        .onAppear {
            model.installKeyShortcuts()
            thumbnails.start()
        }
    }
}

/// The sidebar: Play Demo first, then one row per scene in `SceneCatalog.all`. What the window shows is
/// the selected row.
struct SceneList: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var thumbnails: Thumbnails

    var body: some View {
        // The list's selection IS what the window shows: reading it gives the demo's or the current
        // scene's id, and clicking a row starts the demo or sets the scene. (Clicking empty space would
        // clear a selection; that is ignored.)
        let selection = Binding<String?>(
            get: { model.entry.id },
            set: { id in
                if id == DemoRunScene.id {
                    if !model.playingDemo { model.playDemo() }
                } else if let id, let index = SceneCatalog.all.firstIndex(where: { $0.id == id }) {
                    model.sceneIndex = index
                }
            })

        List(selection: selection) {
            row(title: "Play Demo", caption: "The whole demo, with its music") { demoThumbnail }
                .tag(DemoRunScene.id)
                .help("Second Reality from the beginning, with the original music (P)")
            Section("Scenes") {
                ForEach(SceneCatalog.all) { entry in
                    row(title: entry.title, caption: entry.credit) { thumbnail(for: entry) }
                        .tag(entry.id)
                        .help("\(entry.title), originally by \(entry.credit)")
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row<Picture: View>(title: String, caption: String, @ViewBuilder picture: () -> Picture) -> some View {
        HStack(spacing: 10) {
            picture()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    /// Play Demo's row has no picture of its own: a play sign on black, the shape of the others.
    private var demoThumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        return ZStack {
            Color.black
            Image(systemName: "play.fill")
                .foregroundStyle(.white)
        }
        .frame(width: 64, height: 48)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.15)))
    }

    @ViewBuilder
    private func thumbnail(for entry: SceneEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        Group {
            if let image = thumbnails.images[entry.id] {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                // Placeholder until the picture has been drawn.
                Color.black.opacity(0.35)
            }
        }
        .frame(width: 64, height: 48)   // 4:3, like the scene itself
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.15)))
    }
}

/// The Metal view, which also reports whether its window can be seen at all (macOS calls a window that
/// is minimised, fully covered or on another desktop "occluded").
final class SceneView: MTKView {
    var onVisibility: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let window else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.onVisibility?(window.occlusionState.contains(.visible))
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

/// Puts a Metal drawing surface inside the SwiftUI window.
struct MetalView: NSViewRepresentable {
    let entry: SceneEntry
    let look: Look
    let restartCount: Int
    /// The picture stands still (its window cannot be seen, or the Mac sleeps).
    let paused: Bool
    let onVisibility: (Bool) -> Void

    final class Coordinator {
        var renderer: Renderer?
        var restartCount = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = SceneView()
        view.onVisibility = onVisibility
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("SR Metal: this Mac has no Metal graphics device")
            return view
        }
        view.device = device
        view.colorPixelFormat = Renderer.pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        // Ask for the display's fastest refresh; the system caps this at what the screen can do.
        view.preferredFramesPerSecond = 120

        do {
            let renderer = try Renderer(device: device, entry: entry)
            renderer.look = look
            view.delegate = renderer
            context.coordinator.renderer = renderer
            context.coordinator.restartCount = restartCount
        } catch {
            NSLog("SR Metal: could not start the renderer: \(error)")
        }
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.look = look
        if view.isPaused != paused {
            view.isPaused = paused
            if !paused { renderer.resumeAfterPause() }
        }
        do {
            try renderer.show(entry)
        } catch {
            NSLog("SR Metal: could not start scene \(entry.title): \(error)")
        }
        if restartCount != context.coordinator.restartCount {
            context.coordinator.restartCount = restartCount
            renderer.restart()
        }
    }
}
