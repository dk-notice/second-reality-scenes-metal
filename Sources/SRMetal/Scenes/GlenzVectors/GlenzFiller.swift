import Foundation

/// The see-through polygon filler of Glenz Vectors (GLENZ/NEW.ASM: `__newgroup`, `ng_pass2`,
/// `ng_pass3`), replayed step for step so the pixels come out the same.
///
/// The 1993 method:
///  1. Every edge of every polygon is stored with the polygon's colour number, the row it starts
///     on, the row it ends on, and how far it moves sideways per row (a 16.16 fixed-point number:
///     16 bits of whole pixels, 16 bits of fraction). An edge that two polygons share is stored
///     once, with the two colour numbers combined by XOR.
///  2. Row by row, every edge crossing the row marks one pixel. Sweeping the row from the left,
///     the "current colour" is XOR-ed with an edge's colour number each time one is passed. So a
///     pixel's colour number is the XOR of the colour numbers of ALL the polygons covering it,
///     however many overlap. That is the whole transparency trick: no sorting, no blending.
///  3. Only pixels whose colour number changed since the previous frame are written to the screen,
///     and what is written is the colour number OR-ed with the floor picture's pixel.
///
/// This is a different routine from the Techno Bars filler (`BarRasteriser`, same coder): that one
/// flips bits in a one-colour picture and has a separate clipper; this one keeps a list of edges
/// with fixed-point slopes and needs no clipper.
struct GlenzFiller {
    static let width = 320
    static let height = 200

    private struct Edge {
        /// Position across the row, 16.16 fixed point.
        var x: Int32
        /// Movement across per row, 16.16 fixed point.
        var step: Int32
        /// The first row the edge does NOT reach.
        var endRow: Int
        var colour: UInt8
    }

    /// For each row, the edges that start there.
    private var starting = [[Edge]](repeating: [], count: height)
    /// Every pixel's colour number in the previous frame (the original kept the previous frame's
    /// list of colour changes, which holds the same information).
    private var previous = [UInt8](repeating: 0, count: width * height)

    mutating func begin() {
        for row in 0..<Self.height { starting[row].removeAll(keepingCapacity: true) }
    }

    /// Adds one polygon. Corner positions are screen pixels as 16-bit numbers.
    mutating func add(colour: UInt8, corners: [(x: Int, y: Int)]) {
        for i in corners.indices {
            let a = corners[i]
            let b = corners[(i + 1) % corners.count]
            // Top end first.
            let (top, bottom) = a.y > b.y ? (b, a) : (a, b)
            var y1 = top.y
            let y2 = bottom.y
            if y1 == y2 { continue }                       // level edges mark nothing
            var x = Int32(truncatingIfNeeded: top.x << 16)
            let across = Int(Int16(truncatingIfNeeded: bottom.x - top.x))
            let rows = Int(UInt16(truncatingIfNeeded: y2 - y1))
            let step = Int32(truncatingIfNeeded: Int(Int32(truncatingIfNeeded: across << 16)) / rows)
            if y1 < 0 {
                // Starts above the screen: skip ahead to row 0.
                if y2 <= 0 { continue }
                x = x &+ Int32(truncatingIfNeeded: Int(step) * -y1)
                y1 = 0
            }
            if y1 >= Self.height {
                // Starts below the screen: never drawn. (The original filed these under their row
                // in a 256-entry table and never looked at rows past 199. The reference tool
                // confirms no edge in this scene starts on row 256 or lower, which would have
                // been written outside that table.)
                continue
            }
            if let same = starting[y1].firstIndex(where: { $0.endRow == y2 && $0.x == x && $0.step == step }) {
                // The same edge again (two faces share it): one edge, colours combined.
                starting[y1][same].colour ^= colour
            } else {
                starting[y1].append(Edge(x: x, step: step, endRow: y2, colour: colour))
            }
        }
    }

    /// Works out every pixel's colour number and updates `screen` where it changed.
    mutating func finish(screen: inout [UInt8], background: [UInt8]) {
        var marks = [UInt8](repeating: 0, count: Self.width * Self.height)
        var active: [Edge] = []
        for row in 0..<Self.height {
            active.append(contentsOf: starting[row])
            active.removeAll { row >= $0.endRow }
            for i in active.indices {
                // The whole-pixel part, kept between columns 1 and 319.
                let column = min(max(Int(active[i].x >> 16), 1), 319)
                active[i].x = active[i].x &+ active[i].step
                marks[row * Self.width + column] ^= active[i].colour
            }
        }
        var colour: UInt8 = 0
        // The original's sweep stops one pixel short of the end of the screen.
        for position in 0..<(Self.width * Self.height - 1) {
            colour ^= marks[position]
            if colour != previous[position] {
                screen[position] = colour | background[position]
                previous[position] = colour
            }
        }
    }
}
