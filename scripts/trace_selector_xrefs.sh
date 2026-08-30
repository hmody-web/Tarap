#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/CloudManager"
OUT="$ROOT/selector_xref_trace"
mkdir -p "$OUT"
[ -f "$BIN" ] || ditto -x -k "$ROOT/CloudManager.zip" "$ROOT"
chmod +x "$BIN"

xcrun otool -l "$BIN" > "$OUT/loadcmds.txt" 2>&1
xcrun otool -v -s __DATA_CONST __objc_selrefs "$BIN" > "$OUT/selrefs.txt" 2>&1 || true
xcrun otool -v -s __DATA __objc_selrefs "$BIN" >> "$OUT/selrefs.txt" 2>&1 || true
xcrun otool -v -s __TEXT __objc_methname "$BIN" > "$OUT/methnames.txt" 2>&1 || true
xcrun otool -tvV "$BIN" > "$OUT/disasm.txt" 2>&1

# Use Mach-O metadata directly to resolve selector-ref addresses to names,
# then locate ADRP/LDR references to the selected selector slots.
python3 - <<'PY'
from pathlib import Path
import re, struct

binp=Path("CloudManager")
data=binp.read_bytes()
load=Path("selector_xref_trace/loadcmds.txt").read_text(errors="ignore")
dis=Path("selector_xref_trace/disasm.txt").read_text(errors="ignore").splitlines()

# Parse sections from otool -l.
secs=[]
cur={}
for line in load.splitlines():
    s=line.strip()
    if s.startswith("sectname "):
        if cur.get("sectname"): secs.append(cur)
        cur={"sectname":s.split(None,1)[1]}
    elif s.startswith("segname ") and cur:
        cur["segname"]=s.split(None,1)[1]
    elif s.startswith("addr ") and cur:
        cur["addr"]=int(s.split()[1],16)
    elif s.startswith("size ") and cur:
        cur["size"]=int(s.split()[1],16)
    elif s.startswith("offset ") and cur:
        cur["offset"]=int(s.split()[1],0)
if cur.get("sectname"): secs.append(cur)

def sec(name):
    xs=[x for x in secs if x.get("sectname")==name and all(k in x for k in ("addr","size","offset"))]
    return xs

def vm_to_off(vm):
    for x in secs:
        if all(k in x for k in ("addr","size","offset")) and x["addr"] <= vm < x["addr"]+x["size"]:
            return x["offset"] + (vm-x["addr"])
    return None

def cstr(vm):
    off=vm_to_off(vm)
    if off is None: return None
    e=data.find(b"\0",off,min(len(data),off+256))
    if e<0: return None
    try: return data[off:e].decode()
    except: return None

targets={"imageNamed:","initWithImage:","addSubview:","setFrame:","setImage:",
         "setContentMode:","setClipsToBounds:","layer","setCornerRadius:"}

resolved=[]
for sr in sec("__objc_selrefs"):
    start=sr["offset"]; n=sr["size"]//8
    for i in range(n):
        ptr=struct.unpack_from("<Q",data,start+i*8)[0]
        name=cstr(ptr)
        if name in targets:
            resolved.append((sr["addr"]+i*8,name,ptr))

Path("selector_xref_trace/resolved_selectors.txt").write_text(
    "\n".join(f"{a:#x} -> {name} (methname {p:#x})" for a,name,p in resolved)
)

# Parse ARM64 instruction addresses.
ins=[]
for idx,l in enumerate(dis):
    m=re.match(r'\s*([0-9a-fA-F]{8,16})\s+(.*)',l)
    if m: ins.append((idx,int(m.group(1),16),m.group(2),l))

# Detect ADRP + later LDR x1/w1 using same base register and compute selref address.
# otool -V often resolves labels; also retain textual direct hits.
windows=[]
for pos,(idx,a,op,full) in enumerate(ins):
    low=op.lower()
    if any(name.lower() in low for name in targets):
        windows.append((idx,a,"textual"))
    m=re.search(r'adrp\s+x(\d+),\s*0x([0-9a-fA-F]+)',low)
    if not m: continue
    reg=int(m.group(1)); page=int(m.group(2),16)
    for q in range(pos+1,min(len(ins),pos+9)):
        idx2,a2,op2,full2=ins[q]
        ml=re.search(r'ldr\s+x1,\s*\[x%d,\s*#0x([0-9a-fA-F]+)\]'%reg,op2.lower())
        if ml:
            ref=page+int(ml.group(1),16)
            for ra,name,_ in resolved:
                if ref==ra:
                    windows.append((idx,a,f"{name} via {ra:#x}"))
            break

# Deduplicate and emit broad context to capture objc_msgSend + receiver setup.
seen=set(); out=[]
for idx,a,why in sorted(windows,key=lambda x:x[0]):
    key=idx//20
    if key in seen: continue
    seen.add(key)
    lo=max(0,idx-45); hi=min(len(dis),idx+90)
    out.append(f"===== XREF {a:#x}: {why} =====")
    out.extend(dis[lo:hi])
Path("selector_xref_trace/xref_windows.txt").write_text("\n".join(out))

# Always include Settings integration region.
sv=[]
for _,a,_,full in ins:
    if 0x102d1e650 <= a <= 0x102d1ea80:
        sv.append(full)
Path("selector_xref_trace/settings_integration.txt").write_text("\n".join(sv))
PY

{
 echo "=== RESOLVED SELECTORS ==="
 cat "$OUT/resolved_selectors.txt"
 echo
 echo "=== SELECTOR XREF WINDOWS ==="
 sed -n '1,7000p' "$OUT/xref_windows.txt"
 echo
 echo "=== SETTINGS INTEGRATION ==="
 cat "$OUT/settings_integration.txt"
} > "$OUT/summary.txt"

rm -f "$OUT/loadcmds.txt" "$OUT/selrefs.txt" "$OUT/methnames.txt" "$OUT/disasm.txt"
sed -n '1,2200p' "$OUT/summary.txt"
