#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

OUTPUT_IPA="${2:-Tarab_5.11_LayoutCleaner.ipa}"

if [ "${1:-}" != "" ] && [ -f "${1:-}" ]; then
    INPUT_IPA="$1"
else
    echo "==> Searching for IPA automatically"

    INPUT_IPA="$(find "$ROOT" \
      -maxdepth 3 \
      -type f \
      -name '*.ipa' \
      ! -name "$OUTPUT_IPA" \
      | head -1 || true)"
fi

if [ -z "${INPUT_IPA:-}" ] || [ ! -f "$INPUT_IPA" ]; then
    echo
    echo "❌ No IPA file found."
    echo
    echo "Put your IPA anywhere inside this repository."
    echo
    echo "Files currently found:"
    find "$ROOT" -maxdepth 3 -type f | sort
    exit 1
fi

echo "✅ Found IPA:"
echo "$INPUT_IPA"

WORK="$ROOT/work_layoutcleaner"

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

echo
echo "==> Unpacking IPA"
unzip -q "$INPUT_IPA"

APP="$(find Payload -maxdepth 1 -type d -name '*.app' | head -1)"

if [ -z "$APP" ]; then
    echo "❌ No .app found inside IPA"
    exit 1
fi

EXEC_NAME=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleExecutable' \
  "$APP/Info.plist")

EXEC="$APP/$EXEC_NAME"

if [ ! -f "$EXEC" ]; then
    echo "❌ Main executable not found: $EXEC"
    exit 1
fi

echo "✅ App:"
echo "$APP"

echo "✅ Executable:"
echo "$EXEC_NAME"

echo
echo "==> Building LayoutCleaner.framework"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

FRAMEWORK_DIR="$APP/Frameworks/LayoutCleaner.framework"

mkdir -p "$FRAMEWORK_DIR"

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
  -o "$FRAMEWORK_DIR/LayoutCleaner"

chmod 755 "$FRAMEWORK_DIR/LayoutCleaner"

cat > "$FRAMEWORK_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>

    <key>CFBundleExecutable</key>
    <string>LayoutCleaner</string>

    <key>CFBundleIdentifier</key>
    <string>com.alsaray.LayoutCleaner</string>

    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <key>CFBundleName</key>
    <string>LayoutCleaner</string>

    <key>CFBundlePackageType</key>
    <string>FMWK</string>

    <key>CFBundleShortVersionString</key>
    <string>1.0</string>

    <key>CFBundleVersion</key>
    <string>1</string>

    <key>MinimumOSVersion</key>
    <string>15.0</string>
</dict>
</plist>
PLIST

echo
echo "==> Injecting LayoutCleaner.framework"

python3 "$ROOT/inject_dylib.py" \
  "$EXEC" \
  '@rpath/LayoutCleaner.framework/LayoutCleaner'

echo
echo "==> Checking framework"

file "$FRAMEWORK_DIR/LayoutCleaner" || true
otool -L "$EXEC" | grep -i LayoutCleaner || true

echo
echo "==> Removing old main app signature"

rm -rf "$APP/_CodeSignature"

echo
echo "==> Packing output IPA"

cd "$WORK"

rm -f "$ROOT/$OUTPUT_IPA"

zip -qry "$ROOT/$OUTPUT_IPA" Payload

cd "$ROOT"

echo
echo "====================================="
echo "✅ DONE"
echo "Output:"
echo "$ROOT/$OUTPUT_IPA"
echo
echo "⚠️ Re-sign the IPA before installing."
echo "====================================="
