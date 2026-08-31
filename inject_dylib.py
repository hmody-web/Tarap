#!/usr/bin/env python3
import struct, sys

LC_LOAD_DYLIB = 0xC
MH_MAGIC_64 = 0xFEEDFACF

def align8(n):
    return (n + 7) & ~7

def inject(path, dylib):
    data = bytearray(open(path, "rb").read())

    if struct.unpack_from("<I", data, 0)[0] != MH_MAGIC_64:
        raise SystemExit("Only thin arm64 Mach-O supported")

    ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)
    off = 32

    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)

        if cmd in (0xC, 0x80000018, 0x8000001F, 0x80000020, 0x80000023):
            nameoff = struct.unpack_from("<I", data, off + 8)[0]
            end = data.find(b"\0", off + nameoff, off + size)

            if end > 0:
                current = data[off + nameoff:end].decode("utf-8", "ignore")

                if current == dylib:
                    print("LC_LOAD_DYLIB already exists")
                    return

        off += size

    insert = 32 + sizeofcmds
    name = dylib.encode() + b"\0"
    cmdsize = align8(24 + len(name))

    if len(data[insert:insert + cmdsize]) < cmdsize or any(data[insert:insert + cmdsize]):
        raise SystemExit("Not enough Mach-O header padding")

    command = bytearray(cmdsize)

    struct.pack_into(
        "<IIIIII",
        command,
        0,
        LC_LOAD_DYLIB,
        cmdsize,
        24,
        2,
        0x10000,
        0x10000
    )

    command[24:24 + len(name)] = name
    data[insert:insert + cmdsize] = command

    struct.pack_into("<I", data, 16, ncmds + 1)
    struct.pack_into("<I", data, 20, sizeofcmds + cmdsize)

    open(path, "wb").write(data)

    print("Injected:", dylib)

if __name__ == "__main__":
    inject(sys.argv[1], sys.argv[2])
