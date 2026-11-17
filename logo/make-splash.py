#!/usr/bin/env python3
"""Draw the boot splash's images: logo/make-splash.py DIR

Writes into DIR (overlay/usr/share/plymouth/themes/applereplay) the pieces
the Plymouth theme puts under the logo: the blocks of the progress bar, lit
in the Apple II's hi-res colours or unlit, and the characters of the line
under it (the box's address at boot, "safe to turn off" at shutdown), in the
shapes of the Apple II's own uppercase text.
The logo itself is logo/BootLogo.png, which the build copies in.

Plain 8-bit RGB PNGs, like the logo. Needs only Python 3.
"""
import os
import struct
import sys
import zlib

BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
GREEN = (20, 245, 60)
VIOLET = (255, 68, 253)
ORANGE = (255, 106, 60)
BLUE = (20, 207, 253)
UNLIT = (44, 44, 50)

BLOCK = 16  # pixels square; the theme spaces them 4 apart
GLYPH_SCALE = 3  # 5x7 characters drawn at 15x21

FONT5 = {  # 5x7, the shapes of the Apple II's own uppercase-only text
    "0": "01110 10001 10011 10101 11001 10001 01110",
    "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00110 01000 10000 11111",
    "3": "11111 00001 00010 00110 00001 10001 01110",
    "4": "00010 00110 01010 10010 11111 00010 00010",
    "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00111 01000 10000 11110 10001 10001 01110",
    "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110",
    "9": "01110 10001 10001 01111 00001 00010 11100",
    ".": "00000 00000 00000 00000 00000 00000 00100",
    "A": "00100 01010 10001 10001 11111 10001 10001",
    "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01110 10001 10000 10000 10000 10001 01110",
    "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111",
    "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01111 10000 10000 10011 10001 10001 01111",
    "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "01110 00100 00100 00100 00100 00100 01110",
    "J": "00001 00001 00001 00001 00001 10001 01110",
    "K": "10001 10010 10100 11000 10100 10010 10001",
    "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001",
    "N": "10001 10001 11001 10101 10011 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110",
    "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101",
    "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01110 10001 10000 01110 00001 10001 01110",
    "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110",
    "V": "10001 10001 10001 10001 10001 01010 00100",
    "W": "10001 10001 10001 10101 10101 11011 10001",
    "X": "10001 10001 01010 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100",
    "Z": "11111 00001 00010 00100 01000 10000 11111",
}
# File names for characters that can't be one (the theme uses the same map).
NAMES = {".": "dot"}


def png(rows):
    """rows: a list of rows of (r, g, b)."""
    raw = b"".join(b"\0" + b"".join(bytes(p) for p in row) for row in rows)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", len(rows[0]), len(rows), 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) +
            chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def block(colour):
    """A square with a one-pixel darker rim, so neighbours read as blocks."""
    rim = tuple(c * 3 // 5 for c in colour)
    return [[rim if x in (0, BLOCK - 1) or y in (0, BLOCK - 1) else colour
             for x in range(BLOCK)] for y in range(BLOCK)]


def glyph(bits):
    rows = []
    for line in bits.split():
        row = [WHITE if b == "1" else BLACK for b in line for _ in range(GLYPH_SCALE)]
        rows += [row] * GLYPH_SCALE
    return rows


def images():
    out = {}
    for name, colour in (("green", GREEN), ("violet", VIOLET),
                         ("orange", ORANGE), ("blue", BLUE), ("off", UNLIT)):
        out["block-%s.png" % name] = png(block(colour))
    for ch, bits in FONT5.items():
        out["char-%s.png" % NAMES.get(ch, ch)] = png(glyph(bits))
    return out


if __name__ == "__main__":
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        sys.exit("usage: logo/make-splash.py DIR")
    for name, data in sorted(images().items()):
        with open(os.path.join(sys.argv[1], name), "wb") as f:
            f.write(data)
