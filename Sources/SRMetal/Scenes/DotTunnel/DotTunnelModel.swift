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

    /// Brightness (0...63, the VGA scale) of a ring in a slot. Further away is darker.
    static func classicBrightness(slot: Int, band: Band) -> Int {
        let step = Int((Double(slot) / 1.3).rounded(.toNearestOrEven))
        // The original set palette entries 68 and 132 to black, which blanks the ring in the reference slot.
        if step == 4 { return 0 }
        switch band {
        case .invisible: return 0
        case .bright: return 64 - step
        case .dim: return (64 - step) * 3 / 4
        }
    }

    /// The classic-look picture worked out on the processor, exactly as the 1993 code drew it:
    /// one byte per pixel, 320x200, 0...63. Used to check the graphics-chip version against.
    func classicReferenceFrame() -> [UInt8] {
        var frame = [UInt8](repeating: 0, count: 320 * 200)
        let reference = rings[Self.referenceSlot]
        for slot in stride(from: 80, through: 4, by: -1) {
            let ring = rings[slot]
            guard ring.band != .invisible else { continue }
            let value = UInt8(Self.classicBrightness(slot: slot, band: ring.band))
            let radiusY = Self.classicRadiusY(slot: slot)
            let radiusX = Self.classicRadiusX(radiusY: radiusY)
            for dot in 0..<Self.dotsPerRing {
                let angle = Double(dot) * .pi / 32
                let x = 160 + Int((sin(angle) * Double(radiusX)).rounded(.toNearestOrEven)) + ring.x - reference.x
                let y = 100 + Int((cos(angle) * Double(radiusY)).rounded(.toNearestOrEven)) + ring.y - reference.y
                if x >= 0, x < 320, y >= 0, y < 200 {
                    frame[y * 320 + x] = value
                }
            }
        }
        return frame
    }
}
