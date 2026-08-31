#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==========================================="
echo "   Build latest fleXD + inject into Tarab"
echo "==========================================="

IPA="$(find "$ROOT" -maxdepth 2 -type f -name '*.ipa' \
  ! -name 'Tarab_fleXD_Editable.ipa' | head -1 || true)"

if [ -z "${IPA:-}" ]; then
  echo "❌ No IPA found in project."
  exit 1
fi

echo "✅ IPA: $IPA"

rm -rf "$ROOT/.build" "$ROOT/DerivedData" "$ROOT/work"
mkdir -p "$ROOT/work"

echo "➡️ Resolving latest TimOliver/fleXD..."
xcodebuild \
  -resolvePackageDependencies \
  -scheme FLEXDInject \
  -clonedSourcePackagesDirPath "$ROOT/SourcePackages"

echo "➡️ Building FLEXDInject for physical iPhone..."
xcodebuild \
  -scheme FLEXDInject \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$ROOT/DerivedData" \
  -clonedSourcePackagesDirPath "$ROOT/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS=arm64 \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  build

echo "➡️ Searching for dynamic product..."
PRODUCT="$(find "$ROOT/DerivedData/Build/Products" -type d \
  -name 'FLEXDInject.framework' | head -1 || true)"

if [ -z "${PRODUCT:-}" ]; then
  echo "❌ FLEXDInject.framework not found."
  echo "Available products:"
  find "$ROOT/DerivedData/Build/Products" -maxdepth 4 -type f | head -100
  exit 1
fi

echo "✅ Product: $PRODUCT"

BIN="$PRODUCT/FLEXDInject"
if [ ! -f "$BIN" ]; then
  echo "❌ Framework binary missing: $BIN"
  exit 1
fi

echo "➡️ Framework load info:"
file "$BIN" || true
otool -D "$BIN" || true
otool -L "$BIN" || true

cd "$ROOT/work"
unzip -q "$IPA"

APP="$(find Payload -maxdepth 1 -type d -name '*.app' | head -1)"
if [ -z "${APP:-}" ]; then
  echo "❌ .app not found."
  exit 1
fi

EXEC_NAME=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleExecutable' "$APP/Info.plist")
EXEC="$APP/$EXEC_NAME"

mkdir -p "$APP/Frameworks"
rm -rf "$APP/Frameworks/FLEXDInject.framework"
cp -R "$PRODUCT" "$APP/Frameworks/FLEXDInject.framework"

# Strip simulator slices if Xcode ever emits more than arm64.
xcrun lipo "$APP/Frameworks/FLEXDInject.framework/FLEXDInject" \
  -thin arm64 \
  -output "$APP/Frameworks/FLEXDInject.framework/FLEXDInject.arm64" 2>/dev/null || true

if [ -f "$APP/Frameworks/FLEXDInject.framework/FLEXDInject.arm64" ]; then
  mv "$APP/Frameworks/FLEXDInject.framework/FLEXDInject.arm64" \
     "$APP/Frameworks/FLEXDInject.framework/FLEXDInject"
  chmod 755 "$APP/Frameworks/FLEXDInject.framework/FLEXDInject"
fi

LOAD='@rpath/FLEXDInject.framework/FLEXDInject'

if ! otool -L "$EXEC" | grep -Fq "$LOAD"; then
  python3 "$ROOT/inject_dylib.py" "$EXEC" "$LOAD"
fi

# Remove stale signatures. The IPA is intentionally unsigned and must be
# signed by the user's normal signing tool.
rm -rf "$APP/_CodeSignature"
rm -rf "$APP/Frameworks/FLEXDInject.framework/_CodeSignature"

echo "➡️ Verifying final executable..."
otool -L "$EXEC" | grep -F 'FLEXDInject' || {
  echo "❌ FLEXDInject load command is missing."
  exit 1
}

cd "$ROOT/work"
rm -f "$ROOT/Tarab_fleXD_Editable.ipa"
zip -qry "$ROOT/Tarab_fleXD_Editable.ipa" Payload

echo ""
echo "✅ SUCCESS"
echo "Output: $ROOT/Tarab_fleXD_Editable.ipa"
echo ""
echo "Usage after signing/installing:"
echo "Hold THREE fingers on the app for ~0.5 sec to open fleXD."
