#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"
OUT="$ROOT/settings_overlay_geometry"
mkdir -p "$OUT"
[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

xcrun otool -tvV "$BIN" > "$OUT/disasm.txt" 2>&1 || true
xcrun nm -nm "$BIN" > "$OUT/nm.txt" 2>&1 || true
xcrun otool -ov "$BIN" > "$OUT/objc.txt" 2>&1 || true

# Settings VC lifecycle/build region + methods that manipulate view hierarchy/layout.
python3 - <<'PY'
from pathlib import Path
import re
ls=Path("settings_overlay_geometry/disasm.txt").read_text(errors="ignore").splitlines()
def addr(line):
    m=re.match(r'\s*([0-9a-fA-F]{8,16})\s', line)
    return int(m.group(1),16) if m else None

ranges=[
 ("settings_lifecycle",0x102d1e430,0x102d1ea80),
 ("settings_builder",0x102d1e650,0x102d1f300),
 ("settingrow_renderers",0x102d17600,0x102d18b00),
]
for name,lo,hi in ranges:
    out=[]
    for l in ls:
        a=addr(l)
        if a is not None and lo<=a<=hi:
            out.append(l)
    Path(f"settings_overlay_geometry/{name}.txt").write_text("\n".join(out))
PY

grep -niEi 'addSubview|insertSubview|bringSubviewToFront|setFrame:|frame|bounds|layoutSubviews|viewDidLayoutSubviews|safeArea|leadingAnchor|trailingAnchor|topAnchor|centerYAnchor|widthAnchor|heightAnchor|UIImageView|cornerRadius|clipsToBounds' \
 "$OUT/nm.txt" > "$OUT/layout_symbols.txt" || true

grep -niEi 'viewDidLayoutSubviews|layoutSubviews|SettingsViewController|addSubview|insertSubview|bringSubviewToFront' \
 "$OUT/objc.txt" > "$OUT/objc_layout.txt" || true

{
 echo "=== SETTINGS LIFECYCLE ==="; cat "$OUT/settings_lifecycle.txt"
 echo; echo "=== SETTINGS BUILDER ==="; cat "$OUT/settings_builder.txt"
 echo; echo "=== LAYOUT SYMBOLS ==="; sed -n '1,1200p' "$OUT/layout_symbols.txt"
 echo; echo "=== OBJC LAYOUT ==="; sed -n '1,1200p' "$OUT/objc_layout.txt"
 echo; echo "=== SETTINGROW RENDERERS ==="; sed -n '1,3000p' "$OUT/settingrow_renderers.txt"
} > "$OUT/summary.txt"

rm -f "$OUT/disasm.txt" "$OUT/nm.txt" "$OUT/objc.txt"
sed -n '1,1800p' "$OUT/summary.txt"
