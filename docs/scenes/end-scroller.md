# End Scroller

| Modern look | 1993 look |
|---|---|
| ![](../images/end-scroller-modern.png) | ![](../images/end-scroller-classic.png) |

The very end of the demo: after the credits, a long text creeps up the screen: "Second Reality /
Copyright (C) 1993 by the Future Crew / This demo won the Assembly'93 ...", the sponsors, how to contact the
group, greetings to other groups. It runs until a key is pressed, starting again from the top when it
reaches the end.

- **Original:** `ENDSCRL/MAIN.C` (about 125 lines), built as `ENDSCRL.EXE`.
- **This version:** `Sources/SRMetal/Scenes/EndScroller/` (added 2026-11-24). In the sidebar too.
- **Data:** the released text and font, in `Data/EndScroller/` (see "The released text" below).
- **Length:** the text is 542 lines; its loop mark is on line 538, 11,278 rows down; at 35 rows a second that takes
  about 5 minutes 20 seconds, then it starts again.

## How the original did it

The program switched to a 640x350 16-colour mode and changed one register so it showed 400 rows, then set
four greys: colour 1 = level 20, 2 = 40, 3 and up = 60 (of 63).

Every second screen refresh (`if(dis_waitb()==1) dis_waitb();`) it drew ONE new row of pixels: the current
row of the current text line, into the row of video memory just off the bottom of the screen (twice: the
ring of 401 rows is stored twice over, so the screen can start anywhere without wrapping), and told the
card to start the screen one row lower. So the whole screen moves up a row, 35 times a second, for the
cost of drawing 640 pixels.

Each text line is 25 rows (the font's height). When a line starts, its width is added up (every character's
glyph plus 2 pixels, including the carriage return, which has no glyph) and the line is centred:
start = (639 − width) / 2. A space is 16 pixels wide.

The glyphs are found the way `init()` finds them: scan the font picture for runs of columns with ink, and
give them to the characters of a fixed list in order.

## The released text

The source release's `ENDSCRL` folder has only an earlier version: its `ENDSCROL.TXT` is a joke
work-in-progress ("A font test!!! Yeah!!!!", "PIXEL SUCKS", then about 80 empty lines), and its font has
no Y, Z, ä, ö, / or &. The released demo used a newer text (542 lines) and a 25-row font with those six
characters added; and the released program also understood two markers in the text: a line starting
`[nn` is a gap of nn rows, a line starting `%` sends it back to the first line.

Those released files survive in the data of the C++ port **SecondReality++** (public domain, like the
original), whose authors extracted them from the released demo. This project takes the two files from
there unchanged (and nothing else: the scroller is written from the original `MAIN.C`). Where exactly they
came from, with checksums: [Data/EndScroller/README.md](../../Data/EndScroller/README.md). Chosen by the
user, 2026-11-24.

## This version

**The model** (`EndScrollerModel`) is the original's loop: a ring of 401 rows of shade numbers, one new row
every 2 steps, the same centring, glyph search, 2-pixel gaps and 16-pixel space, and the two markers.

**1993 look:** the model's 640x400 screen in the original's four greys, through `IndexedCanvas`. The
self-test checks: a row every 2 refreshes; the first line's ink starts exactly where the original's
centring puts it; a `[15` line takes 15 rows; the text loops at its `%` line; the font has Y, Z and ä;
and the graphics chip shows the model's screen exactly at 12 moments.

**Modern look:** the same lines at the same places, but drawn in **SuperClarendon**, a Clarendon-style
typeface that comes with macOS (so it costs nothing in the program's size). It was chosen by the user over
the original font smoothed by Super-xBR, after comparing them on real lines of the text
(sheets made into `build/scaler-compare/fonts/`, a folder that is not kept in the repository). Capitals are as tall as the original's 14 rows, sitting on the same row;
the original's tall pixel shape (1.2:1) is kept; the letters use the typeface's own spacing (the original
font's letters were wider, so lines are a little narrower, but each is centred, as before). The text glides
up smoothly instead of a row at a time. Each line is drawn once, at 4 times the original's width, into a
picture of its own, and moved as it scrolls.

| | Original | 1993 look | Modern look |
|---|---|---|---|
| Screen | 640x400, 4 greys | the same | full resolution |
| Font | released 25-row font | the same | SuperClarendon (macOS) |
| Scroll | 1 row every 2 refreshes | the same | smooth, same speed |
| End | until a key | Play Demo: until stopped; alone: loops | the same |

## Limits

- The released text and font are not taken from our own copy of the released demo (its parts are
  compressed) but from the port's data; the marker handling is inferred from the released text and matches
  the port.
- The text's few non-English characters are shown in SuperClarendon by their DOS meaning (0x84 = ä).
- Not compared with the original running.
