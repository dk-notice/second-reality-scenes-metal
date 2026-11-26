# What may come next

The demo itself is finished: every part is a scene in both looks, and Play Demo runs the whole of it on
the original music's cues. This page lists what is wanted around it. Nothing here is started; each is
planned with the user first. (Rewritten 2026-11-25. The earlier page held two ideas from 2026-11-14: a
third, "Reimagined" look, which was dropped, and the whole demo in the Modern look, which was built as
Play Demo. Its text is in the repository's history.)

## Export Play Demo to a video file

Wanted for YouTube, in the Modern look only (the 1993 look's 70 pictures a second do not fit YouTube's
60). Decided with the user on 2026-11-25 and being built:

- The whole demo, 2880x2160 (4:3; YouTube's "4K") at 60 pictures a second, as ProRes 422 with PCM sound
  in a .mov file in `~/Movies/`. It ends after one full pass of the end scroller's text, with a
  2-second fade to black.
- A command steps Play Demo against silently rendered music, as `--demo-timeline` does, so nothing
  depends on the speed of the Mac or on a window, and draws each frame off screen with the Modern
  look's blend taken at that frame's exact moment. The sound output's delay is not involved.
- The program writes raw frames and the sound; a script in `tools/` hands them to ffmpeg, a
  development tool only: the app and `build.sh` never need it.
- Checks prove sound and picture are in step, in the self-test and on the finished file.

## The app's window and menus

The user wants to look again at the interface (the sidebar, the look switch, the menus, the window
title) and see what could be better. Not yet discussed.

## A signed release

So the app opens on other Macs without a warning, outside the App Store: signed with a Developer ID
certificate and notarised by Apple. Still to do then: the certificate and an app-specific password (kept
in the keychain, never in the repository), a release mode in `build.sh` (sign with the hardened runtime,
zip, `notarytool submit`, `stapler staple`), an app icon and a version number. `notarytool` and
`stapler` come with the Command Line Tools.
