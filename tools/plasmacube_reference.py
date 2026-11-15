#!/usr/bin/env python3
"""Reference pictures for the Plasma Cube, made by running the ORIGINAL assembly.

The original scene (second half of PLZPART.EXE) is part C, part assembly:

  - PLZA.ASM   do_block (the textured line filler), do_clear (erasing the previous cube),
               shadepal (dimming a palette for the lighting)
  - SPLINE.ASM getspl (the flight path), with RATA.INC (path points) and SPLINE.INC (blend weights)
  - VECT.C and PLZFILL.C: rotation, projection, which faces show, edge walking, page flipping

This tool reads the two assembly files AS TEXT, expands their macros (IRP / REPT), and carries the
instructions out one at a time in a small x86 interpreter with a model of the VGA card's four bit
planes. The C parts are re-written here in Python, keeping C's 16- and 32-bit whole-number rules.
It prints CRC-32 checksums of the 320x134 screen (colour numbers) and of the palette at the steps
asked for; App/SelfTest.swift expects the same numbers from the Swift replay.

Usage:
  python3 tools/plasmacube_reference.py [--src PLZPART-folder] [--page 1|4] [--png] step [step ...]
  python3 tools/plasmacube_reference.py --tables      (prints Scenes/PlasmaCube/PlasmaCubeTables.swift)
  python3 tools/plasmacube_reference.py --range       (prints coordinate ranges over the whole run)

Steps are 1/70 s, counted as the app counts them: step t is the original's frame t - LEAD (the app
starts LEAD frames early, while the cube is still below the screen). --page chooses which of the six
page states the run starts in: 1 and 4 use the same video page but opposite 2-pixel offsets, and the
app shows the average of the two. Development tool only; the app does not use it.
"""
import re, sys, os, struct, zlib

LEAD = 16            # must match PlasmaCubeModel.leadIn
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'secondreality', 'PLZPART')
sys.path.insert(0, HERE)
import x86interp
# The machine (1 MB of memory, the VGA's four planes, registers, flags) and the small assembler
# live in tools/x86interp.py, shared with the other reference tools.
from x86interp import (M, planes, PM, R, SG, F, STACK, REG, rd8, wr8, rd, wr, labels, code_labels, code,
                       fixups, proc_segment, evaluate, assemble, call, s16, s32, cdiv)

# ----------------------------------------------------------------------------------------------
# Memory map (any free real-mode segments will do) and the C program's variables.
# ----------------------------------------------------------------------------------------------
PLZA, SPLINE, DATA = 0x1000, 0x2000, 0x3000
KUVA = [0x4000, 0x5000, 0x6000, 0x4000]      # kuvataus[]: texture for colour group 0, 1, 2 (3 unused)
DIST = 0x7000
VIDEO = 0xA000
for i, n in enumerate(['kx', 'ky', 'kz', 'dis', 'tx', 'ty', 'ls_kx', 'ls_ky', 'ls_kz']):
    labels[n] = (DATA, i * 2, 2)
CLRTAU, PAL, FPAL = 0x0100, 0x2200, 0x2600   # offsets inside DATA

def getvar(name): return s16(rd(*labels[name][:2], 2))
def setvar(name, v):
    seg, off, size = labels[name]
    wr(seg, off, size, v)

def read_table(filename, directive):
    values = []
    for l in open(os.path.join(SRC, filename), 'rb').read().decode('latin1').splitlines():
        m = re.match(r'\s*' + directive + r'\s+(.*)', l.split(';')[0], re.I)
        if m: values += [int(v) for v in re.findall(r'-?\d+', m.group(1))]
    return values

sinit_bytes = read_table('SINIT.INC', 'db')
SINIT = [s16(sinit_bytes[i] | sinit_bytes[i + 1] << 8) for i in range(0, len(sinit_bytes) - 1, 2)]
def sinit(i): return SINIT[i]
def kosinit(i): return SINIT[i + 256]          # "kosinit=sinit+512" is 512 BYTES on: a quarter turn

import math
SINI = [int(math.sin(a / 1024.0 * math.pi * 4) * 127) for a in range(1524)]   # initvect's own little table

def initvect():
    pal = [0] * 768
    for a in range(1, 32):
        pal[a * 3:a * 3 + 3] = [0, 0, a * 2]
    for a in range(32):
        pal[a * 3 + 96:a * 3 + 99] = [a * 2, a * 2, 63]
        pal[192 + a * 3:192 + a * 3 + 3] = [a * 2, 0, 0]
        pal[192 + a * 3 + 96:192 + a * 3 + 99] = [63, a * 2, 0]
        pal[384 + a * 3:384 + a * 3 + 3] = [a, 0, a * 2 // 3]
        pal[384 + a * 3 + 96:384 + a * 3 + 99] = [31 - a, a * 2, 21]
    M[(DATA << 4) + PAL:(DATA << 4) + PAL + 768] = bytes(pal)
    for y in range(64):
        for x in range(256):
            v = cdiv(SINI[(y * 4 + SINI[x * 2]) & 511], 4) + 32
            for g in range(3):
                M[(KUVA[g] << 4) + y * 256 + x] = v + 64 * g
    for y in range(128):
        for x in range(256):
            M[(DIST << 4) + y * 256 + x] = cdiv(SINI[y * 8], 3) & 0xFF
    for a in range(8 * 256):
        wr(DATA, CLRTAU + a * 4, 2, 640)
        wr(DATA, CLRTAU + a * 4 + 2, 2, 0)

POINTS = [(125, 125, 125), (125, -125, 125), (-125, -125, 125), (-125, 125, 125),
          (125, 125, -125), (125, -125, -125), (-125, -125, -125), (-125, 125, -125)]
FACES = [(1, 2, 3, 0, 0), (7, 6, 5, 4, 0), (0, 4, 5, 1, 1), (1, 5, 6, 2, 2), (2, 6, 7, 3, 1), (3, 7, 4, 0, 2)]
TXT = [(64, 4), (190, 4), (190, 60), (64, 60)]

class State: pass
st = State()

def swappage():
    st.page = (st.page + 1) % 6
    st.vmem = [0x0000, 0x5500, 0xAA00][st.page % 3]

def calculate():
    call('getspl', position=(4 * 256 + st.frames * 4) & 0xFFFF)
    for n in ('kx', 'ky', 'kz', 'ls_kx', 'ls_ky'):
        setvar(n, getvar(n) & 1023)
    kx, ky, kz = getvar('kx'), getvar('ky'), getvar('kz')
    lkx, lky = getvar('ls_kx'), getvar('ls_ky')
    st.ls_y = kosinit(lkx) >> 8
    st.ls_x = s16((sinit(lkx) >> 8) * (sinit(lky) >> 8)) >> 7
    st.ls_z = s16((sinit(lkx) >> 8) * (kosinit(lky) >> 8)) >> 7
    SX, SY, SZ, CX, CY, CZ = sinit(kx), sinit(ky), sinit(kz), kosinit(kx), kosinit(ky), kosinit(kz)
    # count_const: note "a>>15+7" in C means a>>22
    m = [s16(s32(CY * CZ) >> 22), s16(s32(CY * SZ) >> 22), s16(s32(-SY) >> 7),
         s16(s32(s32(s32(SX * CZ + 16384) >> 15) * SY - CX * SZ) >> 22),
         s16(s32(s32(s32(SX * SY + 16384) >> 15) * SZ + CX * CZ) >> 22),
         s16(s32(CY * SX) >> 22),
         s16(s32(s32(s32(CX * CZ + 16384) >> 15) * SY + SX * SZ) >> 22),
         s16(s32(s32(s32(CX * SY + 16384) >> 15) * SZ - SX * CZ) >> 22),
         s16(s32(CY * CX) >> 22)]
    tx, ty, dis = getvar('tx'), getvar('ty'), getvar('dis')
    st.pts = []
    for x, y, z in POINTS:
        def row(a, b, c, add):
            return s16((s16((s16(x * a) >> 1) + (s16(y * b) >> 1) + (s16(z * c) >> 1)) >> 7) + add)
        xx, yy, zz = row(m[0], m[1], m[2], tx), row(m[3], m[4], m[5], ty), row(m[6], m[7], m[8], dis)
        st.pts.append((xx, yy, zz, s16(cdiv(xx * 256, zz) + 320), s16(cdiv(yy * 142, zz) + 66)))
    # sort_faces: really "which faces point at the viewer", plus the lighting
    st.todraw = []
    p = 0
    for a, (p1, p2, p3, p4, colour) in enumerate(FACES):
        x, y, z = st.pts[p1][:3]
        ax, ay, az = s16(st.pts[p2][0] - x), s16(st.pts[p2][1] - y), s16(st.pts[p2][2] - z)
        bx, by, bz = s16(st.pts[p3][0] - x), s16(st.pts[p3][1] - y), s16(st.pts[p3][2] - z)
        nx, ny, nz = s32(ay * bz - az * by), s32(az * bx - ax * bz), s32(ax * by - ay * bx)
        if s32(-x * nx - y * ny - z * nz) > 0: continue
        light = s16(cdiv(s32(st.ls_x * nx + st.ls_y * ny + st.ls_z * nz), 250000) + 32)
        if st.lls[p] != light:
            call('shadepal', fpal=(DATA << 16) | (FPAL + colour * 192), ppal=(DATA << 16) | (PAL + colour * 192),
                 shd=light & 0xFFFF)
            st.lls[p] = light
        st.todraw.append(a)
        p += 1

def setlong(name, v): setvar(name, v & 0xFFFFFFFF)

def do_poly(pnts, colour, dd):
    dd = (dd + 1) & 63
    n = 0
    for a in range(1, 4):
        if pnts[a][1] < pnts[n][1]: n = a
    s1 = s2 = n
    d1, d2 = (s1 + 1) & 3, (s2 - 1) & 3
    def edge(which, s, d):
        dx, dy = s16(pnts[d][0] - pnts[s][0]), s16(pnts[d][1] - pnts[s][1])
        if dy == 0: dy = 1
        setlong('ax' + which, cdiv(65536 * dx, dy))
        setlong('xx' + which, (pnts[s][0] << 16) + 0x8000)
        setlong('txx' + which, (TXT[s][0] << 16) + 0x8000)
        setlong('txy' + which, (TXT[s][1] << 16) + 0x8000)
        setlong('tax' + which, cdiv(65536 * (TXT[d][0] - TXT[s][0]), dy))
        setlong('tay' + which, cdiv(65536 * (TXT[d][1] - TXT[s][1]), dy))
    edge('1', s1, d1)
    edge('2', s2, d2)
    yy = pnts[s1][1]
    setvar('yy', yy & 0xFFFF)
    setvar('from', KUVA[colour] << 16)
    setvar('to', (VIDEO << 16) | ((st.vmem + yy * 160) & 0xFFFF))
    setvar('dseg', DIST + dd * 16)
    setvar('ctau', (DATA << 16) | ((CLRTAU + st.clrptr * 1024 + yy * 4) & 0xFFFF))
    n = 0
    while n < 4:
        m = min(pnts[d1][1], pnts[d2][1])
        call('do_block', ycount=(m - yy) & 0xFFFF)
        yy = m
        setvar('yy', yy & 0xFFFF)
        if pnts[d1][1] == pnts[d2][1]:
            s1 = d1; d1 = (s1 + 1) & 3
            s2 = d2; d2 = (s2 - 1) & 3; n += 2
            edge('1', s1, d1); edge('2', s2, d2)
        elif pnts[d1][1] < pnts[d2][1]:
            s1 = d1; d1 = (s1 + 1) & 3; n += 1
            edge('1', s1, d1)
        else:
            s2 = d2; d2 = (s2 - 1) & 3; n += 1
            edge('2', s2, d2)

def draw():
    for a in st.todraw:
        p1, p2, p3, p4, colour = FACES[a]
        off = (st.page & 1) * 2
        do_poly([(s16(st.pts[i][3] + off), st.pts[i][4]) for i in (p1, p2, p3, p4)], colour, st.frames & 63)

def clear():
    otau = CLRTAU + ((st.clrptr - 3) & 7) * 1024
    ntau = CLRTAU + st.clrptr * 1024
    st.clrptr = (st.clrptr + 1) & 7
    call('do_clear', vmem=(VIDEO << 16) | st.vmem, otau=(DATA << 16) | otau, ntau=(DATA << 16) | ntau)

def frame(step):
    """One trip round VECT.C's main loop, for app step `step`."""
    swappage()
    st.frames = step - LEAD
    calculate()
    draw()
    clear()

def screen():
    """What the VGA shows of the page just drawn: 320x134 colour numbers. The view starts 160 pixels
    into the 640-wide page, and is panned 2 pixels on the pages that were drawn 2 pixels to the right."""
    pan = (st.page & 1) * 2
    out = bytearray(320 * 134)
    for y in range(134):
        base = st.vmem + 40 + y * 160
        for x in range(320):
            v = x + pan
            out[y * 320 + x] = planes[v & 3][(base + (v >> 2)) & 0xFFFF]
    return out

def palette():
    return bytes(M[(DATA << 4) + FPAL:(DATA << 4) + FPAL + 768])

def write_png(name, pixels, pal):
    rows = b''
    for y in range(134):
        line = b''.join(bytes(min(255, c * 255 // 63) for c in pal[p * 3:p * 3 + 3]) for p in pixels[y * 320:(y + 1) * 320])
        rows += (b'\0' + line) * 3
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    open(name, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 320, 402, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))

def setup(page):
    x86interp.SRC = SRC
    for p in planes: p[:] = bytes(65536)
    assemble('PLZA.ASM', PLZA)
    assemble('SPLINE.ASM', SPLINE)
    for seg, off, name in fixups:
        wr(seg, off, 2, code_labels[name])
    initvect()
    st.page, st.vmem, st.clrptr, st.frames = page - 1, 0, 0, 0
    st.lls = [0] * 6

def emit_tables():
    coef = read_table('SPLINE.INC', 'dw')
    assert len(coef) == 1024 and all(coef[i] == coef[1024 - i] for i in range(1, 1024))
    assert SINIT[1024:1280] == SINIT[0:256]
    def block(values):
        return '\n'.join('        ' + ', '.join(str(v) for v in values[i:i + 16]) + ',' for i in range(0, len(values), 16))
    print('''// Made by tools/plasmacube_reference.py --tables from the original PLZPART/SINIT.INC and SPLINE.INC.
// Neither table follows a formula that reproduces it exactly (see docs/scenes/plasma-cube.md), so the
// original numbers are kept here. The self-test checks them by checksum.

enum PlasmaCubeTables {
    /// SINIT.INC: one sine wave in 1024 entries, about 32767 tall (the file repeats the first quarter
    /// so a cosine can be read 256 entries on; wrapping the index does the same).
    static let sine: [Int16] = [
%s
    ]

    /// SPLINE.INC: the weights that blend four neighbouring path points into one position. Entry t
    /// weights the newest point, t+256 and t+512 the middle two, t+768 the oldest; 32768 means 1.
    static let blend: [Int16] = [
%s
    ]
}''' % (block(SINIT[:1024]), block(coef)))

if __name__ == '__main__':
    args = sys.argv[1:]
    page, png, want_range = 1, False, False
    while args and args[0].startswith('--'):
        a = args.pop(0)
        if a == '--src': SRC = args.pop(0)
        elif a == '--page': page = int(args.pop(0))
        elif a == '--png': png = True
        elif a == '--range': want_range = True
        elif a == '--tables': emit_tables(); sys.exit(0)
    steps = sorted(int(a) for a in args)
    setup(page)
    last = max(steps) if steps else 2047
    lo = [10 ** 9] * 3; hi = [-10 ** 9] * 3; first_lit = None; last_lit = None
    for step in range(0, last + 1):
        frame(step)
        if want_range:
            for p in st.pts:
                for i, v in enumerate((p[3], p[4], p[2])):
                    lo[i] = min(lo[i], v); hi[i] = max(hi[i], v)
            pal = palette(); scr = screen()
            if any(pal[c * 3] | pal[c * 3 + 1] | pal[c * 3 + 2] for c in set(scr)):
                if first_lit is None: first_lit = step
                last_lit = step
        if step in steps:
            scr, pal = screen(), palette()
            print('step %d page %d: screen %d palette %d faces %s light %s' % (
                step, st.page, zlib.crc32(bytes(scr)), zlib.crc32(pal), st.todraw, st.lls[:len(st.todraw)]))
            if png: write_png('reference%04d_p%d.png' % (step, page), scr, pal)
    if want_range:
        print('x %d..%d  y %d..%d  z %d..%d  first lit step %s  last lit step %s' % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], first_lit, last_lit))
