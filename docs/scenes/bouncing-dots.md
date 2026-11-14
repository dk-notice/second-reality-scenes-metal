# Bouncing Dots

| Modern look | 1993 look |
|---|---|
| ![](../images/bouncing-dots-modern.png) | ![](../images/bouncing-dots-classic.png) |

512 dots fall onto a floor and bounce, each with a shadow, forming a wandering figure, then a ring, then a
fountain, then a cloud that ends up hanging in the air.

- **Original:** `DOTS/MAIN.C` and `DOTS/ASM.ASM` by Psi, about 540 lines. In the demo it was called
  "MiniVectorBalls".
- **This version:** `Sources/SRMetal/Scenes/BouncingDots/`
- **Length:** about 37 seconds, then it loops.

## How the original did it

### One rule makes all the patterns

There are always exactly 512 dots. Every step, one dot is taken out and dropped back in somewhere new. The
rule for "where" changes through the scene:

| Steps | Where the dot is dropped | What you see |
|---|---|---|
| 1 to 499 | Along a looping path, high above | A wandering figure, falling |
| 500 to 899 | On a circle, thrown upward | A ring |
| 900 to 1699 | On a circle at floor level whose size swells and shrinks, thrown upward | A fountain |
| 1700 to 2359 | At a random place | A cloud |

Because dots are replaced one at a time, in a shuffled order, each new shape grows out of the old one over
about seven seconds (512 steps).

During the cloud, gravity is reduced step by step to nothing, and the view begins to spin faster and
faster, so the dots end up hanging in the air as the scene turns.

### Physics

Each dot has a height and a falling speed. Each frame, gravity is added to the speed and the speed to the
height. At the floor, the speed is reversed and reduced to 13/16, so each bounce is lower than the last.

### Drawing

For each dot, an assembly routine:

1. rotates it about the vertical axis (the view swings from side to side),
2. divides by its distance to get a screen position (perspective),
3. draws a two-pixel shadow on the floor directly beneath it, and
4. draws the dot: 2 pixels, 4 pixels, 2 pixels, in one of 16 shades picked by distance from a table.

### Erasing by putting the background back

The program keeps a copy of the empty background. To rub a dot out, it copies the background back over the
12 pixels where the dot was last drawn, and the same for the shadow. Only the pixels that changed are
touched; the screen is never cleared.

### The floor

The floor is 100 rows, each a slightly lighter grey than the one above, set up once in the palette.

## How this version does it

### 1993 look

The processor replays the original drawing routine exactly: the same 16-bit whole-number arithmetic, the
same erase-by-copying-background, the same order. It produces a picture of colour numbers and a 256-colour
palette, which the graphics chip turns into colours.

The "random" cloud matches 1993 too. The original used the random-number function of the Microsoft C
compiler it was built with, which is a known formula; this version uses the same one, so the dots land
where they did then.

### Modern look

The graphics chip paints a smooth floor, then draws every shadow and every dot as a soft round shape at
full resolution.

- Nearer dots are larger. The original's were the same 4x3 pixels at any distance.
- Dots are sorted so that nearer ones are drawn over further ones.
- Dots glide between steps, except on the step a dot is re-dropped, when it jumps to its new place.
- The floor is a smooth gradient instead of 100 bands.

| | 1993 | This version (modern look) |
|---|---|---|
| Erasing | Copy the background back over each dot | Redraw the whole picture every frame |
| Dot shape | A fixed 4x3-pixel pattern | A round, soft-edged shape sized by distance |
| Shade by distance | A lookup table of 16 shades | Calculated, continuous |
| Floor | 100 palette entries | A gradient calculated per pixel |

## What was checked

- **The graphics chip matches the processor** pixel for pixel at eleven moments (self-test).

### What was not checked

As with the techno bars, the 1993 look depends on the port of the assembly being right, and that was
verified by careful reading, not against a running original.

## Differences from the original, on purpose

- **No white flash at the end.** The original flashed to white and then faded to black. This version fades
  straight to black and loops into the original's fade-in.
- **The re-drop counter starts at zero.** See below.

### Quirks that were kept

These are in the original code and affect which pixels are drawn, so the 1993 look reproduces them.

- A dot that is off the side of the screen does not fall that step. It resumes when it comes back into view.
- The distance calculation combines two results that have each been rounded separately.
- On the "off the side" path, a leftover value is stored as the dot's old shadow position.

## A bug in the original

In `DOTS/MAIN.C`, the counter that picks which dot to re-drop each step (`j`) is declared but never given
a starting value. In C, such a variable holds whatever was left in that spot of memory by whatever used it
before.

What happens depends on the leftover value:

- **Small (0 to 1023):** harmless. The scene runs perfectly.
- **Large:** on the first step the program looks up a junk dot number and writes a dot's position into the
  wrong place in memory, once.
- **Negative:** it stays wrong for up to 511 steps, about seven seconds, writing to a wrong place each time.

The dot table lives in the same block of memory as the assembly drawing routine and its tables. A stray
write can therefore land on the machine code that draws the dots, and the machine locks up the next time
that code runs.

The leftover value is not chance. It depends on what the PC had in memory beforehand: the DOS version, the
drivers loaded, where the program was placed. So a given machine would either never crash here, or crash
on the same frame every time. That would explain a demo that ran perfectly on one PC and reliably crashed
during this scene on another.

The bug is certainly in the file. That it caused any particular crash is a reasoned guess; it cannot be
confirmed without knowing what was in memory on the machine concerned. Every division in the drawing
routine was also checked for overflow (the other common cause of an instant crash), and none can overflow.
