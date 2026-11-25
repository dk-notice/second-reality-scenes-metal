# Rings and Interference

| | Modern look | 1993 look |
|---|---|---|
| Rings | ![](../images/rings-modern.png) | ![](../images/rings-classic.png) |
| Interference | ![](../images/interference-modern.png) | ![](../images/interference-classic.png) |

Two scenes that share the same ring pictures:

- **Rings:** thin teal rings flowing outward on black.
- **Interference:** two sets of purple-grey rings sliding over each other, colours flowing outward, with a
  sideways wave that grows until the picture looks like it is melting.

In the original these ran back to back as the opening of the techno part. Here they are separate scenes
in the sidebar; Play Demo runs them back to back again (see "Inside Play Demo" below).

- **Original:** `TECHNO/KOEB.ASM` (Rings) and `TECHNO/KOEA.ASM` (Interference), assembly by Psi.
- **This version:** `Sources/SRMetal/Scenes/Interference/` (one model and one shader serve both scenes).
- **Length:** Rings fades in over 128 steps and then runs indefinitely. Interference runs 1024 steps, about
  14.6 seconds, and loops seamlessly.

## How the original did it

The program never calculated a ring. It had two pictures of concentric rings, each 640x400, four times the
area of the screen:

- an **8-colour picture** whose rings get thinner further from the centre, and
- a **1-bit picture** (each pixel just on or off) of plain rings 12 pixels wide.

Each was stored on disk as one quarter and mirrored into a full picture when the part started.

### Sliding

The video card was told to show a 320x200 window onto the 8-colour picture, and the window's position was
moved in a circle every frame. The card does that for free: no pixel is copied.

### The fourth layer

The video mode stored each pixel as four separate on/off layers (bit planes). Three layers hold a number
from 0 to 7, which is all the 8-colour picture needs. That left one layer spare.

Every frame, the program copied the 1-bit picture into that spare layer, at a different offset that moved
in its own circle at a different speed. Wherever that layer is on, the pixel's number is 8 higher. So the
video card ends up choosing from colours 0 to 7 where the second picture is off, and colours 8 to 15 where
it is on, and those two groups were given different colour ramps. The interference pattern is the card
combining two pictures by itself.

### Shifting a picture by one pixel

Memory is addressed in bytes, and one byte holds 8 pixels of a 1-bit picture. Copying a picture to a
position that is not a multiple of 8 pixels would mean shifting every byte, which is slow. So when the part
started, it made eight copies of the 1-bit picture, each shifted one pixel further than the last. At run
time it picks the copy with the right shift and does a plain, fast copy.

### Flowing colours

The rings flow because the 16 colours are rotated by one place every frame. No pixel changes.

### The wave

Each row of the 1-bit picture is copied with a small extra sideways shift taken from a sine wave. The
strength of that shift is zero for the first five seconds, then grows one notch every 16 frames.

### Rings

The Rings scene is the same 8-colour picture held still and centred, with only one colour in eight lit
(teal). The colours rotate to make the rings flow, and the palette fades up from black.

## How this version does it

The first surprise was that both pictures follow exact formulas:

- 8-colour picture: ring number = distance to the power 1.4, divided by 16, rounded down. The colour is
  that number's remainder when divided by 8.
- 1-bit picture: distance divided by 12, rounded down. The pixel is on if that is odd.

So the pictures are calculated when the app starts, and no data files are needed.

The second was that the original's layer-copying, with its eight pre-shifted copies, boils down to one
plain rule: the second picture's pixel at screen position (x, y) is the 1-bit picture at
(x + offset + wave - 7, y + offset). The -7 falls out of how the shifted copies were chosen.

| | 1993 | This version |
|---|---|---|
| Ring pictures | Drawn in advance, stored on disk | Calculated from formulas |
| Sliding | The video card shows a moving window | The shader adds an offset |
| Combining the two | A spare bit plane, combined by the card | The shader reads both and picks a colour |
| One-pixel shifts | Eight pre-shifted copies | Not needed; a shader can read any pixel |
| Flowing colours | Rotate the palette | Rotate the palette (1993 look) or shift the ring number (modern) |

### 1993 look

The two calculated pictures are held on the graphics chip. For every pixel the shader looks both up at
the right offsets and picks from 16 colours, exactly as the VGA card did.

### Modern look

No pictures at all. For every pixel of your display, the shader measures the distance to each centre and
works out the ring from that, using the same formulas. The 1993 code could never have afforded that much
maths per pixel; a graphics chip does it without effort.

- Ring edges are softened over one screen pixel.
- The offsets, the wave and the colour flow all glide between steps.
- The ring shades stay as 8 distinct bands, as in the original, not blended into a gradient.

## What was checked

- **The ring formulas are exact.** Both reproduce the original data files (`_CIRCLE.OBK`, `_CIRCLE2.OBK`)
  with zero differences across all 64,000 pixels each. The self-test confirms this by checksum.
- **The simplified copying rule is right.** The original's layer copy, with its eight shifted pictures, was
  emulated byte for byte and compared with the plain rule above: zero mismatching pixels at five moments,
  with and without the wave.
- **The sine table is exact.** `sine x 256, rounded toward zero` reproduces the original `SIN1024.INC`.
- **The graphics chip matches the processor** pixel for pixel at several moments in each scene (self-test).

- **Motion, by program** (`--motion-check`, added 2026-11-14): Rings over 600 steps and Interference over
  its whole loop, modern look also half-way between steps. No jumps in either look, including the
  Interference loop point and the point where Rings starts repeating.

### What was not checked

- Nothing was compared with a running original or a recording.
- That the copy into the fourth layer always finished before the screen was drawn. The original wrote it
  straight into the picture being shown; on a slow PC part of a frame could show the previous step's
  layer. This version treats the copy as instant.
- The modern look by eye in the running app.

## Code review (2026-11-14)

Reviewed line by line against `TECHNO/KOEB.ASM` (Rings) and `TECHNO/KOEA.ASM` `init_interference` /
`do_interference` (Interference), with the wobble table from `TECHNO/KOE.C`, and with `/code-review`.
**No bugs were found, and no code was changed.**

**Confirmed correct, 1993 look.** For each pass of the original's loop, what is on screen during that
frame was worked out and compared with what the model gives for the same step:

- Rings: the fade value is 2 per step, used as "colour x fade / 256"; the colour rotation steps back one
  place per step, starting at 7; the window sits at (160, 100). The palette is sent twice per frame (the
  old one, then the new one straight after), so the new one is what is seen.
- Interference: the window position seen in a frame is the one calculated at the end of the pass before
  (the video card only takes a new window position at the next refresh), and the layer copy made in the
  same frame uses that same older position, so the two agree, as in the model. The wobble wave has already
  moved on by then, which is why the model uses "step + 1" for the wave and "step" for the positions.
- The two palettes, the 5 and 7 places per step, the starting turn of 211, the wobble starting to grow
  after 350 steps by one notch per 16, the wobble table's rounding towards zero, and the plain copying
  rule (x + offset + wave - 7), which was derived again from the assembly during the review.
- Every picture lookup stays inside the 640x400 pictures (columns 57...568, rows 36...363 at the extremes).

**Confirmed correct, modern look.** Every use of the "how far to the next step" value was checked. All
of them go through one number, step + fraction; at the Interference loop point (1024) the two paths, the
wave and the colour rotation are whole turns on from step 0 and the wobble strength is 0, and Rings
repeats every 8 steps once faded in, so nothing glides across a jump.

**Not reproduced (noted, not changed):**

- The original's very first frame. Its position variables start at zero and are only calculated at the
  end of the first pass, so for one frame the original showed the top-left corner of the ring picture.
  This version starts at the calculated position, which is also what lets the loop return to frame 0.
- In the modern look the wobble grows smoothly, so it can be up to one notch (about 2 pixels) ahead of
  the 1993 look; and its rings are measured from the exact centre, which puts ring edges about half a
  canvas pixel outside the 1993 look's.

**Possible tidy-ups** (left for a later pass): the scroll, wobble and rotation formulas are written twice
(whole numbers and decimals); the 200-entry wobble list is rebuilt on every draw, even for Rings; the
model's `Phase` repeats what `part` and `ticks` already say; `SceneError`, used by other scenes, is
declared at the bottom of `InterferenceScene.swift`.

## Differences from the original, on purpose

- **Two scenes instead of one sequence** (on their own; Play Demo joins them again).
- **No white-out in Rings.** The original faded the rings in, then carried on adding brightness until the
  whole screen was white, and ended after 256 steps. Here Rings stops at full brightness and keeps flowing.
- **Interference loops seamlessly.** The original cut away on a music cue: by the demo's timeline, worked
  out later, 989 steps in (when the music's frame counter, started with Rings, reached 925 music
  ticks; it was first read as screen refreshes, 669 steps). Here it runs 1024 steps. The two pictures' paths advance 5 and 7 places per step through a 1024-place sine table,
  so after 1024 steps both are exactly where they started, as are the wave and the colour rotation. The
  wave also shrinks back to nothing over the last 240 steps, which the original did not do. The self-test
  checks that the scene returns to its exact first frame.
- **The colour flow starts immediately.** The original waited for a beat in the music.

### Inside Play Demo

Play Demo (2026-11-24) shows Rings for 256 steps, as long as the original's, then Interference until the
music's frame counter reaches 925. That counter counts music ticks, 52 a second (found 2026-11-25 in
the player's library; see `docs/demo-timeline.md`), so the interference shows for 989 steps, measured
from the script's silent run. (It was first read as screen refreshes, which cut it at 669 steps, 4.6 s
early.)

Inside Play Demo the interference then follows the original (2026-11-25):

- **Full wobble to the end.** The wave grows to full strength and stays there; this scene's own
  shrinking-back (over its last 240 steps, there only so it can loop) is left out, and it does not loop.
- **The flash to white.** On the step the music's counter reaches 925, the picture stops and the palette
  goes 32, 64, 192 and 256 of the way to white, one step each (`KOE.C` 224-228, `flash`: the formula is
  colour x (256 - mix) / 256 + 63 x mix / 256). The fifth step is white too: the script waits five steps
  there. The Modern look glides between the four mixes.

Rings is unchanged there (still no white-out) and neither scene waits for the music; the checks are
"Play Demo: the interference runs to the script's 925 music ticks..." (`InterferenceChecks.swift`).

One thing that is not a difference: the circles are round in pixels, and the canvas is shown at 4:3 as on a
VGA monitor, so they appear as slightly tall ovals. They did in 1993 too.
