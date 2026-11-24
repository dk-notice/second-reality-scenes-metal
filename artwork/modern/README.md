# High-resolution artwork

Your high-resolution versions of the pictures in [../original/](../original/) go here. Nothing in this
folder is made by a script.

## Where to start

Open the full-colour copy in [../original/rgb/](../original/rgb/) (it needs no change of mode or colour
profile). Upscale it, keeping its proportions, until it is at least the target size both ways; then
shrink it to the target size (Image Size, width and height unlinked, Bicubic Sharper). Compare the
result with the `../original/4x3/` version: shapes and positions should line up.

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
7. **Full colour: 8-bit RGB.** Not indexed ("256 colours"): in Photoshop's Export As, untick
   "Smaller File (8-bit)", or use File > Save a Copy as PNG. An indexed save throws the upscaler's
   shading away. A finished picture is typically 5-20 MB.
6. **Fonts:** keep the letters in the same order and the same proportions, with the same gaps
   between them, since the programs find each letter by its position. A larger version of the whole
   strip, scaled evenly, is the safe way.

## Stored with Git LFS

Pictures and working files here (`.png`, `.jpg`, `.tif`, `.webp`, `.psd`, `.kra`, `.xcf`, `.exr`) are
kept with Git LFS (Large File Storage), set up in `.gitattributes` at the top of the project: GitHub
stores them separately and the repository holds only a small pointer to each. Commit and push as
usual; nothing else changes. On another Mac, install it first (`brew install git-lfs`, then
`git lfs install`) or a clone gets the pointers instead of the pictures.

GitHub's free allowance (2026-11): 10 GB of LFS storage and 10 GB of downloads a month. Every
version pushed counts in full, so save drafts locally and commit finished versions. Without a
payment method on the GitHub account, going over blocks further pushes rather than costing money.

## Checking a picture

```bash
python3 tools/art_check.py
```

checks every picture here: the name matches an original, full colour (not 256 colours), no
see-through pixels, the target size, and that it lines up with the original (no cropping, padding
or shift). Add names (`python3 tools/art_check.py 07-troll`) to check only those.

## Status

| Picture | Done? | Notes |
|---|---|---|
| `04-title.png` | Yes (2026-11-24) | Photoshop Generative Upscale; 3840x2880, 8-bit RGB. Framing checked against the original: lines up with no shift. |
| `07-troll.png` | Yes (2026-11-24) | Photoshop Generative Upscale; checked by `tools/art_check.py`. |
| `15-jelly-logo.png` | Yes (2026-11-24) | Photoshop Generative Upscale; checked by `tools/art_check.py`. |
| `17-end-picture.png` | Yes (2026-11-24) | Photoshop Generative Upscale; checked by `tools/art_check.py`. |
| `02-ships-horizon.png` | Yes (2026-11-24) | Photoshop Batch: Generative Upscale (Topaz Gigapixel) 4x twice, Image Size 3840x2880; checked. |
| `05-glenz-plate.png` | Yes (2026-11-24) | Photoshop Batch: Generative Upscale (Topaz Gigapixel) 4x twice, Image Size 3840x2880; checked. |
| `09-mountain-background.png` | Yes (2026-11-24) | Photoshop Batch: Generative Upscale (Topaz Gigapixel) 4x twice, Image Size 3840x2880; checked. |
| `10-lens-picture.png` | Yes (2026-11-24) | Photoshop Batch: Generative Upscale (Topaz Gigapixel) 4x twice, Image Size 3840x2880; checked. |
| `13-water-background.png` | Yes (2026-11-24) | Photoshop Batch: Generative Upscale (Topaz Gigapixel) 4x twice, Image Size 3840x2880; checked. |

Note: the Ships Fly-by scene already accepts a replacement horizon, but it looks for it as
`Data/Visu/U2ABG-modern.png`. When the first pictures here are ready, the scenes will be changed to
read them from this folder instead.
