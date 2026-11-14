# Project state

Last updated: 2026-11-14

## Goal
A native macOS app that re-creates scenes from Second Reality (Future Crew, 1993) from scratch,
drawn on the graphics chip with Metal. Each scene has two looks: Modern (full resolution, smooth)
and 1993 (320x200 pixels, 70 steps per second). The original source is public domain and lives in
`../secondreality` for reference; the existing complete port is in `../SecondRealityPlusPlus`.

## Status
- Three scenes work in both looks: Dot Tunnel, Rings, and Interference. (Rings and Interference were one
  back-to-back sequence in the original; split into two scenes at the user's request, 2026-11-14.)
- The scene framework has now carried a second, different kind of scene (full-canvas shader) without changes
  to its design; only small additions (shared sine table, shared full-canvas vertex shader, generic self-test).
- No scene-picker UI yet. Menu "Scene" has Switch Look (L) and Next/Previous Scene (right/left arrow keys).
- No music.

## How to build and run
- `./build.sh` builds `build/SRMetal.app`.
- `open build/SRMetal.app` runs it. Start-up options go after `--args`: `--look classic|modern`,
  `--scene dot-tunnel|rings|interference`.
- `build/SRMetal.app/Contents/MacOS/SRMetal --selftest` runs the checks without opening a window.
- Needs only Apple's Command Line Tools (no Xcode). Shaders are compiled when the app starts.

## Layout
- `Sources/SRMetal/Core/` shared by all scenes: `DemoScene.swift` (the scene contract and the scene list),
  `Renderer.swift` (clock and the two looks), `Shaders.swift`.
- `Sources/SRMetal/Scenes/<Name>/` one folder per scene.
- `Sources/SRMetal/App/` window, menu, self-test.

## Adding a scene
1. Create `Sources/SRMetal/Scenes/<Name>/` with a class that conforms to `DemoScene` (`reset`, `tick`, `draw`).
2. Add one `SceneEntry` to `SceneCatalog.all` in `Core/DemoScene.swift`.
3. Implement `classicReferenceFrame()` (the 1993 picture worked out on the processor) and list some
   `checkpoints` in the entry. The self-test then compares the graphics chip against it automatically.

## Decisions
- Swift + Metal + SwiftUI, built with Swift Package Manager from the command line.
- Scenes are re-implemented from the original source's logic, not copied from the existing port.
- Every scene is stepped at 70 per second; the Modern look blends between steps.
- Every canvas is shown at 4:3, like a VGA monitor (320x200 pixels were not square).
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
- Interference's length (980 steps, then it loops) is approximate: the original ended it on a music cue (music frame 925).
- The original started the colour rotation on a music beat; this version starts it immediately.
- Modern look: rings calculated per screen pixel with soft edges; colours, scrolling and the row wobble glide
  between steps. Ring shades stay as 8 distinct bands, as in the original.
- Circles are round in pixels, so on the 4:3 display they are slightly tall ovals, as on a real VGA monitor.

## Techno bars: what the original does (for when we build it)
- Each frame draws 11 rotating bars as a 1-bit picture and writes it into ONE of the 4 bit planes of one of
  8 video pages, cycling. Older frames stay in the other planes, so bars leave trails; the palette colours a
  pixel by how many planes have it set. A beat flash comes from the music row.

## Next steps
- Techno bars (same original program as Interference) is the natural next scene; user to confirm.
- Build the sidebar scene picker when asked.
- Later: music.
