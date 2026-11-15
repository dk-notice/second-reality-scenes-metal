#!/usr/bin/env python3
"""Reference pictures for the 3D Sine Landscape, made by running the ORIGINAL assembly.

This reads the original's generated inner loop (COMAN/THELOOP.INC) as text and carries out its
instructions one at a time in a tiny x86 interpreter, driven by MAIN.C's frame logic and the original
table files (W1DTA.BIN, W2DTA.BIN, SIN1024.INC). It prints a CRC-32 checksum of the 320x200 screen
(colour numbers) at the steps asked for; those numbers are what App/SelfTest.swift expects from the
Swift replay. It also writes each of those frames as referenceNNNN.png in the current folder.

Usage:  python3 tools/landscape_reference.py [--every N] [path-to-COMAN-folder] step [step ...]
        e.g. python3 tools/landscape_reference.py 100 200 700 1300 1978 2046   (takes a few minutes)

Steps are 1/70 s. One picture is drawn every N steps (default 2), as on a PC that needed N screen
refreshes per picture; ask only for steps that are multiples of N.

The start (rise from 160) is the original's. The sinking near the end and the stop before step 2048 are this
project's loop, not the original's ending. Development tool only; the app does not use it.
"""
import struct, re, sys, zlib, os
args=sys.argv[1:]
D=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','secondreality','COMAN','')
EVERY=2   # steps per drawn picture; must match SineLandscapeModel.ticksPerPicture
if args and args[0]=='--every': args.pop(0); EVERY=int(args.pop(0))
if args and not args[0].isdigit(): D=os.path.join(args.pop(0),'')
w1=open(D+'W1DTA.BIN','rb').read(); w2=open(D+'W2DTA.BIN','rb').read()
vals=[]
for line in open(D+'SIN1024.INC','rb').read().decode('latin1').splitlines():
    m=re.match(r'\s*(?:\w+\s+)?dw\s+(.*)',line,re.I)
    if m: vals+= [int(v) for v in re.findall(r'-?\d+',m.group(1))]
sin1024=vals; assert len(sin1024)==1024,len(sin1024)

lines=[l.strip() for l in open(D+'THELOOP.INC','rb').read().decode('latin1').replace('\r','').split('\n')]
start=lines.index('theloop PROC FAR')+1
prog=[]; labels={}
for l in lines[start:]:
    if not l or l.startswith(';'): continue
    if l=='theloop ENDP': break
    if l.endswith(':'): labels[l[:-1]]=len(prog); continue
    prog.append(l)
def imm(s):
    s=s.strip()
    if '*' in s: a,b=s.split('*'); return imm(a)*imm(b)
    if s.lower().endswith('h'): return int(s[:-1],16)
    return int(s)
R16={'ax':0,'cx':1,'dx':2,'bx':3,'si':4,'di':5,'bp':6}
R32={'eax':0,'ecx':1}
class S: pass
st=S()
def compile_ins(l):
    op,_,rest=l.partition(' '); args=[a.strip() for a in rest.split(',')] if rest else []
    def tgt(a):
        return a.replace('short','').strip()
    if op=='ret': return ('ret',)
    if op=='jmp': return ('jmp',tgt(args[0]))
    if op=='jge': return ('jge',tgt(args[0]))
    return (op,)+tuple(args)
code=[compile_ins(l) for l in prog]
def run(si,di,cx,dx,bp,ax,vbuf):
    reg=[0]*7   # 32-bit values for ax(eax),cx(ecx); others 16
    reg[0]=ax&0xffff; reg[1]=cx&0xffff; reg[2]=dx&0xffff; reg[4]=si&0xffff; reg[5]=di&0xffff; reg[6]=bp&0xffff
    var={}
    cf=0; ge=False; pc=0
    def g16(r): return reg[R16[r]]&0xffff
    def s16(r,v): i=R16[r]; reg[i]=(reg[i]&0xffff0000)|(v&0xffff)
    def sx(v): return v-65536 if v&0x8000 else v
    n=0
    while True:
        c=code[pc]; pc+=1; o=c[0]; n+=1
        if o=='ret': return n
        if o=='jmp': pc=labels[c[1]]; continue
        if o=='jge':
            if ge: pc=labels[c[1]]
            continue
        a,b=c[1],c[2]
        if o=='mov':
            if a.startswith('cs:'): var[a[3:]]=g16(b)
            elif a=='ds': pass
            elif a=='ax' and b=='cs': pass
            elif a=='ecx': reg[1]=imm(b)&0xffffffff
            elif a=='bx' and b=='fs:[si]': s16('bx',struct.unpack_from('<H',w1,g16('si'))[0])
            elif a.startswith('es:[bp'):
                off=imm(a[6:-1]) if len(a)>7 else 0
                vbuf[(g16('bp')+off)&0xffff]=reg[2]&0xff
            else: raise Exception(c)
        elif o=='xor': reg[0]=0; cf=0
        elif o=='lea':
            m=re.match(r'\[bx\+(-?\d+)\]',b); s16('dx',g16('bx')+int(m.group(1)))
        elif o=='shr':
            assert a=='dl'; dl=reg[2]&0xff; cf=dl&1; reg[2]=(reg[2]&0xff00)|(dl>>1)
        elif o=='cmp':
            x=g16(a); y=g16(b); cf=1 if x<y else 0; ge= sx(x)>=sx(y)
        elif o in('add','adc','sub'):
            # source
            if b.startswith('ds:'): v=var[b[3:]]
            elif b=='gs:[di]': v=struct.unpack_from('<H',w2,g16('di'))[0]
            elif b in R16: v=g16(b)
            elif b in R32: v=reg[R32[b]]
            else: v=imm(b)
            if a in R32:
                i=R32[a]; v&=0xffffffff
                t=reg[i]+v+(cf if o=='adc' else 0)
                cf=t>>32; reg[i]=t&0xffffffff
            else:
                v&=0xffff; x=g16(a)
                if o=='sub':
                    cf=1 if x<v else 0; s16(a,x-v)
                else:
                    t=x+v+(cf if o=='adc' else 0); cf=t>>16; s16(a,t)
        else: raise Exception(c)

def cdiv(a,b):
    q=abs(a)//abs(b); return q if (a<0)==(b<0) else -q
def i16(v):
    v&=0xffff; return v-65536 if v&0x8000 else v
def palette():
    p=[0]*768
    for a in range(256):
        uc=(223-a*22//26)*3
        b=(230-a)//4 if a<=230 else -((a-230)//4)
        b+=cdiv(sin1024[a*4&1023],32)
        b=max(0,min(63,b)); p[uc+1]=b
        b=(255-a)//3; b=min(b,63); p[uc+2]=b
        b=abs(a-220); b=min(b,40); b=40-b; p[uc]=b//3
    for a in range(768-48):
        p[a]=min(63,p[a]*9//6)
    return p
def frames(maxframe, want, sinkstart=None, every=1):
    vbuf=bytearray(65536)
    startrise=160; rot=rot2=0; xwav=ywav=0
    out={}
    for f in range(every,maxframe+1,every):   # f counts 1/70 s steps; one picture every `every` steps
        for _ in range(every):
            if sinkstart is not None and f>sinkstart:
                if startrise<160: startrise+=1
            elif startrise>0: startrise-=1
        rot2+=4; rot+=cdiv(sin1024[rot2&1023],15); r=rot>>3
        rsin=sin1024[r&1023]; rcos=sin1024[(r+256)&1023]; rsin2=sin1024[(r+177)&1023]; rcos2=sin1024[(r+177+256)&1023]
        xw,yw=xwav,ywav
        for a in range(160):
            x=a-80; y=160
            xa=i16(cdiv(x*rcos+y*rsin,256)); ya=i16(cdiv(y*rcos2-x*rsin2,256))
            b=(a&1)*80+(a>>1)+199*160
            run(xw&~1,yw&~1,xa&~1,ya&~1,b,-270,vbuf)
            if a==80: xwav=i16(xwav+xa*4); ywav=i16(ywav+ya*4)
        if f in want:
            scr=bytearray(320*200)
            for k in range(140):
                Y=70+startrise+k
                if Y>=200: break
                row=vbuf[(60+k)*160:(61+k)*160]
                for a in range(160):
                    c=row[(a&1)*80+(a>>1)]
                    scr[Y*320+2*a]=c; scr[Y*320+2*a+1]=c
            out[f]=bytes(scr)
            print('step',f,'screen crc32',zlib.crc32(scr),flush=True)
        vbuf[68*160:98*160]=bytes(30*160)
    return out
def png(path,scr,pal):
    raw=b''
    for y in range(200):
        raw+=b'\0'+b''.join(bytes(min(255,round(pal[c*3+k]*255/63)) for k in range(3)) for c in scr[y*320:(y+1)*320])
    def ch(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d))
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',320,200,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw))+ch(b'IEND',b''))
if __name__=='__main__':
    want=[int(v) for v in args]
    out=frames(max(want),set(want),sinkstart=2048-130-2*EVERY,every=EVERY)
    pal=palette()
    for f,s in out.items(): png('reference%04d.png'%f,s,pal)
