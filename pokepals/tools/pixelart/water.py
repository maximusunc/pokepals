"""
Pixel-art water generator -- the same hand-crafted world language as trees.py and
the character/daemon generators, so ponds, the river and the sunken pools read as
part of one deliberate pixel world instead of the engine's flat filled circles.

Shared conventions (see trees.py / generator.py):
  * shade ROLES, not colors -- '1' dark trough, '2' base surface, '3' bright glint --
    so recoloring water is just picking a different ramp;
  * light from the upper-left -- the brightest glints sit up/left of each ripple crest;
  * a small, deliberate palette per body of water (pond / river / pool).

Where a tree is a SILHOUETTE (a shape cut out of the sky), water is a SURFACE: an
endless sheet the world tiles across a pond or a river of any size. So the unit here
is not a whole sprite but a single SEAMLESS TILE -- a square that repeats edge-to-edge
with no visible seam. The client lays that one tile across each body of water (clipped
to the pond's circle or the river's rectangle) and scrolls it a texel at a time to make
the surface drift. One tile, tiled and scrolled, is the whole animation -- no per-frame
sheets to keep in sync.

The ripples are DERIVED, not hand-placed (a 32px sheet of water hand-shaded pixel by
pixel wouldn't tile): a couple of gently undulating horizontal wave bands, summed at
INTEGER frequencies so the pattern is exactly periodic across the tile and the seam
disappears. Crests catch the light (role 3), troughs fall into shadow (role 1), the
rest is the calm base (role 2). Reshape the water by editing the wave numbers; recolor
it (or add a new kind of water) by adding a ramp. No randomness -- every tile is
reproducible from the numbers below.
"""

import math

from PIL import Image

# The tile is square and small so it reads as chunky pixel water once the client scales
# it up in the world. 32 keeps it in the same size family as the character/daemon frames.
TILE = 32

# Unit-ish direction the light comes FROM, up-left -- kept in step with trees.py / the
# art.json light dir, so a glint on the water is lit from the same side as everything else.
LIGHT = (-0.55, -0.83)

# ------------------------------------------------------------------- palettes
# (dark, base, light) per body of water. "pond" is tuned to data/art.json's palette
# `water` so a baked pond drops straight into the Vale; "river" is a touch brighter and
# cooler (open sky on moving water); "pool" is the cold, near-black still water of the
# Ruin's sunken groves, with only a faint glint.
RAMPS = {
    "pond":  ((0.20, 0.36, 0.48), (0.31, 0.49, 0.59), (0.55, 0.73, 0.79)),
    "river": ((0.23, 0.41, 0.53), (0.35, 0.53, 0.63), (0.64, 0.80, 0.84)),
    "pool":  ((0.07, 0.11, 0.15), (0.14, 0.21, 0.26), (0.34, 0.46, 0.50)),
}

# --------------------------------------------------------------------- wave field
# Each wave is a horizontal band that undulates as it crosses the tile:
#   crest(x, y) = cos( 2pi*(fy*y)/TILE + amp * sin(2pi*(fx*x)/TILE + phase) )
# INTEGER fx/fy are what make it seamless -- the band completes a whole number of cycles
# across the tile in both axes, so the left edge meets the right (and top meets bottom)
# with no seam. Two bands at different frequencies cross into the dappled, glittering
# surface pixel water is known for. Edit these to make the water busier or calmer.
WAVES = [
    {"fx": 1, "fy": 2, "amp": 0.9, "phase": 0.0,  "weight": 1.0},
    {"fx": 2, "fy": 3, "amp": 0.6, "phase": 2.1,  "weight": 0.5},
]

# Where the summed crest tips over into a glint (3) or a trough (1); everything between
# is the calm base (2). Higher GLINT = rarer, sharper sparkles.
GLINT = 0.86
TROUGH = -0.58


def _crest(x, y):
    """Summed wave height at a texel, in roughly [-1, 1]. Periodic across the tile."""
    total = 0.0
    wsum = 0.0
    for w in WAVES:
        inner = 2 * math.pi * (w["fx"] * x) / TILE + w["phase"]
        band = 2 * math.pi * (w["fy"] * y) / TILE + w["amp"] * math.sin(inner)
        total += w["weight"] * math.cos(band)
        wsum += w["weight"]
    return total / wsum


def _shade_grid():
    """Derive the 1/2/3 shade role for every texel from the wave field.

    A crest is a glint (3); its up/left flank is lit a touch wider so the sparkle has a
    direction (top-left light) instead of reading as a symmetric blob; a deep trough is
    shadow (1); the calm surface is base (2)."""
    grid = [[2] * TILE for _ in range(TILE)]
    for y in range(TILE):
        for x in range(TILE):
            c = _crest(x, y)
            # sample a hair up-left: if the crest is stronger there, this texel sits on
            # the lit flank of a ripple and earns a wider highlight (directional light).
            up_left = _crest((x + LIGHT[0]) % TILE, (y + LIGHT[1]) % TILE)
            if c > GLINT or (c > GLINT - 0.14 and up_left > c):
                grid[y][x] = 3
            elif c < TROUGH:
                grid[y][x] = 1
            else:
                grid[y][x] = 2
    return grid


def make_water_tile(variant="pond"):
    """One seamless, fully-opaque water tile (TILE x TILE) for `variant`.

    Fully opaque because water is a surface the client tiles across a shape, not a
    silhouette with sky around it -- the pond/river outline does the clipping."""
    ramp = RAMPS[variant]
    grid = _shade_grid()
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 255))
    px = img.load()
    for y in range(TILE):
        for x in range(TILE):
            r, g, b = ramp[grid[y][x] - 1]
            px[x, y] = (round(r * 255), round(g * 255), round(b * 255), 255)
    return img


def _tiled(variant, reps, scale):
    """A variant tiled `reps`x`reps` and scaled up -- proof that the seam is invisible."""
    tile = make_water_tile(variant)
    sheet = Image.new("RGBA", (TILE * reps, TILE * reps))
    for j in range(reps):
        for i in range(reps):
            sheet.paste(tile, (i * TILE, j * TILE))
    return sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)


def preview_grid(scale=6):
    """One column per variant, each tiled 2x2 so any seam would jump out. Eyeball it."""
    variants = list(RAMPS)
    reps = 2
    cell = TILE * reps * scale
    pad = 8
    sheet = Image.new("RGBA", (len(variants) * (cell + pad) + pad, cell + 2 * pad),
                      (58, 58, 70, 255))
    for c, variant in enumerate(variants):
        blk = _tiled(variant, reps, scale)
        sheet.paste(blk, (pad + c * (cell + pad), pad))
    return sheet


if __name__ == "__main__":
    preview_grid().save("water.png")
    print("saved water.png")
