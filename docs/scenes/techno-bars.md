# Techno Bars

| Modern look | 1993 look |
|---|---|
| ![](../images/techno-bars-modern.png) | ![](../images/techno-bars-classic.png) |

Eleven parallel bars spin about the middle of the screen, their thickness bouncing, leaving ghost trails
that brighten where they overlap. The bars flash on the beat.

- **Original:** `TECHNO/KOE.C` (`doit1`, `doit2`, `doit3`) in C, with the drawing in `TECHNO/KOEA.ASM` and
  `TECHNO/POLYCLIP.ASM`, by Psi.
- **This version:** `Sources/SRMetal/Scenes/TechnoBars/`
- **Length:** about 28 seconds in three sections, then it loops.

| Section | Length | What happens |
|---|---|---|
| 1 | 6 seconds | Steady spin; thickness bounces gently |
| 2 | 12 seconds | Spin keeps accelerating; the bars shrink to nothing and bounce back |
| 3 | about 10 seconds | The same, with the whole set of bars circling the screen, until it slides off to the right |

## How the original did it

### The trails cost nothing

The video mode stored each pixel as four separate on/off layers (bit planes). The program also had eight
screens' worth of video memory ("pages") and could switch which one was shown instantly.

Each frame it:

1. drew the bars as a one-colour picture,
2. copied that picture into just **one** layer of the current page,
3. told the card to show that page, and
4. moved on to the next page. After all eight pages, it moved on to the next layer.

So each page gets a new frame every 8 frames, each time in a different layer. When a page is shown, its
other three layers still hold the bars from 8, 16 and 24 frames earlier. Nobody erased them.

The palette then does the shading: a pixel's colour depends only on how many of its four layers are on,
from black (none) to brightest (all four). Ghost trails and overlap shading are simply old frames showing
through.

Section 3 uses four pages instead of eight, so its ghosts are 4, 8 and 12 frames old.

### Filling shapes by flipping one pixel per row

Filling 11 bars pixel by pixel would be too slow. The original instead:

1. trims each bar to the screen,
2. for each edge of each bar, flips a single pixel on every row the edge crosses, and
3. sweeps every row once from left to right, switching "inside" on at the first flipped pixel, off at the
   next, and so on.

Step 3 fills every shape at once, and is done by table lookup a byte at a time while copying the picture
to video memory. So the only per-bar work is marking the edges.

### The bounce

Thickness behaves like a ball under gravity: a speed is added to it each frame, the speed grows by one
each frame, and when the thickness hits its lower limit the speed is reversed.

### The flash

The palette is swapped for a brighter version on every 8th row of the music, then steps back down over the
next 15 frames.

### The slide-off

In section 3 the bars are drawn into the right half of a double-width screen, and the video card's window
is slid across to the empty left half. The bars leave to the right without being redrawn any differently.

## How this version does it

### 1993 look

The processor replays the original's steps: the same eight pages and four layers, the same edge-marking
fill, the same screen-trimming code, all with the original's whole-number arithmetic. The result is a
picture of colour numbers and a 16-colour palette, which the graphics chip turns into colours.

This is the approach to use when the picture depends on what was left behind in video memory, which is the
whole point of this scene.

### Modern look

No pages, no layers. For every pixel of your display, the shader asks four questions: is this pixel inside
the bars as they are now, as they were 8 steps ago, 16 steps ago, and 24 steps ago? It adds up the answers
and shades by the count. "Inside a bar" is a short calculation: rotate the pixel's position into the bars'
frame, and see whether its distance across the bars falls in a bar or a gap.

- Edges are softened over one screen pixel, so the count changes smoothly at edges.
- The bars glide between steps. To do that, the picture runs one step behind, so that there is always a
  "next" position to glide towards.
- They do not glide into the first step of a section. The bars jump there (the original starts each section
  at a new angle and thickness), and gliding across the jump would sweep them through angles never drawn.
  The cut stays a cut, as in the original.

| | 1993 | This version (modern look) |
|---|---|---|
| Trails | Old frames left in other bit planes | The bars' recent history, tested per pixel |
| Overlap shading | Palette colours by number of planes on | The shader counts and picks the shade |
| Filling bars | Flip edge pixels, sweep each row | Not needed; each pixel tests itself |
| Trimming to the screen | Hand-written clipping code | Not needed |
| Slide-off | The video card's window moves | The shader adds an offset |

## What was checked

- **The graphics chip matches the processor** pixel for pixel at ten moments across the three sections
  (self-test).
- **The fill routine** fills a plain rectangle with exactly the expected pixels, left and top edges
  included, right and bottom not, which is the original's rule (self-test).
- **The modern look never glides across a section change** (self-test, over a whole loop and into the next).
  Within a section the bars only spin forwards, by at most 84/1024 of a turn per step. A glide that goes
  backwards, spins more than 1/8 turn or changes thickness by more than 3 pixels has crossed a section change.
  With the fix below removed, this check fails at exactly the four expected steps.
- **The modern look shows the current bars whenever the 1993 look shows any** (self-test, same run).
- **Independent review of the drawing code (2026-11-14).** A code review compared `BarRasteriser` line by
  line against the original assembly (`KOEA.ASM` `asmbox` and `drawline`, `POLYCLIP.ASM`
  `clipanypoly`, `cliplinex`, `clipliney`). It found them the same: trimming top/bottom first and then
  left/right, against rows 0...199 and columns 0...319; each line end moved using the other end as already
  moved; whole-number division rounding towards zero, as the 386's `idiv` did; repeated points dropped the
  same way; left/right edge direction chosen the same way and the same edge-stepping arithmetic; the top
  row of each edge flipped, the bottom one not. It also confirmed that the original's 16-bit arithmetic
  never overflows with these numbers, so this version's larger numbers give the same results. The original's
  extra "left overflow" path in `drawline` is never switched on (`clipleft` is always 0), so leaving it out
  changes nothing.

### Fixed after that review

The same review found four problems elsewhere in the scene, all now fixed:

- **Modern look: the bars whirled at the change from section one to two.** The glide went from the last
  angle of section one (883/1024) straight to the first of section two (50/1024): about 293° backwards
  within one step. Then the same happened to each ghost, 8, 16 and 24 steps later. Now a section's first
  step is held still (see "Modern look" above).
- **Modern look: one blank step.** With only one step recorded (at the very start and at the start of
  section three), nothing was drawn. Now that step is shown, held still.
- **1993 look: the flash was one step early.** In the original, a page drawn in one pass of the loop only
  appears at the screen refresh inside the next pass, and the flash colours are set just after that refresh.
  So each page was seen with the next pass's flash. This version had paired it with its own pass's flash.
- **1993 look: the slide-off lagged one step.** For the same reason, each page was seen with the slide
  amount worked out at the start of the next pass. Like the original, the last page keeps its slide: the
  original stops before showing a slide of zero.

### What was not checked

Unlike the tunnel and the rings, this scene has no data files to compare against. Its 1993 look depends on
the port of the drawing and trimming assembly being right. That has now been checked twice by reading
(once when it was written, once in the independent review above), but never against a running copy of the
original. The self-test cannot catch a mistake there, because the processor does all the work and the
graphics chip only looks up colours.

Also not reproduced: before each section, the original waits for one extra screen refresh, which moves the
flash on by a step. Since the beat is recreated anyway (see below), this would only change where it starts.

## Differences from the original

- **The beat is recreated.** With no music, the flash timing comes from the song file's own settings
  (speed 3, tempo 130), which gives a flash about every half second. It is not tied to anything.
- **Left out:** the original's lead-in (a white flash, then four columns dropping to black on four beats)
  and the picture that scrolls in after the slide-off.
- **It loops.** After sliding off, the scene starts again from section 1.

### Quirks that were kept

These are how the original code behaves, and they affect pixels, so the 1993 look reproduces them.

- The bottom row of the screen is never drawn.
- The second frame of section 3 places the bars far off the screen, giving one blank frame.
- Video memory is not cleared between sections 1 and 2, so section 1's last frames linger as ghosts for a
  moment.
