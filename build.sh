#!/bin/sh
# Builds the program and wraps it as a double-clickable Mac app in build/SRMetal.app.
set -e
cd "$(dirname "$0")"

swift build -c release

APP="build/SRMetal.app"
rm -rf "$APP"
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

# Sign for this Mac only ("ad-hoc"), so macOS will run it without complaint.
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
