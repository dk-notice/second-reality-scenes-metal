import Foundation

enum VisuError: Error, CustomStringConvertible {
    case missingFile(String)
    case badFile(String, String)

    var description: String {
        switch self {
        case .missingFile(let name):
            return "VISU data file not found: \(name) (looked in the app's Resources/Visu and in Data/Visu)"
        case .badFile(let name, let why):
            return "VISU data file \(name) is not as expected: \(why)"
        }
    }
}

/// Finds and reads the original data files of the two 3D scenes (see `Data/Visu/README.md`).
///
/// `./build.sh` copies `Data/Visu` into the app as `SRMetal.app/Contents/Resources/Visu`. When the
/// program is run some other way (straight from `.build/`, say), the files are looked for in a
/// `Data/Visu` folder next to or above the program, so development runs work too.
enum VisuData {
    static let folder: URL? = {
        let manager = FileManager.default
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Visu"))
        }
        var up = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(up.appendingPathComponent("Data/Visu"))
            up = up.deletingLastPathComponent()
        }
        candidates.append(URL(fileURLWithPath: manager.currentDirectoryPath).appendingPathComponent("Data/Visu"))
        return candidates.first { manager.fileExists(atPath: $0.appendingPathComponent("U2A.00M").path) }
    }()

    static func load(_ name: String) throws -> [UInt8] {
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else {
            throw VisuError.missingFile(name)
        }
        return [UInt8](data)
    }
}

/// Reading little-endian numbers (lowest byte first, as a PC stores them) out of a file's bytes.
struct VisuBytes {
    let bytes: [UInt8]

    func u8(_ at: Int) -> Int { Int(bytes[at]) }
    func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
    func s16(_ at: Int) -> Int16 { Int16(truncatingIfNeeded: u16(at)) }
    func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
    func s32(_ at: Int) -> Int32 { Int32(truncatingIfNeeded: u32(at)) }
    func tag(_ at: Int) -> String { String(decoding: bytes[at..<at + 4], as: UTF8.self) }
}
