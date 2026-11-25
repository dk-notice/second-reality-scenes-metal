# Third-party code

Two things here come from other people: the libopenmpt library (below), and the licence of the xBR picture
scalers. `Sources/SRMetal/Core/PictureScaler.swift` is written for Metal from Hyllian's published xBR
level 2 and Super-xBR shaders (libretro "slang-shaders", copyright 2011-2022 Hyllian, MIT licence):
[xBR-LICENSE.txt](xBR-LICENSE.txt). No file of theirs is included, only that licence.

## libopenmpt (tracker music)

| | |
|---|---|
| What | libopenmpt, the playback library of the OpenMPT tracker. Plays the demo's original Scream Tracker 3 (S3M) songs. |
| Version | 0.8.10 (released 2026-11-01) |
| Source | <https://lib.openmpt.org/files/libopenmpt/src/libopenmpt-0.8.10+release.makefile.tar.gz> |
| SHA-256 of that file | `95073a10d33d0ed4352f41b68edccb9636002d2626f9fd2e00b191fcaabdd876` |
| Added | 2026-11-24 |
| Licence | BSD 3-clause: see [libopenmpt/LICENSE](libopenmpt/LICENSE). The copyright notice must travel with any copy of the program. |
| Changes | None. [libopenmpt/](libopenmpt/) is the release package exactly as downloaded and unpacked. |

### How it is built

`build.sh` copies this folder to `build/libopenmpt/src` (so this one stays as released) and builds it
there with libopenmpt's own Makefile as a **static library** (`libopenmpt.a`), with every optional
format and extra program switched off: no zlib, MP3, Ogg Vorbis, FLAC or audio-output libraries,
none of which S3M needs. Swift Package Manager then links it into the program through
`Sources/COpenMPT/module.modulemap`, so the app contains it and needs nothing but macOS. The first
build of it takes about 15 seconds; `make` then rebuilds only what changed.

Because the library is built by `build.sh`, run `./build.sh` once before using `swift build` on its own.

### Updating to a newer version

1. Download the new `...+release.makefile.tar.gz` from <https://lib.openmpt.org/libopenmpt/download/>
   into a scratch folder, and record its SHA-256 (`shasum -a 256 <file>`).
2. Replace `ThirdParty/libopenmpt/` with the unpacked package (renamed to `libopenmpt`).
3. Update the table above, run `./build.sh` (it notices the new version and builds afresh), then
   `build/SRMetal.app/Contents/MacOS/SRMetal --selftest` and `--music-info`.
