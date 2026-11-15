import CoreGraphics
import Foundation

/// The small pictures in the window's scene list.
///
/// No picture files are shipped with the app. When the window opens, each scene is drawn once into a small
/// picture (Modern look, at the step its `SceneEntry` names) by the same code as the `--snapshot` option.
/// That work is done on a background thread, so the window appears at once; each row shows a grey
/// placeholder until its picture arrives.
final class Thumbnails: ObservableObject {
    /// Pictures made so far, by scene id.
    @Published private(set) var images: [String: CGImage] = [:]

    /// Drawn larger than shown (the row shows 64x48 points), so it stays sharp on a Retina display and
    /// thin lines are smoothed when scaled down.
    static let width = 256
    static let height = 192

    private var started = false

    /// Starts making the pictures. Calling it again does nothing.
    func start() {
        guard !started else { return }
        started = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for entry in SceneCatalog.all {
                do {
                    let image = try Snapshot.render(
                        entry: entry, look: .modern, step: entry.thumbnailStep,
                        width: Self.width, height: Self.height)
                    // Changes the window can see must be made on the main thread.
                    DispatchQueue.main.async { self?.images[entry.id] = image }
                } catch {
                    NSLog("SR Metal: could not make the list picture for \(entry.title): \(error)")
                }
            }
        }
    }
}
