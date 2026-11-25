# How the 1993 demo was built

This page describes the original *Second Reality*, as read from the source code Future Crew released in
2013 (<https://github.com/mtuomi/SecondReality>). It is background for the scene pages.

## Not one program

The demo was about 20 small DOS programs, each written by one person, run one after another.

- **The loader** (`MAIN/U2.ASM`) checks for a 386 processor, a VGA card and about 570 KB of free memory,
  starts the music, then runs each part in order. The list of program names is right there in the file.
- **The music player** is built into the loader and keeps playing in the background while parts load and
  run. That is why the music never skips between scenes.
- **DIS, the "Demo Interrupt Server"** (`DIS/`) is the glue. Every part calls it to ask three things: has
  the screen finished drawing this frame, where is the music right now, and should I quit. A part stays in
  time with the music by looping until the music reaches a given position.

Each part could also run by itself from DOS, which is how four programmers worked in parallel. The team's
planning document survives as `SCRIPT`, in Finnish, with a table of how finished each part was.

The code is mostly assembly and C, with three parts in Turbo Pascal.

## The parts, in order

| # | Scene | DOS program | Source folder | Coder |
|---|---|---|---|---|
| 1 | Opening credits over a horizon | `ALKU.EXE` | `ALKU` | Wildfire |
| 2 | Ships fly past | `U2A.EXE` | `VISU` | Psi |
| 3 | Explosion | `PAM.EXE` | `PAM` | Trug / Wildfire |
| 4 | Title picture | `BEGLOGO.EXE` | `BEG` | |
| 5 | Glenz vectors | `GLENZ.EXE` | `GLENZ` | Psi |
| 6 | **Dot tunnel** | `TUNNELI.EXE` | `TUNNELI` | Trug |
| 7 | **Rings, interference, techno bars** | `TECHNO.EXE` | `TECHNO` | Psi |
| 8 | Picture, then the screen "switches off" | `PANICEND.EXE` | `PANIC` | Wildfire |
| 9 | Mountain scroller | `MNTSCRL.EXE` | `FOREST` | Trug |
| 10 | Lens, then rotozoomer | `LNS&ZOOM.EXE` | `LENS` | Psi |
| 11 | Plasma, then plasma cube | `PLZPART.EXE` | `PLZPART` | Wildfire |
| 12 | **Bouncing dots** | `MINVBALL.EXE` | `DOTS` | Psi |
| 13 | Mirror-ball scroller over water | `RAYSCRL.EXE` | `WATER` | Trug |
| 14 | 3D sine landscape | `3DSINFLD.EXE` | `COMAN` | Psi |
| 15 | Jelly logo | `JPLOGO.EXE` | `JPLOGO` | Psi |
| 16 | 3D city | `U2E.EXE` | `VISU` | Psi |
| 17 | End picture | `ENDLOGO.EXE` | `END` | |
| 18 | Credits | `CRED.EXE` | `CREDITS` | |
| 19 | End scroller | `ENDSCRL.EXE` | `ENDSCRL` | |
| | Hidden starfield | `DDSTARS.EXE` | `DDSTARS` | Psi |

Scenes in bold are re-created in this project. Several programs hold two or three effects back to back.
The folder names do not always match the program names; some rows were matched from the existing port's
naming and not confirmed from every build script.

## The tricks the scenes share

A 486 could not calculate these effects as they ran. Nearly every scene uses the same handful of ideas to
get round that.

### Do the maths beforehand

Anything expensive is calculated in advance and stored in a table, by a separate small program. At run time
the demo only looks values up. The dot tunnel's circles, the interference rings and every sine wave are
tables.

### Let the palette do the work

A VGA card stored each pixel as a number and looked its colour up in a table of 256 colours, the palette.
Changing an entry in that table instantly recolours every pixel with that number, at almost no cost. Fades,
flashes and flowing colours are nearly all done this way: the pixels are never touched.

### Let the video card do the work

The card can be told which part of its memory to show, and that can change every frame. So a picture can be
scrolled without moving a single pixel, and whole screens can be flipped instantly. The interference scene
is a window sliding over a picture four times the size of the screen. The techno bars cycle through eight
screens.

### Bit planes

In 16-colour modes the card stored each pixel as four separate on/off layers, called bit planes, and a
program could write to one layer without disturbing the others. Two scenes here are built on that: the
interference scene keeps one picture in three layers and a second in the fourth, and the techno bars put
each new frame in a different layer so that old frames show through as trails.

### Skip the checks

Checking whether a pixel is on the screen costs time for every pixel. The dot tunnel avoids the check by
arranging its tables so that an off-screen position lands somewhere invisible.

### Rewrite the program as it runs

Some parts change their own machine code. The dot tunnel writes the current colour directly into an
instruction before each ring. A related trick: the jelly
logo's line-stretching code (`ZOOM.INC`, one straight run of instructions per line width) was written by
another program (`DOL.C`) before the part was built.

### The inner loop is assembly

Whatever runs once per pixel or per dot is hand-written assembly. The surrounding logic is usually C.

## What that code is like

By the standards of 1993 this was elite work, and the ideas are clever. The code itself was written against
a party deadline and shows it:

- a function in the timing system is labelled `DOESN'T WORK!-(` and left in;
- one file includes another from a hard-coded drive letter, `i:\u2\dis\dis.h`;
- versions are kept by renaming files (`TUN9.PAS`, `TUN10.PAS`);
- the same picture-unpacking file is copied into several folders;
- placeholder text in the end scroller reads "PIXEL SUCKS" (Pixel was one of the group's artists).

That is normal for demos. The skill is in the ideas and the inner loops.

## Two bugs worth knowing about

### Three parts fail on fast processors

The dot tunnel, mountain scroller and water scroller were written in Turbo Pascal 7 and use its standard
`crt` library. When a program using that library starts, it times a small loop to measure the computer's
speed and divides the result by a fixed number. On a fast enough processor (roughly a 266 MHz Pentium II
and up) the answer no longer fits, and the program stops with "Runtime error 200". The dot tunnel does not
use the library for anything; it is included out of habit.

### An uninitialised counter in the bouncing dots

In `DOTS/MAIN.C` the counter that picks which dot to re-drop each step is never given a starting value. In
C such a variable holds whatever was left in that spot of memory. If the leftover is a small number the
scene runs perfectly. If it is large or negative, the program writes dot positions into the wrong place,
and since the dot table sits in the same block of memory as the drawing routine's machine code, that can
crash the machine. Because the leftover depends on the PC's configuration and not on chance, the crash
would land on the same frame every time on a given machine. See
[scenes/bouncing-dots.md](scenes/bouncing-dots.md#a-bug-in-the-original).
