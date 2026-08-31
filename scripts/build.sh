#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/ProfileOverlay/ProfileOverlay.m"
IMG="$ROOT/ProfileOverlay/portrait.jpeg"
FW="$ROOT/build/ProfileOverlay.framework"
test -f "$SRC" || { echo "Missing: $SRC"; find "$ROOT" -maxdepth 3 -type f; exit 1; }
test -f "$IMG" || { echo "Missing: $IMG"; find "$ROOT" -maxdepth 3 -type f; exit 1; }
rm -rf "$ROOT/build"; mkdir -p "$FW"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --find clang)"
"$CLANG" -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 -fobjc-arc -dynamiclib -framework UIKit -framework Foundation -framework QuartzCore -install_name @rpath/ProfileOverlay.framework/ProfileOverlay "$SRC" -o "$FW/ProfileOverlay"
cp "$IMG" "$FW/portrait.jpeg"
cat > "$FW/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ProfileOverlay</string>
<key>CFBundleIdentifier</key><string>com.alsaray.tarab.profileoverlay</string>
<key>CFBundleName</key><string>ProfileOverlay</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>15.0</string>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none "$FW"
file "$FW/ProfileOverlay"
otool -L "$FW/ProfileOverlay"
