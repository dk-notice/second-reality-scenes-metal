# Title Picture and End Picture

| | Modern look | 1993 look |
|---|---|---|
| Title Picture | ![](../images/title-picture-modern.png) | ![](../images/title-picture-classic.png) |
| End Picture | ![](../images/end-picture-modern.png) | ![](../images/end-picture-classic.png) |

Two of the demo's still pictures, which never simply appear: each comes out of a white screen. The
title picture (part 4) emerges right after the explosion has faded to white; the end picture (part 17),
the Future Crew rings, follows the 3D city and fades to black before the credits.

- **Original:** `BEG/BEG.C` (about 85 lines) and `END/END.C` (about 130 lines, half of it a commented-out
  text scroller). Built as `BEGLOGO.EXE` and `ENDLOGO.EXE`. Who drew the pictures is not recorded here.
- **This version:** `Sources/SRMetal/Scenes/FadingPicture/`: one scene class,
  `FadingPictureScene`, set up twice. The pictures are drawn with the shared toolkit
  (`Core/PictureLayer.swift`, see [how-it-works.md](../how-it-works.md#pictures-in-the-modern-look)).
- **Length:** title 161 steps (2.3 seconds) in the demo; end picture 163 steps, then a hold until the
  music's cue (about 5 seconds), then 64 steps to black. Shown on their own they hold for a while and
  start again.

**These scenes use original artwork** (`artwork/original/rgb/04-title.png` and `17-end-picture.png`,
320x400 each).

## How the original did it

Both programs work the same way:

1. Set every colour to white (all but the last of the 256), and wait: 32 screen refreshes for the
   title, 34 for the end picture. The screen is white.
2. Copy the picture to the screen while it is still invisible (every colour is white).
3. Fade in over 129 refreshes: at refresh c (0 to 128) each colour level p (0...63) of the picture's
   palette becomes ((128 − c) · 63 + p · c) / 128, in whole numbers. So the fade moves in 128ths, twice as
   finely as the explosion's.
4. The title program ends here and the demo moves on to the glenz vectors.
5. The end program waits until the music's "music plus" goes above -16 (at most 5000 refreshes), then
   fades to black over 64 refreshes: colour level p becomes p · c / 64 for c = 63 down to 0.

The last colour (number 255) is left out of the fades; neither picture uses it (checked).

## This version

**The timing** (`FadingPictureModel`) is the original's, as phases: white, fade-in, (hold, fade-out),
end. Inside Play Demo the end picture is told the music's position (`demoUpdate`) and holds until the same
cue as the original; on its own it holds for 375 steps, about as long as in the demo.

**1993 look:** the original pixels, faded by the original's whole-number rules (in 128ths in, 64ths out).
The self-test compares the graphics chip with the same rules worked out on the processor at 23 moments
over the two scenes: all identical.

**Modern look:** the picture made 8 times larger by Super-xBR, the fade gliding smoothly between
refreshes and laid on top of the enlarged picture.

| | Original | 1993 look | Modern look |
|---|---|---|---|
| Picture | 320x400, 256 colours | the same pixels | 8x by Super-xBR |
| Fade in | palette, 128ths, 129 refreshes | the same rule and colours | smooth |
| End picture's hold | until music plus > -16 | the same in Play Demo; 375 steps alone | the same |
| Fade out (end picture) | palette, 64ths, to black | the same rule and colours | smooth |

## Limits

- Not compared with the original running.
- Inside Play Demo the end picture may start its fade-out one step after the original would have: the
  scene checks "music plus" with the music one step older than the original's "wait, then check" would
  see. If so, the last, black step of the fade falls on the credits' first step. Not settled.
- The original's white screen at the start was the palette at white over whatever was on screen (the
  title program also filled video memory with colour 15 first); this version shows the picture faded to
  full white, which is the same colour.
