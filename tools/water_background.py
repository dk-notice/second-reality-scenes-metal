#!/usr/bin/env python3
"""Second Reality part 13 (WATER): the Modern look's background, ray-traced again from the original
scene file WATER/KK.POV with POV-Ray 3.7, at 8 times the original's 320x200.

Written from what was measured on 2026-11-25 (see docs/scenes/water-scroller.md):

  - WATER/DATA.TGA is a raw POV-Ray 1.0 output of the scene at 160x100. Its pixel (x, y) equals the
    shipped background's pixel (2x, 2y+1) to the palette's steps: the picture was not retouched, so
    every difference from a POV-Ray 3.7 render is 1.0 against 3.7. Two things differ:
  - FOG. The scene has black fog. POV-Ray 3.7 leaves fog out while the camera is inside a solid
    object, and the sky (a plane at y = 140) counts everything below it as inside. `hollow` on that
    plane brings the fog back.
  - SAMPLE POINTS. POV-Ray 1.0 took each pixel's sample at its lower left corner, 3.7 at its centre.
    The camera is written out as its vectors (what `look_at` works out; byte for byte the same
    picture) with its direction nudged half an original pixel left and half down. Each original pixel
    is then the middle of an 8x8 block of this picture, which is where the scene's sword map and masks
    take it to be.

The scene text is changed by exactly those two edits; each must apply exactly once or the tool stops.

Usage: tools/water_background.py                     compare Data/Water/BACKGROUND-POVRAY.png with the
                                                     original background (the numbers the self-test uses)
       tools/water_background.py --render            make the picture again (needs POV-Ray 3.7:
                                                     `povray` on the PATH or in /opt/homebrew/bin)
       [path to ../secondreality] may follow either.
Development tool only: the app and build.sh never run POV-Ray; they use the PNG in Data/Water.
"""
import hashlib, math, os, re, shutil, struct, subprocess, sys, tempfile, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'secondreality')
if not os.path.isdir(SRC):
    SRC = os.path.join(HERE, '..', '..', '..', '..', '..', 'secondreality')   # from inside a worktree
OUT = os.path.join(HERE, '..', 'Data', 'Water', 'BACKGROUND-POVRAY.png')

SCALE = 8                       # times the original's 320x200: the size Super-xBR made before
WIDTH, HEIGHT = 320 * SCALE, 200 * SCALE
NUDGE = (-0.5, 0.5)             # sample points moved, in ORIGINAL pixels: right, down
# Edge smoothing: up to 3x3 samples in a pixel wherever neighbours differ by more than 0.1.
ANTIALIAS = ('+A0.1', '+AM2', '+R3')

LOCATION, LOOK_AT, RIGHT_LENGTH = (10.0, 50.0, -50.0), (0.0, 0.0, 0.0), 1.33   # KK.POV; 1.33 is the default
SKY = '   plane { <0.0 1.0 0.0> 140.0 }\n'


def camera(nudge):
    """KK.POV's camera as explicit vectors (POV-Ray's own look_at arithmetic), direction nudged."""
    d = [LOOK_AT[i] - LOCATION[i] for i in range(3)]
    n = math.sqrt(sum(c * c for c in d))
    direction = [c / n for c in d]
    r = (direction[2], 0.0, -direction[0])                       # sky <0 1 0> x direction
    n = math.sqrt(sum(c * c for c in r))
    unit_right = [c / n for c in r]
    right = [c * RIGHT_LENGTH for c in unit_right]
    up = [direction[1] * unit_right[2] - direction[2] * unit_right[1],
          direction[2] * unit_right[0] - direction[0] * unit_right[2],
          direction[0] * unit_right[1] - direction[1] * unit_right[0]]
    # A ray is direction + (x/320 - 1/2) right + (1/2 - y/200) up: moving the samples is moving direction.
    nudged = [direction[i] + nudge[0] / 320 * right[i] - nudge[1] / 200 * up[i] for i in range(3)]
    v = lambda a: '<%.12f %.12f %.12f>' % tuple(a)
    return 'camera {\n   location %s\n   direction %s\n   up %s\n   right %s\n}\n' % (v(LOCATION), v(nudged), v(up), v(right))


def scene_text(src, nudge=NUDGE, fog=True):
    text = open(os.path.join(src, 'WATER', 'KK.POV'), newline='').read().replace('\r', '').replace('\x1a', '')
    text, count = re.subn(r'camera \{\n   location <10 50 -50>\n   look_at <0 0 0>\n\}\n', lambda m: camera(nudge), text)
    assert count == 1, 'KK.POV: the camera is not where it was'
    if fog:
        assert text.count(SKY) == 1, 'KK.POV: the sky plane is not where it was'
        text = text.replace(SKY, SKY + '   hollow\n')
    return text


def povray():
    for candidate in (shutil.which('povray'), '/opt/homebrew/bin/povray'):
        if candidate and os.path.exists(candidate):
            return candidate
    sys.exit('POV-Ray is not installed (brew install povray). It is needed only to make the picture again.')


def render(src, width=WIDTH, height=HEIGHT, antialias=ANTIALIAS, **changes):
    """The scene's red, green, blue bytes, row by row."""
    with tempfile.TemporaryDirectory() as folder:
        for name in ('COLORS.INC', 'SHAPES.INC'):
            shutil.copy(os.path.join(src, 'WATER', name), os.path.join(folder, name.lower()))
        open(os.path.join(folder, 'textures.inc'), 'w').close()    # POV-Ray 1.0's is not in the release; nothing of it is used
        open(os.path.join(folder, 'kk.pov'), 'w').write(scene_text(src, **changes))
        done = subprocess.run([povray(), '+Ikk.pov', '+Okk.ppm', '+FP', f'+W{width}', f'+H{height}', '+MV1.0', '-D', '-GA',
                               '+L.'] + (list(antialias) if antialias else ['-A']), cwd=folder, capture_output=True, text=True)
        path = os.path.join(folder, 'kk.ppm')
        if done.returncode != 0 or not os.path.exists(path):
            sys.exit('POV-Ray failed:\n' + done.stderr[-2000:])
        data = open(path, 'rb').read()
    pixels = data[-width * height * 3:]
    assert data[:2] == b'P6' and data[:-len(pixels)].split()[-3:] == [b'%d' % width, b'%d' % height, b'255']
    return pixels


def png(width, height, rgb):
    def chunk(name, payload):
        c = name + payload
        return struct.pack('>I', len(payload)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
    raw = b''.join(b'\0' + rgb[y * width * 3:(y + 1) * width * 3] for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def read_png(data):
    """Only what `png` writes."""
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    p, idat, size = 8, b'', None
    while p < len(data):
        length, name = struct.unpack_from('>I4s', data, p)
        body = data[p + 8:p + 8 + length]
        if name == b'IHDR':
            size = struct.unpack_from('>II', body)
            assert body[8:] == b'\x08\x02\0\0\0'
        elif name == b'IDAT':
            idat += body
        p += 12 + length
    width, height = size
    raw = zlib.decompress(idat)
    rows = []
    for y in range(height):
        line = raw[y * (width * 3 + 1):(y + 1) * (width * 3 + 1)]
        assert line[0] == 0
        rows.append(line[1:])
    return width, height, b''.join(rows)


def original(src):
    """The shipped background's colours as bytes (VGA level x 255 / 63, rounded as the app does)."""
    bkg = open(os.path.join(src, 'WATER', 'BKG.CLX'), 'rb').read()
    palette = open(os.path.join(src, 'WATER', 'MIEKKA.SCI'), 'rb').read()[10:778]
    return [tuple(int(palette[3 * n + c] * 255 / 63 + 0.5) for c in range(3)) for n in bkg[778:778 + 64000]]


def block_means(width, height, rgb, scale):
    out = []
    for y in range(0, height, scale):
        sums = [0] * (width // scale * 3)
        for row in range(y, y + scale):
            line = rgb[row * width * 3:(row + 1) * width * 3]
            for c in range(3):
                channel = line[c::3]
                for x in range(width // scale):
                    sums[3 * x + c] += sum(channel[x * scale:(x + 1) * scale])
        out += [tuple(sums[3 * x + c] / scale / scale for c in range(3)) for x in range(width // scale)]
    return out


def within(small, orig, dx=0, dy=0):
    """Of the pixels both have when `small` is moved (dx, dy): how many differ by at most 8, 16, 32 (of 255)
    in every channel, and how many were compared."""
    counts, compared = [0, 0, 0], 0
    for y in range(max(0, dy), min(200, 200 + dy)):
        for x in range(max(0, dx), min(320, 320 + dx)):
            a, b = small[(y - dy) * 320 + x - dx], orig[y * 320 + x]
            worst = max(abs(a[c] - b[c]) for c in range(3))
            compared += 1
            for k, limit in enumerate((8, 16, 32)):
                counts[k] += worst <= limit
    return counts, compared


def report(src):
    data = open(OUT, 'rb').read()
    width, height, rgb = read_png(data)
    print(f'{os.path.relpath(OUT)}: {width}x{height}, {len(data)} bytes, CRC-32 {zlib.crc32(data) & 0xFFFFFFFF}, SHA-256 {hashlib.sha256(data).hexdigest()}')
    small, orig = block_means(width, height, rgb, width // 320), original(src)
    print('each 8x8 block\'s mean against the original background (every channel within 8 / 16 / 32 of 255):')
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        counts, compared = within(small, orig, dx, dy)
        where = 'in place' if (dx, dy) == (0, 0) else f'moved {dx:+d} across, {dy:+d} down'
        print(f'  {where:26s} ' + '  '.join(f'{100 * c / compared:5.1f}%' for c in counts) + f'   of {compared}')


def main():
    arguments = [a for a in sys.argv[1:] if not a.startswith('--')]
    src = arguments[0] if arguments else SRC
    if '--render' in sys.argv:
        rgb = render(src)
        open(OUT, 'wb').write(png(WIDTH, HEIGHT, rgb))
    report(src)


if __name__ == '__main__':
    main()
