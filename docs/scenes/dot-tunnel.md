# Dot Tunnel

| Modern look | 1993 look |
|---|---|
| ![](../images/dot-tunnel-modern.png) | ![](../images/dot-tunnel-classic.png) |

A tunnel of dotted rings that snakes around as you fly down it, with alternating light and dark bands.

- **Original:** `TUNNELI/TUN10.PAS` by Trug, about 230 lines of Turbo Pascal with a short assembly loop.
- **This version:** `Sources/SRMetal/Scenes/DotTunnel/`
- **Length:** 1060 steps, about 15 seconds, then it loops.

## How the original did it

It looks 3D, but there is no 3D maths in it.

- **Circles are drawn ahead of time.** A separate program worked out the positions of 64 dots around a
  circle, for every circle size needed, and saved them to a file (`TUNNEL.DAT`).
- **The tunnel is a list of about 100 rings.** Each ring has a sideways position, an up-down position and a
  colour. Nothing else.
- **Depth is faked by size and brightness.** Rings further down the list use a smaller circle from the
  table and a dimmer colour. Ring size is 16384 divided by a number that grows with distance, which is
  real perspective, but only for the size. A ring's sideways offset is not reduced with distance, which is
  what gives the tunnel its exaggerated bend.
- **Movement is a conveyor belt.** Every step, each ring's position is copied to the next slot, and a new
  position is fed in at the far end from a few sine waves added together.
- **Bands come from one line of code.** Every 8 steps the colour given to the newest ring switches between
  light and dark.
- **Drawing is erase-and-redraw.** Each dot remembers where it was last frame, blanks that pixel, and draws
  itself at the new spot. About 5,000 dots per frame, near the limit of a 486.

### Two speed tricks

**No bounds checks.** The program never tests whether a dot is above or below the screen. It keeps a table
that turns a row number into a screen position, and places two extra tables directly before and after it in
memory, filled with the value 64000. A row number that is too small or too large reads from a neighbour
instead, and 64000 is the first position past the bottom of the visible screen, so the dot is drawn where
nobody can see it. That saved a comparison on every dot.

**Self-modifying code.** Before drawing each ring, the program writes that ring's colour into the machine
instruction that draws a dot. The colour then costs nothing to fetch inside the loop.

## How this version does it

The processor only works out about 80 rings per frame: a centre, a size and a brightness for each. It hands
those to the graphics chip, and a shader places all 64 dots of every ring by calculating their positions
with sine and cosine. Then the whole screen is cleared and redrawn every frame.

| | 1993 | This version |
|---|---|---|
| Dot positions | Looked up in a pre-made table | Calculated on the graphics chip each frame |
| Erasing | Each dot blanks its own old pixel | Clear the screen, redraw everything |
| Off-screen dots | Sent somewhere invisible by a table trick | Clipped by the graphics chip |
| Ring colour | Written into the machine code | An ordinary value passed to the shader |
| Tables | Loaded from data files | Calculated from formulas at start-up |

What is kept exactly: the ring list, the conveyor belt, the sine-wave formula that steers the tunnel, the
band timing, the sizes and the brightness rule. So it moves the same way.

### Modern look

- Dots are round with soft edges, and nearer dots are larger. The original's were all one pixel.
- Rings glide between slots instead of jumping one slot per step, and sizes and brightness change smoothly.
- It keeps the original's projection, including the un-reduced sideways offsets. Using true perspective
  throughout would have changed how the tunnel bends.

### 1993 look

Whole-number positions and sizes with the original's rounding, one-pixel dots, on a 320x200 picture.

## What was checked

- **The tables are exact.** The original's generator programs survive (`BALLGEN3.PAS`, `SINGEN.PAS`). The
  formulas in them reproduce `TUNNEL.DAT` (all 8,832 circle points) and `SINIT.DAT` (both sine tables) with
  zero differences, using round-half-to-even rounding. So no data files are needed.
- **The logic matches.** The original algorithm was re-run separately against the original data files; the
  number of lit pixels agrees exactly with this version at six moments in the scene.
- **The graphics chip matches the processor** pixel for pixel at those six moments (self-test).

## Differences from the original

- **End of the scene.** The original erased dots one by one, and as the tunnel emptied at the end a few
  stale dots could be left on screen. This version clears the screen each frame, so none are.
- **Looping.** The original ran once. This one loops; the tunnel has emptied by then, so the loop is clean.
- **Modern look only:** the original's palette happened to blank one ring near the viewer. The modern look
  does not.
