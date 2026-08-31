#!/usr/bin/env python3
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
LC_LOAD_DYLIB = 0xC

def align8(n):
    return (n + 7) & ~7

def main(path, dylib):
    data = bytearray(open(path, "rb").read())

    if len(data) < 32 or struct.unpack_from("<I", data, 0)[0] != MH_MAGIC_64:
        raise SystemExit("Only thin arm64 Mach-O is supported by this injector.")

    ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)
    off = 32

    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)

        if cmd in (0xC, 0x80000018, 0x8000001F, 0x80000020, 0x80000023):
            nameoff = struct.unpack_from("<I", data, off + 8)[0]
            start = off + nameoff
            end = data.find(b"\0", start, off + cmdsize)

            if end > start:
                current = data[start:end].decode("utf-8", "ignore")
                if current == dylib:
                    print("Load command already present:", dylib)
                    return

        off += cmdsize

    name = dylib.encode("utf-8") + b"\0"
    cmdsize = align8(24 + len(name))
    insert = 32 + sizeofcmds

    padding = data[insert:insert + cmdsize]
    if len(padding) != cmdsize or any(padding):
        raise SystemExit("Not enough Mach-O header padding.")

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
    main(sys.argv[1], sys.argv[2])
