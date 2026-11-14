import Foundation

/// The sine table several of the original parts share (SIN1024.INC): one full wave in 1024 entries,
/// scaled to -256...256. This formula reproduces the original file exactly.
enum SinTable {
    static let sin1024: [Int] = (0..<1024).map { (i: Int) -> Int in
        let wave: Double = Foundation.sin(Double(i) * Double.pi / 512) * 256
        return Int(wave.rounded(.towardZero))
    }

    /// Looks up the table with wrap-around, so any index works.
    static func sin(_ index: Int) -> Int {
        sin1024[index & 1023]
    }

    /// A quarter turn ahead of sine.
    static func cos(_ index: Int) -> Int {
        sin1024[(index + 256) & 1023]
    }
}
