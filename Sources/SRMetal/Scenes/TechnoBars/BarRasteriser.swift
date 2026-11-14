import Foundation

/// Draws filled four-sided shapes into a one-colour 320x200 picture, the way the original did
/// (TECHNO/KOEA.ASM `asmbox`, `drawline`, `blit16` and POLYCLIP.ASM).
///
/// The 1993 method, kept here step for step so the pixels come out the same:
///  1. Trim the shape to the screen.
///  2. For each edge, flip ONE pixel on every row the edge crosses.
///  3. Sweep each row left to right, switching "inside" on and off at every flipped pixel.
/// Step 3 fills all shapes at once, so step 2 was the only per-shape work. It was a fast way to
/// fill shapes on a 486.
struct BarRasteriser {
    static let width = 320
    static let height = 200

    struct Point: Equatable {
        var x: Int
        var y: Int
    }

    /// The edge marks: one bit per pixel, 40 bytes per row, as in the original's work buffer.
    private var marks = [UInt8](repeating: 0, count: 40 * height)

    mutating func clear() {
        for i in marks.indices { marks[i] = 0 }
    }

    // MARK: - Step 1: trimming to the screen

    /// Moves the ends of a line onto the screen's top/bottom rows if they stick out.
    /// Returns false if the whole line is above or below the screen.
    private static func clipY(_ a: inout Point, _ b: inout Point) -> Bool {
        func flags(_ p: Point) -> Int { (p.y < 0 ? 4 : 0) | (p.y > 199 ? 8 : 0) }
        let fa = flags(a)
        let fb = flags(b)
        if fa & fb != 0 { return false }
        func slide(_ p: inout Point, toward q: Point, row: Int) {
            let span = q.y - p.y
            if span != 0 {
                p.x = (q.x - p.x) * (row - p.y) / span + p.x
            }
            p.y = row
        }
        if fa & 4 != 0 { slide(&a, toward: b, row: 0) }
        if fa & 8 != 0 { slide(&a, toward: b, row: 199) }
        if fb & 4 != 0 { slide(&b, toward: a, row: 0) }
        if fb & 8 != 0 { slide(&b, toward: a, row: 199) }
        return true
    }

    /// The same for the left/right columns.
    private static func clipX(_ a: inout Point, _ b: inout Point) -> Bool {
        func flags(_ p: Point) -> Int { (p.x < 0 ? 1 : 0) | (p.x > 319 ? 2 : 0) }
        let fa = flags(a)
        let fb = flags(b)
        if fa & fb != 0 { return false }
        func slide(_ p: inout Point, toward q: Point, column: Int) {
            let span = q.x - p.x
            if span != 0 {
                p.y = (q.y - p.y) * (column - p.x) / span + p.y
            }
            p.x = column
        }
        if fa & 1 != 0 { slide(&a, toward: b, column: 0) }
        if fa & 2 != 0 { slide(&a, toward: b, column: 319) }
        if fb & 1 != 0 { slide(&b, toward: a, column: 0) }
        if fb & 2 != 0 { slide(&b, toward: a, column: 319) }
        return true
    }

    /// Trims every edge of a shape with `clip` and joins up what is left.
    private static func clipShape(_ shape: [Point], with clip: (inout Point, inout Point) -> Bool) -> [Point] {
        var result: [Point] = []
        var last: Point?
        for i in shape.indices {
            var a = shape[(i + shape.count - 1) % shape.count]
            var b = shape[i]
            guard clip(&a, &b) else { continue }
            if a != last { result.append(a); last = a }
            if b != last { result.append(b); last = b }
        }
        // The shape is a closed loop, so a repeat of the first point at the end is dropped.
        if let first = result.first, first == last {
            result.removeLast()
        }
        return result
    }

    // MARK: - Step 2: marking edges

    private mutating func flip(x: Int, y: Int) {
        marks[y * 40 + (x >> 3)] ^= UInt8(0x80 >> (x & 7))
    }

    /// Flips one pixel per row along a line, top row included, bottom row not.
    private mutating func markEdge(_ p: Point, _ q: Point) {
        if p.y == q.y { return }
        let top = p.y < q.y ? p : q
        let bottom = p.y < q.y ? q : p
        let rows = bottom.y - top.y
        let leftward = top.x >= bottom.x
        let across = abs(bottom.x - top.x)
        var x = top.x
        var error = -(rows >> 1)
        for y in top.y..<bottom.y {
            flip(x: x, y: y)
            error += across
            while error >= 0 {
                x += leftward ? -1 : 1
                error -= rows
            }
        }
    }

    /// Adds one four-sided shape.
    mutating func add(_ corners: [Point]) {
        // Up and down first, then left and right. A shape trimmed down to a line or less draws nothing.
        let trimmedY = Self.clipShape(corners, with: Self.clipY)
        guard trimmedY.count > 2 else { return }
        let shape = Self.clipShape(trimmedY, with: Self.clipX)
        guard shape.count > 2 else { return }
        for i in shape.indices {
            markEdge(shape[i], shape[(i + 1) % shape.count])
        }
    }

    // MARK: - Step 3: the fill

    /// The finished picture: one byte per pixel, 1 inside a shape and 0 outside.
    func filled() -> [UInt8] {
        var picture = [UInt8](repeating: 0, count: Self.width * Self.height)
        for y in 0..<Self.height {
            var inside: UInt8 = 0
            for x in 0..<Self.width {
                if marks[y * 40 + (x >> 3)] & UInt8(0x80 >> (x & 7)) != 0 {
                    inside ^= 1
                }
                picture[y * Self.width + x] = inside
            }
        }
        return picture
    }
}
