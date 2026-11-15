import MetalKit
import SwiftUI

/// Entry point. `--selftest` runs the checks and exits; `--snapshot` saves a picture and exits;
/// `--visu-test` saves a picture of a 3D engine test case and exits; otherwise the app starts.
@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--snapshot") {
            exit(Snapshot.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--visu-test") {
            exit(VisuTestCommand.run(arguments: CommandLine.arguments) ? 0 : 1)
        }
        SRMetalApp.main()
    }
}

/// What the user has currently chosen. The sidebar, toolbar, menu and keys change it; the picture follows it.
final class AppModel: ObservableObject {
    @Published var look: Look = .modern
    @Published var sceneIndex = 0
    /// Goes up by one each time the user asks to replay the scene from its start.
    @Published private(set) var restartCount = 0
    /// Whether the sidebar is showing. The standard toolbar button changes this too.
    /// (Kept here rather than in the view with `@State`, because `@State` needs a compiler plug-in that
    /// only comes with the full Xcode, and this project builds with the Command Line Tools alone.)
    @Published var columns = NavigationSplitViewVisibility.all
    /// What `columns` was before going fullscreen, so it can be put back afterwards.
    var columnsBeforeFullscreen: NavigationSplitViewVisibility?

    private var keyMonitor: Any?

    init() {
        // Optional start-up choices: `--look classic|modern`, `--scene <id>` (e.g. `--scene interference`)
        // and `--sidebar hidden`.
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        if let chosen = value(after: "--look").flatMap(Look.init(rawValue:)) {
            look = chosen
        }
        if let id = value(after: "--scene"), let index = SceneCatalog.all.firstIndex(where: { $0.id == id }) {
            sceneIndex = index
        }
        if value(after: "--sidebar") == "hidden" {
            columns = .detailOnly
        }
    }

    var entry: SceneEntry { SceneCatalog.all[sceneIndex] }
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
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "l": self.toggleLook()
                case "r": if !event.isARepeat { self.restartScene() }
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

                Button("Next Scene") { model.stepScene(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(!model.hasSeveralScenes)
                Button("Previous Scene") { model.stepScene(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(!model.hasSeveralScenes)
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
            MetalView(entry: model.entry, look: model.look, restartCount: model.restartCount)
                .frame(minWidth: 480, minHeight: 360)
                .background(Color.black)
        }
        .navigationTitle("\(model.entry.title) — \(model.look.title) look")
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

/// The sidebar: one row per scene in `SceneCatalog.all`. The current scene is the selected row.
struct SceneList: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var thumbnails: Thumbnails

    var body: some View {
        // The list's selection IS the current scene: reading it gives the current scene's id, and
        // clicking a row sets the scene. (Clicking empty space would clear a selection; that is ignored.)
        let selection = Binding<String?>(
            get: { model.entry.id },
            set: { id in
                if let id, let index = SceneCatalog.all.firstIndex(where: { $0.id == id }) {
                    model.sceneIndex = index
                }
            })

        List(SceneCatalog.all, selection: selection) { entry in
            HStack(spacing: 10) {
                thumbnail(for: entry)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.body)
                    Text(entry.credit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .help("\(entry.title), originally by \(entry.credit)")
        }
        .listStyle(.sidebar)
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

/// Puts a Metal drawing surface inside the SwiftUI window.
struct MetalView: NSViewRepresentable {
    let entry: SceneEntry
    let look: Look
    let restartCount: Int

    final class Coordinator {
        var renderer: Renderer?
        var restartCount = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
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
