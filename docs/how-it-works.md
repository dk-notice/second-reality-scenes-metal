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
  most scenes (Plasma used a 320x400 screen mode, so its canvas is 320x400).
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
  App/         the window, the menu, the self-test, the picture saver
```

### The contract every scene follows

A scene must be able to do four things (`Core/DemoScene.swift`):

| It must be able to | Meaning |
|---|---|
| `reset()` | Go back to its beginning |
| `tick()` | Advance by one step |
| `draw(...)` | Draw its current state, in whichever look is asked for |
| `classicReferenceFrame()` | Work out its 1993 picture on the processor, for the self-test |

Scenes are listed in one place, `SceneCatalog.all`. The app's scene list, the keyboard shortcuts, the
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
palette. A shared helper, `Core/IndexedCanvas.swift`, then shows it the way a VGA card would. Techno Bars
and Bouncing Dots work this way.

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

### What the self-test cannot prove

For scenes that replay the original on the processor, the processor does all the real work and the
graphics chip only looks up colours. The comparison above then proves only that the display path works. It
cannot prove that the replay matches the 1993 program. Those ports were checked by reading the original
assembly carefully, not by running the original. Each scene's page says which kind it is.

## Adding a scene

1. Create `Sources/SRMetal/Scenes/<Name>/` with a model and a scene class that follows the contract.
2. Add one entry to `SceneCatalog.all` in `Core/DemoScene.swift`, with a few checkpoints.
3. Implement `classicReferenceFrame()`. The self-test then covers the scene automatically.
4. Write `docs/scenes/<name>.md`: how the original did it, how this version does, what was checked, and any
   deliberate differences.

Useful shared pieces in `Core/`:

| File | What it gives a scene |
|---|---|
| `Shaders.swift` | Shader compiling, and a ready-made first half for any shader that paints the whole canvas |
| `SinTable.swift` | The 1024-entry sine table several original parts share |
| `IndexedCanvas.swift` | Shows a picture of pixel numbers through a palette of up to 256 colours |

## House rules for scenes

These came out of building the first six.

- **Calculate rather than copy.** If a table the original shipped as data follows a formula, find it,
  prove it reproduces the file exactly, and calculate the table.
- **Keep the 1993 look pixel-faithful in how things are drawn**, including the original's quirks where they
  affect pixels.
- **Make each scene work on its own.** Scenes loop cleanly. Full-screen white flashes and lead-ins to other
  scenes are left out. Straying from the original for this is fine, as long as the scene's page says so.
