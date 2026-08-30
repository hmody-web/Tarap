#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"
OUT="$ROOT/xref_results"
mkdir -p "$OUT"

if [ ! -f "$BIN" ]; then
  ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
fi

python3 "$ROOT/scripts/direct_trace.py" "$BIN" "$OUT"
cat "$OUT/summary.txt"
