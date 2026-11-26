# Artwork

Every picture the released *Second Reality* (Future Crew, 1993) shows, exported to PNG. The app shows
these originals; for the Modern look it scales them up on the graphics chip with Super-xBR, a
pixel-art scaler (chosen 2026-11-24), and will re-make a picture from its source where that is possible (decided 2026-11-24, replacing
an earlier plan of AI-upscaled versions, which were removed). Like the rest of the original, the artwork was released
into the public domain in 2013.

| Folder | What is in it |
|---|---|
| [original/](original/) | The pictures exactly as the demo had them: original size, original colours. Made by a script; do not edit. |
| [original/rgb/](original/rgb/) | The same pictures in full colour (8-bit RGB, marked as sRGB), including the explosion frames. These are the ones the app uses (`build.sh` copies them in). |
| [original/4x3/](original/4x3/) | The same pictures with each pixel repeated so they have the shape they had on a 1993 monitor (no smoothing). Use these to judge proportions. |
| [original/explosion/](original/explosion/) | The 40 frames of the explosion animation. |

## Where these came from

`tools/art_export.py` reads the original source in `../secondreality` (and changes nothing there):

```bash
python3 tools/art_export.py
```

```bash
python3 tools/art_export.py --check
```

The first writes everything in `original/`. The second decodes everything again and checks the PNGs
on disk still match, pixel for pixel.

For each picture it reads **the copy that was built into the demo**: the data linked into the part's
program, or the file the program loaded. It then checks that copy against the artist's Deluxe Paint
file. Every picture matched its Deluxe Paint file pixel for pixel, except where listed below. The
source folders also hold drafts and alternatives (for example `FOREST/KOE.LBM`, `WATER/KOE.LBM`,
`ALKU/RYPPIS.LBM`); those were never shown and are not exported.

The Ships horizon and the Glenz plate were already used by this project's scenes; the export of both
agrees with them.

## Pixel shapes

The 1993 screen was 4:3, but its pixels were not square:

- 320x200 pictures: each pixel was **1.2 times as tall as it was wide**.
- 320x400 and 640x400 pictures: each pixel was **0.6 times as tall as it was wide**.

So a 320x200 picture and a 320x400 picture both filled the same 4:3 screen. A scaled-up or re-made
version should end up 4:3 (for a one-screen picture), not the shape of its pixel grid. The `4x3/` versions show the right
shape: 320x200 and 320x400 pictures become 1600x1200; the two 640-wide pictures become 3200x1200.

## The pictures

"Part" is the number in the demo's running order (see `docs/original-demo.md`).

| File | Part | Size | What it is, and what a scaled-up or re-made version should respect |
|---|---|---|---|
| `00-start-setup-screen` | Setup menu (`START`) | 640x400 | The screen with the setup options, before the demo starts. How much of its width shows at once has not been checked. Rows 300-331 are not part of the picture: they hold the menu's font. |
| `01-opening-horizon` | 1, opening credits (`ALKU`) | 640x200 | Night horizon the opening credits appear over. Two screens wide; it scrolls sideways. **Colours 1-3** are the text's greys and white in the built copy (the artist's file has dark blues there); 921 pixels of the picture use them. The PNG has the colours the demo showed. |
| `01-opening-font` | 1 | 1500x30 | The credits font. No colours of its own: the shades (black = empty, white = solid) are coloured by the program. The built copy has one stray byte in front, which shifted every letter one pixel; the PNG leaves it out. |
| `02-ships-horizon` | 2, ships fly-by (`VISU`) | 320x200 | Dusk horizon under the ships. Rows outside 25-174 are black (the 3D picture only filled that band). Used by the Ships Fly-by scene (which would use a replacement, `Data/Visu/U2ABG-modern.png`, if one existed; none does). |
| `04-title` | 4, title picture (`BEG`) | 320x400 | "Second Reality" title with the creature. |
| `05-glenz-plate` | 5, glenz vectors (`GLENZ`) | 320x200 | The chequered plate the glenz lands on (top 108 rows; the rest is empty). Already in the Glenz Vectors scene. The program combines its colour numbers with the glenz's, so for that scene the colour **numbers** matter, not just the look. |
| `07-troll` | 7, after the techno bars (`TECHNO`) | 320x400 | The troll. Part 8 then "switches the screen off" on this picture (it has no picture of its own). |
| `09-mountain-background` | 9, mountain scroller (`FOREST`) | 320x200 | Tree against a cloudy sky. The scrolling text is placed pixel by pixel on it through fixed tables; the Mountain Scroller scene fits a smooth map to those tables for its Modern look. |
| `09-mountain-font` | 9 | 640x32 | Not a font: one picture of the whole text, "ANOTHER WAY TO SCROLL", in values 0...7 that the program adds to the background's colour numbers. |
| `10-lens-picture` | 10, lens and rotozoomer (`LENS`) | 320x200 | The bald head. Both effects use it: the lens bends and tints it, and the rotozoomer spins a squeezed copy of it filling the screen. The lens tints by adding to **colours 0-63**: keep that in mind if the colours change. |
| `10-lens-shape` | 10 | 320x200 | Not shown: the drawn shape of the lens (colours 1-4 mark its zones), turned into the lens's tables when building. The Lens scene works its tables out from it. |
| `13-water-background` | 13, water scroller (`WATER`) | 320x200 | Ray-traced scene with chrome balls on rippling water. Made with POV-Ray 1.0 from `WATER/KK.POV`; the Modern look shows that scene rendered again at 2560x1600 (`Data/Water/BACKGROUND-POVRAY.png`, see `docs/scenes/water-scroller.md`), so the app no longer loads this export. The text is placed through fixed tables, as in part 9. |
| `13-water-font` | 13 | 400x35 | Not a font: a picture of a sword with a flame in front and sparks behind, with its own colours (192...255); the part slides it over the water (see `docs/scenes/water-scroller.md`). (The file's header says 400x250; the data is 400x35.) |
| `15-jelly-logo` | 15, jelly logo (`JPLOGO`) | 320x400 | The warrior on a horse ("Ice Kingdom"). The program squashes and wobbles it row by row. |
| `17-end-picture` | 17, end picture (`END`) | 320x400 | The Future Crew ring. |
| `18-credits-pic01` ... `pic18` | 18, credits (`CREDITS`) | 160x100 each | 21 small pictures, one per part, shown beside each part's credits, as linked into the released `CRED.EXE`. Most are miniature screenshots of the part. **Plan (user, 2026-11-24): replace them with screenshots of this project's finished scenes** (nearly all parts are built now; the credits part itself is not). See the warnings below. |
| `18-credits-font` | 18 | 1500x40 | The credits font (shades 0-9, coloured by each credits picture's palette). The program uses the top 32 rows. |
| `19-endscroller-font` | 19, end scroller (`ENDSCRL`) | 1500x30 | The end scroller's font; shades, coloured by the program. |
| `starfield-text-panels` | Hidden part (`DDSTARS`) | 320x200 | The two text panels of the hidden starfield part. Left out of this project's Hidden Starfield scene. 16-colour picture using 4. |
| `explosion/frame-01` ... `40` | 3, explosion (`PAM`) | 320x200 each | The explosion animation, made in Autodesk Animator (`PAM/PRAX4.FLI`). Shown at 17.5 frames a second (each for four screen refreshes) while the palette fades in from white and back. The data holds 42 frames; the program shows the first 40. |

Fonts have no `4x3/` version: how tall their pixels were on screen depends on how each program drew
them, which has not been checked.

## Warnings

- **Credits pictures come from the released program** (since 2026-11-25), unpacked from
  `MAIN/DATA/CRED.EXE` with `deark` (Homebrew), which `tools/art_export.py` needs for them. The
  artist's files in the source (`CREDITS/PICS/*.LBM`) differ: pictures 02, 05b, 09, 14b, 16, 17 and 18
  were redrawn or replaced for the release (02 is a "PART PIC MISSING" placeholder there, a real
  picture in the release), and every palette differs slightly. The export prints the comparison.
- **The explosion's decoding** was checked by structure only (every frame fills exactly the screen,
  and the frames look right), not against the Autodesk Animator original.
- **Colours on screen sometimes differed** from these PNGs: parts fade in and out, the lens tints,
  and fonts are coloured by the program. The PNGs are the pictures as stored.
- The colours are as the 1993 VGA card produced them, 64 levels per channel, so smooth gradients show
  bands; that is the original, not an export fault.

## Formats, for reference

How the demo stored pictures, and how the script reads each, is described at the top of
`tools/artformats.py`. In short: the artists drew in Deluxe Paint (LBM files); the team converted
those to bare-bones formats of their own (a short header, the palette, then the pixels, sometimes
packed) and built them into each part's program.
