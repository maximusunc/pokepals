"""
Stillglass -- the mirror lake -- pixel art: silver-green shore trees (willows, birches, round poplars), the
pale ground the shore is made of and the quiet litter on it, a flat silver water tile, a few weathered
props, and the PHANTOM trees whose reflections are the lake's one wrong thing (tall silver pines and a
great oak with nothing on the shore to cast them: only their upside-down images are ever drawn, so they
are baked here as ordinary trees and shown by the reflection layer alone).

Built on the machinery the other worlds already have:
  * trees   -- trees.make_grove_parts with new cool, pale foliage/bark ramps (so the shapes are the grove's);
  * ground  -- a seamless terrain atlas in ground.py's layout (R = shade role, G = accent), here a soft
               short turf with the faintest grain, plus a detail atlas of quiet shore litter;
  * water   -- one new ramp and a calmer wave field than water.py's: a lake that is almost featureless,
               because the sky is meant to match it;
  * props   -- small procedural sprites on nocthollow.py's Canvas (BASE + optional grayscale TINT).

Deterministic (seeded by name): re-running reproduces the PNGs byte for byte. Baked by tools/gen_stillglass.py.
"""

import math
import random

from PIL import Image

import ground
import nocthollow as noc
import trees
import water
from nocthollow import Canvas, lit, mix  # noqa: F401

# ------------------------------------------------------------------ palettes (0..255 for trees)
trees.FOLIAGE.update({
    # shore trees: grey-green leaves, silvered on the lit side, like willows seen through haze
    "mist_willow": ((62, 88, 82), (112, 142, 130), (190, 212, 200)),
    "mist_birch":  ((84, 112, 100), (140, 170, 152), (208, 226, 214)),
    "mist_round":  ((56, 82, 80), (100, 132, 124), (170, 198, 188)),
    "mist_oak":    ((50, 74, 72), (92, 122, 114), (156, 184, 174)),
    # the phantoms: moonlit silver with a cold blue shadow: just a little too pale to be real
    "phantom":     ((72, 92, 128), (150, 172, 204), (226, 238, 252)),
    "phantom_pine": ((58, 78, 116), (128, 152, 190), (214, 228, 246)),
})
trees.BARK.update({
    "mist":   ((72, 70, 66), (118, 114, 106), (168, 164, 154)),
    "silver": ((96, 100, 108), (176, 182, 190), (228, 232, 238)),
    "phantom": ((60, 66, 92), (104, 114, 148), (166, 178, 206)),
})

GROVE = {
    "willow_a": ("willow", 1, "mist_willow", "mist", None),
    "willow_b": ("willow", 2, "mist_willow", "mist", None),
    "birch_a":  ("birch", 1, "mist_birch", "silver", None),
    "birch_b":  ("birch", 2, "mist_birch", "silver", None),
    "birch_c":  ("birch", 3, "mist_birch", "silver", None),
    "round_a":  ("round", 1, "mist_round", "mist", None),
    "round_b":  ("round", 2, "mist_round", "mist", None),
    "oak_a":    ("oak", 1, "mist_oak", "mist", None),
    "oak_b":    ("oak", 2, "mist_oak", "mist", None),
}
GREAT = {
    "great_willow": ("great_oak", 7, "mist_willow", "mist", None),
    "great_oak":    ("great_oak", 9, "mist_oak", "mist", None),
}
UNDERSTORY = {
    "bush_a": ("bush", 1, "mist_round", "mist", None),
    "bush_b": ("bush", 2, "mist_birch", "mist", None),
    "stump":  ("stump", 1, "mist_willow", "silver", None),
}
# The wrong trees (nothing on the shore casts them). Tall pines among broadleaf shores, a too-pale willow,
# and one great oak: all drawn only as reflections.
PHANTOMS = {
    "pine_a":  ("pine", 1, "phantom_pine", "phantom", None),
    "pine_b":  ("pine", 2, "phantom_pine", "phantom", None),
    "pine_c":  ("pine", 3, "phantom_pine", "phantom", None),
    "willow":  ("willow", 3, "phantom", "phantom", None),
    "birch":   ("birch", 4, "phantom", "phantom", None),
    "great":   ("great_oak", 5, "phantom", "phantom", None),
}


def tree_parts(spec):
    return trees.make_grove_parts(*spec)


# ------------------------------------------------------------------ the ground
TILE = ground.TILE
KINDS = ground.KINDS    # grass, lush, meadow, dirt, sand: re-grown as the shore's moods


def _terrain(kind):
    """(shade_grid, accent_grid) for one mood of the shore: a short, pale turf with the faintest grain: a
    few dimples, the odd bright blade-tip, no tufts. Like ground.make_terrain only FINE detail is baked in;
    the broad swells of light and dark are painted by the shader from world-space noise."""
    rng = random.Random("stillglass-ground-" + kind)
    g = [[2] * TILE for _ in range(TILE)]
    acc = [[0] * TILE for _ in range(TILE)]
    # (dimples, blades, flecks): turf is soft and even; the lush mood is a little denser; the meadow is
    # bright with blade tips; the dirt is the packed bank (speckled); the sand is the pale shingle.
    mix_by_kind = {
        "grass":  (70, 40, 20),
        "lush":   (90, 70, 14),
        "meadow": (60, 90, 24),
        "dirt":   (210, 0, 40),
        "sand":   (40, 0, 90),
    }
    n_dim, n_blade, n_fleck = mix_by_kind[kind]
    base = 1 if kind == "dirt" else 2
    for y in range(TILE):
        for x in range(TILE):
            g[y][x] = base
    for _ in range(n_dim):
        ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_dim // 3):
        ground._stamp(g, [(0, 0, 1), (1, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_blade):
        ground._stamp(g, [(0, 0, 3), (0, 1, 2)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_fleck):
        ground._stamp(g, [(0, 0, 3)], rng.randrange(TILE), rng.randrange(TILE))
    return g, acc


def terrain_atlas():
    img = Image.new("RGBA", (TILE * len(KINDS), TILE), (0, 0, 0, 255))
    px = img.load()
    for k, kind in enumerate(KINDS):
        g, acc = _terrain(kind)
        for y in range(TILE):
            for x in range(TILE):
                px[k * TILE + x, y] = (g[y][x] * 85, 255 if acc[y][x] else 0, 0, 255)
    return img


# Fine litter: ASCII maps in ground.py's format ('1' dark, '2' base, '3' light, '.' clear). (ramp, outlined, rows)
SEDGE = ((74, 98, 84), (122, 150, 128), (184, 208, 184))
PEBBLE = ((96, 100, 108), (146, 152, 160), (206, 212, 220))
SHELL = ((150, 140, 130), (206, 198, 188), (244, 240, 232))
MOONWORT = ((150, 160, 190), (214, 222, 240), (255, 255, 255))
FEATHER = ((130, 140, 156), (190, 198, 212), (240, 244, 250))
DRIFT = ((88, 82, 76), (138, 130, 120), (192, 184, 172))
REEDS = ((76, 100, 92), (126, 154, 140), (190, 212, 198))
CLOVER = ((70, 104, 84), (112, 150, 118), (170, 200, 160))

DETAILS = {
    "sedge_a": (SEDGE, False, [
        "..3...",
        ".32.3.",
        ".2.32.",
        "12.21.",
        "1211..",
    ]),
    "sedge_b": (SEDGE, False, [
        ".3..3..",
        ".2.32..",
        "32.2.3.",
        "2.12.2.",
        "21121..",
    ]),
    "clover": (CLOVER, False, [
        ".3.3.",
        "32323",
        ".222.",
        "..1..",
    ]),
    "pebbles": (PEBBLE, False, [
        ".33..3",
        ".21.31",
        "......",
        "..32..",
        "..21..",
    ]),
    "flatstone": (PEBBLE, True, [
        ".3332..",
        "332222.",
        "3222221",
        ".22111.",
    ]),
    "shell": (SHELL, False, [
        ".33.",
        "3222",
        ".211",
    ]),
    "moonwort": (MOONWORT, False, [
        "..3..",
        ".323.",
        "..2..",
        "..1..",
    ]),
    "feather": (FEATHER, False, [
        "...33",
        "..32.",
        ".32..",
        "32...",
        "1....",
    ]),
    "twig": (DRIFT, False, [
        "3.3....",
        ".23..3.",
        "..2232.",
        "....21.",
    ]),
    # a pale reed, for the shore of the lake
    "silverreed": (REEDS, False, [
        "..3.",
        ".32.",
        ".2..",
        ".2..",
        "32..",
        "2...",
        "2.3.",
        "21..",
        "21..",
        "21..",
    ]),
}


def _detail(name):
    ramp, outlined, rows = DETAILS[name]
    h, w = len(rows), max(len(r) for r in rows)
    pad = 1 if outlined else 0
    img = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    px = img.load()
    solid = set()
    for y, row in enumerate(rows):
        assert len(row) == w, "%s row %d is %d cols, wanted %d" % (name, y, len(row), w)
        for x, ch in enumerate(row):
            if ch == '.':
                continue
            px[x + pad, y + pad] = tuple(ramp[int(ch) - 1]) + (255,)
            solid.add((x + pad, y + pad))
    if outlined:
        for (x, y) in list(solid):
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + dx, y + dy)
                if n not in solid and 0 <= n[0] < img.width and 0 <= n[1] < img.height:
                    px[n] = ground.OUTLINE
    return img


def detail_atlas():
    """(image, index) with index {name: [x, y, w, h]}, the shape data/ground_details.json uses."""
    imgs = {n: _detail(n) for n in DETAILS}
    width = sum(i.width + 1 for i in imgs.values())
    height = max(i.height for i in imgs.values())
    atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    index, x = {}, 0
    for n, im in imgs.items():
        atlas.paste(im, (x, 0), im)
        index[n] = [x, 0, im.width, im.height]
        x += im.width + 1
    return atlas, index


# ------------------------------------------------------------------ water
# The lake: pale silver-grey, nearly featureless, with a few long thin gleams. The sky is meant to match it.
SILVER = ((0.66, 0.73, 0.79), (0.70, 0.77, 0.82), (0.77, 0.84, 0.89))
water.RAMPS["silver"] = SILVER


def silver_tile():
    """One seamless, opaque, almost flat tile: base silver, a couple of long faint gleams (role 3) with a
    fainter shadow just below them (role 1), all periodic across the tile so there is no seam."""
    T = water.TILE
    grid = [[2] * T for _ in range(T)]
    for (row, x0, run) in [(6, 3, 9), (21, 17, 7)]:
        for k in range(run):
            x = (x0 + k) % T
            grid[row][x] = 3
    img = Image.new("RGBA", (T, T), (0, 0, 0, 255))
    px = img.load()
    for y in range(T):
        for x in range(T):
            r, g, b = SILVER[grid[y][x] - 1]
            px[x, y] = (round(r * 255), round(g * 255), round(b * 255), 255)
    return img


# ------------------------------------------------------------------ props
STONE = ((0.34, 0.37, 0.42), (0.55, 0.59, 0.65), (0.80, 0.84, 0.90))
STONE_PALE = ((0.50, 0.54, 0.60), (0.70, 0.74, 0.80), (0.92, 0.95, 0.98))
WOOD = ((0.30, 0.28, 0.26), (0.48, 0.45, 0.41), (0.70, 0.67, 0.62))
REEDC = ((0.30, 0.40, 0.36), (0.48, 0.60, 0.52), (0.72, 0.82, 0.72))
ROPE = ((0.46, 0.42, 0.34), (0.64, 0.58, 0.46), (0.82, 0.76, 0.62))
SCRATCH = (0.26, 0.28, 0.34)


def _p_boulder(c):
    gy = c.h - 2
    pts = [(2, gy), (1, 9), (4, 4), (10, 2), (16, 4), (19, 9), (18, gy)]
    c.poly(pts, lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy * 0.7, 9)))
    c.ellipse(10, gy, 10, 2, lambda x, y, dx, dy: c.put(x, y, STONE[0]) if y >= gy else None)


def _p_flat_stone(c):
    gy = c.h - 2
    c.ellipse(11, gy - 1, 10, 3.6, lambda x, y, dx, dy: c.put(x, y, lit(STONE_PALE, dx, dy * 1.5, 8)))


def _p_cairn(c):
    gy = c.h - 2
    for cx, cy, rx, ry in [(8, gy - 3, 7.2, 3.4), (8, gy - 8, 5.4, 2.8), (8, gy - 12, 3.4, 2.4)]:
        c.ellipse(cx, cy, rx, ry, lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy, rx)))


def _p_driftlog(c):
    gy = c.h - 2
    c.ellipse(15, gy - 2, 14, 3.4, lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx * 0.6, dy * 1.6, 7)))
    c.ellipse(3, gy - 2, 2.4, 3.2, lambda x, y, dx, dy: c.put(x, y, WOOD[2] if dx < 0 else WOOD[0]))
    c.line((9, gy - 4), (12, gy - 6), lambda x, y, dx, dy: c.put(x, y, WOOD[1]))


def _p_reedclump(c):
    gy = c.h - 2
    for x0, h, lean in [(4, 14, -1), (8, 18, 0), (12, 15, 1), (16, 12, 1), (6, 10, -1), (14, 9, 0)]:
        for k in range(h):
            x = x0 + (lean * k) // 5
            ramp = REEDC[2] if k > h - 4 else (REEDC[1] if (x0 + k) % 3 else REEDC[0])
            c.put(x, gy - k, ramp)


def _p_mooring_post(c):
    gy = c.h - 2
    c.poly([(3, gy), (3, 4), (5, 2), (8, 2), (10, 4), (10, gy)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx, dy * 0.5, 6)))
    for x in range(3, 11):
        c.put(x, 7, ROPE[1])
        c.put(x, 8, ROPE[0] if x % 2 else ROPE[2])


def _p_sign_stone(c):
    """The scratched stone by the landing: a tall thin slab with a few lines cut into its face, as if
    someone had once tried to write down what the lake does."""
    gy = c.h - 2
    c.poly([(2, gy), (2, 6), (4, 2), (9, 1), (12, 4), (12, gy)], lambda x, y, dx, dy: c.put(x, y, lit(STONE_PALE, dx * 0.8, dy * 0.5, 9)))
    for (x0, x1, y) in [(4, 9, 6), (4, 10, 9), (4, 8, 12), (5, 10, 15)]:
        for x in range(x0, x1 + 1):
            c.put(x, y, SCRATCH, solid=False)
    c.ellipse(7, gy, 7, 1.6, lambda x, y, dx, dy: c.put(x, y, STONE_PALE[0]) if y >= gy else None)


PROP_BUILDERS = {
    "sg_boulder": ((21, 17), _p_boulder),
    "sg_flat_stone": ((22, 10), _p_flat_stone),
    "sg_cairn": ((16, 24), _p_cairn),
    "sg_driftlog": ((30, 12), _p_driftlog),
    "sg_reedclump": ((22, 22), _p_reedclump),
    "sg_post": ((14, 18), _p_mooring_post),
    "sg_sign_stone": ((15, 26), _p_sign_stone),
}


def make_prop(name):
    """(base, tint_or_None) for a Stillglass prop. None has a tint layer: their colours are fixed."""
    (w, h), fn = PROP_BUILDERS[name]
    c = Canvas(w, h)
    fn(c)
    c.outline()
    return c.img, (c.tint if c.has_tint else None)


# ------------------------------------------------------------------ preview
def preview(path, scale=3):
    """A contact sheet: every tree, the phantoms, understory, props, the water tile and the litter."""
    bg = (176, 188, 196, 255)
    items = []
    for spec in list(GROVE.values()) + list(GREAT.values()) + list(UNDERSTORY.values()) + list(PHANTOMS.values()):
        t, cnp = tree_parts(spec)
        im = cnp.copy() if t is None else t.copy()
        if t is not None:
            im.alpha_composite(cnp)
        items.append(im)
    for name in PROP_BUILDERS:
        items.append(make_prop(name)[0])
    atlas, _ = detail_atlas()
    items.append(atlas)
    items.append(silver_tile())
    pad = 8
    rows, row, rw = [], [], pad
    for im in items:
        if rw + im.width + pad > 900:
            rows.append(row)
            row, rw = [], pad
        row.append(im)
        rw += im.width + pad
    rows.append(row)
    H = sum(max(i.height for i in r) + pad for r in rows) + pad
    sheet = Image.new("RGBA", (900, H), bg)
    y = pad
    for r in rows:
        x = pad
        for im in r:
            sheet.alpha_composite(im, (x, y + max(i.height for i in r) - im.height))
            x += im.width + pad
        y += max(i.height for i in r) + pad
    sheet = sheet.resize((sheet.width * scale // 1, sheet.height * scale // 1), Image.NEAREST)
    sheet.save(path)
    print("wrote preview", path)
