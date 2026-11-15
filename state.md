# Project state

Last updated: 2026-11-14

## Goal
A native macOS app that re-creates scenes from Second Reality (Future Crew, 1993) from scratch,
drawn on the graphics chip with Metal. Each scene has two looks: Modern (full resolution, smooth)
and 1993 (320x200 pixels, 70 steps per second). The original source is public domain and lives in
`../secondreality` for reference; the existing complete port is in `../SecondRealityPlusPlus`.

## Status
- Five scenes work in both looks: Dot Tunnel, Rings, Interference, Techno Bars, and Bouncing Dots. (Rings and Interference were one
  back-to-back sequence in the original; split into two scenes at the user's request, 2026-11-14.)
- The scene framework has now carried a second, different kind of scene (full-canvas shader) without changes
  to its design; only small additions (shared sine table, shared full-canvas vertex shader, generic self-test).
- Documentation is in `README.md` and `docs/` (how the app works, how the original demo was built, and one
  page per scene comparing the original with this version). Keep it up to date: every new scene gets a page.
- No scene-picker UI yet. Menu "Scene" has Switch Look (L) and Next/Previous Scene (right/left arrow keys).
- No music.

## How to build and run
- `./build.sh` builds `build/SRMetal.app`.
- `open build/SRMetal.app` runs it. Start-up options go after `--args`: `--look classic|modern`,
  `--scene dot-tunnel|rings|interference|techno-bars|bouncing-dots|starfield`.
- `build/SRMetal.app/Contents/MacOS/SRMetal --selftest` runs the checks without opening a window.
- `build/SRMetal.app/Contents/MacOS/SRMetal --snapshot <scene-id> <modern|classic> <step> <file.png>` saves a
  960x720 picture without opening a window. The pictures in `docs/images/` were made this way (steps:
  dot-tunnel 500, rings 300, interference 700, techno-bars 310, bouncing-dots 1300).
- Needs only Apple's Command Line Tools (no Xcode). Shaders are compiled when the app starts.

## Layout
- `Sources/SRMetal/Core/` shared by all scenes: `DemoScene.swift` (the scene contract and the scene list),
  `Renderer.swift` (clock and the two looks), `Shaders.swift`.
- `Core/IndexedCanvas.swift` shows a picture of colour numbers through a palette, as a VGA card did. Use it for
  the classic look of scenes best re-created by replaying the original steps on the processor.
- `Sources/SRMetal/Scenes/<Name>/` one folder per scene.
- `Sources/SRMetal/App/` window, menu, self-test.

## Adding a scene
1. Create `Sources/SRMetal/Scenes/<Name>/` with a class that conforms to `DemoScene` (`reset`, `tick`, `draw`).
2. Add one `SceneEntry` to `SceneCatalog.all` in `Core/DemoScene.swift`.
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
- Recommended scene picker (not built yet): a standard Mac sidebar listing scenes, hidden in fullscreen,
  plus the existing menu and keyboard shortcuts.

## Dot Tunnel notes
- Modern look keeps the original's projection (ring size shrinks with distance; ring offsets do not),
  so it moves the same way. It adds gliding between steps, round dots, and larger dots when nearer.
- Modern look does not blank the ring in slot 5 as the original palette did.
- Known small difference: the original erased dots individually and could leave a few stale dots on
  screen while the tunnel emptied at the end. This version clears the screen every frame.
- The scene loops after 1060 steps (about 15 seconds), the original's length.

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

## Hidden Starfield notes
- Source: DDSTARS/STARS.ASM (live; its constants are in K.EXE) wrapped by KOE.ASM. POLYEGA.ASM and SIN1024.INC
  are included but unused; STARS.OK/STARS.PRE are older versions; DOIT1-3.C, KR.C, TEST/ are unrelated leftovers.
- Canvas is 320x400 (EGA mode 0Dh with line-doubling off), the first scene that is not 320x200. The classic
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

## Planned scenes (user's list, 2026-11-14), easiest first
Only the purely calculated scenes and the 3D scenes will be done; the picture-based scenes, scrollers and
stills are out of scope.
1. Bouncing dots - DONE
2. Plasma (PLZPART/PLZ.C + ASMYT.ASM, COPPER.ASM)
3. Hidden starfield (DDSTARS) - DONE
4. 3D sine landscape (COMAN) - a voxel landscape; has a background picture
5. Plasma cube (PLZPART/VECT.C, PLZFILL.C) - needs plasma first
6. Glenz vectors (GLENZ)
7. Ships fly-by (VISU engine + U2A data)
8. 3D city (VISU engine + U2E data)
Ranks 3-6 were judged from file sizes and may swap once read. 7 and 8 share one engine.

## Next steps
- Next scene: Plasma (rank 2 above).
- Build the sidebar scene picker when asked.
- Later: music.
