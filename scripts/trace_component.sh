#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"; OUT="$ROOT/component_trace"
mkdir -p "$OUT"
[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

xcrun otool -tvV "$BIN" > "$OUT/disasm.txt" 2>&1 || true
xcrun nm -nm "$BIN" > "$OUT/nm.txt" 2>&1 || true

# Known SwiftUI Image(uiImage:) stub from previous trace.
grep -n -B120 -A220 -E '1038bc968|Image.*uiImage|UIImage' "$OUT/disasm.txt" \
  > "$OUT/image_uiimage_contexts.txt" || true

# Settings/rows/profile/avatar candidates.
grep -niEi 'SettingRow|SettingsView|avatar|profile|user.*image|image.*user|thumbnail|AsyncImage|ImageView|cell|row' \
 "$OUT/nm.txt" > "$OUT/component_symbols.txt" || true

# Extract contexts around every direct BL to the Image(uiImage:) stub address.
python3 - <<'PY'
from pathlib import Path
import re
p=Path("component_trace/disasm.txt")
ls=p.read_text(errors="ignore").splitlines()
idx=[]
for i,l in enumerate(ls):
    if re.search(r'\bbl\s+0x?1038bc968\b',l,re.I):
        idx.append(i)
o=[]
for n,i in enumerate(idx):
    o.append(f"===== Image(uiImage:) CALL #{n+1} line {i+1} =====")
    o.extend(ls[max(0,i-100):min(len(ls),i+180)])
Path("component_trace/direct_uiimage_call_windows.txt").write_text("\n".join(o))
print("direct calls:",len(idx))
PY

{
 echo "=== COMPONENT SYMBOLS ==="
 sed -n '1,500p' "$OUT/component_symbols.txt"
 echo
 echo "=== DIRECT Image(uiImage:) WINDOWS ==="
 sed -n '1,2500p' "$OUT/direct_uiimage_call_windows.txt"
} > "$OUT/summary.txt"

rm -f "$OUT/disasm.txt" "$OUT/nm.txt"
sed -n '1,1200p' "$OUT/summary.txt"
