#!/usr/bin/env python3
"""vbt-tc1-edp.py IN OUT: copy a VBT, turning the TypeC port 1 (DP-F) child
device into a second internal panel (eDP, handle LFP2).

The ASUS Zephyrus Duo GX651AX wires its bottom OLED panel to TC1 in legacy
mode, but its VBT lists that port as an external DisplayPort, so xe drives an
eDP panel as DP. Load the result with xe.vbt_firmware=<file under /lib/firmware>.
"""
import struct
import sys

DVO_PORT_DPF = 13
DEVICE_HANDLE_LFP1 = 0x0008
DEVICE_HANDLE_LFP2 = 0x0080
DEVICE_TYPE_INTERNAL_CONNECTOR = 1 << 12
BDB_GENERAL_DEFINITIONS = 2
BDB_LFP_OPTIONS = 40
DP_MAX_LANE_COUNT_BYTE = 23
TC1_LANES = 2


def blocks(vbt, bdb):
    """(id, offset of the block's data, size) for each BDB block."""
    header_size, bdb_size = struct.unpack_from("<HH", vbt, bdb + 18)
    off = bdb + header_size
    while off < bdb + bdb_size:
        bid = vbt[off]
        size = struct.unpack_from("<H", vbt, off + 1)[0]
        yield bid, off + 3, size
        off += 3 + size


def main(src, dst):
    vbt = bytearray(open(src, "rb").read())
    assert vbt[:4] == b"$VBT", "not a VBT"
    bdb = struct.unpack_from("<I", vbt, 0x1C)[0]
    assert vbt[bdb:bdb + 16] == b"BIOS_DATA_BLOCK ", "no BDB header"
    version = struct.unpack_from("<H", vbt, bdb + 16)[0]
    print(f"BDB version {version}")

    found = {bid: (off, size) for bid, off, size in blocks(vbt, bdb)}

    off, size = found[BDB_GENERAL_DEFINITIONS]
    child_size = vbt[off + 4]
    tc1 = None
    handles = []
    for c in range(off + 5, off + size - child_size + 1, child_size):
        handle, dtype = struct.unpack_from("<HH", vbt, c)
        if dtype == 0:
            continue
        handles.append(handle)
        print(f"child handle={handle:#06x} type={dtype:#06x} dvo_port={vbt[c + 16]}")
        if vbt[c + 16] == DVO_PORT_DPF:
            tc1 = c
    assert tc1 is not None, "no DP-F (TC1) child device"
    assert DEVICE_HANDLE_LFP1 in handles, "no LFP1 child: expected the port A eDP"
    assert DEVICE_HANDLE_LFP2 not in handles, "an LFP2 child exists already"

    handle, dtype = struct.unpack_from("<HH", vbt, tc1)
    struct.pack_into("<HH", vbt, tc1, DEVICE_HANDLE_LFP2, dtype | DEVICE_TYPE_INTERNAL_CONNECTOR)
    print(f"TC1 child: handle {handle:#06x} -> {DEVICE_HANDLE_LFP2:#06x}, "
          f"type {dtype:#06x} -> {dtype | DEVICE_TYPE_INTERNAL_CONNECTOR:#06x}")

    # The panel claims 4 lanes at times, but a 4-lane link fails within seconds
    # ("8b/10b link not ok") and retrains forever: only 2 lanes are wired.
    # dp_max_lane_count (lanes - 1) is bits 6-7 of byte 23 (BDB 244+).
    assert version >= 244, "dp_max_lane_count needs BDB 244+"
    flags = vbt[tc1 + DP_MAX_LANE_COUNT_BYTE]
    vbt[tc1 + DP_MAX_LANE_COUNT_BYTE] = (flags & 0x3F) | ((TC1_LANES - 1) << 6)
    print(f"TC1 child: max lanes {(flags >> 6) + 1} -> {TC1_LANES}")

    if BDB_LFP_OPTIONS in found:
        lfp = found[BDB_LFP_OPTIONS][0]
        print(f"LFP options: panel_type={vbt[lfp]} panel_type2={vbt[lfp + 1]}")

    open(dst, "wb").write(vbt)
    print(f"wrote {dst}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
