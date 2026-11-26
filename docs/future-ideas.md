# What may come next

The demo itself is finished: every part is a scene in both looks, and Play Demo runs the whole of it on
the original music's cues. This page lists what is wanted around it. Nothing here is started; each is
planned with the user first. (Rewritten 2026-11-25. The earlier page held two ideas from 2026-11-14: a
third, "Reimagined" look, which was dropped, and the whole demo in the Modern look, which was built as
Play Demo. Its text is in the repository's history.)

## Export Play Demo to a video file

Wanted for YouTube, in the Modern look only (the 1993 look's 70 pictures a second do not fit YouTube's
60). The idea as discussed so far:

- A command steps Play Demo against silently rendered music, as `--demo-timeline` does, so nothing
  depends on the speed of the Mac or on a window.
- Each frame is drawn off screen, as `--snapshot` does, at 60 a second, with the Modern look's blend
  between steps taken at each frame's exact moment, at 2880x2160 (4:3; YouTube's "4K").
- The frames and the rendered music go to ffmpeg, a development tool only: the app and `build.sh` never
  need it.
- The sound output's delay (Music ▸ Allow for Output Delay) must not be used: an exported file has none.
- It needs a check that sound and picture stay in step in the finished file.

## The app's window and menus

The user wants to look again at the interface (the sidebar, the look switch, the menus, the window
title) and see what could be better. Not yet discussed.

## A signed release

So the app opens on other Macs without a warning, outside the App Store: signed with a Developer ID
certificate and notarised by Apple. Still to do then: the certificate and an app-specific password (kept
in the keychain, never in the repository), a release mode in `build.sh` (sign with the hardened runtime,
zip, `notarytool submit`, `stapler staple`), an app icon and a version number. `notarytool` and
`stapler` come with the Command Line Tools.
