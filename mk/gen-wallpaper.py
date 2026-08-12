#!/usr/bin/env python3
"""Generate the Vacuum wallpaper as a PNG, with no third-party libraries.

A near-black field with one off-centre accent glow and a soft vignette,
with the Vacuum mark set in the middle as a field of dots.

The mark is not drawn twice. It is read out of logo.txt -- the same file
the shell greeting prints -- by decoding the Braille cells back into the
dot grid they already are: each cell is two dots wide and four tall, and
the codepoint's low eight bits say which of them are lit. So the wallpaper
and the terminal cannot drift apart, because there is only one drawing.

    ./mk/gen-wallpaper.py rootfs/usr/share/vacuum/wallpaper.png [W H]
"""

import math
import os
import struct
import sys
import zlib

BG = (0x0B, 0x0C, 0x0E)
ACCENT = (0x5F, 0xB8, 0xC7)

# Where the glow sits, as a fraction of the canvas, and how far it reaches.
GLOW_X, GLOW_Y = 0.36, 0.42
GLOW_RADIUS = 0.62
GLOW_STRENGTH = 0.30
VIGNETTE = 0.55

# The mark: how wide it sits on the canvas, and how big each dot is
# relative to the spacing between them.
LOGO = os.path.join(os.path.dirname(__file__), "..", "rootfs", "usr", "share",
                    "vacuum", "logo.txt")
MARK_WIDTH = 0.26
MARK_Y = 0.46
DOT_RADIUS = 0.30
DOT_COLOR = (0x7F, 0xD4, 0xE2)


def braille_dots(path):
    """Return (dots, width, height) as a set of lit (x, y) grid positions.

    Braille cells number their dots down the left column then down the
    right, with the last two out of order for historical reasons -- hence
    the explicit table rather than arithmetic.
    """
    bit_xy = {0: (0, 0), 1: (0, 1), 2: (0, 2), 3: (1, 0),
              4: (1, 1), 5: (1, 2), 6: (0, 3), 7: (1, 3)}
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            run = ""
            best = ""
            for ch in line:
                if "\u2800" <= ch <= "\u28ff":
                    run += ch
                else:
                    best, run = (run if len(run) > len(best) else best), ""
            best = run if len(run) > len(best) else best
            if best:
                rows.append(best)
    if not rows:
        return set(), 0, 0

    width = max(len(r) for r in rows)
    dots = set()
    for cell_y, row in enumerate(rows):
        for cell_x, ch in enumerate(row):
            bits = ord(ch) - 0x2800
            for bit, (dx, dy) in bit_xy.items():
                if bits & (1 << bit):
                    dots.add((cell_x * 2 + dx, cell_y * 4 + dy))
    return dots, width * 2, len(rows) * 4


def chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def render(width, height):
    """Return the raw scanlines (filter byte + RGB triples) for the image."""
    dots, dw, dh = braille_dots(LOGO)
    # Grid spacing chosen so the mark occupies MARK_WIDTH of the canvas.
    step = (MARK_WIDTH * width / dw) if dw else 0.0
    dot_r = DOT_RADIUS * step
    mark_x = (width - dw * step) / 2.0
    mark_y = MARK_Y * height - dh * step / 2.0
    # Only test pixels that could possibly be inside a dot.
    reach = dot_r * 2.2

    cx, cy = GLOW_X * width, GLOW_Y * height
    # Normalise distances against the half-diagonal so the look is
    # resolution-independent.
    scale = math.hypot(width, height) / 2.0
    glow_r = GLOW_RADIUS * scale
    vign_r = 0.75 * scale

    rows = bytearray()
    for y in range(height):
        rows.append(0)  # PNG filter type 0 (None)
        row = bytearray()
        dy = y - cy
        vy = y - height / 2.0
        for x in range(width):
            d = math.hypot(x - cx, dy) / glow_r
            # smoothstep falloff, squared for a softer core
            g = 0.0 if d >= 1.0 else (1.0 - d) ** 2 * GLOW_STRENGTH

            v = math.hypot(x - width / 2.0, vy) / vign_r
            shade = 1.0 - VIGNETTE * min(1.0, v) ** 2

            px = [(base + (acc - base) * g) * shade
                  for base, acc in zip(BG, ACCENT)]

            # The mark, drawn over the field. Coverage falls off across one
            # pixel at the rim so the dots are not visibly stair-stepped at
            # this size -- there is no anti-aliasing to inherit here.
            if step:
                gx = (x - mark_x) / step
                gy = (y - mark_y) / step
                best = 0.0
                for ddx in (-1, 0, 1):
                    for ddy in (-1, 0, 1):
                        key = (int(gx) + ddx, int(gy) + ddy)
                        if key not in dots:
                            continue
                        d = math.hypot((gx - key[0] - 0.5) * step,
                                       (gy - key[1] - 0.5) * step)
                        if d <= reach:
                            a = min(1.0, max(0.0, (dot_r - d) + 0.5))
                            best = max(best, a)
                if best > 0.0:
                    px = [p + (t - p) * best for p, t in zip(px, DOT_COLOR)]

            for c in px:
                row.append(max(0, min(255, int(c + 0.5))))
        rows += row
    return bytes(rows)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = sys.argv[1]
    width = int(sys.argv[2]) if len(sys.argv) > 2 else 1920
    height = int(sys.argv[3]) if len(sys.argv) > 3 else 1080

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(render(width, height), 9))
        + chunk(b"IEND", b"")
    )
    with open(out, "wb") as fh:
        fh.write(png)
    print(f"{out}: {width}x{height}, {len(png) / 1024:.1f} KiB")


if __name__ == "__main__":
    main()
