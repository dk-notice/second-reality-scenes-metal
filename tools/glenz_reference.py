#!/usr/bin/env python3
"""Reference pictures for Glenz Vectors, made by running the ORIGINAL assembly.

The original scene (GLENZ.EXE, coder Psi) is part C, part assembly:

  - MATH.ASM   cmatrix_yxz / calcmatrix (the turn matrix), with MATHSIN.INC (3600-step sine table)
  - VEC.ASM    setmatrix, rotlist, cliplist, projlist (turn, squash, floor clamp, perspective),
               ceasypolylist + checkhiddenbx (which faces show), demo_glz / demo_glz2 (face colours
               and the palette writes that light them)
  - NEW.ASM    __newgroup, ng_pass2, ng_pass3 (the row-by-row XOR filler and the change-only
               screen update that ORs in the floor picture)
  - MAIN.C     the script: bounce, jelly, floor fade, second glenz, the wandering, the end

This tool reads the three assembly files AS TEXT, expands their macros, and carries the
instructions out one at a time in the small x86 interpreter of tools/plasmacube_reference.py
(extended here with the extra instructions, near calls and the VGA colour ports). MAIN.C is
re-written here in Python, keeping Microsoft C's 16-bit whole-number rules.

Departures from running the text exactly as written:
  - rotlist patches numbers into its own instructions (self-modifying code). The nine patched
    numbers are kept in nine variables instead.
  - the C calling wrappers' stack handling (CBEG / CEND) and the debugging `setborder` macro are
    replaced by direct calls.
Two small departures from running the text exactly as written, neither of which changes a result:
the two above. One thing is watched for: the filler files each edge under the screen row it starts
on, in a table with 256 entries. An edge starting on row 256 or lower would be written outside
that table. This tool counts edges starting on rows 200-255 (stored, never drawn) and stops with an
error if one ever starts on row 256 or lower. Over the whole scene: 198 of the first kind, none of
the second.

Usage:
  python3 tools/glenz_reference.py [--png] step [step ...]   checksums (and pictures) at those steps
  python3 tools/glenz_reference.py --art                      prints Scenes/GlenzVectors/GlenzFloorArt.swift
  python3 tools/glenz_reference.py --tables                   checks the tables against their formulas

Steps are 1/70 s, counted as the app counts them (see GlenzModel: the plate's fall, a pause, then
the original's frame counter starts at 1). Development tool only; the app does not use it.
"""
import re, sys, os, struct, zlib, math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import plasmacube_reference as pc

SRC = os.path.join(HERE, '..', '..', 'secondreality', 'GLENZ')
M, R, SG, F, STACK = pc.M, pc.R, pc.SG, pc.F, pc.STACK
s16, s32, cdiv = pc.s16, pc.s32, pc.cdiv

# ----------------------------------------------------------------------------------------------
# Turning the files' MASM-style text into the plain form the interpreter's assembler reads.
# ----------------------------------------------------------------------------------------------
def read_lines(name):
    text = open(os.path.join(SRC, name), 'rb').read().decode('latin1').replace('\r', '').replace('\x1a', '')
    return [l.split(';')[0].rstrip() for l in text.split('\n')]

def collect_macros(lines, macros):
    """Removes MACRO ... ENDM definitions from `lines`, storing them in `macros`."""
    out, i = [], 0
    while i < len(lines):
        m = re.match(r'^\s*(\w+)\s+MACRO\b\s*(.*)$', lines[i], re.I)
        if m:
            body, j = [], i + 1
            while not re.search(r'\bENDM\s*$', lines[j], re.I):
                body.append(lines[j]); j += 1
            body.append(re.sub(r'\bENDM\s*$', '', lines[j], flags=re.I))    # "label: ENDM"
            params = [p.strip() for p in m.group(2).split(',') if p.strip()]
            macros[m.group(1).lower()] = (params, body)
            i = j + 1
            continue
        out.append(lines[i]); i += 1
    return out

OVERRIDE = {
    'cbeg': ([], []),                       # the C wrappers are entered with bp already set
    'cend': ([], ['\tret']),
    'setborder': (['col'], []),             # debugging aid, compiled out in the original too
}
unique = [0]

def expand_all(lines, macros):
    """Inlines INCLUDEs (code ones), unrolls REPT, expands macro calls with LOCAL labels."""
    out, i = [], 0
    while i < len(lines):
        s = lines[i].strip()
        up = s.upper()
        m = re.match(r'INCLUDE\s+(\S+)', s, re.I)
        if m:
            name = m.group(1).upper()
            if name in ('ASM.INC',):
                pass                         # only its macros are wanted; collected separately
            else:
                out += expand_all(collect_macros(read_lines(name), macros), macros)
            i += 1
            continue
        if up.startswith('REPT'):
            j = i + 1
            while lines[j].strip().upper() != 'ENDM': j += 1
            for _ in range(pc.evaluate(s[4:])):
                out += expand_all(lines[i + 1:j], macros)
            i = j + 1
            continue
        first = s.split()[0].lower() if s else ''
        label = ''
        m = re.match(r'^(@@\w+|\w+):\s*(\w+)(.*)$', s)
        if m and m.group(2).lower() in macros:
            label, first, s = m.group(1) + ':', m.group(2).lower(), m.group(2) + m.group(3)
        if first in macros:
            params, body = macros[first]
            args = [a.strip() for a in s[len(first):].split(',')] if s[len(first):].strip() else []
            unique[0] += 1
            locals_, text = [], []
            for b in body:
                bm = re.match(r'^\s*local\s+(.*)$', b, re.I)
                if bm:
                    locals_ += [x.strip() for x in bm.group(1).split(',')]
                    continue
                for p, a in zip(params, args):
                    b = re.sub(r'\b%s\b' % p, a, b)
                for l in locals_:
                    b = re.sub(r'\b%s\b' % l, 'm%d_%s' % (unique[0], l), b)
                text.append(b)
            if label: out.append(label)
            out += expand_all(text, macros)
            i += 1
            continue
        if s: out.append(s)
        i += 1
    return out

SKIP = re.compile(r'^(\.386|locals|assume|public|extrn|global|align|end|ideal)\b', re.I)
MEM = re.compile(r'^(?:(byte|word|dword)\s+ptr\s+)?(?:(cs|ds|es|fs|gs|ss):)?([a-z_]\w*)?(?:\[(.*)\])?$')

def normal_operand(t):
    t = t.strip()
    if t in pc.REG or t in SG or t.startswith('offset') or t.startswith('seg '):
        return t
    m = MEM.match(t)
    if not m or not (m.group(1) or m.group(2) or m.group(4) is not None):
        return t
    size, seg, label, expr = m.groups()
    if label in ('bx', 'si', 'di', 'bp'):          # "[bx]" style written without brackets never occurs
        return t
    inner = '+'.join(x for x in (label, expr) if x)
    if seg is None and label is None and re.search(r'\bbp\b', inner):
        seg = 'ss'
    return '[' + (size + ' ' if size else '') + (seg + ':' if seg else '') + inner + ']'

def dup_expand(items):
    while True:
        m = re.search(r'([0-9a-fh*+\- ]+?)\s*dup\s*\(([^()]*)\)', items)
        if not m: return items
        items = items[:m.start()] + ','.join([m.group(2)] * pc.evaluate(m.group(1))) + items[m.end():]

def translate(lines):
    """One instruction or data line per entry, lower case, in the assembler's dialect."""
    equ, out, seen, proc = {}, [], set(), ''
    for s in lines:
        s = s.strip().lower()
        if SKIP.match(s) or re.match(r'^\w+\s+(segment|ends)\b', s):
            continue
        m = re.match(r'^(\w+)\s+equ\s+(.+)$', s)
        if m:
            equ[m.group(1)] = m.group(2).strip()
            continue
        for k, v in equ.items():
            s = re.sub(r'\b%s\b' % k, v, s)
        m = re.match(r'^(\w+)\s+proc\b', s)
        if m:
            proc = m.group(1); out.append('PROC ' + proc); continue
        if re.match(r'^\w+\s+endp\b', s):
            out.append('ENDP'); continue
        m = re.match(r'^(\w+)\s+label\s+(\w+)', s)
        if m:
            out.append('LABEL %s %s' % (m.group(1), m.group(2))); continue
        if re.match(r'^\w+\s*=', s):
            out.append(s); continue
        m = re.match(r'^(?:(\w+)\s+)?(db|dw|dd)\s+(.*)$', s)
        if m and (m.group(1) or '') not in ('rep',):
            out.append((m.group(1) + ' ' if m.group(1) else '') + m.group(2) + ' ' + dup_expand(m.group(3)))
            continue
        m = re.match(r'^(@@\w+|\w+):\s*(.*)$', s)
        if m:
            key = (proc if m.group(1).startswith('@@') else '') + m.group(1)
            assert key not in seen, 'label defined twice: ' + key
            seen.add(key)
            out.append(m.group(1) + ':')
            s = m.group(2)
            if not s: continue
        parts = s.split(None, 1)
        if len(parts) == 2 and parts[0] not in ('rep',):
            s = parts[0] + ' ' + ','.join(normal_operand(a) for a in parts[1].split(','))
        out.append(s)
    return out

# ----------------------------------------------------------------------------------------------
# Extra instructions for the interpreter.
# ----------------------------------------------------------------------------------------------
DAC = bytearray(768)          # the VGA card's 256 colours
dac_pos = [0]
base_parse, base_compile = pc.parse_operand, pc.compile_instruction

def parse_operand(text, proc):
    m = re.match(r'offset\s+(\w+)\s*\+\s*(\w+)$', text.strip().lower())
    if m:
        v = pc.labels[m.group(1)][1] + pc.evaluate(m.group(2))
        return {'kind': 'imm', 'size': None, 'get': lambda: v}
    return base_parse(text, proc)

def run(index):
    while index >= 0:
        r = pc.code[index]()
        index = index + 1 if r is None else r

def set_logic_flags(res, bits):
    F[0] = F[3] = 0
    pc.flags_result(res, bits)

def compile_instruction(text, proc):
    parts = text.split(None, 1)
    op = parts[0]
    rest = parts[1] if len(parts) > 1 else ''
    def lab(name):
        name = name.strip()
        return (proc + name) if name.startswith('@@') else name
    if op in ('stc', 'clc'):
        v = 1 if op == 'stc' else 0
        def f(): F[0] = v
        return f
    if op == 'cld':
        return lambda: None
    if op in ('push', 'pop'):
        o = parse_operand(rest, proc)
        if o['kind'] == 'mem': pc.finish(o, o['size'] or 2)
        if op == 'push': return lambda: STACK.append(o['get']())
        return lambda: o['set'](STACK.pop())
    if op == 'call':
        if rest.startswith('['):
            o = pc.finish(parse_operand(rest, proc), 2)
            return lambda: run(o['get']())
        name = lab(rest)
        def f():
            old = SG['cs']
            SG['cs'] = pc.proc_segment.get(name, old)
            run(pc.code_labels[name])
            SG['cs'] = old
        return f
    more = {'jg': lambda: not F[1] and F[2] == F[3], 'jle': lambda: F[1] or F[2] != F[3],
            'jng': lambda: F[1] or F[2] != F[3], 'jnl': lambda: F[2] == F[3],
            'jc': lambda: F[0], 'jnc': lambda: not F[0], 'jbe': lambda: F[0] or F[1],
            'jcxz': lambda: (R[1] & 0xFFFF) == 0}
    if op in more:
        cond, name = more[op], lab(rest)
        return lambda: pc.code_labels[name] if cond() else None
    if op == 'lodsw':
        def f():
            R[0] = (R[0] & 0xFFFF0000) | pc.rd(SG['ds'], R[6] & 0xFFFF, 2)
            R[6] = (R[6] & 0xFFFF0000) | ((R[6] + 2) & 0xFFFF)
        return f
    if op == 'movsw':
        def f():
            pc.wr(SG['es'], R[7] & 0xFFFF, 2, pc.rd(SG['ds'], R[6] & 0xFFFF, 2))
            R[6] = (R[6] & 0xFFFF0000) | ((R[6] + 2) & 0xFFFF)
            R[7] = (R[7] & 0xFFFF0000) | ((R[7] + 2) & 0xFFFF)
        return f
    if op == 'stosd' or (op == 'rep' and rest == 'stosd'):
        rep = op == 'rep'
        def f():
            n = (R[1] & 0xFFFF) if rep else 1
            for _ in range(n):
                pc.wr(SG['es'], R[7] & 0xFFFF, 4, R[0])
                R[7] = (R[7] & 0xFFFF0000) | ((R[7] + 4) & 0xFFFF)
            if rep: R[1] &= 0xFFFF0000
        return f
    if op == 'out':
        wide = rest.split(',')[1] == 'ax'
        def f():
            port, v = R[2] & 0xFFFF, R[0] & 0xFF
            assert not wide
            if port == 0x3C8: dac_pos[0] = v * 3
            elif port == 0x3C9:
                DAC[dac_pos[0] % 768] = v & 63
                dac_pos[0] += 1
        return f
    args = [a.strip() for a in rest.split(',')] if rest else []
    if op in ('imul', 'neg', 'not') and len(args) == 1:
        o = parse_operand(args[0], proc)
        if o['kind'] == 'mem': pc.finish(o, o['size'])
        size = o['size']; bits = size * 8; mask = (1 << bits) - 1
        if op == 'imul':
            def f():
                a, b = R[0] & mask, o['get']()
                if a >> (bits - 1): a -= 1 << bits
                if b >> (bits - 1): b -= 1 << bits
                p = (a * b) & ((1 << (2 * bits)) - 1)
                if size == 2:
                    R[0] = (R[0] & 0xFFFF0000) | (p & 0xFFFF)
                    R[2] = (R[2] & 0xFFFF0000) | (p >> 16)
                else:
                    R[0], R[2] = p & 0xFFFFFFFF, p >> 32
            assert size in (2, 4)
            return f
        if op == 'neg':
            def f():
                a = o['get']()
                res = (-a) & mask
                o['set'](res)
                F[0] = 1 if a else 0
                F[3] = 1 if a == 1 << (bits - 1) else 0
                pc.flags_result(res, bits)
            return f
        return lambda: o['set'](~o['get']() & mask)
    if op in ('or', 'xchg', 'sbb', 'shrd'):
        ops = [parse_operand(a, proc) for a in args]
        d, s = ops[0], ops[1]
        size = d['size'] or s['size']
        pc.finish(d, size)
        if s['kind'] == 'mem': pc.finish(s, size)
        bits = size * 8; mask = (1 << bits) - 1
        if op == 'or':
            def f():
                res = d['get']() | (s['get']() & mask)
                set_logic_flags(res, bits)
                d['set'](res)
            return f
        if op == 'xchg':
            def f():
                a, b = d['get'](), s['get']()
                d['set'](b); s['set'](a)
            return f
        if op == 'sbb':
            def f():
                a, b = d['get'](), s['get']() & mask
                r = a - b - F[0]
                res = r & mask
                F[0] = 1 if r < 0 else 0
                F[3] = ((a ^ b) & (a ^ res)) >> (bits - 1) & 1
                pc.flags_result(res, bits)
                d['set'](res)
            return f
        count = ops[2]['get']
        def f():
            n = count() & 31
            if n: d['set'](((d['get']() >> n) | (s['get']() << (bits - n))) & mask)
        return f
    try:
        return base_compile(text, proc)
    except Exception as error:               # instructions on paths that are never run
        message = 'instruction not supported: %s (%s)' % (text, error)
        def f(): raise RuntimeError(message)
        return f

pc.parse_operand = parse_operand
pc.compile_instruction = compile_instruction

# ----------------------------------------------------------------------------------------------
# Memory map and loading.
# ----------------------------------------------------------------------------------------------
VEC, NEW, MATH, DATAV, NEWDATA, BGPIC, WORK, VIDEO = 0x1000, 0x2000, 0x3000, 0x4000, 0x5000, 0x6000, 0x7000, 0xA000
ARGS = 0xF000                 # offset in WORK where C arguments are laid out (bp+6 ...)
skipped_edges = [0]        # edges starting on rows 200-255: stored by the original, never drawn

def load():
    import tempfile
    macros = {}
    collect_macros(read_lines('ASM.INC'), macros)
    macros.update(OVERRIDE)
    for i, n in enumerate(['rows']): pc.labels[n] = (DATAV, 0, 2)
    for i, n in enumerate(['wminx', 'wminy', 'wmaxx', 'wmaxy', 'projxadd', 'projyadd']):
        pc.labels[n] = (DATAV, 0x400 + i * 2, 2)
    for i, n in enumerate(['projxmul', 'projymul', 'projminz', 'xadd', 'yadd', 'zadd']):
        pc.labels[n] = (DATAV, 0x440 + i * 4, 4)
    pc.labels['newdata1'] = (NEWDATA, 0, 1)
    pc.labels['_bgpic'] = (BGPIC, 0, 1)
    folder = tempfile.mkdtemp()
    pc.SRC = folder
    for name, seg in (('MATH.ASM', MATH), ('NEW.ASM', NEW), ('VEC.ASM', VEC)):
        lines = expand_all(collect_macros(read_lines(name), macros), macros)
        lines = translate(lines)
        if name == 'VEC.ASM':
            fixed = []
            for l in lines:
                m = re.match(r'^mov \[dword cs:2\+(mtrm\d\d)\],eax$', l)
                if m: l = 'mov [dword cs:%s_v],eax' % m.group(1)
                fixed.append(l)
            lines = []
            i = 0
            while i < len(fixed):
                m = re.match(r'^(mtrm\d\d):$', fixed[i])
                if m:
                    assert fixed[i + 1] == 'mov eax,12345678h'
                    lines.append('mov eax,[dword cs:%s_v]' % m.group(1))
                    i += 2
                    continue
                lines.append(fixed[i]); i += 1
            lines += ['mtrm%02d_v dd 0' % k for k in range(0, 18, 2)]
        if name == 'NEW.ASM':
            # Edges starting below the screen: count them (see the top of this file).
            at = lines.index('@@nc:')
            lines[at + 1:at + 1] = ['cmp bx,200', 'jl @@rowok', 'call far_edge', '@@rowok:']
            lines += ['PROC far_edge', 'ret', 'ENDP']
        open(os.path.join(folder, name), 'w').write('\n'.join(lines) + '\n')
        pc.assemble(name, seg)
    for seg, off, name in pc.fixups:
        pc.wr(seg, off, 2, pc.code_labels[name])
    hook = pc.code_labels['far_edge']
    def count_far():
        skipped_edges[0] += 1
        if (R[3] & 0xFFFF) >= 256: raise RuntimeError('an edge starts on row %d: outside the row table' % (R[3] & 0xFFFF))
        return -1
    pc.code[hook] = count_far
    # init320x200 (VID.ASM), the mode MAIN.C asks for through testasm()
    for n, v in (('projxmul', 256), ('projymul', 213), ('projxadd', 160), ('projyadd', 130), ('projminz', 128),
                 ('wminx', 0), ('wminy', 0), ('wmaxx', 319), ('wmaxy', 199)):
        seg, off, size = pc.labels[n]
        pc.wr(seg, off, size, v)

def asm(name, **regs):
    for k, v in regs.items():
        if k in SG: SG[k] = v
        else: pc.parse_operand(k, '')['set'](v & 0xFFFFFFFF)
    SG['cs'] = pc.proc_segment[name]
    run(pc.code_labels[name])

def c_call(name, *words):
    """Calls one of the C-callable routines with its arguments laid out as the C compiler did."""
    for i, w in enumerate(words):
        pc.wr(WORK, ARGS + 6 + i * 2, 2, w & 0xFFFF)
    SG['ss'] = WORK
    asm(name, bp=ARGS)

# ----------------------------------------------------------------------------------------------
# MAIN.C in Python (16-bit ints, C division).
# ----------------------------------------------------------------------------------------------
sin1024 = [int(math.sin(i * math.pi / 512) * 256) for i in range(1024)]

def glenz_points(scale, cube, tip):
    c, t = cube * scale, tip * scale
    return [(-c, -c, -c), (c, -c, -c), (c, c, -c), (-c, c, -c), (-c, -c, c), (c, -c, c), (c, c, c), (-c, c, c),
            (0, 0, -t), (0, 0, t), (t, 0, 0), (-t, 0, 0), (0, t, 0), (0, -t, 0)]

POINTS = glenz_points(50, 100, 170)       # MAIN.C points[]
POINTSB = glenz_points(99, 60, 105)       # MAIN.C pointsb[]
FACES = [(0, 1, 8), (1, 2, 8), (2, 3, 8), (3, 0, 8), (2, 1, 10), (1, 5, 10), (5, 6, 10), (6, 2, 10),
         (2, 6, 12), (6, 7, 12), (7, 3, 12), (3, 2, 12), (0, 3, 11), (3, 7, 11), (7, 4, 11), (4, 0, 11),
         (5, 1, 13), (1, 0, 13), (0, 4, 13), (4, 5, 13), (5, 4, 9), (4, 7, 9), (7, 6, 9), (6, 5, 9)]
EPOLYS = [(0x4002 + 2 * i, f) for i, f in enumerate(FACES)]
EPOLYSB = [(0x4004 if i % 2 == 0 else 0x4002, f) for i, f in enumerate(FACES)]

# where the C arrays live in WORK
A_POINTS, A_POINTSB, A_POINTS2, A_POINTS2B, A_POINTS3 = 0x0000, 0x0200, 0x0400, 0x0800, 0x0C00
A_EPOLYS, A_EPOLYSB, A_POLYLIST, A_MATRIX = 0x1400, 0x1600, 0x1800, 0x1C00

def put_points(at, pts):
    pc.wr(WORK, at, 4, len(pts))
    for i, p in enumerate(pts):
        for k in range(3): pc.wr(WORK, at + 4 + i * 12 + k * 4, 4, p[k] & 0xFFFFFFFF)

def put_polys(at, polys):
    o = at
    for colour, f in polys:
        for w in (3, colour) + f:
            pc.wr(WORK, o, 2, w); o += 2
    pc.wr(WORK, o, 2, 0)

class Floor:
    """The plate: MAIN.C's first loop, which squashes the top 100 rows of the picture `fc`."""
    def __init__(self):
        fc = open(os.path.join(SRC, 'FC.UH'), 'rb').read()
        self.pal = fc[16:16 + 48]
        self.rows = [fc[784 + a * 320:784 + (a + 1) * 320] for a in range(108)]
        self.vram = bytearray(64000)
        self.yy = 0; self.ya = 0; self.done = False
    def step(self):
        """One frame of the fall. Returns False once the plate has come to rest (nothing drawn)."""
        self.ya += 1; self.yy += self.ya
        if self.yy > 48 * 16:
            self.yy -= self.ya
            self.ya = cdiv(-self.ya * 2, 3)
            if -4 < self.ya < 4:
                self.done = True
                return False
        y = self.yy // 16
        y1 = 130 + y // 2
        y2 = 130 + y * 3 // 2
        if y2 != y1: self.b = 25600 // (y2 - y1)
        v = self.vram
        for ry in range(y1 - 4, y1):
            if ry <= 199: v[ry * 320:ry * 320 + 320] = bytes(320)
        c = 0
        for ry in range(y1, y2):
            if ry <= 199: v[ry * 320:ry * 320 + 320] = self.rows[c // 256]
            c += self.b
        for c in range(16):
            ry = y2 + c
            if ry <= 199: v[ry * 320:ry * 320 + 320] = bytes(320) if c > 7 else self.rows[100 + c]
        return True

FALL_PAUSE = 35      # steps between the plate coming to rest and the original's frame 1 (this version's choice)

class Script:
    def __init__(self):
        self.frame = 0
        self.rx = self.ry = self.rz = 0
        self.zpos = 7500
        self.ypos = -9000; self.yposa = 0
        self.boingm, self.boingd = 6, 7
        self.jello = self.jelloa = 0
        self.xscale = self.yscale = self.zscale = 120
        self.bscale = 0
        self.oxp = self.oyp = self.ozp = 0
        self.oxb = self.oyb = self.ozb = 0
        self.lightshift = 9
        self.backpal = None      # set by the caller: the floor's 16 colours
        self.pal = None
        self.erase_row = None    # set on frames where two floor rows are blanked

    def step(self):
        s = self
        s.erase_row = None
        s.frame += 1
        frame = s.frame
        s.rx += 32; s.ry += 7
        s.rx %= 3 * 3600; s.ry %= 3 * 3600; s.rz %= 3 * 3600
        if frame > 900:
            a = frame - 900
            b = min(frame - 900, 50)
            s.oxp = cdiv(s16(sin1024[(a * 3) & 1023] * b), 10)
            s.oyp = cdiv(s16(sin1024[(a * 5) & 1023] * b), 10)
            s.ozp = cdiv(s16((cdiv(sin1024[(a * 4) & 1023], 2) + 128) * b), 16)
            if frame > 1800:
                a = min(frame - 1800 + 64, 1024)
                s.oxb = s16(cdiv(-sin1024[(a * 6) & 1023] * a, 40))
                s.oyb = s16(cdiv(-sin1024[(a * 7) & 1023] * a, 40))
                s.ozb = s16(cdiv((sin1024[(a * 8) & 1023] + 128) * a, 40))
            else:
                s.oxb = -sin1024[(a * 6) & 1023]
                s.oyb = -sin1024[(a * 7) & 1023]
                s.ozb = sin1024[(a * 8) & 1023] + 128
            b = 1800 - frame
            if b < 0:
                if b < -99: b = -99
                s.oyp = s16(s.oyp - cdiv(b * b, 2))
        if frame > 800:
            if frame > 1220 + 789:
                if s.xscale > 0: s.xscale -= 1
                if s.yscale > 0: s.yscale -= 1
                if s.zscale > 0: s.zscale -= 1
                if s.bscale > 0: s.bscale -= 1
            else:
                if s.bscale < 180: s.bscale += 2
                else: s.bscale = 180
            if s.bscale > s.xscale: s.lightshift = 10
        else:
            if frame < 640 + 70:
                s.yposa = s16(s.yposa + 31)
                s.ypos = s16(s.ypos + cdiv(s.yposa, 40))
                if s.ypos > -300:
                    s.ypos = s16(s.ypos - cdiv(s.yposa, 40))
                    s.yposa = cdiv(s16(s16(-s.yposa) * s.boingm), s.boingd)
                    s.boingm += 2; s.boingd += 1
                if s.ypos > -900 and s.yposa > 0:
                    s.jello = cdiv(s16((s.ypos + 900) * 5), 3)
                    s.jelloa = 0
            else:
                if s.ypos > -2800: s.ypos -= 16
                elif s.ypos < -2800: s.ypos += 16
            s.yscale = s.xscale = 120 + cdiv(s.jello, 30)
            s.zscale = 120 - cdiv(s.jello, 30)
            a = s.jello
            s.jello = s16(s.jello + s.jelloa)
            if (a < 0 and s.jello > 0) or (a > 0 and s.jello < 0):
                s.jelloa = cdiv(s16(s.jelloa * 5), 6)
            a = cdiv(s.jello, 20)
            s.jelloa = s16(s.jelloa - a)
        if frame > 1280 + 789:
            b = max(1280 + 789 + 64 - frame, 0)
            s.pal = bytes(s.backpal[a] * b // 64 for a in range(48))
        elif frame > 700:
            if frame < 765:
                b = max(764 - frame, 0)
                s.pal = bytes(s.backpal[a] * b // 64 for a in range(48))
            elif frame < 790:
                s.erase_row = 150 + (frame - 765) * 2
                if frame > 785:
                    for a in range(16):
                        r = g = b = 0
                        if a & 1: r += 10
                        if a & 2: r += 30
                        if a & 4: r += 20
                        if a & 8: r += 16; g += 16; b += 16
                        s.backpal[a * 3:a * 3 + 3] = bytes((min(r, 63), min(g, 63), min(b, 63)))
            elif frame < 795:
                s.pal = bytes(s.backpal)

class Machine:
    """The whole scene: the plate's fall, the pause, then MAIN.C's main loop."""
    def __init__(self):
        load()
        put_points(A_POINTS, POINTS); put_points(A_POINTSB, POINTSB)
        put_polys(A_EPOLYS, EPOLYS); put_polys(A_EPOLYSB, EPOLYSB)
        self.floor = Floor()
        self.script = Script()
        self.pause = 0
        self.started = False
        DAC[:] = bytes(768)
        DAC[:48] = self.floor.pal
        self.vram = self.floor.vram

    def begin_main(self):
        s = self.script
        s.backpal = bytearray(self.floor.pal)
        seg, off, _ = pc.labels['_backpal']
        M[(seg << 4) + off:(seg << 4) + off + 48] = s.backpal
        for a in range(256):
            b = a if a < 16 else a & 7
            rgb = [s.backpal[b * 3 + k] + (16 if (a & 8) and a > 15 else 0) for k in range(3)]
            DAC[a * 3:a * 3 + 3] = bytes(min(v, 63) for v in rgb)
        seg, off, _ = pc.labels['_lightshift']
        M[(seg << 4) + off] = 9
        M[BGPIC << 4:(BGPIC << 4) + 64000] = self.vram
        for p in pc.planes: p[:64000] = self.vram
        s.pal = bytes(DAC[:48])
        self.started = True

    def tick(self):
        if not self.floor.done:
            self.floor.step()
            if not self.floor.done: return
        if self.pause < FALL_PAUSE:
            self.pause += 1
            if self.pause == FALL_PAUSE: self.begin_main()
            return
        s = self.script
        s.step()
        if s.erase_row is not None:
            y = s.erase_row
            M[(BGPIC << 4) + y * 320:(BGPIC << 4) + y * 320 + 640] = bytes(640)
            for p in pc.planes: p[y * 320:y * 320 + 640] = bytes(640)
        seg, off, _ = pc.labels['_backpal']
        M[(seg << 4) + off:(seg << 4) + off + 48] = s.backpal
        seg, off, _ = pc.labels['_lightshift']
        M[(seg << 4) + off] = s.lightshift
        DAC[:48] = s.pal                    # the retrace routine uploads colours 0-15 every frame
        dm = pc.labels['_demomode']
        SG['ds'] = DATAV
        asm('__newgroup', ax=0)
        if s.xscale > 4:
            pc.wr(dm[0], dm[1], 2, pc.rd(dm[0], dm[1] + 2, 2))
            self.object(s.rx, s.ry, s.rz, A_POINTS, (s.xscale, s.yscale, s.zscale),
                        (s.oxp, s16(s.ypos + 1500 + s.oyp), s16(s.zpos + s.ozp)), s.frame < 800, A_EPOLYS)
        if s.frame > 800 and s.bscale > 4:
            pc.wr(dm[0], dm[1], 2, pc.rd(dm[0], dm[1] + 4, 2))
            self.object(3600 - s.rx // 3, 3600 - s.ry // 3, 3600 - s.rz // 3, A_POINTSB, (s.bscale,) * 3,
                        (s.oxb, s16(s.ypos + 1500 + s.oyb), s16(s.zpos + s.ozb)), False, A_EPOLYSB)
        asm('__newgroup', ax=2)
        self.vram = pc.planes[0][:64000]

    def object(self, rx, ry, rz, points, scale, move, clip, polys):
        c_call('_cmatrix_yxz', rx, ry, rz, A_MATRIX, WORK)
        self.set_matrix(0, 0, 0)
        pc.wr(WORK, A_POINTS2B, 2, 0)
        asm('rotlist', ds=WORK, si=points, es=WORK, di=A_POINTS2B)
        for i in range(9): pc.wr(WORK, A_MATRIX + i * 2, 2, 0)
        for i in range(3): pc.wr(WORK, A_MATRIX + i * 8, 2, scale[i] * 64)
        self.set_matrix(*move)
        pc.wr(WORK, A_POINTS2, 2, 0)
        asm('rotlist', ds=WORK, si=A_POINTS2B, es=WORK, di=A_POINTS2)
        if clip: asm('cliplist', ds=WORK, si=A_POINTS2)
        pc.wr(WORK, A_POINTS3, 2, 0)
        asm('projlist', ds=WORK, si=A_POINTS2, es=WORK, di=A_POINTS3)
        c_call('_ceasypolylist', A_POLYLIST, WORK, polys, WORK, A_POINTS3, WORK)
        SG['ds'] = DATAV
        asm('__newgroup', ax=1, es=WORK, di=A_POLYLIST)

    def set_matrix(self, x, y, z):
        for n, v in (('xadd', x), ('yadd', y), ('zadd', z)):
            seg, off, _ = pc.labels[n]
            pc.wr(seg, off, 4, v & 0xFFFFFFFF)
        asm('setmatrix', ds=WORK, si=A_MATRIX)

def write_png(name, pixels, pal):
    rows = b''
    for y in range(200):
        line = b''.join(bytes(min(255, c * 255 // 63) for c in pal[p * 3:p * 3 + 3]) for p in pixels[y * 320:(y + 1) * 320])
        rows += b'\0' + line
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    open(name, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 320, 200, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))

# ----------------------------------------------------------------------------------------------
def check_tables():
    vals = []
    for l in read_lines('MATHSIN.INC'):
        l = l.strip().lower()
        if l.startswith('dw'): vals += [int(x) for x in l[2:].replace(' ', '').replace('\t', '').split(',') if x]
    calc = [int(math.sin(i * 2 * math.pi / 3600) * 32767 + 0.5) for i in range(4500)]
    bad = [(i, vals[i], calc[i]) for i in range(4500) if vals[i] != calc[i]]
    print('MATHSIN.INC sine, 4500 entries: trunc(sin * 32767 + 0.5) differs at', bad)
    print('  checksum of the 4500 file values:', zlib.crc32(b''.join(struct.pack('<h', v) for v in vals[:4500])))
    file = []
    for l in read_lines('SIN1024.INC'):
        l = l.strip().lower()
        if l.startswith('dw'): file += [int(x) for x in l[2:].split(',') if x.strip()]
    print('SIN1024.INC equals trunc(sin * 256):', file == sin1024)
    fc = open(os.path.join(SRC, 'FC.UH'), 'rb').read()
    ob = open(os.path.join(SRC, '_FC.OBK'), 'rb').read()
    i, data = 0, bytearray()
    while i < len(ob):
        t, n = ob[i], ob[i + 1] | ob[i + 2] << 8
        if t == 0xA0: data += ob[i + 6:i + 3 + n - 1]
        i += 3 + n
    print('_FC.OBK (linked) holds FC.UH exactly:', bytes(data[:len(fc)]) == fc)
    print('floor art checksum (108 rows):', zlib.crc32(fc[784:784 + 108 * 320]), ' palette:', zlib.crc32(fc[16:64]))
    print('(the program reads only rows 0-107 of the picture: 100 of plate, 8 of its front edge)')

def emit_art():
    fc = open(os.path.join(SRC, 'FC.UH'), 'rb').read()
    rows = ['        "' + ''.join('%x' % p for p in fc[784 + y * 320:784 + (y + 1) * 320]) + '",' for y in range(108)]
    pal = ', '.join(str(v) for v in fc[16:64])
    print('''// Made by tools/glenz_reference.py --art from GLENZ/FC.UH. Do not edit by hand.
//
// THIS FILE IS ORIGINAL ARTWORK from Second Reality (Future Crew, 1993; released into the public
// domain with the rest of the source): the hand-drawn chequered plate the glenz lands on. It is
// the top 108 rows of the 320x200, 16-colour picture FC.UH, which the original program linked in
// as _FC.OBK. No formula reproduces it (the squares are shaded by hand), so it is kept as data.

enum GlenzFloorArt {
    static let width = 320
    static let height = 108

    /// The picture's 16 colours: red, green, blue, each 0...63.
    static let palette: [UInt8] = [%s]

    /// One text row per picture row; each character is one pixel's colour number as a hex digit.
    static let rows: [String] = [
%s
    ]

    /// The pixels as colour numbers, row by row.
    static let pixels: [UInt8] = rows.flatMap { row in row.utf8.map { $0 < 58 ? $0 - 48 : $0 - 87 } }
}''' % (pal, '\n'.join(rows)))

if __name__ == '__main__':
    args = sys.argv[1:]
    png = False
    if args and args[0] == '--tables': check_tables(); sys.exit(0)
    if args and args[0] == '--art': emit_art(); sys.exit(0)
    if args and args[0] == '--png': png = True; args.pop(0)
    steps = sorted(int(a) for a in args)
    m = Machine()
    for step in range(0, max(steps) + 1):
        if step > 0: m.tick()
        if step in steps:
            print('step %d (frame %d): screen %d palette %d  edges starting below the screen so far %d' % (
                step, m.script.frame, zlib.crc32(bytes(m.vram)), zlib.crc32(bytes(DAC)), skipped_edges[0]), flush=True)
            if png: write_png('glenz%04d.png' % step, m.vram, DAC)
