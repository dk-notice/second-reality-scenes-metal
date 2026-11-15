# Original 3D data for the VISU engine

These 52 files are ORIGINAL DATA from Second Reality (Future Crew, 1993), copied unchanged from the
released source (`VISU/C/SCENE/` and `VISU/C/U2ABG.UH`; public domain, the Unlicense). They are byte
for byte the files the shipped demo carried in its data folder. 3D models and recorded camera moves
cannot be calculated, so the two 3D scenes load them. `./build.sh` copies this folder into the app
(`SRMetal.app/Contents/Resources/Visu/`) and `Core/Visu/VisuData.swift` reads it from there.

| Files | What | Used by |
|---|---|---|
| `U2A.00M` | palette (768 bytes) and the list of objects | Ships fly-by |
| `U2A.001` ... `U2A.003` | objects: small ship, big ship, engine | Ships fly-by |
| `U2A.0AA`, `U2A.0AB` | list of animations, and the one animation (521 frames) | Ships fly-by |
| `U2ABG.UH` | background picture, 320x200, 64 colours (linked into U2A.EXE as `_BG.OBK`): original hand-made ARTWORK | Ships fly-by |
| `U2E.00M` | palette and the list of objects | 3D city |
| `U2E.001` ... `U2E.042` | objects: buildings, ground plates, trees, cars, ship, logo | 3D city |
| `U2E.0AA`, `U2E.0AB` | list of animations, and the one animation (1801 frames) | 3D city |

The formats are described byte by byte in `docs/visu-engine.md`.
