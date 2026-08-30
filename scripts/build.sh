#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
FW="$OUT/PortraitOverlay.framework"
rm -rf "$OUT"
mkdir -p "$FW"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --find clang)"

"$CLANG" -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 \
  -fobjc-arc -dynamiclib \
  -framework UIKit -framework Foundation -framework QuartzCore \
  -install_name @rpath/PortraitOverlay.framework/PortraitOverlay \
  "$ROOT/PortraitOverlay/PortraitOverlay.m" \
  -o "$FW/PortraitOverlay"

cp "$ROOT/PortraitOverlay/portrait.jpeg" "$FW/portrait.jpeg"

cat > "$FW/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PortraitOverlay</string>
<key>CFBundleIdentifier</key><string>com.alsaray.tarab.portraitoverlay</string>
<key>CFBundleName</key><string>PortraitOverlay</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>15.0</string>
</dict></plist>
PLIST

codesign --force --sign - --timestamp=none "$FW"
file "$FW/PortraitOverlay"
otool -L "$FW/PortraitOverlay"
codesign -dv "$FW" 2>&1 || true
