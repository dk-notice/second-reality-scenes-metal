#!/usr/bin/env python3
"""Reference for the Jelly Logo (JPLOGO/JP.C + ASM.ASM + ZOOM.INC, Psi).

What it does:
  1. Reruns JPLOGO/DOL.C (the program that wrote ZOOM.INC, the 53 line-stretching routines) as a
     formula, and checks it against ZOOM.INC itself: every routine is RUN here, instruction by
     instruction, on a model of the VGA's four memory planes, and the pixels it writes are compared
     with the formula's for every width 0...318.
  2. Checks JPLOGO's own sine table (SIN1024.INC): unlike the other parts' copies it is clamped to
     -255...255 (sin x 256, rounded towards zero, then clamped).
  3. Works out JP.C's bounce (the top and bottom edges, 200 frames in 1/16 pixels, 16-bit C rules)
     and the 800-entry table it spreads them over (each value shows twice; see below).
  4. Replays the part on the 1993 screen: the slide-in (the screen's start row moving), then 700
     refreshes of `doit`, including its row cache (rows are only redrawn when their source row or
     width changes, and the cache is NOT cleared when a row is blanked, so some rows stay black).
  5. Prints CRC-32 checksums of the 1993 picture (320x400; red, green, blue bytes, round(v*255/63))
     at the standalone scene's steps the app's self-test checks, and how many row-refreshes the
     cache leaves black.

The standalone scene's timeline (the app's `JellyLogoModel`): 86 steps of slide-in (as the original's
86 waits), no wait (in the demo: until "music plus" >= 4, about 3 steps), 700 steps of jelly, 35 steps
holding the last picture, then it starts again (821 steps). Step pairing: what the program set up
before its n-th wait for the screen is what shows on step n - 1 (counting from 0); so jelly step j
shows the rows drawn after the j-th wait of `doit` (j = 0: the slide-in's picture).

Usage: tools/jelly_reference.py [path to ../secondreality]
       tools/jelly_reference.py --png <step> <file.png> [path]     (one 1993 picture, 320x400)
Development tool only; the app does not use it.
"""
import os, re, struct, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import artformats  # noqa: E402

SRC = os.path.join(HERE, '..', '..', 'secondreality')
if not os.path.isdir(SRC):
    SRC = os.path.join(HERE, '..', '..', '..', '..', '..', 'secondreality')   # from inside a worktree
SLIDE, WAIT, JELLY, HOLD = 86, 0, 700, 35
STEPS = [0, 1, 2, 3, 10, 40, 80, 84, 85, 86, 87, 90, 95, 105, 111, 115, 165, 225, 265, 365, 465, 470, 471, 565, 665, 785, 820]
BEG, END = 140, 244          # DOL.C: the narrowest and widest routines
BAND = ((160 - END // 2 - 1) & ~7, (160 + END // 2 + 8) & ~7)   # columns every routine writes: 32...287
BLACK, EMPTY = -1, -2


def cdiv(a, b):
    """C's integer division (rounds towards zero)."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def read(*names):
    return open(os.path.join(SRC, 'JPLOGO', *names), 'rb').read()


# ---------------------------------------------------------------- 1. ZOOM.INC

def dol_columns(width):
    """DOL.C's xt[] for a call with `width` (after linezoom's clamp): per screen column the source
    column (0...184), BLACK, or EMPTY (left alone)."""
    width = min(width, 318) & ~1
    xt = [EMPTY] * 320
    if width == 0:
        for x in range(BAND[0], BAND[1]):
            xt[x] = BLACK
        return xt
    y = min(max(width, BEG), END)
    le, ri = 160 - y // 2, 160 + y // 2
    c = ri - le + 1
    for x in range(BAND[0], BAND[1]):
        xt[x] = BLACK if x < le or x > ri else ((x - le) * 185 + c // 2) // c
    return xt


def run_zoom_inc():
    """Runs every routine of ZOOM.INC on four planes. Returns {width: xt as written}."""
    text = read('ZOOM.INC').decode('latin-1').splitlines()
    table = [m.group(1) for m in (re.match(r'dw OFFSET @(zoom\d+)', l.strip()) for l in text) if m]
    labels = {}
    code = []
    for line in text:
        line = line.strip()
        m = re.match(r'@(zoom\d+):', line)
        if m:
            labels[m.group(1)] = len(code)
        elif line and not line.startswith(('zoomt', 'dw')):
            code.append(line)
    results = {}
    for width in range(0, 320, 2):
        planes = [[None] * 80 for _ in range(4)]   # None = not written
        mask, ax = 0x0F, 0                          # linezoom: all planes on, ax = 0
        src = list(range(185))                      # source byte k holds k
        pc = labels[table[width // 2]]
        while True:
            ins = code[pc]; pc += 1
            if ins == 'ret':
                break
            m = re.match(r'mov es:\[di\+(\d+)\],(ax|al|ah)$', ins)
            if m:
                off, reg = int(m.group(1)), m.group(2)
                vals = {'ax': [ax & 255, ax >> 8], 'al': [ax & 255], 'ah': [ax >> 8]}[reg]
                for k, v in enumerate(vals):
                    for p in range(4):
                        if mask & (1 << p):
                            planes[p][off + k] = v
                continue
            m = re.match(r'mov (al|ah),ds:\[si\+(\d+)\]$', ins)
            if m:
                v = src[int(m.group(2))] + 1        # +1 so that 0 means black
                ax = (ax & 0xFF00) | v if m.group(1) == 'al' else (ax & 0xFF) | (v << 8)
                continue
            if ins == 'xor ax,ax': ax = 0; continue
            if ins == 'xor al,al': ax &= 0xFF00; continue
            if ins == 'xor ah,ah': ax &= 0xFF; continue
            m = re.match(r'mov al,(\d+)$', ins)
            if m and code[pc] == 'out dx,al':
                mask = int(m.group(1)); pc += 1
                continue
            raise ValueError('unknown instruction: ' + ins)
        xt = []
        for x in range(320):
            v = planes[x & 3][x >> 2]
            xt.append(EMPTY if v is None else BLACK if v == 0 else v - 1)
        results[width] = xt
    return results


# ---------------------------------------------------------------- 2, 3. sine table and bounce

def sine_table():
    t = read('SIN1024.INC').decode('latin-1')
    return [int(x) for x in re.findall(r'-?\d+', t.split('LABEL WORD')[1])]


def sine_formula():
    import math
    return [max(-255, min(255, int(256 * math.sin(i * math.pi / 512)))) for i in range(1024)]


def bounce():
    """JP.C main's loop: framey1/framey2 (200 frames, 1/16 pixels) and the 800-entry tables."""
    y1, y1a, y2, y2a, mika, halt, a = 0, 500, 399 * 16, 500, 1, 0, 0
    f1, f2 = [], []
    for frame in range(200):
        if not halt:
            y1 += y1a; y2 += y2a
            y2a += 16
            if y2 > 400 * 16:
                y2 -= y2a
                y2a = cdiv(-y2a * mika, 8)
                if mika < 4: mika += 3
            y1a += 16
            la = a
            a = (y2 - y1) - 400 * 16
            if (a & 0x8000) ^ (la & 0x8000):
                y1a = cdiv(y1a * 7, 8)
            y1a += cdiv(a, 8)
            y2a -= cdiv(a, 8)
        if frame > 90:
            if y2 >= 399 * 16:
                y2 = 400 * 16; halt = 1
            else:
                y2a = 8
            y1 = y2 - 400 * 16
        f1.append(y1); f2.append(y2)
    assert all(-32768 <= v < 32768 for v in f1 + f2)
    # framey1t[a] = (framey1[b]*d + framey1[b+1]*c)/3 with b = a/4, c = a&3, d = 3-c: c = 3 already
    # gives framey1[b+1], so every value shows twice. Only a <= 511 is used (b + 1 <= 128).
    t1 = [cdiv(f1[a // 4] * (3 - (a & 3)) + f1[a // 4 + 1] * (a & 3), 3) for a in range(512)]
    t2 = [cdiv(f2[a // 4] * (3 - (a & 3)) + f2[a // 4 + 1] * (a & 3), 3) for a in range(512)]
    return f1, f2, t1, t2


# ---------------------------------------------------------------- 4. the 1993 screen

class Jelly:
    def __init__(self):
        data = artformats.obk_data(read('_PIC.OBK'))
        pic = artformats.read_any(data)
        assert (pic.width, pic.height) == (320, 400)
        cols = struct.unpack_from('<H', data, 6)[0]
        pal = [tuple(data[16 + 3 * i:19 + 3 * i]) if i < cols else (0, 0, 0) for i in range(256)]
        pal[64] = (0, 0, 0)                                   # JP.C: colour 64 made black
        self.palette = pal
        self.rows = []
        for y in range(400):
            r = [p if p else 64 for p in pic.pixels[y * 320 + 70:y * 320 + 254]]   # 0 -> 64
            self.rows.append(r + [65])                          # row[y][184] = 65
        self.sin = sine_table()
        self.t1, self.t2 = bounce()[2:]
        self.xt = {w: dol_columns(w) for w in range(0, 320, 2)}
        self.reset()

    def reset(self):
        self.mem = bytearray(320 * 400)      # the picture's 400 rows; rows 400+ are always black
        self.scroll = 0
        self.lasty = [-1] * 400
        self.lasts = [-1] * 400
        self.y1 = self.y2 = 0
        self.left_black = 0                  # row-refreshes the cache leaves black

    def linezoom(self, y, row, width):
        xt = self.xt[min(width, 318) & ~1]
        for x in range(320):
            v = xt[x]
            if v == EMPTY: continue
            self.mem[y * 320 + x] = 0 if v == BLACK else row[v]

    def doit_frame(self, frame):
        if frame <= 511:
            self.y1, self.y2 = cdiv(self.t1[frame], 16), cdiv(self.t2[frame], 16)
        y1, y2 = self.y1, self.y2
        xsc = cdiv(400 - (y2 - y1), 8)
        for y in range(400):
            if y < y1 or y >= y2:
                self.linezoom(y, None, 0)
                self.blank[y] = True
            else:
                b = (y - y1) * 400 // (y2 - y1)
                a = 184 + cdiv(self.sin[b * 32 // 25] * xsc + 32, 64)
                a &= ~1
                if self.lasty[y] != b or self.lasts[y] != a:
                    self.linezoom(y, self.rows[b], a)
                    self.lasty[y] = b; self.lasts[y] = a
                    self.blank[y] = False
                elif self.blank[y]:
                    self.left_black += 1

    def run(self, last_step):
        """The screen at each step 0...last_step (standalone timeline). Yields (step, rgb)."""
        self.reset()
        self.blank = [True] * 400
        ys, y, a = [], 400 * 64, 64
        while y > 0:
            y -= a; a += 6
            y = max(y, 0)
            ys.append(y)
        assert len(ys) == SLIDE - 3
        for step in range(last_step + 1):
            s = step % (SLIDE + WAIT + JELLY + HOLD)
            if s == 0:
                self.reset(); self.blank = [True] * 400
            if s == 1:
                self.scroll = 400
            elif s == 2:
                for r in range(400):                       # drawn after the second wait
                    self.linezoom(r, self.rows[r], 184)
                self.scroll = ys[0] // 64
            elif 2 < s < SLIDE - 1:
                self.scroll = ys[s - 2] // 64
            elif s == SLIDE - 1:
                self.scroll = 0
            j = s - SLIDE - WAIT
            if 1 <= j < JELLY:
                self.doit_frame(j)
            yield step, self.rgb()

    def rgb(self):
        out = bytearray()
        level = [bytes(round(v * 255 / 63) for v in c) for c in self.palette]
        black = level[0]
        for r in range(400):
            m = r + self.scroll
            if m >= 400:
                out += black * 320
            else:
                for x in range(320):
                    out += level[self.mem[m * 320 + x]]
        return out


def write_png(name, width, height, rgb):
    raw = b''.join(b'\0' + bytes(rgb[y * width * 3:(y + 1) * width * 3]) for y in range(height))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
    with open(name, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def main():
    global SRC
    args = sys.argv[1:]
    if args[:1] == ['--png']:
        step, name = int(args[1]), args[2]
        if len(args) > 3: SRC = args[3]
        for s, rgb in Jelly().run(step):
            if s == step: write_png(name, 320, 400, rgb)
        print('wrote', name)
        return
    if args: SRC = args[0]

    ran = run_zoom_inc()
    bad = [w for w in range(0, 320, 2) if ran[w] != dol_columns(w)]
    print(f'ZOOM.INC: {len(ran)} widths run on four planes; DOL.C formula '
          + ('matches every one' if not bad else f'differs for widths {bad[:10]}'))
    cols = b''.join(struct.pack('<h', v) for w in range(0, 320, 2) for v in dol_columns(w))
    print(f'column tables (widths 0...318, 320 int16 each; -1 black, -2 untouched): crc {zlib.crc32(cols)}')
    table, formula = sine_table(), sine_formula()
    print('SIN1024.INC (JPLOGO): ' + ('= sin x 256 rounded towards zero, clamped to -255...255'
                                      if table == formula else f'{sum(a != b for a, b in zip(table, formula))} entries differ')
          + f'; crc of the 1024 words {zlib.crc32(b"".join(struct.pack("<h", v) for v in table))}')
    f1, f2, t1, t2 = bounce()
    still = max(f for f in range(1, 512) if (cdiv(t1[f], 16), cdiv(t2[f], 16)) != (0, 400)) + 1
    print(f'bounce: crc of framey1+framey2 (400 words) {zlib.crc32(b"".join(struct.pack("<h", v) for v in f1 + f2))}; '
          f'flat from doit frame {still}')

    jelly = Jelly()
    sums, steps = [], set(STEPS)
    for s, rgb in jelly.run(max(STEPS)):
        if s in steps: sums.append(zlib.crc32(rgb))
    print('row-refreshes left black by the row cache:', jelly.left_black)
    print('steps', STEPS)
    print('crc32', sums)


if __name__ == '__main__':
    main()
