#!/usr/bin/env python3
"""Draw applereplay's boot logo: logo/make-logo.py [scale] > logo/BootLogo.png

Pixel art on a 160x90 grid in the Apple II's hi-res colours, written as a
plain 8-bit RGB PNG (no alpha, not interlaced) for Apple's boot.efi, which
shows it centred on the black boot screen. Needs only Python 3.

All of it is drawn here from scratch: no Apple logo, nothing from Total
Replay or any game.
"""
import struct
import sys
import zlib

W, H = 160, 90
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
GREEN = (20, 245, 60)
VIOLET = (255, 68, 253)
ORANGE = (255, 106, 60)
BLUE = (20, 207, 253)
SILVER = (196, 198, 204)
STEEL = (120, 122, 130)
PEARL = (244, 244, 238)
BEIGE = (222, 206, 170)
TAN = (160, 146, 116)

FONT5 = {  # 5x7, the shapes of the Apple II's own uppercase-only text
    "A": "01110 10001 10001 11111 10001 10001 10001",
    "E": "11111 10000 10000 11110 10000 10000 11111",
    "L": "10000 10000 10000 10000 10000 10000 11111",
    "N": "10001 11001 10101 10011 10001 10001 10001",
    "P": "11110 10001 10001 11110 10000 10000 10000",
    "R": "11110 10001 10001 11110 10100 10010 10001",
    "U": "10001 10001 10001 10001 10001 10001 01110",
    "Y": "10001 10001 01010 00100 00100 00100 00100",
    "]": "01110 00010 00010 00010 00010 00010 01110",
    "#": "10101 01010 10101 01010 10101 01010 10101",  # the flashing cursor
    " ": "00000 00000 00000 00000 00000 00000 00000",
}
FONT3 = {  # 3x5, for the small print
    "0": "111 101 101 101 111", "1": "010 110 010 010 111",
    "2": "111 001 111 100 111", "6": "111 100 111 101 111",
    "8": "111 101 111 101 111", "9": "111 101 111 001 111",
    "A": "010 101 111 101 101", "C": "111 100 100 100 111",
    "D": "110 101 101 101 110", "E": "111 100 110 100 111",
    "G": "011 100 101 101 011", "H": "101 101 111 101 101",
    "M": "101 111 111 101 101", "R": "110 101 110 101 101",
    "S": "011 100 010 001 110", "T": "111 010 010 010 010",
    "W": "101 101 101 111 101", ".": "000 000 010 000 000",
    " ": "000 000 000 000 000",
}
CRITTER = [  # a friendly blob with feet; two frames of walking
    ["0011100", "0111110", "1101011", "1111111", "0111110", "0100010", "1100011"],
    ["0011100", "0111110", "1101011", "1111111", "0111110", "0010100", "0110110"],
]

canvas = [[BLACK] * W for _ in range(H)]


def dot(x, y, colour):
    if 0 <= x < W and 0 <= y < H:
        canvas[y][x] = colour


def box(x, y, w, h, colour):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            dot(xx, yy, colour)


def bitmap(x, y, rows, colour, scale=1):
    for r, row in enumerate(rows):
        for c, bit in enumerate(row):
            if bit == "1":
                box(x + c * scale, y + r * scale, scale, scale, colour)


def dim(colour):
    return tuple(v * 2 // 5 for v in colour)


def text(x, y, s, font, colours, scale=1, shadow=False):
    """Draw s; colours is one colour or one per character. Returns the end x."""
    width = len(next(iter(font.values())).split()[0])
    for i, ch in enumerate(s):
        colour = colours[i % len(colours)] if isinstance(colours, list) else colours
        rows = font[ch].split()
        if shadow:
            bitmap(x + 1, y + 1, rows, dim(colour), scale)
        bitmap(x, y, rows, colour, scale)
        x += (width + 1) * scale
    return x


# What you typed to start a program, with the cursor waiting.
text(15, 6, "]RUN APPLEREPLAY#", FONT5, GREEN)

# The name, one hi-res colour per letter.
text(15, 21, "APPLEREPLAY", FONT5, [GREEN, VIOLET, ORANGE, BLUE], scale=2, shadow=True)

# A strip of colour blocks, like a hi-res colour test.
for i, x in enumerate(range(15, 145, 6)):
    box(x, 41, 5, 3, [VIOLET, GREEN, WHITE, ORANGE, BLUE][i % 5])

# 2006 hardware on the left, seen from above: a rounded square with a silver
# edge and a whitish top, and our initials where the maker's mark would be.
for inset, colour in enumerate([STEEL, SILVER, SILVER, PEARL]):
    box(20 + inset + 2, 47 + inset, 21 - 2 * inset - 4, 21 - 2 * inset, colour)
    box(20 + inset, 47 + inset + 2, 21 - 2 * inset, 21 - 2 * inset - 4, colour)
    box(20 + inset + 1, 47 + inset + 1, 21 - 2 * inset - 2, 21 - 2 * inset - 2, colour)
text(27, 55, "AR", FONT3, STEEL)
# 1980s on the right: a joystick, two buttons and all.
box(116, 60, 28, 7, BEIGE)
box(116, 66, 28, 1, TAN)
box(119, 58, 4, 2, ORANGE)
box(125, 58, 4, 2, ORANGE)
box(134, 50, 2, 10, STEEL)
box(132, 47, 6, 5, ORANGE)
dot(132, 47, BLACK), dot(137, 47, BLACK), dot(132, 51, BLACK), dot(137, 51, BLACK)
dot(134, 48, WHITE)
# Between them, the games walk across.
for i, colour in enumerate([VIOLET, GREEN, BLUE]):
    bitmap(52 + i * 22, 51 + 2 * (i % 2), CRITTER[i % 2], colour, scale=2)
for x in range(48, 114, 3):
    dot(x, 68, WHITE if x % 2 else STEEL)

# The small print.
x = text(6, 78, "2026 TECH", FONT3, BLUE)
x = text(x + 2, 78, ".", FONT3, ORANGE)
x = text(x + 2, 78, "2006 HARDWARE", FONT3, WHITE)
x = text(x + 2, 78, ".", FONT3, ORANGE)
text(x + 2, 78, "1980S GAMES", FONT3, GREEN)


def png(scale):
    raw = bytearray()
    for row in canvas:
        line = b"\0" + b"".join(bytes(p) * scale for p in row)
        raw += line * scale

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", W * scale, H * scale, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) +
            chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    sys.stdout.buffer.write(png(int(sys.argv[1]) if len(sys.argv) > 1 else 4))
