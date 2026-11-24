# High-resolution artwork

Your high-resolution versions of the pictures in [../original/](../original/) go here. Nothing in this
folder is made by a script.

## Rules, so the app can use them later

1. **Same name as the original.** `../original/10-lens-picture.png` becomes `10-lens-picture.png`
   here; explosion frames go in `explosion/` with the same names (`explosion/frame-01.png` ...).
2. **PNG.** Full colour is fine; it does not need to keep the original 256-colour palette.
3. **The shape of the `4x3/` version, not of the original's pixel grid.** A one-screen picture is 4:3
   whatever its original size (320x200 and 320x400 both become 4:3). The two 640-wide pictures
   (`00-start-setup-screen`, `01-opening-horizon`) are 8:3. A 160x100 credits picture is 4:3 too.
4. **Same framing.** Keep everything where it was, at the same relative size, so that a position in
   the original (for example where the lens moves, or where a scroller's text runs) is the same
   relative position in yours. Do not crop, pad or recompose.
5. **Any size**, as long as the shape is right. 3840x2880 (4K-wide, 4:3) is plenty for a full screen;
   1600x1200 is the least that is worth doing. The scenes will scale to the window.
6. **Fonts:** keep the letters in the same order and the same proportions, with the same gaps
   between them, since the programs find each letter by its position. A larger version of the whole
   strip, scaled evenly, is the safe way.

## Status

| Picture | Done? | Notes |
|---|---|---|
| (none yet) | | |

Note: the Ships Fly-by scene already accepts a replacement horizon, but it looks for it as
`Data/Visu/U2ABG-modern.png`. When the first pictures here are ready, the scenes will be changed to
read them from this folder instead.
