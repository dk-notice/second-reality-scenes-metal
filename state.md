# Project state

Last updated: 2026-11-27 (the documentation was cleaned up and checked against the code)

## Goal
A native macOS app that re-creates Second Reality (Future Crew, 1993) from scratch, drawn on the graphics
chip with Metal: every part as a scene, and the whole demo with its music ("Play Demo"). Each scene has
two looks: Modern (full resolution, smooth) and 1993 (original pixels, usually 320x200; 70 steps per
second). The original source is public domain and lives in `../secondreality` for reference; the existing
complete C++ port is in `../SecondRealityPlusPlus`; the user's copy of the released demo is in
`../second-reality-original`.

## Status (2026-11-27)
- Development is finished. 25 scenes work in both looks, listed in the demo's order under a "Scenes"
  heading, with Play Demo as the list's first row. The Hidden Starfield is last (it is not in the demo).
  Each scene's page (`docs/scenes/`) says what was built and checked. The user has seen every scene in
  the running app. Nothing has been compared with the original program running.
- With no `--scene` the app starts in Play Demo with the music on and the list hidden. Escape or Stop
  Demo opens the list on the scene the demo was showing. Play Demo runs all 19 parts with the original
  music, changing parts on the original's music cues. It ENDS by itself at step 68,673 (16:21.0), the
  end scroller's `%` line. The picture stays black, Play Demo stays chosen, and the scene list opens.
- On their own, some scenes' lengths differ from the original parts on purpose: Glenz 2,360, Plasma
  2,588, Plasma Cube 2,048, Sine Landscape 2,048, 3D City 3,639, Ships 592.
- Self-test: 652 checks, all pass. `--demo-timeline`: every part starts on the step
  `tools/demo_timeline.py` gives.
- The video export works. The Modern-look video of the whole demo is on YouTube.
- main is on GitHub. The repository is PUBLIC.
- The app is Apple Silicon only (arm64) and needs macOS 15. It is signed ad hoc, so other Macs warn
  about it.

## Next steps
1. DONE 2026-11-27: the documentation clean-up.
   - `docs/dev-notes.md` was removed. Its few facts not found elsewhere were moved first; the file
     stays in git history.
   - The dated work logs and code-review sections were removed from the docs.
   - Every page was checked against the code.
2. DONE 2026-11-27: the plasma's self-test pictures now land in each of its three falls (17
   checkpoints in `Core/DemoScene.swift`); with the fall broken in the drawing only, six fail.
3. SIGNED RELEASE, when the user asks. The app is to be shared outside the App Store without a warning,
   so it is signed with a Developer ID certificate and notarised. The user has an Apple Developer
   account.
   - The user's steps:
     - Create a "Developer ID Application" certificate (Keychain Access makes the request; upload it at
       developer.apple.com; install the downloaded certificate). None is installed yet (checked
       2026-11-27).
     - Make an app-specific password at account.apple.com. Store it with `xcrun notarytool
       store-credentials`, which keeps it in the keychain, never in git.
     - Give Claude the Team ID.
   - Claude's steps:
     - Replace the bundle identifier `local.srmetal` and set the version to 1.0.
     - Make an app icon from one of the demo's own pictures (no AI art); the user picks which.
     - Add an optional release mode to `build.sh`: sign with the hardened runtime, zip, `notarytool
       submit`, `stapler staple`. Both tools are in the Command Line Tools (checked).
     - Check the result with `spctl` and the self-test. The self-test stays in the released program.
   - Requirements to tell the friend: Apple Silicon, macOS 15 or later. An Intel build would be an
     extra step and cannot be tested here.
4. `docs/images/window.png` (the README's picture) is out of date because the list has a new first row.
   It needs a screenshot from the user, of the window only.
5. Interface ideas: only if the user brings them up.

## How to build and run
- `./build.sh` builds `build/SRMetal.app`. The first build also builds libopenmpt (about 15 s); run it
  once before a bare `swift build`. It needs only Apple's Command Line Tools, no Xcode. Shaders compile
  at start. The script clears Finder tags and retries the signing (the Documents folder is synced and
  re-tags the app).
- TWO COPIES TRAP: each worktree builds its own app, and macOS may start another copy with the same
  identity. After every merge into main, rebuild in the main folder. To be sure which copy starts:
  `open -n <full path to the .app> --args ...`.
- Start-up options after `--args`:
  - `--scene <id>`. The ids: `opening-credits ships-flyby explosion title-picture glenz-vectors dot-tunnel
    rings interference techno-bars troll switch-off mountain-scroller lens rotozoomer plasma plasma-cube
    bouncing-dots water-scroller sine-landscape jelly-logo city-3d end-picture credits end-scroller
    starfield`, or `play-demo`.
  - `--look classic|modern`, `--sidebar hidden|shown`, `--music on|off`.
  - `--from <scene id | part 1-21>`, used with `play-demo`.
  - `--end-scroller-steps <n>`: a quick trial of the demo's end, for example `--scene play-demo --from
    end-scroller --end-scroller-steps 350`.
- Commands (run `build/SRMetal.app/Contents/MacOS/SRMetal` directly; none opens a window):
  - `--selftest`: all checks (about 40 s). `--selftest <word>`: only the groups whose label contains the
    word (a scene id, or `demo`, `music`, `core`), in a second or two.
  - `--snapshot <scene-id|play-demo> <modern|classic> <step> <file.png> [blend]`: a 960x720 picture.
  - `--motion-check <scene-id> <modern|classic> [first last] [--csv file]`: draws every step (the Modern
    look also half-way between steps), lists jumps and pixels that show for one picture only, and times
    the steps.
  - `--export-video plan | sound <file.wav> [seconds] | pictures [seconds] | stills <folder> <picture
    number> ...`: the raw material of the video export. Run it through `python3 tools/export_video.py
    [--seconds N] [file.mov]` (needs ffmpeg) and check the result with `python3 tools/check_video.py
    [--seconds N] [file.mov]`. A full export takes about 8 minutes and makes about 34 GB in `~/Movies/`.
  - `--demo-timeline`: runs Play Demo's script against silently rendered music (0.2 s) and compares
    every part's start with `tools/demo_timeline.py`.
  - `--demo-live <start> <seconds> [sound] [delay] [pause <at> <for>] [rebuild <at>]`: the same with the
    real sound output. Claude cannot drive the app's window: launched from here it is not on screen.
  - `--scaler-compare <picture|file.png> <folder> [x y width] [--methods ...]`: labelled comparison
    sheets.
  - `--credits-match <picture 1-21> <scene id> [first last [stride]]`: the steps at which a scene's 1993
    look is most like a credits picture.
  - `--credits-captures <folder>`: renders the credits' Modern pictures (`build.sh` does this into the
    app).
  - `--music-info [--write <folder>]`, `--music-render`, `--music-play`: the songs.
  - `--visu-test list|<case>|compare|damaged`: the 3D engine's test cases.

## Layout
- `Sources/SRMetal/Core/`: shared by all scenes.
  - `DemoScene.swift`: the scene contract and `SceneCatalog`.
  - `Renderer.swift`: the clock and the two looks.
  - `Shaders.swift`.
  - `IndexedCanvas.swift`: a picture of colour numbers through a palette, as on a VGA card.
  - `PictureLayer.swift`: `ScenePicture` and fades.
  - `PictureScaler.swift`: Super-xBR 8x.
  - `ScrollTables.swift`, `Math3D.swift`, `SmoothTriangles.swift`, `DataFolder.swift`.
  - `Visu/`: the 3D engine.
- `Sources/SRMetal/Scenes/<Name>/`: one folder per scene.
  - The model: the original's logic, with no drawing.
  - The scene: the drawing, both looks.
  - `<Name>Checks.swift`.
- `Sources/SRMetal/Demo/`:
  - `DemoSequencer.swift`: `DemoScript.steps`, the running order, step for step as
    `tools/demo_timeline.py`.
  - `DemoRunScene.swift`: Play Demo as one scene.
  - `DemoChecks.swift`.
- `Sources/SRMetal/Music/`: the libopenmpt wrapper, the player, and `MusicPosition`.
- `Sources/SRMetal/App/`:
  - The window, sidebar, commands and `VideoExport.swift`.
  - `SelfTest.swift`: per-scene generic checks.
  - `CoreChecks.swift`: `run` calls every other check. The other checks live next to what they check,
    as extensions of `CoreChecks`.
- `Data/`: original files loaded at run time. Each folder has a README saying what the files are, why
  they ship, and their SHA-256.
- `artwork/original/`: every picture the demo shows, exported to PNG by `tools/art_export.py`. Do not
  edit them by hand. The `rgb/` copies are what the app loads.
- `tools/`: development-only Python, standard library only.
  - One `<scene>_reference.py` per replayed scene.
  - `demo_timeline.py` and `music_steps.c`.
  - `art_export.py`.
  - `water_background.py` (needs POV-Ray).
  - `export_video.py` and `check_video.py` (need ffmpeg).
  - `x86interp.py`.
- `ThirdParty/libopenmpt`: unmodified source, the only dependency.

## Changing or rebuilding a scene
- Research the original and show the user a plan before writing code.
- Compare the source with the RELEASED program in `MAIN/DATA`. Unpack it with `deark -m pklite`; if the
  result is still packed, use `deark -m lzexe` or `deark -m exepack`.
- Pieces:
  - `tools/<scene>_reference.py`.
  - The scene folder with its checks, and one line in `CoreChecks.run`.
  - A `SceneEntry` in `SceneCatalog.all`.
  - `DemoScript.steps`.
  - `Data/<Name>/` with a README, for data that cannot be calculated.
  - The docs: `docs/scenes/<name>.md`, the README, `docs/demo-timeline.md`.
- The user looks at it in the app before it is merged.

## Decisions in force
- Swift + Metal + SwiftUI, built with Swift Package Manager from the command line, with the Command Line
  Tools only. Do NOT use `@State`, `@Observable` or other macro-based features: the macro plug-in ships
  only with Xcode. Keep view state in `AppModel`.
- Licence: the Unlicense, matching the original. The songs (`MUSIC0.S3M`, `MUSIC1.S3M`) are from Future
  Crew's own 2013 release under its Unlicense and are fine to ship.
- Scenes are re-implemented from the original source's logic, not copied from the port. The port has
  quiet differences: never take a number from it unchecked.
- WHAT COUNTS AS RIGHT: Play Demo lines up with the MUSIC, and the 1993 look is faithful to the ORIGINAL
  CODE. Real machines differed, so do not chase a video's load pauses or frame rate. Do use a video for
  waits that follow the music.
- Every scene is stepped at 70 per second, and the Modern look blends between steps. Every canvas is
  shown 4:3.
- The 1993 look is exact, including the original's slips. The Modern look may stray where it is better;
  record each straying on the scene's page.
- Calculate tables from the original's generator where that reproduces the file exactly. Where it cannot
  (lens table 4, the scrollers' position tables), ship the file with a README saying why.
- A picture re-made from its original source ships as a FILE made by a development tool (the water
  background, POV-Ray). Nothing new may be needed by the app or `build.sh` without the user's say.
- Large binary original data is loaded from `Data/`, not written into Swift source.
- NO AI-UPSCALED ART. Modern pictures are the originals through Super-xBR 8x, made at run time.
- Text in the Modern look:
  - opening credits: Superclarendon, stretched to the 1993 line widths
  - credits: DIN Condensed Bold
  - end scroller: Superclarendon
  - mountain text and water sword: through Super-xBR
  - Text parts use the RELEASED texts and fonts.
- Music:
  - The ORIGINAL tracker songs, played live with libopenmpt and unscrambled at load. Song 1 is always at
    tempo 120.
  - Music plays only with Play Demo. Sidebar scenes are silent and loop.
  - The Music menu has Mute and Allow for Output Delay.
  - Sound follows the look.
- PLAY DEMO FOLLOWS THE MUSIC AS HEARD. With Allow for Output Delay on (the default), the player
  reports the position that is being heard after the device's reported delay
  (`Music/PositionHistory.swift`). The speakers report 15.6 ms and AirPods 160 ms. No manual trim is
  wanted.
- Play Demo makes up clock stalls of up to 5 s (`DemoRunScene.longestCatchUp`). Picture and music PAUSE
  TOGETHER while the window cannot be seen or the Mac sleeps. The output is rebuilt when the sound
  device changes, and a failure shows as NO SOUND in the window title.
- THE DEMO'S END opens the scene list and must NOT go to the End Scroller scene: that starts the text
  again and looks like a loop. On its own, the End Scroller scene still loops.
- VIDEO EXPORT:
  - The whole demo only, Modern look only, command line only.
  - 2880x2160 at 60 pictures a second, ProRes 422, 2-channel PCM at 44,100 Hz (630 samples a step), in
    a .mov written to `~/Movies/`.
  - Frame k is drawn at step 7k div 6 with blend (7k mod 6)/6.
  - The program writes raw frames and a WAV, and only the scripts in `tools/` run ffmpeg. There is no
    fade at the end.
- Fewer dependencies is better: libopenmpt is the only one, static and built from source by `build.sh`.
- Closed by the user (do not raise again unless one starts to show):
  - everything looks right by eye (the 3D City's fades and roll, the Ships' empty horizon)
  - Bluetooth switching costs about half a second
  - the water's ripple highlights are fine
- DROPPED FOR GOOD (none was visible):
  - the remaining code-review tidy-ups: work repeated per drawn frame instead of per step, duplicated
    code, the low-memory crash paths, the loaders' "missing" against "damaged" wording
  - `x86interp.py`'s `imul`
  - the reference tools not checking the EXE's hash
  - the end scroller making each line's picture on its first frame
  - the opening credits' Modern pictures held in memory in the 1993 look
  - the Troll flash possibly one refresh late
  - rewriting history to shrink the repository (`git lfs prune` was not run)
  - skipping the black waits when Play Demo starts "from here"
  - the jelly logo's white border
  - a third "Reimagined" look

## Working rules learned (each one cost a mistake once)
- When the source cannot answer, look in the compiled or released files first.
- STEP PAIRING (which step shows what the program just set up) is worked out from each part's own source
  and its copper or wait routine. Never assume it equals another part's.
- A scene on its own has no music: NO stand-in pause where the demo waits for a cue, unless the original
  really shows one.
- MEASURE standalone lengths from the script's silent run; do not estimate them. A scene's Play Demo
  check uses the SCRIPT's numbers, not the model's own constants.
- Break and restore a detail with exact edits, never `git checkout` on the file.
- Use the optimised build for the filtered self-test (`swift build -c release`, then
  `.build/release/SRMetal --selftest <word>`). Its one expected failure is the credits' captured
  pictures, which only the app bundle has.
- The full self-test fails if its total is not `SelfTest.expectedChecks`: change that number with every
  check added or removed.
- Every new check is proven to fail with the detail broken on purpose, then restored. Run the full
  self-test and `--demo-timeline` once before each commit and after each merge.
- A YouTube recording can be measured: open it in the built-in browser, seek the video with JavaScript,
  read small fingerprints of frames from a canvas, and match them to reference pictures.
- Scratch scripts and their output stay OUT of the repository. Comparison sheets for the user go in
  `build/scaler-compare/`, which git ignores.
- `docs/images/window.png` is a capture of the app's window only, never the desktop.

## Traps (facts that caused mistakes)
- The music frame counter (`dis_getmframe`) counts MUSIC TICKS, not refreshes.
- A beat that looks off: ask FIRST whether the user is on Bluetooth headphones.
- The compiled files in a source folder need not be the released build (`PLZPART.EXE` tests
  `curpal==4`, where `PLZ.C` and `PLZ.OBJ` test 5). Read the unpacked released program. The plasma has
  three palettes; do not put the fourth back.
- `GLENZ.EXE` after `deark -m pklite` is still packed by the linker: `deark -m exepack` gives the program
  whose addresses match `GLENZ/V.MAP`.
- Jump the music by rendering and throwing away (`TrackerSong.skip`), never by libopenmpt's
  seek-by-seconds.
- ffmpeg's DEFAULT conversion back to red-green-blue is 2-3 levels dark. Decode with `accurate_rnd` when
  checking a video; the file itself is right.

## Where the detail is
- `docs/scenes/<name>.md`: one page per scene (how the original did it, how this version does, checks,
  differences).
- `docs/how-it-works.md`, `docs/original-demo.md`, `docs/demo-timeline.md` (every part's start, end and
  cue with its source lines), `docs/visu-engine.md`, `docs/future-ideas.md`.
- `README.md`: for a reader of the repository.
- The older work notes are in git history: the file `docs/dev-notes.md`, removed 2026-11-27.
