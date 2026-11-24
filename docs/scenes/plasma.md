# Plasma

| Modern look | 1993 look |
|---|---|
| ![](../images/plasma-modern.png) | ![](../images/plasma-classic.png) |

Soft, flowing clouds of colour in a wide band across the middle of the screen. Four times the band falls
off the bottom of the screen like a dropped object, and comes back at once in new colours fading up from
black: red and blue, then a blue-green rainbow, then grey smoke, then pastel blue and pink.

- **Original:** `PLZPART/PLZ.C` (main loop, tables, palettes), `ASMYT.ASM` (the per-line drawing routine),
  `COPPER.ASM` (everything timed to the screen refresh) and `TWEAK.ASM` (the screen mode), by Wildfire.
  The plasma-covered cube that followed it in the demo is a separate, later scene.
- **This version:** `Sources/SRMetal/Scenes/Plasma/`.
- **Length:** 2323 steps, about 33 seconds, then it repeats.

## How the original did it

### What a plasma is

A plasma is a picture where every pixel's colour number comes from adding up a few smooth waves. Because
the waves are smooth, neighbouring pixels get neighbouring numbers, and a palette of smoothly changing
colours turns that into clouds. Slide the waves along a little every frame and the clouds flow.

### The formula

The program had three tables of wavy numbers, made in advance from sines (a big slow wave with two small
fast ones riding on it): `psini`, `lsini16` and `lsini4`. For a column `c` (0 to 83) on row `y` (0 to 279),
with four numbers `p1` to `p4` that say where the plasma currently is:

```
bend1 = lsini16[ y + p2 + 4*(80 - c) ]
bend2 = lsini4 [ y + p4 + 16*c ]
value = psini[ 8*c + bend1 + p1 ]  +  psini[ 2*y + bend2 + p3 + 4*(80 - c) ]
```

So it is two table lookups added together, but the place each lookup reads from is itself pushed around
by another wavy table. That "wave bent by a wave" is why this plasma looks like smoke and not like a
regular pattern. The four numbers move by 1 to 3 places every frame, each at its own speed.

### Code that rewrites itself

The drawing routine has no loop over columns. The same four instructions are written out 84 times, once
per column, and before each pass another routine goes through all 84 copies and overwrites the addresses
inside the instructions with the current `p1` to `p4` already added in. The processor then just runs
straight through. This "self-modifying code" was the fastest way to do it on a 486.

### The screen mode, and two plasmas at once

Even so, working out one value per pixel was far too slow. So:

- The screen was set to an unusual mode: 320 pixels across and **400** lines down (twice the usual 200),
  with video memory arranged as four interleaved layers ("planes"). Pixel 0 of every group of four is in
  plane 0, pixel 1 in plane 1, and so on. One byte written to memory can go to several planes at once.
- Only **84 values per line** were calculated. Each was written to two planes at once, so it covers two of
  every four pixels.
- **Two different plasmas** were drawn, call them K and L, each with its own four numbers. On even rows K
  went into pixels 1 and 3 of each group and L into pixels 0 and 2; on odd rows the other way round. The
  result is K and L interleaved like the black and white squares of a chessboard, one pixel per square.
- Every frame the video card was told to start the band one line lower or higher than the frame before
  (line 60, then 61, then 60 ...), and to shift it 2 pixels sideways on alternate frames. Moving a
  chessboard by one square swaps black and white. So at any spot on the screen, K and L alternate 70 times
  a second, and the eye sees them **mixed**. The sideways shift also hides the 4-pixel-wide columns.
  (The frame that starts on line 60 is the one with no shift, and line 61 goes with the 2-pixel shift:
  the program picks them the other way round, but the shift reaches the card one frame late. See
  "Code review" below.)
- That alternation of lines only happens while the plasma is flowing normally. While the band falls and
  while a new palette fades in, another routine sets the line and both frames use the same one, so for
  those moments K and L are **not** mixed: each pixel shows only one of them, as a fine chessboard.

The viewer sees one rich, smooth plasma. The program only ever computed two coarse ones.

### The band, the fall and the fade

The plasma is 280 lines tall, placed in the middle of the 400-line screen using a video card feature
called "line compare": at a chosen screen line, the card jumps back to the start of video memory. The
part of the screen above that line shows empty memory (black); the plasma starts below it.

To make the band fall, a routine that runs once per screen refresh simply raises that line number each
frame, by amounts that grow with the square of time, as a falling object's distance does. After 64 frames
the line is past the bottom of the screen. No pixel is moved; the card does it all.

While the band is out of sight the four numbers are reset for the next section. It then reappears in place
immediately, with a black palette that is brightened in 31 equal steps to the new colours.

## How this version does it

| | 1993 | This version |
|---|---|---|
| Sine tables | Three tables made in advance, stored in the program | Calculated at start-up from the original's own formulas |
| Per-pixel work | 84 values per line, each 4 pixels wide | Every pixel, on the graphics chip |
| Speed trick | Code that rewrites its own addresses | Not needed |
| Mixing the two plasmas | Chessboard that flips every frame; the eye mixes | The shader works out both and averages them |
| Band position and fall | Video card's line-compare register | The shader offsets the band |
| Palette fade | 31 additions per colour, sent to the card each frame | The same arithmetic (1993 look); glides between steps (modern) |

### 1993 look

The canvas for this scene is 320x400, not the 320x200 the other scenes use, because that was the original
screen. It is still shown at 4:3.

The three tables are handed to the graphics chip. For every pixel the shader does the original's lookups
with whole numbers, following the chessboard rule to pick plasma K or L. It does that for both of the two
alternating frames and shows the **average** of the two (see the differences below for why).

So in this look you can still see the 1993 construction if you look closely: values are 4 pixels wide and
staggered, and the very first and last line of the band are dotted, because there only one of the two
alternating frames has plasma.

### Modern look

No tables. For every pixel of your display the shader evaluates the sine formulas the tables were made
from, with fractional positions, for both plasmas, looks each up in the palette (blending between
neighbouring palette entries) and mixes the two half and half. There are no columns and no chessboard. The
four numbers, the fall and the fade all glide between steps.

It is the same plasma: the same waves, the same motion, the same colours.

## What was checked

- **The tables match the original's data files.** `psini`, `lsini16` and the brightness ramp `ptau` come out
  identical to `PSINI.INC` (16,384 values), `LSINI16.INC` (8,192) and `PTAU.INC` (129) from the formulas in
  `PLZ.C`, provided the original's own 11-digit value of pi is used. `lsini4` matches `LSINI4.INC` in 8,190
  of 8,192 places. At the other two (entries 3072 and 7168) the exact answer is the whole number 24 and the
  original file says 23: the 1993 maths library landed a hair below. Those two entries are set by hand. The
  self-test compares all four tables with checksums of the original files.
- **The per-pixel formula, against the original's machine code** (code review, below).
- **The chessboard layout and which shift goes with which line**, from the original source (code review).
- **The graphics chip matches the processor** pixel for pixel at 14 moments, including mid-fade, mid-fall
  and each palette (self-test).
- **The scene repeats exactly** after 2323 steps and is black at the point where it repeats (self-test).
- **The modern look glides without a jump** through the whole loop: the end of every step's glide is where
  the next step starts, for the band's position, the eight plasma numbers and the palette (self-test, and
  the `--motion-check` option over steps 0 to 2400: no jumps, no one-picture-only pixels).
- Pictures of both looks were made at several moments and looked at: they show the same shapes and colours.

## Code review (2026-11-14)

The whole scene was read again, line by line, against `PLZ.C`, `ASMYT.ASM`, `COPPER.ASM` and `TWEAK.ASM`,
and this time also against the demo's interrupt server (the part of the demo that runs a scene's routines
at fixed points of each screen refresh): `DIS/DISINT.ASM` and `MAIN/COPPER.ASM`. An earlier version of this
page said that code was missing from the source release. It is there; only the stand-alone test copy
(`DIS/DIS.ASM`) lacks it.

**Found and fixed**

1. **The sideways shift was paired with the wrong line (1993 look).** `pompota` chooses "line 60 and a
   2-pixel shift" or "line 61 and no shift". It runs in the routine the interrupt server calls *during*
   the retrace (the pause between two screen refreshes), and sends the line number to the card at once,
   so the line applies to the frame about to be drawn. The shift is only stored. It is sent to the card by
   another routine (`copper1`), which the interrupt server calls *just before the next* retrace
   (`copper_end` in `MAIN/COPPER.ASM` calls routine 1, waits for the retrace, then calls routine 2). So
   every frame is drawn with its own line and the *previous* frame's shift: line 60 with no shift, line 61
   with 2 pixels. This version had it the other way round. Every picture of the flowing plasma changes at
   pixel level (about a third of the pixels, by up to 32 of 255 in one colour part, in the two pictures
   compared, steps 400 and 2000); pictures during a fall or a fade do not change, because there both
   frames use the same line. No stored checksum depended on it. The self-test now checks the pairing.
2. **A small hop at the start of each fall (modern look).** On the step the fall starts, the original's
   fall counter goes from 0 straight to 2. The modern look glided from 2 onwards but sat still during the
   step before, so the band stayed put and then hopped 0.34 of a line (about one screen pixel in a large
   window) at steps 725, 1493, 1877 and 2261. It now glides into the fall. The new self-test check
   described above caught exactly those four steps before the fix.

**Confirmed correct**

- **The formula.** The drawing routine overwrites the addresses inside its own instructions, so the
  formula depends on exactly which bytes get overwritten. `ASMYT.OBJ`, the assembled original, is in the
  source release: each of the four instructions per column is 4 bytes, two of instruction and two of
  address, with nothing in front, and the rewriting routine stores to exactly those two address bytes
  (its first four targets are 4 bytes apart). So the whole address is replaced, the `ccc*32` and `ccc*64`
  written in the source never take effect, and the formula at the top of this page is what the processor
  ran. The table positions it adds (0, 4000h, 8000h plus 280h, plus 140h) match too.
- **The chessboard.** `PLZ.C` switches on planes 1 and 3 (value 0Ah), draws K on even rows and L on odd
  rows, then planes 0 and 2 (05h) and draws K on odd rows and L on even rows. That is the layout used
  here. The C++ port copies its two buffers to the screen in the same arrangement.
- The parameter speeds and wrap-around, the fall table, the order of work in each refresh (palette, then
  move, then fall or fade), the 31 fade steps and their 16-bit arithmetic including the half that is
  not cleared between sections, the four palettes, the section order and starting numbers, and the end of
  the scene on the fourth fall.
- **Motion in the modern look**: nothing is glided across a jump. The plasma numbers are reset and the
  palette swapped only while the band is hidden (fall counter 64 and 65), and the loop point is black in
  both looks.
- In the 1993 look, `--motion-check` reports large one-picture-only changes during each fall and a jump
  at step 33 where a fade ends. Those are the original's behaviour described above (K and L not mixed
  while falling or fading, so the fine chessboard swaps as the band moves a line), not a fault.

**Still not verified**

See the next section. One finding there needs a decision: the length of a "music frame".

**Possible tidy-ups** (left for a later clean-up pass, nothing wrong with the picture)

- `PlasmaScene.draw` makes a new 256-colour buffer for the graphics chip on every drawn frame, and
  `PlasmaModel.tick` rebuilds the shown palette with `map`; both could be reused.
- The formula exists three times (Swift, the shader's table version, the shader's smooth version), and
  the shader repeats 280, 319 and 399 as plain numbers.
- `PlasmaModel.value` would read before the start of a table for columns 81 to 83 with small parameters.
  The original worked those columns out but they are off the screen, and nothing here asks for them.
- `fields` has a case for fall counter 1, which never occurs (it goes from 0 to 2).

## What was not checked

None of this has been compared with the original program running.

- **Where the band sits.** First plasma row on screen line 61 or 62 of 400. This rests on the documented
  behaviour of the VGA card (the split starts on the line *after* the one it is given), not on a
  measurement. The C++ port puts it one line higher, at 60, and does not alternate lines or shift at all.
- **How long a "music frame" is: probably not 1/70 second.** The section times (723, 1491, 1875, 2259) are
  compared with a counter kept by the music player, which this version assumes ticks once per screen
  refresh. The review found evidence against that: the timetable is written as multiples of `64*6`
  (64 rows of music at 6 ticks each); the C++ port, which plays the real music, advances that counter
  once per music tick, not per refresh; and the music file's starting tempo (130) gives 52 ticks a
  second, not 70. The "-45" in the timetable is also about the length of the 64-frame fall if a tick is
  1/52 second (0.87 s against 0.91 s), which would land each fall on a bar of the music. If that is
  right, the original's sections were about a third longer than here (the whole scene about 43 seconds,
  not 32). It is not proven: the player itself is only in the release as a compiled library, and the
  tempo may change within the tune. Nothing was changed; the scene still uses 1/70 second.
  **Update 2026-11-24:** simulating the whole demo against the real music (`docs/demo-timeline.md`)
  points the other way: with music ticks the later parts overrun song 2, and a recording places the
  sine landscape where the 1/70-second reading predicts it (within 2 s), not 30 s later. So 1/70
  second, as built here, is most likely right. Still to confirm: that the recording starts with the music.
- **The palettes and the fade** were ported from `PLZ.C` and `COPPER.ASM` by reading (now twice).
- The pictures in `docs/images/` were remade after the review was merged, so they show the corrected 1993 look.

## Differences from the original, on purpose

- **The 1993 look shows the two alternating frames averaged, not one after the other.** On a 70 Hz monitor
  the flipping chessboard blurred into a smooth mix. A Mac display refreshes at 60 or 120 Hz, and showing 70
  alternating frames per second on that produces a slow, ugly flicker. So each picture is the average of
  the two, which is what the viewer saw. Both frames use the same moment's numbers.
- **No white fade at the start.** The original began with the whole screen white (left by the previous
  scene) and faded down to the first palette over 127 frames. Here the first palette fades up from black in
  31 steps, exactly like the other three. The increments for it are chosen so it ends on the original's
  exact first palette.
- **It loops.** In the original the fourth fall was the end: the plasma cube followed. Here that fall leads
  back to the first section. The loop point is a black screen, so nothing jumps.
- **Drawing is instant.** The original program drew as fast as the PC could, not once per refresh, while
  the four numbers moved on every refresh regardless. On a slow PC the picture was therefore built from
  slightly different moments. This version draws every frame complete, as an infinitely fast PC would.
- **Sections 2 to 4 stay at 31/32 of full brightness.** That is not a change: the original's fade stopped
  one step short, and this version keeps that.
- A fifth palette the original prepared was only ever shown by the plasma cube, so it is not here.
