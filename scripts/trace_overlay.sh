#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"; OUT="$ROOT/settings_overlay_trace"
mkdir -p "$OUT"
[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

xcrun nm -nm "$BIN" > "$OUT/nm.txt" 2>&1 || true
xcrun otool -ov "$BIN" > "$OUT/objc.txt" 2>&1 || true
xcrun otool -tvV "$BIN" > "$OUT/disasm.txt" 2>&1 || true

grep -niEi 'SettingsViewController|viewDidLoad|viewDidAppear|viewWillAppear|addSubview|UIImageView|UIHostingController|UIHostingView' \
 "$OUT/nm.txt" > "$OUT/symbols.txt" || true
grep -niEi 'SettingsViewController|viewDidLoad|viewDidAppear|viewWillAppear' \
 "$OUT/objc.txt" > "$OUT/objc_settings.txt" || true

# Context around known Settings VC address family from prior trace.
python3 - <<'PY'
from pathlib import Path
import re
ls=Path("settings_overlay_trace/disasm.txt").read_text(errors="ignore").splitlines()
def a(l):
 m=re.match(r'\s*([0-9a-fA-F]{8,16})\s',l)
 return int(m.group(1),16) if m else None
out=[]
for l in ls:
 x=a(l)
 if x is not None and 0x102d1e000 <= x <= 0x102d21000: out.append(l)
Path("settings_overlay_trace/settings_vc_disasm.txt").write_text("\n".join(out))
PY

{
 echo "=== SYMBOLS ==="; sed -n '1,1000p' "$OUT/symbols.txt"
 echo; echo "=== OBJC SETTINGS ==="; sed -n '1,1200p' "$OUT/objc_settings.txt"
 echo; echo "=== SETTINGS VC DISASM ==="; sed -n '1,5000p' "$OUT/settings_vc_disasm.txt"
} > "$OUT/summary.txt"

rm -f "$OUT/nm.txt" "$OUT/objc.txt" "$OUT/disasm.txt"
sed -n '1,1600p' "$OUT/summary.txt"
