#!/usr/bin/env python3
"""A small x86 interpreter that runs original 1993 assembly SOURCE TEXT, shared by the reference tools.

It is not an emulator of a PC: it reads Turbo Assembler source as text, lays the data out in a 1 MB
memory, turns each instruction into a small Python function and runs those. It models the VGA card's
four bit planes and (optionally) its colour registers. It is used by

  tools/plasmacube_reference.py   (base layer only)
  tools/glenz_reference.py        (base layer + MASM layer)
  tools/visu_reference.py         (base layer + MASM layer + its own additions)
  tools/starfield_reference.py    (base layer + MASM layer)

Layers:
  1. the base: memory, registers, flags, a parser for IDEAL-style operands, about 35 instructions
     (written for the Plasma Cube);
  2. the MASM layer, switched on with install_masm_layer(): turns MASM-style text into the base
     dialect (macros with LOCAL labels, REPT, dup, "label: ENDM") and adds instructions, near and
     indirect calls and the VGA colour ports (written for Glenz Vectors).
The code of both layers was moved here unchanged from those two tools, so that what they check did
not change. Instructions that are not supported only fail if they are actually run. Development
tool only; the app does not use it.
"""
import re, sys, os, struct, zlib

SRC = ''             # folder assemble() reads files from; set by the tool
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


# ----------------------------------------------------------------------------------------------
# Turning the files' MASM-style text into the plain form the interpreter's assembler reads.
# ----------------------------------------------------------------------------------------------
def read_lines(name):
    text = open(os.path.join(MASM_SRC, name), 'rb').read().decode('latin1').replace('\r', '').replace('\x1a', '')
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
            if name in INCLUDE_SKIP:
                pass                         # only its macros are wanted; collected separately
            else:
                out += expand_all(collect_macros(read_lines(name), macros), macros)
            i += 1
            continue
        if up.startswith('REPT'):
            j = i + 1
            while lines[j].strip().upper() != 'ENDM': j += 1
            for _ in range(evaluate(s[4:])):
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
    if t in REG or t in SG or t.startswith('offset') or t.startswith('seg '):
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
        items = items[:m.start()] + ','.join([m.group(2)] * evaluate(m.group(1))) + items[m.end():]

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
base_parse, base_compile = parse_operand, compile_instruction
MASM_SRC = ''          # folder read_lines() reads from
INCLUDE_SKIP = set()   # INCLUDE files not to inline (their macros are collected separately)

def masm_parse_operand(text, proc):
    m = re.match(r'offset\s+(\w+)\s*\+\s*(\w+)$', text.strip().lower())
    if m:
        v = labels[m.group(1)][1] + evaluate(m.group(2))
        return {'kind': 'imm', 'size': None, 'get': lambda: v}
    return base_parse(text, proc)

def run(index):
    while index >= 0:
        r = code[index]()
        index = index + 1 if r is None else r

def set_logic_flags(res, bits):
    F[0] = F[3] = 0
    flags_result(res, bits)

def masm_compile_instruction(text, proc):
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
        o = masm_parse_operand(rest, proc)
        if o['kind'] == 'mem': finish(o, o['size'] or 2)
        if op == 'push': return lambda: STACK.append(o['get']())
        return lambda: o['set'](STACK.pop())
    if op == 'call':
        if rest.startswith('['):
            o = finish(masm_parse_operand(rest, proc), 2)
            return lambda: run(o['get']())
        name = lab(rest)
        def f():
            old = SG['cs']
            SG['cs'] = proc_segment.get(name, old)
            run(code_labels[name])
            SG['cs'] = old
        return f
    more = {'jg': lambda: not F[1] and F[2] == F[3], 'jle': lambda: F[1] or F[2] != F[3],
            'jng': lambda: F[1] or F[2] != F[3], 'jnl': lambda: F[2] == F[3],
            'jc': lambda: F[0], 'jnc': lambda: not F[0], 'jbe': lambda: F[0] or F[1],
            'jcxz': lambda: (R[1] & 0xFFFF) == 0}
    if op in more:
        cond, name = more[op], lab(rest)
        return lambda: code_labels[name] if cond() else None
    if op == 'lodsw':
        def f():
            R[0] = (R[0] & 0xFFFF0000) | rd(SG['ds'], R[6] & 0xFFFF, 2)
            R[6] = (R[6] & 0xFFFF0000) | ((R[6] + 2) & 0xFFFF)
        return f
    if op == 'movsw':
        def f():
            wr(SG['es'], R[7] & 0xFFFF, 2, rd(SG['ds'], R[6] & 0xFFFF, 2))
            R[6] = (R[6] & 0xFFFF0000) | ((R[6] + 2) & 0xFFFF)
            R[7] = (R[7] & 0xFFFF0000) | ((R[7] + 2) & 0xFFFF)
        return f
    if op == 'stosd' or (op == 'rep' and rest == 'stosd'):
        rep = op == 'rep'
        def f():
            n = (R[1] & 0xFFFF) if rep else 1
            for _ in range(n):
                wr(SG['es'], R[7] & 0xFFFF, 4, R[0])
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
        o = masm_parse_operand(args[0], proc)
        if o['kind'] == 'mem': finish(o, o['size'])
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
                flags_result(res, bits)
            return f
        return lambda: o['set'](~o['get']() & mask)
    if op in ('or', 'xchg', 'sbb', 'shrd'):
        ops = [masm_parse_operand(a, proc) for a in args]
        d, s = ops[0], ops[1]
        size = d['size'] or s['size']
        finish(d, size)
        if s['kind'] == 'mem': finish(s, size)
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
                flags_result(res, bits)
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

def install_masm_layer():
    """Switches the assembler to the extended operand parser and instruction set."""
    global parse_operand, compile_instruction
    parse_operand = masm_parse_operand
    compile_instruction = masm_compile_instruction
