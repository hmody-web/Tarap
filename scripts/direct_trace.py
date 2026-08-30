import sys,struct,pathlib,re,json
BIN=pathlib.Path(sys.argv[1]); OUT=pathlib.Path(sys.argv[2]); OUT.mkdir(exist_ok=True)
b=BIN.read_bytes()

# Parse 64-bit little-endian Mach-O sections and segments.
MH_MAGIC_64=0xfeedfacf
magic,=struct.unpack_from("<I",b,0)
if magic!=MH_MAGIC_64: raise SystemExit("Not arm64 Mach-O")
_,_,_,_,ncmds,sizeofcmds,_,_=struct.unpack_from("<IiiIIIII",b,0)
off=32; segs=[]; sections=[]
for _ in range(ncmds):
    cmd,cmdsize=struct.unpack_from("<II",b,off)
    if cmd==0x19: # LC_SEGMENT_64
        segname=b[off+8:off+24].split(b'\0')[0].decode(errors='ignore')
        vmaddr,vmsize,fileoff,filesize=struct.unpack_from("<QQQQ",b,off+24)
        nsects,=struct.unpack_from("<I",b,off+64)
        segs.append((segname,vmaddr,vmsize,fileoff,filesize))
        so=off+72
        for i in range(nsects):
            sect=b[so:so+16].split(b'\0')[0].decode(errors='ignore')
            sseg=b[so+16:so+32].split(b'\0')[0].decode(errors='ignore')
            addr,size=struct.unpack_from("<QQ",b,so+32)
            foff,=struct.unpack_from("<I",b,so+48)
            sections.append((sseg,sect,addr,size,foff))
            so+=80
    off+=cmdsize

def va_to_off(va):
    for name,vm,vs,fo,fs in segs:
        if vm<=va<vm+fs: return fo+(va-vm)
    return None
def off_to_va(o):
    for name,vm,vs,fo,fs in segs:
        if fo<=o<fo+fs: return vm+(o-fo)
    return None

# Locate exact localization key in file and map it to VA.
needle=b"subscribe and removeAds"
positions=[m.start() for m in re.finditer(re.escape(needle),b)]
lines=[f"Exact key file offsets: {[hex(x) for x in positions]}"]
for p in positions:
    lines.append(f"key file {p:#x} -> VA {off_to_va(p)}")

# Known addresses from previous direct binary analysis.
crowns=[0x102cfbc68,0x102d07ef8]
key_known=0x103a68ad0

# Direct ARM64 scan for ADRP+ADD address materialization of target.
# adrp Xd, page; add Xd, Xn, #imm12
textsecs=[x for x in sections if x[0]=="__TEXT" and x[1]=="__text"]
refs=[]
targets=[("key", key_known)]
for label,target in targets:
    tpage=target & ~0xfff
    toff=target & 0xfff
    for _,_,addr,size,fo in textsecs:
        end=min(fo+size,len(b))
        for pos in range(fo,end-8,4):
            w=struct.unpack_from("<I",b,pos)[0]
            if (w & 0x9F000000)!=0x90000000: continue # ADRP
            rd=w&31
            immlo=(w>>29)&3; immhi=(w>>5)&0x7ffff
            imm=(immhi<<2)|immlo
            if imm&(1<<20): imm-=1<<21
            pc=off_to_va(pos)
            page=(pc & ~0xfff)+(imm<<12)
            if page!=tpage: continue
            # scan next few insns for ADD immediate using same register
            for q in range(pos+4,min(pos+24,end),4):
                a=struct.unpack_from("<I",b,q)[0]
                # ADD (immediate), 64-bit
                if (a & 0x7F000000)!=0x11000000: continue
                rn=(a>>5)&31; rd2=a&31
                if rn!=rd: continue
                imm12=(a>>10)&0xfff
                sh=(a>>22)&1
                val=page+(imm12<<(12 if sh else 0))
                if val==target:
                    refs.append((label,off_to_va(pos),off_to_va(q),rd))

# Also scan for literal references in 64-bit pointer/data sections to key VA.
ptrrefs=[]
for pos in range(0,len(b)-8,8):
    v=struct.unpack_from("<Q",b,pos)[0]
    if v==key_known:
        ptrrefs.append((pos,off_to_va(pos)))

lines.append(f"Direct ADRP+ADD refs to key: {len(refs)}")
for r in refs: lines.append(f"  {r}")
lines.append(f"64-bit pointer refs to key: {len(ptrrefs)}")
for r in ptrrefs[:100]: lines.append(f"  file={r[0]:#x} va={r[1]}")

# Dump raw ARM64 words around any code refs and around crown callsites.
def dump_words(va, radius=0x100):
    o=va_to_off(va)
    if o is None:return "unmapped"
    st=max(0,o-radius); en=min(len(b),o+radius)
    out=[]
    for p in range(st,en,4):
        w=struct.unpack_from("<I",b,p)[0]
        out.append(f"{off_to_va(p):#x} {w:08x}")
    return "\n".join(out)

for i,r in enumerate(refs):
    (OUT/f"key_ref_{i}_arm64_words.txt").write_text(dump_words(r[1],0x200))
for a in crowns:
    (OUT/f"crown_{a:x}_arm64_words.txt").write_text(dump_words(a,0x300))

# Search a wide byte neighborhood for Swift metadata/function-name clues.
for a in [key_known,*crowns]:
    o=va_to_off(a)
    if o is not None:
        chunk=b[max(0,o-0x4000):min(len(b),o+0x4000)]
        strings=re.findall(rb'[\x20-\x7e]{5,}',chunk)
        (OUT/f"strings_near_{a:x}.txt").write_text("\n".join(x.decode(errors="replace") for x in strings))

(OUT/"summary.txt").write_text("\n".join(lines))
(OUT/"macho_sections.json").write_text(json.dumps(
    [{"segment":a,"section":s,"addr":hex(v),"size":hex(sz),"fileoff":hex(fo)}
     for a,s,v,sz,fo in sections],indent=2))
