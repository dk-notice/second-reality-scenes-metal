import Foundation

/// A replay, on the processor, of the original VISU 3D engine (coder Psi): the part that turns one
/// object into filled polygons on a 320x200 picture of colour numbers.
///
/// It follows the original assembly step for step wherever a pixel depends on it:
///
/// - ACALC.ASM   `calc_rotate`, `calc_nrotate`, `calc_project`
/// - AVID.ASM    `vid_window`, `vid_cameraangle`
/// - ADRAW.ASM   `draw_polylist`: hidden-face test, lighting, building the edge list (`poly_nrm`,
///               `poly_grd`)
/// - ADRAWCLP.ASM  clipping against the near plane and the four window edges
/// - AVIDFILL.ASM  the flat and the Gouraud polygon fillers
/// - VISU.C      `vis_drawobject`
///
/// `tools/visu_reference.py` runs that assembly itself; the self-test holds this replay to the
/// same pictures. See docs/visu-engine.md for how it all works.
final class VisuEngine {
    // MARK: The picture

    static let width = 320
    static let height = 200
    /// The 320x200 picture: one colour number per pixel, row by row.
    var pixels = [UInt8](repeating: 0, count: VisuEngine.width * VisuEngine.height)

    // MARK: The view (ADATA.ASM `_proj*`), as `m1_init` sets it

    /// The window polygons are clipped to: left/right, top/bottom, and nearest/farthest distance.
    var clipX: (min: Int32, max: Int32) = (0, 319)
    var clipY: (min: Int32, max: Int32) = (0, 199)
    var clipZ: (min: Int32, max: Int32) = (256, 1_000_000_000)
    /// Perspective: screen x = addX + mulX * x / z, and the same for y.
    var mulX: Int32 = 250
    var mulY: Int32 = 220
    var addX: Int32 = 160
    var addY: Int32 = 100
    /// How much shorter than wide a pixel's spacing is, times 256 (mode 320x200: 225).
    var aspect: UInt16 = 225

    /// Things the original would have crashed on or scribbled outside its buffers for (a division
    /// whose result does not fit, a pixel outside the picture). Counted here instead; the two
    /// scenes' data never causes any, and the self-test checks that.
    private(set) var faults = 0

    func clear(to colour: UInt8) {
        for i in pixels.indices { pixels[i] = colour }
    }

    /// `vid_window`: sets the clip window and centres the projection in it.
    func setWindow(x1: Int32, x2: Int32, y1: Int32, y2: Int32, z1: Int32, z2: Int32) {
        clipX = (x1, x2); addX = (x1 &+ x2) >> 1
        clipY = (y1, y2); addY = (y1 &+ y2) >> 1
        clipZ = (z1, z2)
    }

    /// `vid_cameraangle`: sets the field of view (0...65535 = a full turn; held between about
    /// 3 and 90 degrees per half).
    func setCameraAngle(_ angle: UInt16) {
        let half = UInt32(bitPattern: clipX.max &- addX)
        var bx = angle >> 1
        if bx < 8 * 64 { bx = 8 * 64 }
        if bx >= 16384 { bx = 16383 }
        let tangent = UInt64(VisuTables.tangent[Int(bx >> 6)])
        let x = UInt32(truncatingIfNeeded: (UInt64(half) * tangent) >> 8)
        mulX = Int32(bitPattern: x)
        mulY = Int32(bitPattern: UInt32(truncatingIfNeeded: (UInt64(x) * UInt64(aspect)) >> 8))
    }

    // MARK: Per-object working lists (the original's o->v, o->n, o->pv)

    private(set) var rx: [Int32] = []
    private(set) var ry: [Int32] = []
    private(set) var rz: [Int32] = []
    private var nx: [Int16] = []
    private var ny: [Int16] = []
    private var nz: [Int16] = []
    private(set) var px: [Int16] = []
    private(set) var py: [Int16] = []
    private(set) var pflags: [UInt16] = []
    private var vertexNormal: [Int] = []

    static let up: UInt16 = 1, down: UInt16 = 2, left: UInt16 = 4, right: UInt16 = 8, near: UInt16 = 16, far: UInt16 = 32

    enum Outcome: Equatable {
        case invisible
        /// Every corner was off the same side of the window; the number holds which side(s).
        case offScreen(UInt16)
        /// Drawn, using this order list.
        case drawn(Int)
    }

    /// `vis_drawobject`: turn the object's corners and normals, project them, pick the order list
    /// whose direction vertex came out nearest, and draw its polygons in that order.
    @discardableResult
    func draw(_ mesh: VisuMesh, matrix r: VisuMatrix, flags: UInt16 = VisuFlags.objectDefault) -> Outcome {
        guard flags & VisuFlags.visible != 0 else { return .invisible }
        rotate(mesh, r)
        rotateNormals(mesh, r, count: flags & VisuFlags.gouraud != 0 ? mesh.normals.count : mesh.faceNormalCount)
        let all = project()
        if all != 0 { return .offScreen(all) }
        var list = 0
        var nearest = Int32.max
        for b in 1..<mesh.orders.count {
            let z = rz[mesh.orders[b][1]]
            if z < nearest { nearest = z; list = b }
        }
        drawPolygons(mesh, order: mesh.orders[list], objectFlags: flags)
        return .drawn(list)
    }

    /// `calc_rotate`. Only the low 16 bits of each matrix number are used (sign-extended), times the
    /// 32-bit coordinate; the three 64-bit products are added, shifted right 14, and the low 32
    /// bits kept; then the position is added.
    private func rotate(_ mesh: VisuMesh, _ r: VisuMatrix) {
        let n = mesh.vertexCount
        let m = r.m.map { Int64(Int16(truncatingIfNeeded: $0)) }
        rx = [Int32](repeating: 0, count: n); ry = rx; rz = rx
        for i in 0..<n {
            let (x, y, z) = (Int64(mesh.x[i]), Int64(mesh.y[i]), Int64(mesh.z[i]))
            rx[i] = Int32(truncatingIfNeeded: (m[0] * x + m[1] * y + m[2] * z) >> 14) &+ r.x
            ry[i] = Int32(truncatingIfNeeded: (m[3] * x + m[4] * y + m[5] * z) >> 14) &+ r.y
            rz[i] = Int32(truncatingIfNeeded: (m[6] * x + m[7] * y + m[8] * z) >> 14) &+ r.z
        }
        vertexNormal = mesh.vertexNormal
    }

    /// `calc_nrotate`: all in 16 bits. Three 32-bit products are added (wrapping at 32 bits),
    /// shifted right 14, and the low 16 bits kept.
    private func rotateNormals(_ mesh: VisuMesh, _ r: VisuMatrix, count: Int) {
        let m = r.m.map { Int32(Int16(truncatingIfNeeded: $0)) }
        let total = mesh.normals.count
        if nx.count < total {
            nx += [Int16](repeating: 0, count: total - nx.count); ny = nx.map { _ in 0 }; nz = ny
        }
        for i in 0..<count {
            let n = mesh.normals[i]
            let (x, y, z) = (Int32(n.x), Int32(n.y), Int32(n.z))
            nx[i] = Int16(truncatingIfNeeded: (x &* m[0] &+ y &* m[1] &+ z &* m[2]) >> 14)
            ny[i] = Int16(truncatingIfNeeded: (x &* m[3] &+ y &* m[4] &+ z &* m[5]) >> 14)
            nz[i] = Int16(truncatingIfNeeded: (x &* m[6] &+ y &* m[7] &+ z &* m[8]) >> 14)
        }
    }

    /// A 64-bit number divided by a 32-bit one, rounding towards zero, as the processor's `idiv`.
    private func divide(_ n: Int64, _ d: Int32) -> Int32 {
        if d == 0 { faults += 1; return 0 }
        let q = n / Int64(d)
        if q > Int64(Int32.max) || q < Int64(Int32.min) { faults += 1 }
        return Int32(truncatingIfNeeded: q)
    }

    /// The same for a 32-bit number divided by a 16-bit one.
    private func divide16(_ n: Int32, _ d: Int16) -> Int16 {
        if d == 0 { faults += 1; return 0 }
        let q = n / Int32(d)
        if q > Int32(Int16.max) || q < Int32(Int16.min) { faults += 1 }
        return Int16(truncatingIfNeeded: q)
    }

    /// Perspective for one point at distance `z`, with the window flags it earns.
    private func perspective(_ x: Int32, _ y: Int32, _ z: Int32) -> (x: Int16, y: Int16, flags: UInt16) {
        var flags: UInt16 = 0
        let sy = divide(Int64(y) * Int64(mulY), z) &+ addY
        if sy > clipY.max { flags |= Self.down }
        if sy < clipY.min { flags |= Self.up }
        let sx = divide(Int64(mulX) * Int64(x), z) &+ addX
        if sx > clipX.max { flags |= Self.right }
        if sx < clipX.min { flags |= Self.left }
        // Only 16 bits of each screen position are stored: a point very far off the side wraps round.
        return (Int16(truncatingIfNeeded: sx), Int16(truncatingIfNeeded: sy), flags)
    }

    /// `calc_project`: every corner to the screen. Returns the flags ALL corners share: non-zero
    /// means the whole object is off one side.
    private func project() -> UInt16 {
        let n = rx.count
        px = [Int16](repeating: 0, count: n); py = px
        pflags = [UInt16](repeating: 0, count: n)
        var all: UInt16 = 0xFFFF
        for i in 0..<n {
            var z = rz[i]
            var flags: UInt16 = 0
            if z < clipZ.min {
                flags |= Self.near
                z = clipZ.min
            } else if z > clipZ.max {
                flags |= Self.far
            }
            let p = perspective(rx[i], ry[i], z)
            px[i] = p.x; py[i] = p.y
            pflags[i] = flags | p.flags
            all &= pflags[i]
        }
        return all
    }

    // MARK: Lighting (ADRAW.ASM)

    /// Where the light comes from (`newlight`), as a direction of length about 16384.
    static let light: (x: Int16, y: Int16, z: Int16) = (12118, 10603, 3030)

    /// `normallight`: brightness 0...255 of a surface whose (turned) normal is number `i`.
    private func brightness(normal i: Int) -> Int {
        guard i < nx.count else { faults += 1; return 128 }
        let sum = Int32(nx[i]) &* Int32(Self.light.x) &+ Int32(ny[i]) &* Int32(Self.light.y) &+ Int32(nz[i]) &* Int32(Self.light.z)
        let v = Int(Int16(truncatingIfNeeded: sum >> 16) >> 5) + 128
        return min(max(v, 0), 255)
    }

    /// `calclight`: the shade to add to a polygon's first colour: 1...30, scaled to the length of
    /// its colour range (8, 16 or 32 shades).
    private func shade(flags: UInt16, normal: Int) -> Int {
        let bits = flags & VisuFlags.shade32
        var ax = 0
        if bits != 0 {
            ax = brightness(normal: normal) >> (6 - Int(bits >> 10))
        }
        if ax <= 1 { ax = 1 }
        if ax >= 30 { ax = 30 }
        return ax
    }

    // MARK: The polygon being worked on
    //
    // The original keeps two polygon records, `poly1` and `poly2`, one straight after the other in
    // memory, and the clipper ping-pongs between them. Some of its reads reach just outside a
    // record's vertex list (to compare with "the vertex before the first"), so the records are kept
    // here as raw bytes at the original offsets; such reads then find what the original found.

    private static let polySides = 0, polyColour = 2, polyFlags = 4
    private static let polyX = 16, polyY = 18
    private static let polyVertex = 16 + 16 * 4          // POLYVX: which 3D vertex each corner is
    private static let polyShade = 16 + 2 * 16 * 4       // POLYGR: Gouraud colour at each corner
    private static let polySize = 16 + 3 * 16 * 4        // 208
    private var poly = [UInt8](repeating: 0, count: 2 * 208 + 96)

    private func r16(_ at: Int) -> UInt16 { UInt16(poly[at]) | UInt16(poly[at + 1]) << 8 }
    private func s16(_ at: Int) -> Int16 { Int16(bitPattern: r16(at)) }
    private func w16(_ at: Int, _ v: UInt16) { poly[at] = UInt8(v & 255); poly[at + 1] = UInt8(v >> 8) }
    private func w16(_ at: Int, _ v: Int16) { w16(at, UInt16(bitPattern: v)) }
    private func r32(_ at: Int) -> UInt32 { UInt32(r16(at)) | UInt32(r16(at + 2)) << 16 }
    private func w32(_ at: Int, _ v: UInt32) { w16(at, UInt16(v & 0xFFFF)); w16(at + 2, UInt16(v >> 16)) }

    /// `draw_polylist`: every polygon of an order list.
    private func drawPolygons(_ mesh: VisuMesh, order: [Int], objectFlags: UInt16) {
        let data = VisuBytes(bytes: mesh.polygonData)
        let p1 = 0, p2 = Self.polySize
        for entry in order.dropFirst(2) {
            if entry == 0 { break }
            let first = UInt16(data.u16(entry))
            let flags = (objectFlags | 0x0F00) & first
            let sides = Int(first & 0xFF)
            w16(p1 + Self.polyFlags, flags)
            w16(p1 + Self.polySides, UInt16(sides))
            let normal = data.u16(entry + 4)
            if data.u16(entry + 2) == 0xFFFF { continue }

            // Hidden-face test: the face normal against the direction to its first corner.
            if flags & VisuFlags.twoSided == 0 {
                let v = data.u16(entry + 6)
                guard v < rx.count, normal < nx.count else { faults += 1; continue }
                let sum = Int64(nx[normal]) &* Int64(rx[v]) &+ Int64(ny[normal]) &* Int64(ry[v]) &+ Int64(nz[normal]) &* Int64(rz[v])
                if sum >= 0 { continue }
            }

            // Flat polygons get one shade; Gouraud ones get one per corner further down.
            var colour = UInt8(data.u8(entry + 2))
            if flags & VisuFlags.gouraud == 0 {
                colour = colour &+ UInt8(shade(flags: flags, normal: normal))
            }
            poly[p1 + Self.polyColour] = colour

            var allFlags: UInt8 = 0xFF, anyFlags: UInt8 = 0
            for i in 0..<min(sides, 16) {
                let v = data.u16(entry + 6 + i * 2)
                guard v < rx.count else { faults += 1; allFlags = 0xFF; anyFlags = 0xFF; break }
                w16(p1 + Self.polyVertex + i * 4, UInt16(v))
                let f = UInt8(pflags[v] & 0xFF)
                allFlags &= f
                anyFlags |= f
                w16(p1 + Self.polyX + i * 4, px[v])
                w16(p1 + Self.polyY + i * 4, py[v])
            }

            if flags & VisuFlags.gouraud != 0 {
                for i in 0..<sides {
                    let v = Int(r16(p1 + Self.polyVertex + i * 4))
                    let n = v < vertexNormal.count ? vertexNormal[v] : 0
                    let c = UInt8(shade(flags: flags, normal: n)) &+ poly[p1 + Self.polyColour]
                    w16(p1 + Self.polyShade + i * 4, UInt16(c) << 8)
                }
            }

            if allFlags != 0 { continue }                 // all corners off the same side
            var si = p1
            if anyFlags != 0 {
                si = clip(si, p2, flags: flags, any: anyFlags)
                if r16(si + Self.polySides) == 0 { continue }
            }
            if r16(si + Self.polyFlags) & VisuFlags.gouraud != 0 {
                edgesGouraud(si)
                fillGouraud()
            } else {
                edgesFlat(si)
                fillFlat()
            }
        }
    }

    // MARK: Clipping (ADRAWCLP.ASM)

    /// The original never sets this back to zero: once any near-plane cut has produced a point
    /// outside a window edge, that edge's bit stays set for the rest of the run, and every later
    /// near-clipped polygon is also run through that edge's clipper (which then usually changes
    /// nothing). Kept, because it is what the original does.
    private(set) var clipVisibility: UInt16 = 0
    private var clipCount = 0
    private var clipZero = 0
    private var clipGouraud = false

    /// For tests: forget what earlier polygons left behind, as when the program has just started.
    func resetClipper() {
        clipVisibility = 0
        for i in poly.indices { poly[i] = 0 }
        for i in stream.indices { stream[i] = 0 }
        for i in gouraudBuffer.indices { gouraudBuffer[i] = 0 }
    }

    /// `newclip`: near plane first (it makes new corners, which may be outside the window), then
    /// up, down, left, right, each only if some corner needs it. Returns which record holds the result.
    private func clip(_ source: Int, _ scratch: Int, flags: UInt16, any: UInt8) -> Int {
        var si = source, di = scratch
        var dl = UInt16(any)
        clipGouraud = flags & VisuFlags.gouraud != 0
        if dl & Self.near != 0 && r16(si + Self.polySides) != 0 {
            clipNear(si, di)
            swap(&si, &di)
            dl |= clipVisibility & 0xFF
        }
        if dl & Self.up != 0 && r16(si + Self.polySides) != 0 {
            clipEdge(si, di, clipped: Self.polyY, other: Self.polyX, limit: Int16(truncatingIfNeeded: clipY.min), keepAbove: true)
            swap(&si, &di)
        }
        if dl & Self.down != 0 && r16(si + Self.polySides) != 0 {
            clipEdge(si, di, clipped: Self.polyY, other: Self.polyX, limit: Int16(truncatingIfNeeded: clipY.max), keepAbove: false)
            swap(&si, &di)
        }
        if dl & Self.left != 0 && r16(si + Self.polySides) != 0 {
            clipEdge(si, di, clipped: Self.polyX, other: Self.polyY, limit: Int16(truncatingIfNeeded: clipX.min), keepAbove: true)
            swap(&si, &di)
        }
        if dl & Self.right != 0 && r16(si + Self.polySides) != 0 {
            clipEdge(si, di, clipped: Self.polyX, other: Self.polyY, limit: Int16(truncatingIfNeeded: clipX.max), keepAbove: false)
            swap(&si, &di)
        }
        return si
    }

    private func depth(_ vertex: Int) -> Int32 {
        guard vertex < rz.count else { faults += 1; return 0 }
        return rz[vertex]
    }

    /// `clipnear`: cuts the polygon at the nearest allowed distance, working in 3D, and projects
    /// the new corners. A new corner takes the Gouraud colour of the corner written before it
    /// (the original's TODO file says "ZCLIP / gouraud": it was never finished).
    private func clipNear(_ source: Int, _ dest: Int) {
        var si = source, di = dest
        clipZero = si
        let limit = clipZ.min
        w32(di, r32(si))
        clipCount = Int(r16(si)) + 1
        w32(di + 4, r32(si + 4))
        w16(di + Self.polyX - 4, UInt16(0x7FFF))

        var bx = Int(r16(si + Self.polyVertex))
        var bp = 0
        var visible = limit <= depth(bx)

        /// ZCLIPGETVX: step to the next corner (wrapping to the first at the end). False when done.
        func next() -> Bool {
            bp = bx
            let dx = clipCount - 1
            if dx < 1 { return false }
            clipCount = dx
            if dx > 1 { si += 4 } else { si = clipZero }
            bx = Int(r16(si + Self.polyVertex))
            return true
        }
        /// ZCLIPCLIP + ZCLIPADDVX: the point where the edge bp-bx crosses the near plane.
        func cut() {
            var a = bx, b = bp
            guard a < rz.count, b < rz.count else { faults += 1; return }
            if !(rz[a] > rz[b]) { swap(&a, &b) }          // a = the farther corner
            let whole = rz[a] &- rz[b]
            let part = rz[a] &- limit
            let x = divide(Int64(rx[b] &- rx[a]) * Int64(part), whole) &+ rx[a]
            let y = divide(Int64(ry[b] &- ry[a]) * Int64(part), whole) &+ ry[a]
            let p = perspective(x, y, limit)
            clipVisibility |= p.flags
            if !(s16(di + Self.polyX - 4) == p.x && s16(di + Self.polyY - 4) == p.y) {
                w16(di + Self.polyX, p.x)
                w16(di + Self.polyY, p.y)
                w16(di + Self.polyShade, r16(di - 4 + Self.polyShade))
                di += 4
            }
        }

        loop: while true {
            if !visible {
                repeat {
                    if !next() { break loop }
                } while limit >= depth(bx)
                cut()
                visible = true
            } else {
                repeat {
                    // ZCLIPADDVISVX: copy a corner that is in front of the plane
                    let (x, y) = (r16(si + Self.polyX), r16(si + Self.polyY))
                    if !(r16(di + Self.polyX - 4) == x && r16(di + Self.polyY - 4) == y) {
                        w16(di + Self.polyX, x)
                        w16(di + Self.polyY, y)
                        w16(di + Self.polyShade, r16(si + Self.polyShade))
                        di += 4
                    }
                    if !next() { break loop }
                } while limit <= depth(bx)
                cut()
                visible = false
            }
        }
        w16(dest + Self.polySides, UInt16((di - dest) >> 2))
    }

    /// `newclipup` / `newclipdown` / `newclipleft` / `newclipright`: cuts the polygon at one window
    /// edge, in screen pixels. `keepAbove` is true for the top and left edges (keep coordinates at
    /// or above the limit).
    private func clipEdge(_ source: Int, _ dest: Int, clipped c: Int, other o: Int, limit: Int16, keepAbove: Bool) {
        var si = source, di = dest
        var bx = 0
        clipZero = si
        w32(di, r32(si))
        clipCount = Int(r16(si)) + 1
        w32(di + 4, r32(si + 4))
        w16(di + Self.polyX - 4, UInt16(0x7FFF))

        // Note the two tests differ on a corner exactly ON the limit: it counts as inside while the
        // walk is inside, and as outside while the walk is outside.
        func inside(_ at: Int) -> Bool { keepAbove ? s16(at + c) >= limit : s16(at + c) <= limit }
        func outside(_ at: Int) -> Bool { keepAbove ? s16(at + c) <= limit : s16(at + c) >= limit }

        /// NEWCLIPNEXT
        func next() -> Bool {
            bx = si
            let dx = clipCount - 1
            if dx < 1 { return false }
            clipCount = dx
            if dx > 1 { si += 4 } else { si = clipZero }
            return true
        }
        /// NEWCLIPCALC: where the edge bx-si crosses the limit, in 16-bit arithmetic with a
        /// 0...16384 multiplier.
        func cut() {
            var o1 = s16(si + o), c1 = s16(si + c)
            var o2 = s16(bx + o), c2 = s16(bx + c)
            var flip = false
            if !(c1 < c2) {
                flip = true
                swap(&c1, &c2)
                swap(&o1, &o2)
            }
            let run = limit &- c1
            let rise = o2 &- o1
            let multiplier = divide16(Int32(run) << 14, c2 &- c1)
            let cutOther = Int16(truncatingIfNeeded: (Int32(rise) * Int32(multiplier)) >> 14) &+ o1
            if s16(di + o - 4) == cutOther && s16(di + c - 4) == limit { return }
            w16(di + o, cutOther)
            w16(di + c, limit)
            if clipGouraud {
                // newclip_grd: the colour between the two corners, by the same multiplier
                let from = flip ? bx : si
                let to = flip ? si : bx
                let step = Int16(bitPattern: r16(to + Self.polyShade) &- r16(from + Self.polyShade))
                let colour = UInt16(truncatingIfNeeded: (Int32(step) * Int32(multiplier)) >> 14) &+ r16(from + Self.polyShade)
                w16(di + Self.polyShade, colour)
            }
            di += 4
        }

        var visible = inside(si)
        loop: while true {
            if !visible {
                repeat {
                    if !next() { break loop }
                } while outside(si)
                cut()
                visible = true
            } else {
                repeat {
                    // NEWCLIPCOPY
                    let xy = r32(si + Self.polyX)
                    if r32(di + Self.polyX - 4) != xy {
                        w32(di + Self.polyX, xy)
                        w16(di + Self.polyShade, r16(si + Self.polyShade))
                        di += 4
                    }
                    if !next() { break loop }
                } while inside(si)
                cut()
                visible = false
            }
        }
        w16(dest + Self.polySides, UInt16((di - dest) >> 2))
    }

    // MARK: From polygon to edge list (ADRAW.ASM `poly_nrm`, `poly_grd`)
    //
    // The edge list ("fill data", described in the original's DOC file) says, from the top row down:
    // a new left edge starts here (position and step per row), a new right edge starts here, now
    // fill this many rows. Positions are 16.16 fixed point: whole pixels in the upper 16 bits.

    private var stream = [UInt8](repeating: 0, count: 2048)

    private func put16(_ at: Int, _ v: UInt16) {
        guard at >= 0, at + 1 < stream.count else { faults += 1; return }
        stream[at] = UInt8(v & 255); stream[at + 1] = UInt8(v >> 8)
    }
    private func put32(_ at: Int, _ v: UInt32) { put16(at, UInt16(v & 0xFFFF)); put16(at + 2, UInt16(v >> 16)) }
    private func get16(_ at: Int) -> UInt16 {
        guard at >= 0, at + 1 < stream.count else { faults += 1; return 0xFFFF }
        return UInt16(stream[at]) | UInt16(stream[at + 1]) << 8
    }
    private func get32(_ at: Int) -> UInt32 { UInt32(get16(at)) | UInt32(get16(at + 2)) << 16 }

    private func edgesFlat(_ polygon: Int) { edges(polygon, gouraud: false) }
    private func edgesGouraud(_ polygon: Int) { edges(polygon, gouraud: true) }

    private func edges(_ polygon: Int, gouraud: Bool) {
        var si = polygon
        let sides = Int(r16(si + Self.polySides))
        let last = si + sides * 4 - 4
        let firstVertex = si

        // The topmost corner (the first one, if several share the top row) and the bottom row.
        var top = si
        var topY = s16(si + Self.polyY)
        var bottomY = topY
        var count = sides
        while true {
            si += 4
            count -= 1
            if count == 0 { break }
            let y = s16(si + Self.polyY)
            if y > bottomY { bottomY = y }
            if y < topY { topY = y; top = si }
        }
        var currentY = topY

        put16(0, r16(polygon + Self.polyColour))
        put16(2, UInt16(bitPattern: topY))
        var bp = 6
        if topY == bottomY {                              // no height: nothing to draw
            put16(bp - 2, 0xFFFF)
            return
        }
        bp -= 2

        var left = top, right = top                       // the left edge walks backwards, the right forwards
        var leftRows: Int16 = 0, rightRows: Int16 = 0

        /// POLYSIDECALC: one edge from corner `from` to corner `to`, `rows` rows tall.
        func side(_ from: Int, _ to: Int, _ rows: UInt16) {
            put16(bp - 2, 0x7777)
            if gouraud {
                let start = r16(from + Self.polyShade)
                put16(bp, start)
                let difference = Int16(bitPattern: r16(to + Self.polyShade) &- start)
                put16(bp + 2, UInt16(bitPattern: divide16(Int32(difference), Int16(bitPattern: rows))))
                bp += 4
            }
            let startX = Int32(s16(from + Self.polyX)) << 16 | 0x8000
            put32(bp, UInt32(bitPattern: startX))
            let endX = Int32(s16(to + Self.polyX)) << 16 | 0x8000
            let step = divide(Int64(endX &- startX), Int32(rows))
            put32(bp + 4, UInt32(bitPattern: step))
            bp += 8
        }

        while true {
            put16(bp, 0); bp += 2
            if s16(left + Self.polyY) == currentY {
                while true {
                    var bx = left - 4
                    if bx < firstVertex { bx = last }
                    let (a, b) = (r16(bx + Self.polyY), r16(left + Self.polyY))
                    if a < b { put16(bp - 2, 0xFFFF); return }     // the edge turns upwards: polygon done
                    if a == b { left = bx; continue }
                    leftRows = Int16(bitPattern: a &- b)
                    side(left, bx, a &- b)
                    left = bx
                    break
                }
            }
            put16(bp, 0); bp += 2
            if s16(right + Self.polyY) == currentY {
                while true {
                    var bx = right + 4
                    if bx > last { bx = firstVertex }
                    let (a, b) = (r16(bx + Self.polyY), r16(right + Self.polyY))
                    if a < b { put16(bp - 2, 0xFFFF); return }
                    if a == b { right = bx; continue }
                    rightRows = Int16(bitPattern: a &- b)
                    side(right, bx, a &- b)
                    right = bx
                    break
                }
            }
            let rows = leftRows < rightRows ? leftRows : rightRows
            put16(bp, UInt16(bitPattern: rows))
            leftRows &-= rows
            rightRows &-= rows
            bp += 2
            currentY &+= rows
            if bp > stream.count - 40 { faults += 1; put16(bp - 2, 0xFFFF); return }
        }
    }

    // MARK: Filling (AVIDFILL.ASM)

    /// One pixel. The original wrote into a planar video page; a position outside the picture
    /// would have landed in a neighbouring row or page. That never happens with clipped polygons.
    @inline(__always)
    private func plot(_ row: Int, _ x: Int, _ colour: UInt8) {
        let at = row + x
        if x < 0 || x >= Self.width || at < 0 || at >= pixels.count { faults += 1; return }
        pixels[at] = colour
    }

    /// `drawfill_nrm`: fills the edge list with one colour. On each row both edges are stepped
    /// FIRST, then the pixels from the smaller position up to (not including) the larger are filled.
    private func fillFlat() {
        let colour = UInt8(get16(0) & 0xFF)
        var row = Int(Int16(bitPattern: get16(2))) * Self.width
        var si = 4
        var leftX: UInt32 = 0, leftStep: UInt32 = 0, rightX: UInt32 = 0, rightStep: UInt32 = 0
        while true {
            var flag = get16(si); si += 2
            if flag & 0x8000 != 0 { return }
            if flag != 0 { leftX = get32(si); leftStep = get32(si + 4); si += 8 }
            flag = get16(si); si += 2
            if flag & 0x8000 != 0 { return }
            if flag != 0 { rightX = get32(si); rightStep = get32(si + 4); si += 8 }
            var count = get16(si)
            if count == 0 { return }
            si += 2
            repeat {
                leftX = leftX &+ leftStep
                rightX = rightX &+ rightStep
                var a = Int(Int16(truncatingIfNeeded: rightX >> 16))
                var b = Int(Int16(truncatingIfNeeded: leftX >> 16))
                if a != b {
                    if a > b { swap(&a, &b) }
                    for x in a..<b { plot(row, x, colour) }
                }
                row += Self.width
                count &-= 1
            } while count != 0
        }
    }

    /// The Gouraud filler's scratch row (`vdfg_buf`), kept between rows as the original's was.
    private var gouraudBuffer = [UInt8](repeating: 0, count: 641)

    /// `drawfill_grd`: fills the edge list with a colour that runs smoothly from one edge to the
    /// other. Colours are 8.8 fixed point (colour number in the upper byte). Each row is drawn as
    /// its two end pixels plus a middle of 2-pixel blocks, and the middle is coloured in steps of
    /// 1, 2 or 4 pixels depending on how fast the colour changes (`gouraud1/2/4`).
    private func fillGouraud() {
        var row = Int(Int16(bitPattern: get16(2))) * Self.width
        var si = 4
        var leftX: UInt32 = 0, leftStep: UInt32 = 0, rightX: UInt32 = 0, rightStep: UInt32 = 0
        var leftC: UInt16 = 0, leftCStep: UInt16 = 0, rightC: UInt16 = 0, rightCStep: UInt16 = 0
        while true {
            var flag = get16(si); si += 2
            if flag & 0x8000 != 0 { return }
            if flag != 0 {
                leftC = get16(si); leftCStep = get16(si + 2)
                leftX = get32(si + 4); leftStep = get32(si + 8); si += 12
            }
            flag = get16(si); si += 2
            if flag & 0x8000 != 0 { return }
            if flag != 0 {
                rightC = get16(si); rightCStep = get16(si + 2)
                rightX = get32(si + 4); rightStep = get32(si + 8); si += 12
            }
            var count = get16(si)
            if count == 0 { return }
            si += 2
            repeat {
                leftC = leftC &+ leftCStep
                rightC = rightC &+ rightCStep
                leftX = leftX &+ leftStep
                rightX = rightX &+ rightStep
                gouraudRow(row,
                           leftX: Int16(truncatingIfNeeded: leftX >> 16), rightX: Int16(truncatingIfNeeded: rightX >> 16),
                           leftC: leftC, rightC: rightC)
                row += Self.width
                count &-= 1
            } while count != 0
        }
    }

    private func gouraudRow(_ row: Int, leftX: Int16, rightX: Int16, leftC: UInt16, rightC: UInt16) {
        if rightX == leftX { return }
        // colour1 belongs to the smaller x, colour2 to the larger
        var first = rightX, lastX = leftX
        var colour1 = rightC, colour2 = leftC
        if !(rightX < leftX) {
            first = leftX; lastX = rightX
            colour1 = leftC; colour2 = rightC
        }
        lastX &-= 1                                        // the rightmost pixel is not filled
        let l = UInt16(bitPattern: first), r = UInt16(bitPattern: lastX)

        // The two end pixels, when they do not line up with a 2-pixel block.
        if r & 1 == 0 { plot(row, Int(r), UInt8(colour2 >> 8)) }
        if l & 1 == 1 { plot(row, Int(l), UInt8(colour1 >> 8)) }

        let firstBlock = (l &+ 1) >> 1
        let lastBlock = (r &- 1) >> 1
        let blocks = Int16(bitPattern: lastBlock &- firstBlock &+ 1)
        if blocks <= 0 { return }
        let n = Int(blocks)
        guard n < 512 else { faults += 1; return }
        let x0 = Int(firstBlock) * 2

        // Colour step per block: |difference| * (65536 / blocks) >> 16, with the sign put back.
        var step: Int16
        let difference = Int16(bitPattern: colour1 &- colour2)
        if difference >= 0 {
            step = Int16(bitPattern: UInt16((UInt32(UInt16(bitPattern: difference)) * UInt32(VisuTables.fillDivide[n])) >> 16))
        } else {
            let positive = UInt16(bitPattern: 0 &- difference)
            step = 0 &- Int16(bitPattern: UInt16((UInt32(positive) * UInt32(VisuTables.fillDivide[n])) >> 16))
        }

        // The original fills a scratch row from the RIGHT end (colour2) leftwards, then copies it
        // to the screen. `value(k)` is the colour k steps in from the right.
        if step >= 400 || step <= -400 {
            // gouraud1: a new colour every pixel
            let s = UInt16(bitPattern: step >> 1)
            let pixelCount = n * 2
            var c = colour2
            for z in stride(from: pixelCount - 1, through: 0, by: -1) {
                plot(row, x0 + z, UInt8(c >> 8))
                c = c &+ s
            }
        } else if step >= 128 || step <= -128 || n < 4 {
            // gouraud2: a new colour every 2 pixels
            let s = UInt16(bitPattern: step)
            var c = colour2
            for z in stride(from: n - 1, through: 0, by: -1) {
                plot(row, x0 + z * 2, UInt8(c >> 8))
                plot(row, x0 + z * 2 + 1, UInt8(c >> 8))
                c = c &+ s
            }
        } else {
            // gouraud4: a new colour every 4 pixels, lined up with the screen's 4-pixel bytes
            let s = UInt16(bitPattern: step << 1)
            let m = (n >> 1) + 1
            var c = colour2 &- s
            for z in stride(from: m - 1, through: 0, by: -1) {
                gouraudBuffer[z] = UInt8(c >> 8)
                c = c &+ s
            }
            let firstByte = x0 >> 2
            for x in x0..<(x0 + n * 2) {
                plot(row, x, gouraudBuffer[(x >> 2) - firstByte])
            }
        }
    }
}
