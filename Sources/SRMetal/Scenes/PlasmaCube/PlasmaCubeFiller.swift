import Foundation

/// The VGA card's memory as the Plasma Cube used it, and the routines that drew into it:
/// a step-for-step port of PLZFILL.C (`do_poly`, `clear`) and PLZA.ASM (`do_block`, `do_clear`).
///
/// The screen mode stored four pixels in each memory address, one in each of four "planes".
/// Writing a byte with all four planes switched on therefore paints four pixels at once, which is
/// how the original filled the cube quickly: the texture is only worked out once per four pixels.
/// At the two ends of each line it switches some planes off, so the cube's outline is still
/// accurate to one pixel.
///
/// There are three pages of 640x136 pixels, used in turn. Only a 320-pixel-wide window of a page
/// is shown, starting 160 pixels in.
struct CubeVideoCard {
    static let pageStarts = [0x0000, 0x5500, 0xAA00]
    static let bytesPerLine = 160
    static let lines = 134

    /// Four planes of 64 KB each, one after the other.
    private var memory = [UInt8](repeating: 0, count: 4 << 16)
    /// Which planes a write reaches (VGA sequencer register 2). It is left as the last line set it.
    private var planeMask: UInt8 = 0x0F
    /// For each of the last 8 frames and each line: the leftmost and rightmost pixel drawn (`clrtau`).
    /// "640, 0" means nothing was drawn on that line.
    private var extents: [UInt16] = {
        var table = [UInt16](repeating: 0, count: 8 * 256 * 2)
        for i in stride(from: 0, to: table.count, by: 2) { table[i] = 640 }
        return table
    }()
    private var extentSlot = 0
    /// Counts 0...5 (`page`): which of the three pages is drawn into, and whether this frame is
    /// drawn two pixels to the right.
    private(set) var page: Int
    private var pageStart = 0

    /// `page` is the value before the first frame; the first frame is drawn with `page + 1`.
    init(page: Int) {
        self.page = page
    }

    /// How far right this frame is drawn. The original drew every other frame two pixels to the
    /// right and slid the picture two pixels left to compensate, so the cube stayed put while the
    /// four-pixel blocks of its texture landed half a block apart on alternate frames.
    var shift: Int { (page & 1) * 2 }

    mutating func swapPage() {
        page = (page + 1) % 6
        pageStart = Self.pageStarts[page % 3]
    }

    // MARK: - Reading the screen

    /// What the monitor shows of the page just drawn: 320x134 colour numbers.
    func screen() -> [UInt8] {
        var picture = [UInt8](repeating: 0, count: 320 * Self.lines)
        for y in 0..<Self.lines {
            let base = pageStart + 40 + y * Self.bytesPerLine
            for x in 0..<320 {
                let v = x + shift
                picture[y * 320 + x] = memory[((v & 3) << 16) | ((base + (v >> 2)) & 0xFFFF)]
            }
        }
        return picture
    }

    // MARK: - Writing

    @inline(__always)
    private mutating func write(_ offset: Int, _ value: UInt8) {
        let o = offset & 0xFFFF
        if planeMask & 1 != 0 { memory[o] = value }
        if planeMask & 2 != 0 { memory[0x10000 | o] = value }
        if planeMask & 4 != 0 { memory[0x20000 | o] = value }
        if planeMask & 8 != 0 { memory[0x30000 | o] = value }
    }

    /// Planes to switch on for the first byte of a line that starts at pixel x (`start_mask`).
    private static let startMask: [UInt8] = [0b1111, 0b1110, 0b1100, 0b1000]
    /// Planes for the last byte of a line that ends at pixel x (`end_mask`).
    private static let endMask: [UInt8] = [0b0001, 0b0011, 0b0111, 0b1111]

    // MARK: - Filling one face (PLZFILL.C do_poly)

    /// The two edges being walked down, as 16.16 fixed-point numbers (whole part in the top 16 bits).
    /// Edge 1 runs to the next corner, edge 2 to the previous one; for a face that is turned towards
    /// the viewer edge 2 is the left end of each line and edge 1 the right end.
    private struct Edges {
        var x1: UInt32 = 0, x2: UInt32 = 0
        var xStep1: UInt32 = 0, xStep2: UInt32 = 0
        var u1: UInt32 = 0, v1: UInt32 = 0, u2: UInt32 = 0, v2: UInt32 = 0
        var uStep1: UInt32 = 0, vStep1: UInt32 = 0, uStep2: UInt32 = 0, vStep2: UInt32 = 0
        /// Current line (`yy`), the memory address of its first byte (`to`), and the texture set.
        var line = 0
        var address = 0
        var group = 0
        /// First row of the sideways-shift table to use (`dseg`): it scrolls one row per frame.
        var shiftRow = 0
    }

    /// Texture position of each of a face's four corners (`txt`).
    static let cornerTexture: [(u: Int, v: Int)] = [(64, 4), (190, 4), (190, 60), (64, 60)]

    /// Draws one four-cornered face. `corners` are page coordinates (x 0...639), in the face's own
    /// corner order; `group` 0...2 picks the colour range; `frame` is the frame counter's low 6 bits.
    mutating func fillFace(_ corners: [(x: Int, y: Int)], group: Int, frame: Int) {
        var top = 0
        for a in 1..<4 where corners[a].y < corners[top].y { top = a }

        var edges = Edges()
        edges.group = group
        edges.shiftRow = (frame + 1) & 63

        func setEdge(_ first: Bool, from s: Int, to d: Int) {
            let dx = Int(Int16(truncatingIfNeeded: corners[d].x - corners[s].x))
            var dy = Int(Int16(truncatingIfNeeded: corners[d].y - corners[s].y))
            if dy == 0 { dy = 1 }
            func fixed(_ whole: Int) -> UInt32 { UInt32(truncatingIfNeeded: (whole << 16) + 0x8000) }
            func slope(_ change: Int) -> UInt32 {
                // C: 65536L * change / dy, in 32-bit whole numbers, rounding towards zero.
                UInt32(bitPattern: Int32(truncatingIfNeeded: 65536 * change) / Int32(dy))
            }
            let texture = Self.cornerTexture
            if first {
                edges.xStep1 = slope(dx)
                edges.x1 = fixed(corners[s].x)
                edges.u1 = fixed(texture[s].u)
                edges.v1 = fixed(texture[s].v)
                edges.uStep1 = slope(texture[d].u - texture[s].u)
                edges.vStep1 = slope(texture[d].v - texture[s].v)
            } else {
                edges.xStep2 = slope(dx)
                edges.x2 = fixed(corners[s].x)
                edges.u2 = fixed(texture[s].u)
                edges.v2 = fixed(texture[s].v)
                edges.uStep2 = slope(texture[d].u - texture[s].u)
                edges.vStep2 = slope(texture[d].v - texture[s].v)
            }
        }

        var s1 = top, s2 = top
        var d1 = (s1 + 1) & 3, d2 = (s2 - 1) & 3
        setEdge(true, from: s1, to: d1)
        setEdge(false, from: s2, to: d2)

        var y = corners[s1].y
        edges.line = y
        edges.address = (pageStart + y * Self.bytesPerLine) & 0xFFFF

        var switches = 0
        while switches < 4 {
            let until = min(corners[d1].y, corners[d2].y)
            fillLines(&edges, count: UInt16(truncatingIfNeeded: until - y))
            y = until
            edges.line = y

            if corners[d1].y == corners[d2].y {
                s1 = d1; d1 = (s1 + 1) & 3
                s2 = d2; d2 = (s2 - 1) & 3
                switches += 2
                setEdge(true, from: s1, to: d1)
                setEdge(false, from: s2, to: d2)
            } else if corners[d1].y < corners[d2].y {
                s1 = d1; d1 = (s1 + 1) & 3
                switches += 1
                setEdge(true, from: s1, to: d1)
            } else {
                s2 = d2; d2 = (s2 - 1) & 3
                switches += 1
                setEdge(false, from: s2, to: d2)
            }
        }
    }

    // MARK: - Filling lines (PLZA.ASM do_block)

    /// The colour number at a texture position given as the original's 16-bit index: row * 256 + column.
    /// First the row's sideways shift is looked up, then the texture is read that many places on.
    @inline(__always)
    private func texel(_ index: Int, _ edges: Edges) -> UInt8 {
        let shiftIndex = edges.shiftRow * 256 + index
        // The shift is a signed byte that the original read as unsigned (0...255): a shift to the
        // left therefore also lands one texture row down. Kept, because it is what was drawn.
        let shift = shiftIndex < PlasmaCubeModel.sideShift.count ? Int(PlasmaCubeModel.sideShift[shiftIndex]) : 0
        let at = (index + shift) & 0xFFFF
        // Past the end of the texture the original would have read whatever came next in memory.
        // That never happens on this path (the self-test's pictures would differ if it did).
        guard at < PlasmaCubeModel.texture.count else { return 0 }
        return PlasmaCubeModel.texture[at] &+ UInt8(edges.group * 64)
    }

    private mutating func fillLines(_ e: inout Edges, count: UInt16) {
        var remaining = count
        if remaining == 0 { return }

        while true {
            line: do {
                if e.line < 0 { break line }                       // above the screen: just step on
                if e.line >= Self.lines { return }                 // below it: stop altogether

                // Note the leftmost and rightmost pixel of this line, for erasing later.
                let slot = (extentSlot * 256 + e.line) * 2
                let left = UInt16(e.x2 >> 16)
                let right = UInt16(e.x1 >> 16)
                if left <= extents[slot] { extents[slot] = left }
                if right >= extents[slot + 1] { extents[slot + 1] = right }

                let leftByte = Int(left >> 2)
                let rightByte = Int(right >> 2)
                if rightByte < leftByte { break line }
                let address = e.address + leftByte
                let span = rightByte - leftByte

                // The two end bytes take the texture exactly at each edge.
                let leftTexel = texel(Int((e.v2 >> 16) & 0xFF) << 8 | Int((e.u2 >> 16) & 0xFF), e)

                if span == 0 {
                    planeMask = Self.startMask[Int(left & 3)] & Self.endMask[Int(right & 3)]
                    write(address, leftTexel)
                    break line
                }

                let inner = span - 1
                if inner > 0 {
                    planeMask = 0x0F
                    // The texture is stepped from the right edge towards the left, one step per byte.
                    // What follows mirrors the processor's registers, including two accidents of
                    // the original code that change the odd pixel:
                    //  - the fraction of the texture column does not start from the edge's own
                    //    fraction but from the whole part of the row step (a register was reused);
                    //  - the low half of the register holding the column step also holds the two
                    //    pixels just looked up, and they are added in along with it.
                    let vStep = Int32(bitPattern: e.v2 &- e.v1) / Int32(inner)
                    let uStep = Int32(bitPattern: e.u2 &- e.u1) / Int32(inner)
                    var ecx = UInt32(bitPattern: vStep)
                    var edx = (ecx << 16) | (ecx >> 16)
                    edx = (edx & 0xFFFF_00FF) | ((edx & 0xFF) << 8)                    // mov dh, dl
                    var eax = UInt32(bitPattern: uStep)
                    eax = (eax << 16) | (eax >> 16)
                    edx = (edx & 0xFFFF_FF00) | (eax & 0xFF)                           // mov dl, al
                    if edx & 0x80 != 0 {                                                // dec dh
                        edx = (edx & 0xFFFF_00FF) | ((((edx >> 8) &- 1) & 0xFF) << 8)
                    }
                    var ebx = ((e.v1 & 0xFFFF) << 16) | ((e.v1 >> 16) & 0xFF) << 8 | ((e.u1 >> 16) & 0xFF)

                    // One texture sample; returns the colour number and moves on one step.
                    @inline(__always) func sample() -> UInt8 {
                        let value = texel(Int(ebx & 0xFFFF), e)
                        let (sum, carry) = ecx.addingReportingOverflow(eax)          // add ecx, eax
                        ecx = sum
                        let wide = UInt64(ebx) + UInt64(edx) + (carry ? 1 : 0)         // adc ebx, edx
                        ebx = UInt32(truncatingIfNeeded: wide)
                        if wide >> 32 != 0 {                                           // adc bh, 0
                            ebx = (ebx & 0xFFFF_00FF) | ((((ebx >> 8) &+ 1) & 0xFF) << 8)
                        }
                        return value
                    }

                    var pairs = inner / 2
                    if inner & 1 == 1 {
                        let value = sample()
                        eax = (eax & 0xFFFF_FF00) | UInt32(value)
                        write(address + span - 1, value)
                        pairs = (span - 2) / 2
                    }
                    var pair = pairs
                    while pair >= 1 {
                        let high = sample()
                        eax = (eax & 0xFFFF_00FF) | (UInt32(high) << 8)
                        let low = sample()
                        eax = (eax & 0xFFFF_FF00) | UInt32(low)
                        write(address + pair * 2 - 1, low)
                        write(address + pair * 2, high)
                        pair -= 1
                    }
                }

                let rightTexel = texel(Int((e.v1 >> 16) & 0xFF) << 8 | Int((e.u1 >> 16) & 0xFF), e)
                planeMask = Self.startMask[Int(left & 3)]
                write(address, leftTexel)
                planeMask = Self.endMask[Int(right & 3)]
                write(address + span, rightTexel)
            }

            // Next line.
            e.address = (e.address + Self.bytesPerLine) & 0xFFFF
            e.line += 1
            e.x1 = e.x1 &+ e.xStep1
            e.x2 = e.x2 &+ e.xStep2
            e.v1 = e.v1 &+ e.vStep1
            e.u1 = e.u1 &+ e.uStep1
            e.v2 = e.v2 &+ e.vStep2
            e.u2 = e.u2 &+ e.uStep2
            remaining &-= 1
            if remaining == 0 { return }
        }
    }

    // MARK: - Erasing the previous cube (PLZFILL.C clear, PLZA.ASM do_clear)

    /// Called after a frame is drawn. The page still holds the cube from three frames ago; rather than
    /// wiping the page, this blanks only the parts of each line the old cube covered and the new one
    /// does not, then tidies the few pixels beside the new cube's two ends.
    mutating func eraseOld() {
        let old = ((extentSlot - 3) & 7) * 512
        let new = extentSlot * 512
        extentSlot = (extentSlot + 1) & 7

        planeMask = 0x0F
        // The original loaded the page's address, then overwrote its low byte with a byte read from
        // video memory (to "fill the latches"). That byte is always 0 here, as is the low byte.
        var base = (pageStart & 0xFF00) | Int(memory[0])
        for line in 0...Self.lines {
            let o = old + line * 2, n = new + line * 2
            if extents[o] != 640 {
                var from = Int(extents[o] >> 2)
                var count = Int(extents[n] >> 2) - from
                if count >= 0 {
                    for i in 0..<count { write(base + from + i, 0) }
                }
                from = Int(extents[n + 1] >> 2)
                count = Int(extents[o + 1] >> 2) - from
                if count >= 0 {
                    for i in 0..<count { write(base + from + 1 + i, 0) }
                }
            }
            extents[o] = 640
            extents[o + 1] = 0
            base = (base + Self.bytesPerLine) & 0xFFFF
        }

        // Blank the pixels just left and just right of the new cube on every line.
        for line in 0..<Self.lines {
            let n = new + line * 2
            let address = pageStart + line * Self.bytesPerLine
            let before = Int(extents[n] &- 1)
            planeMask = Self.endMask[before & 3]
            write(address + (before >> 2), 0)
            let after = Int(extents[n + 1] &+ 1)
            planeMask = Self.startMask[after & 3]
            write(address + (after >> 2), 0)
        }
    }
}
