#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"
OUT="$ROOT/native_uiimageview_trace"
mkdir -p "$OUT"
[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

xcrun nm -nm "$BIN" > "$OUT/nm.txt" 2>&1 || true
xcrun otool -ov "$BIN" > "$OUT/objc.txt" 2>&1 || true
xcrun otool -tvV "$BIN" > "$OUT/disasm.txt" 2>&1 || true

# Locate UIKit image-view related imports/classes/selectors and addSubview paths.
grep -niEi 'UIImageView|addSubview|initWithImage|setImage:|imageNamed:|setFrame:|setBounds:|setCenter:|cornerRadius|clipsToBounds|contentMode' \
 "$OUT/nm.txt" > "$OUT/uiimageview_symbols.txt" || true

grep -niEi 'UIImageView|addSubview:|initWithImage:|setImage:|imageNamed:|setFrame:|cornerRadius|clipsToBounds|contentMode' \
 "$OUT/objc.txt" > "$OUT/uiimageview_objc.txt" || true

# Extract contexts around ObjC message sends whose surrounding instructions mention
# UIImageView/imageNamed/addSubview selectors. This gives us native ABI sequences to copy.
python3 - <<'PY'
from pathlib import Path
import re
ls=Path("native_uiimageview_trace/disasm.txt").read_text(errors="ignore").splitlines()

needles=("UIImageView","addSubview","initWithImage","setImage","imageNamed",
         "setFrame","cornerRadius","clipsToBounds","contentMode")
hits=[]
for i,l in enumerate(ls):
    if any(n.lower() in l.lower() for n in needles):
        hits.append((i,l))

# Deduplicate nearby hits into windows.
windows=[]
for i,_ in hits:
    if not windows or i > windows[-1][1] + 80:
        windows.append([max(0,i-80), min(len(ls)-1,i+140)])
    else:
        windows[-1][1]=min(len(ls)-1,max(windows[-1][1],i+140))

out=[]
for n,(a,b) in enumerate(windows[:80],1):
    out.append(f"===== WINDOW {n} lines {a+1}-{b+1} =====")
    out.extend(ls[a:b+1])
Path("native_uiimageview_trace/native_windows.txt").write_text("\n".join(out))

# Also capture Settings VC builder where hosting view is added, for integration point.
def addr(line):
    m=re.match(r'\s*([0-9a-fA-F]{8,16})\s',line)
    return int(m.group(1),16) if m else None
sv=[]
for l in ls:
    a=addr(l)
    if a is not None and 0x102d1e650 <= a <= 0x102d1ea80:
        sv.append(l)
Path("native_uiimageview_trace/settings_integration.txt").write_text("\n".join(sv))
PY

{
 echo "=== UIIMAGEVIEW SYMBOLS ==="
 sed -n '1,1200p' "$OUT/uiimageview_symbols.txt"
 echo
 echo "=== UIIMAGEVIEW OBJC ==="
 sed -n '1,1500p' "$OUT/uiimageview_objc.txt"
 echo
 echo "=== NATIVE WINDOWS ==="
 sed -n '1,5000p' "$OUT/native_windows.txt"
 echo
 echo "=== SETTINGS INTEGRATION POINT ==="
 cat "$OUT/settings_integration.txt"
} > "$OUT/summary.txt"

rm -f "$OUT/nm.txt" "$OUT/objc.txt" "$OUT/disasm.txt"
sed -n '1,1800p' "$OUT/summary.txt"
