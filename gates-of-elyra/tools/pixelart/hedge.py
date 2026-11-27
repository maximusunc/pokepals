"""
Pixel-art hedge generator -- the maze's tall green walls, as a SEAMLESS leafy tile the
client lays along each hedge run (the maze is a grid, so every run is an axis-aligned
rectangle). Same idea as water.py: one tile, tiled across a wall of any length; here it's
a dappled foliage surface instead of rippling water.

Shared conventions (trees.py / water.py):
  * shade ROLES, not colours -- '1' dark leaf, '2' base, '3' sun-caught highlight;
  * the tile is baked in the hedge's LIT (top) greens, and the client draws the top surface
    with it as-is and the shaded FRONT face with modulate darkened -- one tile, both faces;
  * fully opaque (a hedge is a solid wall, not a silhouette -- the wall rect does the shaping).

Where water is directional ripples, foliage is blobby, so the field here is a sum of a few
higher-frequency sine products at INTEGER frequencies (so the tile repeats with no seam),
thresholded into leaf clumps and ordered-dithered so the clumps read as chunky pixel leaves.
No randomness -- reproducible from the numbers below.
"""

import math

from PIL import Image

TILE = 32

# (dark, base, light) tuned to WorldArt's hedge greens (front/top/highlight family), but a
# touch brighter overall because this is the LIT top tile; the client darkens it for the face.
RAMP = ((0.18, 0.34, 0.18), (0.28, 0.48, 0.26), (0.44, 0.63, 0.36))

# Leaf-clump field: sine products at integer frequencies tile seamlessly; the mix of a few
# gives an irregular, dappled foliage rather than stripes. Edit for bushier/sparser leaves.
CLUMPS = [
    {"fx": 3, "fy": 2, "phase": 0.0, "weight": 1.0},
    {"fx": 2, "fy": 3, "phase": 1.7, "weight": 0.8},
    {"fx": 5, "fy": 4, "phase": 3.1, "weight": 0.5},
]

# 4x4 Bayer matrix (normalised) for the ordered dither between leaf shades.
_BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
BAYER = [[v / 16.0 for v in row] for row in _BAYER]

HIGHLIGHT = 0.34   # above this the leaf catches the sun ('3')
SHADOW = -0.36     # below this it falls into the dark ('1')


def _field(x, y):
    total, wsum = 0.0, 0.0
    for c in CLUMPS:
        a = 2 * math.pi * c["fx"] * x / TILE + c["phase"]
        b = 2 * math.pi * c["fy"] * y / TILE
        total += c["weight"] * math.cos(a) * math.cos(b)
        wsum += c["weight"]
    return total / wsum


def make_hedge_tile():
    """One seamless, fully-opaque leafy hedge tile (TILE x TILE), in the lit-top greens."""
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 255))
    px = img.load()
    step = 1.0 / 2.0  # dither spread across the three shades
    for y in range(TILE):
        for x in range(TILE):
            v = _field(x, y) + (BAYER[y % 4][x % 4] - 0.5) * step
            role = 2 if v > HIGHLIGHT else (0 if v < SHADOW else 1)
            r, g, b = RAMP[role]
            px[x, y] = (round(r * 255), round(g * 255), round(b * 255), 255)
    return img


def _tiled(reps, scale):
    tile = make_hedge_tile()
    sheet = Image.new("RGBA", (TILE * reps, TILE * reps))
    for j in range(reps):
        for i in range(reps):
            sheet.paste(tile, (i * TILE, j * TILE))
    return sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)


def preview_grid(scale=6):
    """The lit tile tiled 2x2, plus a darkened copy (the front-face look), to eyeball the seam."""
    pad = 8
    blk = _tiled(2, scale)
    face = blk.copy()
    fp = face.load()
    for y in range(face.height):
        for x in range(face.width):
            r, g, b, a = fp[x, y]
            fp[x, y] = (int(r * 0.62), int(g * 0.62), int(b * 0.62), a)
    sheet = Image.new("RGBA", (blk.width + face.width + 3 * pad, blk.height + 2 * pad), (110, 148, 92, 255))
    sheet.alpha_composite(blk, (pad, pad))
    sheet.alpha_composite(face, (blk.width + 2 * pad, pad))
    return sheet


if __name__ == "__main__":
    preview_grid().save("hedge.png")
    print("saved hedge.png")
