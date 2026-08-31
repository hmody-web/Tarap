#!/usr/bin/env python3
import struct, sys
LC_LOAD_DYLIB=0xC
MH_MAGIC_64=0xFEEDFACF
def a8(n): return (n+7)&~7
def inject(path,dylib):
    d=bytearray(open(path,"rb").read())
    if struct.unpack_from("<I",d,0)[0]!=MH_MAGIC_64:
        raise SystemExit("Only thin arm64 Mach-O supported")
    ncmds,sizeofcmds=struct.unpack_from("<II",d,16)
    off=32
    for _ in range(ncmds):
        cmd,sz=struct.unpack_from("<II",d,off)
        if cmd in (0xC,0x80000018,0x8000001F,0x80000020,0x80000023):
            no=struct.unpack_from("<I",d,off+8)[0]
            e=d.find(b"\0",off+no,off+sz)
            if e>0 and d[off+no:e].decode("utf-8","ignore")==dylib:
                print("LC_LOAD_DYLIB already exists"); return
        off+=sz
    end=32+sizeofcmds
    name=dylib.encode()+b"\0"
    sz=a8(24+len(name))
    if len(d[end:end+sz])<sz or any(d[end:end+sz]):
        raise SystemExit("Not enough Mach-O header padding")
    c=bytearray(sz)
    struct.pack_into("<IIIIII",c,0,LC_LOAD_DYLIB,sz,24,2,0x10000,0x10000)
    c[24:24+len(name)]=name
    d[end:end+sz]=c
    struct.pack_into("<I",d,16,ncmds+1)
    struct.pack_into("<I",d,20,sizeofcmds+sz)
    open(path,"wb").write(d)
    print("Injected",dylib)
if __name__=="__main__":
    inject(sys.argv[1],sys.argv[2])
