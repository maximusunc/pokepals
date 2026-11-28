"""
Ebbmere -- the tidal flats -- pixel art: the sand the tide goes out over (five moods of it, with ripple
marks), the small litter lying on it (shells, wrack, a starfish, lugworm coils), windswept dune trees, a few
weathered props (a stranded rowboat, driftwood, barnacled rocks, groyne posts, a buoy) and the lighthouse.

The water itself is NOT baked here: the tide covers the flats with a shader that reads the world's baked
seabed (assets/eb_tide.gdshader), so what you see of the sea is drawn live, not painted.

Built on the machinery the other worlds already have:
  * trees   -- trees.make_grove_parts with new weathered foliage/bark ramps (so the shapes are the grove's);
  * ground  -- a seamless terrain atlas in ground.py's layout (R = shade role, G = accent), plus a detail
               atlas of shore litter;
  * props   -- small procedural sprites on nocthollow.py's Canvas (BASE + optional grayscale TINT);
  * the lighthouse -- one tall Canvas drawn as a trunk (the tower) and a canopy (the gallery, lamp room and
               roof), so Scenery can treat it as a landmark you walk behind.

Deterministic (seeded by name): re-running reproduces the PNGs byte for byte. Baked by tools/gen_ebbmere.py.
"""

import math
import random

from PIL import Image

import ground
import nocthollow as noc
import trees
from nocthollow import Canvas, lit, mix  # noqa: F401

# ------------------------------------------------------------------ palettes (0..255 for trees)
trees.FOLIAGE.update({
    # wind-bent dune pines: blue-green, dusty
    "dune_pine": ((40, 68, 66), (66, 100, 94), (118, 150, 136)),
    # sea-buckthorn / thorn scrub: grey-green with a silvery light side
    "thorn":     ((70, 88, 70), (110, 130, 98), (170, 188, 144)),
    # tamarisk: soft sage with feathery light
    "tamarisk":  ((74, 96, 82), (118, 144, 118), (178, 202, 168)),
})
trees.BARK.update({
    "bleached": ((92, 82, 70), (150, 138, 120), (206, 196, 178)),
})

GROVE = {
    "dune_pine_a": ("pine", 11, "dune_pine", "bleached", None),
    "dune_pine_b": ("pine", 12, "dune_pine", "bleached", None),
    "thorn_a":     ("round", 21, "thorn", "bleached", None),
    "thorn_b":     ("round", 22, "thorn", "bleached", None),
    "thorn_c":     ("round", 23, "thorn", "bleached", None),
    "tamarisk_a":  ("willow", 31, "tamarisk", "bleached", "blossom"),
    "tamarisk_b":  ("willow", 32, "tamarisk", "bleached", "blossom"),
}
UNDERSTORY = {
    "bush_a": ("bush", 41, "thorn", "bleached", None),
    "bush_b": ("bush", 42, "tamarisk", "bleached", None),
    "stump":  ("stump", 43, "thorn", "bleached", None),
}


def tree_parts(spec):
    return trees.make_grove_parts(*spec)


# ------------------------------------------------------------------ the ground
TILE = ground.TILE
KINDS = ground.KINDS    # grass, lush, meadow, dirt, sand: re-grown as the sand's moods


def _ripple(g, y0, amp, k, phase, x0, length, rows=(1, 3)):
    """One ripple mark: a wavy dark line with a light lip above it, periodic across the tile (an integer
    number of waves, `k`, per tile width) so it leaves no seam."""
    dark, light = rows
    for i in range(length):
        x = (x0 + i) % TILE
        y = int(round(y0 + amp * math.sin(math.tau * k * x / TILE + phase)))
        g[y % TILE][x] = dark
        g[(y - 1) % TILE][x] = light


def _terrain(kind):
    """(shade_grid, accent_grid) for one mood of the sand. Only FINE detail is baked in; the broad swells of
    light and dark are painted by the shader from world-space noise."""
    rng = random.Random("ebbmere-ground-" + kind)
    g = [[2] * TILE for _ in range(TILE)]
    acc = [[0] * TILE for _ in range(TILE)]
    if kind == "grass":          # dry sand: fine grain and a few short ripple dashes
        for _ in range(120):
            ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(90):
            ground._stamp(g, [(0, 0, 3)], rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(9):
            _ripple(g, rng.randrange(TILE), 1.2, rng.choice([2, 3]), rng.random() * 6.28, rng.randrange(TILE), rng.randint(14, 30))
    elif kind == "lush":         # damp sand: darker grain, longer streaks
        for _ in range(190):
            ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(60):
            ground._stamp(g, [(0, 0, 3)], rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(8):
            _ripple(g, rng.randrange(TILE), 1.6, rng.choice([2, 3, 4]), rng.random() * 6.28, rng.randrange(TILE), rng.randint(28, 60))
    elif kind == "meadow":       # dune grass: straw blades standing in sand
        for _ in range(70):
            ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(130):
            ground._stamp(g, [(0, 0, 3), (0, 1, 2), (0, 2, 1)], rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(60):
            ground._stamp(g, [(0, 0, 3), (1, 1, 2)], rng.randrange(TILE), rng.randrange(TILE))
    elif kind == "dirt":         # wet sand: the sea's long ripple marks, edge to edge
        for _ in range(60):
            ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
        for row in range(0, TILE, 9):
            _ripple(g, row + rng.randint(0, 2), 1.7, rng.choice([2, 3]), rng.random() * 6.28, 0, TILE)
        for _ in range(10):
            ground._stamp(g, [(0, 0, 3), (1, 0, 3)], rng.randrange(TILE), rng.randrange(TILE))
    else:                        # "sand": shell grit, pale and sparkly
        for _ in range(220):
            ground._stamp(g, [(0, 0, 3)], rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(100):
            ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(26):
            ground._stamp(g, [(0, 0, 3), (1, 0, 3), (0, 1, 1)], rng.randrange(TILE), rng.randrange(TILE))
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
SHELL = ((176, 150, 128), (228, 208, 184), (255, 246, 232))
SHELL_PINK = ((176, 120, 120), (232, 178, 170), (255, 226, 214))
WHELK = ((120, 96, 76), (190, 160, 128), (240, 220, 190))
STAR = ((176, 86, 60), (226, 134, 86), (250, 190, 130))
WRACKC = ((54, 60, 36), (86, 96, 52), (130, 142, 80))
PEBBLE = ((96, 98, 100), (150, 152, 154), (210, 210, 206))
DRIFT = ((110, 98, 84), (164, 150, 130), (214, 202, 182))
WORM = ((104, 90, 70), (128, 112, 88), (160, 142, 112))
MARRAM = ((96, 100, 56), (142, 146, 78), (198, 198, 122))
THRIFT = ((176, 86, 120), (230, 140, 170), (255, 205, 220))
FOAMC = ((176, 188, 190), (226, 234, 234), (255, 255, 255))

DETAILS = {
    "cockle": (SHELL, True, [
        ".333.",
        "32322",
        "22212",
        ".211.",
    ]),
    "cockle_pink": (SHELL_PINK, True, [
        ".333.",
        "32322",
        "22212",
        ".211.",
    ]),
    "whelk": (WHELK, True, [
        "..33.",
        ".3222",
        "32212",
        "2221.",
        ".11..",
    ]),
    "razor": (SHELL, True, [
        "3333332",
        "2222211",
    ]),
    "scallop": (SHELL_PINK, True, [
        "..33..",
        ".3232.",
        "323232",
        "222222",
        ".2112.",
    ]),
    "starfish": (STAR, True, [
        "...3...",
        "...2...",
        "3322233",
        ".22322.",
        "..222..",
        ".22.22.",
        ".2...2.",
    ]),
    "wrack": (WRACKC, False, [
        "..3.....",
        ".32.32..",
        "32232.3.",
        "221222.2",
        ".1.11221",
    ]),
    "wrack_small": (WRACKC, False, [
        ".3.3..",
        "3232.3",
        "22122.",
        ".1.1..",
    ]),
    "pebbles": (PEBBLE, False, [
        ".33..3",
        ".21.31",
        "......",
        "..32..",
        "..21..",
    ]),
    "driftchip": (DRIFT, False, [
        "3.33...",
        ".2232.3",
        "..2221.",
        "....11.",
    ]),
    "lugworm": (WORM, False, [
        ".3223.",
        "322122",
        ".2112.",
        "..22..",
    ]),
    "pinholes": (WORM, False, [
        "1....1..",
        "..1.....",
        "....1..1",
        ".1......",
    ]),
    "marram": (MARRAM, False, [
        "..3...3.",
        ".32..32.",
        ".32..32.",
        "3223.322",
        "2222.222",
        ".122.221",
        "..12.21.",
    ]),
    "thrift": (THRIFT, False, [
        ".3.3.",
        "32323",
        ".222.",
        "..1..",
        "..1..",
    ]),
    "foam": (FOAMC, False, [
        ".33.3.",
        "322323",
        ".2.22.",
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


# ------------------------------------------------------------------ props
ROCKC = ((0.30, 0.29, 0.30), (0.50, 0.48, 0.47), (0.76, 0.74, 0.70))
BARNACLE = (0.94, 0.92, 0.86)
WOODC = ((0.42, 0.36, 0.30), (0.64, 0.57, 0.48), (0.86, 0.80, 0.70))
WRACKP = ((0.16, 0.20, 0.09), (0.28, 0.34, 0.15), (0.44, 0.50, 0.25))
SHELLP = ((0.60, 0.52, 0.44), (0.86, 0.80, 0.70), (0.98, 0.95, 0.88))
HULL = ((0.16, 0.26, 0.34), (0.28, 0.44, 0.54), (0.48, 0.64, 0.72))
PLANK = ((0.40, 0.30, 0.22), (0.60, 0.46, 0.34), (0.80, 0.66, 0.50))
RED = ((0.50, 0.14, 0.12), (0.80, 0.24, 0.20), (0.96, 0.52, 0.44))
WHITE = ((0.62, 0.62, 0.60), (0.88, 0.88, 0.84), (1.0, 1.0, 0.98))
GRASS = ((0.36, 0.38, 0.20), (0.56, 0.58, 0.30), (0.78, 0.78, 0.48))
SCRATCH = (0.26, 0.24, 0.22)


def _p_rock(c):
    gy = c.h - 2
    pts = [(2, gy), (1, 10), (4, 4), (10, 2), (16, 4), (19, 10), (18, gy)]
    c.poly(pts, lambda x, y, dx, dy: c.put(x, y, lit(ROCKC, dx, dy * 0.7, 9)))
    for (bx, by) in [(6, 7), (7, 8), (13, 6), (12, 11), (9, 13), (15, 9), (5, 12)]:
        c.put(bx, by, BARNACLE, solid=False)


def _p_rock_big(c):
    gy = c.h - 2
    pts = [(2, gy), (0, 16), (4, 8), (10, 3), (20, 2), (28, 6), (32, 14), (30, gy)]
    c.poly(pts, lambda x, y, dx, dy: c.put(x, y, lit(ROCKC, dx, dy * 0.7, 15)))
    for (bx, by) in [(8, 10), (9, 11), (20, 8), (24, 14), (14, 16), (6, 17), (27, 10), (17, 12)]:
        c.put(bx, by, BARNACLE, solid=False)
    c.line((10, 6), (14, 14), lambda x, y, dx, dy: c.put(x, y, ROCKC[0], solid=False))


def _p_shellheap(c):
    gy = c.h - 2
    c.ellipse(10, gy - 2, 9, 4, lambda x, y, dx, dy: c.put(x, y, lit(SHELLP, dx, dy * 1.4, 8)))
    for (bx, by, col) in [(5, gy - 4, 2), (9, gy - 6, 2), (13, gy - 4, 1), (8, gy - 3, 0), (12, gy - 2, 2), (4, gy - 2, 1), (10, gy - 4, 0)]:
        c.put(bx, by, SHELLP[col], solid=False)
    for (bx, by) in [(7, gy - 5), (11, gy - 5), (6, gy - 3)]:
        c.put(bx, by, (0.82, 0.60, 0.58), solid=False)


def _p_driftwood(c):
    gy = c.h - 2
    c.ellipse(15, gy - 3, 14, 3.4, lambda x, y, dx, dy: c.put(x, y, lit(WOODC, dx * 0.6, dy * 1.6, 7)))
    c.ellipse(2, gy - 3, 2.4, 3.2, lambda x, y, dx, dy: c.put(x, y, WOODC[2] if dx < 0 else WOODC[0]))
    c.line((9, gy - 5), (13, gy - 9), lambda x, y, dx, dy: c.put(x, y, WOODC[1]))
    c.line((20, gy - 5), (23, gy - 10), lambda x, y, dx, dy: c.put(x, y, WOODC[1]))
    c.line((14, gy - 3), (16, gy - 3), lambda x, y, dx, dy: c.put(x, y, WOODC[0], solid=False))


def _p_wrack(c):
    gy = c.h - 2
    c.ellipse(11, gy - 2, 10, 3, lambda x, y, dx, dy: c.put(x, y, lit(WRACKP, dx, dy * 1.5, 8)))
    for (x0, h) in [(4, 6), (7, 8), (11, 7), (15, 5), (9, 4)]:
        for k in range(h):
            c.put(x0 + (k // 3), gy - 3 - k, WRACKP[2] if k % 3 == 0 else WRACKP[1], solid=False)
    c.put(6, gy - 6, (0.62, 0.52, 0.22), solid=False)
    c.put(13, gy - 7, (0.62, 0.52, 0.22), solid=False)


def _p_rowboat(c):
    """A clinker rowboat stranded on its side-keel, half sunk, its blue paint gone to chalk."""
    gy = c.h - 2
    hull = [(1, gy - 8), (4, gy - 2), (12, gy), (26, gy), (34, gy - 3), (38, gy - 10), (30, gy - 8), (10, gy - 8)]
    c.poly(hull, lambda x, y, dx, dy: c.put(x, y, lit(HULL, dx * 0.6, dy * 1.2, 10)))
    # a plank line or two, and the gunwale
    for (x0, x1, y) in [(5, 34, gy - 4), (9, 30, gy - 2)]:
        c.line((x0, y), (x1, y), lambda x, y, dx, dy: c.put(x, y, HULL[0], solid=False))
    c.line((1, gy - 9), (37, gy - 11), lambda x, y, dx, dy: c.put(x, y, PLANK[2]))
    # the inside you can see over the rim, and a thwart
    c.poly([(5, gy - 9), (33, gy - 11), (31, gy - 8), (8, gy - 8)], lambda x, y, dx, dy: c.put(x, y, PLANK[1]))
    c.line((18, gy - 11), (18, gy - 8), lambda x, y, dx, dy: c.put(x, y, PLANK[2]))
    c.ellipse(19, gy, 18, 1.6, lambda x, y, dx, dy: c.put(x, y, WOODC[0]) if y >= gy else None)


def _p_groyne(c):
    """A weathered sea-defence post, barnacled at the foot."""
    gy = c.h - 2
    c.poly([(3, gy), (3, 5), (5, 2), (8, 2), (10, 5), (10, gy)], lambda x, y, dx, dy: c.put(x, y, lit(WOODC, dx, dy * 0.5, 6)))
    for (bx, by) in [(4, gy - 2), (6, gy - 3), (8, gy - 2), (5, gy - 5), (9, gy - 5)]:
        c.put(bx, by, BARNACLE, solid=False)
    for y in range(4, gy - 6, 3):
        c.put(7, y, WOODC[0], solid=False)


def _p_tide_stone(c):
    """The slab by the landing: a tall thin stone with wavy lines cut into its face."""
    gy = c.h - 2
    c.poly([(2, gy), (2, 6), (4, 2), (9, 1), (12, 4), (12, gy)], lambda x, y, dx, dy: c.put(x, y, lit(ROCKC, dx * 0.8, dy * 0.5, 9)))
    for (y, ph) in [(6, 0), (10, 1), (14, 2), (18, 3)]:
        for x in range(4, 11):
            c.put(x, y + (1 if (x + ph) % 4 < 2 else 0), SCRATCH, solid=False)
    c.ellipse(7, gy, 7, 1.6, lambda x, y, dx, dy: c.put(x, y, ROCKC[0]) if y >= gy else None)


def _p_cairn(c):
    gy = c.h - 2
    for cx, cy, rx, ry in [(8, gy - 3, 7.2, 3.4), (8, gy - 8, 5.4, 2.8), (8, gy - 12, 3.4, 2.4)]:
        c.ellipse(cx, cy, rx, ry, lambda x, y, dx, dy: c.put(x, y, lit(ROCKC, dx, dy, rx)))


def _p_marram(c):
    gy = c.h - 2
    for x0, h, lean in [(4, 12, -2), (7, 17, -1), (10, 19, 0), (13, 16, 1), (16, 11, 2), (9, 8, 0), (12, 9, 1)]:
        for k in range(h):
            x = x0 + (lean * k) // 5
            c.put(x, gy - k, GRASS[2] if k > h - 4 else (GRASS[1] if (x0 + k) % 3 else GRASS[0]), solid=False)
    c.ellipse(10, gy, 8, 1.6, lambda x, y, dx, dy: c.put(x, y, GRASS[0], solid=False) if y >= gy else None)


def _p_buoy(c):
    gy = c.h - 2
    c.ellipse(6, gy - 6, 5, 6, lambda x, y, dx, dy: c.put(x, y, lit(RED if dy > -2 else WHITE, dx, dy, 5)))
    c.line((6, gy - 12), (6, gy - 15), lambda x, y, dx, dy: c.put(x, y, WOODC[1]))
    c.line((2, gy - 7), (10, gy - 7), lambda x, y, dx, dy: c.put(x, y, WHITE[1], solid=False))


def _p_sand_dollar(c):
    """The secret's sand-dollar: a pale disc with a five-petal flower pressed into it."""
    gy = c.h - 2
    c.ellipse(8, gy - 5, 7.2, 5.4, lambda x, y, dx, dy: c.put(x, y, lit(SHELLP, dx, dy * 1.3, 8)))
    for a in range(5):
        ang = math.tau * a / 5 - math.pi / 2
        px, py = 8 + math.cos(ang) * 3.2, gy - 5 + math.sin(ang) * 2.4
        c.put(px, py, SHELLP[0], solid=False)
        c.put(8 + math.cos(ang) * 2.0, gy - 5 + math.sin(ang) * 1.5, SHELLP[0], solid=False)
    c.put(8, gy - 5, SHELLP[0], solid=False)


PROP_BUILDERS = {
    "eb_rock": ((21, 17), _p_rock),
    "eb_rock_big": ((35, 26), _p_rock_big),
    "eb_shellheap": ((22, 14), _p_shellheap),
    "eb_driftwood": ((32, 18), _p_driftwood),
    "eb_wrack": ((22, 14), _p_wrack),
    "eb_rowboat": ((42, 24), _p_rowboat),
    "eb_groyne": ((14, 26), _p_groyne),
    "eb_tide_stone": ((15, 26), _p_tide_stone),
    "eb_cairn": ((16, 24), _p_cairn),
    "eb_marram": ((22, 24), _p_marram),
    "eb_buoy": ((14, 20), _p_buoy),
    "eb_sand_dollar": ((18, 14), _p_sand_dollar),
}


def make_prop(name):
    """(base, tint_or_None) for an Ebbmere prop. None has a tint layer: their colours are fixed."""
    (w, h), fn = PROP_BUILDERS[name]
    c = Canvas(w, h)
    fn(c)
    c.outline()
    return c.img, (c.tint if c.has_tint else None)


# ------------------------------------------------------------------ the lighthouse
CREAM = ((0.66, 0.62, 0.56), (0.86, 0.82, 0.74), (0.98, 0.96, 0.90))
SEABLUE = ((0.16, 0.28, 0.40), (0.26, 0.44, 0.58), (0.44, 0.64, 0.76))
SLATE = ((0.20, 0.22, 0.28), (0.32, 0.35, 0.42), (0.52, 0.56, 0.64))
LAMP = (1.0, 0.88, 0.48)
LAMP_DEEP = (0.96, 0.66, 0.26)
LH_W, LH_H = 52, 152
LH_SPLIT = 48        # rows above this are the canopy (gallery, lamp room, roof); the rest is the tower


def lighthouse():
    """(trunk, canopy): one tall tower in two layers of the same size, so they line up when TreeView
    plants the pair on the ground. The lamp room is lit warm from within."""
    c = Canvas(LH_W, LH_H)
    gy = LH_H - 2
    cx = LH_W // 2
    top_y = 50
    bands = [(72, 84), (108, 120)]
    # the tower: a tapering drum, lit from the left, with two sea-blue bands
    for y in range(top_y, gy + 1):
        t = (y - top_y) / (gy - top_y)
        half = 8.0 + 5.5 * t
        ramp = SEABLUE if any(a <= y <= b for a, b in bands) else CREAM
        for x in range(int(cx - half), int(cx + half) + 1):
            u = (x - (cx - half)) / (2.0 * half)
            c.put(x, y, ramp[2 if u < 0.26 else (0 if u > 0.76 else 1)])
    # the stone plinth it stands on
    for y in range(gy - 5, gy + 1):
        half = 15.0 + (y - (gy - 5)) * 0.2
        for x in range(int(cx - half), int(cx + half) + 1):
            u = (x - (cx - half)) / (2.0 * half)
            c.put(x, y, ROCKC[2 if u < 0.22 else (0 if u > 0.78 else 1)])
    # a door with an arched head, a couple of small windows
    for y in range(gy - 17, gy - 5):
        for x in range(cx - 3, cx + 4):
            c.put(x, y, (0.16, 0.12, 0.10))
    for x in range(cx - 2, cx + 3):
        c.put(x, gy - 18, (0.16, 0.12, 0.10))
    c.put(cx + 2, gy - 11, (0.86, 0.66, 0.34), solid=False)
    for wy in (62, 96, 130):
        for x in range(cx - 1, cx + 2):
            for y in range(wy, wy + 4):
                c.put(x, y, (0.12, 0.16, 0.22))
        c.put(cx, wy + 1, (0.96, 0.82, 0.46), solid=False)
    # the gallery: a dark platform with a railing
    for y in range(44, 49):
        half = 15.0 - (y - 44) * 0.4
        for x in range(int(cx - half), int(cx + half) + 1):
            u = (x - (cx - half)) / (2.0 * half)
            c.put(x, y, SLATE[2 if u < 0.2 else (0 if u > 0.8 else 1)])
    for x in range(cx - 15, cx + 16, 3):
        for y in range(38, 44):
            c.put(x, y, SLATE[1], solid=False)
    for x in range(cx - 15, cx + 16):
        c.put(x, 38, SLATE[2])
    # the lamp room: warm glass between thin mullions
    for y in range(24, 38):
        for x in range(cx - 7, cx + 8):
            u = (x - (cx - 7)) / 14.0
            col = mix(LAMP, LAMP_DEEP, 0.6 * u + (0.2 if (y - 24) % 7 > 4 else 0.0))
            c.put(x, y, col, solid=False)
    for x in (cx - 7, cx - 2, cx + 3, cx + 7):
        for y in range(24, 38):
            c.put(x, y, SLATE[0])
    c.put(cx - 4, 30, (1.0, 0.98, 0.84), solid=False)
    c.put(cx - 3, 30, (1.0, 0.98, 0.84), solid=False)
    # the roof: a slate cone with a ball and a vane
    for y in range(12, 24):
        t = (y - 12) / 11.0
        half = 1.0 + 9.5 * t
        for x in range(int(cx - half), int(cx + half) + 1):
            u = (x - (cx - half)) / max(1.0, 2.0 * half)
            c.put(x, y, SLATE[2 if u < 0.3 else (0 if u > 0.78 else 1)])
    c.ellipse(cx, 10, 2.2, 2.2, lambda x, y, dx, dy: c.put(x, y, lit(SLATE, dx, dy, 2)))
    c.line((cx, 8), (cx, 2), lambda x, y, dx, dy: c.put(x, y, SLATE[0]))
    c.line((cx, 3), (cx + 4, 4), lambda x, y, dx, dy: c.put(x, y, SLATE[1]))
    c.outline()
    img = c.img
    trunk, canopy = img.copy(), img.copy()
    tp, cp = trunk.load(), canopy.load()
    for y in range(LH_H):
        for x in range(LH_W):
            if y < LH_SPLIT:
                tp[x, y] = (0, 0, 0, 0)
            else:
                cp[x, y] = (0, 0, 0, 0)
    return trunk, canopy


# ------------------------------------------------------------------ preview
def preview(path, scale=3):
    """A contact sheet: every tree, understory, prop, the litter and the lighthouse."""
    bg = (196, 184, 160, 255)
    items = []
    for spec in list(GROVE.values()) + list(UNDERSTORY.values()):
        t, cnp = tree_parts(spec)
        im = cnp.copy() if t is None else t.copy()
        if t is not None:
            im.alpha_composite(cnp)
        items.append(im)
    for name in PROP_BUILDERS:
        items.append(make_prop(name)[0])
    lt, lc = lighthouse()
    lt.alpha_composite(lc)
    items.append(lt)
    atlas, _ = detail_atlas()
    items.append(atlas)
    items.append(terrain_atlas().resize((TILE * 5 // 2, TILE // 2), Image.NEAREST))
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
