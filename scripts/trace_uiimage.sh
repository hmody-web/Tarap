#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"; OUT="$ROOT/uiimage_trace"
mkdir -p "$OUT"
[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

xcrun nm -nm "$BIN" > "$OUT/nm.txt" 2>&1 || true
grep -niEi 'objc_getClass|sel_registerName|objc_msgSend|UIImage|imageNamed|SwiftUI.*Image|Image.*uiImage' \
 "$OUT/nm.txt" > "$OUT/imports.txt" || true

xcrun otool -Iv "$BIN" > "$OUT/indirect.txt" 2>&1 || true
grep -niEi 'objc_getClass|sel_registerName|objc_msgSend|UIImage|imageNamed' \
 "$OUT/indirect.txt" > "$OUT/indirect_relevant.txt" || true

xcrun otool -tvV "$BIN" > "$OUT/disasm.tmp" 2>&1 || true
grep -n -B60 -A100 -Ei 'imageNamed:|objc_getClass|sel_registerName|UIImage' \
 "$OUT/disasm.tmp" > "$OUT/native_uiimage_calls.txt" || true

strings -a -t x "$BIN" | grep -niEi '^(.*)(UIImage|imageNamed:)$|UIImage|imageNamed:' \
 > "$OUT/uiimage_strings.txt" || true

{
 echo "=== IMPORTS ==="; cat "$OUT/imports.txt" | head -200
 echo; echo "=== INDIRECT ==="; cat "$OUT/indirect_relevant.txt" | head -200
 echo; echo "=== NATIVE CALL WINDOWS ==="; cat "$OUT/native_uiimage_calls.txt" | head -600
 echo; echo "=== STRINGS ==="; cat "$OUT/uiimage_strings.txt" | head -100
} > "$OUT/summary.txt"
rm -f "$OUT/nm.txt" "$OUT/indirect.txt" "$OUT/disasm.tmp"
cat "$OUT/summary.txt"
