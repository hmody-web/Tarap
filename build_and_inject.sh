#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

IPA="$ROOT/Tarab_Input.ipa"
OUTPUT="$ROOT/Tarab_HideOriginalBanner_FORCE.ipa"

rm -rf "$ROOT/DerivedData" "$ROOT/work"
mkdir -p "$ROOT/work"

echo "=== Build TarabBannerHider.framework ==="

xcodebuild \
  -scheme TarabBannerHider \
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

PRODUCT="$(find "$ROOT/DerivedData/Build/Products" -type d -name 'TarabBannerHider.framework' | head -1 || true)"

if [ -z "${PRODUCT:-}" ]; then
  echo "❌ TarabBannerHider.framework not found"
  find "$ROOT/DerivedData/Build/Products" -maxdepth 5 -print
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
rm -rf "$APP/Frameworks/TarabBannerHider.framework"
cp -R "$PRODUCT" "$APP/Frameworks/TarabBannerHider.framework"

FRAMEBIN="$APP/Frameworks/TarabBannerHider.framework/TarabBannerHider"
chmod 755 "$FRAMEBIN"

install_name_tool \
  -id '@rpath/TarabBannerHider.framework/TarabBannerHider' \
  "$FRAMEBIN" || true

LOAD='@rpath/TarabBannerHider.framework/TarabBannerHider'

if ! otool -L "$EXEC" | grep -Fq "$LOAD"; then
  python3 "$ROOT/inject_dylib.py" "$EXEC" "$LOAD"
fi

echo "=== Verify injection ==="
otool -L "$EXEC" | grep -F 'TarabBannerHider.framework/TarabBannerHider'

# Preserve every other tweak/framework already present in the input IPA.
rm -rf "$APP/_CodeSignature"
rm -rf "$APP/Frameworks/TarabBannerHider.framework/_CodeSignature"

cd "$ROOT/work"
rm -f "$OUTPUT"
zip -qry "$OUTPUT" Payload

echo ""
echo "✅ SUCCESS"
echo "Output: $OUTPUT"
