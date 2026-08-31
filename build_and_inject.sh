#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

IPA="$ROOT/Tarab_Input.ipa"
OUTPUT="$ROOT/Tarab_RemoteBanner_Injected.ipa"

echo "=== Tarab Remote Banner Builder ==="
echo "Input: $IPA"

rm -rf "$ROOT/DerivedData" "$ROOT/work"
mkdir -p "$ROOT/work"

echo "➡️ Build TarabRemoteBanner.framework"
xcodebuild \
  -scheme TarabRemoteBanner \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$ROOT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  build

PRODUCT="$(find "$ROOT/DerivedData/Build/Products" -type d -name 'TarabRemoteBanner.framework' | head -1 || true)"
if [ -z "${PRODUCT:-}" ]; then
  echo "❌ TarabRemoteBanner.framework not found"
  exit 1
fi

echo "✅ Framework: $PRODUCT"

cd "$ROOT/work"
unzip -q "$IPA"

APP="$(find Payload -maxdepth 1 -type d -name '*.app' | head -1)"
if [ -z "${APP:-}" ]; then
  echo "❌ .app not found"
  exit 1
fi

EXEC_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")
EXEC="$APP/$EXEC_NAME"

echo "✅ App: $APP"
echo "✅ Executable: $EXEC_NAME"

mkdir -p "$APP/Frameworks"
rm -rf "$APP/Frameworks/TarabRemoteBanner.framework"
cp -R "$PRODUCT" "$APP/Frameworks/TarabRemoteBanner.framework"

FRAMEBIN="$APP/Frameworks/TarabRemoteBanner.framework/TarabRemoteBanner"
chmod 755 "$FRAMEBIN"

# Make the dynamic library self-contained under @rpath.
install_name_tool -id '@rpath/TarabRemoteBanner.framework/TarabRemoteBanner' "$FRAMEBIN" || true

LOAD='@rpath/TarabRemoteBanner.framework/TarabRemoteBanner'
if ! otool -L "$EXEC" | grep -Fq "$LOAD"; then
  python3 "$ROOT/inject_dylib.py" "$EXEC" "$LOAD"
fi

# Preserve every existing framework/tweak from the input IPA.
echo "➡️ Existing custom frameworks retained:"
ls -1 "$APP/Frameworks" | grep -E 'FLEXDInject|ProfileOverlay|PortraitOverlay|TarabRemoteBanner' || true

# Remove stale signatures only; user signs final IPA with their normal signer.
rm -rf "$APP/_CodeSignature"
rm -rf "$APP/Frameworks/TarabRemoteBanner.framework/_CodeSignature"

echo "➡️ Verify injection"
otool -L "$EXEC" | grep -F 'TarabRemoteBanner.framework/TarabRemoteBanner'

cd "$ROOT/work"
rm -f "$OUTPUT"
zip -qry "$OUTPUT" Payload

echo ""
echo "✅ SUCCESS"
echo "Output: $OUTPUT"
