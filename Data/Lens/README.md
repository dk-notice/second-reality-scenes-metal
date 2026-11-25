# The lens's wiping ring (table 4)

Original data from Second Reality (Future Crew, 1993), part 10 (`LENS`, Psi). `./build.sh` copies this
folder into the app (`Resources/Lens/`).

| File | What |
|---|---|
| `LENS.EX4` | Table 4 of the lens, 6,252 bytes, from `../secondreality/LENS/LENS.EX4` unchanged (the same bytes are inside the demo's `_LENSEX4.OBK`). For each of 120 rows: a byte offset and a count (two 16-bit words), then the row lists: a 0, then the x of each pixel of the ring around the lens. Every step the lens is drawn, these pixels are repainted with the picture underneath (`dorow3` in `LENS/ASM.ASM`), which wipes away where the lens was a step earlier. |

## Why this one table is a file

The lens has four tables, made by `LENS/CALC.C` from a drawn lens shape (`LENS/LENS.U`, exported as
`artwork/original/10-lens-shape.png`; zones 1-3 are the lens, zone 4 the ring around it). The app
calculates tables 1-3 itself by running `CALC.C`'s steps again (Microsoft C's random numbers included):
they come out byte for byte the same as `LENS.EX1`-`EX3`. Table 4 does not: the shipped `LENS.EX4` was
made from an OLDER version of the shape, whose ring was slightly different at the top and bottom (for
example it has 21 pixels on row 0, where today's shape has none). That older shape does not survive, so
table 4 is kept as the original file. `tools/lens_reference.py` shows the comparison.

SHA-256: `LENS.EX4` f7a480dc71739f44adf559ef348f976ceb7ab623241d5cd4432902220d7c29f5
