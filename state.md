# Project state

Last updated: 2026-11-25 (documentation audited against the program this day; trimmed this day: the full earlier notes are in `docs/dev-notes.md`)

## Goal
A native macOS app that re-creates Second Reality (Future Crew, 1993) from scratch, drawn on the graphics
chip with Metal: every part as a scene, and the whole demo with its music ("Play Demo"). Each scene has
two looks: Modern (full resolution, smooth) and 1993 (original pixels, usually 320x200; 70 steps per
second). The original source is public domain and lives in `../secondreality` for reference; the existing
complete C++ port is in `../SecondRealityPlusPlus`; the user's copy of the released demo is in
`../second-reality-original`.

## Status (2026-11-25)
- 23 scenes work in both looks and are in the sidebar in the demo's order: Ships Fly-by, Explosion, Title
  Picture, Glenz Vectors, Dot Tunnel, Rings, Interference, Techno Bars, Troll, Screen Switches Off,
  Mountain Scroller, Lens, Rotozoomer, Plasma, Plasma Cube, Bouncing Dots, Water Scroller, 3D Sine
  Landscape, Jelly Logo, 3D City, End Picture, End Scroller, and the Hidden Starfield (last; not in the demo).
- PLAY DEMO (Scene menu, P; Shift-P from the sidebar's scene; Escape stops) runs all 19 parts in the
  original order with the original music (libopenmpt), changing parts on the original's music cues. Every
  part is a real scene EXCEPT TWO: the opening credits (a title card) and the credits (21 still pictures).
- Self-test: 569 checks, all pass. `--demo-timeline`: every part starts on the step the research
  simulation gives. main is pushed to GitHub (private repository).
- The recent scenes (rotozoomer, lens, jelly logo, mountain scroller, water scroller) were each seen by
  the user in the running app and approved; for older ones see their notes. Nothing has been compared with
  the original program running.

## Next steps
1. OLDER SCENES IN PLAY DEMO (IN PROGRESS on branch `claude/older-scenes-timing-demo-23da19`; plan approved
   by the user 2026-11-25). Each scene follows the original part's waits inside Play Demo through
   `demoUpdate`; `DemoScript.steps` is NOT touched; standalone behaviour stays; one commit a scene with its
   check (`Scenes/<Name>/<Name>Checks.swift`) and docs; the user looks at each (`--from <scene>`) before the merge.
   - DONE: Techno Bars (right as it was: the original's section 3 never ran, its frame counter stood at
     2,697 against a limit of 2,520; docs corrected). Ships Fly-by (no pause, frames 0-520). Sine Landscape
     (black 24 steps until "music plus" >= 0, sinks while a pass reads -29...-1, sunk 18 steps before the cut). Plasma Cube (empty screen 312 steps until "music plus" >= 13 and on the cue
     step, then the original's frame n on the n-th step, fresh start without the 16-step lead-in, 1,998 frames). Plasma (WHITE 74 steps until "music plus" >= 0,
     the first palette fades DOWN from white in 127 refreshes, falls a refresh after music frame 723/1491/
     1875/2259, empty after the fourth; `fadepal`'s starting value is not in the source, taken as 63).
     3D City (lead-in over the jelly's last screen handed over by `DemoHandover`, window, cue on section 19,
     frame f at cue + 2f, 16 whitening steps with the palette written from colour 255).
   - NONE of these five has been seen by the user in the app yet (`--scene play-demo --from ships-flyby`,
     `plasma`, `plasma-cube`, `sine-landscape`).
   - TO DO, in this order, with what was found (steps are from the part's start, measured from the script):
     - Glenz: the title picture held 457 steps until "music plus" >= -19, then `zoomer2`'s 47-step wipe
       (bars of colour 255 close in from top and bottom, colours 0-127 fade to grey 30), the 177-step plate
       drop, the glenz at music frame 333 (so the original's pause was about 110 steps, NOT 156: the frame
       counter is reset before the wipe), black for the last 134 steps. READ 2026-11-25: the title picture uses only
       colours 0-79, so the WHOLE picture fades to grey (30 of 63) over the wipe's first 32 steps; the bars
       are BLACK (`BEG.C` sets colour 255 black); they stop at rows 260 and 274 of 400, leaving a grey strip
       until the screen is cleared on step 47. Told to the user; waiting for their OK before building.
   - Standalone lengths that differ from the original part on purpose and stay: Glenz 2,360 (35-step pause,
     loops), Plasma 2,323 (fades from black), Plasma Cube 2,048 (16-step lead-in), Sine Landscape 2,048 (own
     sink time), 3D City 3,639 (own fades), Ships 592 (70-step pause).
2. CREDITS (part 18, `CREDITS/MAIN.C`), after that: research and plan first. Today: 21 pictures as
   stills, 362 steps each. Font decision with the user (compare sheets as before; the credits font has 10
   shades). Known: the 21 pictures survive only as the artist's files, `pic02` is a "PART PIC MISSING"
   placeholder (the released demo may differ: check the port's data and the built `CRED.EXE`). The user's
   later idea: replace the miniature screenshots with ones from this project's own scenes (`--snapshot`).
3. OPENING CREDITS (part 1, `ALKU`): research and plan, font decision first. Today: a title card for 73 s.
4. Then polish, only when the user asks: the open questions below.

## Open questions (not to be started unasked)
- Code review findings left as they are: (3) a resumed part's name is lost if a new part starts on the
  first step; (5) the music-skip check runs only at 44.1 kHz, the player at 48; (6) a failed
  `SilentMusic.play` keeps the old song's details. All harmless today.
- Skip the black waits when Play Demo starts "from here"?
- Troll flash possibly one refresh late (rests on how VGA latches, not on the source alone).
- The jelly logo's white border (overscan) is left out.
- The water background could be re-rendered from the POV-Ray files in `WATER/` instead of scaled up.
- The repository's history holds ~168 MB of deleted AI pictures; shrinking it means rewriting history.
- Waiting on the user by eye: the 3D City's fades and evened-out camera roll; Ships Fly-by's pause.
- Undecided ideas in `docs/future-ideas.md` (a third "Reimagined" look).

## How to build and run
- `./build.sh` builds `build/SRMetal.app` (first builds libopenmpt, about 15 s the first time; run it once
  before a bare `swift build`). Needs only Apple's Command Line Tools, no Xcode. Shaders compile at start.
- TWO COPIES TRAP: each worktree builds its own app, and macOS may start another copy with the same
  identity. After merging into main, rebuild in the main folder. To be sure which copy starts:
  `open -n <full path to the .app> --args ...`.
- Start-up options after `--args`: `--scene <id>` (ids: `ships-flyby explosion title-picture glenz-vectors
  dot-tunnel rings interference techno-bars troll switch-off mountain-scroller lens rotozoomer plasma
  plasma-cube bouncing-dots water-scroller sine-landscape jelly-logo city-3d end-picture end-scroller
  starfield`, or `play-demo`), `--look classic|modern`, `--sidebar hidden`, `--from <scene id | part 1-21>`
  (with `play-demo`), `--music on|off`.
- Commands (run `build/SRMetal.app/Contents/MacOS/SRMetal` directly; none opens a window):
  - `--selftest`: all checks.
  - `--snapshot <scene-id|play-demo> <modern|classic> <step> <file.png> [blend]`: a 960x720 picture.
  - `--motion-check <scene-id> <modern|classic> [first last] [--csv file]`: draws every step (Modern also
    half-way), lists jumps and one-picture-only pixels, times the steps.
  - `--demo-timeline`: runs Play Demo's script against silently rendered music (0.2 s) and compares every
    part's start with `tools/demo_timeline.py`. `--demo-live <start> <seconds> [sound]`: the same with the
    real sound output (Claude cannot drive the app's window: launched from here it is not on screen).
  - `--scaler-compare <picture|file.png> <folder> [x y width] [--methods ...]`: labelled comparison sheets.
  - `--music-info [--write <folder>]`, `--music-render`, `--music-play`: the songs.
  - `--visu-test list|<case>|compare|damaged`: the 3D engine's test cases.

## Layout
- `Sources/SRMetal/Core/`: shared by all scenes. `DemoScene.swift` (the scene contract and `SceneCatalog`),
  `Renderer.swift` (clock, the two looks), `Shaders.swift`, `IndexedCanvas.swift` (a picture of colour
  numbers through a palette, as a VGA card: for 1993 looks replayed on the processor), `PictureLayer.swift`
  (`ScenePicture`, fades), `PictureScaler.swift` (Super-xBR 8x), `ScrollTables.swift` (the two scrollers'
  tables and smooth map), `Math3D.swift`, `SmoothTriangles.swift`, `DataFolder.swift`, `Visu/` (3D engine).
- `Sources/SRMetal/Scenes/<Name>/`: one folder per scene: model (the original's logic, no drawing), scene
  (drawing, both looks), and for the newer ones `<Name>Checks.swift`.
- `Sources/SRMetal/Demo/`: `DemoSequencer.swift` (`DemoScript.steps` = the running order, step for step
  `tools/demo_timeline.py`), `DemoRunScene.swift` (Play Demo as one scene), `DemoChecks.swift`.
- `Sources/SRMetal/Music/`: libopenmpt wrapper, player, `MusicPosition` ("music plus", sync table).
- `Sources/SRMetal/App/`: window, sidebar, commands, `SelfTest.swift` (per-scene generic checks),
  `CoreChecks.swift` (`run` calls every other check; the checks of the shared code and command line).
  The other checks live next to what they check, as extensions of `CoreChecks`:
  `Scenes/<Name>/<Name>Checks.swift`, `Demo/DemoChecks.swift`, `Music/MusicChecks.swift`,
  `Core/PictureChecks.swift` (split 2026-11-25; the self-test prints the same lines as before).
- `Data/`: original files loaded at run time, each folder with a README (what, why it ships, SHA-256):
  `Visu/` (3D models, animation), `Music/`, `EndScroller/`, `Lens/`, `Mountain/`, `Water/`.
- `artwork/original/`: every picture the demo shows, exported to PNG by `tools/art_export.py` (do not edit
  by hand); `rgb/` copies are what the app loads. Inventory: `artwork/README.md`.
- `tools/`: development-only Python (standard library only): one `<scene>_reference.py` per replayed
  scene, `demo_timeline.py` + `music_steps.c`, `art_export.py`, `x86interp.py` (cannot run self-modifying code).
- `ThirdParty/libopenmpt` (unmodified source, the only dependency), `docs/` (see the end of this file).

## Adding a scene
1. Research the original and SHOW THE USER A PLAN before code. Check the source release has the RELEASED
   version (the end scroller's did not): compare with the port's data and, where the built part is in
   `MAIN/DATA`, unpack it (`deark -m pklite`, installed with Homebrew) and look for the data inside.
2. Write `tools/<scene>_reference.py`: facts about the data, and a replay printing checksums at chosen steps.
3. `Sources/SRMetal/Scenes/<Name>/`: model, scene (`DemoScene`: `reset`, `tick`, `draw`,
   `classicReferenceFrame`, `demoUpdate` for music cues), `<Name>Checks.swift`; one line in `CoreChecks.run`.
4. One `SceneEntry` in `SceneCatalog.all` (in the demo's order) with `checkpoints` and a `thumbnailStep`.
5. In `DemoScript.steps`, show the scene; `--demo-timeline` must stay unchanged.
6. Data that cannot be calculated: `Data/<Name>/` with a README, copied by `build.sh`.
7. Docs: `docs/scenes/<name>.md` with pictures made by `--snapshot`, README (table, `--scene` list,
   artwork paragraph), `docs/demo-timeline.md`, and this file.
8. The user looks at it in the app; then merge into main, rebuild main's app, push when approved.

## Decisions in force
- Swift + Metal + SwiftUI, built with Swift Package Manager from the command line; Command-Line-Tools-only
  (do NOT use `@State`, `@Observable` or other macro-based features: the macro plug-in ships only with
  Xcode). Keep view state in `AppModel`.
- Licence: the Unlicense, matching the original. The GitHub repository is private for now.
- Scenes are re-implemented from the original source's logic, not copied from the port. The port has
  quiet differences (the water's fade length and red-first slip): never take a number from it unchecked.
- Every scene is stepped at 70 per second; the Modern look blends between steps. Every canvas is shown 4:3.
- 1993 look = exact, including the original's slips. Modern look may stray where it is better; record each
  straying on the scene's page.
- Calculate tables from the original's generator where that reproduces the file exactly; ship the file
  (with a README saying why) where it cannot be remade (lens table 4, the scrollers' position tables).
- Large binary original data is loaded from `Data/`, not written into Swift source.
- NO AI-UPSCALED ART (user, 2026-11-24). Modern pictures are the originals through Super-xBR 8x, made at
  run time; re-making pictures from source is welcome where possible.
- Text and lettering in the Modern look: decided per part with the user from comparison sheets. So far:
  end scroller in SuperClarendon (a real font fits it); mountain text and water sword through Super-xBR
  (they are pictures, not fonts). The end scroller uses the RELEASED text and font, from the port's data.
- Music: the ORIGINAL tracker songs played live with libopenmpt (their pattern data is scrambled;
  unscrambled at load). Song 1 always at tempo 120. Music plays only with Play Demo; sidebar scenes are
  silent and loop; the Music menu has only Mute (the song keeps running underneath). Sound follows the look.
- Fewer dependencies is better: libopenmpt is the only one (static, built from source by `build.sh`).

## Working rules learned (each one cost a mistake once)
- STEP PAIRING: what the program set up before its n-th wait for the screen shows on step n - 1. Work it
  out from each part's own source; do not assume it equals another part's.
- A scene on its own has no music: NO stand-in pause where the demo waits for a cue, unless the original
  really shows one (the jelly logo's invented half-second pause was noticed and removed; the water's 7.4 s
  still picture is real and kept).
- MEASURE standalone lengths from the script's silent run; do not estimate (two first guesses were wrong).
  The scene's Play Demo check must use the SCRIPT's numbers, not the model's own constants.
- Every new check is proven to fail with the detail broken on purpose, then restored.
- A scene shown by Play Demo gets one extra `demoUpdate` with `justShown` (the script tests its first cue
  on the show step; the lens needed it).
- Jump the music by rendering and throwing away (`TrackerSong.skip`), never by libopenmpt's seek-by-seconds
  (it lands on a row start and counts song 1's later sections from the wrong place).
- Scratch scripts and their output stay OUT of the repository (use the session's scratch folder;
  comparison sheets for the user go in `build/scaler-compare/`, which git ignores).
- `docs/images/window.png` is a capture of the app's window only, never the desktop.
- `build.sh` clears Finder tags and retries the signing (the Documents folder is synced and re-tags the app).
- Sessions: plan first for anything bigger than a small change; commit after each working change; ask
  before pushing; rebuild main's app after a merge.

## Where the detail is
- `docs/dev-notes.md`: the full notes that used to be here (1,400 lines, frozen): per scene and per
  feature, what was found, decided, verified and not verified. Sections worth knowing: "Decisions" (the
  music findings), "PLAY DEMO notes" / "FROM HERE" / "plug-in work", the three code reviews, "Artwork
  notes" (format traps, what is unverified about the credits pictures), "VISU engine notes", and one
  section per scene. Read the section for what you are working on, not the whole file.
- `docs/scenes/<name>.md`: one page per scene: how the original did it, how this version does, checks,
  differences. `docs/how-it-works.md`, `docs/original-demo.md`, `docs/demo-timeline.md` (every part's
  start, end and cue with its source lines), `docs/visu-engine.md`, `docs/future-ideas.md`.
- `README.md`: for a reader of the repository.
