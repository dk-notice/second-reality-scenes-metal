# The water scroller's original files

Original data from Second Reality (Future Crew, 1993), part 13 (`WATER`, the water scroller, by Trug),
copied unchanged from `../secondreality/WATER/`. `./build.sh` copies this folder into the app
(`Resources/Water/`). 154 KB in all.

| File | What |
|---|---|
| `BKG.CLX` | The background: a 10-byte header (`RIX3`, 320, 200), 256 colours (3 bytes each, 0...63), then 320x200 colour numbers (0...191). The same picture is exported as `artwork/original/13-water-background.png`; the scene's 1993 look needs the colour NUMBERS. The part does not use this file's palette (see the next row). |
| `MIEKKA.SCI` | The sword ("miekka" is Finnish for sword): the same header (400 wide; its height word, 250, is wrong: the file holds 35 rows and the part uses 34), THE PART'S PALETTE (the same as the background's in colours 0...191; 192...255 are the sword's), then 400x34 colour numbers, 0 = nothing. Exported as `artwork/original/13-water-font.png`. |
| `WAT1.DAT`, `WAT2.DAT`, `WAT3.DAT` | The three position tables. For each cell of a 158-column, 34-row window on the sword (row by row): a count (16-bit), then that many screen addresses (16-bit, row x 320 + column). The part draws one table per screen refresh in turn: at each address, the cell's colour number, or the background's again where the cell is empty. After the third table the window moves one sword column. |

## Why the tables are files

`WATER/DATGEN.PAS` made them from four ray-traced pictures of the scene (`o:k1.mtv`, `k2`, `k3`, `k5`) in
which the red channel was the sword column at each screen pixel, with the sword moved a third of a column
from one picture to the next. Those pictures are not in the source release, so the tables cannot be made
again. Two files that look as if they might help do not:

- `WATER/MASK.MTV` is a picture of that kind, but from an earlier trial: its columns differ from the
  tables' by 17 to 60 at every one of the tables' 20,858 pixels.
- `WATER/GREEN.CLX` (each pixel's sword row, "fixed" by hand according to `DATGEN.PAS`) is close but not
  the copy that was used: 78 table pixels disagree with it.

(`WATER/WAT4.DAT` is not used by the part and is laid out differently.)

What `tools/water_reference.py` checks instead: each table parses to exactly its length; the three share
no pixel; together they cover 20,858 pixels in 14 separate regions (the sea, and the reflections in the
two balls).

## This is the released version

The source release also holds the built part, `MAIN/DATA/RAYSCRL.EXE`, compressed with PKLITE. Unpacked
(`deark -m pklite`), it contains all five of these files whole, byte for byte. The same five are in the
C++ port SecondReality++ (`Parts/WATER/Water_Data.cpp`).

SHA-256:

    d911d7f64d5dc5bc412e172177bcfe77fa2d2a03961a1cded774387cdc9523e3  BKG.CLX
    3c98ad931328605c9009c4b078b7b29e74575f9a8bbcea0446d4009dcf4a48a2  MIEKKA.SCI
    4a454f4e529fe1617c1b6cafcd0b7852f198eb870e37f52da510f2dc5201e800  WAT1.DAT
    dc513b4f06d2876a28963f4d1e8b1c509d4fff1c65b28460f031d1ce6210f3e7  WAT2.DAT
    b7af775c7247e2eed95800a68f8901ab641e735d896bbf7a79c85731cd38e27b  WAT3.DAT
