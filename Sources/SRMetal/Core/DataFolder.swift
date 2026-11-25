import Foundation

/// Finds one of the app's data folders. `./build.sh` copies each `Data/<name>` (or the artwork) into the
/// app's `Resources/<resource>`; when the program is run some other way (straight from `.build/`, say),
/// the development folder `devPath` is looked for next to or above the program, then in the current folder.
enum DataFolder {
    /// The first candidate folder that holds `marker`, or nil.
    static func find(resource: String, devPath: String, marker: String) -> URL? {
        let manager = FileManager.default
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent(resource)) }
        var up = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(up.appendingPathComponent(devPath))
            up = up.deletingLastPathComponent()
        }
        candidates.append(URL(fileURLWithPath: manager.currentDirectoryPath).appendingPathComponent(devPath))
        return candidates.first { manager.fileExists(atPath: $0.appendingPathComponent(marker).path) }
    }
}
