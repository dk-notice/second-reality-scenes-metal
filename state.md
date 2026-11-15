# Project state

Last updated: 2026-11-14

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
- No music.

## How to build and run
- `./build.sh` builds `build/SRMetal.app`.
- `open build/SRMetal.app` runs it. Start-up options go after `--args`: `--look classic|modern`,
  `--scene dot-tunnel|rings|interference|techno-bars|bouncing-dots|plasma|starfield|sine-landscape|plasma-cube|glenz-vectors|ships-flyby|city-3d`, `--sidebar hidden`.
- `build/SRMetal.app/Contents/MacOS/SRMetal --selftest` runs the checks without opening a window.
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
- `build/SRMetal.app/Contents/MacOS/SRMetal --visu-test list` names the 3D engine's 109 test cases;
  `--visu-test <case> <modern|classic> <file.png> [blend]` saves a 960x720 picture of one;
  `--visu-test compare` prints how far the modern look is from the 1993 one for each case.
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
  (`Thumbnails.swift`), picture rendering (`Snapshot.swift`), self-test.

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
- Original data is loaded from files, not Swift source, when it is large and binary (decided for the 3D
  engine, 2026-11-14): kept in `Data/`, copied into the app by `build.sh`, found at run time by
  `VisuData`. Still no new build tools or dependencies.
- Scenes may implement `prepare(commands:frame:)` (empty by default) to draw into a picture of their own
  before the main pass. Added for the 3D engine's depth buffer, so the main pass and the other scenes'
  pipelines did not have to change.
- `docs/images/window.png` is a capture of the app's window only (`screencapture -l <window id>`), never
  the desktop.

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
- Not verified against a running original: the plane/chessboard layout, the exact band line, which pan
  value pairs with which line, and that timetable "music frames" are 1/70 s. See docs/scenes/plasma.md.
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
  but bits 32-47 of the product; integer perspective tables) and `IndexedCanvas` shows it. Checked by reading
  the assembly plus an independent Python re-run with matching checksums; NOT compared with a running original.
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
  `sin()` for the start-up tables; the modern look beyond still pictures.
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
- Not verified: against a running original or a recording; the music timings; the modern look in motion.
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
  ported step for step. Verified against `tools/visu_reference.py`, which runs the assembly as text: 109 test
  pictures identical (15 ships frames, 31 city frames, 4 multi-frame runs, 59 single-object and clipping
  cases), no faults. The C parts were ported by reading (Python and Swift, same author).
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
- Classic look: every animation frame drawn once, in order, by one engine. Matches all 31
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
The planned list of scenes is complete (2026-11-14).
- NEXT: the user's planned code review, in progress. Techno Bars is DONE (2026-11-14; 4 fixes, see its
  notes). Still to do: run `/code-review` over the other scenes and `Core/`, paying most
  attention to what each scene page lists under "What was not checked" (ports checked by reading only:
  Bouncing Dots, the C parts of the 3D scenes; the plasma's plane layout; the VISU scene
  programs' ordering and pacing) and to the code shared between scenes.
- Waiting on the user, by eye in the running app: the 3D City's fades (`City3DModel.fadeInSteps`,
  `fadeOutSteps`, `darkSteps`) and whether the evened-out camera roll looks right
  (`City3DModel.smoothCameraRoll`); Ships Fly-by's pause (`ShipsFlybyModel.pauseSteps`) and scaled-up background.
- After the review: the undecided ideas in `docs/future-ideas.md` (a third "Reimagined" look per scene;
  the whole demo with music and upscaled artwork). The user will decide; do not start them unasked.
- Possible polish: the Dot Tunnel sidebar picture is rather dim (thin dots at small size).
- `--motion-check` now exists for every scene; only Ships Fly-by and the 3D City have been through it.
