#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"
OUT="$ROOT/symbol_results"
mkdir -p "$OUT"

[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

echo "macOS: $(sw_vers -productVersion)" > "$OUT/environment.txt"
xcodebuild -version >> "$OUT/environment.txt"

# No Homebrew, no radare2: only Xcode/macOS native tools.
xcrun nm -nm "$BIN" > "$OUT/nm_all.txt" 2>&1 || true
xcrun nm -nm -m "$BIN" > "$OUT/nm_macho.txt" 2>&1 || true
xcrun otool -Iv "$BIN" > "$OUT/indirect_symbols.txt" 2>&1 || true

# Demangle whatever Swift symbols survived stripping.
python3 - "$OUT/nm_all.txt" "$OUT/swift_mangled.txt" <<'PY'
import sys,re,pathlib
s=pathlib.Path(sys.argv[1]).read_text(errors="ignore")
syms=[]
for line in s.splitlines():
    m=re.search(r'(\$s[A-Za-z0-9_.$]+)',line)
    if m: syms.append(m.group(1))
pathlib.Path(sys.argv[2]).write_text("\n".join(dict.fromkeys(syms)))
PY

if [ -s "$OUT/swift_mangled.txt" ]; then
  xcrun swift-demangle < "$OUT/swift_mangled.txt" > "$OUT/swift_demangled.txt" 2>&1 || true
else
  : > "$OUT/swift_demangled.txt"
fi

# Filter names likely related to the More/settings/subscription screen.
grep -niEi 'more|setting|subscribe|subscription|remove.?ads|purchase|promo|crown|row|section' \
  "$OUT/swift_demangled.txt" > "$OUT/relevant_swift_symbols.txt" || true
grep -niEi 'more|setting|subscribe|subscription|remove.?ads|purchase|promo|crown|row|section' \
  "$OUT/nm_all.txt" > "$OUT/relevant_nm_symbols.txt" || true

# Disassemble only small windows around the two crown callsites.
xcrun otool -tvV "$BIN" > "$OUT/text_disassembly.txt" 2>&1 || true
python3 - "$OUT/text_disassembly.txt" "$OUT" <<'PY'
import sys,re,pathlib
src=pathlib.Path(sys.argv[1]).read_text(errors="ignore").splitlines()
out=pathlib.Path(sys.argv[2])
targets=[0x102cfbc68,0x102d07ef8]
parsed=[]
for i,l in enumerate(src):
    m=re.match(r'^\s*([0-9a-fA-F]{8,16})\s+',l)
    if m:
        try: parsed.append((int(m.group(1),16),i))
        except: pass
for t in targets:
    if not parsed: continue
    nearest=min(parsed,key=lambda x:abs(x[0]-t))
    i=nearest[1]
    lo=max(0,i-100); hi=min(len(src),i+101)
    (out/f"crown_{t:x}_otool.txt").write_text("\n".join(src[lo:hi]))
PY

# Keep a compact report; the large full disassembly is not needed as an artifact.
{
  echo "=== Relevant Swift symbols ==="
  cat "$OUT/relevant_swift_symbols.txt" 2>/dev/null || true
  echo
  echo "=== Relevant nm symbols ==="
  cat "$OUT/relevant_nm_symbols.txt" 2>/dev/null || true
} > "$OUT/summary.txt"

rm -f "$OUT/text_disassembly.txt"

echo "DONE"
cat "$OUT/summary.txt"
