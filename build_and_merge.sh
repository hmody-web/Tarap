#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

OUT="Tarab_5.11_LayoutCleaner_ANY_IPA.ipa"

echo "==> Searching for ANY IPA file in repository"

INPUT="$(find "$ROOT" -maxdepth 5 -type f -name '*.ipa' \
  ! -name "$OUT" \
  | head -1 || true)"

if [ -z "${INPUT:-}" ] || [ ! -f "$INPUT" ]; then
  echo
  echo "❌ No IPA file found anywhere in repository."
  echo
  echo "Current files:"
  find "$ROOT" -maxdepth 5 -type f | sort
  exit 1
fi

echo "✅ Input IPA:"
echo "$INPUT"

WORK="$ROOT/work_any_ipa"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

echo
echo "==> Unpacking IPA"
unzip -q "$INPUT"

APP="$(find Payload -maxdepth 1 -type d -name '*.app' | head -1)"

if [ -z "$APP" ]; then
  echo "❌ No .app found inside IPA"
  exit 1
fi

EXEC_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")
EXEC="$APP/$EXEC_NAME"

if [ ! -f "$EXEC" ]; then
  echo "❌ Main executable not found: $EXEC"
  exit 1
fi

echo "✅ App: $APP"
echo "✅ Executable: $EXEC_NAME"

FW="$APP/Frameworks/LayoutCleaner.framework"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

echo
echo "==> Replacing/creating LayoutCleaner.framework"
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
<plist version="1.0">
<dict>
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
  <string>3.2</string>
  <key>CFBundleVersion</key>
  <string>32</string>
  <key>MinimumOSVersion</key>
  <string>15.0</string>
</dict>
</plist>
EOF

echo
echo "==> Checking LC_LOAD_DYLIB"

if otool -L "$EXEC" | grep -q '@rpath/LayoutCleaner.framework/LayoutCleaner'; then
  echo "✅ LayoutCleaner already injected - Mach-O will NOT be modified"
else
  echo "==> Injecting LayoutCleaner load command"
  python3 "$ROOT/inject_dylib.py" \
    "$EXEC" \
    '@rpath/LayoutCleaner.framework/LayoutCleaner'
fi

echo
echo "==> Verification"
file "$FW/LayoutCleaner"
otool -L "$EXEC" | grep -E 'LayoutCleaner|ProfileOverlay|PortraitOverlay' || true

echo
echo "==> Removing main app signature"
rm -rf "$APP/_CodeSignature"

echo
echo "==> Packing output IPA"

cd "$WORK"
rm -f "$ROOT/$OUT"
zip -qry "$ROOT/$OUT" Payload

echo
echo "======================================"
echo "✅ DONE"
echo "Output:"
echo "$ROOT/$OUT"
echo
echo "⚠️ Re-sign this IPA before installing."
echo "======================================"
