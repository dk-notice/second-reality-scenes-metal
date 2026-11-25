# The mountain scroller's original files

Original data from Second Reality (Future Crew, 1993), part 9 (`FOREST`, the mountain scroller, by Trug),
copied unchanged from `../secondreality/FOREST/`. `./build.sh` copies this folder into the app
(`Resources/Mountain/`). 161 KB in all.

| File | What |
|---|---|
| `HILLBACK.CLX` | The background: a 10-byte header (`RIX3`, 320, 200), 256 colours (3 bytes each, 0...63), then 320x200 colour numbers. The same picture is exported as `artwork/original/09-mountain-background.png`, but the scene needs the colour NUMBERS and the whole palette: the text is added to the numbers (see below), and colours 128...159, which no background pixel uses, are the hills "with text on". |
| `O2.SCI` | The text, as one picture ("ANOTHER WAY TO SCROLL"): the same header (640, 32), a palette the part does not use, then 640x32 values 0...7. Rows 0...30 are used. Exported as `artwork/original/09-mountain-font.png`. |
| `POS1.DAT`, `POS2.DAT`, `POS3.DAT` | The three position tables. For each cell of a 237-column, 31-row window on the text (row by row): a count (16-bit), then that many screen addresses (16-bit, row x 320 + column). The part draws one table per screen refresh in turn: at each address, background + cell (cell = text value + 128 where there is text). After the third table the window moves one text column. |

## Why the tables are files

`FOREST/READMASK.PAS` made them from four ray-traced pictures of the hills (`o:mask1.mtv` ...
`mask4.mtv`) in which the red channel was the text column at each screen pixel, with the text moved a
third of a column from one picture to the next. Those four pictures are not in the source release, so
the tables cannot be made again. (`READMSK2.PAS` is a later experiment whose output format the part
does not read.)

What `tools/mountain_reference.py` checks instead: each table parses to exactly its length; the three
share no pixel; together they cover all but 2 of the 15,594 pixels of `FOREST/GREEN.CLX` (the one mask
that survives: each pixel's text row), and every address's row agrees with it.

The same five files are in the C++ port SecondReality++ (`Parts/FOREST/Forest_Data.cpp`), byte for
byte, and `O2.SCI` is also the copy in the source release's `MAIN/DATA`: this is the released version.

SHA-256:

    505186e04211e0588beb187fa03f8a34a1e339c5dba5e186e49aa16415cf3ac4  HILLBACK.CLX
    81693b533a77bca4ededc840042486693920b108e1d032d46cab6f81df40386e  O2.SCI
    1ccaefce6474102a4cb2c9b094946a5daf8cd88061af3bb8f53ef2775ea4b5d7  POS1.DAT
    73f6a5db6cd580352ba96ea29045149be49500e986e831a369ddda48b8be4980  POS2.DAT
    6ae248adaf228f35cb39644f699d6d0f25bcbe80d14a98fe41cbe945755f3b84  POS3.DAT
