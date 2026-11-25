#!/bin/sh
# Builds the program and wraps it as a double-clickable Mac app in build/SRMetal.app.
set -e
cd "$(dirname "$0")"

APP="build/SRMetal.app"
# Remove the last build's app BEFORE compiling. If the compile fails, the script stops (set -e)
# and there is then no app at all, rather than an old one that looks like the result of this build.
rm -rf "$APP"

# libopenmpt, the tracker-music library (ThirdParty/libopenmpt; see ThirdParty/README.md), built
# as a STATIC library with every optional format switched off, so it ends up inside the program
# and needs nothing but macOS. It is built in a copy under build/, so the source folder stays as
# released. make only recompiles what changed: the first build takes about 15 seconds, later
# ones almost nothing. A different libopenmpt version wipes the copy and starts again.
LIBOPENMPT=build/libopenmpt/src
if ! cmp -s ThirdParty/libopenmpt/libopenmpt/libopenmpt_version.h "$LIBOPENMPT/libopenmpt/libopenmpt_version.h"; then
    rm -rf build/libopenmpt
fi
mkdir -p "$LIBOPENMPT"
rsync -a ThirdParty/libopenmpt/ "$LIBOPENMPT/"
mkdir -p "$LIBOPENMPT/bin"
if ! make -C "$LIBOPENMPT" -j"$(sysctl -n hw.ncpu)" CONFIG=macos MACOSX_VERSION_MIN=15.0 \
        STATIC_LIB=1 SHARED_LIB=0 EXAMPLES=0 OPENMPT123=0 TEST=0 \
        NO_ZLIB=1 NO_MPG123=1 NO_OGG=1 NO_VORBIS=1 NO_VORBISFILE=1 \
        NO_MINIZ=1 NO_MINIMP3=1 NO_STBVORBIS=1 \
        NO_PORTAUDIO=1 NO_PORTAUDIOCPP=1 NO_SDL2=1 NO_FLAC=1 NO_SNDFILE=1 \
        > build/libopenmpt/make.log 2>&1; then
    tail -20 build/libopenmpt/make.log
    echo "libopenmpt failed to build (full log: build/libopenmpt/make.log)"
    exit 1
fi

swift build -c release

mkdir -p "$APP/Contents/MacOS"
cp .build/release/SRMetal "$APP/Contents/MacOS/SRMetal"

# Original 3D data (models and animation) for the VISU engine: see Data/Visu/README.md.
mkdir -p "$APP/Contents/Resources/Visu"
cp Data/Visu/U2* "$APP/Contents/Resources/Visu/"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SR Metal</string>
    <key>CFBundleDisplayName</key><string>SR Metal</string>
    <key>CFBundleIdentifier</key><string>local.srmetal</string>
    <key>CFBundleExecutable</key><string>SRMetal</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# The original tracker songs (scrambled as shipped; the program unscrambles them): see Data/Music/README.md.
mkdir -p "$APP/Contents/Resources/Music"
cp Data/Music/MUSIC*.S3M "$APP/Contents/Resources/Music/"

# Pictures for Play Demo: the original pictures at their own size (see artwork/README.md). About 1 MB.
mkdir -p "$APP/Contents/Resources/Artwork"
cp artwork/original/rgb/*.png "$APP/Contents/Resources/Artwork/"
cp -R artwork/original/rgb/explosion "$APP/Contents/Resources/Artwork/"

# The end scroller's text and font, as released (see Data/EndScroller/README.md).
mkdir -p "$APP/Contents/Resources/EndScroller"
cp Data/EndScroller/ENDSCROL.TXT Data/EndScroller/ENDFONT.BIN "$APP/Contents/Resources/EndScroller/"

# The lens's wiping ring, the one lens table that cannot be calculated (see Data/Lens/README.md).
mkdir -p "$APP/Contents/Resources/Lens"
cp Data/Lens/LENS.EX4 "$APP/Contents/Resources/Lens/"

# Sign for this Mac only ("ad-hoc"), so macOS will run it without complaint.
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
