# The demo's timeline

When each part of *Second Reality* starts and ends, and how Play Demo follows it. Every part waited on the music in its own way; these conditions were read from the
original source, then **simulated against the real music** (libopenmpt playing the original songs,
stepped 1/70 second at a time) to turn them into times. Tools: `tools/music_steps.c` and
`tools/demo_timeline.py` (usage at the top of each).

## The result

Times are from the moment the music starts (after the setup screen). Every part is a scene in this
project (the Techno part is four: rings, interference, techno bars, troll; Lens & Zoom two).

| # | Part | Song | Starts | Ends | Length |
|---|---|---|---|---|---|
| 1 | Opening credits (`ALKU`) | 1 | 0:00.0 | 1:20.1 | 80.1 s |
| 2 | Ships fly-by (`U2A`), incl. ~14 s of horizon before the ships | 1 | 1:20.1 | 1:41.2 | 21.2 s |
| 3 | Explosion (`PAM`), incl. ~2.7 s wait | 1 | 1:41.2 | 1:46.6 | 5.4 s |
| 4 | Title picture (`BEGLOGO`) | 1 | 1:46.6 | 1:48.9 | 2.3 s |
| 5 | Glenz vectors (`GLENZ`) | 2 | 1:48.9 | 2:32.6 | 43.7 s |
| 6 | Dot tunnel (`TUNNELI`) | 2 | 2:32.6 | 2:47.7 | 15.1 s |
| 7 | Rings, interference, techno bars, troll (`TECHNO`) | 2 | 2:47.7 | 3:44.7 | 56.9 s |
| 8 | Screen switches off (`PANICEND`) | 2 | 3:44.7 | 3:47.4 | 2.7 s |
| — | (the loader waits for the next "+++" in the music) | 2 | 3:47.4 | 3:51.1 | 3.7 s |
| 9 | Mountain scroller (`MNTSCRL`) | 2 | 3:51.1 | 4:20.2 | 29.1 s |
| 10 | Lens, then rotozoomer (`LNS&ZOOM`) | 2 | 4:20.2 | 5:05.6 | 45.4 s |
| 11 | Plasma (`PLZPART`, first half) | 2 | 5:05.6 | 5:43.7 | 38.0 s |
| 11 | Plasma cube (`PLZPART`, second half), incl. 0.7 s of empty screen | 2 | 5:43.7 | 6:12.9 | 29.2 s |
| 12 | Bouncing dots (`MINVBALL`) | 2 | 6:12.9 | 6:49.8 | 36.9 s |
| 13 | Water scroller (`RAYSCRL`) | 2 | 6:49.8 | 7:19.2 | 29.5 s |
| 14 | 3D sine landscape (`3DSINFLD`) | 2 | 7:19.2 | 7:48.3 | 29.1 s |
| 15 | Jelly logo (`JPLOGO`) | 2 | 7:48.3 | 7:59.6 | 11.3 s |
| 16 | 3D city (`U2E`) | 1, from section 18 | 7:59.6 | 8:55.3 | 55.7 s |
| 17 | End picture (`ENDLOGO`) | 1 | 8:55.3 | 9:03.8 | 8.6 s |
| 18 | Credits (`CRED`) | 1 | 9:03.8 | 10:52.4 | 108.6 s |
| 19 | End scroller (`ENDSCRL`) | 1 | 10:52.4 | 16:21.0 (the demo's end) | 328.6 s |

The hidden starfield (`DDSTARS`) is not in the normal run: the loader plays it only when chosen
specially, over song 1 from section 70.

## Play Demo: how the app follows this table

**Scene ▸ Play Demo** (or P) runs the table above in the app, with the music live.

- **The script** (`Sources/SRMetal/Demo/DemoSequencer.swift`, `DemoScript.steps`) is
  `tools/demo_timeline.py` written again in Swift, step for step: "start song 2 at section 0", "wait 1,060
  steps", "wait until music plus ≥ -4", "show the rings", and so on. `DemoSequencer` follows it one 1/70 s
  step at a time, reading the music's section and row from the player each step.
- **The music position** comes from the sound output itself: after each block of sound (a few
  milliseconds) the player notes the section and row it has reached, and the sequencer works out "music
  plus" and the sync value from them (`Music/MusicPosition.swift`). Song 1 is loaded at tempo 120.
- **Checked:** `SRMetal --demo-timeline` (and the self-test) run the same script against the music rendered
  silently, as `tools/music_steps.c` does, and every part starts on exactly the step the Python simulation
  gives; the credits end at step 45,670 (10:52.4).
- **What each part shows** (`Demo/DemoRunScene.swift`):

  | Part | Shown now |
  |---|---|
  | Opening credits | Its own scene: the titles and pages on their music cues, the horizon scrolling to the picture the ships start on |
  | Lens, rotozoomer | Their own scenes: the lens follows both music cues, the rotozoomer turns white on its cue |
  | End scroller | Its own scene, to the text's `%` line, where the released program quit: the demo's end |
  | Troll, screen switch-off | Their own scenes: the troll scrolls in on its music cue, shakes and flashes; the screen collapses to a line and a dot |
  | Explosion | The Ships horizon while the original waited for its cue, then the Explosion scene |
  | Ships fly-by | The ships horizon picture while the original waited, then the Ships Fly-by scene: the whole flight, a frame a step, with no pause |
  | Title picture, end picture | Their own scenes: out of white, as the original; the end picture waits for its music cue and fades to black |
  | Jelly logo | Its own scene: slides in, waits for its music cue, then 700 steps of jelly |
  | Mountain scroller | Its own scene: the leaves fade in, the scroll starts and the fade-out begins on the music cues |
  | Water scroller | Its own scene: black until its first music cue, the fade-in, the still picture until the music's next section, the sword until the fade-out cue |
  | 3D sine landscape | Its own scene: black until its music cue, the rise, the sinking on the music's "plus" above -30, cut at -7 |
  | Plasma cube | Its own scene: an empty screen until its music cue, then the original's frames from the first, black at the cut |
  | Plasma | Its own scene: white until its music cue, the first palette fading down from white, the three falls on the music's tick counter, empty after the third |
  | 3D city | Its own scene: the jelly logo's last picture fading to white, the white window, the wait for section 19, the flight, the shifted whitening into the end picture |
  | Glenz | Its own scene: the title picture held until its music cue, the wipe to grey behind black bars, the plate, the pause until the music's tick counter reaches 333, the glenz, black until the tunnel |
  | Tunnel, dots | The project's scene, started at the part's start and cut at its end; they fit exactly |
  | Techno | Black, rings, interference (its flash to white, then the original's lead-in: four columns wiped to black on four beats, shown by the interference scene), techno bars (all three sections: the third cut by the music, see the scene's page), then the Troll scene, each at the original's moment |
  | Loader's wait after the switch-off | Black |
  | Credits | Its own scene: 21 screens of 362 steps, the released pictures and texts |

  Inside Play Demo every scene follows the original part's own steps and music cues. On its own each
  keeps its standalone timing, which loops and may differ from the original on purpose. The Dot
  Tunnel (1,060 steps) and Bouncing Dots (2,580) fit their parts exactly. The end scroller runs
  to its text's `%` line (16:21.0; the music runs out at 15:57.7), where the demo ends: the screen stays
  black and the scene list opens. (`--end-scroller-steps 350` with `--scene play-demo --from end-scroller`
  tries that ending after 5 seconds instead of five and a half minutes.)
- **The output's delay:** sound is heard a little after it is rendered, and over Bluetooth
  headphones a good deal after (AirPods report 160 ms; the MacBook's speakers 15.6 ms). With **Music ▸
  Allow for Output Delay** on (the default) the script reads the position whose sound is being heard
  now, by the delay macOS reports for the output device, so the picture stays on the beat. The menu
  item shows the delay in use. Off, the newest rendered position is read.
- **Keeping up:** the visuals step by the screen clock and the music by the sound card's, as in 1993;
  parts that wait for the music fall back into step. A stall in drawing of up to 5 seconds is made up
  at once (`DemoRunScene.longestCatchUp`). While the window cannot be seen or the Mac sleeps, picture
  and music PAUSE TOGETHER and carry on from the same place. Making a scene (the city loads its 3D
  data) can take a moment at the start of a part.

### Starting part-way ("Play Demo from Here")

Play Demo can start where a scene first shows or where a part begins (Scene menu, or `--from`). The script
is run silently up to that step, with the music rendered silently as in `--demo-timeline` (the whole demo
takes about 0.2 s), then carried on live: the song the script last started is started again from the same
section, and the time it has played since is rendered and thrown away (to the sample; about 0.15 s even
six minutes into song 2), so the music is exactly where a full run's would be. (libopenmpt's own "jump to a
time" is not used: it lands at the start of a row, and in song 1 after its "---" marks its clock
counts from a different place.) The scene is then shown as in a full run, including the music it is told on the step it first
shows (the lens's cue is already met there).

Checked: from each of the 24 scenes and 20 parts, a silent run carried on this way starts every later
part on exactly the step of a full run (self-test); music skipped into is sample for sample the music
played through (self-test, three places); and with the real sound output (`--demo-live`), later parts
started within 0-3 steps (at most 0.04 s) of a full run, from the switch-off, the rotozoomer and the
end picture.

## How the music is used

- **Song 1** is `MUSIC0.S3M` (Skaven), **song 2** `MUSIC1.S3M` (Purple Motion). The loader
  (`MAIN/U2.ASM` lines 760-940) starts song 1 at section 0, switches to song 2 at section 0 after
  the title picture, and goes back to song 1 at section 18 for the city; the end parts carry on over it.
- **The demo played song 1 at tempo 120**, not the 125 in the file: `MAIN/STARTMUS.C` sets byte 50
  of the module (its starting tempo) to 0x78 when loading it. At 120 every section of song 1 lasts
  exactly 8 seconds.
- Parts waited on four things, all provided by DIS (`DIS/DISINT.ASM`) from the music player:
  - **"music plus"** (`dis_musplus`, `muscode_6`): counts rows towards and after a "+++" separator in
    the song's order list: -32 normally; in the section before a separator, row minus 64 (so -31...-1
    over its last 31 rows); in the section after one, the row number (0...31). Song 2 has 15
    separators and most of its parts start or end on them.
  - **the sync table** (`dis_sync`, `sync_10`): a fixed list of song positions numbered 1...10, used
    by the opening credits and the explosion.
  - **the section and row** themselves (ships, city, techno's troll, water).
  - **the music frame counter** (`dis_getmframe`): music ticks since the part last set it (see below).
- Other parts simply run for a fixed number of screen refreshes (tunnel 1,060; credits 7,602).

## Two questions the source could not answer

The music player's source (STMIK) is not in the source release, so two details had to be settled
another way:

1. **The music frame counter counts music ticks**, not screen refreshes. The player's library ships
   compiled (`MAIN/STMIK.300`), and its symbol table names the counter `np_zframe`. It is increased in one
   place only, the routine at 4353h, which runs once per music tick and is the one that moves the song
   on a row. With a Gravis Ultrasound or no sound card the player was polled once a screen refresh and
   ran a tick whenever a 16-bit sum of its "speed adjust" overflowed (5165h); `MAIN/U2.ASM` 769-774
   sets that to 45000 for song 1 and 48700 for song 2, which is 48.07 and 52.02 ticks a second: the
   songs' tempos 120 and 130 (2 x tempo / 5 ticks a second). The script counts it the same way
   (`DemoSequencer.tickCounter`, and `Music.tk` in the simulation).

   Three parts read it: techno (the interference ends at 925 ticks, the bars at 2520), Glenz and the
   plasma.

   **Glenz and the plasma, from the released programs** (videos of the original agree: three
   plasmas, the grey one last, the cube right after; the tunnel almost at once after the glenz
   fades). Both programs were unpacked and read at the places that call the counter.
   - *Glenz* (`GLENZ.EXE`, byte for byte the `V.EXE` in the source folder): the same as `MAIN.C`: the
     cue at "music plus" -19, the counter set to 0, waits for 300 and 333, the end between -16 and 0.
     Worked out with the simulation: 333 ticks are 448 refreshes, so the glenz appears 6.4 s after the
     cue (4.8 s if it counted refreshes), and the plate rests for 226 refreshes. The end is a song position, so
     the tunnel does not move: 2,150 glenz frames show, and the glenz's own fade to black (done by
     frame 2,133) ends a quarter of a second before the tunnel.
   - *Plasma* (`PLZPART.EXE`): **the released program is not `PLZ.C` as it stands.** Its loop ends when
     `curpal` is 4 (the source says 5), so the third fall ends the part and the fourth palette is never
     shown. The timetable is unchanged (723, 1491, 1875, 2259, 2778: "64 rows x 6 ticks x 2, 4, 5, 6
     patterns, less 45"), and so is the palette code. Song 2 has exactly five patterns between the
     plasma's "+++" and the next one, and in ticks the three falls fit them: they start 974, 2,007 and
     2,524 refreshes after the cue (row 56 of sections 63, 65 and 66), the band is gone 64 refreshes
     later, on the first row after the "+++", and the cube's cue (row 13) comes 48 refreshes after
     that. The source's fourth fall would have come a whole pattern into the cube's music, and with
     it every later part would miss its cue: one reason the counter was long taken for refreshes.
   - The released plasma's fade memory starts as zeros, so its first palette ends one level brighter
     (see `docs/scenes/plasma.md`, "The released program").
2. **Is the player's section number the section playing, or the next one?** Most likely the one
   playing: against a recording of the original (youtu.be/iw17c70uJes) the sine landscape comes out
   at 439-468 s this way, and 431-460 s the other way; the recording shows it at 441-467 s. (This
   assumes the recording's time 0 is within a second or two of the music's start.)

## Simplifications, and what is not checked

- **Opening credits' end:** worked out from the released program, it is 2,947 refreshes after sync 4 (titles on syncs 1-3, each at
  least 427 refreshes; the scroll 320 x 9 refreshes; the last fade and the hand-over): 1:20.1. Nothing
  after it moved, because the ships wait for a fixed song position. See `docs/scenes/opening-credits.md`.
- **Loading time between parts** (reading each program from disk, a fraction of a second on a 486)
  is not counted.
- **The switch-off** ends with a `sleep(1)`, counted as 70 refreshes.
- `LENS/MAIN.C` line 104 compares the address of `dis_musplus` instead of calling it (a bug); the
  simulation assumes the wait after it runs, as it would if the comparison is true.
- Not compared with a running original, except the landscape against the recording (see above for
  the assumption that check rests on).
- Kept as the original has them: the explosion runs 45 steps of 4 refreshes; the title picture's 161 refreshes;
  the city's 100 refreshes of fades before it waits for section 19.

## Sources of each condition

| Part | Start | End |
|---|---|---|
| ALKU | music start; texts on sync 1-4 (`ALKU/MAIN.C` 59-79) | scroll waits sync up to 9 (138), then finishes |
| U2A | section > 10 and row > 46 (`VISU/C/U2A.C` 229-240) | section > 11 and row > 54, or the animation's 521 frames (268-276) |
| PAM | sync ≥ 10 (`PAM/OUTTAA.C` 39) | 45 steps of 4 refreshes |
| BEG | — | 32 + 129 refreshes (`BEG/BEG.C` 24, 80-85) |
| GLENZ | 47-refresh lead-in, music plus ≥ -19 (`GLENZ/MAIN.C` 290); the glenz itself at 333 music ticks (400) | after its intro, -16 < music plus < 0 (409-411) |
| TUNNELI | — | 1,060 refreshes (`TUNNELI/TUN10.PAS` 3, 221) |
| TECHNO | music plus ≥ -4 (`TECHNO/KOE.C` 213) | troll waits section > 35 or 35 row > 48 (638-648), then ≤ 420 refreshes or -6 < music plus < 16 (704-709) |
| PANICEND | — | 121 refreshes + `sleep(1)` (`PANIC/SHUTDOWN.C`) |
| loader | music plus < 0, then > 0 (`MAIN/U2.ASM` 828-850) | |
| MNTSCRL | 64-refresh fade, music plus ≥ 0 (`FOREST/READ2.PAS` 153-159), 127 refreshes | music plus = -11, then 65 refreshes (196-207) |
| LNS&ZOOM | music plus ≥ -6 (`LENS/MAIN.C` 104) | 300 + wait music plus ≥ -20 + 720 + rotozoomer until music plus > -4 (211-213) |
| PLZ | music plus ≥ 0 (`PLZPART/PLZ.C` 68) | music ticks > 1875, the third fall, then 65 refreshes (79-91; the RELEASED program: `PLZ.C` says the fourth, 2259) |
| VECT | music plus ≥ 13 (`PLZPART/VECT.C` 116) | -4 ≤ music plus < 0 (119-120) |
| DOTS | 130-refresh fade (`DOTS/MAIN.C` 171-180) | 2,450 refreshes or -3 ≤ music plus ≤ -1 (185-194) |
| WATER | music plus ≥ 0 (20 refreshes of black), a 127-refresh fade-in, then a new section at row ≥ 16 (519 refreshes of the still picture; `WATER/DEMO.PAS` 97-145) | music plus = -11, then 65 refreshes (159-189) |
| COMAN | music plus ≥ 0 (`COMAN/MAIN.C` 56) | 4,444 refreshes or -7 ≤ music plus ≤ -1 (57-60) |
| JPLOGO | 86-refresh drop-in, music plus ≥ 4 (`JPLOGO/JP.C` 71) | 700 refreshes (72) |
| U2E | 100 refreshes of fades, section > 18 (`VISU/C/U2E.C` 285-366) | the animation's 1,801 frames × 2 refreshes, then a 16-refresh fade |
| ENDLOGO | 163 refreshes (`END/END.C` 61-106) | music plus > -16 (110), then a 64-refresh fade |
| CRED | — | 21 pictures × 362 refreshes (`CREDITS/MAIN.C`) |
| ENDSCRL | — | the text's `%` line: the released program calls `exit(0)` there (`ENDSCRL/MAIN.C` 45-56 loops until a key; the released `ENDSCRL.EXE` differs) |
