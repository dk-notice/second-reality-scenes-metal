import Foundation

/// The state and rules of the dot tunnel, with no drawing code.
///
/// This follows Trug's original (TUNNELI/TUN10.PAS in the Second Reality source) step for step:
/// the tunnel is a conveyor belt of rings. Each step, every ring moves one slot nearer the viewer
/// and a new ring is fed in at the far end, positioned by a few sine waves added together.
struct DotTunnelModel {
    /// Slots 0...100. Slot 99 is where a new ring appears; slot 100 is a staging slot, as in the original.
    static let slotCount = 101
    /// The original scene lasted exactly this many steps (about 15 seconds). We loop after it.
    static let lengthInTicks = 1060
    /// For the last 102 steps the original fed in invisible rings, so the tunnel empties out.
    static let fadeOutTicks = 102
    static let dotsPerRing = 64
    /// Everything is drawn relative to this slot, which keeps the near end of the tunnel centred.
    static let referenceSlot = 5

    enum Band: UInt8 {
        case invisible = 0
        case bright = 64
        case dim = 128
    }

    struct Ring {
        var x: Int = 0
        var y: Int = 0
        var band: Band = .invisible
    }

    private(set) var rings = [Ring](repeating: Ring(), count: slotCount)
    private(set) var tickCount = 0
    private var sx = 0
    private var sy = 0

    /// Video memory as the original's drawing loop leaves it: one colour number per pixel. It is 65536
    /// bytes, not 64000, because the original sent dots above or below the screen to addresses just past
    /// the last visible pixel, and remembered a dot off the left or right edge by a bare 16-bit number.
    private var screen = [UInt8](repeating: 0, count: 65536)
    /// Where each dot was last drawn, by its place in the drawing order (not by ring). The original
    /// never set this list up; here it starts as zeros, which only ever blanks pixel 0.
    private var oldPositions = [Int](repeating: 0, count: 77 * dotsPerRing)

    /// The original's circle table (TUNNEL.DAT): 64 points for each circle size, already centred on
    /// the screen. Entry `n` is the circle of vertical radius `n + 10`. This formula reproduces the file.
    static let circleTable: [[SIMD2<Int>]] = (0..<138).map { entry in
        let radiusY = entry + 10
        let radiusX = classicRadiusX(radiusY: radiusY)
        return (0..<dotsPerRing).map { dot in
            let angle = Double(dot) * .pi / 32
            return SIMD2(160 + Int((sin(angle) * Double(radiusX)).rounded(.toNearestOrEven)),
                         100 + Int((cos(angle) * Double(radiusY)).rounded(.toNearestOrEven)))
        }
    }

    // The original loaded these two tables from SINIT.DAT. These formulas (from its SINGEN.PAS)
    // reproduce that file exactly. The waves grow wider the further along the table you go.
    static let sinTable: [Int] = (0...4096).map { x in
        Int((sin(Double(x) / 128 * .pi) * Double((x * 3) / 128)).rounded(.toNearestOrEven))
    }
    static let cosTable: [Int] = (0...2048).map { x in
        Int((cos(Double(x) / 128 * .pi) * Double((x * 4) / 64)).rounded(.toNearestOrEven))
    }

    mutating func reset() {
        self = DotTunnelModel()
    }

    mutating func tick() {
        let sinT = Self.sinTable
        let cosT = Self.cosTable

        // Where the new far-end ring goes.
        rings[100].x = cosT[sy & 2047] - sinT[(sy * 3) & 4095] - cosT[sx & 2047]
        rings[100].y = sinT[(sx * 2) & 4095] - cosT[sx & 2047] + sinT[0]

        // The conveyor belt: every ring moves one slot nearer.
        for slot in 0..<100 {
            rings[slot] = rings[slot + 1]
        }
        sx += 1
        sy += 1

        // Light and dark stripes: switch every 8 steps.
        rings[99].band = (sy & 15) > 7 ? .dim : .bright
        if tickCount >= Self.lengthInTicks - Self.fadeOutTicks {
            rings[99].band = .invisible
        }

        tickCount += 1
        if tickCount == Self.lengthInTicks {
            reset()
        }
        drawClassic()
    }

    /// The original's drawing loop, replayed step for step into `screen`.
    ///
    /// The original never cleared the screen. Each dot, just before it is drawn, blanks the pixel
    /// where the dot with the same place in the drawing order was drawn the frame before. Rings are
    /// drawn far to near, so that blanking often lands on a dot a further ring has only just drawn
    /// this frame, and that dot is then missing: about one dot in twenty, different ones each frame.
    /// That is part of how the original looked, so it is reproduced.
    private mutating func drawClassic() {
        let reference = rings[Self.referenceSlot]
        var index = 0
        for slot in stride(from: 80, through: 4, by: -1) {
            let ring = rings[slot]
            let colour = Self.colourNumber(slot: slot, band: ring.band)
            // Colour numbers below 64 are rings not switched on yet (or switched off at the end).
            guard colour >= 64 else { continue }
            let circle = Self.circleTable[Self.classicRadiusY(slot: slot) - 10]
            let offsetX = ring.x - reference.x
            let offsetY = ring.y - reference.y
            for dot in 0..<Self.dotsPerRing {
                screen[oldPositions[index]] = 0
                // 16-bit arithmetic: a dot left of the screen wraps round to a large number.
                var position = (circle[dot].x + offsetX) & 0xFFFF
                if position <= 319 {
                    let row = circle[dot].y + offsetY
                    // Rows off the top or bottom go to address 64000, just past the visible screen.
                    position = (position + ((0..<200).contains(row) ? row * 320 : 64000)) & 0xFFFF
                    screen[position] = UInt8(colour)
                }
                oldPositions[index] = position
                index += 1
            }
        }
    }

    /// The colour number the original gave a ring: its band's base (64 or 128) plus a step that grows
    /// with distance. The palette then makes higher numbers darker.
    static func colourNumber(slot: Int, band: Band) -> Int {
        Int(band.rawValue) + Int((Double(slot) / 1.3).rounded(.toNearestOrEven))
    }

    /// The original's palette as brightness (0...63, the VGA scale) for each colour number: two grey
    /// ramps, with numbers 68 and 132 set to black (which blanks the ring in the reference slot).
    static let classicPalette: [Int] = {
        var palette = [Int](repeating: 0, count: 256)
        for step in 0...64 { palette[64 + step] = (64 - step) & 63 }
        for step in 0...64 { palette[128 + step] = (64 - step) * 3 / 4 }
        palette[68] = 0
        palette[132] = 0
        return palette
    }()

    /// The 1993 picture as colour numbers, one byte per pixel, 320x200.
    func classicIndices() -> [UInt8] {
        Array(screen[0..<(320 * 200)])
    }

    // MARK: - The original's size and colour rules

    /// Vertical radius of the ring in a slot, in 320x200 pixels. Radius shrinks with distance: this is the
    /// perspective. The original used whole numbers and looked the circle up in a table.
    static func classicRadiusY(slot: Int) -> Int {
        16384 / (slot * 7 + 95) + 10
    }

    /// Horizontal radius. 1.7 times the vertical one, because 320x200 pixels were taller than wide.
    static func classicRadiusX(radiusY: Int) -> Int {
        Int((Double(radiusY) * 1.7).rounded(.toNearestOrEven))
    }

    /// The 1993 picture as brightness: one byte per pixel, 320x200, 0...63.
    func classicReferenceFrame() -> [UInt8] {
        classicIndices().map { UInt8(Self.classicPalette[Int($0)]) }
    }
}
