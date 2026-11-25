# The end scroller's text and font, as RELEASED

Original data from Second Reality (Future Crew, 1993), as the released demo used it for its end scroller
(part 19, `ENDSCRL`). `./build.sh` copies this folder into the app (`Resources/EndScroller/`).

| File | What |
|---|---|
| `ENDSCROL.TXT` | The scroll text, 542 lines, DOS line ends (CR LF), one non-ASCII byte (0x84 = "ä" in the DOS character set). A line starting `[nn` is a gap of nn pixel rows; a line starting `%` sends the scroller back to the first line. |
| `ENDFONT.BIN` | The font: 25 rows of 1,550 bytes, each 0 (background) or 1-3 (shades the program shows as grey levels 20, 40, 60 of 63). The glyphs are found by scanning for empty columns, in this order: `ABCDEFGHIJKLMNOPQRSTUVWX`, `abcdefghijklmnopqrstuvwxyz0123456789!?,.:`, byte 0x8F twice, `()+-*='Z`, 0x84 (ä), 0x94 (ö), `Y/&`; a space is 16 pixels. |

## Where these came from (read this)

The source release (`../secondreality/ENDSCRL/`) holds only an EARLIER version: `ENDSCROL.TXT` there is a
joke work-in-progress text ("A font test!!! Yeah!!!!"), and its font (`FONA.UH`, exported as
`artwork/original/19-endscroller-font.png`) is 30 rows without Y, Z, ä, ö, / and &. The released demo
used the newer files here. Our copy of the released demo keeps its parts compressed, so they could not be
read from it directly.

Both files were taken on 2026-11-24 from the C++ port **SecondReality++** (`../SecondRealityPlusPlus`,
<https://github.com/XorJS/SecondRealityPlusPlus>, commit 5827f3e, public domain under the Unlicense),
whose authors extracted them from the released demo:

- `ENDSCROL.TXT` = that port's data blob 343536862 (`Blob/Blob_Data.cpp`, 6,141 bytes), byte for byte.
- `ENDFONT.BIN` = `EndScrl::Data::endscrl_font[25][1550]` (`Parts/ENDSCRL/ENDSCRL_MAIN_Data.cpp`), byte for byte.

Only this data was taken, not code: the scroller itself is written from the original `ENDSCRL/MAIN.C`.
SHA-256: `ENDSCROL.TXT` 11067c5f245a22d6a50ad366f312e562caad6958d1f73147eb667c8f2de37bed,
`ENDFONT.BIN` 2a17bfa13a9bfb58d4dbe9f81a0cd6761623edae6e574811ef8d1fedfd22a2a7.

The marker handling (`[nn`, `%`) is not in the source release's `MAIN.C` either; it is inferred from the
released text and matches how the port reads it.
