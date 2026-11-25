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
calls for, then draws. It also works out how far it is towards the next step, a number from 0 up to
(but never reaching) 1, and passes that to the scene.

The sums are kept in a small piece of their own, `StepClock`, apart from the real time source. That lets
the self-test feed it made-up times: ten seconds of a 60 Hz display, of a 120 Hz one, an hour's pause.
After a pause (window hidden, Mac asleep) the clock catches up on a quarter of a second at most, so a
scene never races through minutes of steps.

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

The test opens no window. It checks these kinds of thing.

**The shared code and the command line.** These run first and live in `App/CoreChecks.swift` (its `run`
also calls the checks kept next to what they check: `Scenes/<Name>/<Name>Checks.swift`, `Demo/DemoChecks.swift`,
`Music/MusicChecks.swift`, `Core/PictureChecks.swift`): the scene
list, the clock, the 4:3 picture area, the start-up options and the `--snapshot` and `--motion-check`
command lines, the 3D helpers, smooth triangles, the palette picture, and the sidebar pictures drawn on
two threads at once. They were added by the code review described at the end of this page.

**Tables and pictures against the original's data.** Several tables that the original loaded from data
files are calculated here instead. The test compares them with values taken from the original files, and
compares the two Interference ring pictures in full by checksum (a single number that changes if any byte
changes).

**The graphics chip against the processor.** For every scene, at several moments, the test draws the 1993
look on the graphics chip, reads the picture back, and compares every pixel with the same frame worked out
on the processor (`classicReferenceFrame()`). Each scene lists its own moments ("checkpoints") in the scene
list. Two black pictures match each other, so at least half of a scene's checkpoints must show a picture.

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

A scene may also implement `demoUpdate(_:)`, which only Play Demo calls, just before each step: it
gives the music's position (section, row, "music plus", sync), so a scene can react to the music as the
original part did. Shown on its own, a scene is never called this and keeps its own clock. Techno Bars
uses it for its flash on the beat (2026-11-24). It is also called once on the step a scene is first shown
(`justShown`), before the demo script checks its next cue: the Lens uses that to start on the same step as
the script when its music cue is already met (2026-11-24).

A scene may also give a `currentCanvasSize` when its canvas changes as it runs; the window and
`--snapshot` then use that instead of the entry's fixed size. Only Play Demo needs it (2026-11-24): to the
window it is one scene, which shows other scenes, pictures and title cards in turn (`Demo/`; see
[demo-timeline.md](demo-timeline.md#play-demo-how-the-app-follows-this-table)).

## Pictures in the Modern look

Some scenes and parts show a picture from the 1993 demo (the Ships horizon, the Glenz plate, Play
Demo's pictures). The 1993 look shows it as it was, as hard-edged pixels. The Modern look runs it once
through **Super-xBR** (`Core/PictureScaler.swift`), a pixel-art scaler by Hyllian: it finds the edges
between the picture's pixels and redraws them as smooth lines and curves, making the picture 8 times
larger in three doubling rounds (320x200 becomes 2560x1600); that is then scaled smoothly to the screen. It only blends the
original's colours, never invents new detail, and a self-test check makes sure no new pixel is brighter
or darker than the original pixels around it. Chosen by the user (2026-11-24) over a plain smooth
stretch, sharp pixels and xBR level 2, after side-by-side pictures (`--scaler-compare`), and 8x over
4x for crisper outlines in fullscreen (it is made while the app runs, so the program does not grow); AI-upscaled
pictures were tried earlier and dropped.

A scene that shows an original picture uses the shared toolkit in `Core/PictureLayer.swift`:
`ScenePicture` holds a picture in both versions (the original, and the Super-xBR one, made on first
use), and `PictureLayer` draws it over the canvas with an optional fade towards white or black. In the
1993 look the fade follows the original's own whole-number rule (each colour level c becomes
(63·a + (64 − a)·c) / 64 towards white), so it gives exactly the colours a 1993 VGA card showed; a
self-test check holds it to that. In the Modern look the fade is smooth and laid on top of the
Super-xBR picture, so the scaler's edge choices do not change as a picture fades.

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

## Code review of the core and the app (2026-11-14)

The code in `Core/` (except the 3D engine in `Core/Visu/`, reviewed separately), in `App/` (except
`VisuTestCommand.swift`), `build.sh` and `Package.swift` was reviewed after all twelve scenes were done:
once with Claude Code's `/code-review` command and once by hand, concentrating on the clock, threads, the
two looks, the palette picture, the layouts shared between Swift and shaders, the 3D helpers, the window,
the command line, the self-test itself and the build script. A finding was only acted on once it had
been shown to be real, by a command or by a new self-test check that fails on the old code.

### Found and fixed

| What was wrong | How it was shown | Fix |
|---|---|---|
| The clock's "how far into the next step" number could be exactly 1, though scenes are promised it stays below 1. (The sum is right in 64-bit numbers; squeezing it into 32 bits rounds it up.) | New check fed the old code ten seconds of a steady 60 Hz and 120 Hz display: it happened both times | The number is held just under 1. No visible effect was ever likely: a picture drawn at 1 is where the next step starts anyway |
| `IndexedCanvas`: a colour number beyond the end of a short palette showed a colour left behind by an earlier frame (the three palette buffers are reused and were never blanked) | New check: 24 of 32 test pixels wrong on the old code | The rest of the buffer is blanked: such pixels are black. No scene's 1993 picture changed |
| `--snapshot` and `--motion-check` crashed on a negative step number | Run: no message, crash exit code 133 | Usage message, exit code 1 |
| `--motion-check` with one number, a mistyped number or a backwards range ignored it and checked the whole loop; a failed `--csv` still ended "successfully" | Run: `... rings classic 100` checked 20,000 steps; `--csv /no/such/x.csv` exited 0 | Usage message, or exit code 1 |
| A mistyped `--scene`, `--look` or `--sidebar` value, or an unknown `--option` (such as `--selftests`), was ignored and the first scene opened | Run | The problem is printed with the list of options and scenes; exit code 2, no window |
| `--snapshot`'s 1993 look chose the canvas pixel under each output pixel's top-left corner; the window uses its centre. Rows and columns could be one output pixel off | New check: 8,658 pixels wrong for Dot Tunnel at 960x720 on the old code | Uses the centre. Pictures in `docs/images/` were not remade (the difference is at most one pixel at block edges) |
| A failed compile left the previous build's app in `build/`, looking like the new one | Ran `build.sh` with a compiler that always fails: the old app survived and ran | `build.sh` removes the old app before compiling |
| Holding the L key flipped the look at the keyboard's repeat rate (R already ignored repeats) | Reasoned from the code only: keys cannot be sent to the app by program | L ignores repeats too. **Not tried by hand** |

### Confirmed sound

- **Clock.** 700 steps in ten seconds (give or take one) at 50, 60, 70, 100, 120 and 144 Hz; never more
  steps in one frame than the display's speed needs (two at 60 Hz, one at 120 Hz); steps plus fraction
  move on by the same amount every frame; 17 steps after an hour's pause; a new scene or a restart begins
  with a frame at step 0 and no carried-over time (read from the code).
- **Threads.** The sidebar's background thread makes its own scenes and its own graphics queue, and the
  only things shared with the main thread are tables that never change after they are first worked out
  (Swift makes that first working-out safe). Pictures reach the window on the main thread. A new check
  draws all twelve sidebar pictures on two threads at once and requires identical results. The app was also
  run under Apple's thread sanitizer (a build that reports two threads touching the same data unsafely):
  100 seconds from launch with the 3D City showing while the sidebar pictures were drawn, and then the
  whole self-test. It reported nothing either time. (Under the sanitizer the self-test's stopwatch check,
  "City 1993 replay keeps up", fails, because the sanitizer makes everything several times slower; the
  other 234 checks pass.) A sanitizer only sees what actually ran, so this is good evidence, not proof.
- **The two looks.** The 4:3 area is the largest centred one for exact, wide and tall windows (new check).
  A 320x400 canvas (Plasma) in the 1993 look was seen centred at 4:3 in a capture of the app's window.
  `--snapshot` works from another folder.
- **Layouts shared with shaders.** `SmoothTriangles.Vertex` is 48 bytes with fields at 0, 16 and 32, as
  Metal lays out `float2, float3, float4`; palettes are `float4`, 16 bytes each (new checks, and a drawn
  test of each).
- **`Math3D`.** The two perspective matrices put a point at centre + focal x (x, y) / z with y downwards
  and give the documented depth values; quarter turns go the documented way; the original's combined turn
  `rotationYXZ` equals turn-about-y x turn-about-x x turn-about-z with each angle the OPPOSITE way round
  from the single-axis helpers (now noted here; found by trying every order); the 3D and on-screen
  "faces the camera" tests agree on 500 triangles.
- **`SmoothTriangles`.** Triangles with no area add nothing; either corner order gives true edge
  distances and a one-pixel margin; two triangles sharing an edge draw as one even square of the right area.
- **`build.sh`.** Stops on any failed step; copies all 52 data files; the signature verifies.

### Weak self-test checks

- *Graphics chip against reference* passed when both pictures were black (21 of the 124 checkpoints are),
  and skipped a checkpoint without failing if it could not draw. Now: a failure if it cannot draw, and at
  least half of each scene's checkpoints must show a picture.
- *Dot Tunnel loops* only checked a counter that the model sets to 0 itself. Now it also checks that the
  tunnel is empty on the last step and that the picture after the loop is the first picture.
- Checkpoints out of order would have been compared at the wrong step: now checked.
- The self-test now prints how many checks ran, so a block of checks going missing shows.
- Left as they are, reported to the sessions that own them: *VISU modern look stays close in 7 test
  cases* skips any case it cannot find by name, so it could pass having compared fewer than seven (or
  none); *City 1993 replay keeps up* is a stopwatch test and can fail on a busy Mac with nothing wrong.

### Known limits, not changed

- `byteFromVGA` stops the program if given a value outside 0...63. No scene does; clamping instead would
  hide a scene's mistake.
- `Math3D.project` has no guard for points at or behind the camera. Its one user (Plasma Cube) never has any.
- `SmoothTriangles` draws a triangle much thinner than a pixel too bright (about a quarter of a pixel
  wide however thin it is). Only matters for faces seen almost exactly edge-on.
- If the 1993 look's small picture cannot be created (out of graphics memory) the window shows an
  undefined picture rather than black. Could not be made to happen, so not touched.
- The clock reads the time when the display asks for a picture, not the time the picture will appear.
  Using the display's own timestamp might make Modern motion a touch more even; a proposal, not a fault.

### Not verified

- Anything that needs a person at the keyboard: L, R and the arrow keys with the sidebar focused, holding
  L down, the toolbar, fullscreen in and out (and the sidebar coming back), resizing, moving the window
  between a Retina and an ordinary display, sleep and wake, quitting while the sidebar pictures are still
  being drawn, and what macOS restores at the next launch.
- A 60 Hz display: this Mac's is 120 Hz, so 60 Hz was checked with made-up times only.
- The window's own scaling-up of the 1993 picture is checked by eye in a capture, not pixel by pixel
  (the self-test checks the small picture, and `--snapshot`'s scaling, exactly).
- Macs with Intel graphics.
- Whether all twelve sidebar pictures had finished within the sanitizer's 100 seconds was not observed
  (drawn one after another by themselves under the sanitizer they take about 50 seconds).

