#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"
OUT="$ROOT/settings_selector_trace"
mkdir -p "$OUT"
[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

# Objective-C metadata is the key output here: selector <-> IMP mapping.
xcrun otool -ov "$BIN" > "$OUT/objc_verbose.txt" 2>&1 || true
xcrun nm -nm "$BIN" > "$OUT/nm.txt" 2>&1 || true
xcrun otool -tvV "$BIN" > "$OUT/disasm.txt" 2>&1 || true

# Pull the complete SettingsViewController metadata block with plenty of context.
grep -n -B80 -A500 -E '_TtC5Tarab22SettingsViewController|SettingsViewController' \
 "$OUT/objc_verbose.txt" > "$OUT/settings_objc_block.txt" || true

# Explicit lifecycle selectors and nearby IMP addresses.
grep -n -B25 -A45 -Ei 'viewDidLoad|viewDidAppear:|viewWillAppear:|viewWillDisappear:|viewDidDisappear:|loadView' \
 "$OUT/settings_objc_block.txt" > "$OUT/lifecycle_mapping.txt" || true

# Symbols near the already-known Settings VC implementation region.
grep -n -B20 -A100 -Ei 'SettingsViewController|viewDidLoad|viewDidAppear|viewWillAppear|loadView' \
 "$OUT/nm.txt" > "$OUT/settings_symbols.txt" || true

# Exact disassembly window around Settings VC family for validating the mapped IMP.
python3 - <<'PY'
from pathlib import Path
import re
ls=Path("settings_selector_trace/disasm.txt").read_text(errors="ignore").splitlines()
def addr(line):
    m=re.match(r'\s*([0-9a-fA-F]{8,16})\s',line)
    return int(m.group(1),16) if m else None
out=[]
for line in ls:
    a=addr(line)
    if a is not None and 0x102d1e000 <= a <= 0x102d21500:
        out.append(line)
Path("settings_selector_trace/settings_disasm.txt").write_text("\n".join(out))
PY

{
 echo "=== LIFECYCLE MAPPING ==="
 cat "$OUT/lifecycle_mapping.txt" || true
 echo
 echo "=== SETTINGS OBJC BLOCK ==="
 sed -n '1,1800p' "$OUT/settings_objc_block.txt"
 echo
 echo "=== SETTINGS SYMBOLS ==="
 sed -n '1,1000p' "$OUT/settings_symbols.txt"
 echo
 echo "=== SETTINGS DISASSEMBLY ==="
 sed -n '1,4500p' "$OUT/settings_disasm.txt"
} > "$OUT/summary.txt"

rm -f "$OUT/objc_verbose.txt" "$OUT/nm.txt" "$OUT/disasm.txt"
sed -n '1,1800p' "$OUT/summary.txt"
