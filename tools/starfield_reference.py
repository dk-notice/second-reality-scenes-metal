#!/usr/bin/env python3
"""Reference pictures for the Hidden Starfield, made by running the ORIGINAL assembly.

This reads DDSTARS/STARS.ASM as text and carries out, one instruction at a time in the shared
interpreter (tools/x86interp.py), the routines that decide where every dot goes:

  random       the program's own random numbers
  init_stars   only its table set-up: the row table, the 1024 stars, the two perspective tables
  staradd      move 512 stars one step and add their dots to the current picture
  staradd2     the same for 1024 stars, each dot also put in the picture 17 places further on

What is NOT run from the original, and is written here in Python from reading do_stars instead:
the step counter and its marks (900, 1200, 1500), which picture of the ring is current (the original
fetched it from EMS memory with interrupt 67h; here the 64 pictures are simply 64 places in memory),
and the copy to the screen with the upside-down lower half. The text panels are left out.

It prints, for each step asked for, the CRC-32 checksum of the current 320x100 picture as one colour
number (0...3) per pixel, and of the whole 320x400 screen. Those are what App/SelfTest.swift expects
from StarfieldModel (`currentPicture` and `classicIndices()`). It also prints the perspective tables'
first entries and the first stars after the 100 unseen warm-up steps.

Usage:  python3 tools/starfield_reference.py [path-to-DDSTARS-folder] step [step ...]
        e.g. python3 tools/starfield_reference.py 1 900 1200 1500 1984     (takes a few minutes)

Development tool only; the app does not use it.
"""
import os, re, sys, zlib, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import x86interp as pc

args = sys.argv[1:]
SRC = os.path.join(HERE, '..', '..', 'secondreality', 'DDSTARS')
if args and not args[0].isdigit(): SRC = args.pop(0)
R, SG, F = pc.R, pc.SG, pc.F

# ----------------------------------------------------------------------------------------------
# Three instructions the shared interpreter does not have, and one it gets wrong for this code: a
# shift by a count of zero held in CL ("shr ch,cl" for a dot in the first column of a byte), which on
# a real processor changes nothing and in the interpreter stops with an error. They are added here, as
# tools/visu_reference.py does, so that the interpreter itself is not changed.
# ----------------------------------------------------------------------------------------------
pc.MASM_SRC = SRC
pc.install_masm_layer()
masm_compile = pc.compile_instruction

def compile_instruction(text, proc):
    parts = text.split(None, 1)
    op = parts[0]
    rest = parts[1] if len(parts) > 1 else ''
    if op == 'stosw':
        def f():
            pc.wr(SG['es'], R[7] & 0xFFFF, 2, R[0] & 0xFFFF)
            R[7] = (R[7] & 0xFFFF0000) | ((R[7] + 2) & 0xFFFF)
        return f
    if op == 'shr' and rest.replace(' ', '').endswith(',cl'):
        usual = masm_compile(text, proc)
        return lambda: usual() if R[1] & 31 else None
    if op in ('mul', 'div'):
        o = pc.parse_operand(rest, proc)
        if o['kind'] == 'mem': pc.finish(o, o['size'])
        size = o['size']
        if op == 'mul' and size == 4:              # edx:eax = eax * operand
            def f():
                p = R[0] * o['get']()
                R[0], R[2] = p & 0xFFFFFFFF, p >> 32
                F[0] = F[3] = 1 if R[2] else 0
            return f
        if op == 'div' and size == 2:              # ax = dx:ax / operand, dx = remainder
            def f():
                n = ((R[2] & 0xFFFF) << 16) | (R[0] & 0xFFFF)
                d = o['get']()
                q, r = divmod(n, d)
                if q > 0xFFFF: raise RuntimeError('divide overflow')
                R[0] = (R[0] & 0xFFFF0000) | q
                R[2] = (R[2] & 0xFFFF0000) | r
            return f
    return masm_compile(text, proc)

pc.compile_instruction = compile_instruction

# ----------------------------------------------------------------------------------------------
# Cut the wanted pieces out of the original source text and assemble them.
# ----------------------------------------------------------------------------------------------
CODE = 0x1000                      # segment for the code's own data (stars, tables)
def picture_segment(n):            # 64 pictures of 8192 bytes: plane 0 at offset 0, plane 1 at 4096
    return 0x2000 + (n & 63) * 0x200

def load():
    lines = pc.read_lines('STARS.ASM')
    def squash(s): return ' '.join(s.split()).lower()
    flat = [squash(l) for l in lines]
    def between(first, last):
        a = flat.index(first)
        b = flat.index(last, a)
        return lines[a:b + 1]
    text = between('starvram dw 0a000h', 'seed dd 0')              # the data
    text = ['STARS equ 512', 'STARS2 equ 1024'] + text
    text += between('random proc near', 'random endp')
    # init_stars from just after "call clearsbu" to where it sets the star limit: tables and stars.
    a = flat.index('call clearsbu') + 1
    b = flat.index('mov cs:starlimit,stars', a)
    text += ['init_tables PROC NEAR'] + lines[a:b + 1] + ['\tret', 'init_tables ENDP']
    text += between('staradd proc near', 'staradd endp')
    # staradd2 begins by fetching the picture 17 places on into FS; the driver below sets FS instead.
    body = between('staradd2 proc near', 'staradd2 endp')
    assert squash(body[1]) == 'call starfetch1'
    text += [body[0]] + body[2:]

    out = pc.translate(pc.expand_all(text, {}))
    folder = tempfile.mkdtemp()
    pc.SRC = folder
    open(os.path.join(folder, 'STARS.ASM'), 'w').write('\n'.join(out) + '\n')
    pc.assemble('STARS.ASM', CODE)

def asm(name):
    SG['cs'] = CODE
    pc.run(pc.code_labels[name])

def word(label, index=0):
    seg, off, _ = pc.labels[label]
    return pc.rd(seg, off + 2 * index, 2)

def picture(n):
    """Picture n of the ring as 320x100 colour numbers 0...3."""
    base = picture_segment(n) << 4
    out = bytearray(320 * 100)
    for row in range(100):
        for col in range(320):
            o = row * 40 + (col >> 3)
            bit = 0x80 >> (col & 7)
            out[row * 320 + col] = (1 if pc.M[base + o] & bit else 0) | (2 if pc.M[base + 4096 + o] & bit else 0)
    return bytes(out)

def screen(page):
    """do_stars' copy: the current picture on the even lines of the top half; the picture 32 places
    on, upside down, on the even lines of the bottom half. Odd lines are never written."""
    top, bottom = picture(page), picture(page + 32)
    out = bytearray(320 * 400)
    for row in range(100):
        out[(2 * row) * 320:(2 * row) * 320 + 320] = top[row * 320:row * 320 + 320]
        out[(200 + 2 * row) * 320:(200 + 2 * row) * 320 + 320] = bottom[(99 - row) * 320:(99 - row) * 320 + 320]
    return bytes(out)

def run(want):
    load()
    page = 0
    def fetch0():                                   # starfetch0
        nonlocal page
        page = (page + 1) & 63
        SG['es'] = picture_segment(page)
    asm('init_tables')
    print('muldivy[0..2], [255]:', [word('muldivy', i) for i in (0, 1, 2, 255)])
    print('muldivx[0..2], [255]:', [word('muldivx', i) for i in (0, 1, 2, 255)])
    for _ in range(100):                            # the end of init_stars: 100 unseen steps
        fetch0(); asm('staradd')
    print('first stars after warm-up [depth, x, y]:',
          [[word('star', 4 * i) & 255, pc.s16(word('star', 4 * i + 1)), pc.s16(word('star', 4 * i + 2))] for i in range(4)])
    limit = pc.labels['starlimit']
    for frame in range(1, max(want) + 1):           # do_stars, one pass of its loop
        if frame == 1500: pc.wr(limit[0], limit[1], 2, 1024)
        fetch0()
        if frame > 1200:
            SG['fs'] = picture_segment(page + 17)   # starfetch1
            asm('staradd2')
        elif frame <= 900:
            asm('staradd')
        if frame in want:
            print('step', frame, 'picture crc32', zlib.crc32(picture(page)), 'screen crc32', zlib.crc32(screen(page)), flush=True)

if __name__ == '__main__':
    if not args:
        print(__doc__); sys.exit(1)
    run(set(int(a) for a in args))
