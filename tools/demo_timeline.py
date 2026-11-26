"""Development tool: simulates the whole of Second Reality's running order against the real music.

Each part's start and end conditions were read from the original source (see docs/demo-timeline.md,
which also gives the results). The music is libopenmpt's, stepped 1/70 s at a time by
tools/music_steps.c. Two details of the original player are not in the source, so they are options:
  OFF    0: the player's order number is the order playing; 1: one ahead (as Scream Tracker's own player)
  FRAMES "frames": the player's frame counter (dis_getmframe) counts screen refreshes; "ticks": music ticks
Only OFF=0 with "frames" lets every part find its music cue, and it agrees with a recording (see the doc).
Since 2026-11-25 the counter is known to count music ticks (found in the player's library, MAIN/STMIK.300;
see the doc). The techno part reads it that way whatever FRAMES says (Music.tk); Glenz and the plasma still
follow FRAMES, an open question.

Usage (FOLDER holds MUSIC0-unscrambled.s3m, MUSIC1-unscrambled.s3m and the three step files):
  SRMetal --music-info --write FOLDER
  build/music_steps FOLDER/MUSIC0-unscrambled.s3m 120 0  > FOLDER/s1from0.txt
  build/music_steps FOLDER/MUSIC1-unscrambled.s3m 0 0    > FOLDER/s2from0.txt
  build/music_steps FOLDER/MUSIC0-unscrambled.s3m 120 18 > FOLDER/s1from18.txt
  python3 tools/demo_timeline.py FOLDER 0 frames
It prints each part's start and end in seconds, then the exact steps the Swift is checked against.
"""
import sys
S = sys.argv[1]; OFF = int(sys.argv[2]); TICKS = sys.argv[3] == 'ticks'
def load(name):
    return [tuple(float(x) if i == 3 else int(x) for i, x in enumerate(l.split())) for l in open(f'{S}/{name}')]
def orders(fn, n):
    d = open(fn, 'rb').read(); return list(d[0x60:0x60 + n])
O1 = orders(f'{S}/MUSIC0-unscrambled.s3m', 80); O2 = orders(f'{S}/MUSIC1-unscrambled.s3m', 100)
SYNC = [(0x0000,0),(0x0200,1),(0x0300,2),(0x032f,3),(0x042f,4),(0x052f,5),(0x062f,6),(0x072f,7),(0x082f,8),(0x0900,9),(0x0d00,10),(0x3d00,1),(0x3f00,2),(0x4100,3),(0x4200,4)]

class Music:
    def __init__(s, steps, ordlist, adjust): s.st, s.ol, s.i, s.mf, s.tk, s.sum, s.adj = steps, ordlist, 0, 0.0, 0, 0, adjust
    def cur(s):
        if s.i >= len(s.st): sys.exit(f'demo_timeline: the music steps ran out at step {s.i} (a truncated or wrong step file?)')
        return s.st[s.i]
    def order(s): return s.cur()[1]                  # libopenmpt's current order
    def np_ord(s): return s.cur()[1] + OFF            # what the original player may have reported
    def row(s): return s.cur()[2]
    def plus(s):
        o, r, ol = s.order(), s.row(), s.ol
        z = (o + 1 < len(ol) and ol[o + 1] == 254) | (o > 0 and ol[o - 1] == 254) << 1
        if z == 0: return -32
        if z == 1: return max(r - 64, -32)
        if z == 2: return r if r < 32 else -32
        return max(r - 64, -32) if r > 32 else (r if r < 32 else -32)
    def sync(s):
        pos = s.np_ord() << 8 | s.row()
        for k, (p, v) in enumerate(SYNC):
            if pos <= p: return SYNC[k - 1][1] if k else 0
        return SYNC[-1][1]
    def tick(s):  # one screen refresh (1/70 s)
        t = s.cur()[3]; s.mf += (t * 0.4 / 70) if TICKS else 1; s.i += 1
        # The player's real counter (np_zframe): a music tick whenever the 16-bit sum of its "speed
        # adjust" overflows, once a refresh (MAIN/STMIK.300 at 5165h and 4353h; MAIN/U2.ASM 769-774).
        s.sum += s.adj
        if s.sum >= 65536: s.sum -= 65536; s.tk += 1

class Clock:
    def __init__(s): s.t = 0
T = Clock(); M = None; log = []
def frames(n):
    for _ in range(int(n)): M.tick(); T.t += 1
def until(cond, cap=float('inf')):
    # Without a cap a wait must end on its own: if the music never gets there, the step file runs out
    # and Music.cur stops the tool with an error.
    k = 0
    while not cond() and k < cap: frames(1); k += 1
def part(name, body):
    start = T.t; body(); log.append((name, start, T.t))

# ---- Song 1 (MUSIC0, tempo 120) from order 0 ----
S1 = load('s1from0.txt')
M = Music(S1, O1, 45000)
def alku():   # ALKU/MAIN.C as RELEASED (see docs/scenes/opening-credits.md): three titles, each on its sync
    # (1, 2, 3) or when the one before has faded out (427 refreshes); the scroll starts on sync 4 and moves
    # 1 pixel every 9 refreshes to 320 (2,881); the last fade (64) and the hand-over to the ships (2).
    for c in (1, 2, 3):
        until(lambda: M.sync() >= c); frames(427)
    until(lambda: M.sync() >= 4); frames(2947)
part('ALKU opening credits', alku)
def u2a():    # VISU/C/U2A.C 229-276: start order>10 && row>46; end order>11 && row>54 or 521 frames
    until(lambda: M.np_ord() > 10 and M.row() > 46); s = T.t
    until(lambda: (M.np_ord() > 11 and M.row() > 54) or T.t - s >= 521)
part('U2A ships (incl. waiting on horizon)', u2a)
def pam(): until(lambda: M.sync() >= 10); frames(45 * 4)          # PAM/OUTTAA.C 39-70
part('PAM explosion (incl. wait)', pam)
part('BEGLOGO title', lambda: frames(161))                          # BEG/BEG.C
# ---- Song 2 (MUSIC1) from order 0 ----
M = Music(load('s2from0.txt'), O2, 48700)
def glenz():  # GLENZ/MAIN.C 290-411 + ZOOMER.C
    frames(47); until(lambda: M.plus() >= -19); M.mf = 0; M.tk = 0; frames(177)
    until(lambda: M.tk >= 333); until(lambda: -16 < M.plus() < 0, 7000)
part('GLENZ', glenz)
part('TUNNELI dot tunnel', lambda: frames(1060))                    # TUN10.PAS veke=1060
def techno(): # TECHNO/KOE.C, KOEA/KOEB.ASM
    until(lambda: M.plus() >= -4); M.mf = 0; M.tk = 0; frames(256)
    until(lambda: M.tk >= 925); frames(5); until(lambda: M.plus() >= -3); until(lambda: M.row() & 7 == 7)
    for _ in range(4): frames(21); until(lambda: M.row() & 7 == 7); frames(4)
    frames(420); frames(840); s = T.t; until(lambda: T.t - s >= 700 or M.tk > 2520)
    until(lambda: M.np_ord() > 35 or (M.np_ord() == 35 and M.row() > 48)); frames(53 + 50)
    s = T.t; until(lambda: -6 < M.plus() < 16 or T.t - s >= 420)
part('TECHNO rings/interference/bars/troll', techno)
part('PANICEND switch-off', lambda: frames(121 + 70))
def wait(): until(lambda: M.plus() < 0); until(lambda: M.plus() > 0)  # MAIN/U2.ASM 828-850
part('(loader waits)', wait)
def mnt(): frames(64); until(lambda: M.plus() >= 0); frames(127); until(lambda: M.plus() == -11); frames(65)
part('MNTSCRL mountain scroller', mnt)
def lens():
    until(lambda: M.plus() >= -6); M.mf = 0; frames(300); until(lambda: M.plus() >= -20); frames(720)
    s = T.t; until(lambda: M.plus() > -4 or T.t - s >= 2000)
part('LNS&ZOOM lens + rotozoomer', lens)
def plz(): until(lambda: M.plus() >= 0); M.mf = 0; until(lambda: M.mf > 2259); frames(65)
part('PLZ plasma', plz)
def vect(): until(lambda: M.plus() >= 13); until(lambda: -4 <= M.plus() < 0)
part('VECT plasma cube', vect)
def dots(): frames(130); s = T.t; until(lambda: -3 <= M.plus() <= -1 or T.t - s >= 2450)
part('MINVBALL bouncing dots', dots)
def water():
    until(lambda: M.plus() >= 0); co = M.np_ord(); frames(127)
    until(lambda: M.np_ord() != co and M.row() >= 16); until(lambda: M.plus() == -11); frames(65)
part('RAYSCRL water scroller', water)
def coman(): until(lambda: M.plus() >= 0); s = T.t; until(lambda: -7 <= M.plus() <= -1 or T.t - s >= 4444)
part('3DSINFLD sine landscape', coman)
def jp(): frames(86); until(lambda: M.plus() >= 4); frames(700)
part('JPLOGO jelly logo', jp)
# ---- Song 1 again, from order 18 ----
M = Music(load('s1from18.txt'), O1, 45000)
def u2e(): frames(100); until(lambda: M.np_ord() > 18); frames(3602 + 16)
part('U2E city', u2e)
def end(): frames(163); s = T.t; until(lambda: M.plus() > -16 or T.t - s >= 5000); frames(64)
part('ENDLOGO end picture', end)
part('CRED credits', lambda: frames(7602))
part('ENDSCRL end scroller (until a key)', lambda: frames(0))
for name, a, b in log:
    print(f'{name:40} {a/70:7.1f} s -> {b/70:7.1f} s  ({(b-a)/70:5.1f} s)')
# The exact steps, as the Swift quotes them: `expected` in Sources/SRMetal/App/DemoTimelineCommand.swift
# (the part starts) and the opening credits' cues (`OpeningCreditsModel.cues`, CUES in alku_reference.py):
# the first step on which song 1's sync value has reached 1...9.
print('Part starts (steps):', ', '.join(str(a) for _, a, _ in log))
cues = Music(S1, O1, 45000); first = []
for c in range(1, 10):
    while cues.sync() < c: cues.tick()
    first.append(cues.i)
print('Opening credits\' cues (steps):', ', '.join(map(str, first)))
