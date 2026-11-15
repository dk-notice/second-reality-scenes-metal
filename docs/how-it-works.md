# How the app works

This page explains how the app is put together. No scene-specific detail here; each scene has its own page
in [scenes/](scenes/).

Some terms used throughout:

- **Graphics chip** (GPU): the part of the computer built for drawing. It can run the same small calculation
  for millions of pixels at once.
- **Metal**: Apple's system for telling the graphics chip what to do.
- **Shader**: a small program that runs on the graphics chip, once per corner of a shape or once per pixel.
- **Step** (or "tick"): one beat of the scene's clock, 1/70 of a second.
- **Canvas**: a scene's own coordinate system, the size of the original screen: 320 wide by 200 high for
  most scenes (Plasma, Hidden Starfield and Plasma Cube used 400-line screen modes, so their canvas is
  320x400).
- **Palette**: a table that says which colour each pixel number means. A VGA card stored pixels as small
  numbers and looked the colours up in this table.

## One program, many scenes

The original demo was about 20 separate DOS programs run one after another by a loader. This is a single
app. Each scene is a self-contained piece of code that follows one contract, and a shared core does
everything the scenes have in common.

```
Sources/SRMetal/
  Core/        shared by every scene
  Scenes/      one folder per scene
  App/         the window, the menu, the self-test, the picture saver, the list pictures
```

### The contract every scene follows

A scene must be able to do four things (`Core/DemoScene.swift`):

| It must be able to | Meaning |
|---|---|
| `reset()` | Go back to its beginning |
| `tick()` | Advance by one step |
| `draw(...)` | Draw its current state, in whichever look is asked for |
| `classicReferenceFrame()` | Work out its 1993 picture on the processor, for the self-test |

Scenes are listed in one place, `SceneCatalog.all`. The window's sidebar, the keyboard shortcuts, the
`--scene` option and the self-test all read that list, so adding a scene is one new entry there.

Most scenes are split into two files:

- a **model**, which holds the scene's rules and state and knows nothing about graphics, and
- a **scene**, which takes the model's state and draws it with Metal.

Keeping the rules separate makes them easy to check against the original, and easy to read.

## The clock

The original demo was timed to the VGA card, which redrew the screen 70 times per second. The scenes' code
counts frames, so "one step" and "one frame" were the same thing.

Mac displays refresh at 60 or 120 times per second, not 70. So the core (`Core/Renderer.swift`) keeps its
own clock: each time the display wants a new picture, it runs however many 1/70-second steps real time
calls for, then draws. It also works out how far it is towards the next step, a number from 0 to 1, and
passes that to the scene.

## The two looks

Both looks draw the same scene state. The difference is in how.

### Modern look

The scene draws straight onto the screen at the display's full resolution. It uses the "how far to the next
step" number to glide between steps, so motion is smooth at any refresh rate.

### 1993 look

The scene draws onto a tiny picture exactly the size of the original screen (320x200 pixels for most
scenes). That picture
is then scaled up to the window with hard-edged pixels. Motion advances in whole steps only.

A scene never has to know how either look reaches the screen. It is told which look is wanted and the size
of what it is drawing into.

### Why the picture is 4:3

A VGA monitor was 4:3 whatever the pixel grid. 320x200 is not 4:3, so its pixels were not square: each was
about 1.2 times as tall as it was wide. The original coders allowed for that (you will see a "6/5" stretch
in several scenes). The app shows every canvas at 4:3 with black bars around it, so shapes have the
proportions they had on a real monitor. One side effect: the Rings and Interference circles are perfectly
round in pixels, so they appear as slightly tall ovals, exactly as they did in 1993.

## Two ways to make a 1993 look

Scenes use one of two approaches, depending on what the original did.

**Calculate it on the graphics chip.** Where the original's picture follows from a formula, the shader
applies the same formula with the same whole-number rounding. Dot Tunnel, Rings, Interference and Plasma
work this way.

**Replay it on the processor.** Where the original's picture depends on the order things were drawn and
erased in video memory, the model replays those steps exactly, producing a picture of pixel numbers and a
palette. A shared helper, `Core/IndexedCanvas.swift`, then shows it the way a VGA card would. Techno Bars,
Bouncing Dots, Hidden Starfield, 3D Sine Landscape, Plasma Cube, Glenz Vectors and Ships Fly-by work this way.

Some originals showed two slightly different pictures on alternate frames and let the eye mix them.
`IndexedCanvas` can be given both pictures and shows their even mix (Plasma Cube does this).

## The window

The window (`App/SRMetalApp.swift`) is the standard Mac two-part layout, which SwiftUI calls a
`NavigationSplitView`: a **sidebar** on the left listing every scene, and the scene picture filling the
rest. The toolbar holds the Modern / 1993 switch and a restart button.

All of these controls do the same simple thing: they change one small object, `AppModel`, which holds the
current scene, the current look, and whether the sidebar is showing. The sidebar highlight, the toolbar
switch, the window title, the menu and the picture all follow that object, so they cannot disagree.

**Restart** asks the scene to `reset()` and zeroes the clock. The self-test checks that every scene's
`reset()` really does go back to its first frame.

**Single-key shortcuts.** L, R and the arrow keys have no Command key, so macOS would normally offer them
first to whatever has the keyboard focus. A focused sidebar list would keep them: arrow keys move its
selection, and letters jump to a row by name. So the app looks at every key press before the window does
(`AppModel.installKeyShortcuts`), handles just these keys itself, and passes everything else on. The list
never sees an arrow key, so there is nothing to fight over: Up and Down mean previous and next scene, the
same as Left and Right, wherever the focus is.

**Fullscreen.** On the way into fullscreen the sidebar is hidden, and the toolbar is set to appear only when
the pointer is at the top of the screen. On the way out the sidebar goes back to how it was.

### The pictures in the scene list

No picture files are shipped. When the window opens, `App/Thumbnails.swift` draws each scene once into a
small picture (256x192, Modern look), using the same function as the `--snapshot` option
(`Snapshot.render`). Each scene's entry in the scene list names the step to draw (`thumbnailStep`).

Getting to that step means running the scene's rules from the start, up to 1700 steps, which takes a moment.
So the work is done on a **background thread** (a second line of work running alongside the one that draws
the window). The window appears at once with grey placeholders, and each picture pops in when it is ready.

One build detail: SwiftUI's usual way for a view to remember a value (`@State`) needs a compiler plug-in
that only comes with the full Xcode. This project builds with the Command Line Tools alone, so such values
live in `AppModel` instead.

## Shaders are compiled when the app starts

Shader source code is kept as text inside the Swift files and compiled by the system at start-up. The usual
way is to compile shaders while building the app, but that needs the full Xcode. Doing it at start-up means
the project builds with Apple's small Command Line Tools alone.

## The self-test

```bash
build/SRMetal.app/Contents/MacOS/SRMetal --selftest
```

The test opens no window. It checks three kinds of thing.

**Tables and pictures against the original's data.** Several tables that the original loaded from data
files are calculated here instead. The test compares them with values taken from the original files, and
compares the two Interference ring pictures in full by checksum (a single number that changes if any byte
changes).

**The graphics chip against the processor.** For every scene, at several moments, the test draws the 1993
look on the graphics chip, reads the picture back, and compares every pixel with the same frame worked out
on the processor (`classicReferenceFrame()`). Each scene lists its own moments ("checkpoints") in the scene
list.

**Scene behaviour.** For example, that Dot Tunnel loops back to an empty tunnel, and that Interference
returns to its exact first frame after one full run.

**The 3D engine against the original's code.** The engine in `Core/Visu/` is also tested by itself,
apart from the scenes that use it: 109 test pictures (single objects, clipping cases, whole frames of the ships and city
animations) are drawn and their checksums compared with those from the original assembly, run by
`tools/visu_reference.py`. Its modern look is held loosely to the 1993 pictures. See
[visu-engine.md](visu-engine.md).

### Checking motion

The self-test looks at single pictures, and a still picture cannot show a jump or a flicker. For that
there is a separate option, `--motion-check <scene-id> <modern|classic>`, which draws every step of a
scene's loop (the Modern look also half-way between steps), compares each picture with its neighbours
and lists the moments that stand out. It was written for the 3D City, where it found that the recorded
camera rolls in whole-degree steps (see [scenes/city-3d.md](scenes/city-3d.md)).

### What the self-test cannot prove

For scenes that replay the original on the processor, the processor does all the real work and the
graphics chip only looks up colours. The comparison above then proves only that the display path works. It
cannot prove that the replay matches the 1993 program. Those ports were checked by reading the original
assembly carefully, not by running the original. Each scene's page says which kind it is.

## Adding a scene

1. Create `Sources/SRMetal/Scenes/<Name>/` with a model and a scene class that follows the contract.
2. Add one entry to `SceneCatalog.all` in `Core/DemoScene.swift`, with a few checkpoints and a
   `thumbnailStep` (the step that makes a good small picture for the sidebar).
3. Implement `classicReferenceFrame()`. The self-test then covers the scene automatically.
4. Write `docs/scenes/<name>.md`: how the original did it, how this version does, what was checked, and any
   deliberate differences.

Useful shared pieces in `Core/`:

| File | What it gives a scene |
|---|---|
| `Shaders.swift` | Shader compiling, and a ready-made first half for any shader that paints the whole canvas |
| `SinTable.swift` | The 1024-entry sine table several original parts share |
| `IndexedCanvas.swift` | Shows a picture of pixel numbers through a palette of up to 256 colours, or the even mix of two such pictures |
| `Math3D.swift` | For scenes made of 3D shapes: the matrix that reproduces an original's perspective, turns about each axis, the original engine's combined turn matrix, placing a point on the canvas, and the "does this face point at the camera" test (in 3D and on the screen) |
| `SmoothTriangles.swift` | Flat-coloured triangles with smooth edges that meet without seams, for scenes made of polygons |
| `Visu/` | The original demo's 3D engine, for the ships and city scenes: loads the original models and animation, replays the 1993 engine into a picture of pixel numbers, and draws the same objects as real triangles with a depth buffer for the modern look. See [visu-engine.md](visu-engine.md) |

A scene may also implement `prepare(commands:frame:)`. It is called just before `draw`, while no
drawing pass is open, and is for scenes that must first draw into a picture of their own. The 3D engine's
modern look needs this: it uses a depth buffer (a per-pixel record of distance, so that near things cover
far things) and four samples per pixel for smooth edges, and the app's main drawing pass has neither.
Most scenes leave it out.

## House rules for scenes

These came out of building the first scenes.

- **Calculate rather than copy.** If a table the original shipped as data follows a formula, find it,
  prove it reproduces the file exactly, and calculate the table.
- **Keep the 1993 look pixel-faithful in how things are drawn**, including the original's quirks where they
  affect pixels.
- **No original artwork unless a scene cannot do without it.** Two exceptions so far, each declared
  at the top of the scene's page: Glenz Vectors (its chequered plate is a hand-drawn picture, kept as a
  Swift source file) and Ships Fly-by (original 3D models and animation, and the original horizon
  painting behind them, kept as data files in `Data/Visu/`).
- **Make each scene work on its own.** Scenes loop cleanly. Full-screen white flashes and lead-ins to other
  scenes are left out. Straying from the original for this is fine, as long as the scene's page says so.
