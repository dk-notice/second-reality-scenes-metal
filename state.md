# Project state

Last updated: 2026-11-25 (whole-project code review merged into main; not pushed yet)

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
  scenes' lengths differ from the original parts on purpose: Glenz 2,360, Plasma 2,323, Plasma Cube
  2,048, Sine Landscape 2,048, 3D City 3,639, Ships 592.
- Self-test: 634 checks, all pass. `--demo-timeline`: every part starts on the step the research simulation gives, and since
  2026-11-25 `tools/demo_timeline.py` prints those steps itself (all 21 starts and the opening credits'
  9 cues equal the Swift's). GitHub (private repository) has main up to 00faa8a; the code review's merge
  (355d716) and what follows are NOT pushed yet: ask the user first.
- Every scene was seen by the user in the running app. Nothing has been compared with the original
  program running.

## Next steps
1. CODE REVIEW AND SIMPLIFY: DONE and merged into main (2026-11-25, merge 355d716; main's app rebuilt,
   634 checks pass, every part on time; the user saw the result in the app). The whole project was
   reviewed by six read-only agents; nothing was found wrong with the 1993 look or the timing. Fixed:
   the end scroller's stray "%" and the Troll's jump before restarting (both Modern look); damaged data
   files turned away at load; build.sh leaves no half-made app; the timeline tool prints steps; a dozen
   checks made to check what they say; the self-test's total pinned; the opening credits' Modern
   pictures made with the scene; unused code, stale comments, README checksums. What was left is under
   "Open questions".
   STILL OPEN from the review, each needs a plan shown to the user first: Play Demo falling behind the
   music when the window stops drawing (the step clock drops pauses over 0.25 s;
   `Renderer.longestCatchUp`), and the sound stopping for good when the output device changes (nothing
   restarts `AVAudioEngine`; only the user can test it, with real headphones).
2. SIGNED RELEASE, later, when the user asks (decided 2026-11-25): the app is to be shared outside the
   App Store without a warning on other Macs, so it will be signed with a Developer ID certificate and
   notarised. The user has signed up for an Apple Developer account. Still to do then: the user creates
   the "Developer ID Application" certificate and an app-specific password (kept in the keychain, never
   in git); `build.sh` gets an optional release mode (sign with the hardened runtime, zip, `notarytool
   submit`, `stapler staple`); an app icon and a version number. `notarytool` and `stapler` are in the
   Command Line Tools (checked). The self-test stays in the released program (it costs little). Whether
   the GitHub repository goes public is a separate decision.
3. Then polish, only when the user asks: the open questions below (the user chose to leave them for now).

## Open questions (not to be started unasked)
- Glenz and the plasma still read the music frame counter as screen refreshes. In ticks the Glenz pause
  would be ~1.6 s longer, and the plasma as its source stands would run past the plasma cube's cue: the
  released `PLZPART.EXE` may differ from the source (its pklite unpack came out damaged; not read yet;
  it may be packed twice, as ALKU.EXE was: try `deark -m lzexe` on the result).
  See `docs/demo-timeline.md`, "Later found: it counts music ticks".
- Code review findings left as they are: (3) a resumed part's name is lost if a new part starts on the
  first step; (5) the music-skip check runs only at 44.1 kHz, the player at 48; (6) a failed
  `SilentMusic.play` keeps the old song's details. All harmless today.
- Left from the whole-project review (2026-11-25), none visible today: work repeated on every drawn frame
  instead of once per step (the credits' 1993 text, a plasma buffer, Plasma Cube, Lens, Bouncing Dots,
  Switch Off); the 3D City's Modern fades possibly a frame or two early (one shared palette buffer);
  two low-memory crash paths (`VisuModernRenderer.makeTargets`, `PictureScaler`); duplicated code
  (the three text scenes' shaders and loaders, palette conversions, the tools' PNG writers and four
  ways of finding the original source: several tools need `SR_ORIGINAL` set when run from a worktree);
  `tools/x86interp.py` treats any `imul` as the one-operand form (no source uses another today);
  the reference tools do not check the hash of the EXE they unpack.
- Left from /simplify (2026-11-25): the Lens, Mountain and Water loaders return nil for a damaged file, so
  it is reported as "missing" (make them throw, as Credits and Visu do); the water's sword values have no
  load check like the mountain text's; the end scroller still makes each line's picture on the frame the
  line enters; the opening credits hold about 50 MB of Modern pictures even in the 1993 look (made with
  the scene so none is late on its cue); `--demo-timeline` could print the same "Part starts (steps)"
  line as the Python tool, to compare by eye.
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
    part's start with `tools/demo_timeline.py`. `--demo-live <start> <seconds> [sound]`: the same with the
    real sound output (Claude cannot drive the app's window: launched from here it is not on screen).
  - `--scaler-compare <picture|file.png> <folder> [x y width] [--methods ...]`: labelled comparison sheets.
  - `--credits-match <picture 1-21> <scene id> [first last [stride]]`: the steps at which a scene's 1993
    look is most like a credits picture (to choose the Modern look's capture moments).
  - `--credits-captures <folder>`: renders the credits' Modern pictures (build.sh does this into the app).
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
  `Visu/` (3D models, animation), `Music/`, `OpeningCredits/` (horizon, font), `Credits/` (pictures,
  font), `EndScroller/` (text, font), `Lens/`, `Mountain/`, `Water/`.
- `artwork/original/`: every picture the demo shows, exported to PNG by `tools/art_export.py` (do not edit
  by hand); `rgb/` copies are what the app loads. Inventory: `artwork/README.md`.
- `tools/`: development-only Python (standard library only): one `<scene>_reference.py` per replayed
  scene, `demo_timeline.py` + `music_steps.c`, `art_export.py`, `x86interp.py` (cannot run self-modifying code).
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
- Text and lettering in the Modern look: decided per part with the user from comparison sheets: opening
  credits in Superclarendon stretched to the 1993 line widths (the Dolby logo through Super-xBR); credits
  in DIN Condensed Bold; end scroller in Superclarendon; mountain text and water sword through Super-xBR
  (they are pictures, not fonts). Text parts use the RELEASED texts and fonts (the end scroller's from the
  port's data).
- Music: the ORIGINAL tracker songs played live with libopenmpt (their pattern data is scrambled;
  unscrambled at load). Song 1 always at tempo 120. Music plays only with Play Demo; sidebar scenes are
  silent and loop; the Music menu has only Mute (the song keeps running underneath). Sound follows the look.
- Fewer dependencies is better: libopenmpt is the only one (static, built from source by `build.sh`).

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
- The full self-test fails if its total is not `SelfTest.expectedChecks` (634): change that number with
  every check added or removed. It is how a check that silently stops running gets noticed.
- Every new check is proven to fail with the detail broken on purpose, then restored, using the filtered
  self-test (`--selftest <scene id>`); run the full self-test and `--demo-timeline` once before each
  commit and after each merge (user, 2026-11-25).
- Scratch scripts and their output stay OUT of the repository (the session's scratch folder; comparison
  sheets for the user go in `build/scaler-compare/`, which git ignores).
- `docs/images/window.png` is a capture of the app's window only, never the desktop.

## Traps (facts that caused mistakes)
- The music frame counter (`dis_getmframe`) counts MUSIC TICKS, not refreshes (`MAIN/STMIK.300`).
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
