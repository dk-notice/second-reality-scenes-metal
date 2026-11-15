import Foundation
import simd

/// The scene's script: MAIN.C's variables and the part of its main loop that moves them on by one
/// frame. No drawing. Kept separate so the modern look can ask "where will things be one step
/// from now" without redoing the drawing.
///
/// The original was compiled with 16-bit whole numbers. Where a sum can leave that range the
/// wrap-around is kept (`int16`), because at least once it matters: the third bounce.
struct GlenzScript {
    /// The original's frame counter: 0 before the first frame of its main loop.
    var frame = 0
    /// Turn angles in tenths of a degree, kept below three full turns.
    var rx = 0, ry = 0, rz = 0
    let zpos = 7500
    /// Height of the first glenz and its speed (down is positive).
    var ypos = -9000, yposa = 0
    /// Each bounce keeps boingm/boingd of the speed: 6/7, then 8/8, 10/9, 12/10 ...
    var boingm = 6, boingd = 7
    /// The jelly wobble (a spring) and its speed.
    var jello = 0, jelloa = 0
    var xscale = 120, yscale = 120, zscale = 120
    /// Size of the second (red) glenz.
    var bscale = 0
    /// Wander of the first glenz and of the second.
    var oxp = 0, oyp = 0, ozp = 0
    var oxb = 0, oyb = 0, ozb = 0
    var lightshift = 9
    /// The 16 "floor" colours that every lit face's colours are built on (`backpal`).
    var backpal = GlenzFloorArt.palette
    /// Colours 0-15 as shown (`pal`): `backpal`, faded where the script says so.
    var pal = GlenzFloorArt.palette
    /// On frames where the script blanks two rows of the floor picture: the first of them.
    var eraseRow: Int?
    /// The wobble value the current squash was worked out from (for the modern look, which wants
    /// the squash without the rounding to whole steps).
    var squashJello = 0

    static func int16(_ value: Int) -> Int { Int(Int16(truncatingIfNeeded: value)) }

    mutating func step() {
        let int16 = Self.int16
        eraseRow = nil
        frame += 1
        rx = (rx + 32) % 10800
        ry = (ry + 7) % 10800
        rz %= 10800

        if frame > 900 {
            // Both glenzes wander on sine paths; the first one's wander grows in over 50 frames.
            var a = frame - 900
            var b = min(frame - 900, 50)
            oxp = int16(SinTable.sin(a * 3) * b) / 10
            oyp = int16(SinTable.sin(a * 5) * b) / 10
            ozp = int16((SinTable.sin(a * 4) / 2 + 128) * b) / 16
            if frame > 1800 {
                // The second glenz's wander grows until it swings right across the screen.
                a = min(frame - 1800 + 64, 1024)
                oxb = int16(-SinTable.sin(a * 6) * a / 40)
                oyb = int16(-SinTable.sin(a * 7) * a / 40)
                ozb = int16((SinTable.sin(a * 8) + 128) * a / 40)
            } else {
                oxb = -SinTable.sin(a * 6)
                oyb = -SinTable.sin(a * 7)
                ozb = SinTable.sin(a * 8) + 128
            }
            // From frame 1800 the first glenz accelerates up and out of the picture.
            b = 1800 - frame
            if b < 0 {
                if b < -99 { b = -99 }
                oyp = int16(oyp - b * b / 2)
            }
        }

        if frame > 800 {
            if frame > 1220 + 789 {
                // The end: both shrink to nothing.
                if xscale > 0 { xscale -= 1 }
                if yscale > 0 { yscale -= 1 }
                if zscale > 0 { zscale -= 1 }
                if bscale > 0 { bscale -= 1 }
            } else {
                // The second glenz grows.
                if bscale < 180 { bscale += 2 } else { bscale = 180 }
            }
            if bscale > xscale { lightshift = 10 }
        } else {
            if frame < 640 + 70 {
                // Falling and bouncing.
                yposa = int16(yposa + 31)
                ypos = int16(ypos + yposa / 40)
                if ypos > -300 {
                    ypos = int16(ypos - yposa / 40)
                    yposa = int16(int16(-yposa) * boingm) / boingd
                    boingm += 2
                    boingd += 1
                }
                if ypos > -900 && yposa > 0 {
                    // Close to the floor on the way down: squash by how deep it is.
                    jello = int16((ypos + 900) * 5) / 3
                    jelloa = 0
                }
            } else {
                // Rising to the middle of the screen.
                if ypos > -2800 { ypos -= 16 } else if ypos < -2800 { ypos += 16 }
            }
            squashJello = jello
            xscale = 120 + jello / 30
            yscale = xscale
            zscale = 120 - jello / 30
            var a = jello
            jello = int16(jello + jelloa)
            if (a < 0 && jello > 0) || (a > 0 && jello < 0) {
                jelloa = int16(jelloa * 5) / 6
            }
            a = jello / 20
            jelloa = int16(jelloa - a)
        }

        if frame > 1280 + 789 {
            // The end: colours 0-15 fade to black.
            let b = max(1280 + 789 + 64 - frame, 0)
            pal = backpal.map { UInt8(Int($0) * b / 64) }
        } else if frame > 700 {
            if frame < 765 {
                // The floor fades out...
                let b = max(764 - frame, 0)
                pal = backpal.map { UInt8(Int($0) * b / 64) }
            } else if frame < 790 {
                // ...is wiped from the picture, two rows a frame...
                eraseRow = 150 + (frame - 765) * 2
                if frame > 785 {
                    // ...and its 16 colours become the second glenz's reds.
                    for a in 0..<16 {
                        var r = 0, g = 0, b = 0
                        if a & 1 != 0 { r += 10 }
                        if a & 2 != 0 { r += 30 }
                        if a & 4 != 0 { r += 20 }
                        if a & 8 != 0 { r += 16; g += 16; b += 16 }
                        backpal[a * 3] = UInt8(min(r, 63))
                        backpal[a * 3 + 1] = UInt8(min(g, 63))
                        backpal[a * 3 + 2] = UInt8(min(b, 63))
                    }
                }
            } else if frame < 795 {
                pal = backpal
            }
        }
    }
}

/// The state and rules of the Glenz Vectors scene, with no graphics-chip code.
///
/// Based on Psi's original, GLENZ.EXE: MAIN.C (the script), MATH.ASM (turn matrix), VEC.ASM
/// (turning, projecting, face colours) and NEW.ASM (the filler, see `GlenzFiller`). "Glenz" was
/// demo slang for a see-through faceted solid. The 1993 version worked like this:
///
///  - Screen mode 13h: 320x200 pixels, one byte each, 256 colours.
///  - A hand-drawn chequered plate (a picture) is squashed onto the bottom of the screen with a
///    bounce, then left there as the background.
///  - The glenz is a cube with a four-sided pyramid on each side: 14 corners, 24 triangles. It is
///    turned, squashed (the jelly), moved, and projected with a divide by distance.
///  - Faces are NOT sorted and NOT blended. Each face gets a colour NUMBER, the filler XORs the
///    numbers of all faces covering a pixel, and the palette is arranged so that every possible
///    combination shows as a sensible mixed colour.
///  - Lighting: a front face's brightness is simply its area on screen, and it is applied by
///    rewriting 16 palette entries for that face every frame.
struct GlenzModel {
    // MARK: - Size and length

    static let width = 320
    static let height = 200

    /// Steps the plate takes to fall and settle (MAIN.C's first loop, which ends by itself).
    static let fallSteps = 178
    /// Steps between the plate settling and the glenz appearing. The original waited for a point
    /// in the music here; this number is this version's choice.
    static let pauseSteps = 35
    /// The original's frame counter is the step number minus this.
    static let firstFrameOffset = fallSteps + pauseSteps - 1
    /// Everything is black from the original's frame 2133 (step 2345); the loop restarts soon after.
    static let lengthInTicks = 2360

    // MARK: - Tables and shapes

    /// MATHSIN.INC: sine in 3600 steps (tenths of a degree), 32767 tall, with the first quarter
    /// repeated at the end so a cosine can be read 900 entries on. The formula reproduces the file
    /// except for two entries where the true value sits exactly on a rounding edge.
    static let sine: [Int] = {
        var table = (0..<4500).map { (i: Int) -> Int in
            Int((Foundation.sin(Double(i) * 2 * Double.pi / 3600) * 32767 + 0.5).rounded(.towardZero))
        }
        table[3300] = -16383
        table[3900] = 16383
        return table
    }()

    /// The glenz shape: a cube (corners 0-7) and the six pyramid tips (8-13).
    static func glenzCorners(unit: Int, cube: Int, tip: Int) -> [SIMD3<Int>] {
        let c = cube * unit, t = tip * unit
        return [SIMD3(-c, -c, -c), SIMD3(c, -c, -c), SIMD3(c, c, -c), SIMD3(-c, c, -c),
                SIMD3(-c, -c, c), SIMD3(c, -c, c), SIMD3(c, c, c), SIMD3(-c, c, c),
                SIMD3(0, 0, -t), SIMD3(0, 0, t), SIMD3(t, 0, 0), SIMD3(-t, 0, 0), SIMD3(0, t, 0), SIMD3(0, -t, 0)]
    }

    /// MAIN.C `points` (first glenz) and `pointsb` (second glenz).
    static let firstCorners = glenzCorners(unit: 50, cube: 100, tip: 170)
    static let secondCorners = glenzCorners(unit: 99, cube: 60, tip: 105)

    /// The 24 triangles (MAIN.C `epolys`; `epolysb` lists the same corners).
    static let faces: [[Int]] = [
        [0, 1, 8], [1, 2, 8], [2, 3, 8], [3, 0, 8], [2, 1, 10], [1, 5, 10], [5, 6, 10], [6, 2, 10],
        [2, 6, 12], [6, 7, 12], [7, 3, 12], [3, 2, 12], [0, 3, 11], [3, 7, 11], [7, 4, 11], [4, 0, 11],
        [5, 1, 13], [1, 0, 13], [0, 4, 13], [4, 5, 13], [5, 4, 9], [4, 7, 9], [7, 6, 9], [6, 5, 9]]

    /// The colour number each face starts with. First glenz: 2, 4, 6 ... 48, one per face; the
    /// "2" bit, which alternates, says blue (set) or white. Second glenz: 4 and 2 alternately.
    static func firstFaceColour(_ face: Int) -> Int { 2 + 2 * face }
    static func secondFaceColour(_ face: Int) -> Int { face % 2 == 0 ? 4 : 2 }

    // MARK: - State

    private(set) var ticks = 0
    /// The plate's fall (MAIN.C's first loop): position in sixteenths of a row, and speed.
    private(set) var plateY = 0, plateSpeed = 0
    private(set) var plateSettled = false
    /// The plate position last drawn, in rows; nil before anything is drawn.
    private(set) var plateShown: Int?
    private var pause = 0
    private(set) var script = GlenzScript()
    /// True once the original's main loop has begun.
    private(set) var mainStarted = false

    /// The screen: one colour number per pixel.
    private(set) var screen = [UInt8](repeating: 0, count: width * height)
    /// The floor picture as left by the fall (`bgpic`), OR-ed into everything the filler writes.
    private var background = [UInt8](repeating: 0, count: width * height)
    /// The video card's 256 colours, 0...63 per channel.
    private(set) var colours: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 768)
        table.replaceSubrange(0..<48, with: GlenzFloorArt.palette)
        return table
    }()
    private(set) var filler = GlenzFiller()
    /// Which block of 16 palette entries each face colour of the first glenz currently owns
    /// (`rolcol`), and which blocks are taken (`rolused`).
    private var slotOfColour = [UInt8](repeating: 0, count: 256)
    private var slotTaken = [UInt8](repeating: 0, count: 256)

    mutating func reset() { self = GlenzModel() }

    // MARK: - One step

    private enum Event { case nothing, plate(Int), beginMainLoop, frame }

    /// Moves the clock on by one step: the plate's fall, then the pause, then the script.
    /// Draws nothing.
    private mutating func advance() -> Event {
        if !plateSettled {
            // MAIN.C's first loop: the plate falls, and bounces back with 2/3 of its speed.
            plateSpeed += 1
            plateY += plateSpeed
            if plateY > 48 * 16 {
                plateY -= plateSpeed
                plateSpeed = -plateSpeed * 2 / 3
                if plateSpeed > -4 && plateSpeed < 4 { plateSettled = true }
            }
            if !plateSettled {
                plateShown = plateY / 16
                return .plate(plateY / 16)
            }
        }
        if pause < Self.pauseSteps {
            pause += 1
            if pause == Self.pauseSteps {
                mainStarted = true
                return .beginMainLoop
            }
            return .nothing
        }
        script.step()
        return .frame
    }

    mutating func tick() {
        ticks += 1
        if ticks >= Self.lengthInTicks {
            reset()
            return
        }
        switch advance() {
        case .nothing:
            return
        case .plate(let y):
            Self.drawPlate(at: y, into: &screen)
            return
        case .beginMainLoop:
            beginMainLoop()
            return
        case .frame:
            break
        }

        if let row = script.eraseRow {
            for i in (row * Self.width)..<((row + 2) * Self.width) {
                background[i] = 0
                screen[i] = 0
            }
        }
        // The original uploaded colours 0-15 on every screen refresh.
        colours.replaceSubrange(0..<48, with: script.pal)

        filler.begin()
        if script.xscale > 4 {
            drawGlenz(second: false)
        }
        if script.frame > 800 && script.bscale > 4 {
            drawGlenz(second: true)
        }
        filler.finish(screen: &screen, background: background)
    }

    /// One frame of the plate's fall: the top 100 rows of the picture squashed between two screen
    /// rows that move down, with the plate's 8-row front edge underneath.
    static func drawPlate(at y: Int, into screen: inout [UInt8]) {
        let top = 130 + y / 2
        let bottom = 130 + y * 3 / 2
        func setRow(_ row: Int, _ source: Int?) {
            guard row <= 199 else { return }
            for x in 0..<width {
                screen[row * width + x] = source.map { GlenzFloorArt.pixels[$0 * width + x] } ?? 0
            }
        }
        for row in (top - 4)..<top { setRow(row, nil) }
        if bottom > top {
            let step = 25600 / (bottom - top)
            for row in top..<bottom { setRow(row, (row - top) * step / 256) }
        }
        for c in 0..<16 { setRow(bottom + c, c > 7 ? nil : 100 + c) }
    }

    /// What MAIN.C does between the fall and its main loop: all 256 colours get a starting value,
    /// and the screen is copied as the background picture.
    private mutating func beginMainLoop() {
        let floor = GlenzFloorArt.palette
        for a in 0..<256 {
            let b = a < 16 ? a : a & 7
            for k in 0..<3 {
                let lift = (a & 8 != 0 && a > 15) ? 16 : 0
                colours[a * 3 + k] = UInt8(min(Int(floor[b * 3 + k]) + lift, 63))
            }
        }
        background = screen
    }

    // MARK: - The 3D pipeline, in the original's whole numbers

    /// MATH.ASM `calcmatrix`: nine 16-bit numbers, 32767 meaning (almost) 1. Angles in tenths of
    /// a degree. Note the argument order of `cmatrix_yxz(rx, ry, rz)`: the routine it calls reads
    /// its "X" angle from where `ry` was stored and its "Y" angle from where `rx` was.
    static func turnMatrix(_ rx: Int, _ ry: Int, _ rz: Int) -> [Int] {
        func wrapped(_ angle: Int) -> Int { ((angle % 3600) + 3600) % 3600 }
        let int16 = GlenzScript.int16
        // Two 16-bit fractions multiplied: bits 15-30 of the product.
        func mul(_ a: Int, _ b: Int) -> Int { int16((a * b) >> 15) }
        let (ax, ay, az) = (wrapped(ry), wrapped(rx), wrapped(rz))
        let (xs, xc) = (sine[ax], sine[ax + 900])
        let (ys, yc) = (sine[ay], sine[ay + 900])
        let (zs, zc) = (sine[az], sine[az + 900])
        var m = [Int](repeating: 0, count: 9)
        m[7] = mul(ys, zs)
        m[0] = mul(yc, zc)
        m[7] = int16(m[7] - mul(m[0], xs))
        let xsys = mul(xs, ys)
        m[0] = int16(m[0] - mul(zs, xsys))
        m[1] = mul(zc, xsys)
        let yczs = mul(yc, zs)
        m[1] = int16(m[1] + yczs)
        m[6] = mul(xs, yczs)
        m[6] = int16(m[6] + mul(ys, zc))
        m[3] = int16(-mul(xc, zs))
        m[4] = mul(xc, zc)
        m[2] = int16(-mul(xc, ys))
        m[8] = mul(xc, yc)
        m[5] = xs
        return m
    }

    /// VEC.ASM `rotlist`: matrix times point, each row's sum shifted down 15 bits, then moved.
    /// A quirk kept: the routine hands back its second and third results the other way round, so
    /// every pass through it swaps the y and z axes. The scene passes every point through twice.
    static func rotate(_ p: SIMD3<Int>, by m: [Int], move: SIMD3<Int>) -> SIMD3<Int> {
        func int32(_ v: Int) -> Int { Int(Int32(truncatingIfNeeded: v)) }
        let r0 = int32((m[0] * p.x + m[1] * p.y + m[2] * p.z) >> 15)
        let r1 = int32((m[3] * p.x + m[4] * p.y + m[5] * p.z) >> 15)
        let r2 = int32((m[6] * p.x + m[7] * p.y + m[8] * p.z) >> 15)
        return SIMD3(int32(r0 + move.x), int32(r2 + move.y), int32(r1 + move.z))
    }

    /// One glenz's corners on the screen, by the original's whole-number rules.
    func screenCorners(second: Bool) -> [(x: Int, y: Int)] {
        let s = script
        let turn = second
            ? Self.turnMatrix(3600 - s.rx / 3, 3600 - s.ry / 3, 3600 - s.rz / 3)
            : Self.turnMatrix(s.rx, s.ry, s.rz)
        let scale = second ? [s.bscale * 64, 0, 0, 0, s.bscale * 64, 0, 0, 0, s.bscale * 64]
                           : [s.xscale * 64, 0, 0, 0, s.yscale * 64, 0, 0, 0, s.zscale * 64]
        let int16 = GlenzScript.int16
        let move = second ? SIMD3(s.oxb, int16(s.ypos + 1500 + s.oyb), int16(s.zpos + s.ozb))
                          : SIMD3(s.oxp, int16(s.ypos + 1500 + s.oyp), int16(s.zpos + s.ozp))
        return (second ? Self.secondCorners : Self.firstCorners).map { corner in
            var p = Self.rotate(Self.rotate(corner, by: turn, move: SIMD3(0, 0, 0)), by: scale, move: move)
            // VEC.ASM `cliplist`: while the floor is there, nothing goes below it.
            if !second && s.frame < 800 && p.y > 1500 { p.y = 1500 }
            // VEC.ASM `projlist` with the numbers VID.ASM `init320x200` sets.
            let z = max(p.z, 128)
            return (x: int16(256 * p.x / z + 160), y: int16(p.y * 213 / z + 130))
        }
    }

    /// Twice a face's area on screen, signed (VEC.ASM `checkhiddenbx`). Negative: facing away.
    static func facing(_ a: (x: Int, y: Int), _ b: (x: Int, y: Int), _ c: (x: Int, y: Int)) -> Int {
        let int16 = GlenzScript.int16
        let v = int16(a.x - b.x) * int16(a.y - c.y) - int16(a.y - b.y) * int16(a.x - c.x)
        return Int(Int32(truncatingIfNeeded: v))
    }

    private mutating func drawGlenz(second: Bool) {
        let corners = screenCorners(second: second)
        for (index, face) in Self.faces.enumerated() {
            var points = face.map { corners[$0] }
            // VEC.ASM `ceasypolylist`: a face whose first and last corners land on the same pixel
            // loses the last one. (The facing test still reads it.)
            let (a, b, c) = (points[0], points[1], points[2])
            if a == c { points.removeLast() }
            let v = Self.facing(a, b, c)
            let colour = second ? secondGlenzColour(face: index, facing: v) : firstGlenzColour(face: index, facing: v)
            filler.add(colour: colour, corners: points)
        }
    }

    /// VEC.ASM `demo_glz2`: the second glenz only ever uses the lowest three bits.
    private func secondGlenzColour(face: Int, facing v: Int) -> UInt8 {
        let colour = Self.secondFaceColour(face)
        return UInt8(v < 0 ? colour : (colour >> 1) & 1)
    }

    /// VEC.ASM `demo_glz`: the first glenz. A face turned away gets colour number 4 if it is a
    /// blue face and 0 (nothing) if it is white. A face turned towards the viewer gets a block of
    /// 16 palette entries of its own, and those 16 colours are rewritten now, lit by the face's
    /// area on screen: entry k = the face's colour plus a quarter of floor colour k.
    private mutating func firstGlenzColour(face: Int, facing v: Int) -> UInt8 {
        let colour = Self.firstFaceColour(face)
        if v < 0 {
            let slot = Int(slotOfColour[colour])
            slotOfColour[colour] = 0
            slotTaken[slot] = 0
            return UInt8(((colour >> 1) & 1) << 2)
        }
        let int16 = GlenzScript.int16
        var light: Int
        // What the processor's CL register holds further down, where it ends up as the red of a
        // blue face: a leftover, not a chosen value.
        var leftover: Int
        if script.lightshift == 9 {
            light = int16(v >> 7)
            leftover = 7
        } else {
            let first = (v >> 8) & 0xFFFF
            let second = (first >> 1) | (((v >> 16) & 1) << 15)
            light = int16(first + second)
            leftover = script.lightshift
        }
        light = min(max(light, 0), 63)

        var slot = Int(slotOfColour[colour])
        if slot == 0 {
            // Find a free block: 2, 4, 6 ... (so blocks start at colour 16, 32, 48 ...).
            var tries = 15
            slot = 2
            while slotTaken[slot] != 0 {
                slot += 2
                tries -= 1
                if tries == 0 { break }
            }
            leftover = tries
            // Another register accident, kept: fetching the block number wipes the light value,
            // so a face is unlit on the first frame it owns a block.
            light = 0
            slotOfColour[colour] = UInt8(slot)
            slotTaken[slot] = 1
        }
        let base = (slot << 3) & 255

        let (red, green, blue) = colour & 2 != 0 ? (leftover, light >> 1, light) : (light, light, light)
        for k in 0..<16 {
            let entry = ((base + k) & 255) * 3
            colours[entry] = UInt8(min((red + Int(script.backpal[k * 3]) >> 2) & 255, 63))
            colours[entry + 1] = UInt8(min((green + Int(script.backpal[k * 3 + 1]) >> 2) & 255, 63))
            colours[entry + 2] = UInt8(min((blue + Int(script.backpal[k * 3 + 2]) >> 2) & 255, 63))
        }
        return UInt8(base)
    }

    // MARK: - The 1993 picture

    /// The whole frame as red, green, blue bytes.
    func classicReferenceFrame() -> [UInt8] {
        var frame = [UInt8](repeating: 0, count: Self.width * Self.height * 3)
        for (i, pixel) in screen.enumerated() {
            let entry = Int(pixel) * 3
            frame[i * 3] = byteFromVGA(Int(colours[entry]))
            frame[i * 3 + 1] = byteFromVGA(Int(colours[entry + 1]))
            frame[i * 3 + 2] = byteFromVGA(Int(colours[entry + 2]))
        }
        return frame
    }

    // MARK: - For the modern look

    /// Everything the modern look draws, as triangles on the canvas (320x200 units, fractions allowed).
    struct ModernState {
        /// The plate: canvas rows of its far and near edges, and its brightness (0...1). Nil: no plate.
        var plate: (top: Float, bottom: Float, brightness: Float)?
        /// Front faces of the first glenz with their lit colours.
        var front: [(corners: [SIMD2<Float>], colour: SIMD3<Float>)] = []
        /// Faces that add a fixed tint: the second glenz's "1" front faces and "2" back faces.
        var tinted: [(corners: [SIMD2<Float>], colour: SIMD3<Float>)] = []
        /// Faces that toggle the "4" bit: blue back faces of the first glenz and "4" back faces of
        /// the second. Where two of them overlap the bit cancels, as XOR does.
        var toggling: [[SIMD2<Float>]] = []
        /// The colour the "4" bit stands for.
        var toggleTint = SIMD3<Float>(0, 0, 0)
    }

    /// Where one glenz is, in decimals.
    private struct Placement {
        /// Angles as given to `cmatrix_yxz`, tenths of a degree.
        var angles: SIMD3<Float>
        var scale: SIMD3<Float>
        var move: SIMD3<Float>
    }

    private func placement(second: Bool, ahead: Float) -> Placement? {
        let s = script
        guard mainStarted, s.frame >= 1 else { return nil }
        // The turn is the one thing known exactly between steps: 32 and 7 tenths of a degree per step.
        let rx = Float(s.rx) + 32 * ahead, ry = Float(s.ry) + 7 * ahead
        if second {
            guard s.frame > 800 && s.bscale > 4 else { return nil }
            return Placement(angles: SIMD3(3600 - rx / 3, 3600 - ry / 3, 3600),
                             scale: SIMD3(repeating: Float(s.bscale)),
                             move: SIMD3(Float(s.oxb), Float(s.ypos + 1500 + s.oyb), Float(s.zpos + s.ozb)))
        }
        guard s.xscale > 4 else { return nil }
        let wobble = Float(s.squashJello) / 30
        let scale = s.frame <= 800 ? SIMD3(120 + wobble, 120 + wobble, 120 - wobble)
                                   : SIMD3(Float(s.xscale), Float(s.yscale), Float(s.zscale))
        return Placement(angles: SIMD3(rx, ry, 0), scale: scale,
                         move: SIMD3(Float(s.oxp), Float(s.ypos + 1500 + s.oyp), Float(s.zpos + s.ozp)))
    }

    /// The plate's position for the modern look, in rows and fractions of a row; nil before it is drawn.
    /// Once settled it rests where its fall ended (47 15/16), not at the whole row the 1993 look draws
    /// (47). Until the 2026-11-14 review it switched to the whole row on the step it settled, which
    /// made the plate snap up by most of a row in one step, four times its speed just before.
    private func plateRow() -> Float? {
        guard plateShown != nil else { return nil }
        return Float(plateY) / 16
    }

    private func plateBrightness() -> Float {
        guard mainStarted else { return 1 }
        if script.frame <= 700 { return 1 }
        return Float(max(764 - script.frame, 0)) / 64
    }

    /// This model one step on, as far as the script goes (nothing is drawn). At the last step before
    /// the restart it is this model unchanged: nothing glides across the restart.
    private func oneStepOn() -> GlenzModel {
        var next = self
        if ticks + 1 < Self.lengthInTicks { _ = next.advance() }
        return next
    }

    /// One glenz's 14 corners on the canvas, `alpha` of the way from this step to the next, in
    /// decimals. Nil while that glenz is not drawn.
    func modernCorners(second: Bool, alpha: Float) -> [SIMD2<Float>]? {
        modernCorners(second: second, alpha: alpha, next: oneStepOn())
    }

    private func modernCorners(second: Bool, alpha: Float, next: GlenzModel) -> [SIMD2<Float>]? {
        guard var place = placement(second: second, ahead: alpha) else { return nil }
        if let later = next.placement(second: second, ahead: 0) {
            place.scale += (later.scale - place.scale) * alpha
            place.move += (later.move - place.move) * alpha
        }
        func radians(_ tenths: Float) -> Float { tenths * Float.pi / 1800 }
        // `cmatrix_yxz` hands its first two angles over crossed (see `turnMatrix`).
        let turn = Math3D.rotationYXZ(x: radians(place.angles.y), y: radians(place.angles.x), z: radians(place.angles.z))
        let clipToFloor = !second && script.frame < 800
        let source = second ? Self.secondCorners : Self.firstCorners
        return source.map { (corner: SIMD3<Int>) -> SIMD2<Float> in
            let turned = turn * SIMD3(Float(corner.x), Float(corner.y), Float(corner.z))
            // Two passes through the original's routine, each swapping y and z: the first
            // scale number widens x, the THIRD squashes the height, the second the depth.
            var p = SIMD3(turned.x * place.scale.x, turned.y * place.scale.z, turned.z * place.scale.y) / 512 + place.move
            if clipToFloor { p.y = min(p.y, 1500) }
            return Math3D.canvasPosition(p, focal: SIMD2(256, 213), centre: SIMD2(160, 130), near: 128)
        }
    }

    /// The plate's position as the modern look draws it, `alpha` of the way to the next step.
    func modernPlateRow(alpha: Float) -> Float? {
        guard let row = plateRow() else { return nil }
        return row + ((oneStepOn().plateRow() ?? row) - row) * alpha
    }

    /// The state `alpha` of the way from this step to the next (0...1).
    func modernState(alpha: Float) -> ModernState {
        let next = oneStepOn()
        func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * alpha }
        var state = ModernState()

        if let row = plateRow() {
            let y = mix(row, next.plateRow() ?? row)
            let brightness = mix(plateBrightness(), next.plateBrightness())
            if brightness > 0 { state.plate = (130 + y / 2, 130 + y * 1.5, brightness) }
        }

        // Colours 0-15, gliding between steps.
        func shown(_ index: Int) -> SIMD3<Float> {
            func channel(_ k: Int) -> Float { mix(Float(script.pal[index * 3 + k]), Float(next.script.pal[index * 3 + k])) / 63 }
            return SIMD3(channel(0), channel(1), channel(2))
        }
        state.toggleTint = shown(4)

        for second in [false, true] {
            guard let corners = modernCorners(second: second, alpha: alpha, next: next) else { continue }
            for (index, face) in Self.faces.enumerated() {
                let points = face.map { corners[$0] }
                let v = Math3D.screenFacing(points[0], points[1], points[2])
                if second {
                    let colour = Self.secondFaceColour(index)
                    if v < 0 {
                        if colour == 4 { state.toggling.append(points) } else { state.tinted.append((points, shown(2))) }
                    } else if colour == 2 {
                        state.tinted.append((points, shown(1)))
                    }
                } else {
                    let blue = Self.firstFaceColour(index) & 2 != 0
                    if v < 0 {
                        if blue { state.toggling.append(points) }
                        continue
                    }
                    let nine = script.lightshift == 9
                    let light = min(max(nine ? v / 128 : v * 3 / 512, 0), 63) / 63
                    let colour = blue ? SIMD3(Float(nine ? 7 : 10) / 63, light / 2, light) : SIMD3(repeating: light)
                    state.front.append((points, colour))
                }
            }
        }
        return state
    }
}
