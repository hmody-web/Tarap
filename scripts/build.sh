#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"; FW="$OUT/ProfileOverlay.framework"
rm -rf "$OUT"; mkdir -p "$FW"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --find clang)"
"$CLANG" -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 -fobjc-arc -dynamiclib \
 -framework UIKit -framework Foundation -framework QuartzCore \
 -install_name @rpath/ProfileOverlay.framework/ProfileOverlay \
 "$ROOT/ProfileOverlay/ProfileOverlay.m" -o "$FW/ProfileOverlay"
cp "$ROOT/ProfileOverlay/portrait.jpeg" "$FW/portrait.jpeg"
cat > "$FW/Info.plist" <<'EOF'
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
EOF
codesign --force --sign - --timestamp=none "$FW"
file "$FW/ProfileOverlay"
otool -L "$FW/ProfileOverlay"
