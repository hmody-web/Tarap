#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
OUT="Tarab_5.11_LayoutCleaner_SAFE_V3.ipa"

INPUT="$(find "$ROOT" -maxdepth 3 -type f -name '*.ipa' \
 ! -name "$OUT" ! -name '*LayoutCleaner_SAFE_V2*' ! -name '*LayoutCleaner.ipa' \
 | head -1 || true)"
[ -n "$INPUT" ] || { echo "❌ No input IPA found"; find . -maxdepth 3 -type f | sort; exit 1; }
echo "✅ Input: $INPUT"

WORK="$ROOT/work_v3"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"
unzip -q "$INPUT"

APP="$(find Payload -maxdepth 1 -type d -name '*.app' | head -1)"
EXEC_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")
EXEC="$APP/$EXEC_NAME"
FW="$APP/Frameworks/LayoutCleaner.framework"

rm -rf "$FW"; mkdir -p "$FW"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

echo "==> Building V3"
xcrun clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 \
 -fobjc-arc -dynamiclib "$ROOT/LayoutCleaner.m" \
 -framework Foundation -framework UIKit \
 -install_name '@rpath/LayoutCleaner.framework/LayoutCleaner' \
 -o "$FW/LayoutCleaner"
chmod 755 "$FW/LayoutCleaner"

cat > "$FW/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LayoutCleaner</string>
<key>CFBundleIdentifier</key><string>com.alsaray.LayoutCleaner</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>LayoutCleaner</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>MinimumOSVersion</key><string>15.0</string>
</dict></plist>
EOF

if ! otool -L "$EXEC" | grep -q '@rpath/LayoutCleaner.framework/LayoutCleaner'; then
 python3 "$ROOT/inject_dylib.py" "$EXEC" '@rpath/LayoutCleaner.framework/LayoutCleaner'
else
 echo "✅ Existing LayoutCleaner load command retained"
fi

echo "==> Verify"
otool -L "$EXEC" | grep -E 'LayoutCleaner|ProfileOverlay|PortraitOverlay' || true
rm -rf "$APP/_CodeSignature"

cd "$WORK"
rm -f "$ROOT/$OUT"
zip -qry "$ROOT/$OUT" Payload
echo "✅ Output: $ROOT/$OUT"
echo "⚠️ Re-sign before installing"
