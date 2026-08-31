#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

OUT_IPA="Tarab_DeepFix_V6_1.ipa"
OUT_ZIP="Tarab_DeepFix_V6_1.zip"
REPORT_DIR="$ROOT/V6_Report"

echo "==> Searching for ANY IPA"
INPUT="$(find "$ROOT" -maxdepth 5 -type f -name '*.ipa' \
 ! -name "$OUT_IPA" | head -1 || true)"

if [ -z "${INPUT:-}" ]; then
  echo "❌ No IPA found"
  find "$ROOT" -maxdepth 5 -type f | sort
  exit 1
fi

echo "✅ Input: $INPUT"

WORK="$ROOT/work_v6"
rm -rf "$WORK" "$REPORT_DIR"
mkdir -p "$WORK" "$REPORT_DIR"
cd "$WORK"
unzip -q "$INPUT"

APP="$(find Payload -maxdepth 1 -type d -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "❌ No .app found"; exit 1; }

EXEC_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")
EXEC="$APP/$EXEC_NAME"
FW="$APP/Frameworks/LayoutCleaner.framework"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

echo "==> Static diagnostics"
{
  echo "INPUT=$INPUT"
  echo "APP=$APP"
  echo "EXEC=$EXEC_NAME"
  echo
  echo "===== Info.plist ====="
  plutil -p "$APP/Info.plist" || true
} > "$REPORT_DIR/app_info.txt"

{
  echo "===== Loaded dylibs ====="
  otool -L "$EXEC" || true
  echo
  echo "===== Mach-O headers ====="
  otool -hv "$EXEC" || true
} > "$REPORT_DIR/macho.txt"

{
  echo "===== Relevant binary strings ====="
  strings -a "$EXEC" | grep -Ei \
   'AdsManager|BannerHeightManager|adHeight|bannerHeight|inlineBannerHeight|bannerBottom|BottomConstraint|safeArea|additionalSafeArea|tabBar|UITabBar|SettingsViewController|SupportViewController|webViewBottomConstraint|backgroundExtension|scrollEdge' \
   || true
} > "$REPORT_DIR/relevant_strings.txt"

{
  echo "===== Frameworks ====="
  find "$APP/Frameworks" -maxdepth 2 -type f -print 2>/dev/null | sort || true
} > "$REPORT_DIR/frameworks.txt"

echo "==> Building DeepFix V6"
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
<key>CFBundleInfoDictionaryVersion</key><string>6.1</string>
<key>CFBundleName</key><string>LayoutCleaner</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>6.1</string>
<key>CFBundleVersion</key><string>61</string>
<key>MinimumOSVersion</key><string>15.0</string>
</dict></plist>
EOF

if otool -L "$EXEC" | grep -q '@rpath/LayoutCleaner.framework/LayoutCleaner'; then
  echo "✅ Existing LayoutCleaner load command retained"
else
  python3 "$ROOT/inject_dylib.py" \
   "$EXEC" '@rpath/LayoutCleaner.framework/LayoutCleaner'
fi

{
  echo "===== Post-build dylibs ====="
  otool -L "$EXEC" || true
  echo
  echo "===== LayoutCleaner ====="
  file "$FW/LayoutCleaner" || true
  otool -L "$FW/LayoutCleaner" || true
} > "$REPORT_DIR/post_build.txt"

rm -rf "$APP/_CodeSignature"

echo "==> Packing modified IPA"
cd "$WORK"
rm -f "$ROOT/$OUT_IPA"
zip -qry "$ROOT/$OUT_IPA" Payload

echo "==> Packing final ZIP artifact"
cd "$ROOT"
rm -f "$OUT_ZIP"
zip -q "$OUT_ZIP" "$OUT_IPA"
zip -qr "$OUT_ZIP" "V6_Report"
zip -q "$OUT_ZIP" "README_AR.txt"

echo "✅ ZIP artifact: $ROOT/$OUT_ZIP"
echo "Contains:"
unzip -l "$ROOT/$OUT_ZIP"
