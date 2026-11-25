# The opening credits' horizon and font, as RELEASED

Original data from Second Reality (Future Crew, 1993), as the released demo used it for its opening
credits (part 1, `ALKU`). `./build.sh` copies this folder into the app (`Resources/OpeningCredits/`).

| File | What |
|---|---|
| `HORIZON.BIN` | The night horizon: a 16-byte header (`FC FC`, width 640, height 200), 768 bytes of palette (VGA levels 0...63; colours 1-3 are the text's greys 10, 30 and white 63), then 640 x 200 colour numbers (0...63). The part shows rows 0...149. |
| `FONT.BIN` | The font as the program reads it: 30 rows of 1,500 bytes, each a shade 0...3. The program finds the glyphs by scanning the top 29 rows for empty columns, in the order `ABCDEFGHIJKLMNOPQRSTUVWXabcdefghijklmnopqrstuvwxyz0123456789!?,.:&()+-*=/[]` (`[` and `]` are the two halves of a Dolby Surround logo); a space is 16 pixels. |

## Where these came from

Both were taken on 2026-11-25 from the released `MAIN/DATA/ALKU.EXE` in the source release
(`../secondreality`), which is packed twice (PKLITE, with LZEXE inside: `deark -m pklite`, then
`deark -m lzexe`), by `python3 tools/alku_reference.py --extract Data/OpeningCredits`:

- `HORIZON.BIN` = bytes 143,888 ... 272,671 of the unpacked program; equal to the source's
  `ALKU/HOI.IN0` + `HOI.IN1` byte for byte.
- `FONT.BIN` = bytes 272,673 ... 317,672 (the font as linked, starting with the stray byte the source's
  `FONA.INC` has in front, which the program reads as the first pixel). It differs from `FONA.INC` in 3
  bytes: pixels added to join the two pieces of "&".

The texts are the same words as the source's `ALKU/MAIN.C`; they are written into `OpeningCreditsModel.swift`.

SHA-256: `HORIZON.BIN` f507e5731287576dcea85e94fa41b90fbe5cbc6058a0e3b7b8f3d3e756bc8217,
`FONT.BIN` 886fe1d9b47203000cb36c9b0fcc69cbe409bd045da03756ff91c067dae71a2c.
