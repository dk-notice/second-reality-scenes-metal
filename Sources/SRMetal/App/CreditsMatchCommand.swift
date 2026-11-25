import Foundation
import Metal

/// `SRMetal --credits-match <picture 1-21> <scene id> [first last [stride]]`: finds the step at which a
/// scene's 1993 look is most like one of the credits' released pictures (shrunk to 160 x 100), to choose
/// the moment the Modern look's picture is captured at (`CreditsModel.captures`). Development only;
/// opens no window. Prints the best steps and their average difference (0...255 a channel).
enum CreditsMatchCommand {
    static func run(arguments: [String]) -> Bool {
        guard let at = arguments.firstIndex(of: "--credits-match"), at + 2 < arguments.count,
              let number = Int(arguments[at + 1]), (1...CreditsModel.screens).contains(number),
              let entry = SceneCatalog.all.first(where: { $0.id == arguments[at + 2] }) else {
            print("usage: SRMetal --credits-match <picture 1-21> <scene id> [first last [stride]]")
            return false
        }
        let rest = arguments.dropFirst(at + 3).compactMap { Int($0) }
        let first = rest.count > 0 ? rest[0] : 0
        let last = rest.count > 1 ? rest[1] : 4000
        let stride = rest.count > 2 ? max(rest[2], 1) : 2
        guard let model = try? CreditsModel.load(), let device = MTLCreateSystemDefaultDevice(),
              let scene = try? entry.make(device, Renderer.pixelFormat) else {
            print("could not load the credits data or make the scene")
            return false
        }
        let picture = model.pictures[number - 1]
        let target: [Float] = picture.pixels.flatMap { c in
            (0..<3).map { Float(byteFromVGA(Int(picture.palette[Int(c) * 3 + $0]))) }
        }
        let width = Int(entry.canvasSize.x), height = Int(entry.canvasSize.y)
        var results: [(step: Int, difference: Float)] = []
        var step = 0
        while step < first { scene.tick(); step += 1 }
        while step <= last {
            let frame = scene.classicReferenceFrame()
            if frame.count == width * height * 3 {
                results.append((step, difference(shrink(frame, width: width, height: height), target)))
            }
            for _ in 0..<stride { scene.tick() }
            step += stride
        }
        let best = results.sorted { $0.difference < $1.difference }.prefix(5)
        print("picture \(number) against \(entry.id), steps \(first)...\(last) by \(stride):")
        for r in best { print(String(format: "  step %5d: average difference %.1f", r.step, r.difference)) }
        return true
    }

    /// The frame shrunk to 160 x 100 by averaging (any canvas size; its shape is not kept).
    static func shrink(_ frame: [UInt8], width: Int, height: Int) -> [Float] {
        var out = [Float](repeating: 0, count: 160 * 100 * 3)
        for y in 0..<100 {
            let y0 = y * height / 100, y1 = max((y + 1) * height / 100, y0 + 1)
            for x in 0..<160 {
                let x0 = x * width / 160, x1 = max((x + 1) * width / 160, x0 + 1)
                var sum = SIMD3<Float>(0, 0, 0)
                for yy in y0..<y1 {
                    for xx in x0..<x1 {
                        let i = (yy * width + xx) * 3
                        sum += SIMD3(Float(frame[i]), Float(frame[i + 1]), Float(frame[i + 2]))
                    }
                }
                sum /= Float((y1 - y0) * (x1 - x0))
                out[(y * 160 + x) * 3] = sum.x; out[(y * 160 + x) * 3 + 1] = sum.y; out[(y * 160 + x) * 3 + 2] = sum.z
            }
        }
        return out
    }

    static func difference(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Float(a.count)
    }
}
