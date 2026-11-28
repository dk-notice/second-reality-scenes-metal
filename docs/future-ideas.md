# What may come next

The demo itself is finished: every part is a scene in both looks, Play Demo runs the whole of it on the
original music's cues, and it can be exported as a video.

## A signed release

So the app opens on other Macs without a warning, outside the App Store: signed with a Developer ID
certificate and notarised by Apple. That needs the certificate and an app-specific password (kept in the
keychain, never in the repository), a release mode in `build.sh` (sign with the hardened runtime, zip,
`notarytool submit`, `stapler staple`), an app icon and a version number. `notarytool` and `stapler`
come with the Command Line Tools.
