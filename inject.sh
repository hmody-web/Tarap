#!/usr/bin/env bash
set -euo pipefail
IPA="${1:?Input IPA path required}"
OUT="${2:-$PWD/Tarab_Banner_Forced.ipa}"
ROOT="$PWD/work"
rm -rf "$ROOT" && mkdir -p "$ROOT"
unzip -q "$IPA" -d "$ROOT"
APP=$(find "$ROOT/Payload" -maxdepth 1 -type d -name '*.app' | head -1)
BIN=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")
DYLIB="${DYLIB_PATH:-$PWD/TarabBannerForce/.theos/obj/debug/TarabBannerForce.dylib}"
[ -f "$DYLIB" ] || DYLIB="$PWD/TarabBannerForce/.theos/obj/TarabBannerForce.dylib"
[ -f "$DYLIB" ] || { echo "dylib not found"; exit 1; }
cp "$DYLIB" "$APP/TarabBannerForce.dylib"
# Prefer insert_dylib. Remove old signature because CodeMagic should re-sign final IPA.
chmod +x tools/insert_dylib
./tools/insert_dylib --strip-codesig --inplace @executable_path/TarabBannerForce.dylib "$APP/$BIN"
find "$APP" -name '_CodeSignature' -type d -prune -exec rm -rf {} + || true
rm -f "$APP/embedded.mobileprovision"
OUT_ABS="$OUT"
[[ "$OUT_ABS" = /* ]] || OUT_ABS="$PWD/$OUT_ABS"
rm -f "$OUT_ABS"
(cd "$ROOT" && zip -qry "$OUT_ABS" Payload)
echo "Created: $OUT"
