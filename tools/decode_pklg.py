#!/usr/bin/env python3
"""Decode an Apple PacketLogger .pklg capture and extract BLE ATT writes.

Usage: python3 decode_pklg.py /path/to/capture.pklg [target_handle_hex]

PacketLogger .pklg record format (big-endian):
    4 bytes  length (of the record minus this field... varies; we use it loosely)
    4 bytes  timestamp seconds
    4 bytes  timestamp microseconds
    1 byte   packet type:
                0x00 sent HCI command
                0x01 received HCI event
                0x02 sent ACL data
                0x03 received ACL data
    N bytes  payload

We care about ACL data (0x02/0x03) carrying L2CAP → ATT on the ATT CID (0x0004).
ATT opcodes of interest:
    0x52 Write Command, 0x12 Write Request, 0x1B Handle Value Notification,
    0x1D Handle Value Indication, 0x0A Read Response.
"""
import sys
import struct

ATT_OPCODES = {
    0x52: "WriteCommand",
    0x12: "WriteRequest",
    0x1B: "Notification",
    0x1D: "Indication",
    0x0A: "ReadResponse",
    0x0B: "ReadByTypeResp",
}


def records(data: bytes):
    """Yield (pkt_type, payload) from a .pklg byte stream."""
    i = 0
    n = len(data)
    while i + 13 <= n:
        length = struct.unpack_from(">I", data, i)[0]
        # length covers the 9 header bytes after it (ts+ts+type) + payload,
        # i.e. total record = 4 (length field) + length.
        if length < 9 or i + 4 + length > n:
            # Be forgiving about trailing/garbled bytes.
            break
        pkt_type = data[i + 12]
        payload = data[i + 13 : i + 4 + length]
        yield pkt_type, payload
        i += 4 + length


def parse_acl_att(payload: bytes):
    """From an ACL data payload, return (cid, att_bytes) if it's ATT, else None."""
    # ACL header: 2 bytes handle+flags, 2 bytes total length
    if len(payload) < 4:
        return None
    acl_len = struct.unpack_from("<H", payload, 2)[0]
    l2cap = payload[4 : 4 + acl_len]
    if len(l2cap) < 4:
        return None
    # L2CAP: 2 bytes length, 2 bytes CID
    cid = struct.unpack_from("<H", l2cap, 2)[0]
    att = l2cap[4:]
    return cid, att


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    path = sys.argv[1]
    want_handle = int(sys.argv[2], 16) if len(sys.argv) > 2 else None

    with open(path, "rb") as f:
        data = f.read()

    print(f"# Decoded {path} ({len(data)} bytes)\n")
    print(f"{'dir':<4} {'opcode':<14} {'handle':<8} {'hex':<48} ascii")
    print("-" * 90)

    writes = []
    for pkt_type, payload in records(data):
        if pkt_type not in (0x02, 0x03):
            continue  # only ACL data
        res = parse_acl_att(payload)
        if not res:
            continue
        cid, att = res
        if cid != 0x0004 or not att:  # ATT CID
            continue
        opcode = att[0]
        name = ATT_OPCODES.get(opcode)
        if not name:
            continue
        direction = "TX" if pkt_type == 0x02 else "RX"
        # Write Req/Cmd and Notifications carry a 2-byte handle then value.
        if opcode in (0x52, 0x12, 0x1B, 0x1D):
            if len(att) < 3:
                continue
            handle = struct.unpack_from("<H", att, 1)[0]
            value = att[3:]
        else:
            handle = None
            value = att[1:]
        if want_handle is not None and handle != want_handle:
            continue
        hexs = " ".join(f"{b:02X}" for b in value)
        ascii_s = "".join(chr(b) if 32 <= b < 127 else "." for b in value)
        hstr = f"0x{handle:04X}" if handle is not None else "—"
        print(f"{direction:<4} {name:<14} {hstr:<8} {hexs[:47]:<48} {ascii_s}")
        if opcode in (0x52, 0x12):
            writes.append((handle, value))

    print("\n# --- Summary of WRITES (commands sent by the app) ---")
    seen = set()
    for handle, value in writes:
        key = (handle, bytes(value))
        if key in seen:
            continue
        seen.add(key)
        hexs = " ".join(f"{b:02X}" for b in value)
        ascii_s = "".join(chr(b) if 32 <= b < 127 else "." for b in value)
        print(f"handle 0x{handle:04X}: {hexs}   | {ascii_s}")


if __name__ == "__main__":
    main()
