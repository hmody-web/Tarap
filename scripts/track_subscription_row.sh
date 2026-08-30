#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"
OUT="$ROOT/xref_results"
mkdir -p "$OUT"

echo "macOS: $(sw_vers -productVersion)" | tee "$OUT/environment.txt"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')" | tee -a "$OUT/environment.txt"

# Install radare2 on the macOS runner if it is not already present.
if ! command -v r2 >/dev/null 2>&1; then
  brew install radare2
fi

chmod +x "$BIN"

# Full analysis, strings, xrefs, and functions.
r2 -2 -q -e bin.cache=true -c 'aaa; izz~subscribe and removeAds; q' "$BIN" \
  > "$OUT/key_location.txt" 2>&1 || true

# Scripted r2 session: locate the exact string and ask r2 for references to it.
cat > "$ROOT/find_xref.r2" <<'R2'
aaa
izz~subscribe and removeAds
izz~com.appmania.TarabApp.removeAds
izz~SubscribePopupViewController
izz~RemoveAdsByPromoCode
axt @@ str.subscribe_and_removeAds
q
R2

r2 -2 -q -e bin.cache=true -i "$ROOT/find_xref.r2" "$BIN" \
  > "$OUT/raw_xrefs.txt" 2>&1 || true

# r2 string flag names can vary, so use JSON to locate the string address and
# then run axt/axtj directly at that virtual address.
python3 - "$BIN" "$OUT" <<'PY'
import json, subprocess, sys, pathlib
binp, out = sys.argv[1], pathlib.Path(sys.argv[2])

def r2(cmd):
    return subprocess.run(["r2","-2","-q","-e","bin.cache=true","-c",cmd,binp],
                          text=True,capture_output=True).stdout

s = r2("aaa; izzj; q")
try:
    arr=json.loads(s)
except Exception:
    arr=[]
targets=[]
for x in arr:
    st=x.get("string","")
    if "subscribe and removeAds" in st:
        targets.append(x)

(out/"string_json_matches.json").write_text(json.dumps(targets,indent=2))
summary=[]
for i,x in enumerate(targets):
    va=x.get("vaddr") or x.get("paddr")
    if va is None: continue
    va=int(va)
    summary.append(f"STRING {i}: {va:#x} {x.get('string')}")
    xrefs=r2(f"aaa; axt @ {va}; q")
    (out/f"xrefs_{i}.txt").write_text(xrefs)
    # Dump generous disassembly around each xref address.
    for j,line in enumerate([l for l in xrefs.splitlines() if l.strip()]):
        import re
        m=re.search(r'0x[0-9a-fA-F]+',line)
        if not m: continue
        xa=int(m.group(0),16)
        dis=r2(f"aaa; s {xa}; pdf; q")
        (out/f"xref_{i}_{j}_function.txt").write_text(dis)
        near=r2(f"aaa; s {xa-0x100}; pd 160; q")
        (out/f"xref_{i}_{j}_nearby.txt").write_text(near)

(out/"summary.txt").write_text("\n".join(summary) if summary else "No exact string match found")
PY

# Separately dump the two known crown callsites so their containing functions
# can be compared directly with the localization-key xref function.
for A in 0x102cfbc68 0x102d07ef8; do
  SAFE="${A#0x}"
  r2 -2 -q -e bin.cache=true -c "aaa; s $A; pdf; q" "$BIN" \
    > "$OUT/crown_${SAFE}_function.txt" 2>&1 || true
  r2 -2 -q -e bin.cache=true -c "aaa; s $((A-0x180)); pd 240; q" "$BIN" \
    > "$OUT/crown_${SAFE}_nearby.txt" 2>&1 || true
done

# Search generated disassembly for the relevant key/crown/function relationships.
grep -RniE 'subscribe and removeAds|crown|removeAds|SubscribePopup' "$OUT" \
  > "$OUT/relevant_matches.txt" || true

echo "=== SUMMARY ==="
cat "$OUT/summary.txt" || true
echo "Artifacts are in xref_results/"
