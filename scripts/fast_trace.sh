#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"
OUT="$ROOT/xref_results"
mkdir -p "$OUT"

if [ ! -f "$BIN" ]; then
  echo "Extracting CloudManager..."
  ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
fi
test -f "$BIN" || { echo "CloudManager extraction failed"; exit 2; }

echo "macOS: $(sw_vers -productVersion)"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "Binary: $(stat -f%z "$BIN") bytes"

if ! command -v r2 >/dev/null 2>&1; then
  echo "Installing radare2..."
  brew install radare2
fi

# ONE radare2 process and ONE lightweight analysis pass.
# We already know the two crown addresses, so no need for full aaa repeatedly.
cat > "$ROOT/trace.r2" <<'R2'
e scr.color=false
e anal.hasnext=true
aa
izz~subscribe and removeAds
izz~com.appmania.TarabApp.removeAds
izz~SubscribePopupViewController
izz~RemoveAdsByPromoCode
s 0x103a68ad0
axt
s 0x102cfbc68
afi
pdf
s 0x102d07ef8
afi
pdf
q
R2

echo "Running single-pass trace..."
r2 -2 -q -e bin.cache=true -i "$ROOT/trace.r2" "$BIN" > "$OUT/trace.txt" 2>&1 || true

# Also grab raw context around the known localization string bytes without analysis.
python3 - "$BIN" "$OUT" <<'PY'
import sys, pathlib
b=pathlib.Path(sys.argv[1]).read_bytes()
out=pathlib.Path(sys.argv[2])
needle=b"subscribe and removeAds"
pos=b.find(needle)
with (out/"binary_string_location.txt").open("w") as f:
    f.write(f"file_offset={pos:#x}\n" if pos>=0 else "not found\n")
    if pos>=0:
        f.write(repr(b[max(0,pos-256):pos+512]))
PY

grep -niE 'subscribe and removeAds|removeAds|crown|0x102cfbc68|0x102d07ef8|0x103a68ad0' \
  "$OUT/trace.txt" > "$OUT/relevant_lines.txt" || true

echo "=== relevant results ==="
cat "$OUT/relevant_lines.txt" || true
echo "DONE"
