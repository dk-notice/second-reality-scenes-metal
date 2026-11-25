# Water Scroller

| Modern look | 1993 look |
|---|---|
| ![](../images/water-scroller-modern.png) | ![](../images/water-scroller-classic.png) |

A ray-traced picture fades in: dark blue water with ripples and two chrome balls. After a few seconds
a flame comes skimming over the water towards the viewer, and behind the flame a sword, trailing sparks.
All of it is mirrored, small and bent, in both balls. Part 13 of the demo, after the bouncing dots and
before the 3D sine landscape. It is called a scroller, but there is no text in it.

![The flame in front of the sword (Modern look)](../images/water-scroller-flame-modern.png)

- **Original:** `WATER/DEMO.PAS` (about 190 lines of Turbo Pascal) and `WATER/ROUTINES.ASM` (one routine,
  `putrouts1`, 20 instructions), by Trug. Built into `RAYSCRL.EXE`. `DATGEN.PAS` made the position
  tables; `TESTI.PAS` and `KOE.PAS` are experiments. The same technique as the
  [Mountain Scroller](mountain-scroller.md), by the same coder.
- **This version:** `Sources/SRMetal/Scenes/WaterScroller/` (added 2026-11-25); the table reader and the
  Modern look's map are shared with the mountain scroller (`Core/ScrollTables.swift`).
- **Length:** on its own 2,044 steps (about 29 seconds): black, 127 steps of fading in, 519 of the still
  picture, 1,332 of the sword passing, 65 of fading out, then it starts again. In Play Demo it follows
  the music as the original did, and the music gives exactly those lengths (see below).

**This scene uses original artwork and data:** the background picture, the sword picture and three
position tables, in [Data/Water/](../../Data/Water/README.md) (154 KB). The tables cannot be calculated;
see below.

## How the original did it

1. **Nothing is ray-traced while it runs.** The background is a finished picture (made with POV-Ray; some
   of its scene files are still in `WATER/`). The sword is another finished picture, `MIEKKA.SCI`
   ("miekka" is Finnish for sword): 400 pixels wide and 34 rows tall, with a flame at its front and
   sparks behind.
2. **Position tables.** The program keeps a window on the sword picture, 158 columns by 34 rows. For every
   cell of the window a table lists the screen pixels where it shows: on the water, and again in each
   reflection. Near the viewer one cell covers up to 24 pixels; in the small reflections most cells
   cover none. The tables were made beforehand: the scene was ray-traced with a special surface on the
   water whose red channel was the sword column and whose green channel was the sword row, and
   `DATGEN.PAS` turned those pictures into lists. The ray tracer did the mirroring; the program only
   reads lists.
3. **Three tables, a third of a column apart.** The scene was traced again with the sword moved a third
   of a column each time, and each table lists only the pixels that changed from one tracing to the
   next, so the three share no pixel. The program draws one table per screen refresh (1, 2, 3, 1, ...)
   and after the third moves the window one column. The sword creeps in thirds of a column, and each
   refresh only about a third of its 20,858 pixels are written.
4. **Drawing a pixel** is a choice: the cell's colour number if the cell has sword in it, otherwise the
   background's own pixel again (which is how the sword is wiped off behind itself). The sword has its
   own colours, 192...255; the background uses 0...191. (The mountain scroller adds numbers instead.)
5. **The fades are done on the palette**, and they have a slip in them. The fade-in loop runs 127
   refreshes and raises every colour one level on every second one. But its inner loop steps through
   four bytes per colour instead of three, and the fourth byte is the next colour's red. So red rises
   two levels a round, green and blue one: the picture comes in with pink highlights that turn white as
   green and blue catch up. The fade-out has the same slip the other way: red leaves first, and the
   picture goes out in blue. (The loop also ends one level short, so green and blue stop at 62 of 63
   until the fade-out's first pass sets them.)
6. **Three music cues.** The part starts black and waits for "music plus" ≥ 0 (20 refreshes in the
   demo), then fades in. Then it sits in a loop with only the picture showing until the music is in its
   next section at row 16 or later: 519 refreshes, 7.4 seconds. The sword then runs until "music plus" =
   −11, and the part fades out over 65 refreshes while the sword keeps moving.
7. **The window starts empty**, and the sword comes in at its far end. The sword's last 40 columns are
   empty, so (unlike the mountain scroller's text) nothing is left smearing when it has passed.

## This version

**The data.** The five original files are loaded as they are. The tables could not be worked out again:
`DATGEN.PAS` read four ray-traced pictures (`k1`, `k2`, `k3`, `k5.mtv`) that are not in the source
release. One such picture is there, `MASK.MTV`, but it is from an earlier trial and fits the tables
nowhere. The files are the released version: the built part in the source release (`RAYSCRL.EXE`,
unpacked) contains all five whole.

**1993 look:** the original's 320x200 screen, kept from step to step and changed exactly as the program
changed it: one table a step, the window moving after the third, both fades in whole levels with red
running ahead. Shown through `Core/IndexedCanvas.swift`. Steps are paired with the screen as in the
mountain scroller.

**Modern look:** drawn afresh every frame.

- The background is the picture made 8x larger by Super-xBR. The sword is its own picture made 8x the
  same way (the user's choice, 2026-11-25, as for the mountain scroller's text), as two pictures: its
  colours on black, and its outline.
- The sword's place comes from the same tables, turned into the smooth map the mountain scroller uses:
  every pixel gets a best-fit plane through the places where its neighbours' sword coordinates step, and
  each screen pixel blends the planes around it. The sword then glides instead of creeping.
- The small reflections (regions of fewer than 1,000 pixels, 437 pixels in all) are different: there a
  whole stretch of sword falls inside one pixel, and no plane can be fitted. Each of those pixels keeps
  its own cell and shows the average of the stretch of sword it covers.
- A mask of where the sword may show, also made 8x, gives it a smooth edge where a ball is in front.
- The fades follow the original's rule, red twice as fast, without the whole-number steps.

| | Original | 1993 look | Modern look |
|---|---|---|---|
| Sword movement | a third of a column a refresh, a third of the pixels at a time | the same | continuous |
| Sword near the viewer | blocks up to 24 pixels | the same | smooth but soft (see below) |
| Fades | red twice as fast, whole levels | the same | red twice as fast, smooth |
| Green and blue after the fade-in | stop at level 62 | the same | reach the full colour |
| Still picture before the sword | 7.4 s (waiting for the music) | the same, also on its own | the same |

## Checks

- `tools/water_reference.py` checks the tables' structure (each parses exactly, they share no pixel,
  20,858 pixels in 14 regions), compares them with `GREEN.CLX` and `MASK.MTV`, shows which way the three
  tables order (67% of neighbouring pixels within a third of a column one way, 52% the other), reports
  the palette facts above, and replays the part from the original files, printing checksums at 35 steps.
- The self-test compares the app's 1993 pictures with that tool at those 35 steps (all identical), the
  palette at three moments of the fades, the five data files' checksums, that the tables share no pixel
  and cover 20,858, that the smooth map keeps the large regions' pixels inside their own third of a
  column (95%) and row (99.9%) and the 437 small ones on their own cell, and the loop after 2,044 steps.
- In a silent Play Demo run it checks, against the demo script's own numbers, that the fade-in, the
  scroll and the fade-out start on the very steps the script gets past its three music cues, that the
  sine landscape follows 65 steps later, and that the scene on its own uses the same lengths.
- Each was seen to fail with the detail broken on purpose: red not doubled, the scroll a step early, the
  tables taken in the other order, the section cue a row early, the fade-out cue a row early, the new
  column put straight into the window's last cell.
- `--motion-check water-scroller modern`: no jumps while the sword moves; it marks the three half-steps
  where the fade-out begins (red starts dropping two levels a step).

## Differences and limits

- Modern: near the viewer one sword pixel is stretched over about 25 screen pixels, more than any
  scaler can fill in, so the sword's near end looks out of focus where the 1993 look shows big blocks.
  (Scaling the sword 16x instead of 8x made no visible difference.)
- Modern: the small reflections are still drawn one 320x200 pixel at a time (each an averaged colour)
  and stay coarse.
- Modern: green and blue reach their full colour after the fade-in.
- The background is the original picture scaled up, not re-rendered from the POV-Ray files (a later idea).
- The original drew straight onto the screen being shown; any tearing that caused is not copied.
- Not compared with the original running.
