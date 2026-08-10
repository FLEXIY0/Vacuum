#!/usr/bin/env python3
"""Generate the Vacuum wallpaper as a PNG, with no third-party libraries.

The image is a near-black field with one off-centre accent glow and a soft
vignette -- the "dark minimalism" look, and it compresses to a few tens of
kilobytes because the gradient is smooth.

    ./mk/gen-wallpaper.py rootfs/usr/share/vacuum/wallpaper.png [W H]
"""

import math
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


def chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def render(width, height):
    """Return the raw scanlines (filter byte + RGB triples) for the image."""
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

            for base, acc in zip(BG, ACCENT):
                c = (base + (acc - base) * g) * shade
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
