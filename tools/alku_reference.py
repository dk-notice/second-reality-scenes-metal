#!/usr/bin/env python3
"""Development tool: facts about the opening credits (ALKU/MAIN.C) as RELEASED, and a replay of their 1993
screen, to check the app's Opening Credits scene against.

    python3 tools/alku_reference.py                  # facts, the schedule, and checksums at chosen steps
    python3 tools/alku_reference.py --extract DIR    # write HORIZON.BIN and FONT.BIN into DIR
    python3 tools/alku_reference.py --png STEP FILE  # the 1993 screen at STEP as a picture (320x400)

Reads the released MAIN/DATA/ALKU.EXE, packed twice (PKLITE, and LZEXE inside: `deark -m pklite`, then
`deark -m lzexe`; Homebrew), not the source's files. Its picture equals the source's HOI.IN0/IN1; its font
has 3 pixels added (they join the two pieces of "&"); its code differs from the source (see
docs/scenes/opening-credits.md). Set SR_ORIGINAL=<folder> if the original source is not at ../secondreality.
Standard library only (besides deark).

STEPS are Play Demo's: step 0 is the part's first (song 1 starting from section 0), and the music's sync
values (DIS's `dis_sync`) reach 1...9 on the steps in CUES, measured from the script's silent run and
equal to the "Opening credits' cues (steps)" line tools/demo_timeline.py prints.

How the screen was made (as released):
- 320 x 400: every one of the card's 400 lines shows its own memory row, 176 bytes (704 pixels) wide.
  `tw_putpixel` uses the same 176, so the text is drawn at full height (unlike the credits).
- The horizon (640 x 150 of the 640 x 200 picture) is drawn twice into memory, each picture row on two
  memory rows (lines 50...349). Scrolling to position a shows picture columns a...a+319.
- Colour numbers: the picture uses 0...63; text shades 1...3 are ORed in as 64, 128, 192. Three palettes:
  `palette` (64...255 repeat 0...63: text invisible), `palette2` (text shade s over colour c:
  (P[s] x 63 + P[c] x (63 - P[s])) >> 6, P[1...3] being the picture's greys 10, 30, 63), `fade2` (text
  shades plain, everything else black: the titles).
- Step pairing: the program sets the start address and fine scroll together; the copper writes both just
  before vertical retrace and loads palettes at its start, so what the program sets during step t shows
  on step t + 1, all of it at once (MAIN/COPPER.ASM `copper_end`; ALKU/COPPER.ASM).
"""
import os
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.environ.get("SR_ORIGINAL", os.path.join(HERE, "..", "..", "secondreality"))

# The steps (from the part's start) on which the music's sync value reaches 1...9: song 1 from section 0,
# rendered silently 1/70 s a step (as SRMetal --demo-timeline does; checked there too).
CUES = [1128, 1688, 2099, 2658, 3218, 3777, 4337, 4897, 5045]
TITLE_STEPS = 427        # a title from its cue: fade in 63, hold 300, fade out 64
SCROLL_STEP = 9          # SCRLF: refreshes per pixel of scroll
END = 2947               # from sync 4: 320 scroll steps (2,881), the last fade (64), the hand-over (2)
LENGTH = None            # the part's length, set below from CUES


def released():
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["deark", "-m", "pklite", "-q", "-od", tmp, "-o", "a",
                        os.path.join(SOURCE, "MAIN", "DATA", "ALKU.EXE")], check=True)
        first = os.path.join(tmp, next(f for f in os.listdir(tmp) if f.lower().endswith(".exe")))
        subprocess.run(["deark", "-m", "lzexe", "-q", "-od", tmp, "-o", "b", first], check=True)
        name = next(f for f in os.listdir(tmp) if f.startswith("b") and f.lower().endswith(".exe"))
        with open(os.path.join(tmp, name), "rb") as f:
            return f.read()


EXE = released()
HORIZON_START, HORIZON_SIZE = 143888, 784 + 640 * 200   # FC FC header, palette, 640 x 200 colour numbers
FONT_START, FONT_SIZE = HORIZON_START + HORIZON_SIZE + 1, 45000   # 30 rows of 1500, as the program reads it
HORIZON = EXE[HORIZON_START:HORIZON_START + HORIZON_SIZE]
FONT = EXE[FONT_START:FONT_START + FONT_SIZE] + bytes(1500 * 2)   # rows 30, 31: the zeros linked after it
assert HORIZON[:6] == bytes([252, 252, 128, 2, 200, 0])
P = list(HORIZON[16:784])
PIXELS = HORIZON[784:]

ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXabcdefghijklmnopqrstuvwxyz0123456789!?,.:&()+-*=/[]"
TITLES = [[(120, "A"), (160, "Future Crew"), (200, "Production")],
          [(160, "First Presented"), (200, "at Assembly 93")],
          [(120, "in"), (160, "["), (179, "]")]]          # "[" and "]" are the two halves of a Dolby Surround logo
PAGES = [[(50, "Graphics"), (90, "Marvel"), (130, "Pixel")],
         [(50, "Music"), (90, "Purple Motion"), (130, "Skaven")],
         [(30, "Code"), (70, "Psi"), (110, "Trug"), (148, "Wildfire")],
         [(50, "Additional Design"), (90, "Abyss"), (130, "Gore")]]


def glyphs():
    """init(): each character in ORDER is the next run of columns with ink in the font's top 29 rows (the
    release converts and scans 29 rows; the source 32). A space is 16 pixels."""
    pos, width = {}, {}
    x = 0
    for ch in ORDER:
        while x < 1500 and not any(FONT[y * 1500 + x] & 3 for y in range(29)):
            x += 1
        b = x
        while x < 1500 and any(FONT[y * 1500 + x] & 3 for y in range(29)):
            x += 1
        pos[ch], width[ch] = b, x - b
    pos[" "], width[" "] = 1480, 16
    return pos, width


GLYPH_POS, GLYPH_WIDTH = glyphs()


def shade(y, x):
    """The font as the program holds it after init(): rows 0...28 turned into 64 x shade; row 29 and below
    left as they are (only addtext reads them, and only the logo has ink in row 29)."""
    v = FONT[y * 1500 + x]
    return (v & 3) << 6 if y < 29 else v


def text_image(lines, rows, down, shift):
    """{(x, line): bits} for centred lines: prtc / addtext (both centre on 160 with w = sum(width + 2) / 2).
    Titles draw 29 rows at their place; pages 32 rows from the text buffer, which shows from line 100
    (`down`), 2 pixels right (`shift`)."""
    out = {}
    for top, text in lines:
        x = 160 - sum(GLYPH_WIDTH[c] + 2 for c in text) // 2 + shift
        for c in text:
            sx = GLYPH_POS[c]
            for dx in range(GLYPH_WIDTH[c]):
                for dy in range(rows):
                    v = shade(dy, sx + dx)
                    if v:
                        out[(x + dx, down + top + dy)] = out.get((x + dx, down + top + dy), 0) | v
            x += GLYPH_WIDTH[c] + 2
    return out


def palettes():
    pal2, fade2 = [0] * 768, [0] * 768
    for i in range(0, 768, 3):
        s = i // 192
        for c in range(3):
            if s == 0:
                pal2[i + c] = P[i + c]
            else:
                fade2[i + c] = P[s * 3 + c]
                pal2[i + c] = (P[s * 3 + c] * 63 + P[i % 192 + c] * (63 - P[s * 3 + c])) >> 6
    return P[:192] * 4, pal2, fade2


PALETTE, PALETTE2, FADE2 = palettes()
BLACK = [0] * 768


def copper_fade(start, target, k, frames):
    """ALKU/COPPER.ASM copper3: 8.8 fixed point, (target - start) x 256 / frames added k times."""
    out = []
    for s, t in zip(start, target):
        step = (t - s) * 256 // frames if t >= s else -((s - t) * 256 // frames)   # C's division
        out.append((s * 256 + k * step) >> 8)
    return out


def schedule(cues=CUES):
    """The moments the screen changes, worked out from the cues: the titles' starts, sync 4, and each
    page's R (the step whose scroll step its fade-in starts on). Steps are as in CUES."""
    sync = lambda t: sum(1 for c in cues if c <= t)
    titles, t = [], 0
    for k in range(1, 4):
        while sync(t) < k:
            t += 1
        titles.append(t)
        t += TITLE_STEPS
    while sync(t) < 4:
        t += 1
    t4 = t
    pages, setup = [], t4 + 15 * SCROLL_STEP        # the picture's fade-in loop ends after scroll step 15
    for page in range(len(PAGES)):
        t = setup
        while sync(t) < 5 + page:
            t += 1
        a = (t - t4) // SCROLL_STEP + 1               # the position the next scroll step will show
        if a & 1:
            a += 1                                    # wait for the next step: a must be even
        r = t4 + SCROLL_STEP * (a + 17)               # fmaketext(a + 16), then one more step
        pages.append(r)
        setup = r + 351                               # the fade-out has ended: the next page is set up
    return titles, t4, pages


TITLE_START, SYNC4, PAGE_R = schedule()
LENGTH = SYNC4 + END


def state(step):
    """(palette, scroll position, text image) the 1993 screen shows on a step."""
    pal, text = BLACK, {}
    for k, t in enumerate(TITLE_START):
        j = step - t
        if 1 <= j <= 63:
            pal, text = [(v * j) >> 6 for v in FADE2], TITLES[k]
        elif 64 <= j <= 363:
            pal, text = [(v * 63) >> 6 for v in FADE2], TITLES[k]
        elif 364 <= j <= 427:
            pal, text = [(v * (64 - (j - 364))) >> 6 for v in FADE2], TITLES[k]
    position = 0
    if step >= SYNC4 + 2:
        pal = copper_fade(BLACK, PALETTE, min(step - SYNC4 - 1, 128), 128)
        position = max(0, min(320, (step - SYNC4 - 1) // SCROLL_STEP))
    for k, r in enumerate(PAGE_R):
        j = step - r
        if 1 <= j <= 343:
            text = PAGES[k]
            if j <= 64:
                pal = copper_fade(PALETTE, PALETTE2, j, 64)
            elif j <= 279:
                pal = PALETTE2
            else:
                pal = copper_fade(PALETTE2, PALETTE, j - 279, 64)
    return pal, position, text


def screen(step):
    """The 1993 screen on a step: 320 x 400 x 3 VGA levels (0...63)."""
    pal, position, lines = state(step)
    is_page = any(lines is p for p in PAGES)
    bits = text_image(lines, 32 if is_page else 29, 100 if is_page else 0, 2 if is_page else 0) if lines else {}
    # Titles are drawn while the scroll is at 0 (and the picture is in memory, behind black colours).
    out = bytearray(320 * 400 * 3)
    for line in range(400):
        row = (line - 50) // 2 if 50 <= line < 350 else None
        for x in range(320):
            c = PIXELS[row * 640 + x + position] if row is not None else 0
            c |= bits.get((x, line), 0)
            i = (line * 320 + x) * 3
            out[i:i + 3] = bytes(pal[c * 3:c * 3 + 3])
    return bytes(out)


def checksum(step):
    return zlib.crc32(screen(step))


def check_steps():
    t1, t2, t3 = TITLE_START
    r1, r4 = PAGE_R[0], PAGE_R[3]
    return [0, t1, t1 + 1, t1 + 30, t1 + 200, t1 + 400, t1 + 427, t2 + 100, t3 + 64, t3 + 200,
            SYNC4 + 1, SYNC4 + 2, SYNC4 + 9, SYNC4 + 10, SYNC4 + 70, SYNC4 + 129, r1, r1 + 1, r1 + 32, r1 + 200,
            r1 + 300, r1 + 343, PAGE_R[1] + 150, PAGE_R[2] + 150, r4 + 150, SYNC4 + 2880, SYNC4 + 2881,
            LENGTH - 1]


if __name__ == "__main__":
    if "--extract" in sys.argv:
        folder = sys.argv[sys.argv.index("--extract") + 1]
        with open(os.path.join(folder, "HORIZON.BIN"), "wb") as f:
            f.write(HORIZON)
        with open(os.path.join(folder, "FONT.BIN"), "wb") as f:
            f.write(FONT[:FONT_SIZE])
        print("written to", folder)
    elif "--png" in sys.argv:
        i = sys.argv.index("--png")
        import struct
        rgb = bytes(v * 255 // 63 for v in screen(int(sys.argv[i + 1])))
        with open(sys.argv[i + 2], "wb") as f:
            raw = b"".join(b"\0" + rgb[y * 960:(y + 1) * 960] for y in range(400))
            chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
            f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 320, 400, 8, 2, 0, 0, 0))
                    + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    else:
        sys.path.insert(0, HERE)
        sys.dont_write_bytecode = True
        from artformats import inc_data
        src = lambda n: inc_data(open(os.path.join(SOURCE, "ALKU", n), "rb").read().decode("latin-1"))
        print("horizon equals the source's HOI.IN0 + HOI.IN1:", HORIZON == (src("HOI.IN0") + src("HOI.IN1"))[:HORIZON_SIZE])
        fona = src("FONA.INC")
        print("font: pixels differing from the source's FONA.INC:",
              [i for i in range(FONT_SIZE) if FONT[i] != fona[i]])
        print("titles start:", TITLE_START, " sync 4:", SYNC4, " pages' R:", PAGE_R, " length:", LENGTH)
        print("checksums (CRC-32 of the 320x400 screen as VGA levels, red green blue):")
        for s in check_steps():
            print(f"  step {s:5}: {checksum(s)}")
