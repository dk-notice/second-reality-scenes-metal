# Project state

Last updated: 2026-11-25 (the demo is finished; next: the video export and a look at the interface, both to be planned with the user)

## Goal
A native macOS app that re-creates Second Reality (Future Crew, 1993) from scratch, drawn on the graphics
chip with Metal: every part as a scene, and the whole demo with its music ("Play Demo"). Each scene has
two looks: Modern (full resolution, smooth) and 1993 (original pixels, usually 320x200; 70 steps per
second). The original source is public domain and lives in `../secondreality` for reference; the existing
complete C++ port is in `../SecondRealityPlusPlus`; the user's copy of the released demo is in
`../second-reality-original`.

## Status (2026-11-25)
- 25 scenes work in both looks and are in the sidebar in the demo's order: Opening Credits, Ships Fly-by,
  Explosion, Title Picture, Glenz Vectors, Dot Tunnel, Rings, Interference, Techno Bars, Troll, Screen
  Switches Off, Mountain Scroller, Lens, Rotozoomer, Plasma, Plasma Cube, Bouncing Dots, Water Scroller,
  3D Sine Landscape, Jelly Logo, 3D City, End Picture, Credits, End Scroller, and the Hidden Starfield
  (last; not in the demo). Each scene's page (`docs/scenes/`) says what was built and checked.
- PLAY DEMO (Scene menu, P; Shift-P from the sidebar's scene; Escape stops) runs all 19 parts in the
  original order with the original music (libopenmpt), changing parts on the original's music cues. Every
  part is a real scene and follows its original part's own timing inside Play Demo. On their own, some
  scenes' lengths differ from the original parts on purpose: Glenz 2,360, Plasma 2,588, Plasma Cube
  2,048, Sine Landscape 2,048, 3D City 3,639, Ships 592.
- Self-test: 639 checks, all pass. `--demo-timeline`: every part starts on the step the research simulation gives, and since
  2026-11-25 `tools/demo_timeline.py` prints those steps itself (all 21 starts and the opening credits'
  9 cues equal the Swift's). main is pushed to GitHub (the repository is PUBLIC: user, 2026-11-25; checked with `gh`), the pause and
  sound-output merge and the water background included (2026-11-25).
- Every scene was seen by the user in the running app. Nothing has been compared with the original
  program running.

## Next steps
0. DONE 2026-11-25: everything left was gone through with the user. Dropped items are listed under
   "Decisions in force"; what is still open is under "Open questions". The signed release (item 2)
   waits until the user comes back to it.
1. CODE REVIEW AND SIMPLIFY: DONE, merged and pushed (2026-11-25; merges 355d716 and a67eade; the user
   saw and tried the results in the app). The whole project was reviewed by six read-only agents;
   nothing was found wrong with the 1993 look or the timing. Fixed: the end scroller's stray "%" and
   the Troll's jump before restarting (both Modern look); damaged data files turned away at load;
   build.sh leaves no half-made app; the timeline tool prints steps; a dozen checks made to check what
   they say; the self-test's total pinned; the opening credits' Modern pictures made with the scene;
   unused code, stale comments, README checksums. And the two bigger findings:
   - Play Demo falling behind its music: the clock makes up stalls of up to 5 s inside Play Demo
     (`DemoScene.longestCatchUp`), and the picture and music PAUSE TOGETHER while the window cannot be
     seen or the Mac sleeps (the user chose pausing over playing on; `SceneView`, `AppModel.hidden`,
     `MusicPlayer.paused`).
   - The sound stopping when the output device changes: `MusicPlayer.rebuildOutput` on macOS's notice;
     a failure shows as NO SOUND in the window title (`MusicPlayer.problem`). The user found switching
     between the laptop's speakers and AirPods very quick.
   - Real-sound tests: `--demo-live 8 30 pause 3 4` and `--demo-live 8 30 rebuild 3` (each fails with
     its fix taken out). The self-test never uses the sound output.
   What the review left was dropped on 2026-11-25 (see "Decisions in force").
2. SIGNED RELEASE, later, when the user asks (decided 2026-11-25): the app is to be shared outside the
   App Store without a warning on other Macs, so it will be signed with a Developer ID certificate and
   notarised. The user has signed up for an Apple Developer account. Still to do then: the user creates
   the "Developer ID Application" certificate and an app-specific password (kept in the keychain, never
   in git); `build.sh` gets an optional release mode (sign with the hardened runtime, zip, `notarytool
   submit`, `stapler staple`); an app icon and a version number. `notarytool` and `stapler` are in the
   Command Line Tools (checked). The self-test stays in the released program (it costs little). Whether
   the GitHub repository goes public was a separate decision (it is public: 2026-11-25).
3. THE WATER BACKGROUND FROM POV-RAY: DONE and merged 2026-11-25 (merge 4a706e4; the user saw it in the
   app; main's app rebuilt, 637 checks pass there). Pushed to GitHub the same day.
   - The Modern look's background is `Data/Water/BACKGROUND-POVRAY.png` (2560x1600, 0.9 MB), made by
     `tools/water_background.py --render` from `WATER/KK.POV` with POV-Ray 3.7 (the same file every
     run). POV-Ray is a development tool only: the app and `build.sh` never run it.
   - What made 3.7 give the 1993 picture, both measured: the scene's black FOG (3.7 leaves fog out while
     the camera is inside the solid sky plane; `hollow` on the plane), and HALF A PIXEL (1.0 sampled each
     pixel at its lower left corner; the camera is nudged). `WATER/DATA.TGA`, a raw 160x100 POV-Ray 1.0
     output, shows Future Crew did not retouch the picture. All of it is on
     `docs/scenes/water-scroller.md`, "The background, rendered again".
   - Left over, not looked into further: the ripple highlights differ slightly (cause not found; reading
     POV-Ray 1.0's source might tell: a download, not done). `R1.POV`...`R5.POV` and `RGB.TGA` are not
     the versions that made the position tables, so the tables still cannot be made again.
   - If the balls' rims ever look soft on a bigger screen: render at 16x (`SCALE` in the tool; the
     check's numbers and checksum change).
4. THE GLENZ AND PLASMA TIMING: DONE and merged 2026-11-25 (merge b7617f2; the user saw it in the app:
   Play Demo from the title picture and from the rotozoomer, and the Plasma scene on its own; main's
   app rebuilt, 638 checks pass there). Pushed to GitHub the same day.
   - Read from the released programs: `GLENZ.EXE` is `GLENZ/V.EXE` and matches `MAIN.C`;
     `PLZPART.EXE` ends on its THIRD fall (`curpal==4`, `PLZ.C` says 5) and its fade memory starts as
     zeros. The user's videos agree (three plasmas, grey last, the cube right after; the tunnel almost
     at once after the glenz).
   - Play Demo: Glenz waits for 333 music ticks (glenz at cue + 450, was 335; the scene reads the
     counter); the plasma falls on ticks 723, 1491, 1875 (cue + 975, 2,008, 2,525), the third fall ends
     it, its first palette ends one level brighter; "Plasma cube" starts at step 24,056 (was 23,792),
     with 48 empty steps instead of 312. No other part start moved.
   - Plasma on its own: three palettes, falls at steps 976, 2,009 and 2,526, loop 2,588. Glenz on its
     own: unchanged on purpose (35-step pause).
   - The script's refresh counter (`DemoMusicState.frame`) and the tool's `frames|ticks` option are gone.
5. NEXT (user, 2026-11-25): EXPORT PLAY DEMO TO A VIDEO FILE. To be talked through with the user
   first; no plan agreed yet (the idea so far is under "Open questions" and in `docs/future-ideas.md`).
6. ALSO WANTED (user, 2026-11-25): REVISIT THE INTERFACE (sidebar, look switch, menus, window title)
   and see what could be better. First wish (user, 2026-11-25): THE DEMO PLAYS AT START-UP by default
   and choosing a scene becomes secondary. A plan was shown; not yet agreed.
7. The signed release (item 2) stays for later. Nothing else is planned.

## Open questions (not to be started unasked)
Gone through with the user on 2026-11-25; what was dropped is under "Decisions in force".
- EXPORT PLAY DEMO TO A VIDEO FILE for YouTube (user, 2026-11-25; wanted, not started; NEXT,
  to be talked through first). MODERN LOOK ONLY (the user's choice: the 1993 look's 70 pictures a second do not fit
  YouTube's 60). Idea as discussed, to be planned with the user first: a command that steps Play Demo
  with silently rendered music (as `--demo-timeline` does), draws each frame off-screen (as
  `--snapshot` does) at 60 a second with the Modern look's blend at each frame's exact moment, at
  2880x2160 (4:3; YouTube's "4K" quality), and pipes the frames and the rendered music to ffmpeg
  (installed; a development tool only, like POV-Ray: never needed by the app or `build.sh`). Needs a
  check that sound and picture stay in step in the exported file.
  It must NOT use the output-delay allowance (an exported file has no device delay).
- REVISIT THE INTERFACE (user, 2026-11-25; wanted, not discussed yet). See "Next steps", item 6.
- CLOSED on 2026-11-25 by the user (do not raise again unless one starts to show):
  - By eye, everything looks good at present, the 3D City's fades and camera roll and the Ships Fly-by's
    empty horizon included. The user may make another pass later.
  - No manual trim for AirPods: the delay macOS reports (160 ms) is good enough.
  - Switching the sound output in mid-demo over Bluetooth costs about half a second: not an issue.
  - The water scroller's ripple highlights: working fine as it is.
  - The repository is public, and the songs are fine to ship (settled 2026-11-25): `MUSIC0.S3M` and
    `MUSIC1.S3M` are files of Future Crew's own 2013 release (`../secondreality/MAIN`, under its
    UNLICENSE, "source code and data"), and the user notes the composers have welcomed other remakes.
  - `docs/future-ideas.md` was rewritten as a short list of what may come next (the old ideas are in
    the history).
  - The plasma page's two pictures were checked: byte for byte what the scene draws now at step 1,251
    (they were taken at step 1,000 before the sections grew longer).

## How to build and run
- `./build.sh` builds `build/SRMetal.app` (first builds libopenmpt, about 15 s the first time; run it once
  before a bare `swift build`). Needs only Apple's Command Line Tools, no Xcode. Shaders compile at start.
  It also clears Finder tags and retries the signing (the Documents folder is synced and re-tags the app).
- TWO COPIES TRAP: each worktree builds its own app, and macOS may start another copy with the same
  identity. After every merge into main, rebuild in the main folder. To be sure which copy starts:
  `open -n <full path to the .app> --args ...`.
- Start-up options after `--args`: `--scene <id>` (ids: `opening-credits ships-flyby explosion title-picture glenz-vectors
  dot-tunnel rings interference techno-bars troll switch-off mountain-scroller lens rotozoomer plasma
  plasma-cube bouncing-dots water-scroller sine-landscape jelly-logo city-3d end-picture credits
  end-scroller starfield`, or `play-demo`), `--look classic|modern`, `--sidebar hidden`, `--from <scene id | part 1-21>`
  (with `play-demo`), `--music on|off`.
- Commands (run `build/SRMetal.app/Contents/MacOS/SRMetal` directly; none opens a window):
  - `--selftest`: all checks (~40 s). `--selftest <word>`: only the groups whose label contains the word
    (a scene id, or `demo`, `music`, `core`), in a second or two.
  - `--snapshot <scene-id|play-demo> <modern|classic> <step> <file.png> [blend]`: a 960x720 picture.
  - `--motion-check <scene-id> <modern|classic> [first last] [--csv file]`: draws every step (Modern also
    half-way), lists jumps and one-picture-only pixels, times the steps.
  - `--demo-timeline`: runs Play Demo's script against silently rendered music (0.2 s) and compares every
    part's start with `tools/demo_timeline.py`. `--demo-live <start> <seconds> [sound] [delay] [pause <at> <for>] [rebuild <at>]`: the same with the
    real sound output (Claude cannot drive the app's window: launched from here it is not on screen).
  - `--scaler-compare <picture|file.png> <folder> [x y width] [--methods ...]`: labelled comparison sheets.
  - `--credits-match <picture 1-21> <scene id> [first last [stride]]`: the steps at which a scene's 1993
    look is most like a credits picture (to choose the Modern look's capture moments).
  - `--credits-captures <folder>`: renders the credits' Modern pictures (build.sh does this into the app).
  - `--music-info [--write <folder>]`, `--music-render`, `--music-play`: the songs.
  - `--visu-test list|<case>|compare|damaged`: the 3D engine's test cases.

## Housekeeping (2026-11-25)
- All finished branches were deleted (each fully merged) and the three older sessions' worktrees removed.
  Only `main` remains, plus the branch and worktree of whichever session is open.

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
  `Visu/` (3D models, animation), `Music/`, `OpeningCredits/` (horizon, font), `Credits/` (pictures,
  font), `EndScroller/` (text, font), `Lens/`, `Mountain/`, `Water/`.
- `artwork/original/`: every picture the demo shows, exported to PNG by `tools/art_export.py` (do not edit
  by hand); `rgb/` copies are what the app loads. Inventory: `artwork/README.md`.
- `tools/`: development-only Python (standard library only): one `<scene>_reference.py` per replayed
  scene, `demo_timeline.py` + `music_steps.c`, `art_export.py`, `water_background.py` (needs POV-Ray), `x86interp.py` (cannot run self-modifying code).
- `ThirdParty/libopenmpt` (unmodified source, the only dependency), `docs/` (see the end of this file).

## Changing or rebuilding a scene
All parts are built; this is the checklist when one is redone or a new one is added.
- Research the original and show the user a plan before code. Compare the source with the RELEASED
  program in `MAIN/DATA` (several differed): unpack it with `deark -m pklite`, and if the result is still
  packed, `deark -m lzexe` (ALKU.EXE was packed twice).
- `tools/<scene>_reference.py`: facts about the data, and a replay printing checksums at chosen steps.
- `Sources/SRMetal/Scenes/<Name>/`: model, scene (`DemoScene`), `<Name>Checks.swift`, one line in
  `CoreChecks.run`; a `SceneEntry` in `SceneCatalog.all` (demo order); in Play Demo, `DemoScript.steps`.
- Data that cannot be calculated: `Data/<Name>/` with a README, copied by `build.sh`.
- Docs: `docs/scenes/<name>.md` with pictures made by `--snapshot`, README, `docs/demo-timeline.md`, this file.
- The user looks at it in the app before it is merged.

## Decisions in force
- Swift + Metal + SwiftUI, built with Swift Package Manager from the command line; Command-Line-Tools-only
  (do NOT use `@State`, `@Observable` or other macro-based features: the macro plug-in ships only with
  Xcode). Keep view state in `AppModel`.
- Licence: the Unlicense, matching the original. The GitHub repository is public (2026-11-25).
- Scenes are re-implemented from the original source's logic, not copied from the port. The port has
  quiet differences (the water's fade length and red-first slip): never take a number from it unchecked.
- WHAT COUNTS AS RIGHT (user, 2026-11-25): Play Demo lines up with the MUSIC, and the 1993 look is
  faithful to the ORIGINAL CODE. It will never be perfect and need not be: real machines differed (a
  486 DX2-66 visibly struggles to load some parts), so a video shows what one machine did, not what
  the code says. Do not chase a video's load pauses or frame rate; do use it for waits that follow the
  music, which are the same on every machine.
- Every scene is stepped at 70 per second; the Modern look blends between steps. Every canvas is shown 4:3.
- 1993 look = exact, including the original's slips. Modern look may stray where it is better; record each
  straying on the scene's page.
- A picture re-made from its original source ships as a FILE made by a development tool (the water
  background, POV-Ray): nothing new may be needed by the app or `build.sh` without the user's say.
- Calculate tables from the original's generator where that reproduces the file exactly; ship the file
  (with a README saying why) where it cannot be remade (lens table 4, the scrollers' position tables).
- Large binary original data is loaded from `Data/`, not written into Swift source.
- NO AI-UPSCALED ART (user, 2026-11-24). Modern pictures are the originals through Super-xBR 8x, made at
  run time; re-making pictures from source is welcome where possible.
- Text and lettering in the Modern look: decided per part with the user from comparison sheets: opening
  credits in Superclarendon stretched to the 1993 line widths (the Dolby logo through Super-xBR); credits
  in DIN Condensed Bold; end scroller in Superclarendon; mountain text and water sword through Super-xBR
  (they are pictures, not fonts). Text parts use the RELEASED texts and fonts (the end scroller's from the
  port's data).
- Music: the ORIGINAL tracker songs played live with libopenmpt (their pattern data is scrambled;
  unscrambled at load). Song 1 always at tempo 120. Music plays only with Play Demo; sidebar scenes are
  silent and loop; the Music menu has only Mute (the song keeps running underneath). Sound follows the look.
- PLAY DEMO FOLLOWS THE MUSIC AS HEARD (2026-11-25): with Music > Allow for Output Delay on (the
  default; remembered in the preferences) the player reports the position whose sound left for the
  output device that device's reported delay ago (`Music/PositionHistory.swift`,
  `MusicPlayer.deviceOutputDelay`: the device's latency plus its stream's; the speakers report 15.6 ms,
  AirPods 160 ms). Off, it reports the newest rendered position. `--demo-live ... delay` tests with it on.
- Fewer dependencies is better: libopenmpt is the only one (static, built from source by `build.sh`).
- DROPPED FOR GOOD (user, 2026-11-25; do not raise again unless one starts to show in the app). None
  was visible. Code review findings 3, 5 and 6; work repeated on every drawn frame instead of once per
  step; the two low-memory crash paths; the duplicated code (text scenes' shaders and loaders, palette
  conversions, the tools' PNG writers and ways of finding the original source: several tools still need
  `SR_ORIGINAL` set when run from a worktree); `tools/x86interp.py` treating any `imul` as the
  one-operand form; the reference tools not checking the EXE's hash; the Lens, Mountain and Water
  loaders reporting a damaged file as "missing", and no load check on the water's sword values; the end
  scroller making each line's picture on the frame it enters; the opening credits' 50 MB of Modern
  pictures held in the 1993 look; `--demo-timeline` printing the Python tool's line; the Troll flash
  possibly one refresh late; rewriting history to shrink the repository (not needed: the old pictures
  are in Git LFS; `git lfs prune` would free 168 MB on this Mac, not run); skipping the black waits
  when Play Demo starts "from here"; the jelly logo's white border; the third "Reimagined" look.

## Working rules learned (each one cost a mistake once)
- When the source cannot answer, look in the compiled or released files first (the music counter's
  meaning was settled from the player's library, not by simulation).
- STEP PAIRING (which step shows what the program just set up) is worked out from each part's own source
  and its copper or wait routine; never assume it equals another part's.
- A scene on its own has no music: NO stand-in pause where the demo waits for a cue, unless the original
  really shows one (the jelly logo's invented pause was removed; the water's 7.4 s still picture is real).
- MEASURE standalone lengths from the script's silent run; do not estimate. A scene's Play Demo check
  uses the SCRIPT's numbers, not the model's own constants.
- Break and restore a detail with exact edits, never `git checkout` on the file (it would also throw away
  the uncommitted fix being proven). Use the optimised build for the filtered self-test (`swift build -c
  release`, then `.build/release/SRMetal --selftest <word>`): the debug build takes minutes; its one
  expected failure is the credits' captured pictures, which only the app bundle has.
- The full self-test fails if its total is not `SelfTest.expectedChecks`: change that number with
  every check added or removed. It is how a check that silently stops running gets noticed.
- Every new check is proven to fail with the detail broken on purpose, then restored, using the filtered
  self-test (`--selftest <scene id>`); run the full self-test and `--demo-timeline` once before each
  commit and after each merge (user, 2026-11-25).
- Scratch scripts and their output stay OUT of the repository (the session's scratch folder; comparison
  sheets for the user go in `build/scaler-compare/`, which git ignores).
- `docs/images/window.png` is a capture of the app's window only, never the desktop.

## Traps (facts that caused mistakes)
- The music frame counter (`dis_getmframe`) counts MUSIC TICKS, not refreshes (`MAIN/STMIK.300`).
- A beat that looks off: ask FIRST whether the user is on Bluetooth headphones (2026-11-25: a day's
  "desync" was AirPods). For the record, and nothing to change: `TECHNO/KOE.C` flashes on row 7 of
  every 8, and the player reports row, section and "plus" through a delay ring (51C5h, set up at
  2AC1h): none for output modes 2 and 7, ten polls for the mixing cards.
- The compiled files in a source folder need not be the released build: `PLZPART/PLZ.OBJ` tests
  `curpal==5` as `PLZ.C` does, the released `PLZPART.EXE` tests 4. Read the unpacked program itself.
- The plasma's fourth palette and section exist only in `PLZ.C`; the released part has three. Do not
  put them back.
- `GLENZ.EXE` after `deark -m pklite` is still packed by the linker (`link /E`): `deark -m exepack`
  gives the 399,792-byte program whose addresses match `GLENZ/V.MAP`.
- Jump the music by rendering and throwing away (`TrackerSong.skip`), never by libopenmpt's seek-by-seconds
  (it lands on a row start and counts song 1's later sections from the wrong place).

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
