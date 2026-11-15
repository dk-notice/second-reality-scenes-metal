import Foundation
import Metal

/// Checks run with `SRMetal --selftest`. No window is opened.
///
/// The main check, for every scene: draw the classic look on the graphics chip, read the picture back,
/// and compare it pixel by pixel with the same frame worked out on the processor using the 1993 rules.
enum SelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            print("\(passed ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
            if !passed { ok = false }
        }

        // Tables and pictures that replace the original's data files. The expected values were taken
        // from those files (SINIT.DAT, SIN1024.INC, _CIRCLE.OBK, _CIRCLE2.OBK).
        let sinT = DotTunnelModel.sinTable
        let cosT = DotTunnelModel.cosTable
        check("tunnel sine table matches original spot values",
              Array(sinT[1000...1003]) == [-13, -12, -12, -11] && Array(sinT[4090...4096]) == [-14, -12, -9, -7, -5, -2, 0])
        check("tunnel cosine table matches original spot values",
              Array(cosT[1000...1003]) == [52, 52, 53, 54] && cosT[2048] == 128)
        check("shared sine table matches original spot values",
              Array(SinTable.sin1024[0...5]) == [0, 1, 3, 4, 6, 7] && SinTable.sin1024[256] == 256 && SinTable.sin1024[768] == -256)
        check("interference ring picture matches original file",
              crc32(quarter(of: InterferenceModel.ringPicture)) == 3_479_151_390)
        check("interference stripe picture matches original file",
              crc32(quarter(of: InterferenceModel.stripePicture)) == 990_890_590)

        // The plasma's four tables, against checksums of the original PSINI.INC, LSINI16.INC, LSINI4.INC
        // and PTAU.INC (16-bit tables as low byte, high byte).
        func words(_ table: [UInt16]) -> [UInt8] { table.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] } }
        check("plasma sine table matches original file", crc32(PlasmaModel.psini) == 942_993_316)
        check("plasma bend table 16 matches original file", crc32(words(PlasmaModel.lsini16)) == 3_664_524_141)
        check("plasma bend table 4 matches original file", crc32(words(PlasmaModel.lsini4)) == 3_446_065_726)
        check("plasma brightness ramp matches original file",
              crc32(PlasmaModel.ptau.map { UInt8($0) }) == 404_302_250)

        // The bar-filling routine: a plain 40x20 rectangle must fill exactly 800 pixels,
        // left and top edges included, right and bottom edges not (the original's rule).
        var raster = BarRasteriser()
        raster.add([.init(x: 10, y: 10), .init(x: 50, y: 10), .init(x: 50, y: 30), .init(x: 10, y: 30)])
        let filled = raster.filled()
        check("bar fill: rectangle fills the expected pixels",
              filled.reduce(0) { $0 + Int($1) } == 800 && filled[10 * 320 + 10] == 1 && filled[29 * 320 + 49] == 1
                  && filled[10 * 320 + 50] == 0 && filled[30 * 320 + 10] == 0)

        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            check("Metal device available", false)
            return false
        }

        for entry in SceneCatalog.all {
            do {
                let scene = try entry.make(device, Renderer.pixelFormat)
                let width = Int(entry.canvasSize.x)
                let height = Int(entry.canvasSize.y)
                guard let texture = Renderer.makeClassicTexture(device: device, canvasSize: entry.canvasSize) else {
                    check("\(entry.title): classic texture created", false)
                    continue
                }

                var tick = 0
                for target in entry.checkpoints {
                    while tick < target {
                        scene.tick()
                        tick += 1
                    }
                    guard let commands = queue.makeCommandBuffer() else { continue }
                    Renderer.drawClassic(scene: scene, canvasSize: entry.canvasSize, into: texture, commands: commands)
                    commands.commit()
                    commands.waitUntilCompleted()

                    // The picture comes back as blue, green, red, alpha for each pixel.
                    var pixels = [UInt8](repeating: 0, count: width * height * 4)
                    texture.getBytes(&pixels, bytesPerRow: width * 4,
                                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

                    let reference = scene.classicReferenceFrame()
                    var lit = 0
                    var wrong = 0
                    for i in 0..<(width * height) {
                        let expected = (Int(reference[i * 3]), Int(reference[i * 3 + 1]), Int(reference[i * 3 + 2]))
                        let drawn = (Int(pixels[i * 4 + 2]), Int(pixels[i * 4 + 1]), Int(pixels[i * 4]))
                        if expected != (0, 0, 0) { lit += 1 }
                        // Allow 1 level of difference for rounding 0...63 up to 0...255.
                        if abs(drawn.0 - expected.0) > 1 || abs(drawn.1 - expected.1) > 1 || abs(drawn.2 - expected.2) > 1 {
                            wrong += 1
                        }
                    }
                    check("\(entry.title), step \(target): graphics chip matches 1993 reference", wrong == 0,
                          "\(lit) lit pixels, \(wrong) wrong")
                }
            } catch {
                check("\(entry.title) starts", false, "\(error)")
            }
        }

        // The tunnel should loop back to an empty tunnel after its full run.
        var tunnel = DotTunnelModel()
        for _ in 0..<DotTunnelModel.lengthInTicks { tunnel.tick() }
        check("Dot Tunnel loops after \(DotTunnelModel.lengthInTicks) steps", tunnel.tickCount == 0)

        // Interference should loop seamlessly: after one full run it is back at its first frame, and the
        // last step before the loop differs from the first frame no more than any two neighbouring steps do.
        func changed(_ a: [UInt8], _ b: [UInt8]) -> Int {
            var count = 0
            for i in stride(from: 0, to: a.count, by: 3) where a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] {
                count += 1
            }
            return count
        }
        var interference = InterferenceModel(part: .interference)
        let firstFrame = interference.classicReferenceFrame()
        interference.tick()
        let secondFrame = interference.classicReferenceFrame()
        for _ in 1..<(InterferenceModel.interferenceTicks - 1) { interference.tick() }
        let lastFrame = interference.classicReferenceFrame()
        interference.tick()
        check("Interference returns to its first frame after \(InterferenceModel.interferenceTicks) steps",
              interference.classicReferenceFrame() == firstFrame)
        let ordinaryStep = changed(firstFrame, secondFrame)
        let loopStep = changed(lastFrame, firstFrame)
        check("Interference loop point is no bigger a jump than an ordinary step",
              loopStep <= ordinaryStep * 11 / 10,
              "\(loopStep) pixels change across the loop, \(ordinaryStep) across an ordinary step")

        // Plasma should loop exactly: any moment and the same moment one full run later look identical,
        // and the loop point itself is black (the band has fallen away; the next palette has not begun).
        var plasma = PlasmaModel()
        for _ in 0..<400 { plasma.tick() }
        let plasmaBefore = plasma.classicReferenceFrame()
        for _ in 0..<(PlasmaModel.lengthInTicks - 400) { plasma.tick() }
        check("Plasma is black at its loop point", !plasma.classicReferenceFrame().contains { $0 != 0 })
        for _ in 0..<400 { plasma.tick() }
        check("Plasma repeats exactly after \(PlasmaModel.lengthInTicks) steps",
              plasma.classicReferenceFrame() == plasmaBefore && plasmaBefore.contains { $0 != 0 })

        print(ok ? "All checks passed." : "Some checks FAILED.")
        return ok
    }

    /// The top-left quarter (320x200) of a 640x400 picture: the part the original stored on disk.
    private static func quarter(of picture: [UInt8]) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(320 * 200)
        for y in 0..<200 {
            result.append(contentsOf: picture[(y * 640)..<(y * 640 + 320)])
        }
        return result
    }

    /// A standard checksum (CRC-32): a single number that changes if any byte of the data changes.
    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}
