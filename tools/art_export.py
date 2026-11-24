#!/usr/bin/env python3
"""Exports every picture the released Second Reality uses to PNG, into artwork/original/.

    python3 tools/art_export.py            # export (reads ../secondreality, changes nothing there)
    python3 tools/art_export.py --check    # re-decode and compare with what is in artwork/original/

For each picture it reads the copy that was BUILT INTO the demo (the .OBK/.OBJ/.INC linked
into the part's program, or the file the program loads) and cross-checks it against the
artist's Deluxe Paint file, so the PNG is what the demo actually showed. Outputs:
- artwork/original/<name>.png       exact pixels and palette (an indexed PNG)
- artwork/original/4x3/<name>.png   each pixel repeated so the picture has the shape it
                                    had on a 1993 monitor (no smoothing); pictures only
- artwork/original/explosion/frame-NN.png   the 40 explosion frames
- artwork/original/CHECKSUMS.txt    a checksum of each picture's pixels and palette
Set SR_ORIGINAL=<folder> if the original source is not at ../secondreality.
"""

import hashlib
import os
import sys

sys.dont_write_bytecode = True  # leave no __pycache__ folder in tools/
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artformats import (FormatError, Picture, inc_data, obk_data, png_indexed, png_scaled,  # noqa: E402
                        read_any, read_fcfc, read_lbm, read_png_indexed, read_rix, vga_palette, words)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SOURCE = os.environ.get("SR_ORIGINAL", os.path.join(REPO, "..", "secondreality"))
OUT = os.path.join(REPO, "artwork", "original")

# Pixel shapes: a 320x200 screen filled a 4:3 monitor, so each pixel was 1.2 times as tall
# as wide; in the 400-line modes 0.6. Written as (repeat across, repeat down).
TALL = (5, 6)     # 1.2
SHORT = (5, 3)    # 0.6


def src(path):
    with open(os.path.join(SOURCE, path), "rb") as f:
        return f.read()


def from_obk(path):
    return obk_data(src(path))


def from_inc(*paths):
    return b"".join(inc_data(src(p).decode("latin-1")) for p in paths)


def raw_font(data, width, height):
    """Fonts kept as bare pixels (FONA.INC): shade levels 0...n, coloured by the program.
    Shown here as greys from black (0) to white (the highest level)."""
    pixels = data[:width * height]
    top = max(pixels)
    greys = [((v * 255 + top // 2) // top,) * 3 for v in range(top + 1)]
    return Picture(width, height, pixels, greys, top + 1)


BARE_FONTS = {"01-opening-font", "18-credits-font", "19-endscroller-font"}


def planar_fcfc(data):
    """TEXTS.16: FCFC header, then bit planes one row after another (plane 0, plane 1, ...)."""
    magic, w, h, cols, add = words(data, 0, 5)
    rb = w // 8
    body = data[add * 16:]
    planes = len(body) // (rb * h)  # TEXTS.16: 2 (its header says 16 colours, it uses 4)
    out = bytearray()
    for y in range(h):
        rows = [body[(y * planes + p) * rb:(y * planes + p + 1) * rb] for p in range(planes)]
        for x in range(w):
            v = 0
            for p, r in enumerate(rows):
                v |= ((r[x >> 3] >> (7 - (x & 7))) & 1) << p
            out.append(v)
    return Picture(w, h, out, vga_palette(data[16:16 + cols * 3], cols), cols)


# (name, part, built copy -> Picture, [artist's files to compare], pixel shape or None, note)
PIECES = [
    ("00-start-setup-screen", "START", lambda: read_any(from_obk("START/_HZPIC.OBJ")),
     ["START/HZPIC.P", "START/HZPIC.LBM"], SHORT,
     "Setup screen. Rows 300-331 hold the screen's font."),
    ("01-opening-horizon", "ALKU", lambda: read_any(from_inc("ALKU/HOI.IN0", "ALKU/HOI.IN1")),
     ["ALKU/HOI.U", "ALKU/HOI.LBM"], TALL,
     "Palette as built: colours 1-3 were changed to the text's greys."),
    ("01-opening-font", "ALKU", lambda: raw_font(from_inc("ALKU/FONA.INC")[1:], 1500, 30),
     ["ALKU/FONA.UH", "ALKU/FONA.LBM"], None,
     "Font: shades 0-3, coloured by the program. The built copy has one stray byte in front (left out here)."),
    ("02-ships-horizon", "VISU", lambda: read_any(src("VISU/C/U2ABG.UH")),
     ["VISU/C/_BG.OBK", "VISU/C/U2ABG.LBM"], TALL, "Already used by the Ships Fly-by scene."),
    ("04-title", "BEG", lambda: read_any(from_obk("BEG/_PIC.OBK")),
     ["BEG/SRTITLE.UP", "BEG/SRTITLE.LBM"], SHORT, ""),
    ("05-glenz-plate", "GLENZ", lambda: read_any(from_obk("GLENZ/_FC.OBK")),
     ["GLENZ/FC.UH", "GLENZ/FC.LBM"], TALL, "Already used by the Glenz Vectors scene."),
    ("07-troll", "TECHNO", lambda: read_any(src("MAIN/DATA/TROLL.UP")),
     ["TECHNO/TROLL.UP", "TECHNO/PANICPIC.LBM"], SHORT,
     "Shown after the techno bars; part 8 then 'switches the screen off' on it."),
    ("09-mountain-background", "FOREST", lambda: read_any(from_obk("FOREST/HILLBACK.OBJ")),
     ["FOREST/HILLBACK.CLX", "FOREST/FINAL.LBM"], TALL, ""),
    ("09-mountain-font", "FOREST", lambda: read_any(src("MAIN/DATA/O2.SCI")),
     ["FOREST/O2.SCI", "FOREST/FONA2.LBM"], None, "Font, with its own palette."),
    ("10-lens-picture", "LENS", lambda: read_any(from_obk("LENS/_LENSEXB.OBK")),
     ["LENS/LENS.EXB", "LENS/LENSPIC.LBM"], TALL, "Used by both the lens and the rotozoomer."),
    ("10-lens-shape", "LENS", lambda: Picture(320, 200, src("LENS/LENS.U"), read_lbm(src("LENS/LENS.LBM")).palette),
     ["LENS/LENS.LBM"], TALL,
     "Not shown: the lens's shape (colours 1-4 = its zones), turned into tables when building."),
    ("13-water-background", "WATER", lambda: read_any(from_obk("WATER/BKG.OBJ")),
     ["WATER/BKG.CLX", "WATER/FINAL.LBM"], TALL, "Ray-traced (POV-Ray)."),
    ("13-water-font", "WATER", lambda: read_rix(from_obk("WATER/MIEKKA.OBJ"), height=35),
     ["WATER/MIEKKA.SCI"], None,
     "Font (sword letters), with its own palette. Its header says 400x250; the data is 400x35."),
    ("15-jelly-logo", "JPLOGO", lambda: read_any(from_obk("JPLOGO/_PIC.OBK")),
     ["JPLOGO/ICEKNGDM.UP", "JPLOGO/ICEKNGDM.LBM"], SHORT, ""),
    ("17-end-picture", "END", lambda: read_any(from_obk("END/_PIC.OBK")),
     ["END/PIC.UH", "END/PIC.LBM"], SHORT, ""),
    ("18-credits-font", "CREDITS", lambda: raw_font(from_inc("CREDITS/FONA.INC"), 1500, 40),
     [], None, "Font: shades 0-9, coloured by each credits picture's palette. The program uses the top 32 rows."),
    ("19-endscroller-font", "ENDSCRL", lambda: raw_font(from_inc("ENDSCRL/FONA.INC"), 1500, 30),
     ["ENDSCRL/FONA.UH", "ENDSCRL/FONA.LBM"], None, "Font: shades 0-3, coloured by the program."),
    ("starfield-text-panels", "DDSTARS", lambda: planar_fcfc(from_obk("DDSTARS/_TEXTPIC.OBK")),
     ["DDSTARS/TEXTS.16", "DDSTARS/TEXTS.LBM"], None,
     "Two text panels; left out of this project's Hidden Starfield."),
]
CREDITS = ["01", "02", "03", "04", "05", "05B", "06", "07", "08", "09", "10", "10B",
           "11", "12", "13", "14", "14B", "15", "16", "17", "18"]
for c in CREDITS:
    PIECES.append((f"18-credits-pic{c.lower()}", "CREDITS",
                   (lambda c=c: read_lbm(src(f"CREDITS/PICS/PIC{c}.LBM"))), [], TALL,
                   "Only the artist's file survives (the built copies are not in the source)."))


def other(path):
    """An artist's file or another built copy, read whatever its kind."""
    if path.upper().endswith(".16"):
        return planar_fcfc(src(path))
    if path.upper().endswith((".OBK", ".OBJ")):
        return read_any(from_obk(path))
    return read_any(src(path))


def compare(a, b):
    """'same', or how b differs from a. Palettes are compared on a's colours only, and
    within 4 of 255 (Deluxe Paint keeps 0...252 where the demo keeps 0...63)."""
    if (a.width, a.height) != (b.width, b.height):
        return f"size {b.width}x{b.height}"
    diff = sum(1 for x, y in zip(a.pixels, b.pixels) if x != y)
    worst = max((max(abs(p - q) for p, q in zip(a.palette[c], b.palette[c])) for c in a.used_colours()), default=0)
    if diff == 0 and worst <= 4:
        return "same"
    return f"{diff} pixels differ" + (f", colours differ by up to {worst}" if worst > 4 else "")


def checksum(pic):
    h = hashlib.sha256(pic.pixels + b"".join(bytes(c) for c in pic.palette))
    return h.hexdigest()[:16]


# ---------------------------------------------------------------- the explosion (PAM)

def explosion_frames():
    """OUT.ANI as linked into PAM.EXE (OUT.IN0-4). Each frame starts on a 16-byte boundary and
    changes the picture shown TWO frames earlier (the player draws into two pages in turn).
    The data holds 42 frames; OUTTAA.C shows the first 40, four screen refreshes each:
    byte n > 0: n pixels of the next byte; n < 0: skip -n pixels; 0: end of frame (ANIM.C)."""
    data = from_inc(*[f"PAM/OUT.IN{i}" for i in range(5)])
    palette = vga_palette(from_inc("PAM/PAL.INC"))
    pages = [bytearray(64000), bytearray(64000)]
    frames = []
    pos = 0
    while len(frames) < 40:
        page = pages[len(frames) & 1]
        i = 0
        while True:
            n = data[pos]; pos += 1
            if n == 0:
                break
            if n < 128:
                v = data[pos]; pos += 1
                page[i:i + n] = bytes([v]) * n
                i += n
            else:
                i += 256 - n
        if i != 64000:  # every frame must cover the screen exactly: a strong check of the decoding
            raise FormatError(f"explosion frame {len(frames) + 1} covers {i} pixels, not 64000")
        frames.append(Picture(320, 200, bytes(page), palette))
        pos = (pos + 15) & ~15
    return frames, data


# ---------------------------------------------------------------- main

def export():
    os.makedirs(os.path.join(OUT, "4x3"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "explosion"), exist_ok=True)
    sums = []
    problems = 0
    for name, part, load, others, shape, note in PIECES:
        pic = load()
        results = []
        for o in others:
            try:
                b = other(o)
                if name in BARE_FONTS:  # no palette of their own: compare shapes only
                    b.palette = pic.palette
                results.append(f"{o}: {compare(pic, b)}")
            except FormatError as e:
                results.append(f"{o}: unreadable ({e})")
        with open(os.path.join(OUT, name + ".png"), "wb") as f:
            f.write(png_indexed(pic))
        if shape:
            with open(os.path.join(OUT, "4x3", name + ".png"), "wb") as f:
                f.write(png_scaled(pic, *shape))
        sums.append(f"{checksum(pic)}  {name}.png  {pic.width}x{pic.height}")
        print(f"{name:28} {pic.width}x{pic.height:<4} " + ("; ".join(results) or "(no other copy)"))
        problems += sum(1 for r in results if not r.endswith("same"))
    frames, _ = explosion_frames()
    for i, pic in enumerate(frames, 1):
        with open(os.path.join(OUT, "explosion", f"frame-{i:02}.png"), "wb") as f:
            f.write(png_indexed(pic))
        sums.append(f"{checksum(pic)}  explosion/frame-{i:02}.png  320x200")
    with open(os.path.join(OUT, "4x3", "explosion-frame-20.png"), "wb") as f:
        f.write(png_scaled(frames[19], *TALL))
    print(f"explosion: {len(frames)} frames")
    with open(os.path.join(OUT, "CHECKSUMS.txt"), "w") as f:
        f.write("# Checksum of each picture's pixels + palette (tools/art_export.py).\n")
        f.write("\n".join(sums) + "\n")
    print(f"{len(sums)} pictures written to {os.path.relpath(OUT, REPO)}; "
          f"{problems} comparisons not 'same' (see above)")


def check():
    """Decode again and compare with the PNGs on disk, pixel for pixel."""
    bad = 0
    pics = [(name, load()) for name, _, load, _, _, _ in PIECES]
    frames, _ = explosion_frames()
    pics += [(f"explosion/frame-{i:02}", p) for i, p in enumerate(frames, 1)]
    for name, pic in pics:
        with open(os.path.join(OUT, name + ".png"), "rb") as f:
            w, h, pixels, palette = read_png_indexed(f.read())
        if (w, h, pixels) != (pic.width, pic.height, pic.pixels) or palette != pic.palette:
            print("DIFFERENT:", name); bad += 1
    print(f"{len(pics)} PNGs checked, {bad} different")
    return bad == 0


if __name__ == "__main__":
    if not os.path.isdir(SOURCE):
        sys.exit(f"Original source not found at {SOURCE} (set SR_ORIGINAL)")
    if "--check" in sys.argv:
        sys.exit(0 if check() else 1)
    export()
