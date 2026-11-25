import Foundation

/// The rotozoomer (part 3 of the lens part, `LENS/MAIN.C` `part3` and `LENS/ASM.ASM` `_rotate`, Psi):
/// a squeezed copy of the lens picture, repeated in every direction, turning and zooming.
///
/// - The picture: a 256x256 tile (`rotpic`), columns 32...287 of the lens picture, rows stretched 11/10
///   (tile row y shows picture row y·10/11 − 18); the rows that fall outside the picture show its row 0.
/// - The screen: 160x100 big pixels (a tweaked 320x400 mode, each pixel 2 wide and 4 tall).
/// - The camera: 2000 steps of (x, y, xa, ya), played from `LENS.EXP` in the demo; that file was made by
///   the formulas in MAIN.C's SAVEPATH branch, which give all 2000 steps exactly (worked out here).
/// - Palette: step s draws path[s], then the frame counter is s + 1 and the palette is set: while it is
///   below 16 the picture is brightened by (15 − frame)·5 levels (a flash in from white); above 1872 it
///   fades towards white by (frame − 1872) / 2 of 63. After the last step everything is white.
/// - In the demo the loop also stops as soon as "music plus" is above −4 (checked before each step);
///   on its own, the scene shows white for a moment and starts again.
struct RotozoomerModel {
    static let pathSteps = 2000
    static let musicCue = -4
    /// White steps after the last step, on its own, before starting again.
    static let endWhiteSteps = 35

    /// One step of the camera. `x`, `y`, `xa`, `ya` are the whole numbers the original used; `exact`
    /// holds the same four without rounding (for the Modern look's smooth motion).
    struct PathPoint: Equatable {
        var x: Int, y: Int, xa: Int, ya: Int
        var exact: SIMD4<Double>
    }

    /// MAIN.C part3's SAVEPATH branch, with Microsoft C's rules (a double stored in an int is truncated,
    /// int / 16 truncates towards zero).
    static let path: [PathPoint] = {
        var out: [PathPoint] = []
        out.reserveCapacity(pathSteps)
        var d1 = 0.0, d2 = 0.00007654321, d3 = 0.0, scale = 2.0, scalea = -0.01
        for frame in 0..<pathSteps {
            let fx = 70.0 * sin(d1) - 30
            let fy = 70.0 * cos(d1) + 60
            d1 -= 0.005
            let fxa = -1024.0 * sin(d2) * scale
            let fya = 1024.0 * cos(d2) * scale
            let xa = Int(fxa), ya = Int(fya)
            out.append(PathPoint(x: Int(fx) - xa / 16, y: Int(fy) - ya / 16, xa: xa, ya: ya,
                                 exact: SIMD4(fx - fxa / 16, fy - fya / 16, fxa, fya)))
            d2 += d3
            scale += scalea
            if frame > 25 && d3 < 0.02 { d3 += 0.00005 }
            if frame < 270 {
                if scale < 0.9 && scalea < 1 { scalea += 0.0001 }
            } else if frame < 400 {
                if scalea > 0.001 { scalea -= 0.0001 }
            } else if frame > 1600 {
                if scalea > -0.1 { scalea -= 0.001 }
            } else if frame > 1100 {
                let a = min(frame - 900, 100)
                if scalea < 256 { scalea += 0.000001 * Double(a) }
            }
        }
        return out
    }()

    /// Steps since the start (0 shows path[0]).
    private(set) var step = 0
    /// Play Demo's music cue has come: white from now on.
    private(set) var stopped = false
    /// Inside Play Demo: the music's "music plus", given before each step. nil on its own.
    var musicPlus: Int?

    mutating func reset() {
        step = 0
        stopped = false
    }

    mutating func tick() {
        if stopped { return }
        step += 1
        if let plus = musicPlus, plus > Self.musicCue, step < Self.pathSteps {
            stopped = true
            return
        }
        if musicPlus == nil && step >= Self.pathSteps + Self.endWhiteSteps { reset() }
    }

    /// Whether the turning picture shows (otherwise the screen is white).
    var showsPicture: Bool { !stopped && step < Self.pathSteps }

    /// The fade showing. 1993 look: `smooth` false, whole steps and the original's whole numbers. Modern
    /// look: `alpha` of a step on, gliding.
    func fade(alpha: Float = 0, smooth: Bool = false) -> PictureFade {
        guard showsPicture else { return PictureFade(towardWhite: true, keep: 0, outOf: 63) }
        let frame = step + 1
        let at = Float(frame) + (smooth ? alpha : 0)
        if at < 16 { return .brighten(max((15 - at) * 5, 0)) }
        let start = Self.pathSteps - 128
        if frame > start || at > Float(start) {
            let a = smooth ? min((at - Float(start)) / 2, 63) : Float(min((frame - start) / 2, 63))
            return PictureFade(towardWhite: true, keep: 63 - a, outOf: 63)
        }
        return .none
    }

    /// The camera for the Modern look, `alpha` of the way to the next step, without rounding.
    func exactCamera(alpha: Float) -> SIMD4<Double> {
        let s = min(step, Self.pathSteps - 1)
        let a = Self.path[s].exact, b = Self.path[min(s + 1, Self.pathSteps - 1)].exact
        return a + (b - a) * Double(alpha)
    }

    // MARK: The 1993 picture

    /// The 256x256 tile (`rotpic`) from the lens picture's 320x200 colour numbers, as MAIN.C makes it.
    static func tile(fromPicture back: [UInt8]) -> [UInt8] {
        var rotpic = [UInt8](repeating: 0, count: 65536)
        for x in 0..<256 {
            for y in 0..<256 {
                var a = y * 10 / 11 - 36 / 2
                if a < 0 || a > 199 { a = 0 }
                rotpic[x + y * 256] = back[x + 32 + a * 320]
            }
        }
        return rotpic
    }

    /// The same tile turned a quarter (`rotpic90`), which `_rotate` reads when the picture lies more
    /// than 45 degrees over.
    static func turned(_ rotpic: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 65536)
        for x in 0..<256 {
            for y in 0..<256 { out[x + y * 256] = rotpic[y + (255 - x) * 256] }
        }
        return out
    }

    /// `_rotate(x, y, xa, ya)` in whole numbers, as the assembly does it: the 160x100 screen.
    ///
    /// - The row start moves by (xa, ya)·64 in 16.16 fixed point, times 307/256 for the pixel shape; only
    ///   its whole part is used (low byte of x and y).
    /// - Along a row, a table of 160 offsets: x grows by ya·64, y by −xa·64, each an 8-bit whole part with
    ///   its own 16-bit fraction (the assembly patches these into its own instructions).
    /// - A pixel is tile[(row start + offset) mod 65536]: a 16-bit sum, so when x passes 255 it carries
    ///   into y (one row's shift at the tile's left/right edge, as in 1993).
    /// - If |xa| > |ya| it reads the turned tile with the camera turned to match.
    static func rotate(_ p: PathPoint, tile: [UInt8], turnedTile: [UInt8]) -> [UInt8] {
        let m16: UInt32 = 0xFFFF
        var xpos = (UInt32(truncatingIfNeeded: p.x) & m16) << 16
        var ypos = (UInt32(truncatingIfNeeded: p.y) & m16) << 16
        var xadd = UInt32(bitPattern: Int32(Int16(truncatingIfNeeded: p.xa)) << 6)
        var yadd = UInt32(bitPattern: Int32(Int16(truncatingIfNeeded: p.ya)) << 6)
        var useTurned = false
        if abs(Int32(bitPattern: xadd)) > abs(Int32(bitPattern: yadd)) {
            useTurned = true
            (xadd, yadd) = (0 &- yadd, xadd)
            (xpos, ypos) = (0 &- ypos, xpos)
        }
        // The offset table.
        let cx = yadd & m16, bl = UInt8(truncatingIfNeeded: yadd >> 16)
        let xLow = xadd & m16
        // −(xadd's 24 bits): neg dx, then neg bh and subtract the borrow.
        let dx = (0 &- xLow) & m16
        let bh = (0 &- UInt8(truncatingIfNeeded: xadd >> 16)) &- (xLow != 0 ? 1 : 0)
        var si: UInt32 = 0, di: UInt32 = 0
        var al: UInt8 = 0, ah: UInt8 = 0
        var offsets = [UInt16](repeating: 0, count: 160)
        for c in 0..<160 {
            si += cx
            al = al &+ bl &+ UInt8(si >> 16)
            si &= m16
            di += dx
            ah = ah &+ bh &+ UInt8(di >> 16)
            di &= m16
            offsets[c] = UInt16(al) | UInt16(ah) << 8
        }
        // The pixel shape: 307/256 (unsigned multiply, low 32 bits, then an arithmetic shift).
        xadd = UInt32(bitPattern: Int32(bitPattern: 307 &* xadd) >> 8)
        yadd = UInt32(bitPattern: Int32(bitPattern: 307 &* yadd) >> 8)
        var screen = [UInt8](repeating: 0, count: 160 * 100)
        let source = useTurned ? turnedTile : tile
        source.withUnsafeBufferPointer { tex in
            for row in 0..<100 {
                ypos = ypos &+ yadd
                xpos = xpos &+ xadd
                let start = UInt16((ypos >> 8) & 0xFF00) | UInt16((xpos >> 16) & 0xFF)
                for c in 0..<160 { screen[row * 160 + c] = tex[Int(start &+ offsets[c])] }
            }
        }
        return screen
    }
}
