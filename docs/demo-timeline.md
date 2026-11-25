# The demo's timeline

When each part of *Second Reality* starts and ends, worked out on 2026-11-24 as the groundwork for a
"Play Demo" mode. Every part waited on the music in its own way; these conditions were read from the
original source, then **simulated against the real music** (libopenmpt playing the original songs,
stepped 1/70 second at a time) to turn them into times. Tools: `tools/music_steps.c` and
`tools/demo_timeline.py` (usage at the top of each).

## The result

Times are from the moment the music starts (after the setup screen). "Have" says what this project
already has for the part.

| # | Part | Song | Starts | Ends | Length | Have |
|---|---|---|---|---|---|---|
| 1 | Opening credits (`ALKU`) | 1 | 0:00.0 | 1:12.9 | 72.9 s | Picture: horizon, font |
| 2 | Ships fly-by (`U2A`), incl. ~21 s of horizon before the ships | 1 | 1:12.9 | 1:41.2 | 28.3 s | **Scene** |
| 3 | Explosion (`PAM`), incl. ~2.7 s wait | 1 | 1:41.2 | 1:46.6 | 5.4 s | 40 frames |
| 4 | Title picture (`BEGLOGO`) | 1 | 1:46.6 | 1:48.9 | 2.3 s | Picture |
| 5 | Glenz vectors (`GLENZ`) | 2 | 1:48.9 | 2:32.6 | 43.7 s | **Scene** |
| 6 | Dot tunnel (`TUNNELI`) | 2 | 2:32.6 | 2:47.7 | 15.1 s | **Scene** |
| 7 | Rings, interference, techno bars, troll (`TECHNO`) | 2 | 2:47.7 | 3:44.7 | 56.9 s | **3 scenes** + troll picture |
| 8 | Screen switches off (`PANICEND`) | 2 | 3:44.7 | 3:47.4 | 2.7 s | — |
| — | (the loader waits for the next "+++" in the music) | 2 | 3:47.4 | 3:51.1 | 3.7 s | — |
| 9 | Mountain scroller (`MNTSCRL`) | 2 | 3:51.1 | 4:20.2 | 29.1 s | Picture, font |
| 10 | Lens, then rotozoomer (`LNS&ZOOM`) | 2 | 4:20.2 | 5:05.6 | 45.4 s | Picture |
| 11 | Plasma (`PLZPART`, first half) | 2 | 5:05.6 | 5:39.9 | 34.3 s | **Scene** |
| 11 | Plasma cube (`PLZPART`, second half) | 2 | 5:39.9 | 6:12.9 | 33.0 s | **Scene** |
| 12 | Bouncing dots (`MINVBALL`) | 2 | 6:12.9 | 6:49.8 | 36.9 s | **Scene** |
| 13 | Water scroller (`RAYSCRL`) | 2 | 6:49.8 | 7:19.2 | 29.5 s | Picture, font |
| 14 | 3D sine landscape (`3DSINFLD`) | 2 | 7:19.2 | 7:48.3 | 29.1 s | **Scene** |
| 15 | Jelly logo (`JPLOGO`) | 2 | 7:48.3 | 7:59.6 | 11.3 s | Picture |
| 16 | 3D city (`U2E`) | 1, from section 18 | 7:59.6 | 8:55.3 | 55.7 s | **Scene** |
| 17 | End picture (`ENDLOGO`) | 1 | 8:55.3 | 9:03.8 | 8.6 s | Picture |
| 18 | Credits (`CRED`) | 1 | 9:03.8 | 10:52.4 | 108.6 s | 21 pictures, font (stopgaps) |
| 19 | End scroller (`ENDSCRL`) | 1 | 10:52.4 | until a key | — | Font, text |

The hidden starfield (`DDSTARS`) is not in the normal run: the loader plays it only when chosen
specially, over song 1 from section 70.

## Play Demo: how the app follows this table

Built 2026-11-24. **Scene ▸ Play Demo** (or P) runs the table above in the app, with the music live.

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
- **Stand-ins** (`Demo/DemoRunScene.swift`), until each part is built properly:

  | Part | Shown now |
  |---|---|
  | Opening credits, explosion, switch-off, rotozoomer, end scroller | A title card naming the part |
  | Ships fly-by | The ships horizon picture while the original waited, then the Ships Fly-by scene |
  | Title, mountain, lens, water, jelly logo, end picture | The original picture: hard-edged pixels in the 1993 look; in the Modern look made 8x larger by Super-xBR, then smoothly scaled |
  | Glenz, tunnel, plasma, plasma cube, dots, landscape, city | The project's scene, started at the part's start and cut at its end |
  | Techno | Black, rings, interference, black (the original's lead-in on four beats), techno bars, then the troll picture, each at the original's moment |
  | Loader's wait after the switch-off | Black |
  | Credits | The 21 credits pictures in the original order, 362 steps each |

  The scenes keep their own timing (they loop and differ from the original on purpose), so a scene
  may loop or be cut mid-way. The end scroller's card stays, with the music playing, until the demo is
  stopped (Escape).
- **Known limits:** the visuals step by the screen clock and the music by the sound card's, as in 1993;
  parts that wait for the music fall back into step. If the window cannot draw for a while (hidden,
  Mac asleep), the visuals fall behind for up to the end of the part. Making a scene (the city loads
  its 3D data) can take a moment at the start of a part.

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
  - **the music frame counter** (`dis_getmframe`): see below.
- Other parts simply run for a fixed number of screen refreshes (tunnel 1,060; credits 7,602).

## Two questions the source could not answer, settled by simulation

The music player (STMIK) is not in the source release, so two details had to be tested:

1. **Does the "music frame counter" count music ticks or screen refreshes?** Most likely screen
   refreshes (1/70 s). With music ticks the plasma and plasma cube run so much longer that the sine
   landscape misses its music cue (it hits its 63.5 s limit) and song 2 reaches its end before the
   jelly logo's cue, which would then come only after the song looped back to its start: possible,
   but clearly not what was intended. And a recording (youtu.be/iw17c70uJes, already used for the
   sine landscape's speed) shows the landscape at 441-467 s; the simulation gives 439-468 s with
   screen refreshes and 469-533 s with ticks. This answers the old question in
   `docs/scenes/plasma.md` in favour of 1/70 s, as this project built it.
2. **Is the player's section number the section playing, or the next one?** Most likely the one
   playing: against the same recording the landscape comes out at 439-468 s this way, and
   431-460 s the other way.

   Both checks against the recording assume its time 0 is within a second or two of the music's
   start. That is not yet confirmed: the recording is 16 min 18 s long, and its first seconds are
   black. To confirm, find a sharp early event in it (the explosion's white flash, predicted at about
   1:44, or the title picture at 1:47-1:49) and compare.

## Simplifications, and what is not checked

- **Opening credits' end** is approximate (when the scroll finishes after sync value 9, taken as 60
  refreshes); it does not change anything after it, because the ships wait for a fixed song position.
- **Loading time between parts** (reading each program from disk, a fraction of a second on a 486)
  is not counted.
- **The switch-off** ends with a `sleep(1)`, counted as 70 refreshes.
- `LENS/MAIN.C` line 104 compares the address of `dis_musplus` instead of calling it (a bug); the
  simulation assumes the wait after it runs, as it would if the comparison is true.
- `MAIN/U2.ASM` passes a "speed adjust" (45000 or 48700) to the player for some sound cards; its
  meaning is unknown (the player's source is missing). Not modelled.
- Not compared with a running original, except the landscape against the recording (see above for
  the assumption that check rests on).
- Kept quirks for later: the explosion runs 45 steps of 4 refreshes; the title picture's 161 refreshes;
  the city's 100 refreshes of fades before it waits for section 19.

## Sources of each condition

| Part | Start | End |
|---|---|---|
| ALKU | music start; texts on sync 1-4 (`ALKU/MAIN.C` 59-79) | scroll waits sync up to 9 (138), then finishes |
| U2A | section > 10 and row > 46 (`VISU/C/U2A.C` 229-240) | section > 11 and row > 54, or the animation's 521 frames (268-276) |
| PAM | sync ≥ 10 (`PAM/OUTTAA.C` 39) | 45 steps of 4 refreshes |
| BEG | — | 32 + 129 refreshes (`BEG/BEG.C` 24, 80-85) |
| GLENZ | 47-refresh lead-in, music plus ≥ -19 (`GLENZ/MAIN.C` 290) | after its intro, -16 < music plus < 0 (409-411) |
| TUNNELI | — | 1,060 refreshes (`TUNNELI/TUN10.PAS` 3, 221) |
| TECHNO | music plus ≥ -4 (`TECHNO/KOE.C` 213) | troll waits section > 35 or 35 row > 48 (638-648), then ≤ 420 refreshes or -6 < music plus < 16 (704-709) |
| PANICEND | — | 121 refreshes + `sleep(1)` (`PANIC/SHUTDOWN.C`) |
| loader | music plus < 0, then > 0 (`MAIN/U2.ASM` 828-850) | |
| MNTSCRL | 64-refresh fade, music plus ≥ 0 (`FOREST/READ2.PAS` 153-159) | music plus = -11, then 65 refreshes (196-207) |
| LNS&ZOOM | music plus ≥ -6 (`LENS/MAIN.C` 104) | 300 + wait music plus ≥ -20 + 720 + rotozoomer until music plus > -4 (211-213) |
| PLZ | music plus ≥ 0 (`PLZPART/PLZ.C` 68) | music frame > 2259, then ~64 refreshes (79-91) |
| VECT | music plus ≥ 13 (`PLZPART/VECT.C` 116) | -4 ≤ music plus < 0 (119-120) |
| DOTS | 130-refresh fade (`DOTS/MAIN.C` 171-180) | 2,450 refreshes or -3 ≤ music plus ≤ -1 (185-194) |
| WATER | music plus ≥ 0, then a new section at row ≥ 16 (`WATER/DEMO.PAS` 97-145) | music plus = -11, then 65 refreshes (159-189) |
| COMAN | music plus ≥ 0 (`COMAN/MAIN.C` 56) | 4,444 refreshes or -7 ≤ music plus ≤ -1 (57-60) |
| JPLOGO | 86-refresh drop-in, music plus ≥ 4 (`JPLOGO/JP.C` 71) | 700 refreshes (72) |
| U2E | 100 refreshes of fades, section > 18 (`VISU/C/U2E.C` 285-366) | the animation's 1,801 frames × 2 refreshes, then a 16-refresh fade |
| ENDLOGO | 163 refreshes (`END/END.C` 61-106) | music plus > -16 (110), then a 64-refresh fade |
| CRED | — | 21 pictures × 362 refreshes (`CREDITS/MAIN.C`) |
| ENDSCRL | — | only on a key press (`ENDSCRL/MAIN.C` 45-56) |
