#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
OUTPUT_IPA="${2:-Tarab_5.11_LayoutCleaner_SAFE_V2.ipa}"

if [ "${1:-}" != "" ] && [ -f "${1:-}" ]; then
  INPUT_IPA="$1"
else
  INPUT_IPA="$(find "$ROOT" -maxdepth 3 -type f -name '*.ipa' \
    ! -name 'Tarab_5.11_LayoutCleaner_SAFE_V2.ipa' \
    ! -name 'Tarab_5.11_LayoutCleaner.ipa' | head -1 || true)"
fi

if [ -z "${INPUT_IPA:-}" ] || [ ! -f "$INPUT_IPA" ]; then
  echo "❌ No input IPA found"
  find "$ROOT" -maxdepth 3 -type f | sort
  exit 1
fi

echo "✅ Input IPA: $INPUT_IPA"

WORK="$ROOT/work_safe_v2"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

echo "==> Unpacking IPA"
unzip -q "$INPUT_IPA"

APP="$(find Payload -maxdepth 1 -type d -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "❌ No .app inside IPA"; exit 1; }

EXEC_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")
EXEC="$APP/$EXEC_NAME"

echo "✅ App: $APP"
echo "✅ Executable: $EXEC_NAME"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
FW="$APP/Frameworks/LayoutCleaner.framework"

echo "==> Replacing old LayoutCleaner.framework if present"
rm -rf "$FW"
mkdir -p "$FW"

echo "==> Building SAFE V2 framework"
xcrun clang \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min=15.0 \
  -dynamiclib \
  -fvisibility=hidden \
  "$ROOT/LayoutCleaner.c" \
  -framework Foundation \
  -framework UIKit \
  -install_name '@rpath/LayoutCleaner.framework/LayoutCleaner' \
  -o "$FW/LayoutCleaner"

chmod 755 "$FW/LayoutCleaner"

cat > "$FW/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>LayoutCleaner</string>
  <key>CFBundleIdentifier</key><string>com.alsaray.LayoutCleaner</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>LayoutCleaner</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>MinimumOSVersion</key><string>15.0</string>
</dict>
</plist>
PLIST

echo "==> Ensuring LC_LOAD_DYLIB exists"
if otool -L "$EXEC" | grep -q '@rpath/LayoutCleaner.framework/LayoutCleaner'; then
  echo "✅ LayoutCleaner load command already exists"
else
  python3 "$ROOT/inject_dylib.py" \
    "$EXEC" '@rpath/LayoutCleaner.framework/LayoutCleaner'
fi

echo "==> Verification"
file "$FW/LayoutCleaner"
otool -L "$EXEC" | grep -E 'LayoutCleaner|ProfileOverlay|PortraitOverlay' || true

echo "==> Removing main app signature"
rm -rf "$APP/_CodeSignature"

echo "==> Packing IPA"
cd "$WORK"
rm -f "$ROOT/$OUTPUT_IPA"
zip -qry "$ROOT/$OUTPUT_IPA" Payload

echo
echo "✅ DONE: $ROOT/$OUTPUT_IPA"
echo "⚠️ Re-sign it before installing."
