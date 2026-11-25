#!/usr/bin/env python3
"""Reference for the Water Scroller (part 13: WATER/DEMO.PAS + ROUTINES.ASM, Trug).

The part scrolls no text: MIEKKA.SCI ("miekka" = sword) is ONE PICTURE of a sword, 400 columns by 34
rows of colour numbers (0 = nothing). A window of it, 158 columns by 34 rows, is laid over the water of
the background (BKG.CLX) and its reflections in the chrome balls through three position tables
(WAT1-3.DAT): for each of the window's 158 x 34 cells a count and that many screen addresses.
`putrouts1` writes, at each address, the cell's colour number, or the background's again where the
cell is empty. One table is drawn per refresh (1, 2, 3, 1, ...); after table 3 the window moves one
column. The same technique as the mountain scroller (tools/mountain_reference.py), by the same coder.

What this tool does:
  1. Checks the three tables' structure (they cannot be recalculated: DATGEN.PAS made them from four
     ray-traced mask pictures, o:k1/k2/k3/k5.mtv, that are not in the source release; MASK.MTV, which
     is, turns out to be a different, earlier render): each parses to exactly its length; they share
     no pixel; how they compare with GREEN.CLX (each pixel's sword row) and with MASK.MTV.
  2. Shows which way the three tables order: a pixel in table k (0...2) at window column c sits at
     sword coordinate c + (2 - k)/3, as in the mountain scroller.
  3. Reports palette and picture facts the scene relies on.
  4. Replays the part on the 1993 screen and prints CRC-32 checksums of the picture (320x200; red,
     green, blue bytes, round(v*255/63)) at the standalone scene's steps the app's self-test checks.

The standalone scene's timeline (the app's `WaterScrollerModel`), paired with the screen the same way
as the mountain scroller's:
  step 0                 black
  steps 1...127          the fade-in: step s shows what DEMO.PAS's fade loop left after its pass
                         y = s - 1. A new level is set on every odd y. Each pass raises `pal[x*3+pf]`
                         for pf = 0...3, one too many, so every colour's RED rises twice a pass.
  steps 128...646        the finished picture, still (HOLD steps: in the demo the part waits here for
                         the music's next section, row 16)
  step 647 + k           scroll draw k (table k mod 3)
  FADE_DRAW              the draw on which the fade-out starts (in the demo: "music plus" = -11).
                         65 draws: the palette as it stands is set, then lowered (red twice a pass).
                         Then the scene starts again.

Usage: tools/water_reference.py [path to ../secondreality]
       tools/water_reference.py --png <step> <file.png> [path]     (one 1993 picture, 320x200)
Development tool only; the app does not use it.
"""
import os, struct, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'secondreality')
if not os.path.isdir(SRC):
    SRC = os.path.join(HERE, '..', '..', '..', '..', '..', 'secondreality')   # from inside a worktree

COLS, ROWS, WIDTH = 158, 34, 400
FADE_IN = 127           # passes of the fade-in loop (y = 0...63*2)
HOLD = 519              # standalone: still steps before the scroll (as long as the demo's wait; see the app's check)
FADE_DRAW = 1332        # standalone: the draw that shows fade-out setting 0 (as in the demo)
FADE_OUT = 65
SCROLL = 1 + FADE_IN + HOLD          # the step showing scroll draw 0
LENGTH = SCROLL + FADE_DRAW + FADE_OUT
STEPS = [0, 1, 2, 3, 4, 5, 60, 61, 126, 127, 128, 300, 646, 647, 648, 649, 650, 655, 656, 700, 800, 1000, 1100, 1300,
         1500, 1700, 1900, 1978, 1979, 1980, 1981, 2000, 2010, 2042, 2043]
FILES = ('WAT1.DAT', 'WAT2.DAT', 'WAT3.DAT', 'BKG.CLX', 'MIEKKA.SCI')


def load(src):
    f = lambda n: open(os.path.join(src, 'WATER', n), 'rb').read()
    bkg, miekka = f('BKG.CLX'), f('MIEKKA.SCI')
    assert bkg[:4] == b'RIX3' and struct.unpack_from('<HH', bkg, 4) == (320, 200)
    assert miekka[:4] == b'RIX3' and struct.unpack_from('<H', miekka, 4) == (WIDTH,)   # its height word (250) is wrong
    tables = []
    for n in (1, 2, 3):
        d = f(f'WAT{n}.DAT'); p = 0; cells = []
        for _ in range(COLS * ROWS):
            count = struct.unpack_from('<H', d, p)[0]; p += 2
            cells.append(struct.unpack_from(f'<{count}H', d, p)); p += 2 * count
        assert p == len(d), f'WAT{n}.DAT does not parse to its length'
        tables.append(cells)
    return {'pal': miekka[10:778], 'bgpal': bkg[10:778], 'bg': bkg[778:778 + 64000],
            'sword': miekka[778:778 + WIDTH * ROWS], 'tables': tables,
            'green': f('GREEN.CLX')[778:778 + 64000], 'mask': f('MASK.MTV'), 'raw': {n: f(n) for n in FILES}}


class Part:
    """DEMO.PAS's state from refresh to refresh."""

    def __init__(self, d):
        self.d = d
        self.screen = bytearray(d['bg'])
        self.fbuf = bytearray(COLS * ROWS + 1)       # the window (one byte longer, as declared)
        self.target = list(d['pal']) + [0]           # tmppal, 769 bytes
        self.pal = [0] * 769                         # the palette being faded
        self.shown = [0] * 768                       # what the VGA card was last given
        self.sss = self.scp = 0

    def scr(self):
        bg, screen, fbuf = self.d['bg'], self.screen, self.fbuf
        for i, cell in enumerate(self.d['tables'][self.sss]):
            v = fbuf[i]
            for a in cell:
                screen[a] = v if v else bg[a]

    def fade_in_pass(self, y):
        if y & 1:
            for x in range(256):
                self.shown[3 * x:3 * x + 3] = self.pal[3 * x:3 * x + 3]
                for pf in range(4):                  # 0 to 3: the next colour's red as well
                    if self.pal[3 * x + pf] < self.target[3 * x + pf]:
                        self.pal[3 * x + pf] += 1
        self.scr()                                   # the window is empty: the background again
        self.sss = 0 if self.sss == 2 else self.sss + 1

    def start_scroll(self):
        self.sss = self.scp = 0

    def draw(self, fading):
        if fading:
            for x in range(256):
                self.shown[3 * x:3 * x + 3] = self.pal[3 * x:3 * x + 3]
                for pf in range(4):
                    if self.pal[3 * x + pf] > 0:
                        self.pal[3 * x + pf] -= 1
        self.scr()
        if self.sss == 2:
            self.sss = 0
            # move(fbuf[1], fbuf, sizeof(fbuf)), then the new column at index 158 + row * 158: the next
            # row's first cell, which the next move brings to this row's last.
            self.fbuf[0:COLS * ROWS] = self.fbuf[1:COLS * ROWS + 1]
            for r in range(ROWS):
                self.fbuf[COLS + r * COLS] = self.d['sword'][r * WIDTH + self.scp]
            if self.scp < 390:
                self.scp += 1
        else:
            self.sss += 1


def frames(d, steps):
    """step -> (screen, palette as shown) for the wanted standalone steps."""
    part, out = Part(d), {}
    for step in range(max(steps) + 1):
        if 1 <= step <= FADE_IN:
            part.fade_in_pass(step - 1)
        elif step == SCROLL:
            part.start_scroll()
        if step >= SCROLL:
            part.draw(step - SCROLL >= FADE_DRAW)
        if step in steps:
            out[step] = (bytes(part.screen), bytes(part.shown))
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
    tables, green, bg = d['tables'], d['green'], d['bg']
    for name, data in d['raw'].items():
        print(f'{name}: {len(data)} bytes, crc {zlib.crc32(data)}')
    sets = [set(a for cell in t for a in cell) for t in tables]
    counts = [sum(len(cell) for cell in t) for t in tables]
    union = sets[0] | sets[1] | sets[2]
    area = {a for a in range(64000) if 1 <= green[a] <= ROWS}
    print(f'tables: {counts} addresses; shared between tables: {sum(counts) - len(union)}; together {len(union)} pixels; '
          f'GREEN.CLX rows 1...{ROWS}: {len(area)} pixels ({len(area - union)} of them in no table, {len(union - area)} table pixels outside)')
    # DATGEN writes row y = 34 first: table row r is GREEN.CLX value 34 - r.
    wrong = sum(1 for t in tables for i, cell in enumerate(t) for a in cell if green[a] != ROWS - i // COLS)
    rising = all(list(cell) == sorted(cell) for t in tables for cell in t)
    print(f'rows that disagree with GREEN.CLX (34 - table row): {wrong}; addresses rise within every cell: {rising}')
    col, row, ph = {}, {}, {}
    for k, t in enumerate(tables):
        for i, cell in enumerate(t):
            for a in cell:
                col[a], row[a], ph[a] = i % COLS, i // COLS, k
    mask = d['mask']
    assert mask[:8] == b'320 200\n'
    red = mask[8::3]
    print(f'MASK.MTV: its red channel (DATGEN\'s column) equals the table column at {sum(1 for a in union if red[a] == col[a] + 1)} '
          f'of {len(union)} table pixels (differences {min(red[a] - col[a] - 1 for a in union if red[a])}...'
          f'{max(red[a] - col[a] - 1 for a in union if red[a])}): another render')
    for label, third in (('c + (2 - k)/3', lambda a: 3 * col[a] + 2 - ph[a]), ('c + k/3', lambda a: 3 * col[a] + ph[a])):
        pairs = near = 0
        for a in union:
            b = a + 1
            if b % 320 and b in col and abs(row[a] - row[b]) <= 1 and abs(col[a] - col[b]) <= 2:
                pairs += 1
                near += abs(third(a) - third(b)) <= 1
        print(f'sword coordinate {label}: {near} of {pairs} neighbours along a row are within a third of a column')
    # Regions: the sea and the reflections.
    seen, sizes = set(), []
    for a in sorted(union):
        if a in seen:
            continue
        stack, n = [a], 0
        seen.add(a)
        while stack:
            p = stack.pop(); n += 1
            for q in (p - 1, p + 1, p - 320, p + 320):
                if q in col and q not in seen and abs(q % 320 - p % 320) <= 1:
                    seen.add(q); stack.append(q)
        sizes.append(n)
    print(f'regions (4-connected): {len(sizes)}, sizes {sorted(sizes, reverse=True)}')
    # Palette and picture facts.
    pal, bgpal, sword = d['pal'], d['bgpal'], d['sword']
    differ = [c for c in range(256) if pal[3 * c:3 * c + 3] != bgpal[3 * c:3 * c + 3]]
    print(f'background colours used: {min(bg)}...{max(bg)}; MIEKKA.SCI\'s palette differs from BKG.CLX\'s in '
          f'{differ[0]}...{differ[-1]} ({len(differ)} colours)')
    inked = [c for c in range(WIDTH) if any(sword[r * WIDTH + c] for r in range(ROWS))]
    print(f'sword: colours {sorted(set(sword) - {0})[0]}...{max(sword)} ({len(set(sword)) - 1} of them, '
          f'below 192: {sorted(v for v in set(sword) if 0 < v < 192)}); inked columns {inked[0]}...{inked[-1]}; '
          f'column 390 inked: {390 in inked}')
    print(f'cells per table that own no pixel: {[sum(1 for cell in t if not cell) for t in tables]} of {COLS * ROWS}; '
          f'largest cell {max(len(cell) for t in tables for cell in t)} pixels')


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
    print(f'standalone length {LENGTH} steps (scroll from step {SCROLL}, fade-out from draw {FADE_DRAW})')
    print('steps', STEPS)
    print('crc32', [zlib.crc32(rgb(*got[s])) for s in STEPS])
    print('palette crc32 at 61, 127, 1990:', [zlib.crc32(frames(d, [s])[s][1]) for s in (61, 127, 1990)])


if __name__ == '__main__':
    main()
