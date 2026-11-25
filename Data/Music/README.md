# The demo's music

The two songs of *Second Reality*, copied unchanged from the original source release
(`MAIN/MUSIC0.S3M`, `MAIN/MUSIC1.S3M`), which Future Crew released into the public domain in 2013.

| File | Title | Composer | Used for |
|---|---|---|---|
| `MUSIC0.S3M` | "UnreaL ][ - The 2ND Reality" | Skaven | The first half of the demo |
| `MUSIC1.S3M` | "UnreaL ][ / PM" | Purple Motion | The second half |

Both are Scream Tracker 3 files (8 channels). `build.sh` copies them into the app as
`SRMetal.app/Contents/Resources/Music`, and the program plays them with libopenmpt
(see `ThirdParty/README.md`).

## They are scrambled

Future Crew scrambled the notes (the "pattern" data) of both songs, probably so the music could not
simply be ripped out of the demo. Ordinary players cannot play these files. The program unscrambles
them as it loads them (`Sources/SRMetal/Music/MusicData.swift`): in each pattern block, every byte
after the block's 2-byte length is XOR-ed with `i ^ (4 * i)`, `i` being the byte's position in the
block. Unscrambled, every pattern holds exactly 64 rows, which the program checks.

Checked 2026-11-24: unscrambled `MUSIC0.S3M` matches a widely circulated unscrambled copy
("2ND_SKAV.S3M") byte for byte, except that copy's order list, which was edited so that ordinary
players play straight through. The demo's own order list is kept here, because its "+++" separators
and "---" ends are what the demo's parts synchronised on.

To get standard S3M files to open in a tracker or player:

```bash
build/SRMetal.app/Contents/MacOS/SRMetal --music-info --write <folder>
```

## SHA-256

To check the two files (run in this folder): `shasum -a 256 -c` with these lines.

```text
aacdb968ae9ebf07bfa02af129fb43f1b15101ab3a94c95b7f5fe69840d28fe1  MUSIC0.S3M
3393f848a4840b53aa247c4158e414bad848879e7f6059e214631c310e8dde54  MUSIC1.S3M
```
