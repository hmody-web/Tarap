#!/usr/bin/env python3
import struct, sys

LC_LOAD_DYLIB = 0xC
MH_MAGIC_64 = 0xFEEDFACF

def align8(n): return (n + 7) & ~7

def add_load_dylib(path, dylib):
    data = bytearray(open(path, "rb").read())
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != MH_MAGIC_64:
        raise SystemExit("Only thin 64-bit Mach-O is supported")

    # mach_header_64: 32 bytes
    ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)
    cmd_start = 32
    cmd_end = cmd_start + sizeofcmds

    # Don't add twice
    off = cmd_start
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd in (0xC, 0x18 | 0x80000000, 0x1F | 0x80000000, 0x20 | 0x80000000, 0x23 | 0x80000000):
            nameoff = struct.unpack_from("<I", data, off+8)[0]
            s0 = off + nameoff
            s1 = data.find(b"\0", s0, off+cmdsize)
            if s1 > s0 and data[s0:s1].decode("utf-8", "ignore") == dylib:
                print("LC_LOAD_DYLIB already exists")
                return
        off += cmdsize

    name = dylib.encode() + b"\0"
    cmdsize = align8(24 + len(name))
    newcmd = bytearray(cmdsize)
    struct.pack_into("<IIIIII", newcmd, 0, LC_LOAD_DYLIB, cmdsize, 24, 2, 0x10000, 0x10000)
    newcmd[24:24+len(name)] = name

    # Find earliest non-zero file-backed content after load commands.
    # Standard iOS executables normally have enough zero padding here.
    needed = len(newcmd)
    region = data[cmd_end:cmd_end+needed]
    if len(region) < needed or any(region):
        raise SystemExit(
            f"Not enough Mach-O header padding ({needed} bytes needed). "
            "Use optool/insert_dylib for this binary."
        )

    data[cmd_end:cmd_end+needed] = newcmd
    struct.pack_into("<I", data, 16, ncmds + 1)
    struct.pack_into("<I", data, 20, sizeofcmds + cmdsize)
    open(path, "wb").write(data)
    print("Injected:", dylib)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: inject_dylib.py <Mach-O> <@rpath/...>")
    add_load_dylib(sys.argv[1], sys.argv[2])
