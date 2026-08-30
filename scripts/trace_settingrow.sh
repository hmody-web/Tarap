#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"; OUT="$ROOT/settingrow_results"
mkdir -p "$OUT"
[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

# Objective-C metadata + symbols for Settings/rows.
xcrun otool -ov "$BIN" > "$OUT/objc.txt" 2>&1 || true
grep -n -B100 -A180 -Ei 'SettingsViewController|SettingsViewModel|SettingRow|SettingSection' \
 "$OUT/objc.txt" > "$OUT/settings_objc_context.txt" || true

xcrun nm -nm "$BIN" > "$OUT/nm.txt" 2>&1 || true
grep -niEi 'SettingsViewController|SettingsViewModel|SettingRow|SettingSection|restore|purchase|subscribe|remove.?ads' \
 "$OUT/nm.txt" > "$OUT/settings_symbols.txt" || true

# Find likely localization keys for both adjacent rows from binary strings.
strings -a -t x "$BIN" > "$OUT/strings.tmp"
grep -niEi 'subscribe and removeAds|restore.{0,20}purchase|purchase.{0,20}restore|removeAds' \
 "$OUT/strings.tmp" > "$OUT/row_key_candidates.txt" || true

# Apple disassembler. Keep only windows around Settings/row symbols and key references.
xcrun otool -tvV "$BIN" > "$OUT/disasm.tmp" 2>&1 || true
grep -n -B100 -A180 -Ei 'SettingsViewController|SettingsViewModel|SettingRow|SettingSection|restore.*purchase|subscribe.*removeAds' \
 "$OUT/disasm.tmp" > "$OUT/settings_disassembly_context.txt" || true

# Extract metadata chunks that mention likely row/image fields.
grep -n -B50 -A80 -Ei 'image|icon|title|action|selector|SettingRow' \
 "$OUT/settings_objc_context.txt" > "$OUT/settingrow_fields_context.txt" || true

{
 echo "=== ROW KEY CANDIDATES ==="
 cat "$OUT/row_key_candidates.txt" | head -100
 echo
 echo "=== SETTINGS SYMBOLS ==="
 cat "$OUT/settings_symbols.txt" | head -250
 echo
 echo "=== SETTING ROW FIELDS ==="
 cat "$OUT/settingrow_fields_context.txt" | head -350
} > "$OUT/summary.txt"

rm -f "$OUT/objc.txt" "$OUT/nm.txt" "$OUT/disasm.tmp" "$OUT/strings.tmp"
cat "$OUT/summary.txt"
