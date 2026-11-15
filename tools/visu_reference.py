#!/usr/bin/env python3
"""Reference pictures for the VISU 3D engine, made by running the ORIGINAL assembly.

VISU (coder Psi) is the 3D engine behind two parts of Second Reality: the ships fly-by (U2A.EXE)
and the 3D city (U2E.EXE). Its assembly files are read here AS TEXT and carried out one
instruction at a time by the small x86 interpreter in tools/x86interp.py:

  - ACALC.ASM    matrices, turning points and normals, perspective  (calc_*)
  - ADRAW.ASM    one object's polygons: hidden-face test, lighting, building edge lists (draw_polylist)
  - ADRAWCLP.ASM clipping against the near plane and the four window edges
  - AVID.ASM, AVIDM1.ASM, AVIDFILL.ASM   window, field of view, clearing, the two polygon fillers
  - ADATA.ASM with ADATASIN.INC, AVISTAN.INC, AFILLDIV.INC   variables and tables

The C side (VISU.C `vis_loadobject` / `vis_drawobject`, and the scene programs U2A.C / U2E.C:
reading the animation, ordering the objects) is re-written here in Python.

Departures from running the text exactly as written (none changes a result):
  - `fastmovsb` / `faststosb` (block copy / block fill written as 512 hand-encoded instructions that
    are jumped into) are replaced by a plain byte copy / fill of the same bytes.
  - The Gouraud fillers jump INTO a run of 641 repeated instruction pairs ("jmp ax", 7 bytes a
    pair). The jump is carried out by counting pairs instead of bytes. `--check-exe` confirms from
    the shipped program files that a pair really is 7 bytes.
  - The C calling wrappers (CBEG / CEND) and the call through `drawfill_routine` are replaced by
    direct calls; arguments are laid out in memory as the C compiler laid them out.
  - Video mode set-up (BIOS calls, VGA registers other than the plane mask) is not run; the
    variables `m1o_init` sets are set by running `m1o_init` itself.
If the assembly would divide with a result too large for its register (a crash on a real PC) the
tool stops with an error.

Usage:
  python3 tools/visu_reference.py                 all test cases: name and CRC-32 of the 320x200 picture
  python3 tools/visu_reference.py --png DIR       also write each picture as a PNG into DIR
  python3 tools/visu_reference.py --case NAME     only that case (may be repeated)
  python3 tools/visu_reference.py --tables        check the three tables against their generator formulas
  python3 tools/visu_reference.py --check-exe     check instruction sizes and constants in U2A.EXE / U2E.EXE
  python3 tools/visu_reference.py --info          sizes, objects and animation lengths of both scenes
  python3 tools/visu_reference.py --trace NAME    one case, printing what each object and polygon did

The test cases are listed in CASES below; App/SelfTest.swift (through Core/Visu/VisuTestCases.swift)
runs the same list through the Swift replay and expects the same numbers.
Development tool only; the app does not use it.
"""
import re, sys, os, struct, zlib, math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import x86interp as pc

ORIGINAL = os.path.join(HERE, '..', '..', 'secondreality')
SRC = os.path.join(ORIGINAL, 'VISU')
DATA_DIR = os.path.join(HERE, '..', 'Data', 'Visu')        # the app's copies of the scene files
M, R, SG, F, STACK = pc.M, pc.R, pc.SG, pc.F, pc.STACK
s16, s32 = pc.s16, pc.s32

# ----------------------------------------------------------------------------------------------
# Reading the source text and turning it into the interpreter's dialect.
# ----------------------------------------------------------------------------------------------
SKIP_INCLUDES = {'atext.asm', 'avidm2.asm'}      # the debugging font and the 640x400 mode: never used here
included_once = set()

def read_file(name):
    text = open(os.path.join(SRC, name.upper()), 'rb').read().decode('latin1').replace('\r', '').replace('\x1a', '')
    out = []
    for l in text.split('\n'):
        l = l.split(';')[0].rstrip().lower()
        m = re.match(r'^\s*include\s+(\S+)', l)
        if m:
            inc = m.group(1)
            if inc in SKIP_INCLUDES: continue
            if inc in ('a.inc', 'ad.inc'):
                if inc in included_once: continue
                included_once.add(inc)
            out += read_file(inc)
            continue
        out.append(l)
    return out

base_evaluate = pc.evaluate
def evaluate(expr):
    """Constant expressions, including the assembler's word operators."""
    e = pc.NUM.sub(lambda m: str(pc.number(m.group(1))), expr)
    for word, sign in (('and', '&'), ('or', '|'), ('not', '~'), ('shr', '>>'), ('shl', '<<')):
        e = re.sub(r'\b%s\b' % word, sign, e)
    if not re.fullmatch(r'[0-9+\-*/()&|~<> \t]+', e):
        raise ValueError('not a constant: ' + expr)
    return int(eval(e.replace('/', '//')))
pc.evaluate = evaluate

EQU = {}

def take_equates(lines, constants_with_equals):
    """Removes `name equ value` lines (and, for the include files, `NAME = value`) and remembers them."""
    out = []
    for l in lines:
        m = re.match(r'^\s*(\w+)\s+equ\s+(.+)$', l)
        if not m and constants_with_equals:
            m = re.match(r'^\s*(max\w+)\s*=\s*(.+)$', l)
        if m:
            EQU[m.group(1)] = str(evaluate(substitute(m.group(2))))
            continue
        out.append(l)
    return out

def substitute(l):
    if EQU:
        l = re.sub(r'\b(' + '|'.join(sorted(EQU, key=len, reverse=True)) + r')\b', lambda m: EQU[m.group(1)], l)
    return l

unique = [0]
def expand_rept(lines):
    """Unrolls REPT blocks, giving each copy its own LOCAL labels."""
    out, i = [], 0
    while i < len(lines):
        s = lines[i].strip()
        m = re.match(r'^(\S+:)\s*(rept\b.*)$', s)          # "label: REPT n"
        if m:
            out.append(m.group(1))
            s = m.group(2)
        if s.startswith('rept'):
            depth, j = 1, i + 1
            while True:
                u = lines[j].strip()
                if re.match(r'^(\S+:\s*)?rept\b', u): depth += 1
                if u == 'endm':
                    depth -= 1
                    if depth == 0: break
                j += 1
            body = lines[i + 1:j]
            locals_ = []
            for b in body:
                m = re.match(r'^\s*local\s+(.*)$', b)
                if m: locals_ += [x.strip() for x in m.group(1).split(',')]
            body = [b for b in body if not re.match(r'^\s*local\s', b)]
            for _ in range(evaluate(s[4:])):
                unique[0] += 1
                copy = body
                for l in locals_:
                    copy = [re.sub(r'\b%s\b' % l, 'r%d_%s' % (unique[0], l), b) for b in copy]
                out += expand_rept(copy)
            i = j + 1
            continue
        out.append(lines[i]); i += 1
    return out

def fold_constants(l):
    """Replaces bracketed constant sub-expressions such as (0+1)*2 by their value."""
    if re.match(r'^\s*(\w+\s+)?(db|dw|dd)\b', l): return l
    while True:
        done = True
        for m in re.finditer(r'\(([^()]*)\)', l):
            try: v = evaluate(m.group(1))
            except Exception: continue
            l = l[:m.start()] + str(v) + l[m.end():]
            done = False
            break
        if done: return l

SKIP = re.compile(r'^(\.386|locals|assume|public|extrn|global|align|end|ideal|\.model|\.code)\b')

def translate(lines):
    """One instruction or data line per entry. @@ labels are made unique per procedure here
    (procedures nest in AVIDFILL.ASM, which the base assembler does not follow)."""
    out, procs = [], ['']
    def qualify(s):
        return re.sub(r'@@(\w+)', lambda m: '%s__%s' % (procs[-1], m.group(1)), s)
    for s in lines:
        s = s.strip()
        if not s or SKIP.match(s) or re.match(r'^\w+\s+(segment|ends)\b', s):
            continue
        m = re.match(r'^(\w+)\s+proc\b', s)
        if m:
            procs.append(m.group(1)); out.append('PROC ' + m.group(1)); continue
        if re.match(r'^(\w+\s+)?endp\b', s):
            if len(procs) > 1: procs.pop()
            continue
        m = re.match(r'^(\w+)\s+label\s+(\w+)', s)
        if m:
            out.append('LABEL %s %s' % (m.group(1), m.group(2))); continue
        if re.match(r'^\w+\s*=', s):
            out.append(s); continue
        m = re.match(r'^(?:(\w+)\s+)?(db|dw|dd)\s+(.*)$', s)
        if m:
            out.append((m.group(1) + ' ' if m.group(1) else '') + m.group(2) + ' ' + pc.dup_expand(m.group(3)))
            continue
        s = qualify(s)
        m = re.match(r'^(\w+):\s*(.*)$', s)
        if m:
            out.append(m.group(1) + ':')
            s = m.group(2)
            if not s: continue
        parts = s.split(None, 1)
        if len(parts) == 2 and parts[0] not in ('rep',):
            s = parts[0] + ' ' + ','.join(pc.normal_operand(a) for a in parts[1].split(','))
        out.append(s)
    return out

# ----------------------------------------------------------------------------------------------
# Extra instructions (a third layer over the interpreter's two).
# ----------------------------------------------------------------------------------------------
pc.install_masm_layer()
masm_parse, masm_compile = pc.parse_operand, pc.compile_instruction
seq_index = [0]                 # VGA sequencer: which register port 3C5 addresses
out_of_page = [0]

def parse_operand(text, proc):
    m = re.match(r'offset\s+(\w+)$', text.strip())
    if m and m.group(1) not in pc.labels:            # the address of code: its instruction index
        name = m.group(1)
        return {'kind': 'imm', 'size': None, 'get': lambda: pc.code_labels[name]}
    m = re.match(r'offset\s+(\w+)\s*\+\s*(.+)$', text.strip())
    if m:
        v = pc.labels[m.group(1)][1] + evaluate(m.group(2))
        return {'kind': 'imm', 'size': None, 'get': lambda: v}
    return masm_parse(text, proc)

def setreg16(i, v): R[i] = (R[i] & 0xFFFF0000) | (v & 0xFFFF)

def compile_instruction(text, proc):
    parts = text.split(None, 1)
    op = parts[0]
    rest = parts[1] if len(parts) > 1 else ''
    args = [a.strip() for a in rest.split(',')] if rest else []
    if op == 'movsb':
        def f():
            pc.wr8(SG['es'], R[7] & 0xFFFF, pc.rd8(SG['ds'], R[6] & 0xFFFF))
            setreg16(6, R[6] + 1); setreg16(7, R[7] + 1)
        return f
    if op == 'cmc':
        def f(): F[0] ^= 1
        return f
    if op == 'cwd':
        def f(): setreg16(2, 0xFFFF if R[0] & 0x8000 else 0)
        return f
    if op in ('js', 'jns'):
        want = 1 if op == 'js' else 0
        return lambda: pc.code_labels[rest] if F[2] == want else None
    if op == 'jmpback':
        def f():
            n7 = (-R[0]) & 0xFFFF
            assert n7 % 7 == 0 and n7 // 7 <= 641, 'computed jump outside the unrolled loop'
            return pc.code_labels[rest] - 2 * (n7 // 7)
        return f
    if op == 'call' and rest in pc.REG:
        get = parse_operand(rest, proc)['get']
        return lambda: pc.run(get())
    if op == 'lea':
        d = parse_operand(args[0], proc)
        addr = parse_operand(args[1], proc)['addr']
        return lambda: d['set'](addr()[1])
    if op == 'lfs':
        d, s = parse_operand(args[0], proc), parse_operand(args[1], proc)
        addr = s['addr']
        def f():
            sg, off = addr()
            d['set'](pc.rd(sg, off, 2))
            SG['fs'] = pc.rd(sg, off + 2, 2)
        return f
    if op == 'out':
        wide = args[1] == 'ax'
        def f():
            port = R[2] & 0xFFFF
            if port == 0x3C4:
                seq_index[0] = R[0] & 0xFF
                if wide and seq_index[0] == 2: pc.PM[0] = (R[0] >> 8) & 0x0F
            elif port == 0x3C5:
                assert not wide
                if seq_index[0] == 2: pc.PM[0] = R[0] & 0x0F
            elif port == 0x3D4:
                pass                                   # display start address: page flipping, not modelled
            else:
                raise RuntimeError('port %x written' % port)
        return f
    if op in ('mul', 'idiv') and len(args) == 1:
        o = parse_operand(args[0], proc)
        if o['kind'] == 'mem': pc.finish(o, o['size'])
        size = o['size']; bits = size * 8; mask = (1 << bits) - 1
        assert size in (2, 4), text
        def put(lo, hi):
            if size == 2: setreg16(0, lo); setreg16(2, hi)
            else: R[0], R[2] = lo & mask, hi & mask
        if op == 'mul':
            def f():
                p = (R[0] & mask) * o['get']()
                put(p & mask, p >> bits)
                F[0] = F[3] = 1 if p >> bits else 0
            return f
        def f():
            n = ((R[2] & mask) << bits) | (R[0] & mask)
            if n >> (2 * bits - 1): n -= 1 << (2 * bits)
            d = o['get']()
            if d >> (bits - 1): d -= 1 << bits
            if d == 0: raise RuntimeError('divide by zero: ' + text)
            q = abs(n) // abs(d)
            if (n < 0) != (d < 0): q = -q
            if not -(1 << (bits - 1)) <= q < (1 << (bits - 1)):
                raise RuntimeError('divide overflow (a crash on a real PC): %s  %d / %d' % (text, n, d))
            put(q & mask, (n - q * d) & mask)
        return f
    if op in ('sar', 'sal', 'shl', 'shr', 'rol', 'rcl'):
        d, c = parse_operand(args[0], proc), parse_operand(args[1], proc)
        if d['kind'] == 'mem': pc.finish(d, d['size'])
        size = d['size']; bits = size * 8; mask = (1 << bits) - 1
        count = c['get']
        def f():
            a, n = d['get'](), count() & 31
            if n == 0: return
            if op == 'rcl':
                assert n == 1
                res = ((a << 1) | F[0]) & mask
                F[0] = a >> (bits - 1)
                d['set'](res)
                return
            if op == 'rol':
                n %= bits
                res = ((a << n) | (a >> (bits - n))) & mask
                F[0] = res & 1
                d['set'](res)
                return
            if op == 'sar':
                sa = a - (1 << bits) if a >> (bits - 1) else a
                res = (sa >> n) & mask
                F[0] = (sa >> (n - 1)) & 1
            elif op == 'shr':
                res = a >> n
                F[0] = (a >> (n - 1)) & 1
            else:
                res = (a << n) & mask
                F[0] = (a >> (bits - n)) & 1 if n <= bits else 0
            F[3] = 0
            pc.flags_result(res, bits)
            d['set'](res)
        return f
    if op == 'in' or op == 'int' or (op == 'rep' and rest != 'stosw'):
        def f(): raise RuntimeError('not modelled: ' + text)
        return f
    if op == 'rep':                                    # rep stosw (clearing video memory in the mode set-up)
        def f(): raise RuntimeError('not modelled: ' + text)
        return f
    return masm_compile(text, proc)

pc.parse_operand = parse_operand
pc.compile_instruction = compile_instruction

# ----------------------------------------------------------------------------------------------
# Memory map and loading.
# ----------------------------------------------------------------------------------------------
DATA, CODE, WORK, HEAP0, HEAP1 = 0x1000, 0x2000, 0x3000, 0x4000, 0xA000
ARGS = 0xF000                 # offset in WORK where C arguments are laid out (bp+6 ...)
POLYDRW = None
trace = [None]                # a list that collects what happened, when tracing

def load():
    import tempfile
    lines = {}
    for name in ('adata.asm', 'acalc.asm', 'adraw.asm', 'avid.asm'):
        lines[name] = read_file(name)
    macros = {}
    for name in lines:
        l = take_equates(lines[name], True)
        l = [substitute(x) for x in l]
        l = pc.collect_macros(l, macros)
        lines[name] = l
    macros['cbeg'] = ([], ['\tloadds'])
    macros['cend'] = ([], ['\tret'])
    macros['cbegr'] = (['bytes'], ['\tloadds'])
    macros['cendr'] = ([], ['\tret'])
    folder = tempfile.mkdtemp()
    pc.SRC = folder
    for name, seg in (('adata.asm', DATA), ('acalc.asm', CODE), ('adraw.asm', CODE), ('avid.asm', CODE)):
        l = expand_rept(lines[name])
        l = pc.expand_all(l, macros)
        l = [fold_constants(x) for x in l]
        l = translate(l)
        if name == 'adraw.asm':
            at = l.index('call [cs:drawfill_routine]')
            assert l[at - 2:at + 2] == ['push es', 'push offset _polydrw', 'call [cs:drawfill_routine]', 'add sp,4'], l[at - 2:at + 2]
            l[at - 2:at + 2] = ['call vid_drawfill_direct']
            l = [re.sub(r'^(drawfill_routine0? dd) _vid_drawfill$', r'\1 0', x) for x in l]
            # hooks for --trace (they change nothing)
            at = l.index('_draw_polylist__nocl:')
            l[at + 1:at + 1] = ['call trace_poly']
            l += ['PROC trace_poly', 'ret', 'PROC trace_fill', 'ret']
            at = l.index('call vid_drawfill_direct')
            l[at:at] = ['call trace_fill']
        if name == 'avid.asm':
            cut = l.index('LABEL fastmovsb_bt word')
            assert l[cut - 1].startswith('jmp drawfill_grd__1'), l[cut - 1]
            l = l[:cut] + ['PROC fastmovsb', 'ret', 'PROC faststosb', 'ret']
            fixed, proc = [], ''
            for x in l:
                m = re.match(r'^PROC (\w+)', x)
                if m: proc = m.group(1)
                if x == 'add ax,offset %s__vdfg_fcode' % proc: continue
                if x == 'jmp ax' and proc.startswith('gouraud'): x = 'jmpback %s__vdfg_fcode' % proc
                fixed.append(x)
            l = fixed
            assert sum(1 for x in l if x.startswith('jmpback')) == 3
            l += ['PROC vid_drawfill_direct', 'push bp', 'push si', 'push di', 'push ds',
                  'mov ax,seg _datanull', 'mov ds,ax', 'call vidstart',
                  'mov ax,seg _datanull', 'mov fs,ax', 'mov si,offset _polydrw',
                  'mov bx,[ds:si]', 'cmp bx,1', 'ja vdd_done', 'add bx,bx', 'add si,2',
                  'call [drawfill_progs+bx]',
                  'vdd_done:', 'pop ds', 'pop di', 'pop si', 'pop bp', 'ret']
        open(os.path.join(folder, name), 'w').write('\n'.join(l) + '\n')
        if name == 'acalc.asm': here = pc.assemble(name, seg)
        elif seg == CODE: here = assemble_at(name, seg, here)
        else: pc.assemble(name, seg)
    for seg, off, name in pc.fixups:
        pc.wr(seg, off, 2, pc.code_labels[name])

    def movs():
        n = R[1] & 0xFFFF
        assert n < 2048
        for i in range(n):
            pc.wr8(SG['es'], (R[7] + i) & 0xFFFF, pc.rd8(SG['ds'], (R[6] + i) & 0xFFFF))
        setreg16(6, R[6] + n); setreg16(7, R[7] + n)
        return -1
    def stos():
        n = R[1] & 0xFFFF
        assert n < 2048
        for i in range(n):
            pc.wr8(SG['es'], (R[7] + i) & 0xFFFF, R[0] & 0xFF)
        setreg16(7, R[7] + n)
        return -1
    pc.code[pc.code_labels['fastmovsb']] = movs
    pc.code[pc.code_labels['faststosb']] = stos

    def trace_poly():
        if trace[0] is not None:
            trace[0].append(('poly', R[6] & 0xFFFF))
        return -1
    def trace_fill():
        if trace[0] is not None:
            seg, off, _ = pc.labels['_polydrw']
            trace[0].append(('fill', bytes(M[(seg << 4) + off:(seg << 4) + off + 96])))
        return -1
    pc.code[pc.code_labels['trace_poly']] = trace_poly
    pc.code[pc.code_labels['trace_fill']] = trace_fill

def assemble_at(name, seg, start):
    """pc.assemble always starts a file's data at offset 0; the three code files share one segment,
    so the later ones are padded to start where the previous one stopped."""
    path = os.path.join(pc.SRC, name)
    text = open(path).read()
    open(path, 'w').write('pad_%s db %d dup(?)\n' % (name.split('.')[0], start) + text)
    return pc.assemble(name, seg)

def asm(name, **regs):
    for k, v in regs.items():
        if k in SG: SG[k] = v
        else: pc.parse_operand(k, '')['set'](v & 0xFFFFFFFF)
    SG['cs'] = CODE
    pc.run(pc.code_labels[name])

def c_call(name, *words):
    """Calls a C-callable routine: 16-bit words at [bp+6], [bp+8] ... as the C compiler pushed them."""
    for i, w in enumerate(words):
        pc.wr(WORK, ARGS + 6 + i * 2, 2, w & 0xFFFF)
    SG['ss'] = WORK
    asm(name, bp=ARGS, sp=ARGS - 0x400)
    return ((R[2] & 0xFFFF) << 16) | (R[0] & 0xFFFF)

def far(p): return (p[1], p[0])                  # a far pointer as two words: offset, then segment
def long(v): return (v & 0xFFFF, (v >> 16) & 0xFFFF)

heap = [HEAP0]
def getmem(size):
    """Each block gets its own segment, offset 0, as the original's halloc gave. Blocks start
    filled with 0xCC so that a result cannot quietly depend on what an earlier test case left."""
    seg = heap[0]
    heap[0] += size // 16 + 1
    assert heap[0] <= HEAP1, 'out of memory'
    M[seg << 4:heap[0] << 4] = b'\xCC' * ((heap[0] - seg) << 4)
    return (seg, 0)

def reset_engine():
    """The engine's one variable that is never set back: the clipper's `clipvisfl` (see docs).
    Every test case starts with it at zero, as when the program has just been loaded."""
    seg, off, _ = pc.labels['clipvisfl']
    pc.wr(seg, off, 2, 0)

def put(p, data):
    lin = (p[0] << 4) + p[1]
    M[lin:lin + len(data)] = data

def get(p, n):
    lin = (p[0] << 4) + p[1]
    return bytes(M[lin:lin + n])

def getvar(name):
    seg, off, size = pc.labels[name]
    return s32(pc.rd(seg, off, size)) if size == 4 else s16(pc.rd(seg, off, size))

# ----------------------------------------------------------------------------------------------
# VISU.C in Python.
# ----------------------------------------------------------------------------------------------
F_DEFAULT, F_VISIBLE, F_GOURAUD = 0xF001, 0x0001, 0x1000

class Obj:
    pass

def vis_loadobject(data):
    o = Obj()
    base = getmem(len(data))
    put(base, data)
    o.flags = F_DEFAULT
    o.r = getmem(48); o.r0 = getmem(48)
    o.pl = [None]
    o.plnum = 1
    d = 0
    while True:
        tag = data[d:d + 4]
        length = struct.unpack_from('<I', data, d + 4)[0]
        body = d + 8
        if tag == b'END ': break
        elif tag == b'VERS': assert struct.unpack_from('<H', data, body)[0] == 0x100
        elif tag == b'NAME': o.name = data[body:data.index(b'\0', body)].decode('latin1')
        elif tag == b'VERT':
            o.vnum = struct.unpack_from('<H', data, body)[0]
            o.v0 = (base[0], body + 4)
            o.v = getmem(16 * o.vnum)
            o.pv = getmem(16 * o.vnum)
        elif tag == b'NORM':
            o.nnum, o.nnum1 = struct.unpack_from('<HH', data, body)
            o.n0 = (base[0], body + 4)
            o.n = getmem(16 * o.nnum)
        elif tag == b'POLY': o.pd = (base[0], body)
        elif tag == b'ORD0': o.pl[0] = (base[0], body)
        elif tag == b'ORDE': o.pl.append((base[0], body)); o.plnum += 1
        else: raise ValueError('unknown block %r' % tag)
        d = body + length
    return o

def copy_object(g):
    o = Obj()
    o.__dict__.update(g.__dict__)
    o.r = getmem(48); o.r0 = getmem(48)
    return o

def vis_drawobject(o):
    if not o.flags & F_VISIBLE: return 'invisible'
    c_call('_calc_rotate', o.vnum, *far(o.v), *far(o.v0), *far(o.r))
    count = o.nnum if o.flags & F_GOURAUD else o.nnum1
    c_call('_calc_nrotate', count, *far(o.n), *far(o.n0), *far(o.r))
    o.vf = c_call('_calc_project', o.vnum, *far(o.pv), *far(o.v)) & 0xFFFF
    if o.vf: return 'off screen (flags %d)' % o.vf
    a, al = 0, 0x7FFFFFFF
    for b in range(1, o.plnum):
        c = struct.unpack('<H', get((o.pl[b][0], o.pl[b][1] + 2), 2))[0]
        bl = s32(struct.unpack('<I', get((o.v[0], o.v[1] + c * 16 + 8), 4))[0])
        if bl < al: al, a = bl, b
    c_call('_draw_polylist', *far(o.pl[a]), *far(o.pd), *far(o.v), *far(o.pv), *far(o.n), o.flags)
    return 'drawn with order list %d' % a

def read_matrix(p):
    return list(struct.unpack('<12i', get(p, 48)))

def write_matrix(p, m):
    put(p, struct.pack('<12i', *[s32(v) for v in m]))

# ----------------------------------------------------------------------------------------------
# The scene programs (U2A.C / U2E.C) in Python: loading, the animation stream, object order.
# ----------------------------------------------------------------------------------------------
class Scene:
    """`name` is U2A or U2E. Holds the objects ("co" in the C source), camera and animation."""
    def __init__(self, name):
        self.name = name
        folder = DATA_DIR if os.path.exists(os.path.join(DATA_DIR, name + '.00M')) else os.path.join(SRC, 'C', 'SCENE')
        self.read = lambda ext: open(os.path.join(folder, '%s.%s' % (name, ext)), 'rb').read()
        mat = self.read('00M')
        self.palette = bytearray(mat[16:16 + 768])
        self.city = 1 if mat[15:16] == b'C' else 2 if mat[15:16] == b'R' else 0
        at = struct.unpack_from('<I', mat, 4)[0]
        self.conum = struct.unpack_from('<H', mat, at)[0]
        files = struct.unpack_from('<%dH' % (self.conum - 1), mat, at + 2)
        self.co = [None] * self.conum
        self.index = [0] * self.conum
        self.on = [0] * self.conum
        self.dist = [0] * self.conum
        newest = -1
        for c in range(1, self.conum):
            e = files[c - 1]
            if e > newest:
                newest = e
                self.co[c] = vis_loadobject(self.read('%03d' % e))
            else:
                g = next(g for g in range(c) if self.index[g] == e and g > 0)
                self.co[c] = copy_object(self.co[g])
            self.index[c] = e
            write_matrix(self.co[c].r, [0] * 12); write_matrix(self.co[c].r0, [0] * 12)
        cam = Obj(); cam.r = cam.r0 = getmem(48); cam.name = 'camera'
        write_matrix(cam.r, [0] * 12)                # a static variable in C: starts as zeros
        self.co[0] = cam
        self.cam = cam.r
        anims = self.read('0AA')
        first = struct.unpack_from('<h', anims, 0)[0]
        self.stream = self.read('0%c%c' % (65 + first // 10, 65 + first % 10))
        self.sp = 0
        self.fov = 0
        self.frame = 0
        self.ended = False

    def step(self):
        """Reads one frame of the animation stream. False once the end marker has been read."""
        s = self.stream
        onum = 0
        while True:
            a = s[self.sp]; self.sp += 1
            if a == 0xFF:
                a = s[self.sp]; self.sp += 1
                if a <= 0x7F:
                    self.fov = a << 8
                    break
                elif a == 0xFF:
                    self.ended = True
                    return False
            if (a & 0xC0) == 0xC0:
                onum = (a & 0x3F) << 4
                a = s[self.sp]; self.sp += 1
            onum = (onum & 0xFF0) | (a & 0xF)
            if (a & 0xC0) == 0x80: self.on[onum] = 1
            elif (a & 0xC0) == 0x40: self.on[onum] = 0
            assert onum < self.conum
            r = read_matrix(self.co[onum].r0)
            pflag = 0
            nbytes = (a & 0x30) >> 4
            for i in range(nbytes):
                pflag |= s[self.sp] << (8 * i); self.sp += 1
            def lsget(f):
                f &= 3
                if f == 0: return 0
                n = (1, 2, 4)[f - 1]
                v = int.from_bytes(s[self.sp:self.sp + n], 'little', signed=True)
                self.sp += n
                return v
            r[9] = s32(r[9] + lsget(pflag))
            r[10] = s32(r[10] + lsget(pflag >> 2))
            r[11] = s32(r[11] + lsget(pflag >> 4))
            kind = 2 if pflag & 0x40 else 1
            for b in range(9):
                if pflag & (0x80 << b):
                    r[b] = s32(r[b] + lsget(kind))
            write_matrix(self.co[onum].r0, r)
        self.frame += 1
        return True

    def draw(self):
        """One picture of the current state, as the scene program's main loop draws it (after the
        screen has been cleared): field of view, object matrices, order, objects."""
        c_call('_vid_cameraangle', self.fov)
        order = []
        for a in range(1, self.conum):
            if not self.on[a]: continue
            order.append(a)
            o = self.co[a]
            put(o.r, get(o.r0, 48))
            c_call('_calc_applyrmatrix', *far(o.r), *far(self.cam))
            b = struct.unpack('<H', get((o.pl[0][0], o.pl[0][1] + 2), 2))[0]
            self.dist[a] = s32(c_call('_calc_singlez', b, *far(o.v0), *far(o.r)))
            if self.name == 'U2E':
                if o.name[1] == '_': self.dist[a] = 1000000000
                # U2E.C tests its own frame counter, which counts in twos: animation frame * 2
                if 900 * 2 < self.frame * 2 < 1100 * 2 and o.name[1:4] == 's01': self.dist[a] = 1
        if self.name == 'U2A':
            if self.city == 1:
                for k in (2, 7, 13): self.dist[k] = 1000000000
            if self.city == 2: self.dist[14] = 1000000000
        for a in range(len(order)):                 # the C insertion sort: farthest first
            c = order[a]; dis = self.dist[c]
            b = a - 1
            while b >= 0 and dis > self.dist[order[b]]:
                order[b + 1] = order[b]; b -= 1
            order[b + 1] = c
        log = []
        for a in order:
            log.append((a, self.co[a].name, self.dist[a], vis_drawobject(self.co[a])))
        return log

def start_video(window):
    """vid_init(3) / vid_init(11) (both set the same variables) and vid_window."""
    asm('m1o_init', ds=DATA)
    x1, x2, y1, y2, z1, z2 = window
    c_call('_vid_window', *long(x1), *long(x2), *long(y1), *long(y2), *long(z1), *long(z2))
    c_call('_vid_setswitch', 0, 0xFFFF)

def clear(colour):
    for p in pc.planes: p[:16000] = bytes([colour]) * 16000

def screen():
    """The 320x200 picture on video page 0, unscrambled from the four planes."""
    out = bytearray(64000)
    for y in range(200):
        for x in range(320):
            out[y * 320 + x] = pc.planes[x & 3][y * 80 + (x >> 2)]
    return out

WINDOW = (0, 319, 25, 174, 512, 9999999)         # U2A.C and U2E.C: vid_window(0L,319L,25L,174L,512L,9999999L)

# ----------------------------------------------------------------------------------------------
# Test cases. Keep this list in step with Core/Visu/VisuTestCases.swift.
#   ('frame', scene, animation frame)                      a whole picture of a scene
#   ('object', scene, object file number, field of view, (rotx, roty, rotz), (x, y, z))
#        one object alone: turned by calc_setrmatrix_rotyxz (angles 0..65535 = one turn) and placed
#        at x, y, z in front of a camera at the origin
# ----------------------------------------------------------------------------------------------
CASES = []
def case(name, *what): CASES.append((name,) + what)

for f in (20, 60, 100, 140, 180, 220, 262, 275, 300, 340, 380, 420, 460, 500, 520):
    case('ships-%04d' % f, 'frame', 'U2A', f)
for f in (1, 30, 75, 100, 170, 200, 260, 330, 400, 480, 560, 600, 680, 760, 800, 880, 905, 960, 1040, 1099,
          1101, 1180, 1260, 1340, 1420, 1460, 1500, 1580, 1660, 1740, 1800):
    case('city-%04d' % f, 'frame', 'U2E', f)

# One object alone. Position = where the object's centre vertex lands in front of the camera.
def obj(name, scene, number, fov, rot, pos, window=0):
    case(name, 'object', scene, number, fov, rot, pos, window)

SHIP_TURNS = [(0, 0, 0), (8000, 20000, 3000), (40000, 5000, 60000), (16384, 0, 0), (0, 16384, 0), (30000, 30000, 30000)]
for i, r in enumerate(SHIP_TURNS):
    obj('ship-turn%d' % i, 'U2A', 1, 8704, r, (0, 0, 2500))
# clipping: the ship (Gouraud) across each window edge, the corners and the near plane
for n, pos in (('left', (-530, 0, 1200)), ('right', (530, 0, 1200)), ('top', (0, -281, 1200)), ('bottom', (0, 281, 1200)),
               ('topleft', (-520, -270, 1200)), ('bottomright', (520, 270, 1200)), ('near', (0, 0, 600)),
               ('near-side', (250, -100, 520)), ('near-more', (-60, 40, 450)), ('behind', (0, 0, -100)),
               ('huge', (0, 0, 700)), ('far', (300, 100, 60000))):
    obj('ship-clip-' + n, 'U2A', 1, 8704, (8000, 20000, 3000), pos)
obj('ship-fullscreen-window', 'U2A', 1, 8704, (8000, 20000, 3000), (0, 0, 500), 1)
for i, fov in enumerate((0, 4000, 16000, 30000, 40000, 65535)):
    obj('ship-fov%d' % i, 'U2A', 1, fov, (50000, 9000, 1000), (0, 0, 2500))
obj('bigship-0', 'U2A', 2, 8704, (0, 0, 0), (0, 0, 150000))
obj('bigship-1', 'U2A', 2, 8704, (12000, 50000, 7000), (20000, -10000, 120000))
obj('bigship-inside', 'U2A', 2, 8704, (3000, 2000, 60000), (0, 0, 30000))
obj('bigship-under', 'U2A', 2, 8704, (49152, 0, 0), (0, -9000, 9000))
obj('engine-0', 'U2A', 3, 8704, (60000, 30000, 0), (0, 0, 100000))
obj('engine-1', 'U2A', 3, 8704, (20000, 10000, 40000), (10000, 5000, 80000))
# city objects: flat-shaded buildings, Gouraud trees, the logo, many-sided polygons
for i, r in enumerate([(0, 0, 0), (52000, 6000, 0), (20000, 40000, 9000)]):
    obj('building-turn%d' % i, 'U2E', 5, 7168, r, (0, 0, 40000))
for n, pos in (('left', (-9000, 0, 25000)), ('right', (12000, 0, 25000)), ('top', (0, -6000, 25000)),
               ('bottom', (0, 6000, 25000)), ('near', (0, 0, 4000)), ('near-corner', (2500, 1500, 3000)), ('inside', (0, 0, 0))):
    obj('building-clip-' + n, 'U2E', 5, 7168, (52000, 6000, 0), pos)
obj('tree-0', 'U2E', 9, 7168, (49152, 0, 0), (0, 0, 7000))
obj('tree-1', 'U2E', 9, 7168, (40000, 30000, 2000), (0, 0, 4000))
obj('tree-near', 'U2E', 9, 7168, (40000, 30000, 2000), (300, 200, 900))
obj('logo-0', 'U2E', 23, 7168, (49152, 0, 0), (0, 0, 120000))
obj('logo-1', 'U2E', 23, 7168, (45000, 60000, 3000), (0, 0, 90000))
obj('logo-near', 'U2E', 23, 7168, (45000, 60000, 3000), (10000, 0, 20000))
obj('block-0', 'U2E', 24, 7168, (52000, 9000, 0), (0, 0, 80000))
obj('block-near', 'U2E', 24, 7168, (52000, 9000, 0), (9000, 5000, 15000))
obj('car-0', 'U2E', 35, 7168, (52000, 9000, 0), (0, 0, 2000))
obj('car-1', 'U2E', 35, 7168, (30000, 50000, 20000), (100, 0, 900))
obj('columns-0', 'U2E', 34, 7168, (52000, 9000, 0), (0, 0, 20000))
obj('columns-near', 'U2E', 34, 7168, (52000, 9000, 0), (2000, 1000, 3000))
obj('plushouse-0', 'U2E', 39, 7168, (50000, 9000, 0), (0, 0, 45000))
obj('plushouse-near', 'U2E', 39, 7168, (50000, 9000, 0), (6000, 4000, 9000))
obj('cityship-0', 'U2E', 28, 7168, (10000, 20000, 0), (0, 0, 4000))
obj('cityship-near', 'U2E', 28, 7168, (10000, 20000, 0), (-300, 200, 1500))
obj('ground-0', 'U2E', 15, 7168, (44000, 3000, 0), (0, 3000, 30000))
obj('ground-under', 'U2E', 15, 7168, (48000, 3000, 0), (0, 2000, 12000))

WINDOWS = [WINDOW, (0, 319, 0, 199, 256, 1000000000)]

scenes = {}
def scene_objects(name):
    if name not in scenes: scenes[name] = Scene(name)
    return scenes[name]

def run_case(c):
    kind = c[1]
    reset_engine()
    clear(0)
    if kind == 'frame':
        start_video(WINDOW)
        sc = Scene(c[2])
        for _ in range(c[3]):
            if not sc.step(): raise RuntimeError('%s: the animation ends before frame %d' % (c[0], c[3]))
        return sc.draw()
    if kind == 'object':
        _, _, scene_name, number, fov, rot, pos, window = c
        start_video(WINDOWS[window])
        sc = scene_objects(scene_name)
        o = sc.co[sc.index.index(number, 1)]
        c_call('_vid_cameraangle', fov)
        c_call('_calc_setrmatrix_rotyxz', *far(o.r), rot[0], rot[1], rot[2])
        m = read_matrix(o.r)
        centre = struct.unpack('<H', get((o.pl[0][0], o.pl[0][1] + 2), 2))[0]
        cx, cy, cz = struct.unpack('<3i', get((o.v0[0], o.v0[1] + centre * 16), 12))
        for k in range(3):
            m[9 + k] = pos[k] - ((m[3 * k] * cx + m[3 * k + 1] * cy + m[3 * k + 2] * cz) >> 14)
        write_matrix(o.r, m)
        return [(number, o.name, 0, vis_drawobject(o))]
    raise ValueError(kind)

def png(path, pixels, palette):
    rows = bytearray()
    for y in range(200):
        rows.append(0)
        for x in range(320):
            c = pixels[y * 320 + x] * 3
            rows += bytes((palette[c] * 255 // 63, palette[c + 1] * 255 // 63, palette[c + 2] * 255 // 63))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 320, 200, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(bytes(rows))) + chunk(b'IEND', b''))

def case_palette(c):
    pal = bytearray(Scene.__new__(Scene).__class__(c[2]).palette) if False else None
    mat = open(os.path.join(SRC, 'C', 'SCENE', c[2] + '.00M'), 'rb').read()
    pal = bytearray(mat[16:784])
    if c[2] == 'U2A':
        bg = open(os.path.join(SRC, 'C', 'U2ABG.UH'), 'rb').read()
        pal[192 * 3:] = bg[16:16 + 192]
    return pal

# ----------------------------------------------------------------------------------------------
def check_tables():
    def words(name, n):
        seg, off, _ = pc.labels[name]
        return list(struct.unpack('<%dh' % n, bytes(M[(seg << 4) + off:(seg << 4) + off + 2 * n])))
    sin = words('_sintable', 4096)
    calc = [int(math.sin(2 * math.pi * r / 4096) * 16384 + 0.5) for r in range(4096)]
    print('ADATASIN.INC: 4096 entries; trunc(sin * 16384 + 0.5) differs at',
          [(i, sin[i], calc[i]) for i in range(4096) if sin[i] != calc[i]][:8], ' crc', zlib.crc32(struct.pack('<4096h', *sin)))
    tan = words('_avistan', 256)
    calc = [32767 if a < 2 else int(256 / math.tan(a * 2.0 * 3.141592653589 / 1024.0)) for a in range(256)]
    print('AVISTAN.INC: 256 entries; DOTAN.C formula differs at',
          [(i, tan[i], calc[i]) for i in range(256) if tan[i] != calc[i]][:8], ' crc', zlib.crc32(struct.pack('<256h', *tan)))
    div = [v & 0xFFFF for v in words('_afilldiv', 512)]
    calc = [min(65536 // max(z, 1), 65535) for z in range(512)]
    print('AFILLDIV.INC: 512 entries; DOFILL.C formula differs at',
          [(i, div[i], calc[i]) for i in range(512) if div[i] != calc[i]][:8], ' crc', zlib.crc32(struct.pack('<512H', *div)))

def check_exe():
    """Looks in the shipped programs for the bytes the departures above rely on."""
    for name in ('U2A.EXE', 'U2E.EXE'):
        d = open(os.path.join(SRC, 'C', name), 'rb').read()
        light = d.find(struct.pack('<3h', 12118, 10603, 3030))
        pair = re.compile(rb'(?:(?:\x03\xda|\x01\xd3)\x2e\x88\x3e..){641}', re.S)
        runs = [m.start() for m in pair.finditer(d)]
        tan = d.find(struct.pack('<6h', 32767, 32767, 20859, 13905, 10428, 8341))
        print('%s: light direction at %s; runs of 641 seven-byte "add bx,dx / mov cs:[n],bh" pairs at %s; tangent table at %s'
              % (name, light, runs, tan))
        for r in runs:
            after = d[r + 641 * 7:r + 641 * 7 + 2]
            print('   after the run at %d: %s (8b c3 or 89 d8 = the two-byte "mov ax,bx" filler)' % (r, after.hex()))

def info():
    for name in ('U2A', 'U2E'):
        heap[0] = HEAP0
        sc = Scene(name)
        frames = 0
        fovs = set()
        first_on = {}
        while sc.step():
            frames += 1
            fovs.add(sc.fov)
            for i in range(1, sc.conum):
                if sc.on[i] and i not in first_on: first_on[i] = frames
        print('%s: %d objects + camera, animation %d bytes, %d frames, field-of-view values %s, flag byte %r' % (
            name, sc.conum - 1, len(sc.stream), frames, sorted(fovs), sc.city))
        for i in range(1, sc.conum):
            o = sc.co[i]
            print('   co[%2d] file %03d %-12s vertices %3d normals %3d (%3d face) order lists %d  first shown at frame %s' % (
                i, sc.index[i], o.name, o.vnum, o.nnum, o.nnum1, o.plnum, first_on.get(i)))

if __name__ == '__main__':
    args = sys.argv[1:]
    out_dir, only, tracing = None, [], False
    load()
    while args:
        a = args.pop(0)
        if a == '--tables': check_tables(); sys.exit(0)
        elif a == '--check-exe': check_exe(); sys.exit(0)
        elif a == '--info': info(); sys.exit(0)
        elif a == '--png': out_dir = args.pop(0)
        elif a == '--case': only.append(args.pop(0))
        elif a == '--trace': only.append(args.pop(0)); tracing = True
    for c in CASES:
        if only and c[0] not in only: continue
        heap[0] = HEAP0
        scenes.clear()
        if tracing: trace[0] = []
        log = run_case(c)
        pixels = screen()
        print('%-22s %10d' % (c[0], zlib.crc32(bytes(pixels))), flush=True)
        if tracing:
            for entry in log: print('   ', entry)
            print('    polygons past the hidden-face test: %d, filled: %d' % (
                sum(1 for t in trace[0] if t[0] == 'poly'), sum(1 for t in trace[0] if t[0] == 'fill')))
        if out_dir:
            png(os.path.join(out_dir, c[0] + '.png'), pixels, case_palette(c))
