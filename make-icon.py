#!/usr/bin/env python3
"""Draw Nudge's app icon into icon.png. Stdlib only.

A bold white lowercase n on macOS's rounded-square icon plate (824 of
1024 px), shaded with a "sunset" diagonal gradient, orange at the top left
to pink at the bottom right. Rasterized from signed distance functions and
written as an RGBA PNG. The strokes are heavy so the n still reads as the
small badge macOS puts on avatar notifications. Rerun after changing the
shape or colour; build.sh turns it into an .icns.
"""

import math
import os
import struct
import zlib

SIZE = 1024
SUNSET = ((255, 170, 60), (235, 60, 130))  # top-left, bottom-right
WHITE = (255, 255, 255)


def png(path, w, h, rgba):
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))
    raw = b"".join(b"\x00" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


# Shapes work in unit coordinates: the canvas spans [-1, 1], y down.

def circle(cx, cy, r):
    return lambda x, y: math.hypot(x - cx, y - cy) - r


def rounded_rect(cx, cy, hw, hh, r):
    def d(x, y):
        qx, qy = abs(x - cx) - hw + r, abs(y - cy) - hh + r
        return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
    return d


def capsule(ax, ay, bx, by, r):
    """A segment from a to b thickened to radius r (round ends)."""
    def d(x, y):
        px, py, vx, vy = x - ax, y - ay, bx - ax, by - ay
        h = max(0.0, min(1.0, (px * vx + py * vy) / (vx * vx + vy * vy)))
        return math.hypot(px - vx * h, py - vy * h) - r
    return d


def upper_arc(cx, cy, R, r):
    """The top half of a ring of radius R, thickened to r, round ends."""
    def d(x, y):
        if y <= cy:
            return abs(math.hypot(x - cx, y - cy) - R) - r
        return min(math.hypot(x - cx + R, y - cy), math.hypot(x - cx - R, y - cy)) - r
    return d


def union(*fs):
    return lambda x, y: min(f(x, y) for f in fs)


# The n: a left stem that rises a little above the arch, the arch, and a
# right stem, all strokes 0.34 wide. DY centres it: the arch top and the
# stem bottoms both sit 0.52 from the middle.
W, R, DY = 0.17, 0.3, -0.05
N = union(
    capsule(-R, -0.27 + DY, -R, 0.4 + DY, W),
    upper_arc(0, DY, R, W),
    capsule(R, DY, R, 0.4 + DY, W),
)
PLATE_SDF = rounded_rect(0, 0, 0.805, 0.805, 0.36)


def cover(d, px):
    return max(0.0, min(1.0, 0.5 - d / px))


def render(size=SIZE):
    px = 2.0 / size
    out = bytearray(size * size * 4)
    for j in range(size):
        y = (j + 0.5) * px - 1
        for i in range(size):
            x = (i + 0.5) * px - 1
            a = cover(PLATE_SDF(x, y), px)
            if a <= 0:
                continue
            t = max(0.0, min(1.0, (x + y + 1.6) / 3.2))
            plate = [p + (q - p) * t for p, q in zip(*SUNSET)]
            c = cover(N(x, y), px)
            r, g, b = (p + (w - p) * c for p, w in zip(plate, WHITE))
            k = (j * size + i) * 4
            out[k:k + 4] = bytes((round(r), round(g), round(b), round(a * 255)))
    return out


if __name__ == "__main__":
    png(os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon.png"), SIZE, SIZE, render())
