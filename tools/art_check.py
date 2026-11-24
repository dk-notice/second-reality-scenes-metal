#!/usr/bin/env python3
"""Checks high-resolution pictures in artwork/modern/ against the rules in its README.

    python3 tools/art_check.py                  # every picture in artwork/modern/
    python3 tools/art_check.py 07-troll         # just these

For each picture: it has an original of the same name; it is a PNG in full colour (8 bits per
channel, RGB, not indexed, no transparency in use); it has the target size (the shape of the
original's 4x3 version, 2.4 times as large, e.g. 3840x2880); and its framing matches the original
(both are reduced to 160 blocks across and compared; the best fit should be with no shift).
Uses only Python and macOS's own `sips` (to shrink the big picture quickly).
"""

import os
import struct
import subprocess
import sys
import tempfile
import zlib

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artformats import read_png_indexed  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODERN = os.path.join(REPO, "artwork", "modern")
ORIGINAL = os.path.join(REPO, "artwork", "original")
GRID = 160          # blocks across for the framing comparison
SHIFT = 3           # blocks of shift tried each way
FIXED_TARGETS = {"explosion/": (1920, 1440)}  # chosen sizes that are not 2.4 x the 4x3 version


def png_header(path):
    with open(path, "rb") as f:
        data = f.read(64)
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h, depth, ctype = struct.unpack(">IIBB", data[16:26])
    return w, h, depth, ctype


def alpha_in_use(path):
    """For a PNG with an alpha channel: is any pixel not fully opaque? (Full decode; slow.)"""
    with open(path, "rb") as f:
        data = f.read()
    pos, idat = 8, b""
    while pos < len(data):
        n = struct.unpack_from(">I", data, pos)[0]
        name = data[pos + 4:pos + 8]
        if name == b"IHDR":
            w, h = struct.unpack_from(">II", data, pos + 8)
        elif name == b"IDAT":
            idat += data[pos + 8:pos + 8 + n]
        pos += 12 + n
    raw = zlib.decompress(idat)
    stride, bpp = w * 4, 4
    prev = bytearray(stride)
    p = 0
    for _ in range(h):
        f = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride]); p += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        if min(line[3::4]) < 255:
            return True
        prev = line
    return False


def small_brightness(path, cols, rows):
    """The picture shrunk to cols x rows by sips, as brightness values."""
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "small.bmp")
        subprocess.run(["sips", "-s", "format", "bmp", "-z", str(rows), str(cols), path, "--out", out],
                       check=True, capture_output=True)
        with open(out, "rb") as f:
            bmp = f.read()
    start = struct.unpack_from("<I", bmp, 10)[0]
    w, h = struct.unpack_from("<ii", bmp, 18)
    bpp = struct.unpack_from("<H", bmp, 28)[0] // 8
    stride = (w * bpp + 3) & ~3
    grid = []
    for y in range(abs(h)):
        src_row = (abs(h) - 1 - y) if h > 0 else y  # BMP rows run bottom to top
        base = start + src_row * stride
        grid.append([0.114 * bmp[base + x * bpp] + 0.587 * bmp[base + x * bpp + 1] + 0.299 * bmp[base + x * bpp + 2]
                     for x in range(w)])
    return grid


def original_brightness(name, cols, rows):
    with open(os.path.join(ORIGINAL, name + ".png"), "rb") as f:
        w, h, pixels, palette = read_png_indexed(f.read())
    lum = [0.299 * r + 0.587 * g + 0.114 * b for r, g, b in palette]
    grid = []
    for Y in range(rows):
        y0, y1 = Y * h // rows, max(Y * h // rows + 1, (Y + 1) * h // rows)
        row = []
        for X in range(cols):
            x0, x1 = X * w // cols, max(X * w // cols + 1, (X + 1) * w // cols)
            v = [lum[pixels[y * w + x]] for y in range(y0, y1) for x in range(x0, x1)]
            row.append(sum(v) / len(v))
        grid.append(row)
    return grid


def framing(name, path, width, height):
    cols = GRID
    rows = round(GRID * height / width)
    new = small_brightness(path, cols, rows)
    old = original_brightness(name, cols, rows)
    def diff(dx, dy):
        v = [abs(new[Y][X] - old[Y + dy][X + dx])
             for Y in range(SHIFT, rows - SHIFT) for X in range(SHIFT, cols - SHIFT)]
        return sum(v) / len(v)
    results = sorted((diff(dx, dy), dx, dy) for dx in range(-SHIFT, SHIFT + 1) for dy in range(-SHIFT, SHIFT + 1))
    return results[0]


def target_size(name):
    for prefix, size in FIXED_TARGETS.items():
        if name.startswith(prefix):
            return size
    path = os.path.join(ORIGINAL, "4x3", name + ".png")
    if not os.path.exists(path):
        return None
    w, h, _, _ = png_header(path)
    return w * 12 // 5, h * 12 // 5


def check(name):
    path = os.path.join(MODERN, name + ".png")
    problems, notes = [], []
    if not os.path.exists(os.path.join(ORIGINAL, name + ".png")):
        return [f"no original named {name}.png (names must match artwork/original/)"], notes
    head = png_header(path)
    if head is None:
        return ["not a PNG file"], notes
    w, h, depth, ctype = head
    notes.append(f"{w}x{h}")
    if ctype == 3:
        problems.append("indexed colour (256 colours); save as full RGB (untick 'Smaller File (8-bit)')")
    elif ctype in (0, 4):
        problems.append("greyscale; save as RGB")
    if depth != 8:
        problems.append(f"{depth} bits per channel; save as 8-bit")
    if ctype == 6:
        if alpha_in_use(path):
            problems.append("has see-through pixels; flatten the picture before saving")
        else:
            notes.append("has an unused transparency channel (harmless)")
    target = target_size(name)
    if target is None:
        notes.append("no target size known for this picture (fonts: shape not yet checked)")
    elif (w, h) != target:
        problems.append(f"size {w}x{h}, should be {target[0]}x{target[1]}")
    if ctype in (2, 6):
        d, dx, dy = framing(name, path, w, h)
        notes.append(f"framing: best fit {'with no shift' if (dx, dy) == (0, 0) else f'shifted {dx},{dy} blocks'}, "
                     f"brightness differs by {d:.1f} of 255 on average")
        if (dx, dy) != (0, 0):
            problems.append(f"framing is off by about {dx},{dy} of {GRID} blocks across: check for cropping or padding")
        elif d > 25:
            problems.append("lines up, but looks very different from the original: check by eye")
    return problems, notes


def main(names):
    if not names:
        for root, _, files in os.walk(MODERN):
            for f in sorted(files):
                if f.lower().endswith(".png"):
                    names.append(os.path.relpath(os.path.join(root, f), MODERN)[:-4])
    bad = 0
    for name in sorted(names):
        name = name[:-4] if name.endswith(".png") else name
        problems, notes = check(name)
        print(f"{name}: {'OK' if not problems else 'PROBLEM'} ({'; '.join(notes)})")
        for p in problems:
            print(f"    - {p}")
        bad += bool(problems)
    print(f"{len(names)} checked, {bad} with problems")
    return bad == 0


if __name__ == "__main__":
    sys.exit(0 if main(sys.argv[1:]) else 1)
