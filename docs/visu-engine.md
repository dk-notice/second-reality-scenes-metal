# The VISU 3D engine

| | Modern look | 1993 look |
|---|---|---|
| A small ship alone | ![](images/visu-ship-turn1-modern.png) | ![](images/visu-ship-turn1-classic.png) |
| City, animation frame 800 | ![](images/visu-city-0800-modern.png) | ![](images/visu-city-0800-classic.png) |
| Ships, animation frame 60 | ![](images/visu-ships-0060-modern.png) | ![](images/visu-ships-0060-classic.png) |

Two parts of Second Reality are real 3D: the **ships fly-by** near the start (`U2A.EXE`) and the **3D
city** near the end (`U2E.EXE`). Both are the same program with different data. The shared part is a
small 3D engine its author (Psi) called **VISU**, about 4,000 lines of assembly and a little C.

This page describes that engine, the data it reads, and this project's version of it. The engine was
built and checked by itself first, so that when the two scenes were added, a wrong picture could be
traced to either the engine or the scene. Both scenes now exist
([scenes/ships-flyby.md](scenes/ships-flyby.md), [scenes/city-3d.md](scenes/city-3d.md)). What the engine consists of:

- `Sources/SRMetal/Core/Visu/`: the engine, for both looks.
- `Data/Visu/`: the original models and animation, 52 files, 257 KB (see "The data" below).
- `tools/visu_reference.py`: runs the ORIGINAL assembly, to check the engine against.
- A command-line option to look at it (the pictures above were made this way):

      build/SRMetal.app/Contents/MacOS/SRMetal --visu-test list
      build/SRMetal.app/Contents/MacOS/SRMetal --visu-test city-0800 modern picture.png
      build/SRMetal.app/Contents/MacOS/SRMetal --visu-test city-0800 classic picture.png

Some words used below. A **vertex** is a corner point in 3D. A **polygon** is a flat shape with
three or more corners. A **normal** is an arrow of fixed length pointing straight out of a surface;
it says which way the surface faces. A **matrix** here is nine numbers that turn a point, plus three
that move it. **Clipping** is cutting away the part of a polygon that falls outside the picture.
**Flat shading** gives a polygon one colour; **Gouraud shading** (after its inventor) works out a
colour at each corner and blends between them. **Fixed point** means storing fractions in whole
numbers by agreeing that, say, 16384 stands for 1.

## Which original files are live

All paths are inside the released source, `VISU/`.

- **The engine** is a library, `VISU.LIB`. Its `MAKEFILE` builds it from `visux.obj visu.obj
  amain.obj adata.obj acalc.obj avid.obj adraw.obj`, and the listing `VISU.LST` agrees. `AVID.ASM`
  pulls in `AVIDM1.ASM` (320x200 mode), `AVIDM2.ASM` (640x400 mode), `ATEXT.ASM` (a debugging font) and
  `AVIDFILL.ASM` (the polygon fillers). `ADRAW.ASM` pulls in `ADRAWCLP.ASM` (clipping). `ADATA.ASM`
  pulls in three tables: `ADATASIN.INC`, `AVISTAN.INC`, `AFILLDIV.INC`.
- **The two scene programs** are in `VISU/C/`: `U2A.C` and `U2E.C`. `C/MAKEFILE` links each with
  `visu.lib` and the demo's shared `disc.obj`; `U2A.EXE` also links `_bg.obk`, a background picture.
  Both are copied to the demo's data folder. The two sources differ only in how they start, end, clear
  the screen, pace themselves and order a few objects (compared line by line).
- **The data** is in `VISU/C/SCENE/`: `U2A.*` and `U2E.*`. Every one of these files, and both
  `.EXE` files, is byte for byte the same as the copy in the shipped demo's data folder
  (`MAIN/DATA/`), so this is the data the demo ran.
- **Not live:** `AVIDFILL.OK`, `ADRAWCLP.OLD`, `AVIDPOLY.OLD`, `AVIDTIMR.OLD`, `*.CUT`, `DOFILLT.C`,
  `DOFILL.1` (older versions and cuttings); `KOE.ASM` (a scratch file); in `C/`: `U2AOK.C`, `U2AOLD.C`,
  `U2ABBK.C`, `U2EOLD.C`, `CITY.C`, `CPLAY.C`, `SRVEC.C` (older players), and `MAIN.C` with
  `READASC.C`, `READVUE.C`, `OSORT.C`, `SAVE.C` ... which is the CONVERTER (`C.EXE`), not part of the demo.
- **Linked but never used by the two scenes:** the 640x400 mode, the font, the sky and dot routines,
  `calc_rotate16`, `calc_project16`, `calc_sftranslate`, `calc_mulrmatrix`, `calc_invrmatrix`,
  `calc_setrmatrix_camera` and the three `calc_setrmatrix_rot...` routines (the scenes' turns come
  ready-made from the animation data).

One check on the source itself: the shipped `U2A.EXE` and `U2E.EXE` contain the light direction
numbers from `ADRAW.ASM`, the field-of-view table, and three runs of exactly 641 seven-byte
instruction pairs where `AVIDFILL.ASM` says the Gouraud fillers are (`tools/visu_reference.py
--check-exe`). So at least those parts of the source are what was shipped.

### Where the data came from

The models were made in 3D Studio (the top-level `3DS/` folder holds project files such as
`UUSALKU.3DS`, "new beginning", and `CITY.ASC`). `C.EXE` (`VISU/C/MAIN.C`, "3DS converter V2.0")
read a text export of the model (`.ASC`), a frame-by-frame export of the camera and object moves
(`.VUE`), a materials list (`.MAT`: for each material a first colour, a fade length of 8, 16 or 32
colours, and `G` for Gouraud) and a two-line settings file (`.INF`), and wrote the engine's files.
`CALKU.BAT` and `CCITY.BAT` show the calls: `c -s10.0 u2a`, `c -s10.0 u2e` (scale 10). The converter
also worked out, for every object, eight back-to-front polygon orders, by actually drawing the object
from eight directions (`OSORT.C`).

## The data

The files are in `Data/Visu/` and are loaded when needed (`Core/Visu/VisuData.swift`). All
numbers are little-endian (lowest byte first). "word" = 2 bytes, "long" = 4 bytes.

| Scene | Files | Bytes |
|---|---|---|
| Ships | `U2A.00M`, `U2A.001`-`003`, `U2A.0AA`, `U2A.0AB`, `U2ABG.UH` | 35,529 + 64,784 (background) |
| City | `U2E.00M`, `U2E.001`-`042`, `U2E.0AA`, `U2E.0AB` | 157,009 |

**How the app carries them.** The data is too big and too binary for Swift source files, so
`./build.sh` copies the folder into the app (`SRMetal.app/Contents/Resources/Visu/`) and the program
reads the files from there. If it is run from somewhere else (for example `.build/release/SRMetal`),
it looks for a `Data/Visu` folder next to or above itself. No new build tools are involved.

### Object file (`NAME.001` ...)

A run of blocks. Each block: 4 letters, a long length, then that many bytes.

| Block | Contents |
|---|---|
| `VERS` | word 0x0100 |
| `NAME` | the object's name as text ending in a zero byte. The name INCLUDES its quote marks: `"s01"`. |
| `VERT` | word: number of vertices. word: unused. Then per vertex 16 bytes: long x, long y, long z, word index of this vertex's Gouraud normal, word unused. |
| `NORM` | word: number of normals. word: how many of them (the first ones) are face normals; the rest are vertex normals for Gouraud. Then per normal 8 bytes: word x, word y, word z (length 16384), word unused. |
| `POLY` | a zero word, then polygon records (below). |
| `ORD0` | an order list: every polygon, unsorted. |
| `ORDE` | eight more order lists, each a back-to-front order for one viewing direction. |
| `END ` | length 0 |

A polygon record is `6 + 2n` bytes: byte n (number of corners), byte flags, byte colour, byte unused,
word index of its face normal, then n words: vertex indices.

An order list is words: the list's length in words; a vertex index; then polygon positions (byte
offsets from the start of the `POLY` block); then 0. In `ORD0` the vertex is the object's centre point.
In each `ORDE` list it is a "direction" vertex placed far out in the direction that list was sorted
for. These extra vertices sit at the end of the `VERT` block: the small ship has 159 vertices, of which
150 belong to polygons, one is the centre and eight are directions.

Flag bits of a polygon (the same bits, moved up 8 places, exist for objects):

| Bits | Meaning | In the two scenes' data |
|---|---|---|
| 0x01 | flip | defined, never read by the engine |
| 0x02 | two-sided (skip the hidden-face test) | never set |
| 0x0C | shade range: 0 none, 0x04 = 8 colours, 0x08 = 16, 0x0C = 32 | 16 and 32 only |
| 0x10 | Gouraud | 484 of 1,206 polygons |
| 0x20 | texture | defined, never implemented |

Polygons have 3 to 12 corners (the engine allows 16).

### Scene file (`NAME.00M`)

| Offset | Contents |
|---|---|
| 0 | 16 header bytes. Byte 15 switched on special object ordering in `U2A.C` if it was `C` or `R`; it is 0 in both files. The long at offset 4 is where the object list starts (784). |
| 16 | the palette: 256 colours, 3 bytes each (red, green, blue, 0...63) |
| 784 | word: number of objects INCLUDING the camera (ships 6, city 58). Then one word per object: its file number. A number that has appeared before means another copy of that object (the ships scene has three copies of ship 001). |

Object 0 is the camera. Every object starts switched off, with all twelve matrix numbers zero.

### Animation (`NAME.0AA`, `NAME.0AB`)

`NAME.0AA` is a list of animations: pairs of words, ending with -1. Both scenes list one animation,
number 1, which means the file `NAME.0AB` (the number written with letters, 0 = A).

`NAME.0AB` is a stream of bytes read once from start to end. It holds, frame by frame, only what
CHANGED, and each change as a difference from the frame before, in as few bytes as it needs:

- a byte `c`. If `c` is 0xFF: the next byte `d` ends the frame when `d` is 0x7F or less (and sets
  the field of view to `d * 256`), or ends the whole animation when it is 0xFF.
- otherwise, if the top two bits of `c` are both set, `c` holds the upper part of an object number
  (`(c & 0x3F) * 16`) and the real `c` follows.
- object number = upper part + `c & 0x0F`. Top two bits of `c`: 10 = switch the object on, 01 = switch
  it off. Bits 0x30 say how many "what changed" bytes follow (0 to 3).
- the "what changed" bits: bits 0-1, 2-3, 4-5 give the size of the change in x, y, z (0 = none,
  1 = one byte, 2 = a word, 3 = a long, all signed). Bit 6: matrix changes are words rather than
  bytes. Bits 7 to 15: which of the nine matrix numbers changed.
- then the changes themselves, in that order, each ADDED to the object's current numbers.

The ships animation has 521 frames, the city 1,801. The field of view never changes: 8704 for the
ships, 7168 for the city.

### Background picture (`U2ABG.UH`, ships only)

16 header bytes, 768 palette bytes, then 320x200 pixels, one byte each, row by row. `U2A.C` copies
the picture's first 64 colours into palette entries 192...255; the pixels already use the numbers
192...242 (and 0). It is a starry sky over a dark landscape, drawn only in rows 25...174.

## Numbers and conventions

- The camera is at (0, 0, 0) looking along +z; x runs right, y runs down.
- A matrix ("rmatrix") is nine longs for the turn, in which **16384 means 1**, and three longs for
  the position.
- Angles are 0...65535 for a full turn. The sine table has 4096 entries of height 16384.
- Screen positions are 16-bit whole pixels. Edge positions while filling are 16.16 fixed point.
  Gouraud colours while filling are 8.8 fixed point: the colour number is the upper byte.
- All three tables are calculated here from the formulas in `DOSIN.C`, `DOTAN.C` and `DOFILL.C` and
  match the original files exactly.

## One picture, step by step

### What the scene program does

1. **Read animation.** One or more frames of the stream are read (see "Timing"). This changes
   the camera's and the objects' matrices and switches objects on or off.
2. **Clear** the page being drawn: the ships copy the background picture in, the city fills it
   with colour 255.
3. **Field of view** (`vid_cameraangle`): the projection multipliers are set from the angle through
   the tangent table: `mulX = (half the window's width) * table[angle / 128] / 256`, `mulY = mulX *
   225 / 256` (225 is the mode's pixel shape). For the ships this gives 360 and 316, for the city 446 and 391 (views about 48 and 40 degrees wide, the "fov" numbers in the converter's settings files).
4. **Each switched-on object** gets its matrix multiplied by the camera's (`calc_applyrmatrix`), so
   that it takes the object's points straight to camera space. The depth of the object's centre point
   is measured (`calc_singlez`).
5. **Order.** The objects are sorted farthest first by that one depth (a plain insertion sort).
   `U2E.C` overrides it in two cases: objects whose name starts with an underscore (the ground
   plates) count as infinitely far, so they are drawn first; and during animation frames 901...1099
   the ship counts as nearest, so it is drawn last.
6. **Draw** each object (`vis_drawobject`).

### What the engine does for one object

1. **Turn and move** every vertex (`calc_rotate`): for each coordinate, three 64-bit products are
   added, shifted right 14, and the position added. It reads only the low 16 bits of each matrix number.
2. **Turn the normals** (`calc_nrotate`), entirely in 16-bit arithmetic.
3. **Project** every vertex (`calc_project`): `screen x = addX + mulX * x / z`, the same for y. A
   vertex nearer than the near plane is flagged NEAR and projected as if at the near plane; each
   vertex also gets flags for being off the left, right, top or bottom of the window. Only 16 bits of
   each screen position are kept.
4. **Whole-object test:** if every vertex has some flag in common, the object is off-screen and skipped.
5. **Choose an order list:** of the eight direction vertices, the one that ended up nearest the
   camera names the list to use. That list is the object's polygons back to front for a viewer in
   that direction. There is no other sorting inside an object.
6. **Each polygon** in that order (`draw_polylist`):
   - **Hidden-face test:** the face normal against the direction to the polygon's first corner
     (three 64-bit products). Facing away: skipped.
   - **Light** (`calclight`): the normal against a fixed light direction (12118, 10603, 3030) gives a
     brightness 0...255, which is divided down to the polygon's shade range (by 8 for 32 shades, by
     16 for 16) and held to 1...30. A flat polygon gets one shade from its face normal, added to its
     colour number. A Gouraud polygon gets one per corner from the corner's vertex normal.
   - **Trivial reject:** if all its corners share an off-window flag, skipped.
   - **Clip** if any corner has a flag (next section).
   - **Edge list** (`poly_nrm` / `poly_grd`): starting from the topmost corner, the polygon's
     outline is walked down both sides at once and written out as "a new left edge starts here, a new
     right edge starts here, now fill this many rows". The original's `DOC` file describes this stream.
   - **Fill** (`drawfill_nrm` / `drawfill_grd`).

### Clipping

`newclip` runs up to five cutters in turn, each only if some corner needs it, passing the polygon
back and forth between two records:

- **Near plane** (`clipnear`), in 3D: where an edge crosses the nearest allowed distance, a new corner
  is worked out and projected. A new corner simply takes the Gouraud colour of the corner written
  before it; the author's `TODO` file reads "ZCLIP / gouraud", so this was known and never finished.
- **Top, bottom, left, right** (`newclipup` and friends), in screen pixels with 16-bit arithmetic: the
  crossing point is found with a multiplier from 0 to 16384, and Gouraud colours are blended by the
  same multiplier.

Each cutter drops a new corner that equals the one before it.

### The two fillers

Both step the two edges FIRST and then fill the row, from the smaller position up to but not
including the larger.

- **Flat** (`drawfill_nrm`): the span in one colour.
- **Gouraud** (`drawfill_grd`): the colour runs evenly from one edge's colour to the other's. For
  speed the row is treated as two end pixels plus a middle of 2-pixel blocks; the colour step per
  block is found by multiplying with a table of 65536 / length; and then, depending on how fast the
  colour changes along the row, the middle is filled with a new colour every pixel, every 2 pixels,
  or every 4 pixels (three unrolled loops, `gouraud1`, `gouraud2`, `gouraud4`). The 4-pixel steps line
  up with the screen's 4-pixel bytes rather than with the polygon, which is where the blocky banding
  in the 1993 pictures comes from.

## Video mode, pages, palette, timing

- **Mode.** "Mode X" 320x200, 256 colours: video memory in four planes, one byte per four pixels in
  each (see docs/original-demo.md). Four pages, 16,384 bytes apart. The engine has a 640x400 mode
  and "oversampling" switches too, but both scenes use the plain 320x200 mode with oversampling off.
- **Window.** Both scenes call `vid_window(0, 319, 25, 174, 512, 9999999)`: a 320x150 band in the
  middle of the screen (black bars above and below), projection centre (159, 99), nothing nearer than
  512.
- **Pages.** The ships draw into a free page while an interrupt at each screen refresh shows
  finished pages in turn, each for as many refreshes as it took to draw (a queue of four). The city
  does the same, more simply.
- **Timing.** The animation is tied to the screen's 70 refreshes a second, not to how fast the PC
  draws: after each picture, the program reads as many animation frames as refreshes have passed.
  For the ships one animation frame is one refresh (521 frames: 7.4 seconds). For the city one
  animation frame is TWO refreshes (1,801 frames: 51.5 seconds). A slow PC simply showed fewer of
  the frames.
- **Palette.** Ships: the scene file's 256 colours with the background's 64 copied into 192...255.
  City: the scene file's colours with 255 and 252 set to black and 253 and 254 to white.

## The two scenes

| | Ships fly-by | 3D city |
|---|---|---|
| Original program | `U2A.C` | `U2E.C` |
| Scene name for `VisuWorld` | `U2A` | `U2E` |
| Objects | 5: three small ships (`"s01"`), one big ship (`"Sippi"`), and an engine (`"moottori"`) that is never switched on | 57: buildings, ground plates, trees, cars, one ship, the "Future Crew" logo |
| Animation | 521 frames, one per 1/70 s | 1,801 frames, one per 2/70 s |
| Field of view | 8704 | 7168 |
| Screen cleared to | the background picture | colour 255 (black) |
| Extra ordering rules | none (the scene file's flag byte is 0) | underscore names first; ship last in frames 901...1099 |
| Starts | waits for the music (order above 10, row above 46), shows the background | fades the previous part to white, wipes to a letterbox, fades to the city's palette, waits for the music (order above 18); the first picture is skipped |
| Ends | when the music reaches order above 11, row above 54, or the animation ends; then all pages are filled with the background | when the animation ends: a 16-step fade to white |

First appearances, in animation frames. Ships: the big ship at 17, two small ships at 260, the
third at 271. City: the first building at frame 1, the ship at 14, the logo at 1455.

## This version

### The 1993 look

| File | What it is |
|---|---|
| `VisuMath.swift` | the three tables; the matrix routines of `ACALC.ASM` |
| `VisuData.swift` | finds and reads the data files |
| `VisuObject.swift` | an object file parsed (`VisuMesh`), and an object in a scene (`VisuObject`) |
| `VisuWorld.swift` | a scene: object list, the animation stream, ordering the objects (`U2A.C` / `U2E.C`) |
| `VisuEngine.swift` | one object to pixels: turn, project, hidden faces, light, clip, edge lists, fill |
| `VisuPlayback.swift` | what the two scenes share: playing the recording, a second copy kept one frame ahead for the modern look's glide, restarting |
| `VisuTest.swift`, `VisuTestCases.swift` | the test cases (the list is written by the reference tool) |

`VisuEngine` draws into a plain 320x200 array of colour numbers, which `IndexedCanvas` can show
through the palette. It was ported step for step from the assembly: the same 16-, 32- and 64-bit
arithmetic, the same order of operations, the same table lookups. The planes of Mode X are not
modelled, because a pixel's plane and byte follow directly from its x position; the fillers' plane
masks are folded into plain "set pixels x1 to x2".

### The modern look

`VisuModern.swift` (`VisuModernRenderer`) draws the same objects as real triangles on the graphics
chip. Every polygon is cut into triangles fanning out from its first corner. What differs from the
1993 look:

- **Resolution and smoothness.** Corners stay in decimals instead of snapping to whole pixels of a
  320x200 grid, and edges are smoothed by taking four samples per pixel.
- **What is in front.** Between objects, a **depth buffer** decides pixel by pixel (the graphics chip
  keeps the distance of what it has drawn at every pixel, and a new pixel only shows if it is nearer).
  The original instead drew whole objects back to front by ONE depth each, so one object could wrongly
  cover another. Within an object, polygons are still drawn back to front in the original's own
  order lists. This is deliberate: the models rely on it. The big ship's panels float just off its
  hull and in places dip slightly inside it; with a depth buffer alone, half of them vanish.
- **Light.** The original's rule, worked out for each corner on the graphics chip without rounding to
  a whole colour number; the colour is then blended between neighbouring palette entries. So shading
  is smooth where the original shows bands and blocks.
- **Near plane.** Cut exactly by the graphics chip, with correct colours, where the original shows
  wrong colours on Gouraud polygons (see "Kept quirks").
- **Motion.** A scene keeps the pose (where every object is) of the last two animation frames and
  draws the blend of the two (`VisuPose.blended`), so movement glides between frames.

Because the app's main drawing pass has no depth buffer, the renderer draws into a picture of its
own first and then lays that over whatever the scene has drawn (its background). For this, scenes now
have an optional `prepare` step that runs before the main pass (`Core/DemoScene.swift`).

Depth is stored as `near / distance` (`Math3D.perspectiveNearOverZ`), not the usual way round,
because the city's distances run from 512 to millions and the usual arrangement runs out of
precision far away.

### Kept quirks (1993 look)

- **Wrong colours at the near plane.** When a Gouraud polygon is cut by the near plane, the new corners
  get the colour of the corner before; the first new corner of a polygon gets whatever was left in
  memory. This shows as stray red or white patches on a ship that is very close:

  | Modern look | 1993 look |
  |---|---|
  | ![](images/visu-ship-clip-near-modern.png) | ![](images/visu-ship-clip-near-classic.png) |

- **A flag that is never cleared.** The near-plane cutter notes which window edges its new corners
  fell outside, in a variable (`clipvisfl`) that is never set back to zero. So after the first such
  corner, every later near-clipped polygon is also run through that edge's cutter, for the rest of
  the scene. This usually changes nothing visible.
- **Crossed angles.** `calc_setrmatrix_rotyxz` and its two siblings turn about the y axis by the z
  angle and about z by the y angle (the routine takes its saved angles off the stack in the wrong
  order). The scenes never call them; only this project's test cases do.
- **16-bit screen positions.** A vertex very far off the side of the screen wraps round.
- **Objects sorted by one point each**, with the city's two overrides.

## What was checked, and how

**Against the original's own assembly.** `tools/visu_reference.py` reads `ACALC.ASM`, `ADRAW.ASM`,
`ADRAWCLP.ASM`, `AVID.ASM`, `AVIDM1.ASM`, `AVIDFILL.ASM` and `ADATA.ASM` as text and carries the
instructions out one by one in the small x86 interpreter shared with the Plasma Cube and Glenz tools
(`tools/x86interp.py`), on the original data. The C parts are re-written in Python. It draws 109 test
cases; `VisuTestCases.swift` (written by the tool) holds the cases and the checksum of each picture,
and the self-test draws every case with the Swift engine and expects the same checksum:

| Cases | What |
|---|---|
| 15 | whole frames of the ships animation |
| 31 | whole frames of the city animation, including both sides of the ship-ordering rule |
| 4 | runs of 40 to 65 consecutive pictures by ONE engine (so leftover state is tested too) |
| 59 | single objects: 6 turns of the small ship; the ship across each window edge, two corners and the near plane; different fields of view; the big ship from outside, inside and below; flat-shaded buildings, Gouraud trees and cars, the logo, polygons with 10 and 12 corners; a second window setting |

All 109 are identical, and the engine met nothing the original would have crashed on (a division
whose result does not fit, a pixel outside the picture). `--coverage` shows what the cases reach:
both fillers (8,572 flat and 19,925 Gouraud polygons), all three Gouraud loops (30,000 to 57,000 rows
each), the near-plane cutter (224 polygons), each edge cutter (1,160 to 2,094), Gouraud colour
blending while clipping (2,662), hidden-face rejects (63,693).

**Departures of the tool from running the text exactly** (none changes a result): the two block
copy / fill helpers, written as 512 hand-encoded instructions that are jumped into, are replaced by
plain loops; the Gouraud loops' jump into the middle of 641 repeated instruction pairs is done by
counting pairs (and the shipped programs were checked to have exactly such runs, 7 bytes a pair);
the C calling wrappers are replaced by direct calls; video set-up (BIOS, VGA registers other than the
plane mask) is not run.

**Tables and data.** The three tables match the original files. The data files match the shipped
demo's copies. The background picture file matches the one linked into `U2A.EXE`.

**The modern look** has nothing exact to compare with. It was looked at next to the 1993 picture
for sixteen cases, and the self-test holds it loosely: the average difference per colour channel
between the two looks stays under 8 out of 255 in seven cases (measured over all 109: 5.0 at most).

### What was NOT checked

- **Against a running original or a recording.** Everything above compares with the original's CODE,
  not with a PC running it.
- **The C parts**, which were ported by reading, twice by the same author (Python and Swift):
  `vis_loadobject`, `vis_drawobject`, the animation reader, the object ordering. A misreading made the
  same way in both would not show. (The pictures are recognisably right, which limits how wrong
  they can be.)
- **Whole scenes.** Nothing on this page covers how the scenes start, end, fade, or keep time with
  the music; the table above is from reading `U2A.C` and `U2E.C`. Each scene's own page says what was
  checked for it ([scenes/ships-flyby.md](scenes/ships-flyby.md), [scenes/city-3d.md](scenes/city-3d.md)).
- **Paths the data never takes:** two-sided polygons, polygons with no shading, 8-shade ranges.
  They are ported but no test reaches them.
- **Mode X page flipping and the screen-refresh queue**: not modelled at all.
- **Which pictures a real PC drew.** A 1993 PC skipped animation frames when it was slow; this
  engine can draw every one. Because of the never-cleared flag above, the exact pixels of a frame
  can depend on which frames were drawn before it. Each single-frame test starts from a fresh engine.
- **The modern look in motion by eye.** For both scenes every step was rendered and compared with
  its neighbours by program (see the scenes' pages). The two things this page used to warn about
  for the city did not happen: objects that sit almost on top of each other (roads on ground plates,
  10 units apart) and frames 901...1099, where the original forced the ship to be drawn last. Drawing
  every city frame with its objects in reverse order changes at most 2 pixels, so the depth buffer
  separates all objects cleanly and the modern picture does not depend on drawing order.

## Not ported

`calc_mulrmatrix`, `calc_invrmatrix`, `calc_setrmatrix_camera` (used only by the converter),
`calc_rotate16`, `calc_project16`, `calc_sftranslate`, the dot, sky, sight, picture-copy and text
routines, the 640x400 mode, and the oversampling switches (always off in the two scenes).
