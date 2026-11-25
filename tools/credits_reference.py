#!/usr/bin/env python3
"""Development tool: facts about the credits part (CREDITS/MAIN.C) as RELEASED, and a replay of its
1993 screen, to check the app's Credits scene against.

    python3 tools/credits_reference.py                  # facts, and checksums at chosen steps
    python3 tools/credits_reference.py --extract DIR    # write CREDPICS.BIN and CREDFONT.BIN into DIR
    python3 tools/credits_reference.py --png STEP FILE  # the 1993 screen at STEP as a picture (320x400)

Reads the released MAIN/DATA/CRED.EXE (PKLITE-packed; unpacked with `deark -m pklite`, Homebrew), not
the source's files: the released pictures and texts differ from the source (see artwork/README.md).
Set SR_ORIGINAL=<folder> if the original source is not at ../secondreality. Standard library only
(besides deark).

How the screen was made (CREDITS/MAIN.C, TWEAK.ASM), per screen of credits, 362 refreshes:
- Video memory is 640 pixels a row (CRTC offset 80 in byte mode), each row shown on 2 of 400 lines.
  `tw_putpixel` writes as if rows were 320 wide (address 80 y + x / 4), so the TEXT, drawn at y 16, 58,
  100, 142 with it, lands on display row y / 2, at x + 320 for odd y: only the font's even rows are on
  the left half of the screen. The picture is drawn at (400 + x, 400 + 2 y), which is display row
  200 + y, x 400 + x: the program allowed for the wide rows there.
- The top of the screen shows display rows from 200, scrolled sideways by yy pixels (start address
  yy / 4 bytes plus a fine scroll of yy & 3). Below the split line (line compare, in the 400 lines) the
  card shows display rows from 0, not scrolled: the text.
- One wait, then the slide in (y = 25600, then y x 12 / 13 while y > 0: 102 refreshes; split y / 128 +
  200, yy 320 - y / 80), 200 refreshes still, the slide out (y += v, v += 15 from 0 while y < 25600: 59;
  yy 320 + y / 80).
- Step pairing: `dis_waitb` returns just after vertical retrace begins (MAIN/COPPER.ASM `copper_end`).
  The split and fine scroll written after it show on the coming refresh; the start address is latched
  by the card at the start of retrace, so the one written after the wait shows a refresh later (an
  assumption about the VGA card, not from the source).
"""
import os
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.environ.get("SR_ORIGINAL", os.path.join(HERE, "..", "..", "secondreality"))

PICTURES = 21
PICTURE_START, PICTURE_SIZE = 72272, 16784
STEPS_PER_SCREEN = 362
ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/?!:,.\"()+-"
FONT_ROWS, FONT_WIDTH = 32, 1500


def released():
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["deark", "-m", "pklite", "-q", "-od", tmp, "-o", "cred",
                        os.path.join(SOURCE, "MAIN", "DATA", "CRED.EXE")], check=True)
        name = next(f for f in os.listdir(tmp) if f.lower().endswith(".exe"))
        with open(os.path.join(tmp, name), "rb") as f:
            return f.read()


EXE = released()
FONT_START = 12272   # where FONA.INC (40 rows of 1500) is linked into the unpacked program
FONT = EXE[FONT_START:FONT_START + 40 * FONT_WIDTH]


def picture_block(k):
    s = PICTURE_START + PICTURE_SIZE * k
    block = EXE[s:s + PICTURE_SIZE]
    assert block[:2] == b"\xfc\xfc" and block[2:6] == bytes([160, 0, 100, 0]), k
    return block


def screens():
    """The 21 texts, read from the strings linked into the program in order. Each screen's text is
    lines ending in a zero byte, and an empty line ends it; its first line is printed even if empty
    (MAIN.C: `while(*(text = prtc(...)))`)."""
    start = EXE.find(b"GRAPHICS - MARVEL")
    pos, out = start, []
    for _ in range(PICTURES):
        lines = []
        while True:
            end = EXE.index(b"\0", pos)
            line = EXE[pos:end].decode("ascii")
            pos = end + 1
            if lines and line == "":
                break
            lines.append(line)
        out.append(lines)
    return out


SCREENS = screens()


def glyphs():
    """MAIN.C `init`: each character in ORDER is the next run of columns with ink in the top 32 rows."""
    pos, width = {}, {}
    x = 0
    for ch in ORDER:
        while x < FONT_WIDTH and not any(FONT[y * FONT_WIDTH + x] for y in range(FONT_ROWS)):
            x += 1
        b = x
        while x < FONT_WIDTH and any(FONT[y * FONT_WIDTH + x] for y in range(FONT_ROWS)):
            x += 1
        pos[ch], width[ch] = b, x - b
    pos[" "], width[" "] = FONT_WIDTH - 32, 8
    return pos, width


GLYPH_POS, GLYPH_WIDTH = glyphs()


def memory(k):
    """Video memory for screen k as 640-wide display rows (dict: (row, x) -> colour), and its palette."""
    mem = {}
    y = 16
    for line in SCREENS[k]:
        w = sum(GLYPH_WIDTH[c] + 2 for c in line)
        x = 160 - w // 2
        for c in line:
            sx = GLYPH_POS[c]
            for x2 in range(x, x + GLYPH_WIDTH[c]):
                for y2 in range(y, y + FONT_ROWS):
                    address = 80 * y2 + x2 // 4   # tw_putpixel: 80 bytes a row
                    row, byte = divmod(address, 160)
                    mem[(row, byte * 4 + (x2 & 3))] = FONT[(y2 - y) * FONT_WIDTH + sx]
                sx += 1
            x += GLYPH_WIDTH[c] + 2
        y += FONT_ROWS + 10
    block = picture_block(k)
    for py in range(100):
        for px in range(160):
            mem[(200 + py, 400 + px)] = block[784 + py * 160 + px] + 16
    pal = bytearray(block[16:784])
    pal[48:768] = block[16:16 + 720]      # init(): the picture's colours move up 16
    for a in range(10):
        pal[a * 3:a * 3 + 3] = bytes([7 * a] * 3)
    return mem, bytes(pal)


def registers(local):
    """(split line, fine-scroll yy, start-address yy) shown on a screen's local step 0...361."""
    ins = []
    y = 200 * 128
    while y > 0:
        ins.append(y)
        y = y * 12 // 13
    outs = []
    y = v = 0
    while y < 128 * 200:
        outs.append(y)
        y += v
        v += 15
    assert len(ins) == 102 and len(outs) == 59 and 1 + len(ins) + 200 + len(outs) == STEPS_PER_SCREEN
    if local == 0:
        return 400, 0, 0
    j = local - 1
    if j < len(ins):
        return ins[j] // 128 + 200, 320 - ins[j] // 80, 320 - ins[j - 1] // 80 if j else 0
    j -= len(ins)
    last = 320 - ins[-1] // 80
    if j < 200:
        return ins[-1] // 128 + 200, last, last
    j -= 200
    return outs[j] // 128 + 200, 320 + outs[j] // 80, 320 + outs[j - 1] // 80 if j else last


def screen(step):
    """The 1993 picture at a step of the whole credits: 320 x 400 colour numbers, and the palette."""
    k, local = divmod(step % (PICTURES * STEPS_PER_SCREEN), STEPS_PER_SCREEN)
    mem, pal = memory(k)
    split, pan, start = registers(local)
    # The fine scroll the card holds on a screen's first step is the previous screen's last one; it does
    # not matter there (nothing is drawn within sight).
    view = 4 * (start // 4) + (pan & 3)
    out = bytearray(320 * 400)
    for line in range(400):
        if line <= split:
            row, x0 = 200 + line // 2, view
        else:
            row, x0 = (line - split - 1) // 2, 0
        for c in range(320):
            x = x0 + c
            r = row + x // 640
            out[line * 320 + c] = mem.get((r, x % 640), 0)
    return bytes(out), pal


def checksum(step):
    pixels, pal = screen(step)
    return zlib.crc32(pixels + pal)


CHECK_STEPS = [0, 1, 2, 10, 50, 102, 103, 200, 302, 303, 304, 330, 361, 362, 362 * 9 + 40, 362 * 9 + 320,
               362 * 20 + 150, 362 * 21 - 1] + [362 * k + 250 for k in range(PICTURES)]   # every screen, held

if __name__ == "__main__":
    if "--extract" in sys.argv:
        folder = sys.argv[sys.argv.index("--extract") + 1]
        with open(os.path.join(folder, "CREDPICS.BIN"), "wb") as f:
            f.write(b"".join(picture_block(k) for k in range(PICTURES)))
        with open(os.path.join(folder, "CREDFONT.BIN"), "wb") as f:
            f.write(FONT)
        print("written to", folder)
    elif "--png" in sys.argv:
        i = sys.argv.index("--png")
        pixels, pal = screen(int(sys.argv[i + 1]))
        sys.path.insert(0, HERE)
        sys.dont_write_bytecode = True
        from artformats import Picture, png_rgb, vga_palette
        with open(sys.argv[i + 2], "wb") as f:
            f.write(png_rgb(Picture(320, 400, pixels, vga_palette(pal))))
    else:
        sys.path.insert(0, HERE)
        sys.dont_write_bytecode = True
        from artformats import inc_data
        inc = inc_data(open(os.path.join(SOURCE, "CREDITS", "FONA.INC"), "rb").read().decode("latin-1"))
        print("font: 40 x 1500 bytes at", FONT_START, "equal to the source's FONA.INC:", FONT == inc[:len(FONT)])
        for k, lines in enumerate(SCREENS):
            print(f"screen {k + 1:2}: " + " | ".join(lines))
        print("checksums (CRC-32 of the 320x400 colour numbers, then the 768 palette levels):")
        for s in CHECK_STEPS:
            print(f"  step {s:5}: {checksum(s)}")
