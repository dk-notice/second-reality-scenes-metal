"""Readers for the picture formats used by Second Reality (1993), and a PNG writer.

Development-only, standard library only. Every reader returns a Picture: width, height,
pixels (one colour number per pixel, row by row) and palette (256 x (r, g, b), 0...255).

Formats:
- UH  ("Uh1"):  16-byte header (magic, width, height), 768 palette bytes, raw pixels.
- FCFC:        raw pixels; header words: magic FCFC, width, height, colours, offset of the
                pixels in 16-byte units. Palette (colours x 3 bytes) at byte 16.
- FDFC (bytes FD FC):  the same header, pixels packed row by row (each row: byte count, then
                runs; a byte with the top bit set repeats the next byte that many (& 0x7F)
                times). This is READP.C's format, used by the .UP files and some .UH files.
- RIX3 (.SCI, .CLX): "RIX3", width, height, 2 more bytes, 768 palette bytes, raw pixels.
- LBM (Deluxe Paint, IFF): "PBM " (one byte per pixel) or "ILBM" (bit planes), with
                ByteRun1 packing. Documented format (Electronic Arts, 1985).
Palettes in all but LBM are VGA numbers 0...63; they are scaled to 0...255 here.
Containers: .OBK (a linked object file) and .INC ("db 1,2,3" text) hold copies of
files; obk_data() and inc_data() take the file's bytes back out.
"""

import re
import struct
import zlib


class FormatError(Exception):
    pass


class Picture:
    def __init__(self, width, height, pixels, palette, colours=256):
        if len(pixels) != width * height:
            raise FormatError(f"{width}x{height} needs {width * height} pixels, got {len(pixels)}")
        self.width, self.height = width, height
        self.pixels = bytes(pixels)
        pal = list(palette)[:256]
        pal += [(0, 0, 0)] * (256 - len(pal))
        self.palette = pal
        self.colours = colours  # how many palette entries the file itself stores

    def used_colours(self):
        return sorted(set(self.pixels))


def vga(v):
    """A VGA palette number (0...63) as 0...255."""
    return (min(v, 63) * 255 + 31) // 63


def vga_palette(data, count=256):
    return [(vga(data[i * 3]), vga(data[i * 3 + 1]), vga(data[i * 3 + 2])) for i in range(count)]


def words(data, offset, count):
    return struct.unpack_from("<" + "H" * count, data, offset)


# ---------------------------------------------------------------- the demo's own formats

def read_uh(data):
    if data[:3] != b"Uh1":
        raise FormatError("not a Uh1 file")
    w, h = words(data, 4, 2)
    return Picture(w, h, data[784:784 + w * h], vga_palette(data[16:784]))


def read_fcfc(data):
    magic, w, h, cols, add = words(data, 0, 5)
    if magic != 0xFCFC:
        raise FormatError("not an FCFC file")
    start = add * 16
    return Picture(w, h, data[start:start + w * h], vga_palette(data[16:16 + cols * 3], cols), cols)


def read_fdfc(data):
    """READP.C, row by row."""
    magic, w, h, cols, add = words(data, 0, 5)
    if magic != 0xFCFD:
        raise FormatError("not an FDFC file")
    pos = add * 16
    out = bytearray()
    for _ in range(h):
        count = words(data, pos, 1)[0]
        pos += 2
        end = pos + count
        row = bytearray()
        while pos < end:
            a = data[pos]; pos += 1
            if a & 0x80:
                row += bytes([data[pos]]) * (a & 0x7F); pos += 1
            else:
                row.append(a)
        # The packer can run past a row's end (HZPIC.P: 756 for 640); READP.C writes the
        # extra into the next bytes of its buffer, which the programs never show.
        if len(row) < w:
            raise FormatError(f"row {len(out) // w} unpacks to {len(row)} pixels, not {w}")
        out += row[:w]
    return Picture(w, h, out, vga_palette(data[16:16 + cols * 3], cols), cols)


def read_rix(data, height=None):
    if data[:4] != b"RIX3":
        raise FormatError("not a RIX3 file")
    w, h = words(data, 4, 2)
    if height is not None:
        h = height
    elif 778 + w * h > len(data):
        # MIEKKA.SCI says 400x250 (copied from SWORD.SCI) but holds 400x35.
        h = (len(data) - 778) // w
    return Picture(w, h, data[778:778 + w * h], vga_palette(data[10:778]))


def read_any(data, **options):
    if data[:3] == b"Uh1":
        return read_uh(data)
    if data[:4] == b"RIX3":
        return read_rix(data, **options)
    if data[:4] == b"FORM":
        return read_lbm(data)
    magic = words(data, 0, 1)[0]
    if magic == 0xFCFC:
        return read_fcfc(data)
    if magic == 0xFCFD:
        return read_fdfc(data)
    raise FormatError("unknown picture format")


# ---------------------------------------------------------------- Deluxe Paint LBM

def byterun1(data, pos, length):
    """Unpack `length` bytes of ByteRun1 starting at pos. Returns (bytes, new pos)."""
    out = bytearray()
    while len(out) < length:
        n = data[pos]; pos += 1
        if n < 128:
            out += data[pos:pos + n + 1]; pos += n + 1
        elif n > 128:
            out += bytes([data[pos]]) * (257 - n); pos += 1
        # 128: no operation
    if len(out) != length:
        raise FormatError("a packed row runs past its end")
    return out, pos


def read_lbm(data):
    if data[:4] != b"FORM" or data[8:12] not in (b"PBM ", b"ILBM"):
        raise FormatError("not a PBM/ILBM file")
    kind = data[8:12]
    pos, end = 12, 8 + struct.unpack_from(">I", data, 4)[0]
    chunks = {}
    while pos + 8 <= min(end, len(data)):
        name = data[pos:pos + 4]
        size = struct.unpack_from(">I", data, pos + 4)[0]
        chunks.setdefault(name, data[pos + 8:pos + 8 + size])
        pos += 8 + size + (size & 1)
    hd = chunks.get(b"BMHD")
    body = chunks.get(b"BODY")
    if hd is None or body is None:
        raise FormatError("BMHD or BODY missing")
    w, h = struct.unpack_from(">HH", hd, 0)
    planes, masking, compression = hd[8], hd[9], hd[10]
    cmap = chunks.get(b"CMAP", b"")
    palette = [tuple(cmap[i:i + 3]) for i in range(0, len(cmap) - 2, 3)]
    cols = len(palette)
    out = bytearray()
    p = 0

    def take(n):
        nonlocal p
        if compression == 1:
            row, p = byterun1(body, p, n)
            return row
        if compression != 0:
            raise FormatError(f"unknown compression {compression}")
        row = body[p:p + n]; p += n
        return row

    if kind == b"PBM ":
        if planes != 8:
            raise FormatError(f"PBM with {planes} planes")
        rowbytes = w + (w & 1)
        for _ in range(h):
            out += take(rowbytes)[:w]
    else:
        rowbytes = ((w + 15) // 16) * 2
        for _ in range(h):
            plane_rows = [take(rowbytes) for _ in range(planes)]
            if masking == 1:
                take(rowbytes)
            for x in range(w):
                byte, bit = x >> 3, 7 - (x & 7)
                v = 0
                for i, r in enumerate(plane_rows):
                    v |= ((r[byte] >> bit) & 1) << i
                out.append(v)
    return Picture(w, h, out, palette, cols)


# ---------------------------------------------------------------- containers

def obk_data(data):
    """The data bytes of an object file made by BINOBJ/DOOBJ (.OBK, .OBJ): every LEDATA
    record, segment by segment in order, offsets respected."""
    pos = 0
    segments = {}
    order = []
    while pos + 3 <= len(data):
        kind = data[pos]
        length = struct.unpack_from("<H", data, pos + 1)[0]
        body = data[pos + 3:pos + 3 + length - 1]  # without the checksum byte
        if kind in (0xA0, 0xA1):
            seg = body[0]; q = 1
            if seg & 0x80:
                seg = ((seg & 0x7F) << 8) | body[1]; q = 2
            if kind == 0xA0:
                off = struct.unpack_from("<H", body, q)[0]; q += 2
            else:
                off = struct.unpack_from("<I", body, q)[0]; q += 4
            if seg not in segments:
                segments[seg] = bytearray(); order.append(seg)
            buf = segments[seg]
            chunk = body[q:]
            if len(buf) < off + len(chunk):
                buf += bytes(off + len(chunk) - len(buf))
            buf[off:off + len(chunk)] = chunk
        elif kind in (0xA2, 0xA3):
            raise FormatError("iterated data records are not supported")
        pos += 3 + length
    return b"".join(bytes(segments[s]) for s in order)


def inc_data(text):
    """The bytes of an INCBIN-style .INC file ("db 252,252,128,...")."""
    out = bytearray()
    for line in text.splitlines():
        m = re.match(r"\s*(?:\w+\s+)?db\s+(.*)", line, re.IGNORECASE)
        if not m:
            continue
        for item in m.group(1).split(";")[0].split(","):
            item = item.strip()
            if not item:
                continue
            if item.lower().endswith("h"):
                out.append(int(item[:-1], 16) & 0xFF)
            else:
                out.append(int(item) & 0xFF)
    return bytes(out)


# ---------------------------------------------------------------- PNG

def _png(width, height, colour_type, rows, plte=None, srgb=False):
    def chunk(name, payload):
        c = name + payload
        return struct.pack(">I", len(payload)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    raw = b"".join(b"\0" + r for r in rows)
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, colour_type, 0, 0, 0))
    if srgb:  # "these colours are sRGB" (rendering intent 0), so editors need not ask
        out += chunk(b"sRGB", b"\0")
    if plte is not None:
        out += chunk(b"PLTE", plte)
    out += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    return out


def png_indexed(pic):
    """Exact: the colour numbers themselves, with the palette. Every program reads it."""
    plte = b"".join(bytes(c) for c in pic.palette)
    rows = [pic.pixels[y * pic.width:(y + 1) * pic.width] for y in range(pic.height)]
    return _png(pic.width, pic.height, 3, rows, plte)


def png_scaled(pic, sx, sy):
    """RGB, each pixel repeated sx times across and sy times down (no smoothing)."""
    lut = [bytes(c) for c in pic.palette]
    rows = []
    for y in range(pic.height):
        line = b"".join(lut[v] * sx for v in pic.pixels[y * pic.width:(y + 1) * pic.width])
        rows += [line] * sy
    return _png(pic.width * sx, pic.height * sy, 2, rows)


def png_rgb(pic):
    """Full colour (8 bits per channel), marked as sRGB: ready for photo editors and upscalers."""
    lut = [bytes(c) for c in pic.palette]
    rows = [b"".join(lut[v] for v in pic.pixels[y * pic.width:(y + 1) * pic.width]) for y in range(pic.height)]
    return _png(pic.width, pic.height, 2, rows, srgb=True)


def read_png_written(data):
    """Reads back a PNG this module wrote (no row filters). Returns (width, height, colour
    type, pixel bytes, palette or None, has sRGB chunk)."""
    pos = 8
    idat = b""; plte = None; w = h = ctype = 0; srgb = False
    while pos < len(data):
        n = struct.unpack_from(">I", data, pos)[0]
        name = data[pos + 4:pos + 8]; body = data[pos + 8:pos + 8 + n]
        if name == b"IHDR":
            w, h = struct.unpack_from(">II", body, 0); ctype = body[9]
        elif name == b"PLTE":
            plte = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif name == b"sRGB":
            srgb = True
        elif name == b"IDAT":
            idat += body
        pos += 12 + n
    raw = zlib.decompress(idat)
    stride = w * (3 if ctype == 2 else 1)
    if any(raw[y * (stride + 1)] for y in range(h)):
        raise FormatError("row filters are not supported here")
    pixels = b"".join(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)] for y in range(h))
    return w, h, ctype, pixels, plte, srgb


def read_png_indexed(data):
    """Reads back what png_indexed wrote (for checking). Returns (width, height, pixels, palette)."""
    pos = 8
    idat = b""; plte = b""; w = h = 0
    while pos < len(data):
        n = struct.unpack_from(">I", data, pos)[0]
        name = data[pos + 4:pos + 8]; body = data[pos + 8:pos + 8 + n]
        if name == b"IHDR":
            w, h = struct.unpack_from(">II", body, 0)
        elif name == b"PLTE":
            plte = body
        elif name == b"IDAT":
            idat += body
        pos += 12 + n
    raw = zlib.decompress(idat)
    pixels = b"".join(raw[y * (w + 1) + 1:(y + 1) * (w + 1)] for y in range(h))
    return w, h, pixels, [tuple(plte[i:i + 3]) for i in range(0, len(plte), 3)]
