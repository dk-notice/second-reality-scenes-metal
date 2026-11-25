import Foundation
import simd

/// The state and rules of the Plasma Cube scene, with no drawing code.
///
/// Based on Wildfire's original: the second half of PLZPART.EXE (VECT.C, PLZFILL.C, PLZA.ASM,
/// SPLINE.ASM with RATA.INC and SPLINE.INC, SINIT.INC). The 1993 version worked like this:
///
///  - A cube with corners at +-125 is turned by three angles, moved, and projected with a divide
///    by its distance. All in 16-bit whole numbers.
///  - Where the cube is, how it is turned and where the light is come from a hand-made list of
///    path points, blended smoothly: every 64 frames the blend moves on by one point.
///  - Only the faces turned towards the viewer are drawn (at most three). A cube never needs sorting.
///  - Each face is filled with a wavy texture that is worked out once when the program starts. What
///    makes it flow is a second table that shifts each texture row sideways, and scrolls by one row
///    per frame.
///  - Lighting is done with the palette: the three pairs of opposite faces each own 64 colours, and
///    the whole 64 are dimmed by how squarely the face meets the light.
///  - The scene ends by itself: the light swings round behind the cube, which goes black as it
///    comes to rest.
///
/// Inside Play Demo it follows the part's waits (VECT.C 114-120): the screen is cleared and black until
/// "music plus" >= 13; the loop then shows its empty first page for one refresh, counts it, and draws,
/// so the step that meets the cue is still black and the n-th step after it shows the original's frame
/// n, from a fresh start (no lead-in of this version's). It runs until the script cuts it; no second run.
struct PlasmaCubeModel {
    // MARK: - Size and length

    static let width = 320
    /// The mode showed each picture row on three monitor lines: 134 rows fill the 400 lines.
    static let rows = 134
    static let canvasHeight = 400

    /// Steps this version runs before the original's first frame, so the cube starts fully below
    /// the screen (the original's first frame already showed the tip of one corner).
    static let leadIn = 16
    /// The cube is black from the original's frame 1995 on; the loop restarts a little later.
    static let lengthInTicks = 2048

    // MARK: - Tables

    static func sine(_ angle: Int) -> Int { Int(PlasmaCubeTables.sine[angle & 1023]) }
    static func cosine(_ angle: Int) -> Int { Int(PlasmaCubeTables.sine[(angle + 256) & 1023]) }

    /// The small sine table the original calculated at start-up (PLZFILL.C `sini`): two waves in
    /// 1024 entries, -127...127, rounded towards zero.
    static let wave: [Int] = (0..<1524).map { (a: Int) -> Int in
        Int(sin(Double(a) / 1024.0 * Double.pi * 4) * 127)
    }

    /// The face texture (`kuva1`): 256 wide, 64 rows used, values 1...63. Horizontal bands that
    /// snake up and down across the width. The other two colour ranges are this plus 64 and plus 128.
    static let texture: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 64 * 256)
        for y in 0..<64 {
            for x in 0..<256 {
                table[y * 256 + x] = UInt8(wave[(y * 4 + wave[x * 2]) & 511] / 4 + 32)
            }
        }
        return table
    }()

    /// The sideways shift for each texture row (`dist1`): 128 rows, the same value across a row,
    /// -42...42 stored as a byte.
    static let sideShift: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 128 * 256)
        for y in 0..<128 {
            let value = UInt8(truncatingIfNeeded: wave[y * 8] / 3)
            for x in 0..<256 { table[y * 256 + x] = value }
        }
        return table
    }()

    /// The unlit palette (`pal`), 0...63 per channel: three ranges of 64 colours.
    /// 0: black to blue to white. 1: black to red to yellow. 2: black to purple, then to green.
    static let basePalette: [UInt8] = {
        var pal = [UInt8](repeating: 0, count: 768)
        func set(_ index: Int, _ r: Int, _ g: Int, _ b: Int) {
            pal[index * 3] = UInt8(r); pal[index * 3 + 1] = UInt8(g); pal[index * 3 + 2] = UInt8(b)
        }
        for a in 0..<32 {
            set(a, 0, 0, a * 2)
            set(32 + a, a * 2, a * 2, 63)
            set(64 + a, a * 2, 0, 0)
            set(96 + a, 63, a * 2, 0)
            set(128 + a, a, 0, a * 2 / 3)
            set(160 + a, 31 - a, a * 2, 21)
        }
        return pal
    }()

    /// The path (RATA.INC), hand-made by the original's author. Each point is: sideways, down,
    /// distance, three turn angles, two light angles (1024 = a full turn).
    static let pathPoints: [[Int]] = {
        // The sixteen turns the cube goes through; the path uses the list twice.
        let turns: [[Int]] = [
            [0, 400, 600], [100, 500, 700], [200, 600, 800], [300, 700, 700],
            [400, 800, 600], [500, 700, 500], [600, 600, 400], [700, 500, 300],
            [800, 400, 200], [700, 300, 100], [600, 200, 0], [500, 100, 100],
            [400, 0, 200], [300, 100, 300], [200, 200, 400], [100, 300, 500]]
        // First time round: rising into view from below, then coming closer as the light turns.
        let down = [2000, 2000, 2000, 2000, 2000, -150, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let distance = [500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 450, 400, 350, 300, 300]
        let light = [0, 0, 0, 0, 0, 0, 0, 0, 32, 64, 96, 128, 160, 192, 224, 256]
        var points: [[Int]] = []
        for i in 0..<16 { points.append([0, down[i], distance[i]] + turns[i] + [light[i], 0]) }
        // Second time round: close up, light fixed.
        for i in 0..<16 { points.append([0, 0, 300] + turns[i] + [256, 0]) }
        // Backing away, straightening up, the light going round behind.
        points.append([0, 0, 350, 0, 400, 400, 0, 128])
        points.append([0, 0, 400, 100, 300, 300, 64, 256])
        points.append([0, 0, 450, 200, 200, 200, 128, 384])
        points.append([0, 0, 500, 100, 100, 100, 192, 512])
        return points
    }()

    /// Where the path ends: square on, unlit. The original repeated this point 100 times.
    static let restPoint = [0, 0, 500, 0, 0, 0, 256, 512]

    static func pathPoint(_ index: Int) -> [Int] {
        index < pathPoints.count ? pathPoints[max(index, 0)] : restPoint
    }

    /// The cube's corners and faces (VECT.C `object`). Each face: four corners in order, colour range.
    static let corners: [SIMD3<Int>] = [
        SIMD3(125, 125, 125), SIMD3(125, -125, 125), SIMD3(-125, -125, 125), SIMD3(-125, 125, 125),
        SIMD3(125, 125, -125), SIMD3(125, -125, -125), SIMD3(-125, -125, -125), SIMD3(-125, 125, -125)]
    static let faces: [(corners: [Int], group: Int)] = [
        ([1, 2, 3, 0], 0), ([7, 6, 5, 4], 0), ([0, 4, 5, 1], 1),
        ([1, 5, 6, 2], 2), ([2, 6, 7, 3], 1), ([3, 7, 4, 0], 2)]

    // MARK: - State

    private(set) var ticks = 0
    /// The original's frame counter: negative during this version's lead-in.
    var frames: Int { ticks - Self.leadIn }
    /// Inside Play Demo: the music, given before each step. nil on its own.
    private(set) var music: DemoMusicState?
    /// Inside Play Demo: whether the start cue has been met, and whether the screen is still empty.
    private(set) var cued = false
    private(set) var waiting = false
    static let startCue = 13

    /// Each corner after turning and moving (x, y, z) and where it lands on the 640-wide page.
    private(set) var turned = [SIMD3<Int>](repeating: .zero, count: 8)
    private(set) var projected = [SIMD2<Int>](repeating: .zero, count: 8)
    /// Faces to draw this frame, in drawing order.
    private(set) var visibleFaces: [Int] = []
    /// The light level last used for the first, second and third face drawn (`lls`). The original
    /// remembered it by drawing position, not by face; see `calculate`.
    private var lastLight = [Int](repeating: 0, count: 6)
    /// The palette as lit (`fpal`): 256 colours, 0...63 per channel.
    private(set) var palette = [UInt8](repeating: 0, count: 768)

    /// Two replays of the video card. The original drew alternate frames two pixels apart (see
    /// `CubeVideoCard.shift`); the two replays are half a cycle apart, so at any step one holds the
    /// frame "as drawn" and the other the same frame as the neighbouring frames were drawn.
    private(set) var cards = [CubeVideoCard(page: 0), CubeVideoCard(page: 3)]

    /// `drawing`: whether the first frame is drawn at once (not inside Play Demo, which starts empty).
    init(drawing: Bool = true) {
        if drawing { drawFrame() }
    }

    /// Play Demo's music, before each step; `justShown` on the step the scene appears.
    mutating func update(music: DemoMusicState, justShown: Bool) {
        if justShown {
            self = PlasmaCubeModel(drawing: false)
            waiting = true
            ticks = Self.leadIn      // the original's frame 0
            // The script tests the cue on the very step it shows the scene.
            cued = music.plus >= Self.startCue
        }
        self.music = music
    }

    mutating func reset() { self = PlasmaCubeModel() }

    mutating func tick() {
        if let music {
            guard cued else {
                if music.plus >= Self.startCue { cued = true }
                return
            }
            ticks += 1
            waiting = false
            drawFrame()
            return
        }
        ticks += 1
        if ticks >= Self.lengthInTicks {
            self = PlasmaCubeModel()
            return
        }
        drawFrame()
    }

    /// One trip round VECT.C's main loop.
    private mutating func drawFrame() {
        calculate()
        for card in cards.indices {
            cards[card].swapPage()
            for face in visibleFaces {
                let entry = Self.faces[face]
                let shift = cards[card].shift
                let quad = entry.corners.map { corner -> (x: Int, y: Int) in
                    (x: Int(Int16(truncatingIfNeeded: projected[corner].x + shift)), y: projected[corner].y)
                }
                cards[card].fillFace(quad, group: entry.group, frame: frames & 63)
            }
            cards[card].eraseOld()
        }
    }

    // MARK: - The path (SPLINE.ASM getspl)

    /// The eight path values for a frame: sideways, down, distance, three turn angles, two light angles.
    static func pathValues(frame: Int) -> [Int] {
        let position = (4 * 256 + frame * 4) & 0xFFFF
        let first = position >> 8
        let t = position & 255
        let blend = PlasmaCubeTables.blend
        return (0..<8).map { (channel: Int) -> Int in
            var sum = 0
            for k in 0..<4 {
                sum += pathPoint(first + 3 - k)[channel] * Int(blend[t + 256 * k])
            }
            // The sum is a 32-bit number; the result is its bits 15...30.
            return Int(Int16(truncatingIfNeeded: Int(Int32(truncatingIfNeeded: sum)) >> 15))
        }
    }

    // MARK: - Turning, projecting, lighting (VECT.C calculate, count_const, rotate, sort_faces)

    private static func int16(_ value: Int) -> Int { Int(Int16(truncatingIfNeeded: value)) }
    private static func int32(_ value: Int) -> Int { Int(Int32(truncatingIfNeeded: value)) }

    private mutating func calculate() {
        let int16 = Self.int16, int32 = Self.int32
        let path = Self.pathValues(frame: frames)
        let (tx, ty, distance) = (path[0], path[1], path[2])
        let (kx, ky, kz) = (path[3] & 1023, path[4] & 1023, path[5] & 1023)
        let (lightA, lightB) = (path[6] & 1023, path[7] & 1023)

        // The direction of the light, about 127 long.
        let lightY = Self.cosine(lightA) >> 8
        let lightX = int16((Self.sine(lightA) >> 8) * (Self.sine(lightB) >> 8)) >> 7
        let lightZ = int16((Self.sine(lightA) >> 8) * (Self.cosine(lightB) >> 8)) >> 7

        // The nine numbers of the turn, each about 256 times the true value.
        let sx = Self.sine(kx), sy = Self.sine(ky), sz = Self.sine(kz)
        let cx = Self.cosine(kx), cy = Self.cosine(ky), cz = Self.cosine(kz)
        let m: [Int] = [
            int16(int32(cy * cz) >> 22),
            int16(int32(cy * sz) >> 22),
            int16(int32(-sy) >> 7),
            int16(int32(int32(int32(sx * cz + 16384) >> 15) * sy - cx * sz) >> 22),
            int16(int32(int32(int32(sx * sy + 16384) >> 15) * sz + cx * cz) >> 22),
            int16(int32(cy * sx) >> 22),
            int16(int32(int32(int32(cx * cz + 16384) >> 15) * sy + sx * sz) >> 22),
            int16(int32(int32(int32(cx * sy + 16384) >> 15) * sz - sx * cz) >> 22),
            int16(int32(cy * cx) >> 22)]

        for (i, corner) in Self.corners.enumerated() {
            func row(_ a: Int, _ b: Int, _ c: Int, _ add: Int) -> Int {
                let sum = int16((int16(corner.x * a) >> 1) + (int16(corner.y * b) >> 1) + (int16(corner.z * c) >> 1))
                return int16((sum >> 7) + add)
            }
            let x = row(m[0], m[1], m[2], tx)
            let y = row(m[3], m[4], m[5], ty)
            // The cube never reaches the eye on this path (nearest: 86). A zero here stopped the original.
            let z = max(row(m[6], m[7], m[8], distance), 1)
            turned[i] = SIMD3(x, y, z)
            // The page is 640 wide and the view starts 160 in, so 320 is the middle of the screen.
            projected[i] = SIMD2(int16(x * 256 / z + 320), int16(y * 142 / z + 66))
        }

        visibleFaces.removeAll(keepingCapacity: true)
        var drawn = 0
        for (number, face) in Self.faces.enumerated() {
            let p = turned[face.corners[0]]
            let a = turned[face.corners[1]] &- p
            let b = turned[face.corners[2]] &- p
            let nx = int32(a.y * b.z - a.z * b.y)
            let ny = int32(a.z * b.x - a.x * b.z)
            let nz = int32(a.x * b.y - a.y * b.x)
            // Facing away from the viewer: not drawn.
            if int32(-p.x * nx - p.y * ny - p.z * nz) > 0 { continue }

            let light = int16(int32(lightX * nx + lightY * ny + lightZ * nz) / 250000 + 32)
            // The original skipped re-dimming the palette when the level had not changed, but it
            // remembered the level per drawing position, not per face. When a different face takes
            // over a position at the same level, its colours are left as they last were.
            if lastLight[drawn] != light {
                dim(group: face.group, light: light)
                lastLight[drawn] = light
            }
            visibleFaces.append(number)
            drawn += 1
        }
    }

    /// PLZA.ASM `shadepal`: every colour of one range times the light level, divided by 64.
    private mutating func dim(group: Int, light: Int) {
        let level = Int(UInt8(truncatingIfNeeded: light))
        for i in (group * 192)..<(group * 192 + 192) {
            palette[i] = UInt8(truncatingIfNeeded: (Int(Self.basePalette[i]) * level) >> 6)
        }
    }

    // MARK: - The 1993 picture

    /// The two 320x400 pictures of colour numbers whose average the classic look shows.
    func classicPictures() -> (first: [UInt8], second: [UInt8]) {
        func tripled(_ screen: [UInt8]) -> [UInt8] {
            var picture = [UInt8](repeating: 0, count: Self.width * Self.canvasHeight)
            for line in 0..<Self.canvasHeight {
                let row = line / 3
                picture.replaceSubrange((line * Self.width)..<((line + 1) * Self.width),
                                        with: screen[(row * Self.width)..<((row + 1) * Self.width)])
            }
            return picture
        }
        return (tripled(cards[0].screen()), tripled(cards[1].screen()))
    }

    func classicReferenceFrame() -> [UInt8] {
        if waiting { return [UInt8](repeating: 0, count: Self.width * Self.canvasHeight * 3) }
        let pictures = classicPictures()
        var frame = [UInt8](repeating: 0, count: Self.width * Self.canvasHeight * 3)
        for i in 0..<(Self.width * Self.canvasHeight) {
            let a = Int(pictures.first[i]) * 3, b = Int(pictures.second[i]) * 3
            for channel in 0..<3 {
                let mixed = (Double(byteFromVGA(Int(palette[a + channel]))) + Double(byteFromVGA(Int(palette[b + channel])))) / 2
                frame[i * 3 + channel] = UInt8(mixed.rounded())
            }
        }
        return frame
    }

    // MARK: - The modern look's state

    struct ModernFace {
        /// The four corners, in front of the camera (x right, y down, z away), in corner order.
        var corners: [SIMD3<Float>]
        var group: Int
        /// 0...1: how brightly the face is lit.
        var light: Float
    }

    struct ModernState {
        var faces: [ModernFace]
        /// How far the texture's sideways shift has scrolled, in texture rows (0..<64).
        var scroll: Float
    }

    /// The same rules without the rounding to whole numbers, `alpha` (0..<1) of the way to the next step.
    func modernState(alpha: Float) -> ModernState {
        let frame = Double(frames) + Double(alpha)
        // The path, with the blend table read between its entries.
        let position = 1024 + frame * 4
        let first = Int((position / 256).rounded(.down))
        let t = position - Double(first) * 256
        func weight(_ at: Double) -> Double {
            let whole = Int(at.rounded(.down))
            let low = Double(PlasmaCubeTables.blend[min(whole, 1023)])
            let high = whole + 1 < 1024 ? Double(PlasmaCubeTables.blend[whole + 1]) : 0
            return (low + (high - low) * (at - Double(whole))) / 32768
        }
        var path = [Double](repeating: 0, count: 8)
        for k in 0..<4 {
            let w = weight(t + Double(256 * k))
            let point = Self.pathPoint(first + 3 - k)
            for channel in 0..<8 { path[channel] += Double(point[channel]) * w }
        }

        func turn(_ value: Double) -> Double { value * 2 * Double.pi / 1024 }
        let sx = sin(turn(path[3])), sy = sin(turn(path[4])), sz = sin(turn(path[5]))
        let cx = cos(turn(path[3])), cy = cos(turn(path[4])), cz = cos(turn(path[5]))
        let rotation = simd_double3x3(rows: [
            SIMD3(cy * cz, cy * sz, -sy),
            SIMD3(sx * cz * sy - cx * sz, sx * sy * sz + cx * cz, cy * sx),
            SIMD3(cx * cz * sy + sx * sz, cx * sy * sz - sx * cz, cy * cx)])
        let offset = SIMD3(path[0], path[1], path[2])
        let points = Self.corners.map { rotation * SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) + offset }

        let lightA = turn(path[6]), lightB = turn(path[7])
        let light = SIMD3(sin(lightA) * sin(lightB), cos(lightA), sin(lightA) * cos(lightB)) * 127

        var faces: [ModernFace] = []
        for face in Self.faces {
            let p = points[face.corners[0]]
            let normal = simd_cross(points[face.corners[1]] - p, points[face.corners[2]] - p)
            if -simd_dot(p, normal) > 0 { continue }
            let level = simd_dot(light, normal) / 250000 + 32
            faces.append(ModernFace(
                corners: face.corners.map { SIMD3<Float>(points[$0]) },
                group: face.group,
                light: Float(min(max(level, 0), 64) / 64)))
        }
        let scroll = (frame + 1).truncatingRemainder(dividingBy: 64)
        return ModernState(faces: faces, scroll: Float(scroll < 0 ? scroll + 64 : scroll))
    }
}
