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
  most scenes. Plasma, Plasma Cube, Hidden Starfield, the Jelly Logo, the Troll, the Screen Switching
  Off and the title and end pictures used 400-line screen modes, so their canvas is 320x400; the
  Rotozoomer's is 160x100 (it drew double-size pixels) and the End Scroller's 640x400.
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
  Demo/        Play Demo: the running order as a script, and the scene that follows it
  Music/       the tracker songs: loading, playing, and where the music is right now
  App/         the window, the menus, the self-test, the picture saver, the list pictures
Data/          original files the program loads (3D models, songs, tables that cannot be calculated)
artwork/       the original pictures, exported to PNG
tools/         development-only scripts that replay the original's data, for checking
```

### The contract every scene follows

A scene must be able to do four things (`Core/DemoScene.swift`):

| It must be able to | Meaning |
|---|---|
| `reset()` | Go back to its beginning |
| `tick()` | Advance by one step |
| `draw(...)` | Draw its current state, in whichever look is asked for |
| `classicReferenceFrame()` | Work out its 1993 picture on the processor, for the self-test |

Scenes are listed in one place, `SceneCatalog.all`, in the demo's order. The window's sidebar, the
keyboard shortcuts, the `--scene` option, the self-test and Play Demo all read that list.

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
After a stall the clock catches up on a quarter of a second at most, so a scene never races through
minutes of steps.

Play Demo is different, because its music plays on a clock of its own and does not stall with the picture.
Two rules keep them together:

- **A short stall is made up in full**, up to 5 seconds (a scene being made at a part change, a hitch):
  the missed steps are run at once. Dropped, every later step would lag the music by that much.
- **While nobody can see the picture, everything pauses**: when the window is minimised, fully covered or
  on another desktop, or the Mac goes to sleep, the picture stops and the music with it, and both carry on
  from the same place. (Catching up afterwards would not do: some parts wait for one exact row of the
  music, a tenth of a second long, and would miss it.) The scene's view reports whether its window can be
  seen; this holds for scenes on their own too, which simply stand still.

The sound output itself can stop: macOS stops it when the output device changes (headphones connected,
another device chosen). The player then makes its output again at the new device's rate and carries on
with the song from its place. If there is no sound output at all, Play Demo would wait for music that
never comes, so the window's title says "NO SOUND" and why.

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
applies the same formula with the same whole-number rounding. Rings, Interference and Plasma work this
way.

**Replay it on the processor.** Where the original's picture depends on the order things were drawn and
erased in video memory, the model replays those steps exactly, producing a picture of pixel numbers and a
palette. A shared helper, `Core/IndexedCanvas.swift`, then shows it the way a VGA card would. Dot Tunnel (its dots are drawn and
erased one by one, as in 1993), Techno Bars,
Bouncing Dots, Hidden Starfield, 3D Sine Landscape, Plasma Cube, Glenz Vectors, Ships Fly-by, the 3D City,
the Rotozoomer, the Lens, the Jelly Logo, the two scrollers and the End Scroller work this way.

**Show the original picture.** The Explosion, the title and end pictures and the Troll show an original
picture through the shared picture toolkit (see "Pictures in the Modern look" below), with the original's
fade arithmetic. The Screen Switching Off has a shader of its own.

Some originals showed two slightly different pictures on alternate frames and let the eye mix them.
`IndexedCanvas` can be given both pictures and shows their even mix (Plasma Cube does this).

## The window

The window (`App/SRMetalApp.swift`) is the standard Mac two-part layout, which SwiftUI calls a
`NavigationSplitView`: a **sidebar** on the left, and the scene picture filling the rest. The sidebar's
first row is Play Demo; below a "Scenes" heading come all the scenes. The toolbar holds the Modern / 1993
switch and a restart button.

**Start-up and the end.** With no `--scene` option the app starts in Play Demo from the beginning, with
the music on and the sidebar hidden (`StartupOptions`). Escape, or Stop Demo, stops it and opens the
sidebar on the scene the demo was showing (`AppModel.stopDemoAndBrowse`). When the demo reaches its own
end, the end scroller's last line, the picture stays black, Play Demo stays chosen and the sidebar opens
(`DemoRunScene.onEnd`, `AppModel.demoEnded`). It does not go on to the End Scroller scene: that would
start the text again and look like a loop.

All of these controls do the same simple thing: they change one small object, `AppModel`, which holds the
current scene, the current look, whether the sidebar is showing, and whether Play Demo is running. The sidebar highlight, the toolbar
switch, the window title, the menu and the picture all follow that object, so they cannot disagree.

**Restart** asks the scene to `reset()` and zeroes the clock. The self-test checks that every scene's
`reset()` really does go back to its first frame.

**Single-key shortcuts.** L (look), R (restart), P (Play Demo), M (mute), the arrow keys (previous and
next scene) and Escape (stop the demo; only while it plays) have no Command key, so macOS would normally offer them
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

Getting to that step means running the scene's rules from the start, up to 1700 steps, which takes a moment
(and some scenes first make their 8x pictures).
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

The test opens no window and takes about 40 seconds. A word after it runs only the groups of checks
whose label contains that word, in a second or two: a scene id (`--selftest interference`), or a topic
such as `demo` (every Play Demo check), `music` or `core`. The last line then says it was not the full
self-test, and a word that matches nothing is a failure. That is for working on one area; the full
self-test is run before every commit.

It checks these kinds of thing.

**The shared code and the command line.** These run first and live in `App/CoreChecks.swift` (its `run`
also calls the checks kept next to what they check: `Scenes/<Name>/<Name>Checks.swift`, `Demo/DemoChecks.swift`,
`Music/MusicChecks.swift`, `Core/PictureChecks.swift`): the scene
list, the clock, the 4:3 picture area, the start-up options and the `--snapshot` and `--motion-check`
command lines, the 3D helpers, smooth triangles, the palette picture, and the sidebar pictures drawn on
two threads at once.

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

**Replays against a second replay.** The scenes that replay original data (rotozoomer, lens, jelly logo,
the two scrollers and others) each have a reference tool in `tools/`, written separately in Python, that
replays the same original files and prints checksums of the picture at chosen steps. The self-test holds
the app's 1993 pictures to those checksums.

**Play Demo.** The running order is run silently against the music (the whole demo in a fraction of a
second) and every part must start on the step the research simulation gives; started part-way from each
scene and part, every later part must still start on the same step; and each scene that waits for the
music must react on the very step the script gets past that cue.

There are 652 checks in all; the test's last lines give the number run. The full self-test fails if
that number is not `SelfTest.expectedChecks`, so a block of checks that silently stops running is
noticed. Each new check is first shown to fail with the thing it guards broken on purpose.

**The 3D engine against the original's code.** The engine in `Core/Visu/` is also tested by itself,
apart from the scenes that use it: 124 test pictures (single objects, clipping cases, whole frames of the ships and city
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
2. Add one entry to `SceneCatalog.all` in `Core/DemoScene.swift` (at its place in the demo's order), with
   a few checkpoints and a `thumbnailStep` (the step that makes a good small picture for the sidebar).
3. Implement `classicReferenceFrame()`. The self-test then covers the scene automatically.
4. For a scene that replays original data: a reference tool `tools/<scene>_reference.py`, and the scene's
   own checks in `Scenes/<Name>/<Name>Checks.swift` (one line in `CoreChecks.run` calls them).
5. If the scene is a part of the demo: show it in the running order (`DemoScript.steps` in
   `Demo/DemoSequencer.swift`) and, if it waits for the music, implement `demoUpdate(_:)`.
6. Data that cannot be calculated goes in `Data/<Name>/` with a README, and `build.sh` copies it.
7. Write `docs/scenes/<name>.md`: how the original did it, how this version does, what was checked, and any
   deliberate differences.

Useful shared pieces in `Core/`:

| File | What it gives a scene |
|---|---|
| `Shaders.swift` | Shader compiling, and a ready-made first half for any shader that paints the whole canvas |
| `SinTable.swift` | The 1024-entry sine table several original parts share |
| `IndexedCanvas.swift` | Shows a picture of pixel numbers through a palette of up to 256 colours, or the even mix of two such pictures |
| `Math3D.swift` | For scenes made of 3D shapes: the matrix that reproduces an original's perspective, turns about each axis, the original engine's combined turn matrix, placing a point on the canvas, and the "does this face point at the camera" test (in 3D and on the screen) |
| `SmoothTriangles.swift` | Flat-coloured triangles with smooth edges that meet without seams, for scenes made of polygons |
| `PictureLayer.swift` | An original picture in both versions, drawn over the canvas with the original's fades (see "Pictures in the Modern look") |
| `PictureScaler.swift` | Super-xBR: makes a small picture 8 times larger for the Modern look |
| `ScrollTables.swift` | For the mountain and water scrollers: reads their position tables and fits the Modern look's smooth map to them |
| `DataFolder.swift` | Finds a folder of original data, inside the app or in the project while developing |
| `Visu/` | The original demo's 3D engine, for the ships and city scenes: loads the original models and animation, replays the 1993 engine into a picture of pixel numbers, and draws the same objects as real triangles with a depth buffer for the modern look. See [visu-engine.md](visu-engine.md) |

A scene may also implement `prepare(commands:frame:)`. It is called just before `draw`, while no
drawing pass is open, and is for scenes that must first draw into a picture of their own. The 3D engine's
modern look needs this: it uses a depth buffer (a per-pixel record of distance, so that near things cover
far things) and four samples per pixel for smooth edges, and the app's main drawing pass has neither.
Most scenes leave it out.

A scene may also implement `demoUpdate(_:)`, which only Play Demo calls, just before each step: it
gives the music's position (section, row, "music plus", sync), so a scene can react to the music as the
original part did. Shown on its own, a scene is never called this and keeps its own clock. Techno Bars
uses it for its flash on the beat; the troll, the end picture, the lens, the rotozoomer, the jelly logo
and the two scrollers use it to wait for the same music cues as the original parts. It is also called once on the step a scene is first shown
(`justShown`), before the demo script checks its next cue: the Lens uses that to start on the same step as
the script when its music cue is already met.

A scene may also give a `currentCanvasSize` when its canvas changes as it runs; the window and
`--snapshot` then use that instead of the entry's fixed size. Only Play Demo needs it: to the
window it is one scene, which shows other scenes, pictures and title cards in turn (`Demo/`; see
[demo-timeline.md](demo-timeline.md#play-demo-how-the-app-follows-this-table)).

## Pictures in the Modern look

Many scenes show a picture from the 1993 demo (the Ships horizon, the Glenz plate, the explosion's
frames, the title and end pictures, the troll, the lens picture, the jelly logo, the scrollers'
backgrounds, and the credits pictures Play Demo still shows as stills). The 1993 look shows it as it was, as hard-edged pixels. The Modern look runs it once
through **Super-xBR** (`Core/PictureScaler.swift`), a pixel-art scaler by Hyllian: it finds the edges
between the picture's pixels and redraws them as smooth lines and curves, making the picture 8 times
larger in three doubling rounds (320x200 becomes 2560x1600); that is then scaled smoothly to the screen. It only blends the
original's colours, never invents new detail, and a self-test check makes sure no new pixel is brighter
or darker than the original pixels around it. It was chosen over a plain smooth stretch, sharp pixels
and xBR level 2 from side-by-side pictures (`--scaler-compare`), and 8x over 4x for crisper outlines in
fullscreen (it is made while the app runs, so the program does not grow). No AI-upscaled artwork is used.

A scene that shows an original picture uses the shared toolkit in `Core/PictureLayer.swift`:
`ScenePicture` holds a picture in both versions (the original, and the Super-xBR one, made on first
use), and `PictureLayer` draws it over the canvas with an optional fade towards white or black. In the
1993 look the fade follows the original's own whole-number rule (each colour level c becomes
(63·a + (64 − a)·c) / 64 towards white), so it gives exactly the colours a 1993 VGA card showed; a
self-test check holds it to that. In the Modern look the fade is smooth and laid on top of the
Super-xBR picture, so the scaler's edge choices do not change as a picture fades.

## House rules for scenes

- **Calculate rather than copy.** If a table the original shipped as data follows a formula, find it,
  prove it reproduces the file exactly, and calculate the table.
- **Keep the 1993 look pixel-faithful in how things are drawn**, including the original's quirks where they
  affect pixels.
- **Original artwork is declared.** Each scene that uses original pictures or data says so at the top of
  its page, and the README lists them. No AI-upscaled artwork: the Modern look scales the originals with
  Super-xBR.
- **Make each scene work on its own.** Scenes loop cleanly, silently. Some (Rings, Interference, Dot
  Tunnel and others) leave out full-screen white flashes and lead-ins to other scenes; most keep what the
  original part showed. A scene on its own gets no invented pause where the demo waited for the music, unless the
  original really showed something during that wait. Straying from the original is fine, as long as the
  scene's page says so.
- **Inside Play Demo a scene follows the music** as the original part did, to the step.

## Video export

`--export-video` (`App/VideoExport.swift`) makes the raw material for a video of the whole of Play Demo
in the Modern look: 2880x2160 pictures at 60 a second, and the music as a WAV file. It follows no clock.
The demo is stepped against silently rendered music, 630 sound sample pairs a step at 44,100 Hz (735 a
picture), and picture k is drawn at step 7k div 6 with a blend of (7k mod 6)/6 towards the next step. So
sound and picture cannot drift, however fast or slow the Mac is. The export ends with the demo itself.

`tools/export_video.py` runs it and hands the pictures and sound to ffmpeg, which writes a ProRes 422 .mov
to `~/Movies/`; `tools/check_video.py` checks the finished file (counts, the sound byte for byte, song 2's
start, pictures either side of part starts). ffmpeg is needed only by those two scripts: the app and
`build.sh` never use it. One trap: ffmpeg's default conversion back to red-green-blue comes out 2-3 levels
dark, so the check decodes with `accurate_rnd`; the file itself is right. The self-test checks the
arithmetic and that an exported picture equals `--snapshot`'s.

## How the reference tools work

The reference tools in `tools/` are development-only Python (standard library only); the app never runs
them. Several of them run the original's assembly SOURCE TEXT in a small interpreter, `tools/x86interp.py`:
not a PC emulator, but a reader of Turbo Assembler text that lays out the data in a 1 MB memory with the
VGA's four planes and runs each instruction as a small Python function. A base layer handles IDEAL-style
text and about 35 instructions; a MASM layer turns macros, `REPT` and `dup` into that dialect and adds
calls and the VGA colour ports; `visu_reference.py` adds more of its own. An unsupported instruction only
fails if it is actually run, so check new code paths before trusting a result.

What was learned using them:

- Read the part's MAKEFILE first: it settles which files, and even which artwork, were live.
- Built files can differ from their generator source, and a source folder's compiled files from the
  released program: check against the released one (see `state.md`, "Changing or rebuilding a scene").
- Self-modifying code (numbers patched into instructions) needs a small text rewrite before it can be
  interpreted.
- Compare palettes as well as screens: a reference run once found a port mistake that reading had missed.
- Fill the heap with 0xCC before each test case, so a result cannot quietly depend on an earlier case.

## Swift and Metal traps

- `setVertexBytes` holds at most 4 KB. Use a vertex buffer for anything bigger.
- The Swift compiler can give up ("unable to type-check in reasonable time") on a closure that builds a
  `SIMD4` from several `Float(...)` conversions and divisions; write the parts out as separate `let`s.

## Known limits of the core

- `byteFromVGA` stops the program if given a value outside 0...63. No scene does; clamping instead would
  hide a scene's mistake.
- `Math3D.project` has no guard for points at or behind the camera. Its one user (Plasma Cube) never has any.
- `SmoothTriangles` draws a triangle much thinner than a pixel too bright (about a quarter of a pixel wide
  however thin it is). Only matters for faces seen almost exactly edge-on.
- Not tried: Macs with Intel graphics (the app is built for Apple silicon only), and a 60 Hz display
  other than with made-up times.
