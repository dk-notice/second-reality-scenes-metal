import MetalKit
import SwiftUI

/// Entry point. `--selftest` runs the checks and exits; otherwise the app starts.
@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run() ? 0 : 1)
        }
        SRMetalApp.main()
    }
}

/// What the user has currently chosen. The menu changes it; the picture follows it.
final class AppModel: ObservableObject {
    @Published var look: Look = .modern
    @Published var sceneIndex = 0

    init() {
        // Optional start-up choice: `--look classic` or `--look modern`.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--look"), flag + 1 < arguments.count,
           let chosen = Look(rawValue: arguments[flag + 1]) {
            look = chosen
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
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct SRMetalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("SR Metal", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 960, height: 720)
        .commands {
            CommandMenu("Scene") {
                Button(model.look == .modern ? "Switch to 1993 Look" : "Switch to Modern Look") {
                    model.toggleLook()
                }
                .keyboardShortcut("l", modifiers: [])

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

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        MetalView(entry: model.entry, look: model.look)
            .frame(minWidth: 480, minHeight: 360)
            .background(Color.black)
            .navigationTitle("\(model.entry.title) — \(model.look.title) look")
    }
}

/// Puts a Metal drawing surface inside the SwiftUI window.
struct MetalView: NSViewRepresentable {
    let entry: SceneEntry
    let look: Look

    final class Coordinator {
        var renderer: Renderer?
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
    }
}
