import CoreGraphics
import Foundation
import Metal
import simd

/// Self-test checks for the rotozoomer (run by `CoreChecks.run`; see `App/CoreChecks.swift`).
extension CoreChecks {
    // MARK: - The rotozoomer (added 2026-11-24)

    /// The camera path and the timing, without drawing.
    static func rotozoomerTiming(_ check: (String, Bool, String) -> Void) {
        let path = RotozoomerModel.path
        var bytes: [UInt8] = []
        for p in path {
            for v in [p.x, p.y, p.xa, p.ya] {
                let w = UInt16(bitPattern: Int16(v))
                bytes += [UInt8(w & 255), UInt8(w >> 8)]
            }
        }
        // 603415142 = CRC-32 of the 16,000 bytes of camera path in the original LENS/LENS.EXP (pathdata2).
        check("Rotozoomer: the camera path worked out from MAIN.C's formulas equals all 2000 steps of the original LENS.EXP",
              path.count == 2000 && SelfTest.crc32(bytes) == 603_415_142, "\(SelfTest.crc32(bytes))")
        let turned = path.filter { abs($0.xa) > abs($0.ya) }.count
        check("Rotozoomer: the turned tile is read on 920 of the 2000 steps, as tools/rotozoom_reference.py counts",
              turned == 920, "\(turned)")
        // The fade's value on the steps either side of each change; on its own, 35 white steps at the end.
        var model = RotozoomerModel()
        func run(to step: Int) -> PictureFade {
            while model.step < step { model.tick() }
            return model.fade()
        }
        let first = run(to: 0), lastFlash = run(to: 13), flashOver = run(to: 14)
        let beforeFade = run(to: 1871), fadeStart = run(to: 1872), fadeNext = run(to: 1873)
        _ = run(to: 2000)
        let stillShown = model.showsPicture
        for _ in 2000..<2035 { model.tick() }
        check("Rotozoomer: flashes in from white over 14 steps (70 levels, 5 fewer a step), fades to white from step 1873 (one level every 2 steps), starts again after 2035 steps",
              first.add == 70 && lastFlash.add == 5 && flashOver.add == 0 && flashOver.keep == 1 && beforeFade.keep == 1
                && fadeStart.keep == 63 && fadeStart.outOf == 63 && fadeNext.keep == 62 && !stillShown && model.step == 0,
              "\(first.add) \(lastFlash.add) \(flashOver.add) \(beforeFade.keep) \(fadeStart.keep)/\(fadeStart.outOf) \(fadeNext.keep) \(stillShown) \(model.step)")
        // Inside Play Demo it stops (white) as soon as "music plus" is above -4.
        var inDemo = RotozoomerModel()
        inDemo.musicPlus = -20
        for _ in 0..<1000 { inDemo.tick() }
        let running = inDemo.showsPicture
        inDemo.musicPlus = -3
        inDemo.tick()
        check("Rotozoomer: inside Play Demo it turns white when music plus goes above -4",
              running && !inDemo.showsPicture && inDemo.fade().keep == 0, "")
    }

    /// The 1993 pictures against tools/rotozoom_reference.py (which works the assembly out register by
    /// register from the original LENS.EXB and LENS.EXP).
    static func rotozoomerPictures(_ check: (String, Bool, String) -> Void, device: MTLDevice) throws {
        let scene = try RotozoomerScene(device: device, pixelFormat: Renderer.pixelFormat)
        let steps = [0, 1, 7, 14, 15, 16, 100, 270, 500, 777, 1000, 1300, 1600, 1871, 1872, 1873, 1900, 1990, 1999]
        let expected: [UInt32] = [3_826_628_422, 3_826_628_422, 1_689_986_678, 3_134_328_650, 1_297_677_111,
                                  2_961_328_681, 3_122_540_278, 1_399_456_430, 3_771_225_021, 205_195_275,
                                  3_401_772_704, 1_384_129_999, 3_316_621_840, 1_934_200_087, 4_026_307_715,
                                  3_530_408_979, 1_741_187_595, 2_911_997_760, 3_826_628_422]
        var sums: [UInt32] = []
        for step in 0...steps.last! {
            if steps.contains(step) { sums.append(SelfTest.crc32(scene.classicReferenceFrame())) }
            scene.tick()
        }
        check("Rotozoomer: 1993 pictures match tools/rotozoom_reference.py at steps \(steps)", sums == expected, "\(sums)")
    }
}
