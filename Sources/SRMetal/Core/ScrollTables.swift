import Foundation
import simd

/// The position tables of Trug's two scrollers (the mountain scroller, part 9, and the water scroller,
/// part 13), and the Modern look's smooth map fitted to them.
///
/// A scroller has a window on a picture (text, or a sword), `columns` by `rows` cells, and three tables:
/// for each window cell the screen pixels (320x200 addresses) it lands on. One table is drawn per
/// refresh; the three share no pixel, each holding the pixels a third of a column further on.
struct ScrollTables {
    /// One position table: cell i (row x columns + column) owns `addresses[starts[i]..<starts[i + 1]]`.
    struct Table {
        var starts: [Int]
        var addresses: [UInt16]
    }

    let columns: Int
    let rows: Int
    let tables: [Table]

    /// Reads one table file: per cell a 16-bit count, then that many 16-bit addresses. nil unless the
    /// file holds exactly `columns` x `rows` cells of addresses on the screen.
    static func parse(_ d: [UInt8], columns: Int, rows: Int) -> Table? {
        var table = Table(starts: [0], addresses: [])
        var p = 0
        for _ in 0..<(columns * rows) {
            guard p + 2 <= d.count else { return nil }
            let count = Int(d[p]) | Int(d[p + 1]) << 8
            p += 2
            guard p + 2 * count <= d.count else { return nil }
            for k in 0..<count {
                let address = UInt16(d[p + 2 * k]) | UInt16(d[p + 2 * k + 1]) << 8
                guard address < 64000 else { return nil }
                table.addresses.append(address)
            }
            p += 2 * count
            table.starts.append(table.addresses.count)
        }
        guard p == d.count else { return nil }
        return table
    }

    /// The Modern look's map: for every screen pixel a plane through the text coordinates around it,
    /// `u = a + b·dx + c·dy` and the same for v (dx, dy from the pixel's centre, in pixels). u is the
    /// window column (0...`columns`), v the text row (0...`rows`).
    ///
    /// Where the coordinates come from: a pixel that table k (0...2) lists at window column c covers the
    /// third of a column from u = c + (2 − k)/3 (the tables are the hills ray-traced three times with the
    /// text moved a third of a column; `tools/mountain_reference.py` shows the order), and its cell's row
    /// is v. Both are known only in steps (thirds of a column, whole rows), but where two neighbouring
    /// pixels are one step apart, the line between them is where the coordinate crosses that step: an
    /// exact value at a known place. Each pixel gets the weighted best-fit plane through such crossings
    /// around it on the same stretch of hill (and, weakly, through the pixels' own middles). The map is
    /// then grown three pixels outwards, so the text's edges are cut by the plane (a straight edge), not
    /// by the pixel grid.
    ///
    /// `smallRegion` (the water scroller): connected regions of fewer pixels than this get no plane. There
    /// a cell is smaller than a pixel (tiny reflections), so each pixel keeps its own cell's middle, marked
    /// 2 instead of 1, with the region's average cells-per-pixel in place of the slopes (u's b: columns
    /// per pixel; v's c: rows per pixel).
    struct SmoothMap {
        /// Per pixel: a, b, c, and 1 if the pixel has a plane (2: a small region's pixel; else 0).
        var u: [Float]
        /// Per pixel: a, b, c, 0.
        var v: [Float]
    }

    func smoothMap(smallRegion: Int = 0) -> SmoothMap {
        let w = 320, h = 200, none = -1
        // Per pixel: its third of a column (3c + 2 − k) and its row.
        var third = [Int](repeating: none, count: w * h), row = third
        for (k, table) in tables.enumerated() {
            for cell in 0..<(columns * rows) {
                for i in table.starts[cell]..<table.starts[cell + 1] {
                    let a = Int(table.addresses[i])
                    third[a] = 3 * (cell % columns) + 2 - k
                    row[a] = cell / columns
                }
            }
        }
        // Crossings between a pixel and its right (0) and lower (1) neighbour: the coordinate's value on
        // the line between them, or nil.
        var crossU = [Float?](repeating: nil, count: w * h * 2), crossV = crossU
        for y in 0..<h {
            for x in 0..<w {
                let a = y * w + x
                for (side, b) in [(0, x + 1 < w ? a + 1 : -1), (1, y + 1 < h ? a + w : -1)] where b >= 0 {
                    let here = third[a] != none, there = third[b] != none
                    if here && there {
                        let dt = abs(third[a] - third[b]), dr = abs(row[a] - row[b])
                        guard dt <= 3, dr <= 1 else { continue }     // further apart: another fold of the hills
                        if dt >= 1 { crossU[2 * a + side] = Float(third[a] + third[b] + 1) / 6 }
                        if dr == 1 { crossV[2 * a + side] = Float(max(row[a], row[b])) }
                    } else if here != there {
                        // The edge of the text's band: its first row starts and its last row ends here
                        // (unless this is the band's left or right end instead).
                        let inside = here ? a : b
                        guard third[inside] > 6, third[inside] < 3 * columns - 7 else { continue }
                        if row[inside] == 0 { crossV[2 * a + side] = 0 }
                        if row[inside] == rows - 1 { crossV[2 * a + side] = Float(rows) }
                    }
                }
            }
        }
        // Least squares for value = a + b·dx + c·dy.
        typealias Sample = (dx: Float, dy: Float, value: Float, weight: Float)
        func fit(_ points: [Sample]) -> SIMD3<Float>? {
            var m = simd_double3x3(0), r = SIMD3<Double>(0, 0, 0)
            for p in points {
                let b = SIMD3<Double>(1, Double(p.dx), Double(p.dy)), wt = Double(p.weight)
                m += simd_double3x3(columns: (b * b.x * wt, b * b.y * wt, b * b.z * wt))
                r += b * Double(p.value) * wt
            }
            guard abs(m.determinant) > 1e-2 else { return nil }
            return SIMD3<Float>(m.inverse * r)
        }
        var map = SmoothMap(u: [Float](repeating: 0, count: w * h * 4), v: [Float](repeating: 0, count: w * h * 4))
        let radius = 5
        for y in 0..<h {
            for x in 0..<w where third[y * w + x] != none {
                let t0 = third[y * w + x], r0 = row[y * w + x]
                let u0 = (Float(t0) + 0.5) / 3, v0 = Float(r0) + 0.5
                var pu: [Sample] = [], pv: [Sample] = []
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let xx = x + dx, yy = y + dy
                        guard xx >= 0, yy >= 0, xx < w, yy < h else { continue }
                        let b = yy * w + xx
                        guard third[b] != none else { continue }
                        // The same stretch of hill: the coordinates may not jump on the way there.
                        let reach = abs(dx) + abs(dy)
                        guard abs(third[b] - t0) <= 4 * reach + 3, abs(row[b] - r0) <= reach + 1 else { continue }
                        let fx = Float(dx), fy = Float(dy)
                        let weight = exp(-(fx * fx + fy * fy) / 10)
                        pu.append((fx, fy, (Float(third[b]) + 0.5) / 3, weight * 0.05))
                        pv.append((fx, fy, Float(row[b]) + 0.5, weight * 0.05))
                        for side in 0...1 {
                            let mx = fx + (side == 0 ? 0.5 : 0), my = fy + (side == 1 ? 0.5 : 0)
                            let mw = exp(-(mx * mx + my * my) / 10)
                            if let value = crossU[2 * b + side] { pu.append((mx, my, value, mw)) }
                            if let value = crossV[2 * b + side] { pv.append((mx, my, value, mw)) }
                        }
                    }
                }
                // The crossings to this pixel's left and above belong to those neighbours even when they
                // are outside the band.
                for (b, side, mx, my) in [(y * w + x - 1, 0, Float(-0.5), Float(0)), (y * w + x - w, 1, Float(0), Float(-0.5))]
                where b >= 0 && third[b] == none {
                    if let value = crossV[2 * b + side] { pv.append((mx, my, value, 1)) }
                }
                var planeU = SIMD3<Float>(u0, 0, 0), planeV = SIMD3<Float>(v0, 0, 0)
                if pu.count >= 8, let a = fit(pu) { planeU = a }
                if pv.count >= 8, let b = fit(pv) { planeV = b }
                // A fit may not carry the pixel out of its own step by much.
                planeU.x = min(max(planeU.x, Float(t0) / 3 - 0.2), Float(t0 + 1) / 3 + 0.2)
                planeV.x = min(max(planeV.x, Float(r0) - 0.3), Float(r0 + 1) + 0.3)
                let i = 4 * (y * w + x)
                map.u[i] = planeU.x; map.u[i + 1] = planeU.y; map.u[i + 2] = planeU.z; map.u[i + 3] = 1
                map.v[i] = planeV.x; map.v[i + 1] = planeV.y; map.v[i + 2] = planeV.z
            }
        }
        // Small regions (the water's tiny reflections, where a cell is smaller than a pixel): no plane can be
        // fitted, so each pixel keeps its own cell, with the region's cells-per-pixel as its footprint.
        if smallRegion > 0 {
            var seen = [Bool](repeating: false, count: w * h)
            for start in 0..<(w * h) where third[start] != none && !seen[start] {
                var stack = [start], members: [Int] = []
                seen[start] = true
                while let p = stack.popLast() {
                    members.append(p)
                    for q in [p - 1, p + 1, p - w, p + w] where q >= 0 && q < w * h && !seen[q] && third[q] != none
                        && abs(q % w - p % w) <= 1 {
                        seen[q] = true
                        stack.append(q)
                    }
                }
                guard members.count < smallRegion else { continue }
                // How many columns and rows a step of one pixel crosses, on average.
                var du: Float = 0, dv: Float = 0, pairs: Float = 0
                for p in members {
                    for q in [p + 1, p + w] where q < w * h && third[q] != none && abs(q % w - p % w) <= 1 {
                        du += Float(abs(third[p] - third[q])) / 3
                        dv += Float(abs(row[p] - row[q]))
                        pairs += 1
                    }
                }
                let footU = min(max(pairs > 0 ? du / pairs : 1, 1), 16), footV = min(max(pairs > 0 ? dv / pairs : 1, 1), 16)
                for p in members {
                    map.u[4 * p] = (Float(third[p]) + 0.5) / 3; map.u[4 * p + 1] = footU; map.u[4 * p + 2] = 0; map.u[4 * p + 3] = 2
                    map.v[4 * p] = Float(row[p]) + 0.5; map.v[4 * p + 1] = 0; map.v[4 * p + 2] = footV
                }
            }
        }
        for _ in 0..<3 {
            var next = map
            for y in 0..<h {
                for x in 0..<w where map.u[4 * (y * w + x) + 3] == 0 {
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let xx = x + dx, yy = y + dy
                        guard xx >= 0, yy >= 0, xx < w, yy < h, map.u[4 * (yy * w + xx) + 3] == 1 else { continue }
                        let from = 4 * (yy * w + xx), to = 4 * (y * w + x)
                        // The neighbour's plane, re-centred on this pixel.
                        next.u[to] = map.u[from] - map.u[from + 1] * Float(dx) - map.u[from + 2] * Float(dy)
                        next.u[to + 1] = map.u[from + 1]; next.u[to + 2] = map.u[from + 2]; next.u[to + 3] = 1
                        next.v[to] = map.v[from] - map.v[from + 1] * Float(dx) - map.v[from + 2] * Float(dy)
                        next.v[to + 1] = map.v[from + 1]; next.v[to + 2] = map.v[from + 2]
                        break
                    }
                }
            }
            map = next
        }
        return map
    }
}
