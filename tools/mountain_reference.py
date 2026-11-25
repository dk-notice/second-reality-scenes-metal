#!/usr/bin/env python3
"""Reference for the Mountain Scroller (part 9: FOREST/READ2.PAS + ROUTINES.ASM, Trug).

The part has no font and no text string: the text is ONE PICTURE (O2.SCI, 640 wide, rows 0...30 used,
values 0...7: "ANOTHER WAY TO SCROLL"). A window of it, 237 columns by 31 rows, is laid over the hills
of the background (HILLBACK.CLX) through three position tables (POS1-3.DAT): for each of the window's
237 x 31 cells a count and that many screen addresses. `putrouts` writes, at each address,
background + cell (cell = text value + 128 where the text is inked, else 0; a byte, so it wraps).
One table is drawn per refresh (1, 2, 3, 1, ...); after table 3 the window moves one column.

What this tool does:
  1. Checks the three tables' structure (they cannot be recalculated: READMASK.PAS made them from
     ray-traced mask pictures, o:mask1-4.mtv, that are not in the source release): each parses to
     exactly its length; they share no pixel; together they cover all but 2 pixels of GREEN.CLX's
     mask (the surviving one of READMASK's inputs: the text row of every pixel); every address's row
     agrees with GREEN.CLX; addresses rise within a cell (READMASK scans the screen upwards).
  2. Shows which way the three tables order: a pixel in table k (0...2) at window column c sits at
     text coordinate c + (2 - k)/3 (the Modern look's smooth map is fitted through these).
  3. Reports palette facts the scene relies on.
  4. Replays the part on the 1993 screen and prints CRC-32 checksums of the picture (320x200; red,
     green, blue bytes, round(v*255/63)) at the standalone scene's steps the app's self-test checks.

The standalone scene's timeline (the app's `MountainScrollerModel`). Step pairing: what the program
set up before its n-th wait for the screen shows on step n - 1 (counting from 0).
  step 0            black
  steps 1...64      the leaves fade in (every colour except 0...31 and 128...159, the hills and the
                    text on them): step s shows level s - 1 (each channel min(target, level))
  step 65 + j       scroll draw j (table j mod 3). The hills and the text fade in during draws
                    0...126: draw j shows level (j - 1) div 2 for colours 0...176 (j = 0: still black);
                    it stops at 62 (the loop never sets the full palette).
  FADE_DRAW         the draw on which the fade-out starts (in the demo: "music plus" = -11; on its
                    own: the same draw as in the demo). Fade i (0...64) shows on step 65 + FADE_DRAW + i:
                    each channel max(target - i, 0). Then the scene starts again.

Usage: tools/mountain_reference.py [path to ../secondreality]
       tools/mountain_reference.py --png <step> <file.png> [path]     (one 1993 picture, 320x200)
Development tool only; the app does not use it.
"""
import os, struct, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'secondreality')
if not os.path.isdir(SRC):
    SRC = os.path.join(HERE, '..', '..', '..', '..', '..', 'secondreality')   # from inside a worktree

COLS, ROWS = 237, 31
FADE_IN = 64            # waits of the first fade
HILL_FADE_DRAWS = 127   # draws of the second fade loop
FADE_DRAW = 1906        # standalone: the draw that shows fade-out level 0 (as in the demo; see the app's check)
FADE_OUT = 65
LENGTH = 1 + FADE_IN + FADE_DRAW + FADE_OUT
STEPS = [0, 1, 2, 33, 64, 65, 66, 67, 68, 70, 100, 150, 191, 192, 193, 400, 665, 1000, 1500, 1582, 1583, 1700, 1900,
         1970, 1971, 1972, 1996, 2034, 2035]


def load(src):
    f = lambda n: open(os.path.join(src, 'FOREST', n), 'rb').read()
    hb = f('HILLBACK.CLX')
    assert hb[:4] == b'RIX3' and struct.unpack_from('<HH', hb, 4) == (320, 200)
    o2 = f('O2.SCI')
    assert o2[:4] == b'RIX3' and struct.unpack_from('<HH', o2, 4) == (640, 32)
    text = bytearray(640 * ROWS)
    for r in range(ROWS):
        text[r * 640:(r + 1) * 640] = o2[778 + r * 640:778 + (r + 1) * 640]
    tables = []
    for n in (1, 2, 3):
        d = f(f'POS{n}.DAT'); p = 0; cells = []
        for _ in range(COLS * ROWS):
            count = struct.unpack_from('<H', d, p)[0]; p += 2
            cells.append(struct.unpack_from(f'<{count}H', d, p)); p += 2 * count
        assert p == len(d), f'POS{n}.DAT does not parse to its length'
        tables.append(cells)
    green = f('GREEN.CLX')[778:778 + 64000]
    return {'pal': hb[10:778], 'bg': hb[778:778 + 64000], 'text': bytes(text), 'tables': tables, 'green': green,
            'raw': {n: f(n) for n in ('POS1.DAT', 'POS2.DAT', 'POS3.DAT', 'HILLBACK.CLX', 'O2.SCI')}}


class Part:
    """The part's state from scroll draw to scroll draw (READ2.PAS's `scr`)."""

    def __init__(self, d):
        self.d = d
        self.screen = bytearray(d['bg'])
        # fbuf: the text with 128 added where inked; font: the window, text columns 0...132 at 104...236.
        self.fbuf = bytes(v + 128 if v else 0 for v in d['text'])
        self.font = bytearray(COLS * ROWS)
        for r in range(ROWS):
            self.font[r * COLS + 104:r * COLS + COLS] = self.fbuf[r * 640:r * 640 + 133]
        self.scp, self.sss = 133, 0

    def draw(self):
        bg, screen, font = self.d['bg'], self.screen, self.font
        for i, cell in enumerate(self.d['tables'][self.sss]):
            v = font[i]
            for a in cell:
                screen[a] = (bg[a] + v) & 255
        if self.sss == 2:
            # move(font[1], font[0], 237*31): one byte past the window comes in at the end and is
            # overwritten by the new column at once.
            self.font[0:COLS * ROWS - 1] = self.font[1:COLS * ROWS]
            for r in range(ROWS):
                self.font[r * COLS + COLS - 1] = self.fbuf[r * 640 + self.scp]
            if self.scp < 639:
                self.scp += 1
            self.sss = 0
        else:
            self.sss += 1


def is_hill(c):
    return c < 32 or 128 <= c < 160


def palette(d, step):
    """The 256 colours (VGA levels) showing on standalone step `step`."""
    pal = d['pal']
    out = bytearray(768)
    j = step - 1 - FADE_IN          # scroll draw showing (negative: before the scroll)
    for c in range(256):
        for k in range(3):
            t = pal[c * 3 + k]
            if step == 0:
                v = 0
            elif j >= FADE_DRAW:
                v = max(t - (j - FADE_DRAW), 0)
            elif is_hill(c):
                v = 0 if j <= 0 else min(t, min((j - 1) // 2, 62))
            elif j < 0:
                v = min(t, step - 1)
            elif c <= 176 and j >= 1:
                v = min(t, 63)      # set again with the hills, already at its target
            else:
                v = t
            out[c * 3 + k] = v
    return out


def frames(d, steps):
    """step -> (screen, palette) for the wanted standalone steps."""
    part, drawn, out = Part(d), 0, {}
    for step in range(max(steps) + 1):
        j = step - 1 - FADE_IN
        while drawn <= j:
            part.draw(); drawn += 1
        if step in steps:
            out[step] = (bytes(part.screen), palette(d, step))
    return out


def rgb(screen, pal):
    v8 = [round(v * 255 / 63) for v in range(64)]
    table = [bytes(v8[pal[c * 3 + k]] for k in range(3)) for c in range(256)]
    return b''.join(table[p] for p in screen)


def write_png(path, w, h, data):
    def chunk(t, body): return struct.pack('>I', len(body)) + t + body + struct.pack('>I', zlib.crc32(t + body))
    raw = b''.join(b'\0' + data[y * w * 3:(y + 1) * w * 3] for y in range(h))
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def facts(d):
    tables, green, bg, pal = d['tables'], d['green'], d['bg'], d['pal']
    for name, data in d['raw'].items():
        print(f'{name}: {len(data)} bytes, crc {zlib.crc32(data)}')
    sets = [set(a for cell in t for a in cell) for t in tables]
    counts = [sum(len(cell) for cell in t) for t in tables]
    union = sets[0] | sets[1] | sets[2]
    area = {a for a in range(64000) if green[a]}
    print(f'tables: {counts} addresses; shared between tables: {sum(counts) - len(union)}; '
          f'together {len(union)} pixels of GREEN.CLX\'s {len(area)} (missing {sorted(area - union)}, extra {len(union - area)})')
    wrong = sum(1 for t in tables for i, cell in enumerate(t) for a in cell if green[a] != i // COLS + 1)
    rising = all(list(cell) == sorted(cell) for t in tables for cell in t)
    print(f'rows that disagree with GREEN.CLX: {wrong}; addresses rise within every cell: {rising}')
    col, ph = {}, {}
    for k, t in enumerate(tables):
        for i, cell in enumerate(t):
            for a in cell:
                col[a], ph[a] = i % COLS, k
    for label, frac in (('c + (2 - k)/3', lambda k: (2 - k) / 3), ('c + k/3', lambda k: k / 3)):
        pairs = back = 0
        for a in union:
            b = a + 1
            if b % 320 and b in col and green[a] == green[b] and abs(col[a] - col[b]) <= 1:
                pairs += 1
                back += (col[b] + frac(ph[b])) < (col[a] + frac(ph[a]))
        print(f'text coordinate {label}: {pairs - back} of {pairs} neighbours along a row are in order')
    # Palette facts.
    hills = [a for a in union if bg[a] < 32]
    leaves = [a for a in union if bg[a] >= 32]
    print(f'text-area pixels on hill colours (0...31): {len(hills)}, highest {max(bg[a] for a in hills)}; '
          f'on other colours: {len(leaves)} ({min(bg[a] for a in leaves)}...{max(bg[a] for a in leaves)})')
    same = all(pal[(160 + i) * 3:(161 + i) * 3] == pal[(32 + i) * 3:(33 + i) * 3] for i in range(96))
    print(f'colours 160...255 are a copy of 32...127: {same}')
    changed = sum(1 for a in leaves for v in range(1, 8)
                  if pal[((bg[a] + 128 + v) & 255) * 3:((bg[a] + 128 + v) & 255) * 3 + 3] != pal[bg[a] * 3:bg[a] * 3 + 3])
    print(f'(leaf pixel, text value) pairs whose colour differs from the bare leaf: {changed} of {len(leaves) * 7}')
    text = d['text']
    print(f'text: values {sorted(set(text))}; last column inked rows '
          f'{[r for r in range(ROWS) if text[r * 640 + 639]]}')
    print(f'hill colours with a 63 (shown as 62 after the hill fade): '
          f'{[c for c in range(256) if is_hill(c) and 63 in pal[c * 3:c * 3 + 3]]}')


def main():
    args = sys.argv[1:]
    png = None
    if args[:1] == ['--png']:
        png = (int(args[1]), args[2]); args = args[3:]
    d = load(args[0] if args else SRC)
    if png:
        screen, pal = frames(d, [png[0]])[png[0]]
        write_png(png[1], 320, 200, rgb(screen, pal)); print('wrote', png[1])
        return
    facts(d)
    got = frames(d, STEPS)
    print(f'standalone length {LENGTH} steps (fade-out from draw {FADE_DRAW})')
    print('steps', STEPS)
    print('crc32', [zlib.crc32(rgb(*got[s])) for s in STEPS])


if __name__ == '__main__':
    main()
