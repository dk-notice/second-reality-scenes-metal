import Foundation
import Metal

/// Checks run with `SRMetal --selftest`. No window is opened.
///
/// The main check: draw the classic look on the graphics chip, read the picture back, and compare it
/// pixel by pixel with the same frame worked out on the processor using the 1993 rules.
enum SelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            print("\(passed ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
            if !passed { ok = false }
        }

        // Spot values taken from the original SINIT.DAT file.
        let sinT = DotTunnelModel.sinTable
        let cosT = DotTunnelModel.cosTable
        check("sine table matches original spot values",
              Array(sinT[1000...1003]) == [-13, -12, -12, -11] && Array(sinT[4090...4096]) == [-14, -12, -9, -7, -5, -2, 0])
        check("cosine table matches original spot values",
              Array(cosT[1000...1003]) == [52, 52, 53, 54] && cosT[2048] == 128)

        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            check("Metal device available", false)
            return false
        }

        do {
            let scene = try DotTunnelScene(device: device, pixelFormat: Renderer.pixelFormat)
            let canvas = SIMD2<Float>(320, 200)
            guard let texture = Renderer.makeClassicTexture(device: device, canvasSize: canvas) else {
                check("classic texture created", false)
                return false
            }

            var tick = 0
            for target in [1, 60, 250, 500, 777, 1000] {
                while tick < target {
                    scene.tick()
                    tick += 1
                }
                guard let commands = queue.makeCommandBuffer() else { continue }
                Renderer.drawClassic(scene: scene, canvasSize: canvas, into: texture, commands: commands)
                commands.commit()
                commands.waitUntilCompleted()

                var pixels = [UInt8](repeating: 0, count: 320 * 200 * 4)
                texture.getBytes(&pixels, bytesPerRow: 320 * 4,
                                 from: MTLRegionMake2D(0, 0, 320, 200), mipmapLevel: 0)

                let reference = scene.model.classicReferenceFrame()
                var lit = 0
                var wrong = 0
                for i in 0..<(320 * 200) {
                    let expected = Int((Double(reference[i]) * 255 / 63).rounded())
                    if expected > 0 { lit += 1 }
                    // Allow 1 level of difference for rounding 0...63 up to 0...255.
                    if abs(Int(pixels[i * 4]) - expected) > 1 { wrong += 1 }
                }
                check("step \(target): graphics chip matches 1993 reference", wrong == 0,
                      "\(lit) lit pixels, \(wrong) wrong")
            }

            // After the full run the scene should have looped back to an empty tunnel.
            while tick < DotTunnelModel.lengthInTicks {
                scene.tick()
                tick += 1
            }
            check("scene loops after \(DotTunnelModel.lengthInTicks) steps", scene.model.tickCount == 0)
        } catch {
            check("dot tunnel scene starts", false, "\(error)")
        }

        print(ok ? "All checks passed." : "Some checks FAILED.")
        return ok
    }
}
