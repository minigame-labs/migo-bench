#!/usr/bin/env python3
"""Read a raw `screencap` (no -p) on stdin; exit 0 if the game area shows more
than one colour, 1 if it is a single flat colour. Either way it prints the
colour count and the flat colour's hex, so a caller can tell a flat screen that
changes (content that paints one colour on purpose, like multicanvas) from one
that does not.

A flat screen after the settle is a runtime that is not drawing the game: on
the C host with no image decoder, Phaser's boot threw and the screen stayed
black while its frame loop kept logging fps=60 -- which is exactly the fps
source EMUI falls back to. Every bench game draws more than one colour once it
is running, or changes it over time.

The raw format is a little-endian header (width, height, format and, from
Android 12, a colour space) followed by 4-byte RGBA pixels; the header length
is whatever precedes width*height*4 bytes. The top 8% (status bar) and bottom
4% (navigation) are skipped; a 32x32 grid is sampled from the rest.
"""
import struct
import sys

data = sys.stdin.buffer.read()
if len(data) < 12:
    sys.exit("screen_renders: no screenshot")
width, height = struct.unpack_from("<II", data, 0)
header = len(data) - width * height * 4
if header not in (12, 16):
    sys.exit(f"screen_renders: unexpected raw screencap ({width}x{height}, {len(data)} bytes)")

top, bottom = int(height * 0.08), int(height * 0.96)
colours = set()
for gy in range(32):
    y = top + (bottom - top - 1) * gy // 31
    row = header + y * width * 4
    for gx in range(32):
        x = (width - 1) * gx // 31
        colours.add(data[row + x * 4: row + x * 4 + 3])
flat = next(iter(colours)).hex() if len(colours) == 1 else "-"
print(f"screen_colours={len(colours)} screen_flat={flat}")
sys.exit(0 if len(colours) > 1 else 1)
