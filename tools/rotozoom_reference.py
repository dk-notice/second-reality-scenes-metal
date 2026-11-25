#!/usr/bin/env python3
"""Reference for the Rotozoomer (part 3 of the lens part, LENS/MAIN.C + LENS/ASM.ASM `_rotate`, Psi).

What it does:
  1. Works out the camera path from the formulas in MAIN.C's `#ifdef SAVEPATH` branch (with Microsoft
     C's rules: doubles truncated to int on assignment, int / 16 truncated towards zero) and checks all
     2000 steps against the path the demo really played, `LENS/LENS.EXP` (pathdata2).
  2. Builds the 256x256 picture tile (`rotpic`) and its turned copy (`rotpic90`) from LENS.EXB exactly
     as MAIN.C does.
  3. Carries out `_rotate` register by register (a line-by-line transliteration of the assembly, with
     16-bit and 32-bit wrap-around, the 24-bit negation and the 8-bit add-with-carry chains), giving
     the 160x100 screen of colour numbers.
  4. Prints CRC-32 checksums of the 1993 picture (red, green, blue bytes, 0...255 = round(v*255/63))
     at the steps the app's self-test checks, faded as part3() sets the palette.

The routine patches numbers into its own instructions (self-modifying code); here those numbers are
kept in a list instead. This is NOT the assembly run by an interpreter: tools/x86interp.py cannot run
code that rewrites itself. It is a second, independent working of the same instructions.

Usage: tools/rotozoom_reference.py [path to ../secondreality]   (default ../secondreality)
       tools/rotozoom_reference.py --png <step> <file.png>        (one 1993 picture, 160x100)
Development tool only; the app does not use it.
"""
import math, os, struct, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'secondreality')
if not os.path.isdir(SRC):
    SRC = os.path.join(HERE, '..', '..', '..', '..', '..', 'secondreality')   # from inside a worktree
STEPS = [0, 1, 7, 14, 15, 16, 100, 270, 500, 777, 1000, 1300, 1600, 1871, 1872, 1873, 1900, 1990, 1999]


def tr(v):
    return int(v)          # C: double -> int truncates towards zero


def path_from_formulas():
    out = []
    d1, d2, d3, scale, scalea = 0.0, 0.00007654321, 0.0, 2.0, -0.01
    for frame in range(2000):
        x = 70.0 * math.sin(d1) - 30
        y = 70.0 * math.cos(d1) + 60
        d1 -= .005
        xa = tr(-1024.0 * math.sin(d2) * scale)
        ya = tr(1024.0 * math.cos(d2) * scale)
        x = tr(x) - tr(xa / 16)
        y = tr(y) - tr(ya / 16)
        d2 += d3
        out.append((x, y, xa, ya))
        scale += scalea
        if frame > 25:
            if d3 < .02: d3 += 0.00005
        if frame < 270:
            if scale < .9:
                if scalea < 1: scalea += 0.0001
        elif frame < 400:
            if scalea > 0.001: scalea -= 0.0001
        elif frame > 1600:
            if scalea > -.1: scalea -= 0.001
        elif frame > 1100:
            a = min(frame - 900, 100)
            if scalea < 256: scalea += 0.000001 * a
    return out


def path_from_file():
    d = open(os.path.join(SRC, 'LENS', 'LENS.EXP'), 'rb').read()
    start2 = struct.unpack('<h', d[2:4])[0]
    ints = struct.unpack('<%dh' % ((len(d) - 4) // 2), d[4:])
    p2 = ints[start2:]
    return [tuple(p2[4 * i:4 * i + 4]) for i in range(len(p2) // 4)]


def load_picture():
    d = open(os.path.join(SRC, 'LENS', 'LENS.EXB'), 'rb').read()
    palette = list(d[16:16 + 768])
    back = d[784:784 + 64000]
    rotpic = bytearray(65536)
    for x in range(256):
        for y in range(256):
            a = y * 10 // 11 - 36 // 2
            if a < 0 or a > 199: a = 0
            rotpic[x + y * 256] = back[x + 32 + a * 320]
    rotpic90 = bytearray(65536)
    for x in range(256):
        for y in range(256):
            rotpic90[x + y * 256] = rotpic[y + (255 - x) * 256]
    return palette, rotpic, rotpic90


M32, M16 = 0xFFFFFFFF, 0xFFFF


def rotate(x, y, xa, ya, rotpic, rotpic90):
    """_rotate(x, y, xa, ya): the 160x100 screen of colour numbers, row by row."""
    xpos = (x & M16) << 16
    ypos = (y & M16) << 16
    def cwde_shl6(v):                    # mov ax,[..]; cwde; shl eax,6
        v &= M16
        if v & 0x8000: v -= 0x10000
        return (v << 6) & M32
    ebx = cwde_shl6(ya)
    eax = cwde_shl6(xa)
    ecx, edx = eax, ebx
    tex = rotpic
    def s32(v): return v - (1 << 32) if v & 0x80000000 else v
    if s32(ecx) < 0: ecx = (-s32(ecx)) & M32
    if s32(edx) < 0: edx = (-s32(edx)) & M32
    if s32(ecx) > s32(edx):              # cmp ecx,edx / jle: signed
        tex = rotpic90
        eax, ebx = ebx, eax
        eax = (-eax) & M32
        ecx, edx = xpos, ypos
        ecx, edx = edx, ecx
        ecx = (-ecx) & M32
        xpos, ypos = ecx, edx
    xadd, yadd = eax, ebx
    # Column table (the self-modified offsets).
    cx = yadd & M16                      # mov cx,word ptr yadd[0]
    dx = xadd & M16                      # mov dx,word ptr xadd[0]
    bl = (yadd >> 16) & 0xFF
    bh = (xadd >> 16) & 0xFF
    bh = (-bh) & 0xFF                    # neg bh
    borrow = 1 if dx != 0 else 0         # neg dx sets carry when dx was not 0
    dx = (-dx) & M16
    bh = (bh - borrow) & 0xFF            # sbb bh,0
    si = di = 0
    al = ah = 0
    offsets = []
    for _ in range(160):
        t = si + cx; si = t & M16; c = t >> 16
        al = (al + bl + c) & 0xFF        # adc al,bl (its carry out is overwritten next)
        t = di + dx; di = t & M16; c = t >> 16
        ah = (ah + bh + c) & 0xFF        # adc ah,bh
        offsets.append(al | (ah << 8))
    # The patched numbers: block g of the REPT (zzz = 13g) patches moda+zzz+2 and +6 (the "mov al" and
    # "mov ah" of moda's block g) with entries 4g and 4g+2, modb's with 4g+1 and 4g+3. moda's block g
    # writes address 2g (al) and 2g+1 (ah) with planes 0-1 on, modb's the same addresses with planes 2-3.
    # Address n shows pixels 4n...4n+3, so the 2-pixel-wide screen columns get entries 0, 1, 2, ... in
    # order: column c uses entry c.
    # Aspect: eax = 307 * xadd (mul: unsigned 32x32, low 32 bits kept), sar 8.
    def aspect(v):
        lo = (307 * v) & M32
        return (s32(lo) >> 8) & M32
    xadd = aspect(xadd)
    yadd = aspect(yadd)
    screen = bytearray(160 * 100)
    for row in range(100):
        ypos = (ypos + yadd) & M32
        b = (ypos >> 8) & M32
        xpos = (xpos + xadd) & M32
        a = (xpos >> 16) & M32
        bx = (b & 0xFF00) | (a & 0xFF)   # mov bl,al
        si = bx & M16
        for c in range(160):
            screen[row * 160 + c] = tex[(si + offsets[c]) & M16]   # 16-bit address: x carries into y
    return screen


def palette_at(palette, step):
    """The 64 colours (6-bit levels) showing at `step`: path[step] drawn, then frame = step + 1."""
    frame = step + 1
    base = palette[:192]
    if frame < 16:
        return [min(v + (15 - frame) * 5, 63) for v in base]
    if frame > 2000 - 128:
        a = min((frame - (2000 - 128)) // 2, 63)
        return [(v * (63 - a) + a * 63) // 63 for v in base]
    return base


def picture(step, path, palette, rotpic, rotpic90):
    screen = rotate(*path[step], rotpic, rotpic90)
    pal = palette_at(palette, step)
    rgb = bytearray()
    for c in screen:
        rgb += bytes(round(pal[3 * c + i] * 255 / 63) for i in range(3))
    return rgb


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
    path = path_from_formulas()
    played = path_from_file()
    same = sum(1 for a, b in zip(path, played) if a == b)
    print(f'path: {len(played)} steps in LENS.EXP, {same} equal to the formulas')
    palette, rotpic, rotpic90 = load_picture()
    print(f'picture: colours used {max(rotpic) + 1}; rotpic crc {zlib.crc32(rotpic)}; rotpic90 crc {zlib.crc32(rotpic90)}')
    turned = [s for s, (x, y, xa, ya) in enumerate(played) if abs(xa) > abs(ya)]
    print(f'turned copy used on {len(turned)} steps' + (f', first {turned[0]}' if turned else ''))
    if png:
        write_png(png[1], 160, 100, picture(png[0], played, palette, rotpic, rotpic90))
        return
    sums = [zlib.crc32(picture(s, played, palette, rotpic, rotpic90)) for s in STEPS]
    print('steps', STEPS)
    print('crc32', sums)


if __name__ == '__main__':
    main()
