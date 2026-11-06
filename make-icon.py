#!/usr/bin/env python3
"""Draw Nudge's app icon into icon.png. Stdlib only.

A white bell on macOS's rounded-square icon plate (824 of 1024 px),
rasterized from signed distance functions and written as an RGBA PNG.
Rerun after changing the shape or colour; build.sh turns it into an .icns.
"""

import math
import os
import struct
import zlib

SIZE = 1024
PLATE = (236, 132, 36)
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


def trapezoid(cy, hh, top_hw, bottom_hw):
    """Approximate: a box whose half-width widens linearly downward."""
    def d(x, y):
        t = max(0.0, min(1.0, (y - (cy - hh)) / (2 * hh)))
        hw = top_hw + (bottom_hw - top_hw) * t
        return max(abs(x) - hw, abs(y - cy) - hh)
    return d


def union(*fs):
    return lambda x, y: min(f(x, y) for f in fs)


BELL = union(
    circle(0, -0.16, 0.3),                 # crown
    trapezoid(0.08, 0.24, 0.3, 0.4),       # flaring body
    rounded_rect(0, 0.33, 0.5, 0.06, 0.06),  # lip
    circle(0, 0.46, 0.11),                 # clapper
    circle(0, -0.5, 0.07),                 # loop
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
            c = cover(BELL(x, y), px)
            r, g, b = (p + (w - p) * c for p, w in zip(PLATE, WHITE))
            k = (j * size + i) * 4
            out[k:k + 4] = bytes((round(r), round(g), round(b), round(a * 255)))
    return out


if __name__ == "__main__":
    png(os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon.png"), SIZE, SIZE, render())
