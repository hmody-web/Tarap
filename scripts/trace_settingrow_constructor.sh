#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"
OUT="$ROOT/settingrow_constructor"
mkdir -p "$OUT"
[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

xcrun otool -tvV "$BIN" > "$OUT/disasm.txt" 2>&1 || true
xcrun nm -nm "$BIN" > "$OUT/nm.txt" 2>&1 || true

# Exact subscription row creation region: crown.fill at 0x102d4d3d8,
# next row begins around 0x102d4d448.
python3 - <<'PY'
from pathlib import Path
import re
ls=Path("settingrow_constructor/disasm.txt").read_text(errors="ignore").splitlines()

def addr(line):
    m=re.match(r'\s*([0-9a-fA-F]{8,16})\s',line)
    return int(m.group(1),16) if m else None

ranges=[
 ("subscription_constructor",0x102d4d250,0x102d4d520),
 ("settingrow_renderer_A",0x102d17680,0x102d17920),
 ("settingrow_renderer_B",0x102d18720,0x102d18a20),
]
for name,lo,hi in ranges:
    out=[]
    for l in ls:
        a=addr(l)
        if a is not None and lo<=a<=hi: out.append(l)
    Path(f"settingrow_constructor/{name}.txt").write_text("\n".join(out))

# Collect branch/call targets in subscription constructor, then dump broad contexts
# around those targets to identify the SettingRow initializer/storage function.
region=[]
for l in ls:
    a=addr(l)
    if a is not None and 0x102d4d250<=a<=0x102d4d520: region.append(l)
targets=[]
for l in region:
    m=re.search(r'\bbl\s+(0x)?([0-9a-fA-F]+)',l)
    if m:
        t=int(m.group(2),16)
        if 0x102000000 <= t <= 0x103900000:
            targets.append(t)
targets=sorted(set(targets))
Path("settingrow_constructor/call_targets.txt").write_text("\n".join(hex(x) for x in targets))

ctx=[]
for t in targets:
    ctx.append(f"===== TARGET {t:#x} =====")
    for l in ls:
        a=addr(l)
        if a is not None and t-0x100<=a<=t+0x240: ctx.append(l)
Path("settingrow_constructor/call_target_contexts.txt").write_text("\n".join(ctx))
PY

grep -niEi 'SettingRow|SettingSection|SettingsViewController|SettingsViewModel|presentSubscription|subscribe' \
 "$OUT/nm.txt" > "$OUT/setting_symbols.txt" || true

{
 echo "=== SUBSCRIPTION CONSTRUCTOR ==="
 cat "$OUT/subscription_constructor.txt"
 echo
 echo "=== CALL TARGETS ==="
 cat "$OUT/call_targets.txt"
 echo
 echo "=== SETTING SYMBOLS ==="
 sed -n '1,800p' "$OUT/setting_symbols.txt"
 echo
 echo "=== TARGET CONTEXTS ==="
 sed -n '1,3500p' "$OUT/call_target_contexts.txt"
 echo
 echo "=== RENDERER A ==="
 cat "$OUT/settingrow_renderer_A.txt"
 echo
 echo "=== RENDERER B ==="
 cat "$OUT/settingrow_renderer_B.txt"
} > "$OUT/summary.txt"

rm -f "$OUT/disasm.txt" "$OUT/nm.txt"
sed -n '1,1400p' "$OUT/summary.txt"
