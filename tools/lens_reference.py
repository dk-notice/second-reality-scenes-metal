#!/usr/bin/env python3
"""Reference for the Lens (parts 1 and 2 of the lens part, LENS/MAIN.C + LENS/ASM.ASM, Psi).

What it does:
  1. Reruns LENS/CALC.C (the program that made the lens's tables) with Microsoft C's rand() and
     checks its output against the tables the demo really used, LENS.EX1 ... LENS.EX4. Tables 1-3
     come out byte for byte; table 4 does not (it was made from an older lens shape; see the docs).
  2. Works out the lens's bounce path from MAIN.C's SAVEPATH formulas and checks all 715 positions
     against LENS.EXP (pathdata1).
  3. Replays the part on a 64 KB screen, using the ORIGINAL table files (the app calculates tables
     1-3 itself, so this is an independent check of that too):
       - part1: the picture uncovered by two sweeps per row (16-bit int arithmetic, as MAIN.C's ints),
       - part2: `drawlens` with `dorow` / `dorow2` / `dorow3` as ASM.ASM does them (16-bit addresses),
         and the palette fade of colours 64-255.
  4. Prints CRC-32 checksums of the 1993 picture (red, green, blue bytes, 0...255 = round(v*255/63))
     at the standalone scene's steps the app's self-test checks.

The standalone scene's timeline (the app's `LensModel`): 35 black steps, the 300 steps of part1, the
720 steps of part2, 35 steps holding the last picture, then it starts again (1090 steps).

Usage: tools/lens_reference.py [path to ../secondreality]
       tools/lens_reference.py --png <step> <file.png> [path]     (one 1993 picture, 320x200)
Development tool only; the app does not use it.
"""
import math, os, struct, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'secondreality')
if not os.path.isdir(SRC):
    SRC = os.path.join(HERE, '..', '..', '..', '..', '..', 'secondreality')   # from inside a worktree
BLACK, REVEAL, LENS, HOLD = 35, 300, 720, 35
STEPS = [0, 34, 35, 36, 40, 60, 100, 114, 115, 200, 334, 335, 340, 366, 367, 400, 430, 500, 600, 700, 800,
         900, 975, 1000, 1049, 1054, 1055, 1089]


def cdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def read(name):
    return open(os.path.join(SRC, 'LENS', name), 'rb').read()


# ---------------------------------------------------------------------------------------------- CALC.C
def calc_tables():
    seed = [1]
    def rand():
        seed[0] = (seed[0] * 214013 + 2531011) & 0xFFFFFFFF
        return (seed[0] >> 16) & 0x7FFF
    shape = read('LENS.U')
    cx, cy, ymax, xmax = 76, 58, 120, 150
    full = 59 * 59 + 50 * 50
    def lenscalc(x, y):
        yy = cdiv(y * 9, 8)
        now = full - float(x * x + yy * yy)
        if now < 1.0: now = 1.0
        new = 250.0 / math.pow(now, 0.69)
        fx = (rand() - 16384) / 30000.0
        fy = (rand() - 16384) / 30000.0
        return int((x + fx) * new), int((y + fy) * new)
    tables = []
    for col in range(1, 5):
        rd, rowbeg, rowcnt = [], [0] * ymax, [0] * ymax
        for y in range(ymax):
            z = -1
            rowbeg[y] = len(rd)
            for x in range(xmax):
                v = shape[x + y * 320]
                if col == 1:
                    if v and v != 4:
                        if z == -1: rd.append(x); z = x + y * 320
                        x2, y2 = lenscalc(x - cx, y - cy)
                        rd.append((cx + x2) + (cy + y2) * 320 - z)
                elif col == 4:
                    if v == 4:
                        if z == -1: rd.append(0); z = x + y * 320
                        rd.append(x)
                elif v == col:
                    if z == -1: rd.append(x); z = x + y * 320
                    x2, y2 = lenscalc(x - cx, y - cy)
                    rd.append(x + y * 320 - z)
                    rd.append((cx + x2) + (cy + y2) * 320 - z)
            c = max(len(rd) - rowbeg[y] - 1, 0)
            rowcnt[y] = c if col in (1, 4) else c // 2
        out = b''.join(struct.pack('<HH', (rowbeg[a] * 2 + ymax * 4) & 0xFFFF, rowcnt[a]) for a in range(ymax))
        out += b''.join(struct.pack('<H', v & 0xFFFF) for v in rd)
        tables.append(out)
    return tables


# ---------------------------------------------------------------------------------------------- path
def lens_path():
    x, y, xa, ya, first = 65 * 64, -50 * 64, 64, 64, True
    out = []
    for frame in range(715):
        out.append((cdiv(x, 64), cdiv(y, 64)))
        x += xa; y += ya
        if x > 256 * 64 or x < 60 * 64: xa = -xa
        if y > 150 * 64 and frame < 600:
            y -= ya
            if first: ya = cdiv(-ya * 2, 3); first = False
            else: ya = cdiv(-ya * 9, 10)
        ya += 2
    return out


def path_from_file():
    d = read('LENS.EXP')
    a = struct.unpack('<h', d[2:4])[0]
    ints = struct.unpack('<%dh' % a, d[4:4 + 2 * a])
    return [(ints[2 * i], ints[2 * i + 1]) for i in range(a // 2)]


# ---------------------------------------------------------------------------------------------- replay
class Lens:
    def __init__(self):
        exb = read('LENS.EXB')
        self.palette = list(exb[16:16 + 768])
        back = bytearray(65536)
        back[:64000] = exb[784:784 + 64000]
        back[64000:] = back[64000 - 1536:64000]          # memcpy(back+64000, back+64000-1536, 1536)
        self.back = back
        ex0 = read('LENS.EX0')
        self.lenswid, self.lenshig = struct.unpack('<hh', ex0[:4])
        tints = [tuple(ex0[4 + 3 * i:7 + 3 * i]) for i in range(3)]
        pal = self.palette
        for i in range(1, 4):
            for a in range(0, 192, 3):
                for ch in range(3):
                    pal[a + i * 192 + ch] = min(tints[i - 1][ch] + pal[a + ch], 63)
        self.full = list(pal)
        # fade2: 32 copies of colours 64-255
        self.fade2 = [[pal[y] - cdiv(pal[y % 192] * (31 - x), 31) for y in range(192, 768)] for x in range(32)]
        self.tables = [struct.unpack('<%dH' % (len(t) // 2), t) for t in (read('LENS.EX%d' % n) for n in (1, 2, 3, 4))]
        self.path = path_from_file()

    def reset(self):
        self.screen = bytearray(65536)
        self.pal = list(self.full)
        self.f1 = [170 * 64 + (100 - b) * 50 for b in range(200)]
        self.f2 = list(self.f1)
        self.f1a = [(19 + b // 5 + 4) & ~7 for b in range(200)]
        self.f2a = [(-(19 + (199 - b) // 5 + 4)) & ~7 for b in range(200)]

    def sweep_frame(self):
        scr, back = self.screen, self.back
        for _ in range(6):
            for y in range(200):
                for f in (self.f1, self.f2):
                    a = (y * 320 + (s16(f[y]) >> 6)) & 0xFFFF
                    scr[a] = back[a]
                self.f1[y] = s16(self.f1[y] + self.f1a[y])
                self.f2[y] = s16(self.f2[y] + self.f2a[y])

    def dorow(self, t, u, y, orc):
        si, cnt = t[2 * y] // 2, t[2 * y + 1]
        if cnt < 4: return                       # cmp cx,4 / jge: shorter rows are not drawn
        di = u + t[si]
        for k in range(cnt):
            self.screen[(di + k) & 0xFFFF] = self.back[(di + t[si + 1 + k]) & 0xFFFF] | orc

    def dorow2(self, t, u, y, orc):
        si, cnt = t[2 * y] // 2, t[2 * y + 1]
        if cnt == 0: return                      # jcxz: nothing read for an empty row
        di = u + t[si]
        for p in range(cnt):
            self.screen[(di + t[si + 1 + 2 * p]) & 0xFFFF] = self.back[(di + t[si + 2 + 2 * p]) & 0xFFFF] | orc

    def dorow3(self, t, u, y):
        si, cnt = t[2 * y] // 2, t[2 * y + 1]
        if cnt == 0: return
        di = u + t[si]
        for k in range(cnt):
            a = (di + t[si + 1 + k]) & 0xFFFF
            self.screen[a] = self.back[a]

    def drawlens(self, x0, y0):
        lensxs, lensys = self.lenswid // 2, self.lenshig // 2
        u1 = (x0 - lensxs) + (y0 - lensys) * 320
        u2 = (x0 - lensxs) + (y0 + lensys - 1) * 320
        ys, ye = self.lenshig // 2, self.lenshig - 1
        t1, t2, t3, t4 = self.tables
        for y in range(ys):
            for u, row in ((u1, y), (u2, ye - y)):
                if 0 <= u <= 64000:
                    self.dorow(t1, u, row, 0x40)
                    self.dorow2(t2, u, row, 0x80)
                    self.dorow2(t3, u, row, 0xC0)
                    self.dorow3(t4, u, row)
            u1 += 320
            u2 -= 320

    def step(self, s):
        """Carries out standalone step s (call for s = 0, 1, 2, ... in order)."""
        if s == 0: self.reset()
        if BLACK <= s < BLACK + REVEAL:
            if s - BLACK < 80: self.sweep_frame()
        elif BLACK + REVEAL <= s < BLACK + REVEAL + LENS:
            k = s - BLACK - REVEAL
            if k < 96:
                a = max(cdiv(k - 32, 2), 0)
                self.pal[192:768] = self.fade2[a]
            if k < 715:
                self.drawlens(*self.path[k])

    def rgb(self):
        p = self.pal
        out = bytearray()
        for c in self.screen[:64000]:
            out += bytes(round(p[3 * c + i] * 255 / 63) for i in range(3))
        return out

    def residue(self):
        """Pixels showing lens colours (64-255) while no lens should be there."""
        return sum(1 for c in self.screen[:64000] if c >= 64)


def write_png(name, width, height, rgb):
    raw = b''.join(b'\0' + bytes(rgb[y * width * 3:(y + 1) * width * 3]) for y in range(height))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
    open(name, 'wb').write(png)


def main():
    global SRC
    args = sys.argv[1:]
    png = None
    if args[:1] == ['--png']:
        png = (int(args[1]), args[2]); args = args[3:]
    if args: SRC = args[0]
    lens = Lens()
    if png:
        for s in range(png[0] + 1): lens.step(s)
        write_png(png[1], 320, 200, lens.rgb())
        return
    calc = calc_tables()
    for n in range(4):
        real = read('LENS.EX%d' % (n + 1))
        same = calc[n] == real
        print(f'table {n + 1}: CALC.C gives {len(calc[n])} bytes, LENS.EX{n + 1} {len(real)} bytes: '
              + ('identical' if same else f'{sum(1 for a, b in zip(calc[n], real) if a != b)} bytes differ')
              + f'; crc {zlib.crc32(real)}')
    path = lens_path()
    played = path_from_file()
    print(f'path: {len(played)} positions in LENS.EXP, {sum(1 for a, b in zip(path, played) if a == b)} equal to the formulas')
    t1 = lens.tables[0]
    print('longest row of table 1:', max(t1[2 * y + 1] for y in range(120)), 'pixels (dorow unrolls 64 words = 128)')
    sums, revealed, res = [], None, []
    total = BLACK + REVEAL + LENS + HOLD
    for s in range(max(STEPS) + 1):
        lens.step(s)
        if s == BLACK + REVEAL - 1:
            revealed = sum(1 for i in range(64000) if lens.screen[i] == lens.back[i])
        if s >= BLACK + REVEAL + 700 and s < BLACK + REVEAL + LENS:
            res.append(lens.residue())
        if s in STEPS:
            sums.append(zlib.crc32(lens.rgb()))
    print(f'after part1: {revealed} of 64000 pixels equal the picture')
    print(f'lens colours left on screen after the lens has gone (steps 700-719 of part2): {max(res)} at most, {res[-1]} at the end')
    print('steps', STEPS)
    print('crc32', sums)


if __name__ == '__main__':
    main()
