import Foundation

/// `SRMetal --credits-captures <folder>`: renders the credits' Modern-look pictures (`CreditsModel.captures`)
/// from this project's scenes into the folder, as `cap01.png` ... `cap21.png`. `build.sh` runs it with the
/// app's `Resources/Credits/Modern` folder. Picture 21 shows the credits screen itself, so it is made last:
/// its own picture there is the released one through Super-xBR.
enum CreditsCapturesCommand {
    static func run(arguments: [String]) -> Bool {
        guard let at = arguments.firstIndex(of: "--credits-captures"), at + 1 < arguments.count else {
            print("usage: SRMetal --credits-captures <folder>")
            return false
        }
        let folder = URL(fileURLWithPath: arguments[at + 1])
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var good = true
        for (index, capture) in CreditsModel.captures.enumerated() {
            guard let capture else { continue }
            let url = folder.appendingPathComponent(CreditsModel.captureName(index))
            try? FileManager.default.removeItem(at: url)
            guard let entry = SceneCatalog.all.first(where: { $0.id == capture.scene }),
                  let image = try? Snapshot.render(entry: entry, look: .modern, step: capture.step,
                                                   width: CreditsModel.captureSize.width, height: CreditsModel.captureSize.height),
                  Snapshot.writePNG(image, to: url) else {
                print("credits picture \(index + 1): could not capture \(capture.scene) at step \(capture.step)")
                good = false
                continue
            }
        }
        print(good ? "Credits pictures captured into \(folder.path)" : "Some credits pictures could not be captured")
        return good
    }
}
