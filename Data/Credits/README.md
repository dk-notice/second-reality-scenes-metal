# The credits' pictures and font, as RELEASED

Original data from Second Reality (Future Crew, 1993), as the released demo used it for its credits
(part 18, `CREDITS`). `./build.sh` copies this folder into the app (`Resources/Credits/`).

| File | What |
|---|---|
| `CREDPICS.BIN` | The 21 pictures, in the order the credits show them, 16,784 bytes each: a 16-byte header (`FC FC`, width 160, height 100), 768 bytes of palette (VGA levels 0...63), then 160 x 100 colour numbers (0...239). |
| `CREDFONT.BIN` | The font: 40 rows of 1,500 bytes, each a shade 0...9 (the program shows them as greys 7 x shade of 63). The program uses the top 32 rows and finds the glyphs by scanning for empty columns, in the order `ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/?!:,."()+-`; a space is 8 pixels. |

## Where these came from

Both were taken on 2026-11-25 from the released `MAIN/DATA/CRED.EXE` in the source release
(`../secondreality`), unpacked with `deark -m pklite` (the program is PKLITE-compressed), by
`python3 tools/credits_reference.py --extract Data/Credits`:

- `CREDPICS.BIN` = bytes 72,272 ... 424,735 of the unpacked program (the 21 pictures as linked in).
- `CREDFONT.BIN` = bytes 12,272 ... 72,271, which equal the source's `CREDITS/FONA.INC` byte for byte.

The pictures are NOT the source's files: the artist's files in `CREDITS/PICS/` differ for pictures 02,
05b, 09, 14b, 16, 17 and 18 (02 is a "PART PIC MISSING" placeholder there) and in every palette. The
released texts differ from the source's `MAIN.C` too; they are written into `CreditsModel.swift`.

SHA-256: `CREDPICS.BIN` f4c15094a0f54d36b8e78e586fc04f982d6a2d19fc068e17a7fb483541cdefd9,
`CREDFONT.BIN` 4b9e365ab715318643fb0f08fedb580f26d508231a44b990f550c8f4e0717c9d.
