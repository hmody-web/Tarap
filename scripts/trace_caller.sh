#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"; OUT="$ROOT/caller_trace"
mkdir -p "$OUT"
[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

# Full symbolized disassembly only once.
xcrun otool -tvV "$BIN" > "$OUT/disasm.txt" 2>&1 || true
xcrun nm -nm "$BIN" > "$OUT/nm.txt" 2>&1 || true

# The only native SwiftUI Image(uiImage:) builder discovered starts at 0x102d132ac.
# Find all direct references/calls to it and neighboring closure/function entry points.
grep -n -B80 -A120 -Ei '102d132ac|102d13618|1038bc968' "$OUT/disasm.txt" \
 > "$OUT/exact_component_refs.txt" || true

# Find metadata/symbols nearest the component and Settings row/view.
grep -n -B30 -A80 -Ei 'SettingRow|SettingsViewController|SettingsViewModel|102d132ac|102d13' "$OUT/nm.txt" \
 > "$OUT/nearest_symbols.txt" || true

# Extract all lines that reference the component address, without head/SIGPIPE.
grep -nEi '102d132ac' "$OUT/disasm.txt" > "$OUT/direct_refs.txt" || true

{
 echo "=== DIRECT REFS TO 0x102d132ac ==="
 cat "$OUT/direct_refs.txt" || true
 echo
 echo "=== NEAREST SYMBOLS ==="
 sed -n '1,1200p' "$OUT/nearest_symbols.txt"
 echo
 echo "=== EXACT COMPONENT CONTEXT ==="
 sed -n '1,2200p' "$OUT/exact_component_refs.txt"
} > "$OUT/summary.txt"

rm -f "$OUT/disasm.txt" "$OUT/nm.txt"
sed -n '1,1000p' "$OUT/summary.txt"
