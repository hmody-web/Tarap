#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

OUT_IPA="Tarab_MKTabBarFix_V8.ipa"
OUT_ZIP="Tarab_MKTabBarFix_V8.zip"

echo "==> Searching for ANY IPA"

INPUT="$(find "$ROOT" -maxdepth 5 -type f -name '*.ipa' \
 ! -name "$OUT_IPA" | head -1 || true)"

if [ -z "${INPUT:-}" ]; then
    echo "❌ No IPA found"
    find "$ROOT" -maxdepth 5 -type f | sort
    exit 1
fi

echo "✅ Input: $INPUT"

WORK="$ROOT/work_v8"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

unzip -q "$INPUT"

APP="$(find Payload -maxdepth 1 -type d -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "❌ No .app found"; exit 1; }

EXEC_NAME=$(/usr/libexec/PlistBuddy \
 -c 'Print :CFBundleExecutable' "$APP/Info.plist")

EXEC="$APP/$EXEC_NAME"
FW="$APP/Frameworks/LayoutCleaner.framework"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

echo "==> Checking for MKTabBarViewController"

if strings -a "$EXEC" | grep -q 'MKTabBarViewController'; then
    echo "✅ MKTabBarViewController found in executable"
else
    echo "⚠️ MKTabBarViewController string not found"
fi

echo "==> Building V8"

rm -rf "$FW"
mkdir -p "$FW"

xcrun clang \
 -arch arm64 \
 -isysroot "$SDK" \
 -miphoneos-version-min=15.0 \
 -fobjc-arc \
 -dynamiclib \
 "$ROOT/LayoutCleaner.m" \
 -framework Foundation \
 -framework UIKit \
 -install_name '@rpath/LayoutCleaner.framework/LayoutCleaner' \
 -o "$FW/LayoutCleaner"

chmod 755 "$FW/LayoutCleaner"

cat > "$FW/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LayoutCleaner</string>
<key>CFBundleIdentifier</key><string>com.alsaray.LayoutCleaner</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>LayoutCleaner</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>8.0</string>
<key>CFBundleVersion</key><string>80</string>
<key>MinimumOSVersion</key><string>15.0</string>
</dict></plist>
EOF

if otool -L "$EXEC" | grep -q \
 '@rpath/LayoutCleaner.framework/LayoutCleaner'; then
    echo "✅ Existing LayoutCleaner load command retained"
else
    echo "==> Injecting load command"

    python3 "$ROOT/inject_dylib.py" \
      "$EXEC" \
      '@rpath/LayoutCleaner.framework/LayoutCleaner'
fi

echo "==> Verification"

otool -L "$EXEC" | grep -E \
 'LayoutCleaner|ProfileOverlay|PortraitOverlay' || true

rm -rf "$APP/_CodeSignature"

echo "==> Packing IPA"

cd "$WORK"
rm -f "$ROOT/$OUT_IPA"
zip -qry "$ROOT/$OUT_IPA" Payload

echo "==> Packing ZIP artifact"

cd "$ROOT"
rm -f "$OUT_ZIP"
zip -q "$OUT_ZIP" "$OUT_IPA"
zip -q "$OUT_ZIP" "README_AR.txt"

echo "✅ Output ZIP: $ROOT/$OUT_ZIP"
