# Second Reality Scenes (Metal)

Scenes from Future Crew's 1993 PC demo *Second Reality*, re-created from scratch as one native macOS app
that draws on the graphics chip.

Every scene can be shown two ways, switchable at any time:

- **Modern look**: full display resolution, soft edges, smooth motion.
- **1993 look**: the original pixels (320x200 for most scenes) and 70 steps per second, as on a 486 with a
  VGA card.

| | Modern look | 1993 look |
|---|---|---|
| Dot Tunnel | ![](docs/images/dot-tunnel-modern.png) | ![](docs/images/dot-tunnel-classic.png) |
| Rings | ![](docs/images/rings-modern.png) | ![](docs/images/rings-classic.png) |
| Interference | ![](docs/images/interference-modern.png) | ![](docs/images/interference-classic.png) |
| Techno Bars | ![](docs/images/techno-bars-modern.png) | ![](docs/images/techno-bars-classic.png) |
| Bouncing Dots | ![](docs/images/bouncing-dots-modern.png) | ![](docs/images/bouncing-dots-classic.png) |
| Plasma | ![](docs/images/plasma-modern.png) | ![](docs/images/plasma-classic.png) |
| Hidden Starfield | ![](docs/images/starfield-modern.png) | ![](docs/images/starfield-classic.png) |
| 3D Sine Landscape | ![](docs/images/sine-landscape-modern.png) | ![](docs/images/sine-landscape-classic.png) |
| Plasma Cube | ![](docs/images/plasma-cube-modern.png) | ![](docs/images/plasma-cube-classic.png) |
| Glenz Vectors | ![](docs/images/glenz-vectors-modern.png) | ![](docs/images/glenz-vectors-classic.png) |
| Ships Fly-by | ![](docs/images/ships-flyby-modern.png) | ![](docs/images/ships-flyby-classic.png) |
| 3D City | ![](docs/images/city-3d-modern.png) | ![](docs/images/city-3d-classic.png) |

## What this is, and is not

This is not a port of the demo, and it does not play the demo from start to finish. A complete port already
exists (see [Credits](#credits-and-sources)). This project takes scenes one at a time, works out from the
original source code how each was done, and builds it again in a modern way, keeping a pixel-faithful 1993
look alongside for comparison.

The interesting part is the comparison. The original is full of tricks for making a slow machine look fast.
A modern graphics chip needs none of them, so each scene's documentation explains what the trick was and
what replaced it.

The demo's two original songs can be played from the **Music** menu: the real tracker music, played live by
libopenmpt, which is built into the program (see [ThirdParty/README.md](ThirdParty/README.md)).

**Play Demo** (in the **Scene** menu, or press P) runs the whole demo, all 19 parts in the original order with
the original music, changing parts on the same music cues the 1993 demo waited for. It is a skeleton for now:
the parts this project has built appear as its scenes, cut where the original part ended; picture parts show
the original pictures (in the Modern look made larger by Super-xBR, a pixel-art scaler); every other part shows a title card
naming it. See [docs/demo-timeline.md](docs/demo-timeline.md).

## Scenes

| Scene | Original coder | How the original did it, and how this version does |
|---|---|---|
| Dot Tunnel | Trug | [docs/scenes/dot-tunnel.md](docs/scenes/dot-tunnel.md) |
| Rings, Interference | Psi | [docs/scenes/rings-and-interference.md](docs/scenes/rings-and-interference.md) |
| Techno Bars | Psi | [docs/scenes/techno-bars.md](docs/scenes/techno-bars.md) |
| Troll, Screen Switches Off | Psi; Wildfire | [docs/scenes/troll-and-switch-off.md](docs/scenes/troll-and-switch-off.md) |
| Rotozoomer | Psi | [docs/scenes/rotozoomer.md](docs/scenes/rotozoomer.md) |
| Bouncing Dots | Psi | [docs/scenes/bouncing-dots.md](docs/scenes/bouncing-dots.md) |
| Plasma | Wildfire | [docs/scenes/plasma.md](docs/scenes/plasma.md) |
| Hidden Starfield | Psi | [docs/scenes/starfield.md](docs/scenes/starfield.md) |
| 3D Sine Landscape | Psi | [docs/scenes/sine-landscape.md](docs/scenes/sine-landscape.md) |
| Plasma Cube | Wildfire | [docs/scenes/plasma-cube.md](docs/scenes/plasma-cube.md) |
| Glenz Vectors | Psi | [docs/scenes/glenz-vectors.md](docs/scenes/glenz-vectors.md) |
| Ships Fly-by | Psi | [docs/scenes/ships-flyby.md](docs/scenes/ships-flyby.md) |
| Explosion | Trug, Wildfire | [docs/scenes/explosion.md](docs/scenes/explosion.md) |
| End Scroller | Future Crew | [docs/scenes/end-scroller.md](docs/scenes/end-scroller.md) |
| Title Picture, End Picture | Future Crew | [docs/scenes/title-and-end-pictures.md](docs/scenes/title-and-end-pictures.md) |
| 3D City | Psi | [docs/scenes/city-3d.md](docs/scenes/city-3d.md) |

All twelve planned scenes are done: the purely calculated scenes and the 3D scenes. The last two, Ships
Fly-by and the 3D City, share the original's 3D engine, which was built and checked against the original's
code first: see [docs/visu-engine.md](docs/visu-engine.md). Picture-based scenes, scrollers and stills were
out of scope at first. Since Play Demo exists (2026-11-24) the remaining parts are being added one at a
time, starting with the Explosion (the original's hand-drawn animation), the title and end pictures, the troll and the screen
switch-off, the end scroller and the rotozoomer. The ideas are in
[docs/future-ideas.md](docs/future-ideas.md).

Everything on screen is calculated, with three exceptions (all public domain, like the rest of the
original). Glenz Vectors includes the original's hand-drawn chequered plate, because the scene cannot do
without it. And Ships Fly-by is made of original material: the ships are the original's 3D models and
recorded camera moves, read from [Data/Visu/](Data/Visu/README.md) (models and animation cannot be
calculated), and they fly over the original's hand-painted horizon picture, kept at the user's request. The 3D City
is likewise the original's models and recorded flight, with no picture. The Explosion is the original's
hand-drawn animation frames, the Title and End Pictures are the original pictures, and the Rotozoomer
turns the original lens picture.

## Build and run

You need a Mac with macOS 15 or later and Apple's Command Line Tools (`xcode-select --install`).
The full Xcode app is not needed, and nothing else needs installing: the one outside library, libopenmpt
(for the music), is included as source code and built by `build.sh`.

```bash
./build.sh
```

```bash
open build/SRMetal.app
```

### Controls

![The app's window: scene list on the left, the scene on the right](docs/images/window.png)

The window has a list of scenes down the left (the sidebar) and a toolbar along the top.

| To do this | Use |
|---|---|
| Choose a scene | Click it in the sidebar, or press the Right / Down arrow (next) or Left / Up arrow (previous) |
| Switch between the Modern and 1993 looks | The **Modern / 1993** switch in the toolbar, or press L |
| Play the current scene again from its start | The circular-arrow button at the right of the toolbar, or press R |
| Hide or show the sidebar | The sidebar button at the left of the toolbar, or Control-Command-S |
| Fullscreen | The green window button, or Control-Command-F (in newer macOS versions also the Globe key with F) |
| Play one of the demo's two songs, from its start | **Music** menu, "Play Song 1" or "Play Song 2" |
| Stop the music | **Music** menu, "Stop Music", or Command-. (full stop) |
| Play the whole demo with its music | **Scene** menu, "Play Demo", or press P (again: from the start) |
| Stop the demo | Escape, **Scene** menu "Stop Demo", or choose any scene |

In fullscreen the sidebar and toolbar get out of the way so that only the scene shows; the keys above still
work, and moving the pointer to the top of the screen brings the toolbar back. Leaving fullscreen puts the
sidebar back as it was.

The look, restart and next/previous actions are also in the **Scene** menu.

The music's sound follows the look: smooth in the Modern look; in the 1993 look the samples are played
without smoothing, which sounds grittier, closer to a sound card of the time. Each song plays to its end
(Song 1 lasts about 10 minutes, Song 2 about 7). Song 1 plays at tempo 120, as the demo played it, not at
the 125 written in the file.

### Options

Put these after `--args` when starting the app, for example
`open build/SRMetal.app --args --scene techno-bars --look classic`.

| Option | Meaning |
|---|---|
| `--scene <id>` | Start on a scene: `dot-tunnel`, `rings`, `interference`, `techno-bars`, `troll`, `switch-off`, `rotozoomer`, `bouncing-dots`, `plasma`, `starfield`, `sine-landscape`, `plasma-cube`, `glenz-vectors`, `ships-flyby`, `explosion`, `title-picture`, `city-3d`, `end-picture`, `end-scroller`; or `play-demo` to start the whole demo |
| `--look modern` or `--look classic` | Start in that look |
| `--sidebar hidden` | Start with the scene list hidden |

A mistyped option or scene name is reported (run the program directly to see the message) and the app
does not start.

Two more are run directly on the program inside the app, and open no window:

```bash
build/SRMetal.app/Contents/MacOS/SRMetal --selftest
```

runs the checks (see [docs/how-it-works.md](docs/how-it-works.md#the-self-test)), and

```bash
build/SRMetal.app/Contents/MacOS/SRMetal --snapshot dot-tunnel modern 500 picture.png
```

saves a picture of a scene at a given step. The pictures on this page were made that way. `play-demo`
works too (the music is then rendered silently to find the place): `--snapshot play-demo modern 7500 title.png`
shows the title picture, 7,500 steps (1:47) into the demo. (For the
Modern look, a number from 0 to 1 added at the end draws the picture that far on towards the next step;
this is for checking that motion is smooth.)

```bash
build/SRMetal.app/Contents/MacOS/SRMetal --visu-test city-0800 modern picture.png
```

saves a picture of one of the 3D engine's test cases, in either look (`--visu-test list` names them).

```bash
build/SRMetal.app/Contents/MacOS/SRMetal --motion-check city-3d modern
```

checks a scene's motion: it draws every step of the scene's loop (the Modern look also half-way between
steps), compares each picture with its neighbours, and lists jumps and pixels that show for one picture
only. It also reports how long one step takes. (`classic` checks the 1993 look.)

```bash
build/SRMetal.app/Contents/MacOS/SRMetal --music-info
```

loads the demo's two songs and describes them, without playing anything. Add `--write <folder>` to also
save them unscrambled as standard S3M files (see [Data/Music/README.md](Data/Music/README.md)).

```bash
build/SRMetal.app/Contents/MacOS/SRMetal --music-render 1 20 song1.wav classic
```

saves the first 20 seconds of song 1 (or 2) as a WAV sound file without playing it, in the `modern` or
`classic` (1993) sound; `--music-play 1 10 classic` plays them through the speakers instead.

```bash
build/SRMetal.app/Contents/MacOS/SRMetal --demo-timeline
```

runs Play Demo's whole running order against the music, silently, in well under a second, and lists when each
part starts. It checks every start against the research simulation (`tools/demo_timeline.py`); the self-test
does the same.

```bash
build/SRMetal.app/Contents/MacOS/SRMetal --scaler-compare 07-troll out-folder 120 15 80
```

saves two sheets comparing four ways of scaling up one of the original pictures for the Modern look
(smooth, sharp pixels, xBR level 2, Super-xBR): the whole picture, and a part of it (here 80 pixels
wide from 120, 15) as it would look filling a screen. The xBR scalers are written from Hyllian's
shaders (MIT licence).

## Documentation

- [docs/how-it-works.md](docs/how-it-works.md): how the app is put together, the two looks, the self-test,
  and how to add a scene.
- [docs/original-demo.md](docs/original-demo.md): how the 1993 demo was built, and the tricks its scenes share.
- [docs/scenes/](docs/scenes/): one page per scene, original versus new.
- [docs/visu-engine.md](docs/visu-engine.md): the original's 3D engine (used by Ships Fly-by and the 3D
  City): how it worked, its data formats, this project's version of it, and what was checked.
- [artwork/](artwork/README.md): every picture the original demo shows, exported to PNG (the app shows
  these).
- [docs/demo-timeline.md](docs/demo-timeline.md): when each part of the original demo starts and ends, worked
  out from its source and simulated against the real music, and how Play Demo follows it.
- [state.md](state.md): working notes: current status, decisions, and what is next.

## How faithful is the 1993 look?

It varies by scene, and each scene's page says exactly what was checked.

- **Dot Tunnel, Rings, Interference**: the original's data tables turned out to follow exact formulas. Those
  formulas were checked against the original data files with zero differences, and the result is compared
  pixel by pixel with what the graphics chip draws.
- **Plasma**: the same, except that 2 of one table's 8,192 values had to be set by hand, and the way the
  original laid two plasmas over each other was worked out by reading its source, not by running it.
- **Techno Bars, Bouncing Dots**: the original drawing code was ported step by step from the assembly.
  That port was checked by careful reading, not against a running copy of the original, so an
  off-by-one-pixel mistake is possible.
- **3D Sine Landscape, Plasma Cube, Glenz Vectors**: ported from the assembly too, but then checked against the
  original's own assembly text run instruction by instruction in a small interpreter (`tools/`). The
  pictures match exactly. The C code around the assembly was still ported by reading.

- **Ships Fly-by, 3D City and the 3D engine under them**: the engine was ported from the assembly and checked
  the same way, on 109 test pictures made from the original's models and animation. All match exactly, and
  the scenes' pictures agree with the 15 and 31 of them that are frames of their animations. The small scene
  programs around the engine were ported by reading.

Some scenes also differ from the original on purpose, so that each works as a standalone, looping scene:
for example there are no full-screen white flashes, and Interference loops seamlessly. Every such change is
listed on the scene's page.

## Credits and sources

*Second Reality* was made by **Future Crew** and first shown at Assembly '93, where it won the PC demo
competition. The scenes here were originally coded by:

- **Psi** (Sami Tammilehto)
- **Trug** (Mika Tuomi)
- **Wildfire** (Arto Vuori)

with graphics by Marvel and Pixel and music by Purple Motion and Skaven.

Future Crew released the demo's source code and data into the public domain in 2013, for its 20th
anniversary. Everything here was worked out from that release:

- Original source: <https://github.com/mtuomi/SecondReality>
- A complete, playable port in C++ (Windows, Linux, macOS, web):
  <https://github.com/XorJS/SecondRealityPlusPlus>, based on the Windows port by Gargaj / Conspiracy,
  <https://github.com/ConspiracyHu/SecondRealityW32>
- Fabien Sanglard's code review of the original: <https://fabiensanglard.net/second_reality/>

No code from the original or from those ports is included here. The scenes were re-implemented from the
original's logic, and tables the original shipped as data files are calculated instead.

The music is played with **libopenmpt** (<https://lib.openmpt.org/>), copyright the OpenMPT Project
Developers and Contributors and Olivier Lapicque, used under the BSD 3-clause licence: see
[ThirdParty/libopenmpt/LICENSE](ThirdParty/libopenmpt/LICENSE). It is the only outside library in the program.

The end scroller's text and font are the RELEASED demo's, taken unchanged from the data of the C++ port
**SecondReality++** (<https://github.com/XorJS/SecondRealityPlusPlus>, public domain under the
Unlicense), whose authors extracted them from the released demo; the source release has only an earlier
version. See [Data/EndScroller/README.md](Data/EndScroller/README.md). No code was taken from the port.
The end scroller's Modern look uses SuperClarendon, a typeface that comes with macOS (not included in
this project).

The xBR level 2 and Super-xBR picture scalers (`Sources/SRMetal/Core/PictureScaler.swift`) are written
for Metal from Hyllian's published shaders (libretro "slang-shaders", copyright 2011-2022 Hyllian),
used under the MIT licence: see [ThirdParty/xBR-LICENSE.txt](ThirdParty/xBR-LICENSE.txt).

## Licence

This project is released into the public domain under the [Unlicense](UNLICENSE), the same terms Future Crew
chose for the original. You may copy, change and use it for any purpose, with no conditions and no warranty.
The exception is `ThirdParty/libopenmpt`, which keeps its own BSD licence (its copyright notice must be kept
with any copy of the program).
