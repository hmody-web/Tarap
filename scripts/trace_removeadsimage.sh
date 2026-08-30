#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"; OUT="$ROOT/removeadsimage_results"
mkdir -p "$OUT"
[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

# Objective-C metadata gives us the exact class/method around removeAdsImage.
xcrun otool -ov "$BIN" > "$OUT/objc_metadata.txt" 2>&1 || true
grep -n -B80 -A120 -E 'removeAdsImage|setRemoveAdsImage:' "$OUT/objc_metadata.txt" \
 > "$OUT/removeAdsImage_objc_context.txt" || true

xcrun nm -nm "$BIN" > "$OUT/nm.txt" 2>&1 || true
grep -ni -E 'removeAdsImage|SettingsView|SettingRow|SettingSection' "$OUT/nm.txt" \
 > "$OUT/relevant_symbols.txt" || true

# Full disassembly only temporary. Locate exact getter/setter/ivar references and
# keep small windows, so artifact stays small.
xcrun otool -tvV "$BIN" > "$OUT/disasm.tmp" 2>&1 || true
grep -n -B60 -A100 -E 'removeAdsImage|setRemoveAdsImage|_removeAdsImage' "$OUT/disasm.tmp" \
 > "$OUT/removeAdsImage_disassembly_context.txt" || true

# Also inspect selector/ivar metadata strings and nearby raw strings.
strings -a -t x "$BIN" | grep -i -B30 -A30 'removeAdsImage' \
 > "$OUT/removeAdsImage_strings_context.txt" || true

{
 echo "=== OBJC CONTEXT ==="
 cat "$OUT/removeAdsImage_objc_context.txt" | head -300
 echo
 echo "=== SYMBOLS ==="
 cat "$OUT/relevant_symbols.txt" | head -200
 echo
 echo "=== DISASSEMBLY ==="
 cat "$OUT/removeAdsImage_disassembly_context.txt" | head -400
} > "$OUT/summary.txt"

rm -f "$OUT/disasm.tmp" "$OUT/objc_metadata.txt" "$OUT/nm.txt"
cat "$OUT/summary.txt"
