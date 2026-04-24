#!/usr/bin/env python3
# bin2mem.py  IN  OUT  [WORDS]
# Convert a raw .bin file into a zero-padded $readmemh image.
# Each output line is one 32-bit little-endian word in hex, no prefix.
# Default padding is 4096 words (= 16 KB BRAM).
import sys, pathlib

src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])
n_words = int(sys.argv[3]) if len(sys.argv) > 3 else 4096

d = src.read_bytes()
d += b"\x00" * ((-len(d)) % 4)
words = [int.from_bytes(d[i:i+4], "little") for i in range(0, len(d), 4)]
if len(words) > n_words:
    sys.exit(f"ERROR: {src} is {len(words)} words, exceeds {n_words}")
words += [0] * (n_words - len(words))

with dst.open("w") as f:
    f.write("\n".join(f"{w:08x}" for w in words) + "\n")
