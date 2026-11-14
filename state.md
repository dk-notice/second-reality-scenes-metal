# Project state

Last updated: 2026-11-14

## Goal
A native macOS app that re-creates scenes from Second Reality (Future Crew, 1993) from scratch,
drawn on the graphics chip with Metal. Each scene has two looks: Modern (full resolution, smooth)
and 1993 (320x200 pixels, 70 steps per second). The original source is public domain and lives in
`../secondreality` for reference; the existing complete port is in `../SecondRealityPlusPlus`.

## Status
- Scene 1, the Dot Tunnel, works in both looks.
- The scene framework is in place, ready for more scenes.
- No scene-picker UI yet (only one scene). Menu "Scene" has Switch Look (L) and Next/Previous (arrow keys).
- No music.

## How to build and run
- `./build.sh` builds `build/SRMetal.app`.
- `open build/SRMetal.app` runs it. Add `--args --look classic` to start in the 1993 look.
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
3. Add a check to `App/SelfTest.swift` comparing the classic look against a processor-side reference.

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

## Next steps
- User to pick the next scene to add.
- Build the sidebar scene picker when asked.
- Later: music.
