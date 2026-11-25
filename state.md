# Project state

Last updated: 2026-11-24

## Goal
A native macOS app that re-creates scenes from Second Reality (Future Crew, 1993) from scratch,
drawn on the graphics chip with Metal. Each scene has two looks: Modern (full resolution, smooth)
and 1993 (original pixels, usually 320x200; 70 steps per second). The original source is public domain and lives in
`../secondreality` for reference; the existing complete port is in `../SecondRealityPlusPlus`.

## Status
- ALL TWELVE PLANNED SCENES ARE DONE (2026-11-14). Twelve scenes work in both looks: Dot Tunnel, Rings,
  Interference, Techno Bars, Bouncing Dots, Plasma, Hidden Starfield, 3D Sine Landscape, Plasma Cube, Glenz
  Vectors, Ships Fly-by and 3D City (the last five added 2026-11-14). (Plasma and Hidden Starfield were built in parallel by two sessions, the starfield in its
  own worktree, and merged on 2026-11-14.) (Rings and Interference were one
  back-to-back sequence in the original; split into two scenes at the user's request, 2026-11-14.)
- The scene framework has now carried a second, different kind of scene (full-canvas shader) without changes
  to its design; only small additions (shared sine table, shared full-canvas vertex shader, generic self-test).
- Documentation is in `README.md` and `docs/` (how the app works, how the original demo was built, and one
  page per scene comparing the original with this version). Keep it up to date: every new scene gets a page.
- Scene chooser built (2026-11-14): a sidebar lists every scene with a small picture, title and original
  coder; the toolbar has a Modern / 1993 switch and a restart button. Keys: L look, R restart, right/down
  next scene, left/up previous. Fullscreen hides the sidebar and toolbar. The "Scene" menu has the same actions.
  The user tried it by hand and reported it "working perfectly" (2026-11-14); which interactions they tried
  was not itemised. Seen in window captures: sidebar open and hidden, both looks, row highlight, pictures,
  4:3 letterbox, window title.
- The original's shared 3D engine ("VISU") is built and verified (2026-11-14): `Core/Visu/`, original data
  in `Data/Visu/`, `tools/visu_reference.py`, and `docs/visu-engine.md`. Ships Fly-by and the 3D City are
  built on it (2026-11-14, see their notes below); what the two scenes share is `Core/Visu/VisuPlayback.swift`.
- Music groundwork (2026-11-24): libopenmpt 0.8.10 is in `ThirdParty/libopenmpt` (unmodified source),
  built by `build.sh` as a static library and linked into the program; the two original songs are in
  `Data/Music` (scrambled, as shipped) and unscrambled at load. `--music-info` describes them.
  MUSIC PLAYER (2026-11-24): a "Music" menu plays either song (whole song, all sub-songs) or stops
  (Command-.); the sound follows the look (1993 = no interpolation). See "MUSIC" under Decisions.
- PLAY DEMO SKELETON (2026-11-24): Scene menu "Play Demo" (P; Escape stops) runs all 19 parts in the
  original order with the original music, changing parts on the original's music cues. Stand-ins: the
  11 built scenes (cut at the part's end), the original artwork pictures (smoothly stretched in
  Modern, hard-edged in 1993), title cards for the rest. See "PLAY DEMO notes" below and `docs/demo-timeline.md`.
- ARTWORK: every picture the released demo shows is exported to PNG in `artwork/original/` (see
  "Artwork notes"). DECIDED (user, 2026-11-24): NO AI-UPSCALED ART. The Modern look will scale the
  original pictures with a pixel-art scaler shader (xBR / ScaleFX family, written from the published
  algorithm) and re-make pictures from source where possible (water re-render from its POV-Ray files,
  credits pictures from finished scenes). The 30 AI pictures (`artwork/modern/`), the Photoshop
  workflow (`artwork/to-upscale/`, git-ignored copies) and `tools/art_check.py` were deleted the same
  day, at the user's request. They remain in git history and in GitHub's LFS storage (~168 MB).

## How to build and run
- `./build.sh` builds `build/SRMetal.app`.
- `open build/SRMetal.app` runs it. Start-up options go after `--args`: `--look classic|modern`,
  `--scene dot-tunnel|rings|interference|techno-bars|troll|switch-off|bouncing-dots|plasma|starfield|sine-landscape|plasma-cube|glenz-vectors|ships-flyby|explosion|title-picture|city-3d|end-picture`, `--sidebar hidden`.
- `build/SRMetal.app/Contents/MacOS/SRMetal --selftest` runs the checks without opening a window.
- `--scene play-demo` starts the app in Play Demo. `--demo-timeline` runs Play Demo's script against
  silently rendered music (0.2 s) and compares every part's start with `tools/demo_timeline.py`.
  `--snapshot play-demo <look> <step> <file>` pictures any moment of it.
- `build/SRMetal.app/Contents/MacOS/SRMetal --music-info [--write <folder>]` loads both songs into libopenmpt
  and describes them (and saves them unscrambled as standard S3M files).
- `--music-render <1|2> <seconds> <file.wav> [modern|classic]` saves the start of a song as a WAV file;
  `--music-play <1|2> <seconds> [modern|classic]` plays it through the speakers and reports how far the
  sound output got (proof the audio thread pulled music).
- `build.sh` first builds libopenmpt (copy in `build/libopenmpt/src`, log `build/libopenmpt/make.log`;
  about 15 s the first time). Run it once before a bare `swift build`, which needs the library.
- `build/SRMetal.app/Contents/MacOS/SRMetal --snapshot <scene-id> <modern|classic> <step> <file.png> [blend]` saves a
  960x720 picture without opening a window. `blend` (0...1, optional, modern look) draws that far on towards
  the next step, for checking motion (added with Ships Fly-by). The pictures in `docs/images/` were made this way (steps:
  dot-tunnel 500, rings 300, interference 700, techno-bars 310, bouncing-dots 1300, plasma 1000,
  starfield 1700, sine-landscape 700, plasma-cube 416, glenz-vectors 1300 and, for the squash picture, 365;
  ships-flyby 350, and 170 and 345 for its "bigship" and "near" pictures; city-3d 1600, and 660 and 3400
  for its "trees" and "logo" pictures).
- `build/SRMetal.app/Contents/MacOS/SRMetal --motion-check <scene-id> <modern|classic> [first last] [--csv file]`
  checks MOTION by program (added with the 3D City): draws every step of the loop (modern look also
  half-way between steps), compares neighbouring pictures, lists jumps and one-picture-only pixels, and
  times the scene's steps. The city's whole loop takes about 8 seconds.
- `build/SRMetal.app/Contents/MacOS/SRMetal --visu-test list` names the 3D engine's 124 test cases;
  `--visu-test <case> <modern|classic> <file.png> [blend]` saves a 960x720 picture of one;
  `--visu-test compare` prints how far the modern look is from the 1993 one for each case;
  `--visu-test damaged` feeds the loader deliberately damaged data files (none may crash it).
- `./build.sh` also copies `Data/Visu/` (original 3D models and animation) into the app's `Resources/Visu/`.
- Needs only Apple's Command Line Tools (no Xcode). Shaders are compiled when the app starts.

## Layout
- `Sources/SRMetal/Core/` shared by all scenes: `DemoScene.swift` (the scene contract and the scene list),
  `Renderer.swift` (clock and the two looks), `Shaders.swift`, `Math3D.swift` (3D helpers, see Plasma Cube notes),
  `SmoothTriangles.swift` (smooth-edged flat triangles, see Glenz Vectors notes).
- `Core/IndexedCanvas.swift` shows a picture of colour numbers through a palette, as a VGA card did. Use it for
  the classic look of scenes best re-created by replaying the original steps on the processor.
- `Sources/SRMetal/Scenes/<Name>/` one folder per scene.
- `Core/Visu/` the original's 3D engine for the ships and city scenes (see "VISU engine notes").
- `Data/Visu/` original data files the 3D engine loads (52 files, 257 KB; has its own README).
- `tools/` development-only scripts (not part of the app): `landscape_reference.py`, `plasmacube_reference.py`,
  `glenz_reference.py`, `visu_reference.py`, and `x86interp.py`, the small x86 interpreter the last three share
  (moved out of the plasma cube tool unchanged on 2026-11-14; both older tools print the same as before).
- `Sources/SRMetal/App/` window, sidebar and toolbar (`SRMetalApp.swift`), sidebar pictures
  (`Thumbnails.swift`), picture rendering (`Snapshot.swift`), self-test (`SelfTest.swift`; the checks of the
  shared code and command line are in `CoreChecks.swift`).

## Adding a scene
1. Create `Sources/SRMetal/Scenes/<Name>/` with a class that conforms to `DemoScene` (`reset`, `tick`, `draw`).
2. Add one `SceneEntry` to `SceneCatalog.all` in `Core/DemoScene.swift`, including a `thumbnailStep`: the
   step drawn for the scene's small picture in the sidebar (the docs-picture step is a good choice).
3. Write `docs/scenes/<name>.md`, add the scene to the tables in `README.md`, and make its two pictures with
   `--snapshot`.
4. Implement `classicReferenceFrame()` (the 1993 picture worked out on the processor) and list some
   `checkpoints` in the entry. The self-test then compares the graphics chip against it automatically.

## Decisions
- Swift + Metal + SwiftUI, built with Swift Package Manager from the command line.
- Licence: the Unlicense (public domain), matching the original (user, 2026-11-14).
- The GitHub repository is private for now; the user has not yet decided whether to make it public.
- Scenes are re-implemented from the original source's logic, not copied from the existing port.
- Every scene is stepped at 70 per second; the Modern look blends between steps.
- Every canvas is shown at 4:3, like a VGA monitor (320x200 pixels were not square).
- Straying from the original is acceptable where it makes a better standalone scene (user, 2026-11-14):
  e.g. no white-out in Rings, seamless loop in Interference. Record each such change in the scene's notes.
- Tables the original loaded from data files are calculated from the original's generator formulas where
  those reproduce the files exactly (true for the tunnel: verified against TUNNEL.DAT and SINIT.DAT).
- Scene picker (built 2026-11-14, user-approved design): a standard Mac sidebar listing scenes, hidden in
  fullscreen, plus the existing menu and keyboard shortcuts. Sidebar pictures are drawn by the app at
  start-up on a background thread (no picture files shipped).
- Single-key shortcuts (L, R, arrows) are caught by the app before the window sees them, so a focused
  sidebar list cannot swallow them. Up/down mean previous/next scene, like left/right.
- Do not use SwiftUI's `@State` (or other macro-based features such as `@Observable`): the macro plug-in
  ships only with full Xcode and the build fails with Command Line Tools. Keep view state in `AppModel`.
  Xcode 27.2 is installed on this Mac (not the active toolchain) and does build the project, but the user
  chose to keep the project Command-Line-Tools-only (2026-11-14).
- MUSIC (user, 2026-11-24; not started): the full-demo goal will play the ORIGINAL tracker songs live
  (`MAIN/MUSIC0.S3M`, `MUSIC1.S3M`) with libopenmpt, not pre-rendered audio, because its live music
  position (order/row) is what the original parts synchronised on. libopenmpt is built by this project
  from its source with every optional format off (S3M needs none of them), as a STATIC library linked
  into the program: no Homebrew copy, no separate library file in the app. This is the project's first
  dependency; it is BSD-licensed (keep its licence file; credit it in the README).
  FINDINGS (2026-11-24, read-only so far):
  - The songs' PATTERN DATA IS SCRAMBLED: each byte of a pattern is XOR-ed with (i) ^ (4*i), i = the
    byte's offset from the start of the pattern block (its 2-byte length included). Unscrambled, all
    154 patterns of MUSIC0/MUSIC1.S3M parse to exactly 64 rows, effects ABCDEFGHJKOQS. libopenmpt cannot
    play the files as they are: unscramble before handing them over (a few lines, at load time).
  - No Zxx sync markers in the songs. The parts synchronised on: the current order and row
    (`dis_muscode`/`dis_musrow`, STMIK's `_np_ord`/`_np_row`); `dis_musplus`, a count around the "+++"
    separators (254) in the order list (-32 when none is near; rows-64 before one, row after one; see
    DIS/DISINT.ASM muscode_6 and the C++ port's st3play GetPlusFlags); and `dis_sync`, a hard-coded
    order/row table (the port's music.cpp `syncdata`). libopenmpt reports order, row and the order
    list, so all of these can be computed.
  - The C++ port plays the music with st3play (8bitbubsy's port of Scream Tracker 3.21's replayer,
    modified to unscramble), not libopenmpt. Our choice stays libopenmpt (user's decision).
  - Licence: the source release's UNLICENSE covers the whole repository, music files included; there
    is no separate statement about the music.
  - libopenmpt: newest release 0.8.10 (2026-11-01), "makefile" source package 1.7 MB.
  DONE (2026-11-24): steps 1-2 of the plan. libopenmpt 0.8.10 source committed unchanged in
  `ThirdParty/libopenmpt` (SHA-256 and update steps in `ThirdParty/README.md`); `build.sh` builds it with
  its own Makefile (CONFIG=macos, STATIC_LIB=1, every NO_* switch on) in `build/libopenmpt/src`;
  `Package.swift` has a system-library target `COpenMPT` (modulemap links "openmpt" and "c++") and a
  `-L` to that folder. `otool -L` on the program lists no libopenmpt: it is inside. Program 3 MB.
  Code: `Music/MusicData.swift` (finds files, unscrambles, checks 64 rows), `Music/TrackerSong.swift`
  (wraps the C interface), `App/MusicInfoCommand.swift`. 7 self-test checks in `CoreChecks.music`
  (260 checks in all). Correction to the rule above: a pattern block's length word COUNTS ITS OWN 2
  BYTES, so bytes 2..<length are unscrambled. libopenmpt reports the markers as 0xFFFE (+++) and 0xFFFF
  (---), drops trailing "---", and reports 78 / 99 orders and 5 / 1 sub-songs.
  Cross-check: the user's downloaded unscrambled copies (`downloaded-unscrambled-s3ms/`, NOT committed,
  the user's folder): 2ND_SKAV.S3M = our unscrambled MUSIC0 except 49 order-list bytes (their "+++"
  removed and "---" turned into pattern 31); 2ND_PM.S3M is a different (1997) version of MUSIC1.
  DONE (step 3, 2026-11-24): `Music/MusicPlayer.swift`: AVAudioEngine + an AVAudioSourceNode whose
  render block pulls `TrackerSong.render(left:right:)` at the output's own sample rate. The audio thread
  only TRIES the lock (`OSAllocatedUnfairLock.withLockIfAvailableUnchecked`) and plays silence if the
  menu is swapping songs; songs are made and freed on the main thread. End of song -> main thread, once,
  and only stops if that song is still loaded. Sound follows the look: `TrackerSong.setSound` sets the
  interpolation filter length (1 = none for 1993, 0 = default). `playWholeSong` selects sub-song -1
  (MUSIC0 whole: 578 s; first sub-song 119 s). Menu in `SRMetalApp` ("Music"); `AppModel.look` didSet
  forwards the look. 2 more self-test checks (262). `--music-play 1 3` reached exactly 3.00 s.
  NOT verified by Claude: how it sounds (the user listens), switching the look while playing by ear,
  and the menu in the running app (only that the app still starts).
  DONE (2026-11-24): step 4, the music position as the clock, with the Play Demo sequencer (see
  "PLAY DEMO notes"). Song 1 now ALWAYS loads at tempo 120 (the Music menu too: as the demo played it);
  `TrackerSong(song, asInDemo: false)` gives the file's 125.
  Seen while building, not investigated: two linker warnings that search paths inside the Command
  Line Tools folder do not exist; harmless (the build works).
- Original data is loaded from files, not Swift source, when it is large and binary (decided for the 3D
  engine, 2026-11-14): kept in `Data/`, copied into the app by `build.sh`, found at run time by
  `VisuData`. Still no new build tools or dependencies.
- Scenes may implement `prepare(commands:frame:)` (empty by default) to draw into a picture of their own
  before the main pass. Added for the 3D engine's depth buffer, so the main pass and the other scenes'
  pipelines did not have to change.
- `docs/images/window.png` is a capture of the app's window only (`screencapture -l <window id>`), never
  the desktop.

## PLAY DEMO notes (2026-11-24)
- Asked for by the parent session (full-demo skeleton); plan approved by the user before coding.
- Music read-out: after each block the audio thread writes section/row into a SECOND lock it only tries
  (`MusicPlayer.reached`; always taken inside `shared`, never the other way round). `play()` resets it
  inside `shared`, so no block of an old song can report after a switch. `Music/MusicPosition.swift`
  has "music plus" and the sync table (same rules as the Python tool). `play(_:look:fromOrder:)`.
- `Demo/DemoSequencer.swift`: `DemoScript.steps` = `tools/demo_timeline.py` step for step (part,
  show, playSong, frames, until with optional cap, reset frame counter, note section, hold).
  `DemoSequencer.tick()` runs the no-time steps, then spends the step waiting. Music comes through
  `DemoMusicSource`: `LiveDemoMusic` (the player) or `SilentMusic` (renders 630 samples at 44,100 Hz per
  step, like `tools/music_steps.c`). Result: all 21 part starts equal the Python's to the step.
- `Demo/DemoRunScene.swift`: Play Demo is one `DemoScene` to the window. New protocol member
  `currentCanvasSize` (default nil) lets it change canvas as parts change; Renderer and Snapshot use it.
  High-resolution pictures: only current + next kept, next loaded in the background (MTKTextureLoader).
  Title cards drawn with Core Text. `build.sh` copies `artwork/original/rgb` into the app
  (`Resources/Artwork/`; app 5 MB). (At first it also carried the AI pictures, 165 MB, removed.)
- AppModel: `playingDemo`; the demo's SceneEntry is not in `SceneCatalog.all` (not in the sidebar, not
  in the per-scene self-tests). Choosing a scene, Escape or Stop Demo ends it and stops the music; the
  Music menu replaces the demo's song and leaves the demo. Window title shows the part. Each part
  change is logged (NSLog) with the music position.
- Seen by Claude: snapshots of the title card, title picture, troll (1993), plasma, credits picture 1
  (both looks). LIVE RUN (2026-11-24, `--scene play-demo`, window open, music through the speakers):
  all 21 parts started, each 0.2-0.3 s after the simulation's time (the sound output's start-up delay;
  the music cues keep it from growing); credits ended 10:52.7 vs 10:52.4; no errors logged; song
  switches landed on song 2 section 0 and song 1 section 18. NOT verified by Claude: how it looks and
  sounds to a viewer, fullscreen, switching look mid-demo, Escape/P/menu by hand.
- Not done / ideas: the Music menu's check mark does not show during Play Demo; a "start from part N"
  option (needs the music jumped to the right place); the end scroller is only a card.

## PLAY DEMO plug-in work (2026-11-24, plan approved by the user)
- Plan: (1) scenes can see the music inside Play Demo, proven on Techno Bars' flash; (2) a shared
  picture-and-fade toolkit; (3) the explosion as a real scene (frames made 8x on the fly, the next one
  prepared ahead, fade laid on after scaling, original 17.5 frames a second; also in the sidebar).
- STEP 1 DONE: `DemoScene.demoUpdate(_ context: DemoContext)` (default empty; only Play Demo calls it,
  before each tick): music state, steps since the part started, steps since the scene appeared.
  Techno Bars sets `TechnoBarsModel.musicRow` from it (nil standalone = the old estimate). 2 self-test
  checks (274): the flash follows the rows given; a silent Play Demo run gives Techno Bars the music's
  row on all 1,260 of its steps (on the step it appears, it has not been told yet: by design, as a
  new scene is seen at its first step). Part-change log lines now only in the running app.
- STEP 2 DONE: `Core/PictureLayer.swift`: `ScenePicture` (original + Super-xBR 8x on first use,
  `prepareUpscaled()` to make it ahead) and `PictureLayer` (draws over the canvas with `PictureFade`:
  1993 look = the original's whole-number rule, Modern = smooth, laid on after scaling). Play Demo's
  pictures now go through it (only the picture showing is kept). 1 self-test check (275): 1993 fades
  to white and black match the rule on 60 pixels (proven to fail, 46 of 60, with rounding instead).
- STEP 3 DONE: `Scenes/Explosion/` (sidebar, after Ships Fly-by): `ExplosionModel` (OUTTAA.C's timing
  and `wfade` table: 45 rounds x 4 steps = 180, then loops) and `ExplosionScene` (frames via
  `ScenePicture`, 1993 fade exact; Modern: 8x per frame, the next prepared on a background thread,
  only two kept, smooth fade on top). `build.sh` copies `artwork/original/rgb/explosion` (456 KB).
  17 new self-test checks (292): all 15 checkpoints match the rule pixel for pixel. Play Demo: the
  Ships horizon during the wait for sync 10, then the explosion; all part starts unchanged.
  `docs/scenes/explosion.md` with its two pictures. NOT seen by the user in the app yet.
  TITLE AND END PICTURES DONE (2026-11-24; the user said to keep going in the suggested order):
  `PictureFade` generalised to "keep k of n parts" (64ths and 128ths, to white or black; explosion
  unchanged); `ScenePicture.pixels` shared. `Scenes/FadingPicture/`: `FadingPictureModel` (white,
  fade-in 129 steps in 128ths, then for the end picture a hold until music plus > -16 via demoUpdate
  (375 steps alone), fade to black in 64ths) and `FadingPictureScene`, set up as "title-picture"
  (BEG.C, 32 white) and "end-picture" (END.C, 34 white). Neither picture uses colour 255 (left out of
  the original fades; checked). 28 new self-test checks (320). Play Demo shows both scenes; all part
  starts unchanged. `docs/scenes/title-and-end-pictures.md`. Credit "Future Crew": who drew the two
  pictures is not recorded in our docs.
  TROLL AND SWITCH-OFF DONE (2026-11-24, user: "push and continue"): `PictureLayer` gained a sideways
  offset and a brighten amount (`PictureFade.add`). `Scenes/Troll/` (`TrollModel`: KOE.C's xpos/xposa
  scroll, ripple shake with the shared sine table, palfade flash one refresh after its shake value;
  music cue section 35 row 48 via demoUpdate; 35-step wait and 300-step hold alone) and
  `Scenes/SwitchOff/` (`SwitchOffModel`: per refresh a 400-entry row map, white fade, colour 0 level,
  wiped line ranges, dot level, worked out from SHUTDOWN.C's register tricks; own shader; colour 0 =
  the troll's only pure black, kept black; colour 1 = white; 70-step lead-in alone, none in the demo).
  Modern switch-off: explicit gradients + anisotropic sampler (without them the band edges showed
  grey lines across the screen). 39 new self-test checks (361), incl. scroll 53 + shake 50 (matches
  the timing research) and the band list. Play Demo uses both; part starts unchanged.
  NEXT (suggested order): the end scroller (fonts decision first), then the rotozoomer.

## Code review of core and app (2026-11-14)
- Reviewed: `Core/` (not `Core/Visu/`), `App/` (not `VisuTestCommand.swift`), `build.sh`, `Package.swift`.
  Full account, with how each finding was proven: `docs/how-it-works.md`, "Code review of the core and the app".
- Fixed (8): clock fraction could be exactly 1; `IndexedCanvas` showed stale colours beyond a short palette;
  `--snapshot` / `--motion-check` crashed on a negative step; `--motion-check` ignored a malformed range and
  exited 0 on a failed `--csv`; mistyped `--scene` / `--look` / `--sidebar` / unknown `--option` were ignored
  (now reported, exit code 2, no window); `--snapshot`'s 1993 look was up to one output pixel off from the
  window's; `build.sh` left a stale app after a failed compile; holding L strobed the look (reasoned only).
- No API that scenes call changed. New: `StepClock` (the clock's sums, in `Renderer.swift`), `StartupOptions`
  (in `SRMetalApp.swift`), `Snapshot.request(from:)`, `MotionCheck.stepRange(from:)`.
- Self-test: 235 checks (was 200; the 200 print exactly as before). Core and app checks are in
  `App/CoreChecks.swift` and run first. New checks of shared code go THERE, not among the scenes' checks.
  The self-test's last lines now give the number of checks run.
- `docs/images/` classic pictures were NOT remade after the `--snapshot` scaling fix (at most one pixel's
  difference at block edges). Remake them if exactness matters.
- For the user to try by hand (none of this can be done by program): hold L down (should switch once, not
  flicker); L, R and arrows with the sidebar list focused; fullscreen in and out with the sidebar shown and
  hidden beforehand; resize and drag between displays; sleep and wake with the app open; quit within a
  second of launch; relaunch and see what macOS restored; `open build/SRMetal.app --args --scene typo`
  (nothing should open: the message only shows when the program is run directly in a terminal).
- Proposals, not done: use the display's own timestamp for the clock; a `/simplify` pass over the
  duplicated picture-difference loops in `SelfTest.swift` and `MotionCheck.swift` and the per-scene
  shader recompiling; give `SceneEntry` a loop length so `--motion-check` need not guess where a loop ends.

## Artwork notes
- SUPERSEDED (2026-11-24): everything below about high-resolution versions, Photoshop, Git LFS and
  `art_check.py` is history: the user decided against AI-upscaled art (see Status, ARTWORK). Git LFS
  is still installed (`git lfs install` set the global git config) but the repository no longer uses it
  (`.gitattributes` removed). The exports in `artwork/original/` are unaffected and are what the app shows.
- Started 2026-11-24 at the user's request, instead of a new scene for now. A ranked list of possible
  new scenes was made the same day (best first: Rotozoomer, Lens, Jelly Logo; the unused Twister; the
  two scrollers; the explosion). The user has not picked one yet; every remaining part of the demo
  needs original pictures, so the "calculated and 3D only" scope would have to widen.
- `tools/art_export.py` (with `tools/artformats.py`, standard-library Python) reads `../secondreality`
  and writes `artwork/original/` (exact indexed PNGs), `original/4x3/` (pixels repeated 5x6 or 5x3 to
  the 1993 monitor shape) and `original/explosion/` (40 frames). `--check` re-decodes and compares
  pixel for pixel. `artwork/README.md` is the inventory: what each picture is and what an upscale
  must respect. `artwork/modern/README.md` gives the naming and shape rules for the user's versions.
- Decided: the exports live in this repository (user, 2026-11-24). The PNGs are made by the script;
  do not edit them by hand.
- Each picture is read from the copy BUILT INTO the demo (.OBK/.OBJ/.INC or the file the part loads)
  and cross-checked against the artist's Deluxe Paint file: all match, except the opening horizon's
  colours 1-3 (changed to the text's greys in the built copy; the PNG keeps the built colours). The
  Ships horizon and the Glenz plate agree with this project's scenes.
- Format traps found: the "FDFC" packer can run past a row's end (START/HZPIC.P); MIEKKA.SCI's header
  says 400x250 but holds 400x35; ALKU/FONA.INC has one stray byte in front; TEXTS.16 is 2 bit planes
  though its header says 16 colours; the credits font has 10 shades, the others 4; explosion frames
  are changes against the frame TWO back (two video pages), and every frame covers exactly 64000
  pixels, which is the decoding's check.
- Not verified: the 21 credits pictures (only the artist's files survive; `PIC02` is a "PART PIC
  MISSING" placeholder in the source, the released demo may differ); the explosion against its
  Autodesk Animator original (`PAM/PRAX4.FLI`); how tall the fonts' pixels were on screen (so fonts
  have no `4x3/` version); how much of the 640-wide setup screen shows at once.
- Ideas: the water background was ray-traced and POV-Ray scene files survive in `WATER/`, so it may be
  re-rendered at high resolution instead of upscaled (which file made it is unknown). The credits
  pictures are mostly miniature screenshots of each part and could be re-made from the scenes.
- Git LFS set up 2026-11-24 (user's request): `brew install git-lfs`, `git lfs install` (global git
  config), and `.gitattributes` sends image and paint files under `artwork/modern/` to LFS. The
  exports in `artwork/original/` stay ordinary files. Tested by staging a picture (stored as an LFS
  pointer). Nothing pushed through LFS yet. GitHub free: 10 GB storage, 10 GB downloads a month.
- Target size for the high-resolution pictures (advised 2026-11-24): 12 times the original width, in
  the 1993 shape: 3840x2880 for one-screen pictures, 7680x2880 for the 640-wide ones, 1920x1440 for
  the credits pictures and the explosion frames. The lens/rotozoomer picture may want more (decide
  when that scene is built). Upscale from the original-size PNGs, then correct the shape.
- `artwork/original/rgb/` (added 2026-11-24, user's request): full-colour copies of every export
  and explosion frame, 8-bit RGB with an sRGB chunk, as the starting files for Photoshop (it needs
  RGB). `--check` verifies them against the palettes.
- First high-resolution picture done 2026-11-24: `artwork/modern/04-title.png` (user, Photoshop
  Generative Upscale; upscale the original grid, then shrink to 3840x2880). Checked: 8-bit RGB,
  framing lines up with the original. Trap met: Photoshop's "Smaller File (8-bit)" export saved it
  with 256 colours the first time; check every new file is RGB (PNG colour type 2 or 6).
- `tools/art_check.py` (2026-11-24) checks pictures in `artwork/modern/`: name, full colour, no
  transparency in use, target size (2.4 x the `4x3/` version; explosion frames 1920x1440), framing
  (shrunk with `sips`, compared in 160-block grids; best fit must be unshifted). Proven on test files
  to catch a 256-colour save, a wrong size and a crop. Done so far: 04-title, 07-troll, 15-jelly-logo, 17-end-picture (all four
  320x400 pictures); 02-ships-horizon, 05-glenz-plate, 09-mountain-background, 10-lens-picture,
  13-water-background (the five 320x200 ones worth doing, by Batch, 2026-11-24).
  The 21 credits pictures (1920x1440, by Batch, 2026-11-24) are a STOPGAP: see the next step below.
  `art_check.py` fix found on them: framing is compared in blocks of at least 2 original pixels (at 1
  pixel per block the upscaler's half-pixel smoothing tipped the best fit by one block).
- Automating the 320x200 pictures in Photoshop (2026-11-24): `artwork/to-upscale/` (git-ignored) holds
  `320x200/` (full-colour copies of ships horizon, glenz plate, mountain background, lens picture, water
  background) and `done/` (the Batch output). Plan: a recorded Action (2 x Generative Upscale 4x, Image
  Size 3840x2880, Save a Copy PNG, close) run by File > Automate > Batch. Generative Upscale makes a NEW
  document with a changed name, so output names may need fixing; Claude checks, renames and moves the
  results into `artwork/modern/`. Not yet known: whether Generative Upscale records in an Action (Adobe
  does not say; a community answer says yes) and how many credits a batch uses.
  RESULT: it records and batches fine (user, 2026-11-24). Photoshop's default model was Topaz
  Gigapixel (a partner model). Output names gain " Topaz Gigapixel 4x scale" twice. The saved PNGs
  have an alpha channel with the top and bottom rows at 254 (invisible); `art_check.py` now treats
  250-254 as harmless and flags only real see-through pixels. A "Flatten Image" step before saving
  would avoid the channel.
- Ships Fly-by still looks for an optional replacement background `Data/Visu/U2ABG-modern.png` (none
  exists); without it the Modern look uses the original made 4x by Super-xBR (2026-11-24).
- A stray git worktree some session had made inside `../secondreality` (`.claude/worktrees/`, branch
  `claude/project-continuation-5bf400`, no changes or commits of its own) was removed at the user's
  request on 2026-11-24, with `git worktree remove` and `git branch -d`.

## Dot Tunnel notes
- Modern look keeps the original's projection (ring size shrinks with distance; ring offsets do not),
  so it moves the same way. It adds gliding between steps, round dots, and larger dots when nearer.
- Modern look does not blank the ring in slot 5 as the original palette did.
- The scene loops after 1060 steps (about 15 seconds), the original's length.
- Code review (2026-11-14), against TUNNELI/TUN10.PAS; see docs/scenes/dot-tunnel.md:
  - FIXED, 1993 look: it cleared and redrew every frame, showing every dot. The original never clears:
    each dot blanks the old pixel of the dot in its place in the drawing order just before it is drawn,
    and that often lands on a dot a further ring has just drawn. Roughly one dot in twenty is missing each
    frame (163-296 pixels' difference at steps 100-900). The classic look is now a processor replay of that
    loop (`DotTunnelModel.drawClassic`, shown through `IndexedCanvas`), no longer calculated in the shader.
    Every 1993 picture with dots changed; `docs/images/dot-tunnel-classic.png` was remade.
  - The old note here about "stale dots at the end" was wrong and is gone: the original leaves none (the
    one ring never erased, slot 4, is always off screen).
  - Verified against a Python re-run of TUN10.PAS reading the original TUNNEL.DAT / SINIT.DAT: same
    checksums at steps 60, 250, 500, 777, 900, 1000 (in the self-test). Same reviewer wrote both.
  - Modern look: no fault found; `--motion-check` shows no jumps, loop point included.
  - `docs/how-it-works.md` still lists Dot Tunnel under "calculate it on the graphics chip"; it now
    belongs under "replay it on the processor" (not edited by the review session, by its brief).
  - Tidy-ups left: modern look repeats the size/brightness formulas; literal 320/200/160/100.

## Rings and Interference notes
- Both scenes live in `Scenes/Interference/` and share one model, one shader and the ring pictures; a `part`
  value says which scene an instance is.
- Source: TECHNO/KOEB.ASM (Rings: teal rings fade in) and KOEA.ASM (Interference: two ring pictures interfering).
- Rings deliberately differs from the original: the original burned out to full white after fading in and
  ended after 256 steps. The user asked for the white removed (2026-11-14), so Rings fades in over 128 steps
  and then flows indefinitely. Its self-test reference follows this rule, not the original's white-out. The techno bars (KOE.C `doit1/2/3`) are the rest of that original program; not built yet.
- The two 640x400 ring pictures are calculated: ring number = floor(distance^1.4 / 16) for the 8-colour one,
  floor(distance / 12) & 1 for the 1-bit one. Both reproduce the original files exactly (checked by checksum
  in the self-test).
- The original's bit-plane copy with pre-shifted pictures reduces to: stripe pixel = picture(x + overx + wobble
  - 7, y + overy). Verified against a byte-level emulation of the assembly.
- Interference deliberately differs from the original so it loops seamlessly (user request, 2026-11-14):
  it runs 1024 steps (the original ran about 980 and cut away on a music cue), and the row wobble shrinks
  back to nothing over the last 240 steps. At 1024 steps both scroll paths, the wobble wave and the colour
  rotation are back at their start. The self-test checks this.
- The original started the colour rotation on a music beat; this version starts it immediately.
- Modern look: rings calculated per screen pixel with soft edges; colours, scrolling and the row wobble glide
  between steps. Ring shades stay as 8 distinct bands, as in the original.
- Circles are round in pixels, so on the 4:3 display they are slightly tall ovals, as on a real VGA monitor.
- Code review (2026-11-14), against TECHNO/KOEB.ASM and KOEA.ASM (+ KOE.C's wobble table); see
  docs/scenes/rings-and-interference.md. NO bugs found, no code changed. Frame-by-frame timing of the
  original's loop (which position, wave and palette are on screen in which frame) matches the model;
  `--motion-check` shows no jumps in either look, loop points included. Not reproduced, on purpose: the
  original's very first frame (window at the picture's top-left corner for one frame). Tidy-ups left:
  formulas written twice (whole numbers / decimals), wobble list rebuilt every draw, `Phase` duplicates
  `part`, `SceneError` lives in `InterferenceScene.swift` though other scenes use it.

## Techno Bars notes
- Source: TECHNO/KOE.C `doit1` (420 steps), `doit2` (840), `doit3` (up to 980, sliding off right near the end),
  plus KOEA.ASM `asmbox`/`drawline`/`blit16` and POLYCLIP.ASM. The scene loops after the slide-off.
- How the original made trails: each frame's bars are a 1-bit picture written into ONE of the 4 bit planes of
  one of 8 video pages (4 pages in `doit3`), then that page is shown. The other planes still hold the frames
  from 8/16/24 steps earlier (4/8/12 in `doit3`). The palette colours a pixel by how many planes are set.
- Classic look: `TechnoBarsModel` replays those steps on the processor (pages, planes, the XOR edge-fill
  rasteriser and the clipper ported step for step) and `IndexedCanvas` displays the result. So the self-test
  for this scene only proves the display path; the port of the rasteriser was checked by reading, plus one
  rectangle fill test. It has NOT been compared with a running original.
- Modern look: per screen pixel, the shader tests the current bars and three ghosts analytically and shades by
  the count, with soft edges, gliding between steps (one step of delay so there is always a next state).
- Beat flash: the original flashed on every 8th music row. Without music this is recreated from the song's
  header (speed 3, tempo 130: a flash about every 32 steps). Approximate, and not aligned to anything.
- Kept quirks: the bottom screen row is never drawn; `doit3`'s second frame puts the bars off-screen (one
  blank frame); section one's last frames linger as ghosts at the start of section two.
- Left out: the original's lead-in (white flash, then four columns dropping to black on four beats), stale
  video memory showing briefly at the start of `doit1`, and the picture that scrolls in after the slide-off.
- Code review (2026-11-14): the rasteriser and clipper were reviewed independently, line by line, against
  KOEA.ASM / POLYCLIP.ASM and found to match. Four other problems were fixed (see docs/scenes/techno-bars.md):
  - Modern look: it whirled at the section 1->2 cut. Each section's first step is now held still
    (`BarState.startsSection`).
  - Modern look: it showed a blank step when only one step was recorded.
  - Classic look: each page is now seen with the NEXT pass's flash and slide, as in the original. `tick()`
    ends by doing that next-pass work early.
  - New self-test checks: there is no glide across a section change (confirmed to fail without the fix),
    and the current bars are shown whenever the classic look shows bars.
- Review tidy-ups deliberately left for later (user's choice): the per-step 64 KB picture copy, the flash
  formula written twice (classic/modern), duplicated thickness and bounce code, and the screen-size
  constants written out in several places.

## Bouncing Dots notes
- Source: DOTS/MAIN.C and DOTS/ASM.ASM (`drawdots`). 512 dots; each step one dot (in a shuffled order) is
  re-dropped by a rule that changes through the scene: wandering figure (frames 1-499), ring (500-899),
  fountain (900-1699), random cloud with gravity fading out and the view spinning up (1700-2359).
- Classic look: `BouncingDotsModel` replays `drawdots` on the processor with the original's 16-bit arithmetic,
  erase-by-restoring-background, Microsoft C `rand()` (so the random cloud matches), and quirks: a dot off the
  side of the screen does not fall that step; the depth uses two separately truncated products; a leftover
  register value is stored as the old shadow position on the off-screen path. Shown through `IndexedCanvas`
  (which now takes palettes of up to 256 colours). As with Techno Bars, the port was checked by reading only.
- Modern look: smooth floor gradient, then every shadow and dot drawn as a soft round sprite, sorted far to
  near, bigger when nearer (the original's dots were all 4x3 pixels), gliding between steps except on the step
  a dot is re-dropped.
- Deliberate departures: the original ended with a flash to white and then a fade to black; this fades straight
  to black (frames 2360-2424) and loops, starting again with the original's 130-step floor fade-in. The
  original's uninitialised re-drop counter starts at 0 here. The unused "face" data is not used.
- Code review (2026-11-14), against DOTS/MAIN.C and ASM.ASM; see docs/scenes/bouncing-dots.md:
  - The port of `drawdots` and of MAIN.C's script was re-read instruction by instruction in a separate
    session and found to match. Still never compared with a running original. 1993 pictures unchanged.
  - FIXED, modern look: (1) on the first step with dots (131) all dots and shadows glided in from a
    placeholder at the top-left corner; (2) once gravity is off, a rising dot's 16-bit height wraps
    (-32768 -> +32767 and usually back), and the modern look glided it across the screen (e.g. dot 419,
    steps 2383-2384); (3) the smooth fade-in went below 0 for two steps and snapped back at step 130.
    `Projected.jumped` now also covers (1) and (2).
  - New self-test checks: no glide longer than 50 canvas pixels over a loop and a bit (normal maximum
    27; confirmed to fail without the fixes); the smooth fade stays in 0...64 without snapping.
  - Noted, not changed: dots the 1993 look hides (off the side, or shadow below the screen) are still
    drawn by the modern look, and do not fall while hidden.
  - Tidy-ups left: unused `floorGrey`; colour formulas written 2-3 times; per-draw 64 KB copy and
    palette rebuild; literal screen numbers.

## Plasma notes
- Source: PLZPART/PLZ.C, ASMYT.ASM (`plzline`, `setplzparas`), COPPER.ASM (`moveplz`, `pompota`, `do_drop`),
  TWEAK.ASM (`tw_opengraph2`). Flat plasma only; the cube is a later scene.
- Canvas is 320x400 (not 320x200; the starfield is the same): the original mode was 320x400 with 4 planes and 96 bytes
  per row. The framework needed no changes for this.
- The plasma is a 280-line band starting at screen line 61/62, placed with the VGA line-compare register.
- Per-pixel rule (from the self-modifying `plzline`): value = psini[8c + lsini16[y + p2 + 4(80-c)] + p1]
  + psini[2y + lsini4[y + p4 + 16c] + p3 + 4(80-c)], c = 0...83 (4 pixels each), y = 0...279.
- Two plasmas (K and L parameters) are interleaved as a one-pixel chessboard; the original flipped the
  chessboard every frame (line compare 60/61, 2-pixel pan on alternate frames) so the eye mixed them.
- Tables are calculated: psini, lsini16 and ptau reproduce the .INC files exactly when the original's
  11-digit pi is used; lsini4 needs two entries (3072, 7168) set by hand to 23. Checksums in the self-test.
- Deliberate departures: the 1993 look shows the average of the two alternating frames (70 Hz alternation
  flickers on a 60/120 Hz display); the opening fade from white is replaced by the same 31-step fade from
  black the other sections use; the final fall loops back to section 0 (2323 steps); drawing is treated as
  instant (the original's draw loop was not locked to the refresh).
- Code review 2026-11-14 (branch `claude/review-plasma-1872aa`), two fixes, each with a self-test check:
  (1) 1993 look: the 2-pixel pan was paired with the wrong line. The original picks line and pan together
  in the retrace routine but the pan is written to the card by `copper1` just before the NEXT retrace
  (order of calls is in MAIN/COPPER.ASM `copper_end`; routine numbers in DIS/DISINT.ASM), so line 60 shows
  with pan 0 and line 61 with pan 2. Flowing-plasma pictures change at pixel level; fall and fade pictures
  do not. (2) Modern look: the band hopped 0.34 line on the first step of each fall (counter goes 0 to 2);
  it now glides in.
- Settled by that review: the per-pixel formula (checked against the machine code in ASMYT.OBJ: the whole
  16-bit address in each instruction is overwritten); the plane/chessboard layout (second reading; the C++
  port agrees); the pan/line pairing. The real interrupt server IS in the source release (DIS/DISINT.ASM
  plus MAIN/COPPER.ASM); only DIS/DIS.ASM is the stub.
- Still not verified: the exact band line (rests on the VGA rule "split starts on the line after").
- OPEN, needs the user's decision: timetable "music frames" are probably music ticks (about 52 a second at
  the tune's starting tempo 130), not 1/70 s. The C++ port counts them per music tick. If so the original
  sections were about a third longer (scene about 43 s, not 32). Not proven (the player is a compiled
  library); nothing changed. See docs/scenes/plasma.md "What was not checked".
- `--motion-check plasma classic` reports big flicker during each fall and a jump at step 33: that is the
  original's behaviour (K and L are not mixed while falling or fading), not a fault.
- For the plasma cube later: the fifth palette (`pals[4]`, "white II") is built in PLZ.C but not in
  `PlasmaModel.palettes`; the tables and `PlasmaModel.value` should be reusable.

## Hidden Starfield notes
- Source: DDSTARS/STARS.ASM (live; its constants are in K.EXE) wrapped by KOE.ASM. POLYEGA.ASM and SIN1024.INC
  are included but unused; STARS.OK/STARS.PRE are older versions; DOIT1-3.C, KR.C, TEST/ are unrelated leftovers.
- Canvas is 320x400 (EGA mode 0Dh with line-doubling off), like Plasma, not 320x200. The classic
  texture, self-test and `--snapshot` coped without changes to `Core/`.
- How the original worked: 64 off-screen 320x100 pictures in a ring, one shown per step; each step the stars'
  dots are OR-ed into the current picture and pictures are never cleared, so a seamless 64-step film loop
  gets denser for ever. Bottom half of the screen = the picture 32 places round the ring, upside down.
  512 stars to step 900, nothing 901-1200, then 1024 stars each also drawn 17 pictures ahead.
- Classic look: `StarfieldModel` replays that on the processor (own random generator: Microsoft's constants
  but bits 32-47 of the product; integer perspective tables) and `IndexedCanvas` shows it. Since the
  2026-11-14 review it is checked against the original's own routines run in the x86 interpreter
  (`tools/starfield_reference.py <DDSTARS folder> <steps>`): whole screens match at 15 steps. The frame
  logic around those routines (step marks, picture ring, mirror, fade) is still from reading only, and
  nothing was compared with a running original.
- Code review 2026-11-14: one real bug fixed. Dots were placed with the star's depth from before the step;
  the original uses the depth after it (`movzx bx,[si]` / `sub bl,2`). All 1993 pictures changed slightly and
  the self-test checksums were replaced with the original's. The earlier Python "independent re-run" shared
  the misreading. Modern look in motion: no jumps found over the whole loop. Minor items left alone are
  listed in docs/scenes/starfield.md.
- Modern look: the model also records each star's "flight"; the shader works out which dots of each flight are
  in the picture now showing and draws soft round stars, bigger and brighter when nearer, gliding between steps.
- Deliberate departures: the two text panels (a picture) are left out; the original never ended, this stops
  adding stars at step 1984, fades out over the last 33 of 2048 steps and loops from black.
- Docs picture step: starfield 1700.

## 3D Sine Landscape notes
- Source: COMAN/MAIN.C, ASM.ASM (`docol`, `docopy`), THELOOP.INC (the inner loop, written out by DOLOOP.C as
  128 unrolled steps). Built as 3DSINFLD.EXE. MAIN1.C, ASM1.ASM, DOLOOP1/2.C, DOLOOP.OK are older versions.
- It is a Comanche-style column renderer: height = wave1[x] + wave2[y] (two 32768-entry lists), 160 columns
  each 2 pixels wide on a 320x200 canvas, 128 ray steps per column (64 single, 64 double).
- NO background picture: COMBG.* is not linked (`_COMBG.OBK`), MAIN.C has a 16-byte stand-in, and the code
  that would show it is inside `IFDEF PXLSUX`, never set. The picture is only test stripes anyway. Sky = black.
- Tables calculated and identical to the files: WAVE.H (KOE.C's formula), W1DTA.BIN (needs Microsoft C
  `rand()` from seed 1), W2DTA.BIN, and the per-step constants. One catch: the shipped DOLOOP.C says
  `120-j/8` for the colour offset but the built THELOOP.INC/OBJ and C.EXE have `140-j/8`; 140 is used.
- Classic look: `SineLandscapeModel` replays the loop on the processor (the original's "flipped" 16.16
  numbers, carries and partial buffer clearing), shown through `IndexedCanvas`. Verified against
  `tools/landscape_reference.py`, which runs THELOOP.INC's assembly text in a small x86 interpreter:
  identical pictures at steps 100, 200, 700, 1300, 1978, 2046. MAIN.C/docol/docopy were ported by reading.
- Modern look: one ray per display pixel in the fragment shader (same 128 steps, then 7 halvings to the
  exact hit), smooth height tables without the random roughness, palette formula evaluated directly,
  camera gliding between steps.
- Speed: the original moved the camera once per drawn picture, so its speed depended on the PC. One move
  per step was first tried and the user found it significantly too fast (2026-11-14). Now one picture every
  `SineLandscapeModel.ticksPerPicture` = 2 steps (the rise/fall still moves one line per step, as in the
  original). Measured against the user's YouTube clip (youtu.be/iw17c70uJes, landscape at 441-467 s): clip frames at
  446/452/458/464 s match reference pictures 223/433/643/854, i.e. exactly 35 pictures a second, so 2 is
  right for that recording. If the number ever changes, change `EVERY` in `tools/landscape_reference.py` too, re-run it, and update the self-test sums.
- Deliberate departures: the land sinks fully out of sight and the scene loops from black after 2048 steps (the
  original sank on a music cue; in the recording it gets nearly out of sight before the cut); the two video pages and one-frame display lag are
  not modelled.
- Code review 2026-11-14: Swift re-read against MAIN.C, `docol`, `docopy` and THELOOP.INC; no bug found,
  nothing changed in the scene. Modern look in motion: no jumps (`--motion-check`), and a new self-test checks
  the camera glide is unbroken over a loop and into the next. MAIN.C/docol/docopy are still verified by
  reading only (now twice), not by running them.
- Useful for the later 3D scenes: (1) read the MAKEFILE first, it settled which files and even which
  artwork were live; (2) check generated or built files against their generator source, they can differ;
  (3) when an inner loop is plain assembly text, interpreting that text in Python is a cheap, strong check
  of a port (about 100 lines; see `tools/`); (4) a YouTube recording can be measured: open it in the built-in browser, seek the video with JavaScript,
  read small fingerprints of frames from a canvas, and match them to reference pictures (this gave the
  speed above); (5) C.EXE files linked with `/E` are run-length packed, so
  data cannot be searched for in them reliably.

## Plasma Cube notes
- Source: PLZPART/VECT.C, PLZFILL.C, PLZA.ASM (`do_block`, `do_clear`, `shadepal`), SPLINE.ASM (`getspl`) with
  RATA.INC and SPLINE.INC, SINIT.INC; COPPER.ASM only uploads the palette and counts frames here.
  PLZPART.PRJ and the link map settle what is live.
- NOT used by the shipped program: TILE.INC / TILEPAL.INC (so no original artwork in this scene), the
  plasma's tables, the plasma's fifth palette. No floor, no shadow. The planning notes' "doubling" is the
  alternating 2-pixel shift below. `Scenes/Plasma/` was not touched.
- What it shows: a cube (corners +-125) on a hand-made path of 36 points blended by a weight table, 64 frames
  per point; faces culled by normal (no sorting); three colour ranges of 64, dimmed through the palette by a
  moving light; the light ends up behind the cube, so the scene fades itself to black at original frame 1995.
- Texture: 256x64, calculated once (`wave[4y + wave[2x]]/4 + 32`); the flow comes from a per-row sideways
  shift table read one row further on each frame. One texture lookup per 4 pixels (all four VGA planes
  written at once); line ends masked to the exact pixel.
- Canvas 320x400: 134 picture rows, each three monitor lines. Pages are 640x136, three of them; the view is
  320 wide starting 160 in.
- Classic look: `PlasmaCubeModel` (path, turn, projection, culling, lighting in 16/32-bit arithmetic) and
  `CubeVideoCard` in `PlasmaCubeFiller.swift` (planes, pages, edge walker, line filler with the processor's
  registers mirrored, eraser), shown through `IndexedCanvas`. Verified against `tools/plasmacube_reference.py`,
  which runs PLZA.ASM and SPLINE.ASM as text in a small x86 interpreter (macros expanded, planes modelled):
  identical screens and palettes at 10 steps for both shifts. The C parts were ported by reading (twice:
  Python and Swift, same author).
- Two replays run half a cycle apart and the classic look shows the even mix (`IndexedCanvas.draw(...,
  blendedWith:)`, new), because the original drew alternate frames 2 pixels apart for the eye to mix.
- Tables kept as original numbers in `PlasmaCubeTables.swift` (made by the tool's `--tables`): SINIT.INC and
  SPLINE.INC. No formula reproduces either exactly (tried: sine amplitudes 32760...32768 with three roundings;
  cubic pieces and cosine sums for the blend table). Path points are written out in the model.
- Modern look: real triangles through `Math3D.perspective`, texture per pixel from the wave formulas,
  perspective-correct, edges faded over one pixel on oversized faces, everything gliding via the path read
  between table entries.
- Deliberate departures: starts 16 steps early (cube fully out of sight) and loops after 2048 steps from
  black; the alternating shift shown mixed; picture and palette shown the step they are made.
- Kept quirks: light level remembered per drawing position, not per face (stale colours now and then); two
  register accidents in the filler; signed shift read as unsigned.
- Not verified: against a running original or a recording; when the music cut the part; the C compiler's
  `sin()` for the start-up tables; the modern look's texture and edge smoothing beyond still pictures.
- Code review 2026-11-14 (branch `claude/review-plasma-1872aa`): no fault found in the scene; no picture
  changed. VECT.C and PLZFILL.C read again independently against the Swift, no difference. New self-test
  check compares the modern cube with the 1993 replay at all 2048 steps (same faces bar 16 edge-on steps,
  corners within 4.3 units of 250, light within 2 of 64). `--motion-check` on the modern look: no jumps,
  whole loop and across the loop point. One tool fix: `tools/plasmacube_reference.py --src` was ignored
  for the tables (they were read before the options); it now works from a worktree, and re-running it
  reproduced the stored checksums for steps 16, 60 and 416. Tidy-ups listed in the scene page.
- For the later 3D scenes (glenz, ships, city):
  - `Core/Math3D.swift`: `perspective(focal:centre:canvasSize:near:far:)` gives the matrix for an original's
    "x*focal/z + centre" projection in canvas pixels (camera looks along +z, y down); it already spreads depth
    over 0...1. Also `project`, `rotationX/Y/Z`, `transform`, `facesCamera`.
  - There is NO depth buffer yet: the render passes in `Renderer`, `Snapshot` and the self-test have only a
    colour attachment. A convex cube does not need one. Glenz (see-through, convex shapes) probably will not
    either; ships and city will, or must sort faces as the original did. Adding one means a depth texture in
    those three passes AND `depthAttachmentPixelFormat` on every scene's pipeline, so plan it as its own change.
  - Edge smoothing without multisampling: draw each face oversized, pass 0...1 face coordinates, fade by
    `min(uv, 1-uv) / fwidth(uv) + 1`, blend with premultiplied alpha. Works for convex objects drawn in any order.
  - The interpreter in `tools/plasmacube_reference.py` is general enough to reuse: it parses Turbo Assembler
    IDEAL and MASM operands, IRP/REPT/INCLUDE, data and ARG, and about 35 instructions with flags, in a 1 MB
    memory with VGA planes. Check new instructions before trusting it.
  - A C expression trap met here: `a>>15+7` means `a>>22`.
  - Check what a path really shows before designing a loop: this scene already ended in black by itself.

## Glenz Vectors notes
- Source: GLENZ/MAIN.C (script), MATH.ASM + MATHSIN.INC (turn matrix), VEC.ASM (rotlist, cliplist, projlist,
  ceasypolylist, checkhiddenbx, demo_glz, demo_glz2), NEW.ASM (filler; included by VIDPOLY.ASM), VID.ASM
  `init320x200` (projection numbers), FC.UH = linked _FC.OBK (plate picture). MAKEFILE and V.MAP settle what
  is live; most of VID*.ASM, ZOOM.ASM, `zoomer1`, `cpolylist`, `cclipedges` are linked but never called.
- USES ORIGINAL ARTWORK (user's rule applied): the chequered plate is a hand-drawn 16-colour picture, no
  formula. Its 108 rows and 16 colours are in `GlenzFloorArt.swift` (made by `tools/glenz_reference.py --art`).
- What the shipped program does (differs from the team's SCRIPT notes): no picture tipping over (`zoomer1`
  is dead code); the plate itself drops in and bounces; a blue-and-white glenz falls on it three times with
  a jelly squash (pressed flat against the floor by clamping corners); plate fades; a LARGER red glenz
  grows around the first; both wander; the first flies out of the top; both shrink; fade.
- Mode 13h (320x200, 256 colours, one page). Transparency = colour numbers + XOR + palette: first-glenz
  front faces get their own multiple of 16 (16 palette entries each, rewritten every frame with the face's
  light plus a quarter of colours 0-15); back blue faces are 4; the second glenz uses bits 1, 2, 4; the
  filler XORs the numbers of all faces over a pixel and ORs in the floor picture's pixel. Light = the
  face's area on screen.
- Classic look: `GlenzModel` + `GlenzScript` + `GlenzFiller`, shown through `IndexedCanvas`. Verified
  against `tools/glenz_reference.py` (MATH.ASM, VEC.ASM, NEW.ASM run as text): screen and all 256 colours
  identical at 26 steps. MAIN.C ported by reading (Python and Swift); the 16-bit bounce overflow was also
  confirmed in the compiled MAIN.OBJ.
- Modern look: corners in decimals, faces as smooth-edged triangles, mixed by blending that follows the
  original's rule (add the reds; XOR the "4" bit in the alpha channel; front faces = own colour + a
  quarter of what is behind). Uses the drawable's alpha channel as scratch and sets it back to 1.
- Timing: plate 177 steps, pause 35 (our choice; the original waited for the music), original frame =
  step - 212, black from step 2345, loop at 2360.
- Deliberate departures: lead-in (`zoomer2`, wipes the previous scene's picture) left out; the pause; the
  loop; one picture per step. Kept quirks are listed in docs/scenes/glenz-vectors.md (the third bounce
  sticks for four frames because of 16-bit overflow; blue faces' red is a leftover register; a face is
  unlit on its first frame; the plate does not fade under the glenz).
- Code review 2026-11-14: script and plate re-read against MAIN.C, no difference. One modern-look bug
  fixed: the plate snapped up 0.94 of a row on the step it settled (it switched from the fall's exact
  position to the 1993 look's whole row); it now rests at 47 15/16. New self-tests: modern corners within
  3 pixels of the 1993 corners at every step and every glide unbroken (so nothing glides across a phase
  change), and the plate never moves faster than it falls. The one-step dimming at step 1070 is the
  original's (`lightshift` becomes 10 when bscale 116 passes xscale 115), in both looks.
- Not verified: against a running original or a recording; the music timings; how the modern look's
  colours look in motion (positions are now checked by program).
- For the two remaining 3D scenes (ships, city; VISU engine):
  - `tools/glenz_reference.py` shows how to reuse the interpreter: `import plasmacube_reference as pc`,
    replace `pc.compile_instruction` / `pc.parse_operand` with wrappers that add instructions, and feed
    it text first turned from MASM style into its dialect (`translate`, `expand_all` with MACRO/LOCAL/REPT/
    dup, "label: ENDM"). It now covers near and indirect calls, 32-bit imul, shrd, sbb, neg, xchg, string
    moves and the VGA colour ports. Unsupported instructions only fail if they are actually run.
  - Self-modifying code (numbers patched into instructions) needs a small text rewrite before interpreting.
  - A reference run found a real port mistake here that reading had missed (a register overwritten on one
    path). Compare palettes as well as screens.
  - GLENZ's MATH.ASM / VEC.ASM look like an early relative of the VISU engine (same list formats as in
    GLENZ/DOC). Check whether VISU has the same habits: 3600-step sine table with the +0.5 rounding (two
    entries off), `rotlist` returning y and z swapped, angles handed over crossed, projection
    "centre + mul * x / z" with z held to at least 128, 16.16 edge slopes.
  - `Math3D.rotationYXZ`, `canvasPosition`, `screenFacing` are in Core for this. `Core/SmoothTriangles.swift`
    gives seam-free smooth edges for flat triangles when the blending adds coverage up; with ordinary
    "over" blending a faint seam would show, and solid sorted polygons (ships, city) still need either
    a depth buffer or far-to-near order. There is still NO depth buffer in the three render passes.
    (Later the same day: still true of the main passes. The VISU renderer brings its own depth buffer in
    a pre-pass; see "VISU engine notes".)
  - `setVertexBytes` holds at most 4 KB: fine for 24 triangles of 48 bytes a corner, not for a ship. Use
    a vertex buffer for bigger shapes.
  - Compiled .OBJ files can settle questions about the C code: search for the instruction bytes.

## VISU engine notes
Full write-up: `docs/visu-engine.md` (formats byte by byte, the pipeline, what was checked). Short version:
- Source: `VISU/` ACALC.ASM, ADRAW.ASM + ADRAWCLP.ASM, AVID.ASM + AVIDM1.ASM + AVIDFILL.ASM, ADATA.ASM (three
  tables), VISU.C; scene programs `VISU/C/U2A.C` (ships) and `U2E.C` (city), which differ only in start, end,
  clearing, pacing and a few ordering rules. MAKEFILE and VISU.LST settle what is live. The data in
  `VISU/C/SCENE/` and both EXEs are identical to the shipped copies in `MAIN/DATA/`.
- Mode X 320x200, window `vid_window(0,319,25,174,512,9999999)` (a 320x150 band), oversampling off, 640x400
  mode unused. Field of view fixed: 8704 ships, 7168 city.
- Data used in the files: flat and Gouraud polygons with 16 or 32 shades, 3 to 12 corners. No two-sided,
  unshaded, 8-shade or textured polygons exist in the data (ported, untested).
- All three tables are calculated from DOSIN.C / DOTAN.C / DOFILL.C and equal the files.
- Classic: `VisuEngine` (one object to pixels) + `VisuWorld` (scene files, animation stream, object order),
  ported step for step. Verified against `tools/visu_reference.py`, which runs the assembly as text: 124 test
  pictures identical (15 ships frames, 45 city frames, 5 multi-frame runs, 59 single-object and clipping
  cases; 15 of the 124 were added by the code review), no faults. The C parts were ported by reading
  (Python and Swift, same author) and read a third time, independently, in the review.
- Modern: `VisuModernRenderer`: triangles into an off-screen picture with a depth buffer and 4 samples per
  pixel, composited over the scene's background. Depth buffer BETWEEN objects; the original's order lists
  WITHIN an object (tried a plain depth buffer first: the big ship's hull panels half vanished, because they
  float just off the hull and partly dip inside it). Light by the original's rule per corner, colour blended
  between palette entries. Depth stored as near/z (`Math3D.perspectiveNearOverZ`).
- Kept quirks: wrong Gouraud colours on polygons cut by the near plane (the original's TODO says "ZCLIP /
  gouraud"); `clipvisfl` is never cleared; the `calc_setrmatrix_rot*` routines cross the y and z angles
  (used only by test cases); 16-bit screen positions.
- Interpreter additions worth knowing (in `visu_reference.py`, a third layer): word operators in constants
  (`and`, `shr`, `not`), `REPT` with `LOCAL` and "label: REPT", nested PROCs (labels made unique per procedure
  before assembling), 16-bit idiv with overflow detection, mul, sar/sal/rcl/cmc/cwd/lea/lfs, the VGA plane
  mask through ports 3C4/3C5, calls through a register, and a computed jump into unrolled code done by
  counting instruction pairs. Each test case starts with heap memory filled with 0xCC, so a result cannot
  quietly depend on an earlier case (this caught the camera matrix not being zeroed).
- Not verified: against a running original or a recording; the scenes' starts, ends, fades and music timing
  (read from U2A.C / U2E.C only); the modern look in motion.
- CODE REVIEW (2026-11-14; full account in docs/visu-engine.md, "Code review"). Every finding was
  demonstrated before it was changed.
  - Fixed: the loader trusted counts and positions in the data files (14 kinds of damage each shown to
    crash the app); now every one is checked and a bad file gives `VisuError.badFile` with the reason. A
    damaged animation just ends where the damage is.
  - Fixed: clipping could grow a polygon past the engine's polygon records (a 16-corner zig-zag cut into
    more than 40 corners, found by a directed search, kept as `VisuDamagedFiles.worstScribble`). Growth
    stops at 32 corners (`VisuEngine.mostClippedCorners`) and counts as a fault. Real polygons stay at 16
    or under.
  - Fixed, modern look: the shader normalised the turned normal; the original does not, and the
    recordings SCALE some objects (the ships' big ship shrinks to about a fifth; city building
    "talojota" is stretched 2x in depth), so those were lit differently from the 1993 look (ships
    frame 100: modern 4.5 of 255 brighter on average, now 0.7).
  - Fixed: `--visu-test compare` skipped cases it could not draw without a word.
  - Coverage: both whole animations were played with temporary counters in the engine. They reach five
    engine paths and 32 object/order-list pairs the 109 cases did not; 14 city frames and a two-frame
    ships run (22 and 261, one engine) now cover all of them and match the original assembly.
  - New self-test checks (6; the whole self-test has 206 now): both whole animations with no
    faults; one engine drawing every frame gives the same pictures as a fresh engine per frame (so the
    carried-over state changes no pixel in either animation); 2,466 damaged files and 401 scribbled
    polygons; the light on the scaled big ship; both scenes built and stepped on four threads at once.
  - Confirmed by independent reading: VISU.C, the animation reader, the sort and U2E.C's ordering rules
    (its frame counter counts in twos); `vid_init(3)` ("oversample x 4" in U2A.C) is the plain mode.
    A missing data file gives a clear message in the headless tools; the data is found from four
    different ways of starting the program.
  - Measured, no change: the modern picture sits about a third of a 1993 pixel lower than the 1993 one
    (the original filler steps its edges before each row).
  - Not demonstrated, left alone: the modern renderer's shared palette buffer (a fade could be one step
    early for one frame if the graphics chip ran behind); the mesh cache filed by object identity; the
    replacement background's band edges at small sizes; a blend value outside 0...1 on the command line.
  - Tidy-ups left for a later `/simplify` pass: listed at the end of docs/visu-engine.md.
  - `tools/visu_reference.py` takes `SR_ORIGINAL=<folder of the original source>` (needed in a worktree).
  - The self-test takes about 14 s now (was about 10).

## How to build the Ships and City scenes with this
Read `docs/visu-engine.md` first ("The two scenes" table has each scene's parameters). Then, per scene:

1. Load: `let world = try VisuWorld(name: "U2A")` (ships) or `"U2E"` (city). For the city also set
   `world.distanceRule = VisuWorld.cityOrdering`. Make ONE `VisuEngine` and call
   `VisuWorld.setSceneWindow(engine)`.
2. Stepping: the app steps 70 times a second. Ships: `world.advance()` every step (521 frames, 7.4 s).
   City: every SECOND step (1801 frames, 51.5 s). `advance()` returns false at the end of the animation.
   After each advance keep two poses for the modern look: `previous = current; current = world.pose()`.
3. 1993 look: put the background into `engine.pixels` (ships: the 64,000 pixel bytes of `U2ABG.UH` after its
   784-byte header; city: `engine.clear(to: 255)`), call `world.draw(with: engine)`, and show
   `engine.pixels` with `IndexedCanvas`. Palette: `VisuTest.palette(for: world)` gives the ships palette
   (scene colours + the background's 64 colours at 192...255); for the city use `world.palette` with colours
   252 and 255 set to black and 253, 254 to white (U2E.C). Values are 0...63.
4. Modern look: in `prepare(commands:frame:)` call `engine.setCameraAngle(world.fieldOfView)` and
   `renderer.render(previous.blended(to: current, alpha: frame.alpha), view: engine.view, palette: ...,
   targetSize: frame.targetSize, commands: commands)`; in `draw` draw the background first with an ordinary
   pipeline, then `renderer.composite(into: encoder)`. For the city, whose animation frame lasts two steps,
   the blend factor is `(stepWithinFrame + frame.alpha) / 2`.
5. `App/VisuTestCommand.swift` is a complete worked example of both looks without a scene.

Pitfalls found:
- `reset()` must call `world.restart()` AND `engine.resetClipper()` (or make a new engine): the engine carries
  state from polygon to polygon (the never-cleared clip flag, leftover bytes in its polygon records), and the
  self-test's "restarts from its first frame" check compares pictures exactly.
- `world.pose()` and `world.draw(with:)` both recompute the objects' camera matrices, so they can be called
  in any order, but `draw` sets the engine's field of view and `pose` does not.
- Object names include their quote marks (`"s01"`), which is why U2E.C tests `name[1]`.
- The first pictures are empty: no object is on until frame 17 (ships) / frame 1 (city). Before any
  `advance()` the field of view is 0, which the engine clamps; nothing is drawn anyway.
- The original showed only a 320x150 band (rows 25-174). The modern renderer clips to the same band.
- Scenes are created on background threads for the sidebar pictures; `VisuWorld` loads files in its
  initialiser, which is fine, but do not share one `VisuWorld` between scene instances.
- For the scenes' self-test checkpoints, `classicReferenceFrame()` is just `engine.pixels` through the
  palette. Whole-frame checksums that already match the original are in `VisuTestCases.swift` (drawn into
  an empty screen of colour 0, from a fresh engine); reuse those frames as a scene-level cross-check.
- Known gaps to watch in motion (modern look): objects lying almost on top of each other (roads are 10 units
  above ground plates; fine in stills), and city frames 901-1099, where the original forced the ship to be
  drawn last and the modern look trusts the depth buffer instead. If flicker shows, a small depth bias in
  favour of later-drawn objects is the first thing to try.
- (Both scenes are now built. The two "known gaps" above did not show in the city: see "3D City notes".
  Both scenes use `VisuPlayback`, which wraps steps 1, 2 and the pose handling of step 4.)

## Ships Fly-by notes
Full write-up: `docs/scenes/ships-flyby.md`.
- Source: `VISU/C/U2A.C` (scene program) + the VISU engine + `U2A.*` data + `U2ABG.UH`. Files in
  `Scenes/ShipsFlyby/`: `ShipsFlybyModel.swift` (background, palette, timetable; no graphics code) and
  `ShipsFlybyScene.swift` (Metal).
- USES ORIGINAL ARTWORK AND DATA (user's decision, 2026-11-14): the hand-painted horizon picture
  `U2ABG.UH` stays as the background; the ships and their flight are the original's models and recorded
  animation. Declared at the top of the scene's page, in the README and in `Data/Visu/README.md`.
- What U2A.C adds to the engine: copies the WHOLE 320x200 background over the page every frame
  (`vid_clearbg`; rows outside 25...174 of the picture are black), palette = scene colours + the picture's
  64 colours at 192...255, no fades at all, starts and ends on music cues with the plain horizon showing.
- Speed: NOT PC-dependent. An interrupt counts screen refreshes and the program reads one animation frame
  per refresh (skipping frames when drawing was slow). So one frame per step is the original's rate.
- Timetable: steps 0...70 empty horizon (`ShipsFlybyModel.pauseSteps` = 70, our choice, the ONE number to
  change by eye), steps 71...591 = animation frames 1...521, loop at 592 (8.5 s). The animation itself
  is empty for its first 22 frames and a speck for its last second. The last frame still has 4 pixels of
  the big ship (it is never switched off); they vanish at the loop point.
- Objects: 1, 4, 5 = small ship (one model three times; on at frames 260, 260, 271; off at 515, 520,
  518), 2 = big ship (on at 17, first seen at 23, never off), 3 = engine (never on). Frame 521 switches
  object 5 back on (a leftover in the data; harmless).
- Classic look: model draws EVERY step (background copy + `world.draw(with: engine)`), whichever look is
  showing, so the engine's carried-over state depends only on the step. `reset()` restarts both worlds and
  calls `engine.resetClipper()`.
- Modern look: background drawn first (smooth scaling; band edges kept crisp by clamping in the shader),
  then `VisuModernRenderer` composited over it. Gliding uses a SECOND `VisuWorld` kept one frame ahead
  (`ahead`), so at blend 0 the modern look shows exactly the classic frame, and it glides towards a
  known next frame.
- Replacement background for the modern look (for upscaled artwork later): put a picture named
  `U2ABG-modern.png` in `Data/Visu/` and rebuild (`build.sh` copies `Data/Visu/U2*`). It must show the
  whole 320x200 screen (4:3 as displayed, bars included; any pixel size). The 1993 look ignores it. Tried
  once with a test picture; none is shipped. Code: `ShipsFlybyScene.modernBackgroundFile`.
- Checked: scene pictures agree with all 15 assembly-verified ships frames (self-test: same ship pixels,
  background untouched elsewhere); background and palette checksums from the original files; the loop;
  restart; the glide (ends where the next step starts, and is half-way at half-way); the two looks within
  2.8/255 of each other at 5 steps; motion of the whole loop by program (below).
- Not checked: a running original or recording; U2A.C's start/end as the demo showed them; the modern
  look by eye in the running app (the user is the first to watch it move).
- Code review (2026-11-14, see docs/scenes/ships-flyby.md): U2A.C read again independently, no
  difference found. One visible fix, in the engine: the recording SCALES the big ship down to about a
  fifth as it leaves, the original's light weakens with that scale (the ship greys), and the modern
  look ignored it. Now both looks do it; a new kept quirk, "the big ship greys as it shrinks".
  Motion check re-run: 1993 report identical, modern still no jumps.
- MOTION CHECK (first time in this project): every step of the loop was rendered in both looks, the
  modern look also half-way between steps (1,776 pictures), and neighbours compared by a small program.
  Result: no jumps in either look (no step's change stands out from its neighbours, including the pause
  and the loop point); the glide is even (the two halves of a step carry the same change, 2% apart on
  average); no flicker on the big ship's hull panels (the engine notes' predicted problem did not show);
  the only violent moment is the animation's own (steps 331...346, fighters entering through the near
  plane from behind the camera, same shapes in both looks). The first run FOUND A REAL BUG that stills
  could not show: the modern look was not gliding at all (see the trap below). Fixed and self-tested.
- For the city session:
  - Copy the structure of `ShipsFlybyModel`/`ShipsFlybyScene`. The city's animation frame lasts TWO
    steps, so its look-ahead world advances every second step and the blend is `(stepWithinFrame +
    alpha) / 2`.
  - TRAP met here: `VisuPose.blended` pairs objects by identity. A pose taken from a second `VisuWorld`
    has different objects, so NOTHING pairs and the "blend" silently shows the next frame (no glide, and
    stills look perfect). Re-label the look-ahead pose with the main world's objects, as
    `ShipsFlybyModel.tick` does. The self-test check "is half-way between frames half-way through a step"
    exists to catch this; write the same check for the city.
  - Stills cannot show motion faults. Use `--snapshot <id> modern <step> <file> 0.5` to render between
    steps, render a run of consecutive pictures, and compare neighbours (a jump = one change much bigger
    than those around it; flicker = pixels unlike both neighbours while the neighbours agree). The
    comparison program was a throw-away Swift script (about 70 lines, ImageIO); rendering all 1,776
    pictures took about 10 minutes, one process per picture.
  - Never leave test files in `build/SRMetal.app/Contents/Resources/Visu/` while rendering: a test
    background left there for a minute showed up as a "pop" in two pictures.
  - No depth trouble showed in the ships scene (objects never interlock, and each ship is drawn in
    the original's own polygon order). The city is the real test of the predicted problems: roads 10
    units above ground plates, and frames 901...1099 (ship forced last in the original).
  - The Swift compiler gives up ("unable to type-check in reasonable time") on a closure that builds a
    SIMD4 from several `Float(...)` conversions and divides; write the parts out as separate `let`s.

## 3D City notes
Full write-up: `docs/scenes/city-3d.md`.
- Source: `VISU/C/U2E.C` (scene program) + the VISU engine + `U2E.*` data. Files in `Scenes/City3D/`:
  `City3DModel.swift` (palette, timetable, fades, roll smoothing; no graphics code) and `City3DScene.swift`.
- USES ORIGINAL 3D DATA (accepted by the user): 57 objects from 42 model files, one 1,801-frame recorded
  flight. NO picture (background is black, colour 255). Declared at the top of the scene's page and in the README.
- What U2E.C adds to the engine: clear to colour 255; palette with 252, 255 black and 253, 254 white; two
  ordering rules (underscore names = ground, drawn first; ship drawn "last" in frames 901...1099, which
  really means distance 1, so objects whose centre is BEHIND the camera can still follow it); no text or
  overlay; white fades at both ends (left out).
- Speed: NOT PC-dependent. Confirmed in U2E.C: it counts screen refreshes and reads (late + 1) / 2 frames,
  so exactly one animation frame per two refreshes (35 a second, 51.5 s).
- Timetable: steps 0, 1 black; steps 2...3603 = frames 1...1801, two steps each; fade up over
  `fadeInSteps` = 70 from step 2; fade down over the LAST `fadeOutSteps` = 105 steps of the animation;
  `darkSteps` = 35 black; loop at 3639 (52 s). Those three constants are the ones to change by eye.
  The opening frame is a white wall filling the band, which slides away (the original's hand-over from a
  white screen); the fade-in keeps it dim while it fills the picture, so there is no full white screen.
- Classic look: every animation frame drawn once, in order, by one engine. Matches all 45
  assembly-verified city frames (self-test), so the engine's carried-over state changes nothing there.
- SPEED of the 1993 replay, measured: 0.25 ms a step on average, about 1 ms at worst (budget 14.3 ms).
  Nothing needed optimising. The self-test measures it every run. Whole self-test: about 10 s.
- Modern look: `VisuModernRenderer`, blend = (step within frame + alpha) / 2.
- CAMERA ROLL SMOOTHING (modern look only, our addition): the recording holds the camera's roll only in
  whole degrees, so the camera snapped 1 degree hundreds of times; the motion check showed it as
  one-picture-only pixels on every edge at once. `City3DModel.rollCorrections` finds the smoothest roll
  within half a degree of the recorded one (blur, clamp to the band, repeat 100 times) and the modern pose
  is rolled by the difference (`VisuPose.rolled`). `smoothCameraRoll` switches it off. So the modern
  picture can be tilted up to 0.5 degrees from the 1993 one.
- MOTION CHECK results: the predicted depth trouble did NOT happen. Drawing every frame with objects in
  reverse order changed at most 2 pixels, so no depth bias and no forced ship order are needed in the
  modern look. After the roll fix: spikes of one-picture-only pixels 213 -> 53, uneven changes 111 -> 19.
  What is left: thin ship outlines at moments the ship's recorded motion changes direction, objects
  switching on or off, and the ship flying past the camera at steps 3516...3526 (the recording's own).
- Shared code moved to `Core/Visu/VisuPlayback.swift` (world + look-ahead world + engine, restart, pose
  re-labelling, palette helpers); `ShipsFlybyModel` now uses it and all its checks pass unchanged.
  Other engine additions: `VisuWorld.cameraTrack()`, `VisuPose.rolled(by:)`. No engine behaviour changed.
- Not checked: a running original or recording; U2E.C's start and end as shown; that the roll steps are
  an export artefact rather than intent (a judgement); the cause of the leftover ship-outline spikes
  (judged from where the pixels are); the ship's visibility in the forced-order stretch beyond 8 samples;
  the modern look by eye in the running app.
- Trap met while testing: "ship drawn last" is not literally last (see above); a check that expected the
  ship at the end of the order failed in 17 frames for that reason.
- Code review (2026-11-14, see docs/scenes/city-3d.md): no fault found in the scene's own files. U2E.C
  read again independently (ordering rules, frame counter, palette, pace, skipped first turn): no
  difference. The scene now matches 45 assembly-verified frames (31 before). The engine's two fixes
  apply here too (damaged files; the stretched building "talojota" is now lit in the modern look as
  in the 1993 one). Motion check re-run: 1993 report identical; modern 5 jumps and 137 spikes, as before.

## Planned scenes (user's list, 2026-11-14), easiest first
Only the purely calculated scenes and the 3D scenes will be done; the picture-based scenes, scrollers and
stills are out of scope.
1. Bouncing dots - DONE
2. Plasma (PLZPART/PLZ.C + ASMYT.ASM, COPPER.ASM) - DONE
3. Hidden starfield (DDSTARS) - DONE
4. 3D sine landscape (COMAN) - DONE (the background picture turned out to be unused)
5. Plasma cube (PLZPART/VECT.C, PLZFILL.C) - DONE (it shares nothing with the plasma after all)
6. Glenz vectors (GLENZ) - DONE (the floor is a hand-drawn picture, included as data)
-  The shared 3D engine for 7 and 8 (VISU) - DONE as groundwork, verified, no scene (2026-11-14)
7. Ships fly-by (VISU engine + U2A data) - DONE (original background picture kept, user's decision)
8. 3D city (VISU engine + U2E data) - DONE (no picture; modern look evens out the camera roll)
All planned scenes are done.
Ranks 3-6 were judged from file sizes and may swap once read. 7 and 8 share one engine.

## Next steps
- FUTURE (user, 2026-11-24): replace the 21 credits pictures (`artwork/original/18-credits-pic*`)
  with screenshots taken from this project's own finished scenes, framed like the originals (compare
  with `artwork/original/4x3/`). Most credits pictures are miniature screenshots of the demo's parts,
  so this needs those parts built as scenes first. `pic02` is a placeholder ("PART PIC MISSING") and
  `pic06` (Interference) was first in line. `--snapshot` can make the pictures.
- DEMO TIMELINE RESEARCH DONE (2026-11-24): `docs/demo-timeline.md` has every part's start and end
  (from the original source, simulated against the real music with `tools/music_steps.c` +
  `tools/demo_timeline.py`): 19 parts, credits end at 10:52, then the end scroller until a key. Key facts:
  song 1 = MUSIC0 at tempo 120 (STARTMUS.C overrides the file's 125: every section 8 s); loader runs
  song 1 from 0 (parts 1-4), song 2 from 0 (parts 5-15), song 1 from section 18 (city and end parts);
  most parts wait on "music plus" (rows around "+++" separators); dis_getmframe counts 1/70 s; the
  player's section number is the one playing (both "most likely", see the doc). Two helper agents
  read the parts; Claude checked their numbers against our scenes (tunnel 1,060; techno 420/840/980).
  The user said (2026-11-24) the visuals' tempo and the music's already line up well, by ear.
  DONE (2026-11-24): the Play Demo skeleton built on it (see "PLAY DEMO notes"). NEXT: replace stand-ins
  part by part with real parts (the user chooses which), and make the built scenes follow the original
  part's timing inside the demo instead of looping.
- WHERE WE LEFT OFF (end of 2026-11-24). Play Demo skeleton done and pushed. The user dropped the AI
  artwork (deleted). The Modern look's pictures now go through Super-xBR (user's choice after
  side-by-side sheets). NEXT: the user looks at it in the app; later, one at a time, re-made pictures
  (water via POV-Ray, credits from scenes).
  SCALER COMPARISON DONE (2026-11-24): `Core/PictureScaler.swift` has four methods as Metal shaders
  (smooth, sharp pixels, xBR level 2, Super-xBR 4x then smooth), the xBR ones written from Hyllian's
  MIT-licensed libretro shaders (default-preset settings). `--scaler-compare <picture> <folder> [x y w]`
  makes labelled 2x2 sheets (whole picture, and a zoomed part). Sheets for troll, title, Glenz plate
  and Ships horizon are in `build/scaler-compare/` (not in git). Claude's read: xBR level 2 turns the
  painted shading into hard contour bands (rejected); Super-xBR gives clean edges and smooth shading,
  slightly soft; it once turned two neighbouring stars into a short streak. Nothing in the app uses
  the scaler yet: WAITING for the user's choice.
  CHOSEN AND BUILT (user, 2026-11-24): SUPER-XBR. `PictureScaler.upscaled(_:device:)` makes a picture 4x
  once (two rounds of the three passes, rgba16Float, mipmapped; one compiled scaler per device, behind a
  lock, since sidebar pictures are made on a background thread). Used by Ships Fly-by's background,
  Glenz's plate and Play Demo's pictures (Modern look only; Play Demo keeps only the picture showing at
  4x). 2 new self-test checks (272): a flat colour stays unchanged and 4x; on the troll every new
  pixel lies within the colours of the original pixels within 2 around it (proven to fail, 268,682
  values, with Super-xBR's own clamp removed). Docs pictures remade: ships-flyby-modern/-bigship/-near,
  glenz-vectors-squash-modern. Seen by Claude in snapshots: ships, glenz plate, troll. NOT seen by the
  user in the running app yet.
  8X (user, 2026-11-24): after a 4x-vs-8x comparison at 5K-fullscreen size (8x crisper on hard outlines,
  e.g. the title's eyes; same on soft brushwork), the app now uses 8x (`PictureScaler.modernScale`,
  three rounds; still rgba16Float). The user's concern is the PROGRAM's size, not memory: the 8x
  pictures are made at run time (well under 0.1 s each), so the app is unchanged in size.
The planned list of scenes is complete (2026-11-14).
- DONE (2026-11-14): the code review. Techno Bars was reviewed first, then five parallel sessions, each in its
  own worktree, reviewed everything else against the original source (early scenes; the plasma pair; starfield,
  landscape and glenz; the 3D engine with ships and city; the shared core and app). Their branches merged
  cleanly into main. 24 proven bugs fixed, each with a self-test check; the self-test went from 200 to 253
  checks. Every scene page now has a "Code review" section saying what was found, what was confirmed, and
  what is still unverified. All docs pictures were remade afterwards.
  Notable: Dot Tunnel's 1993 look now replays the original's dot-by-dot erasing (about one dot in twenty is
  missing each frame, as in 1993); every Hidden Starfield dot had been one step out of place; the plasma's
  sideways shift was paired with the wrong frame; the 3D loader no longer crashes on damaged files.
- MOSTLY SETTLED (2026-11-24, docs/demo-timeline.md): the plasma's section timings (dis_getmframe) are in
  screen refreshes (1/70 s), as built: simulating the whole demo with music ticks makes later parts overrun
  song 2, and a recording places the sine landscape where the 1/70-s reading predicts. To confirm: that the
  recording (youtu.be/iw17c70uJes) starts with the music (check the explosion flash at about 1:44).
- NEXT, if the user wants it: a `/simplify` pass. Each scene page and the core notes list "Possible
  tidy-ups" that the review deliberately left alone.
- Still never done: comparing any scene with the original program running. The user's own copy of the
  released demo is in `../second-reality-original/` (outside this repository); it could be run in a DOS
  emulator for a side-by-side check.
- Waiting on the user, by eye in the running app: the 3D City's fades (`City3DModel.fadeInSteps`,
  `fadeOutSteps`, `darkSteps`) and whether the evened-out camera roll looks right
  (`City3DModel.smoothCameraRoll`); Ships Fly-by's pause (`ShipsFlybyModel.pauseSteps`) and scaled-up background.
- After the review: the undecided ideas in `docs/future-ideas.md` (a third "Reimagined" look per scene;
  the whole demo with music and upscaled artwork). The user will decide; do not start them unasked.
- Possible polish: the Dot Tunnel sidebar picture is rather dim (thin dots at small size).
- `--motion-check` now exists for every scene; only Ships Fly-by and the 3D City have been through it.
