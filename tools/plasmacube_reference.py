#!/usr/bin/env python3
"""Reference pictures for the Plasma Cube, made by running the ORIGINAL assembly.

The original scene (second half of PLZPART.EXE) is part C, part assembly:

  - PLZA.ASM   do_block (the textured line filler), do_clear (erasing the previous cube),
               shadepal (dimming a palette for the lighting)
  - SPLINE.ASM getspl (the flight path), with RATA.INC (path points) and SPLINE.INC (blend weights)
  - VECT.C and PLZFILL.C: rotation, projection, which faces show, edge walking, page flipping

This tool reads the two assembly files AS TEXT, expands their macros (IRP / REPT), and carries the
instructions out one at a time in a small x86 interpreter with a model of the VGA card's four bit
planes. The C parts are re-written here in Python, keeping C's 16- and 32-bit whole-number rules.
It prints CRC-32 checksums of the 320x134 screen (colour numbers) and of the palette at the steps
asked for; App/SelfTest.swift expects the same numbers from the Swift replay.

Usage:
  python3 tools/plasmacube_reference.py [--src PLZPART-folder] [--page 1|4] [--png] step [step ...]
  python3 tools/plasmacube_reference.py --tables      (prints Scenes/PlasmaCube/PlasmaCubeTables.swift)
  python3 tools/plasmacube_reference.py --range       (prints coordinate ranges over the whole run)

Steps are 1/70 s, counted as the app counts them: step t is the original's frame t - LEAD (the app
starts LEAD frames early, while the cube is still below the screen). --page chooses which of the six
page states the run starts in: 1 and 4 use the same video page but opposite 2-pixel offsets, and the
app shows the average of the two. Development tool only; the app does not use it.
"""
import re, sys, os, struct, zlib

LEAD = 16            # must match PlasmaCubeModel.leadIn
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'secondreality', 'PLZPART')

# ----------------------------------------------------------------------------------------------
# The machine: 1 MB of memory, the VGA's four planes, registers and flags.
# ----------------------------------------------------------------------------------------------
M = bytearray(1 << 20)
planes = [bytearray(65536) for _ in range(4)]
PM = [0x0F]                      # which planes a write to video memory reaches (sequencer register 2)
R = [0] * 8                      # eax ecx edx ebx esp ebp esi edi
SG = {'cs': 0, 'ds': 0, 'es': 0, 'fs': 0, 'gs': 0, 'ss': 0}
F = [0, 0, 0, 0]                 # carry, zero, sign, overflow
STACK = []
REG = {}
for i, n in enumerate(['ax', 'cx', 'dx', 'bx', 'sp', 'bp', 'si', 'di']):
    REG['e' + n] = (i, 0xFFFFFFFF, 0, 4)
    REG[n] = (i, 0xFFFF, 0, 2)
for i, n in enumerate('acdb'):
    REG[n + 'l'] = (i, 0xFF, 0, 1)
    REG[n + 'h'] = (i, 0xFF, 8, 1)

def rd8(seg, off):
    lin = ((seg << 4) + (off & 0xFFFF)) & 0xFFFFF
    if 0xA0000 <= lin < 0xB0000:
        return planes[0][lin - 0xA0000]
    return M[lin]

def wr8(seg, off, v):
    lin = ((seg << 4) + (off & 0xFFFF)) & 0xFFFFF
    if 0xA0000 <= lin < 0xB0000:
        o = lin - 0xA0000
        m = PM[0]
        for p in range(4):
            if m >> p & 1:
                planes[p][o] = v
    else:
        M[lin] = v

def rd(seg, off, size):
    v = 0
    for i in range(size):
        v |= rd8(seg, off + i) << (8 * i)
    return v

def wr(seg, off, size, v):
    for i in range(size):
        wr8(seg, off + i, (v >> (8 * i)) & 0xFF)

# ----------------------------------------------------------------------------------------------
# A small assembler for the subset of Turbo Assembler these two files use.
# ----------------------------------------------------------------------------------------------
labels = {}       # name -> (segment, offset, size)   data labels
code_labels = {}  # name -> index into `code`
code = []         # compiled instructions (Python closures)
source_of = []    # the text of each instruction, for error messages
fixups = []       # (segment, offset, label) for "dw OFFSET label"
proc_segment = {} # procedure name -> the segment its code lives in (the value of CS while it runs)
SIZES = {'byte': 1, 'word': 2, 'dword': 4, 'db': 1, 'dw': 2, 'dd': 4}
ARGSEG = 0x0800
arg_ptr = [0]

def number(tok):
    t = tok.lower()
    if t.endswith('h'): return int(t[:-1], 16)
    if t.endswith('b'): return int(t[:-1], 2)
    if t.endswith('d'): return int(t[:-1])
    return int(t)

NUM = re.compile(r'\b([0-9][0-9a-fA-F]*[hH]|[01]+[bB]|[0-9]+[dD]?)\b')

def evaluate(expr):
    """A constant expression: numbers in any base, + - * / and brackets."""
    e = NUM.sub(lambda m: str(number(m.group(1))), expr)
    if not re.fullmatch(r'[0-9+\-*/() \t]+', e):
        raise ValueError('not a constant: ' + expr)
    return int(eval(e.replace('/', '//')))

def expand(lines, folder):
    """Inline INCLUDE files and unroll IRP and REPT blocks."""
    out = []
    i = 0
    while i < len(lines):
        raw = lines[i].split(';')[0].rstrip()
        s = raw.strip()
        up = s.upper()
        m = re.match(r"INCLUDE\s+['\"](.+)['\"]", s, re.I)
        if m:
            text = open(os.path.join(folder, m.group(1).upper()), 'rb').read().decode('latin1')
            out += expand(text.replace('\r', '').split('\n'), folder)
            i += 1
            continue
        if up.startswith('IRP') or up.startswith('REPT'):
            depth, j = 1, i + 1
            while True:
                u = lines[j].split(';')[0].strip().upper()
                if u.startswith('IRP') or u.startswith('REPT'): depth += 1
                if u == 'ENDM':
                    depth -= 1
                    if depth == 0: break
                j += 1
            body = lines[i + 1:j]
            if up.startswith('REPT'):
                for _ in range(evaluate(s[4:])):
                    out += expand(body, folder)
            else:
                m = re.match(r'IRP\s+(\w+)\s*,\s*<(.*)>', s, re.I)
                name, values = m.group(1), [v.strip() for v in m.group(2).split(',')]
                for v in values:
                    sub = [re.sub(r'\b%s\b' % name, v, l.replace('&%s&' % name, v).replace('&' + name, v))
                           for l in body]
                    out += expand(sub, folder)
            i = j + 1
            continue
        if s: out.append(s)
        i += 1
    return out

def parse_operand(text, proc):
    """Returns a dict: kind 'reg' / 'seg' / 'imm' / 'mem', with what is needed to read or write it."""
    t = text.strip()
    low = t.lower()
    if low in REG:
        idx, mask, shift, size = REG[low]
        return {'kind': 'reg', 'size': size,
                'get': lambda: (R[idx] >> shift) & mask,
                'set': lambda v: R.__setitem__(idx, (R[idx] & ~(mask << shift) & 0xFFFFFFFF) | ((v & mask) << shift))}
    if low in SG:
        return {'kind': 'seg', 'size': 2, 'get': lambda: SG[low], 'set': lambda v: SG.__setitem__(low, v & 0xFFFF)}
    m = re.match(r'offset\s+(\w+)$', low)
    if m:
        off = labels[m.group(1)][1]
        return {'kind': 'imm', 'size': None, 'get': lambda: off}
    m = re.match(r'seg\s+(\w+)$', low)
    if m:
        seg = labels[m.group(1)][0]
        return {'kind': 'imm', 'size': None, 'get': lambda: seg}
    # MASM style "ds:[si+4]" or "cs:table[di+4]" becomes IDEAL style "[ds:si+4]" / "[cs:table+di+4]"
    m = re.match(r'^(?:(\w\w):)?(\w+)?\[(.*)\]$', t)
    if m and (m.group(1) or m.group(2)):
        t = '[' + (m.group(1) + ':' if m.group(1) else '') + (m.group(2) + '+' if m.group(2) else '') + m.group(3) + ']'
    if t.startswith('['):
        inner = t[1:-1].strip()
        size = None
        m = re.match(r'(byte|word|dword)\s+(.*)$', inner, re.I)
        if m:
            size, inner = SIZES[m.group(1).lower()], m.group(2)
        segreg = None
        m = re.match(r'(cs|ds|es|fs|gs|ss)\s*:\s*(.*)$', inner, re.I)
        if m:
            segreg, inner = m.group(1).lower(), m.group(2)
        regs, disp, label_seg = [], 0, None
        for sign, term in re.findall(r'([+-]?)\s*([^+-]+)', inner):
            term = term.strip()
            k = -1 if sign == '-' else 1
            if term.lower() in ('bx', 'si', 'di', 'bp'):
                regs.append(REG[term.lower()][0])
            elif term.lower() in labels:
                seg, off, lsize = labels[term.lower()]
                disp += k * off
                label_seg = seg
                if size is None: size = lsize
            else:
                disp += k * evaluate(term)
        if segreg is None and label_seg is None: segreg = 'ds'
        def address():
            off = disp
            for r in regs: off += R[r] & 0xFFFF
            return (SG[segreg] if segreg else label_seg), off & 0xFFFF
        op = {'kind': 'mem', 'size': size, 'addr': address}
        return op
    return {'kind': 'imm', 'size': None, 'get': (lambda v: (lambda: v))(evaluate(t))}

def finish(op, size):
    """Gives a memory operand its size once known and builds its get/set."""
    if op['kind'] == 'mem':
        op['size'] = size
        addr = op['addr']
        op['get'] = lambda: rd(*addr(), size)
        op['set'] = lambda v: wr(*addr(), size, v)
    return op

def flags_result(res, bits):
    F[1] = 1 if res == 0 else 0
    F[2] = (res >> (bits - 1)) & 1

def compile_instruction(text, proc):
    parts = text.split(None, 1)
    op = parts[0].lower()
    rest = parts[1] if len(parts) > 1 else ''
    def lab(name):
        name = name.strip()
        return (proc + name) if name.startswith('@@') else name

    if op in ('ret', 'retf'):
        return lambda: -1
    if op in ('push', 'pop'):
        ops = [parse_operand(a, proc) for a in rest.split()]
        if op == 'push':
            def f():
                for o in ops: STACK.append(o['get']())
        else:
            def f():
                for o in ops: o['set'](STACK.pop())
        return f
    if op == 'rep':
        assert rest.strip().lower() == 'stosb'
        def f():
            n = R[1] & 0xFFFF
            al, di, es = R[0] & 0xFF, R[7] & 0xFFFF, SG['es']
            for i in range(n): wr8(es, di + i, al)
            R[7] = (R[7] & 0xFFFF0000) | ((di + n) & 0xFFFF)
            R[1] &= 0xFFFF0000
        return f
    if op == 'lodsb':
        def f():
            R[0] = (R[0] & 0xFFFFFF00) | rd8(SG['ds'], R[6] & 0xFFFF)
            R[6] = (R[6] & 0xFFFF0000) | ((R[6] + 1) & 0xFFFF)
        return f
    if op == 'stosb':
        def f():
            wr8(SG['es'], R[7] & 0xFFFF, R[0] & 0xFF)
            R[7] = (R[7] & 0xFFFF0000) | ((R[7] + 1) & 0xFFFF)
        return f
    if op == 'cdq':
        def f(): R[2] = 0xFFFFFFFF if R[0] & 0x80000000 else 0
        return f
    if op == 'loop':
        name = lab(rest)
        def f():
            c = (R[1] - 1) & 0xFFFF
            R[1] = (R[1] & 0xFFFF0000) | c
            return code_labels[name] if c else None
        return f
    if op == 'jmp':
        if rest.strip().startswith('['):
            o = finish(parse_operand(rest, proc), 2)
            return lambda: o['get']()
        name = lab(rest)
        return lambda: code_labels[name]
    conditions = {
        'je': lambda: F[1], 'jz': lambda: F[1], 'jne': lambda: not F[1], 'jnz': lambda: not F[1],
        'jl': lambda: F[2] != F[3], 'jge': lambda: F[2] == F[3],
        'ja': lambda: not F[0] and not F[1], 'jb': lambda: F[0], 'jae': lambda: not F[0]}
    if op in conditions:
        cond, name = conditions[op], lab(rest)
        return lambda: code_labels[name] if cond() else None

    args = [a.strip() for a in rest.split(',')]
    ops = [parse_operand(a, proc) for a in args]

    if op == 'out':
        def f():
            if (R[2] & 0xFFFF) == 0x3C4 and args[1].lower() == 'ax' and (R[0] & 0xFF) == 2:
                PM[0] = (R[0] >> 8) & 0x0F
        return f
    if op in ('lds', 'les', 'lgs'):
        d, s = ops
        addr, seg = s['addr'], op[1:]
        def f():
            sg, off = addr()
            d['set'](rd(sg, off, 2))
            SG[seg] = rd(sg, off + 2, 2)
        return f
    if op in ('movzx', 'movsx'):
        d, s = ops
        if s['kind'] == 'mem': finish(s, s['size'] or 1)
        bits = s['size'] * 8
        if op == 'movzx':
            return lambda: d['set'](s['get']())
        def f():
            v = s['get']()
            d['set'](v - (1 << bits) if v >> (bits - 1) else v)
        return f
    if op in ('mul', 'imul', 'idiv', 'inc', 'dec'):
        o = ops[0]
        if o['kind'] == 'mem': finish(o, o['size'])
        size = o['size']
        bits, mask = size * 8, (1 << (size * 8)) - 1
        if op == 'mul':
            assert size == 1
            def f(): R[0] = (R[0] & 0xFFFF0000) | ((R[0] & 0xFF) * o['get']())
            return f
        if op == 'imul':
            assert size == 2
            def f():
                a, b = R[0] & 0xFFFF, o['get']()
                if a & 0x8000: a -= 65536
                if b & 0x8000: b -= 65536
                p = (a * b) & 0xFFFFFFFF
                R[0] = (R[0] & 0xFFFF0000) | (p & 0xFFFF)
                R[2] = (R[2] & 0xFFFF0000) | (p >> 16)
            return f
        if op == 'idiv':
            assert size == 4
            def f():
                n = (R[2] << 32) | R[0]
                if n >> 63: n -= 1 << 64
                d = o['get']()
                if d >> 31: d -= 1 << 32
                q = abs(n) // abs(d)
                if (n < 0) != (d < 0): q = -q
                R[0] = q & 0xFFFFFFFF
                R[2] = (n - q * d) & 0xFFFFFFFF
            return f
        k = 1 if op == 'inc' else -1
        def f():                                   # inc and dec leave the carry flag alone
            a = o['get']()
            res = (a + k) & mask
            o['set'](res)
            flags_result(res, bits)
            F[3] = 1 if res == ((1 << (bits - 1)) if k == 1 else (1 << (bits - 1)) - 1) else 0
        return f

    d, s = ops[0], ops[1]
    size = d['size'] or s['size']
    if op in ('shr', 'shl', 'rol'):
        size = d['size']
    finish(d, size)
    if s['kind'] == 'mem': finish(s, size)
    bits, mask = size * 8, (1 << (size * 8)) - 1
    dget, dset, sget = d['get'], d['set'], s['get']

    if op == 'mov':
        return lambda: dset(sget() & mask)
    if op == 'shld':
        n = ops[2]['get']()
        def f(): dset(((dget() << n) | (sget() >> (bits - n))) & mask)
        return f
    if op in ('add', 'adc'):
        carry = op == 'adc'
        def f():
            a, b = dget(), sget() & mask
            r = a + b + (F[0] if carry else 0)
            res = r & mask
            F[0] = r >> bits
            F[3] = ((~(a ^ b)) & (a ^ res)) >> (bits - 1) & 1
            flags_result(res, bits)
            dset(res)
        return f
    if op in ('sub', 'cmp'):
        store = op == 'sub'
        def f():
            a, b = dget(), sget() & mask
            r = a - b
            res = r & mask
            F[0] = 1 if r < 0 else 0
            F[3] = ((a ^ b) & (a ^ res)) >> (bits - 1) & 1
            flags_result(res, bits)
            if store: dset(res)
        return f
    if op in ('and', 'test', 'xor'):
        def f():
            a, b = dget(), sget() & mask
            res = (a ^ b) if op == 'xor' else (a & b)
            F[0] = F[3] = 0
            flags_result(res, bits)
            if op != 'test': dset(res)
        return f
    if op == 'shr':
        def f():
            a, n = dget(), sget()
            res = a >> n
            F[0] = (a >> (n - 1)) & 1
            flags_result(res, bits)
            dset(res)
        return f
    if op == 'shl':
        def f():
            a, n = dget(), sget()
            res = (a << n) & mask
            F[0] = (a >> (bits - n)) & 1
            flags_result(res, bits)
            dset(res)
        return f
    if op == 'rol':
        def f():
            a, n = dget(), sget()
            dset(((a << n) | (a >> (bits - n))) & mask)
        return f
    raise ValueError('instruction not supported: ' + text)

DIRECTIVES = ('IDEAL', 'MODEL', 'P386', 'ASSUME', 'PUBLIC', 'EXTRN', 'END', 'ENDS', 'ALIGN', 'MASM', 'ENDP')

def assemble(filename, segment):
    """Lays out the file's data in `segment` and compiles its instructions."""
    text = open(os.path.join(SRC, filename), 'rb').read().decode('latin1').replace('\r', '')
    lines = expand(text.split('\n'), SRC)
    equates = {}
    here = 0
    proc = ''
    pending = []   # instructions are compiled after all labels of the file are known
    for line in lines:
        m = re.match(r'^(\w+)\s*=\s*(.+)$', line)
        if m:
            e = m.group(2)
            for k, v in equates.items(): e = re.sub(r'\b%s\b' % k, str(v), e)
            equates[m.group(1)] = evaluate(e)
            continue
        for k, v in equates.items(): line = re.sub(r'\b%s\b' % k, str(v), line)
        first = line.split()[0].upper()
        if first in DIRECTIVES or first in ('SEGMENT', 'CODESEG'):
            continue
        m = re.match(r'LABEL\s+(\w+)\s+(\w+)', line, re.I)
        if m:
            labels[m.group(1).lower()] = (segment, here, SIZES[m.group(2).lower()])
            continue
        m = re.match(r'PROC\s+(?:C\s+)?(\w+)', line, re.I)
        if m:
            proc = m.group(1)
            proc_segment[proc] = segment
            pending.append(('label', proc))
            continue
        m = re.match(r'ARG\s+(.*)', line, re.I)
        if m:
            for a in m.group(1).split(','):
                name, kind = [x.strip().lower() for x in a.split(':')]
                labels[name] = (ARGSEG, arg_ptr[0], SIZES[kind])
                arg_ptr[0] += 4
            continue
        m = re.match(r'^(?:(\w+)\s+)?(db|dw|dd)\s+(.*)$', line, re.I)
        if m:
            size = SIZES[m.group(2).lower()]
            if m.group(1): labels[m.group(1).lower()] = (segment, here, size)
            for item in m.group(3).split(','):
                item = item.strip()
                dup = re.match(r'(.+?)\s+dup\s*\(\s*\?\s*\)', item, re.I)
                if dup:
                    here += size * evaluate(dup.group(1))
                    continue
                off = re.match(r'offset\s+(\w+)', item, re.I)
                if off:
                    fixups.append((segment, here, off.group(1)))
                elif item != '?':
                    v = evaluate(item)
                    M[(segment << 4) + here:(segment << 4) + here + size] = (v & ((1 << (8 * size)) - 1)).to_bytes(size, 'little')
                here += size
            continue
        m = re.match(r'^(@@\w+|\w+):\s*(.*)$', line)
        if m:
            name = m.group(1)
            pending.append(('label', (proc + name) if name.startswith('@@') else name))
            line = m.group(2)
            if not line: continue
        pending.append(('ins', line, proc))
    for item in pending:
        if item[0] == 'label':
            code_labels[item[1]] = len(code)
        else:
            code.append(compile_instruction(item[1], item[2]))
            source_of.append(item[1])
    return here

def call(name, **arguments):
    for k, v in arguments.items():
        seg, off, size = labels[k]
        wr(seg, off, size, v)
    SG['cs'] = proc_segment[name]
    pc = code_labels[name]
    while pc >= 0:
        r = code[pc]()
        pc = pc + 1 if r is None else r

# ----------------------------------------------------------------------------------------------
# Memory map (any free real-mode segments will do) and the C program's variables.
# ----------------------------------------------------------------------------------------------
PLZA, SPLINE, DATA = 0x1000, 0x2000, 0x3000
KUVA = [0x4000, 0x5000, 0x6000, 0x4000]      # kuvataus[]: texture for colour group 0, 1, 2 (3 unused)
DIST = 0x7000
VIDEO = 0xA000
for i, n in enumerate(['kx', 'ky', 'kz', 'dis', 'tx', 'ty', 'ls_kx', 'ls_ky', 'ls_kz']):
    labels[n] = (DATA, i * 2, 2)
CLRTAU, PAL, FPAL = 0x0100, 0x2200, 0x2600   # offsets inside DATA

def s16(v):
    v &= 0xFFFF
    return v - 65536 if v & 0x8000 else v

def s32(v):
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v

def cdiv(a, b):
    """C division: rounds towards zero."""
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q

def getvar(name): return s16(rd(*labels[name][:2], 2))
def setvar(name, v):
    seg, off, size = labels[name]
    wr(seg, off, size, v)

def read_table(filename, directive):
    values = []
    for l in open(os.path.join(SRC, filename), 'rb').read().decode('latin1').splitlines():
        m = re.match(r'\s*' + directive + r'\s+(.*)', l.split(';')[0], re.I)
        if m: values += [int(v) for v in re.findall(r'-?\d+', m.group(1))]
    return values

sinit_bytes = read_table('SINIT.INC', 'db')
SINIT = [s16(sinit_bytes[i] | sinit_bytes[i + 1] << 8) for i in range(0, len(sinit_bytes) - 1, 2)]
def sinit(i): return SINIT[i]
def kosinit(i): return SINIT[i + 256]          # "kosinit=sinit+512" is 512 BYTES on: a quarter turn

import math
SINI = [int(math.sin(a / 1024.0 * math.pi * 4) * 127) for a in range(1524)]   # initvect's own little table

def initvect():
    pal = [0] * 768
    for a in range(1, 32):
        pal[a * 3:a * 3 + 3] = [0, 0, a * 2]
    for a in range(32):
        pal[a * 3 + 96:a * 3 + 99] = [a * 2, a * 2, 63]
        pal[192 + a * 3:192 + a * 3 + 3] = [a * 2, 0, 0]
        pal[192 + a * 3 + 96:192 + a * 3 + 99] = [63, a * 2, 0]
        pal[384 + a * 3:384 + a * 3 + 3] = [a, 0, a * 2 // 3]
        pal[384 + a * 3 + 96:384 + a * 3 + 99] = [31 - a, a * 2, 21]
    M[(DATA << 4) + PAL:(DATA << 4) + PAL + 768] = bytes(pal)
    for y in range(64):
        for x in range(256):
            v = cdiv(SINI[(y * 4 + SINI[x * 2]) & 511], 4) + 32
            for g in range(3):
                M[(KUVA[g] << 4) + y * 256 + x] = v + 64 * g
    for y in range(128):
        for x in range(256):
            M[(DIST << 4) + y * 256 + x] = cdiv(SINI[y * 8], 3) & 0xFF
    for a in range(8 * 256):
        wr(DATA, CLRTAU + a * 4, 2, 640)
        wr(DATA, CLRTAU + a * 4 + 2, 2, 0)

POINTS = [(125, 125, 125), (125, -125, 125), (-125, -125, 125), (-125, 125, 125),
          (125, 125, -125), (125, -125, -125), (-125, -125, -125), (-125, 125, -125)]
FACES = [(1, 2, 3, 0, 0), (7, 6, 5, 4, 0), (0, 4, 5, 1, 1), (1, 5, 6, 2, 2), (2, 6, 7, 3, 1), (3, 7, 4, 0, 2)]
TXT = [(64, 4), (190, 4), (190, 60), (64, 60)]

class State: pass
st = State()

def swappage():
    st.page = (st.page + 1) % 6
    st.vmem = [0x0000, 0x5500, 0xAA00][st.page % 3]

def calculate():
    call('getspl', position=(4 * 256 + st.frames * 4) & 0xFFFF)
    for n in ('kx', 'ky', 'kz', 'ls_kx', 'ls_ky'):
        setvar(n, getvar(n) & 1023)
    kx, ky, kz = getvar('kx'), getvar('ky'), getvar('kz')
    lkx, lky = getvar('ls_kx'), getvar('ls_ky')
    st.ls_y = kosinit(lkx) >> 8
    st.ls_x = s16((sinit(lkx) >> 8) * (sinit(lky) >> 8)) >> 7
    st.ls_z = s16((sinit(lkx) >> 8) * (kosinit(lky) >> 8)) >> 7
    SX, SY, SZ, CX, CY, CZ = sinit(kx), sinit(ky), sinit(kz), kosinit(kx), kosinit(ky), kosinit(kz)
    # count_const: note "a>>15+7" in C means a>>22
    m = [s16(s32(CY * CZ) >> 22), s16(s32(CY * SZ) >> 22), s16(s32(-SY) >> 7),
         s16(s32(s32(s32(SX * CZ + 16384) >> 15) * SY - CX * SZ) >> 22),
         s16(s32(s32(s32(SX * SY + 16384) >> 15) * SZ + CX * CZ) >> 22),
         s16(s32(CY * SX) >> 22),
         s16(s32(s32(s32(CX * CZ + 16384) >> 15) * SY + SX * SZ) >> 22),
         s16(s32(s32(s32(CX * SY + 16384) >> 15) * SZ - SX * CZ) >> 22),
         s16(s32(CY * CX) >> 22)]
    tx, ty, dis = getvar('tx'), getvar('ty'), getvar('dis')
    st.pts = []
    for x, y, z in POINTS:
        def row(a, b, c, add):
            return s16((s16((s16(x * a) >> 1) + (s16(y * b) >> 1) + (s16(z * c) >> 1)) >> 7) + add)
        xx, yy, zz = row(m[0], m[1], m[2], tx), row(m[3], m[4], m[5], ty), row(m[6], m[7], m[8], dis)
        st.pts.append((xx, yy, zz, s16(cdiv(xx * 256, zz) + 320), s16(cdiv(yy * 142, zz) + 66)))
    # sort_faces: really "which faces point at the viewer", plus the lighting
    st.todraw = []
    p = 0
    for a, (p1, p2, p3, p4, colour) in enumerate(FACES):
        x, y, z = st.pts[p1][:3]
        ax, ay, az = s16(st.pts[p2][0] - x), s16(st.pts[p2][1] - y), s16(st.pts[p2][2] - z)
        bx, by, bz = s16(st.pts[p3][0] - x), s16(st.pts[p3][1] - y), s16(st.pts[p3][2] - z)
        nx, ny, nz = s32(ay * bz - az * by), s32(az * bx - ax * bz), s32(ax * by - ay * bx)
        if s32(-x * nx - y * ny - z * nz) > 0: continue
        light = s16(cdiv(s32(st.ls_x * nx + st.ls_y * ny + st.ls_z * nz), 250000) + 32)
        if st.lls[p] != light:
            call('shadepal', fpal=(DATA << 16) | (FPAL + colour * 192), ppal=(DATA << 16) | (PAL + colour * 192),
                 shd=light & 0xFFFF)
            st.lls[p] = light
        st.todraw.append(a)
        p += 1

def setlong(name, v): setvar(name, v & 0xFFFFFFFF)

def do_poly(pnts, colour, dd):
    dd = (dd + 1) & 63
    n = 0
    for a in range(1, 4):
        if pnts[a][1] < pnts[n][1]: n = a
    s1 = s2 = n
    d1, d2 = (s1 + 1) & 3, (s2 - 1) & 3
    def edge(which, s, d):
        dx, dy = s16(pnts[d][0] - pnts[s][0]), s16(pnts[d][1] - pnts[s][1])
        if dy == 0: dy = 1
        setlong('ax' + which, cdiv(65536 * dx, dy))
        setlong('xx' + which, (pnts[s][0] << 16) + 0x8000)
        setlong('txx' + which, (TXT[s][0] << 16) + 0x8000)
        setlong('txy' + which, (TXT[s][1] << 16) + 0x8000)
        setlong('tax' + which, cdiv(65536 * (TXT[d][0] - TXT[s][0]), dy))
        setlong('tay' + which, cdiv(65536 * (TXT[d][1] - TXT[s][1]), dy))
    edge('1', s1, d1)
    edge('2', s2, d2)
    yy = pnts[s1][1]
    setvar('yy', yy & 0xFFFF)
    setvar('from', KUVA[colour] << 16)
    setvar('to', (VIDEO << 16) | ((st.vmem + yy * 160) & 0xFFFF))
    setvar('dseg', DIST + dd * 16)
    setvar('ctau', (DATA << 16) | ((CLRTAU + st.clrptr * 1024 + yy * 4) & 0xFFFF))
    n = 0
    while n < 4:
        m = min(pnts[d1][1], pnts[d2][1])
        call('do_block', ycount=(m - yy) & 0xFFFF)
        yy = m
        setvar('yy', yy & 0xFFFF)
        if pnts[d1][1] == pnts[d2][1]:
            s1 = d1; d1 = (s1 + 1) & 3
            s2 = d2; d2 = (s2 - 1) & 3; n += 2
            edge('1', s1, d1); edge('2', s2, d2)
        elif pnts[d1][1] < pnts[d2][1]:
            s1 = d1; d1 = (s1 + 1) & 3; n += 1
            edge('1', s1, d1)
        else:
            s2 = d2; d2 = (s2 - 1) & 3; n += 1
            edge('2', s2, d2)

def draw():
    for a in st.todraw:
        p1, p2, p3, p4, colour = FACES[a]
        off = (st.page & 1) * 2
        do_poly([(s16(st.pts[i][3] + off), st.pts[i][4]) for i in (p1, p2, p3, p4)], colour, st.frames & 63)

def clear():
    otau = CLRTAU + ((st.clrptr - 3) & 7) * 1024
    ntau = CLRTAU + st.clrptr * 1024
    st.clrptr = (st.clrptr + 1) & 7
    call('do_clear', vmem=(VIDEO << 16) | st.vmem, otau=(DATA << 16) | otau, ntau=(DATA << 16) | ntau)

def frame(step):
    """One trip round VECT.C's main loop, for app step `step`."""
    swappage()
    st.frames = step - LEAD
    calculate()
    draw()
    clear()

def screen():
    """What the VGA shows of the page just drawn: 320x134 colour numbers. The view starts 160 pixels
    into the 640-wide page, and is panned 2 pixels on the pages that were drawn 2 pixels to the right."""
    pan = (st.page & 1) * 2
    out = bytearray(320 * 134)
    for y in range(134):
        base = st.vmem + 40 + y * 160
        for x in range(320):
            v = x + pan
            out[y * 320 + x] = planes[v & 3][(base + (v >> 2)) & 0xFFFF]
    return out

def palette():
    return bytes(M[(DATA << 4) + FPAL:(DATA << 4) + FPAL + 768])

def write_png(name, pixels, pal):
    rows = b''
    for y in range(134):
        line = b''.join(bytes(min(255, c * 255 // 63) for c in pal[p * 3:p * 3 + 3]) for p in pixels[y * 320:(y + 1) * 320])
        rows += (b'\0' + line) * 3
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    open(name, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 320, 402, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))

def setup(page):
    for p in planes: p[:] = bytes(65536)
    assemble('PLZA.ASM', PLZA)
    assemble('SPLINE.ASM', SPLINE)
    for seg, off, name in fixups:
        wr(seg, off, 2, code_labels[name])
    initvect()
    st.page, st.vmem, st.clrptr, st.frames = page - 1, 0, 0, 0
    st.lls = [0] * 6

def emit_tables():
    coef = read_table('SPLINE.INC', 'dw')
    assert len(coef) == 1024 and all(coef[i] == coef[1024 - i] for i in range(1, 1024))
    assert SINIT[1024:1280] == SINIT[0:256]
    def block(values):
        return '\n'.join('        ' + ', '.join(str(v) for v in values[i:i + 16]) + ',' for i in range(0, len(values), 16))
    print('''// Made by tools/plasmacube_reference.py --tables from the original PLZPART/SINIT.INC and SPLINE.INC.
// Neither table follows a formula that reproduces it exactly (see docs/scenes/plasma-cube.md), so the
// original numbers are kept here. The self-test checks them by checksum.

enum PlasmaCubeTables {
    /// SINIT.INC: one sine wave in 1024 entries, about 32767 tall (the file repeats the first quarter
    /// so a cosine can be read 256 entries on; wrapping the index does the same).
    static let sine: [Int16] = [
%s
    ]

    /// SPLINE.INC: the weights that blend four neighbouring path points into one position. Entry t
    /// weights the newest point, t+256 and t+512 the middle two, t+768 the oldest; 32768 means 1.
    static let blend: [Int16] = [
%s
    ]
}''' % (block(SINIT[:1024]), block(coef)))

if __name__ == '__main__':
    args = sys.argv[1:]
    page, png, want_range = 1, False, False
    while args and args[0].startswith('--'):
        a = args.pop(0)
        if a == '--src': SRC = args.pop(0)
        elif a == '--page': page = int(args.pop(0))
        elif a == '--png': png = True
        elif a == '--range': want_range = True
        elif a == '--tables': emit_tables(); sys.exit(0)
    steps = sorted(int(a) for a in args)
    setup(page)
    last = max(steps) if steps else 2047
    lo = [10 ** 9] * 3; hi = [-10 ** 9] * 3; first_lit = None; last_lit = None
    for step in range(0, last + 1):
        frame(step)
        if want_range:
            for p in st.pts:
                for i, v in enumerate((p[3], p[4], p[2])):
                    lo[i] = min(lo[i], v); hi[i] = max(hi[i], v)
            pal = palette(); scr = screen()
            if any(pal[c * 3] | pal[c * 3 + 1] | pal[c * 3 + 2] for c in set(scr)):
                if first_lit is None: first_lit = step
                last_lit = step
        if step in steps:
            scr, pal = screen(), palette()
            print('step %d page %d: screen %d palette %d faces %s light %s' % (
                step, st.page, zlib.crc32(bytes(scr)), zlib.crc32(pal), st.todraw, st.lls[:len(st.todraw)]))
            if png: write_png('reference%04d_p%d.png' % (step, page), scr, pal)
    if want_range:
        print('x %d..%d  y %d..%d  z %d..%d  first lit step %s  last lit step %s' % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], first_lit, last_lit))
