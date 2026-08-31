#!/bin/bash
set -euo pipefail

INPUT_IPA="${1:-Tarab_5.11_ProfileOverlay_Merged.ipa}"
OUTPUT_IPA="${2:-Tarab_5.11_LayoutCleaner.ipa}"

ROOT="$(pwd)"
WORK="$ROOT/work_layoutcleaner"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

echo "==> Unpacking IPA"
unzip -q "$ROOT/$INPUT_IPA"

APP="$(find Payload -maxdepth 1 -type d -name '*.app' | head -1)"
if [ -z "$APP" ]; then
  echo "No .app found"
  exit 1
fi

EXEC_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")
EXEC="$APP/$EXEC_NAME"

echo "==> Building LayoutCleaner.framework"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$APP/Frameworks/LayoutCleaner.framework"

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
  -o "$APP/Frameworks/LayoutCleaner.framework/LayoutCleaner"

chmod 755 "$APP/Frameworks/LayoutCleaner.framework/LayoutCleaner"

cat > "$APP/Frameworks/LayoutCleaner.framework/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>LayoutCleaner</string>
  <key>CFBundleIdentifier</key><string>com.alsaray.LayoutCleaner</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>LayoutCleaner</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>15.0</string>
</dict>
</plist>
PLIST

echo "==> Injecting LC_LOAD_DYLIB"
python3 "$ROOT/inject_dylib.py" "$EXEC" '@rpath/LayoutCleaner.framework/LayoutCleaner'

echo "==> Removing old signatures (IPA must be re-signed)"
rm -rf "$APP/_CodeSignature"
find "$APP/Frameworks/LayoutCleaner.framework" -name '_CodeSignature' -type d -prune -exec rm -rf {} + 2>/dev/null || true

echo "==> Packing IPA"
cd "$WORK"
zip -qry "$ROOT/$OUTPUT_IPA" Payload

echo
echo "DONE: $ROOT/$OUTPUT_IPA"
echo "Re-sign this IPA before installing."
