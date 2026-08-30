#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"
OUT="$ROOT/more_icon_results"
mkdir -p "$OUT"

[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

echo "macOS: $(sw_vers -productVersion)" > "$OUT/environment.txt"
xcodebuild -version >> "$OUT/environment.txt"

# Symbols/imports relevant to UIKit image creation and the More/settings screen.
xcrun nm -nm "$BIN" > "$OUT/nm.txt" 2>&1 || true
grep -niEi 'UIImage|systemName|systemImageNamed|imageNamed|settings|more|remove.?ads|subscribe|purchase' \
 "$OUT/nm.txt" > "$OUT/relevant_imports.txt" || true

# Disassemble once with Apple's otool, then let Python locate only calls around
# UIImage/SF Symbols and strings relevant to the More list.
xcrun otool -tvV "$BIN" > "$OUT/disassembly.txt" 2>&1 || true

python3 - "$BIN" "$OUT" <<'PY'
import sys,pathlib,re,struct,json
binp=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2])
b=binp.read_bytes()
d=(out/"disassembly.txt").read_text(errors="ignore").splitlines()

# Collect interesting imported call names and their surrounding assembly.
needles=[
 "UIImage", "systemImageNamed", "imageNamed", "subscribe and removeAds",
 "removeAds", "settings", "crown", "Join Tarab Premium"
]
hits=[]
for i,line in enumerate(d):
    low=line.lower()
    if any(n.lower() in low for n in needles):
        hits.append((i,line))

with (out/"interesting_disassembly_hits.txt").open("w") as f:
    for k,(i,line) in enumerate(hits):
        f.write(f"\n===== HIT {k}: {line} =====\n")
        f.write("\n".join(d[max(0,i-35):min(len(d),i+36)]))
        f.write("\n")

# Find literal strings relevant to More/settings and image APIs.
strings=[]
for m in re.finditer(rb'[\x20-\x7e]{5,}',b):
    s=m.group().decode(errors="ignore")
    lo=s.lower()
    if any(x in lo for x in ["removeads","subscribe","setting","more","uiimage",
                              "systemimage","imagenamed","crown","purchase"]):
        strings.append((m.start(),s))
(out/"relevant_binary_strings.txt").write_text(
    "\n".join(f"{o:#x}\t{s}" for o,s in strings))

# Compact summary.
(out/"summary.txt").write_text(
    f"Interesting disassembly hits: {len(hits)}\n"
    f"Relevant binary strings: {len(strings)}\n"
    "Search target: More/settings row icon path, especially UIKit UIImage/SF Symbol creation.\n")
PY

rm -f "$OUT/disassembly.txt"
echo "=== SUMMARY ==="
cat "$OUT/summary.txt"
echo "=== IMPORTS ==="
cat "$OUT/relevant_imports.txt" | head -200 || true
