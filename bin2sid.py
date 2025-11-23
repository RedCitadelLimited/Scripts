#!/usr/bin/env python3
import sys
import struct

def binary_to_sid(sid_bytes):
    sid = "S-"
    sid += str(sid_bytes[0]) + "-"
    sub_authority_count = sid_bytes[1]
    identifier_authority = int.from_bytes(sid_bytes[2:8], byteorder='big')
    sid += str(identifier_authority)
    for i in range(sub_authority_count):
        start = 8 + i*4
        sub_auth = struct.unpack("<I", sid_bytes[start:start+4])[0]
        sid += "-" + str(sub_auth)
    return sid

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <binary_sid>")
        sys.exit(1)

    arg = sys.argv[1].strip()

    # remove leading b if the shell stripped the quotes
    if arg.startswith("b") and all(c in "0123456789abcdefABCDEF" for c in arg[1:]):
        arg = arg[1:]

    # remove surrounding b'...'
    if arg.startswith("b'") and arg.endswith("'"):
        arg = arg[2:-1]

    if arg.startswith('b"') and arg.endswith('"'):
        arg = arg[2:-1]

    try:
        sid_bytes = bytes.fromhex(arg)
    except ValueError:
        print("Invalid hex string")
        sys.exit(1)

    print(binary_to_sid(sid_bytes))

if __name__ == "__main__":
    main()
