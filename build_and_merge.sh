#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

OUT_IPA="Tarab_RuntimeDiag_V9_3_1.ipa"
OUT_ZIP="Tarab_RuntimeDiag_V9_3_1.zip"

INPUT="$(find "$ROOT" -maxdepth 5 -type f -name '*.ipa' \
 ! -name "$OUT_IPA" | head -1 || true)"

if [ -z "${INPUT:-}" ]; then
    echo "❌ No IPA found"
    exit 1
fi

echo "✅ Input: $INPUT"

WORK="$ROOT/work_v9_3"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

unzip -q "$INPUT"

APP="$(find Payload -maxdepth 1 -type d -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "❌ No .app found"; exit 1; }

EXEC_NAME=$(/usr/libexec/PlistBuddy \
 -c 'Print :CFBundleExecutable' "$APP/Info.plist")

EXEC="$APP/$EXEC_NAME"
FW="$APP/Frameworks/RuntimeDiag.framework"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

rm -rf "$FW"
mkdir -p "$FW"

xcrun clang \
 -arch arm64 \
 -isysroot "$SDK" \
 -miphoneos-version-min=15.0 \
 -fobjc-arc \
 -dynamiclib \
 "$ROOT/RuntimeDiag.m" \
 -framework Foundation \
 -framework UIKit \
 -install_name '@rpath/RuntimeDiag.framework/RuntimeDiag' \
 -o "$FW/RuntimeDiag"

chmod 755 "$FW/RuntimeDiag"

cat > "$FW/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RuntimeDiag</string>
<key>CFBundleIdentifier</key><string>com.alsaray.RuntimeDiag</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>RuntimeDiag</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>9.3.1</string>
<key>CFBundleVersion</key><string>931</string>
<key>MinimumOSVersion</key><string>15.0</string>
</dict></plist>
EOF

if ! otool -L "$EXEC" | grep -q \
 '@rpath/RuntimeDiag.framework/RuntimeDiag'; then
    python3 "$ROOT/inject_dylib.py" \
      "$EXEC" \
      '@rpath/RuntimeDiag.framework/RuntimeDiag'
fi

rm -rf "$APP/_CodeSignature"

cd "$WORK"
rm -f "$ROOT/$OUT_IPA"
zip -qry "$ROOT/$OUT_IPA" Payload

cd "$ROOT"
rm -f "$OUT_ZIP"
zip -q "$OUT_ZIP" "$OUT_IPA"
zip -q "$OUT_ZIP" "README_AR.txt"

echo "✅ Output: $OUT_ZIP"
