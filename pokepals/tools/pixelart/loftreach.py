"""
Loftreach -- the sky-island world -- pixel art: bright, breezy and high.

Built on the machinery the other worlds already have (nothing shared is edited; the new ramps are registered
on the imported modules at run time, as stillglass.py does):
  * trees      -- trees.make_grove_parts with fresh, sunlit ramps (so the shapes are the grove's);
  * ground     -- a seamless sunlit TURF tile and a stratified ROCK tile (the islands' cliff faces and the
                  stone under them), both opaque and tiling; the client fills each island's outline with them;
  * litter     -- a small detail atlas for the islands' grass (tufts, clover, daisies, windflowers, feathers);
  * clouds     -- soft pixel clouds in a few sizes (the sea of cloud under the islands) and bright high clouds
                  (the ones that, seen from far above, make the picture);
  * props      -- small procedural sprites on nocthollow.py's Canvas: the windmill tower (its sails are drawn by
                  the client so they turn), kite stakes, weathervanes, signs, hay, barrels, a bird-perch ...

Deterministic (seeded by name): re-running reproduces the PNGs byte for byte. Baked by tools/gen_loftreach.py.
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
    "lr_green":   ((46, 108, 70), (92, 168, 84), (170, 220, 116)),
    "lr_lime":    ((70, 130, 70), (128, 190, 84), (206, 238, 124)),
    "lr_pine":    ((30, 84, 84), (60, 130, 112), (124, 188, 146)),
    "lr_blossom": ((160, 70, 110), (232, 128, 164), (255, 208, 220)),
    "lr_gold":    ((172, 104, 36), (228, 164, 56), (252, 220, 116)),
    "lr_birch":   ((70, 130, 84), (126, 186, 100), (196, 234, 138)),
})
trees.BARK.update({
    "lr_bark": ((84, 62, 48), (126, 94, 68), (176, 140, 102)),
    "lr_pale": ((120, 112, 104), (214, 208, 196), (246, 244, 236)),
})

GROVE = {
    "round_a":   ("round", 1, "lr_green", "lr_bark", None),
    "round_b":   ("round", 2, "lr_lime", "lr_bark", None),
    "oak_a":     ("oak", 1, "lr_green", "lr_bark", None),
    "birch_a":   ("birch", 1, "lr_birch", "lr_pale", None),
    "birch_b":   ("birch", 2, "lr_birch", "lr_pale", None),
    "pine_a":    ("pine", 1, "lr_pine", "lr_bark", None),
    "pine_b":    ("pine", 2, "lr_pine", "lr_bark", None),
    "blossom_a": ("round", 5, "lr_blossom", "lr_bark", None),
    "blossom_b": ("round", 3, "lr_blossom", "lr_bark", None),
    "fruit_a":   ("round", 4, "lr_lime", "lr_bark", "fruit"),
    "gold_a":    ("oak", 3, "lr_gold", "lr_bark", None),
}
GREAT = {
    "great_apple": ("great_round", 8, "lr_lime", "lr_bark", "fruit"),
    "great_oak":   ("great_oak", 7, "lr_green", "lr_bark", None),
}
UNDERSTORY = {
    "bush_a": ("bush", 1, "lr_green", "lr_bark", None),
    "bush_b": ("bush", 2, "lr_lime", "lr_bark", None),
    "bush_bloom": ("bush", 5, "lr_green", "lr_bark", "blossom"),
    "stump": ("stump", 1, "lr_green", "lr_bark", None),
}


def tree_parts(spec):
    return trees.make_grove_parts(*spec)


# ------------------------------------------------------------------ seamless tiles
TILE = ground.TILE   # 128


def _periodic(seed, waves=6, fmax=5):
    """A periodic scalar field over the tile as a function (x, y) -> roughly 0..1: a few integer-frequency
    sines, so the tile repeats with no seam."""
    rng = random.Random(seed)
    parts = [(rng.randint(1, fmax), rng.randint(0, fmax), rng.random() * math.tau, rng.random() * math.tau) for _ in range(waves)]

    def f(x, y):
        s = 0.0
        for (kx, ky, p1, p2) in parts:
            s += math.sin(math.tau * (kx * x + ky * y) / TILE + p1) * math.cos(math.tau * (ky * x - kx * y) / TILE * 0.5 + p2)
        return 0.5 + 0.5 * max(-1.0, min(1.0, s / (waves * 0.55)))
    return f


BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

TURF = ((78, 148, 78), (104, 176, 88), (140, 206, 100), (190, 232, 126))   # dark, base, light, glint


def turf_tile():
    """Seamless sunlit turf: broad soft light and dark swells dithered into three greens, short blades, a few
    bright glints. Opaque."""
    rng = random.Random("loftreach-turf")
    swell = _periodic("turf-swell", 7, 3)
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 255))
    px = img.load()
    grid = [[1] * TILE for _ in range(TILE)]
    for y in range(TILE):
        for x in range(TILE):
            v = swell(x, y)
            d = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.22
            v += d
            grid[y][x] = 0 if v < 0.36 else (2 if v > 0.68 else 1)
    # blades: little 'v' strokes of the lighter and darker greens
    for _ in range(330):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        c = rng.choice([0, 0, 2, 2, 3])
        grid[y % TILE][x % TILE] = c
        if rng.random() < 0.7:
            grid[(y - 1) % TILE][x % TILE] = max(c, 1) if c != 0 else 0
        if rng.random() < 0.3:
            grid[(y - 2) % TILE][(x + rng.choice([-1, 1])) % TILE] = c
    for y in range(TILE):
        for x in range(TILE):
            r, g, b = TURF[grid[y][x]]
            px[x, y] = (r, g, b, 255)
    return img


ROCK = ((92, 78, 74), (134, 114, 98), (176, 154, 124), (214, 194, 156))


def rock_tile():
    """Seamless stratified rock: horizontal bands of warm stone, vertical cracks, chips. Opaque."""
    rng = random.Random("loftreach-rock")
    bands = _periodic("rock-bands", 5, 2)
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 255))
    px = img.load()
    grid = [[1] * TILE for _ in range(TILE)]
    for y in range(TILE):
        # strata: the band index depends mostly on y, wobbled by x
        for x in range(TILE):
            v = 0.5 + 0.5 * math.sin(math.tau * (y * 3 + 4.0 * math.sin(math.tau * x / TILE * 2)) / TILE)
            v = 0.6 * v + 0.4 * bands(x * 0.3, y)
            v += (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.18
            grid[y][x] = 0 if v < 0.34 else (2 if v > 0.66 else 1)
    for _ in range(26):   # cracks
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        for _k in range(rng.randint(4, 14)):
            grid[y % TILE][x % TILE] = 0
            y += 1
            x += rng.choice([-1, 0, 0, 1])
    for _ in range(90):   # chips
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        grid[y][x] = 3
        grid[y][(x + 1) % TILE] = 2
    for y in range(TILE):
        for x in range(TILE):
            r, g, b = ROCK[grid[y][x]]
            px[x, y] = (r, g, b, 255)
    return img


# ------------------------------------------------------------------ clouds
def _cloud(w, h, seed, top, mid, bot, flat=0.55):
    """One pixel cloud: a flat-ish bottom, lobed top, lit from above, with a dithered edge. RGBA."""
    rng = random.Random(seed)
    lobes = []
    n = max(4, w // 22)
    for i in range(n):
        cx = w * (0.14 + 0.72 * i / max(1, n - 1)) + rng.uniform(-3, 3)
        rx = rng.uniform(w * 0.12, w * 0.22)
        ry = rng.uniform(h * 0.42, h * 0.7) * (1.0 - 0.3 * abs(i - (n - 1) / 2) / ((n - 1) / 2 + 0.01))
        lobes.append((cx, h * 0.8 + rng.uniform(-2, 2), rx, ry))
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    base_y = h * 0.84
    for y in range(h):
        for x in range(w):
            inside = 0.0
            for (cx, cy, rx, ry) in lobes:
                d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                if d <= 1.0 and y <= base_y:
                    inside = max(inside, 1.0 - d)
            if inside <= 0.0:
                continue
            # dither the very edge
            if inside < 0.16 and BAYER[y % 4][x % 4] / 16.0 > inside * 6.0:
                continue
            t = y / base_y
            if t < 0.38:
                col = top
            elif t < 0.72:
                col = mid
            else:
                col = bot
            px[x, y] = (col[0], col[1], col[2], 255)
    return img


CLOUD_LOW = {   # the sea below the islands: pale blue-white, a cool underside
    "lr_cloud_a": (176, 56, 11), "lr_cloud_b": (232, 72, 12), "lr_cloud_c": (128, 44, 13), "lr_cloud_d": (288, 84, 14),
}
CLOUD_HIGH = {   # the high clouds that make the picture: brighter, warmer underside
    "lr_hicloud_a": (120, 44, 21), "lr_hicloud_b": (168, 56, 22),
}


def cloud_sprite(name):
    if name in CLOUD_LOW:
        w, h, seed = CLOUD_LOW[name]
        return _cloud(w, h, "lr-%s-%d" % (name, seed), (252, 253, 255), (222, 235, 250), (186, 208, 238))
    w, h, seed = CLOUD_HIGH[name]
    return _cloud(w, h, "lr-%s-%d" % (name, seed), (255, 255, 255), (246, 248, 255), (214, 226, 248))


# ------------------------------------------------------------------ litter on the grass
GRASS_T = ((70, 132, 74), (112, 178, 92), (176, 224, 120))
CLOVER = ((60, 124, 78), (100, 166, 96), (150, 206, 120))
DAISY = ((220, 220, 206), (252, 252, 244), (255, 214, 92))
WIND = ((150, 96, 200), (206, 150, 240), (250, 226, 255))
POPPY = ((190, 52, 48), (240, 98, 80), (255, 190, 150))
BUTTER = ((214, 160, 36), (250, 208, 70), (255, 244, 170))
PEBBLE = ((110, 100, 96), (160, 148, 136), (214, 202, 184))
FEATHER = ((150, 160, 176), (212, 220, 232), (250, 252, 255))

DETAILS = {
    "tuft_a": (GRASS_T, False, [
        "..3..3.",
        ".23.32.",
        ".22.22.",
        "122.221",
        "1221221",
    ]),
    "tuft_b": (GRASS_T, False, [
        "...3...",
        "..32.3.",
        ".322.2.",
        "12222.1",
    ]),
    "clover": (CLOVER, False, [
        ".3.3.",
        "32323",
        ".222.",
        "..1..",
    ]),
    "daisy": (DAISY, False, [
        ".1.1.",
        "1.3.1",
        ".131.",
        "..1..",
        "..1..",
    ]),
    "windflower": (WIND, False, [
        "..3..",
        ".323.",
        "..2..",
        "..1..",
        "..1..",
    ]),
    "poppy": (POPPY, False, [
        ".3.3.",
        "32223",
        ".212.",
        "..1..",
        "..1..",
    ]),
    "buttercup": (BUTTER, False, [
        "..3..",
        ".323.",
        "..2..",
        "..1..",
    ]),
    "pebbles": (PEBBLE, False, [
        ".33..3",
        ".21.31",
        "......",
        "..32..",
        "..21..",
    ]),
    "feather": (FEATHER, False, [
        "...33",
        "..32.",
        ".32..",
        "32...",
        "1....",
    ]),
}


def _detail(name):
    ramp, outlined, rows = DETAILS[name]
    h, w = len(rows), max(len(r) for r in rows)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        assert len(row) == w, "%s row %d is %d cols, wanted %d" % (name, y, len(row), w)
        for x, ch in enumerate(row):
            if ch == '.':
                continue
            px[x, y] = tuple(ramp[int(ch) - 1]) + (255,)
    return img


def detail_atlas():
    """(image, index) with index {name: [x, y, w, h]}."""
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
STONE = ((0.46, 0.44, 0.44), (0.66, 0.63, 0.60), (0.88, 0.85, 0.80))
STONE_WARM = ((0.52, 0.44, 0.38), (0.74, 0.64, 0.52), (0.94, 0.86, 0.72))
WASH = ((0.70, 0.66, 0.62), (0.90, 0.88, 0.84), (1.00, 0.99, 0.95))   # whitewash
WOOD = ((0.36, 0.26, 0.18), (0.56, 0.42, 0.28), (0.78, 0.62, 0.42))
WOOD_PALE = ((0.50, 0.40, 0.30), (0.72, 0.60, 0.44), (0.92, 0.82, 0.62))
ROOF = ((0.50, 0.22, 0.20), (0.76, 0.34, 0.28), (0.94, 0.54, 0.42))
STRAW = ((0.70, 0.54, 0.24), (0.90, 0.74, 0.36), (1.00, 0.92, 0.58))
IRON = ((0.20, 0.22, 0.28), (0.34, 0.38, 0.46), (0.56, 0.62, 0.72))
SKY_BLUE = ((0.28, 0.48, 0.74), (0.46, 0.68, 0.92), (0.74, 0.88, 1.00))
LEAFC = ((0.22, 0.46, 0.28), (0.36, 0.64, 0.34), (0.62, 0.84, 0.46))
GOLD = ((0.80, 0.56, 0.14), (0.98, 0.78, 0.26), (1.00, 0.94, 0.58))
SCRATCH = (0.30, 0.26, 0.24)


def _p_windmill(c):
    """The tower of a windmill: a round whitewashed stone tower with a red cap, a door and two windows. The sails
    are drawn by the client (they turn) from the hub, which sits at pixel (32, 30) of this 64 x 110 sprite."""
    gy = c.h - 2
    # base: wide stone plinth
    c.poly([(10, gy), (14, gy - 14), (50, gy - 14), (54, gy)], lambda x, y, dx, dy: c.put(x, y, lit(STONE_WARM, dx * 0.8, dy * 0.4, 30)))
    # tower: tapering whitewash
    for y in range(30, gy - 12):
        t = (y - 30) / float(gy - 42)
        half = 11 + 9 * t
        for x in range(int(32 - half), int(32 + half) + 1):
            dx = x - 32
            c.put(x, y, WASH[2] if dx < -half * 0.45 else (WASH[0] if dx > half * 0.55 else WASH[1]))
    # courses of stone showing through
    for y in range(40, gy - 14, 9):
        t = (y - 30) / float(gy - 42)
        half = 11 + 9 * t
        for x in range(int(32 - half) + 2, int(32 + half) - 1, 4):
            c.put(x, y, WASH[0], solid=False)
    # cap
    c.poly([(18, 32), (22, 18), (32, 10), (42, 18), (46, 32)], lambda x, y, dx, dy: c.put(x, y, lit(ROOF, dx * 0.8, dy * 0.8, 14)))
    c.ellipse(32, 31, 15, 3, lambda x, y, dx, dy: c.put(x, y, WOOD[0]) if y >= 31 else None)
    # the hub
    c.disc(32, 30, 3, lambda x, y, dx, dy: c.put(x, y, lit(IRON, dx, dy, 3)))
    # door and windows
    c.poly([(27, gy - 14), (27, gy - 26), (32, gy - 31), (37, gy - 26), (37, gy - 14)], lambda x, y, dx, dy: c.put(x, y, WOOD[1] if dx < 3 else WOOD[0]))
    c.put(36, gy - 21, GOLD[1], solid=False)
    for (wx, wy) in [(26, 56), (38, 56)]:
        c.poly([(wx - 2, wy + 5), (wx - 2, wy), (wx, wy - 2), (wx + 2, wy), (wx + 2, wy + 5)], lambda x, y, dx, dy: c.put(x, y, SKY_BLUE[1] if dy < 1 else SKY_BLUE[0]))
    c.ellipse(32, gy, 22, 2, lambda x, y, dx, dy: c.put(x, y, STONE_WARM[0]) if y >= gy else None)


def _p_kite_stake(c):
    """A stake with a spool of line and a couple of spare kites folded against it."""
    gy = c.h - 2
    c.poly([(7, gy), (7, 6), (9, 3), (11, 6), (11, gy)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx * 0.7, dy * 0.4, 6)))
    c.ellipse(9, 12, 4, 5, lambda x, y, dx, dy: c.put(x, y, lit(WOOD_PALE, dx, dy, 4)))
    for y in range(8, 17, 2):
        for x in range(6, 13):
            c.put(x, y, SKY_BLUE[2] if (x + y) % 3 else SKY_BLUE[1], solid=False)
    c.ellipse(9, gy, 5, 1.6, lambda x, y, dx, dy: c.put(x, y, STONE[0]) if y >= gy else None)


def _p_vane(c):
    """A weathervane: a tall iron pole, the four letters' crossbar, and an arrow that points up and to the right
    (every vane in Loftreach points the same way, whichever way the wind blows)."""
    gy = c.h - 2
    for y in range(12, gy):
        c.put(10, y, IRON[1])
        c.put(11, y, IRON[2] if y % 3 else IRON[1])
    for x in range(5, 18):
        c.put(x, 16, IRON[1])
    for (x, y) in [(5, 15), (17, 15), (11, 12), (11, 20)]:
        c.put(x, y, GOLD[1])
    # the arrow, pointing right and a little up
    c.line((5, 8), (20, 4), lambda x, y, dx, dy: c.put(x, y, GOLD[1]))
    c.poly([(20, 1), (24, 4), (20, 7)], lambda x, y, dx, dy: c.put(x, y, GOLD[2]))
    c.poly([(5, 6), (2, 4), (3, 10), (6, 10)], lambda x, y, dx, dy: c.put(x, y, GOLD[0]))
    c.ellipse(10, gy, 6, 1.6, lambda x, y, dx, dy: c.put(x, y, STONE[0]) if y >= gy else None)


def _p_sign(c):
    gy = c.h - 2
    c.poly([(7, gy), (7, 5), (9, 4), (11, 5), (11, gy)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx * 0.7, dy * 0.4, 6)))
    c.poly([(1, 5), (13, 3), (16, 6), (13, 9), (1, 9)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD_PALE, dx * 0.5, dy, 8)))
    for x in range(3, 12):
        c.put(x, 6, SCRATCH, solid=False)
    for x in range(3, 9):
        c.put(x, 8, SCRATCH, solid=False)
    c.ellipse(9, gy, 5, 1.6, lambda x, y, dx, dy: c.put(x, y, STONE[0]) if y >= gy else None)


def _p_boulder(c):
    gy = c.h - 2
    pts = [(2, gy), (1, 9), (4, 4), (10, 2), (16, 4), (19, 9), (18, gy)]
    c.poly(pts, lambda x, y, dx, dy: c.put(x, y, lit(STONE_WARM, dx, dy * 0.7, 9)))
    for (x, y) in [(5, 6), (6, 6), (7, 5), (14, 4), (15, 5)]:
        c.put(x, y, LEAFC[1], solid=False)
    c.ellipse(10, gy, 10, 2, lambda x, y, dx, dy: c.put(x, y, STONE_WARM[0]) if y >= gy else None)


def _p_barrel(c):
    gy = c.h - 2
    c.ellipse(7, gy - 6, 6, 8, lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx * 0.9, dy * 0.5, 6)))
    for y in (gy - 11, gy - 2):
        for x in range(2, 13):
            if c.inside(x, y):
                c.put(x, y, IRON[1], solid=False)
    c.ellipse(7, gy - 13, 5, 1.8, lambda x, y, dx, dy: c.put(x, y, WOOD_PALE[1]))


def _p_haystack(c):
    gy = c.h - 2
    c.poly([(1, gy), (3, 9), (8, 3), (14, 2), (20, 4), (23, 10), (24, gy)], lambda x, y, dx, dy: c.put(x, y, lit(STRAW, dx * 0.8, dy * 0.6, 12)))
    for (x, y) in [(6, 8), (9, 6), (13, 7), (17, 9), (11, 12), (7, 14)]:
        c.put(x, y, STRAW[0], solid=False)
    c.ellipse(12, gy, 12, 2, lambda x, y, dx, dy: c.put(x, y, STRAW[0]) if y >= gy else None)


def _p_planter(c):
    """A wooden planter of mixed flowers."""
    gy = c.h - 2
    c.poly([(1, gy), (1, gy - 6), (21, gy - 6), (21, gy)], lambda x, y, dx, dy: c.put(x, y, WOOD[2] if dy < -1 else WOOD[1]))
    rng = random.Random("planter")
    for x in range(2, 21):
        c.put(x, gy - 7, LEAFC[1])
        c.put(x, gy - 8, LEAFC[0] if x % 2 else LEAFC[1])
    for x in range(3, 20, 3):
        col = rng.choice([POPPY[1], WIND[1], BUTTER[1], DAISY[1]])
        h = rng.randint(2, 5)
        c.put(x, gy - 9 - h, col)
        c.put(x - 1, gy - 8 - h, col, solid=False)
        c.put(x + 1, gy - 8 - h, col, solid=False)
        c.put(x, gy - 8 - h + 1, GOLD[1], solid=False)


def _p_lamp(c):
    """A lamp-post with a hanging lantern, swaying in no wind in particular."""
    gy = c.h - 2
    for y in range(8, gy):
        c.put(5, y, IRON[1])
        c.put(6, y, IRON[2] if y % 4 else IRON[1])
    for x in range(5, 12):
        c.put(x, 6, IRON[1])
    c.poly([(9, 9), (9, 14), (13, 14), (13, 9), (11, 7)], lambda x, y, dx, dy: c.put(x, y, GOLD[1] if dy > -2 else GOLD[2]))
    c.glow(11, 11, (1.0, 0.96, 0.72))
    c.ellipse(5, gy, 5, 1.6, lambda x, y, dx, dy: c.put(x, y, STONE[0]) if y >= gy else None)


def _p_bench(c):
    gy = c.h - 2
    c.poly([(1, gy - 6), (1, gy - 9), (24, gy - 9), (24, gy - 6)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD_PALE, 0, dy, 4)))
    c.poly([(2, gy), (2, gy - 6), (4, gy - 6), (4, gy)], lambda x, y, dx, dy: c.put(x, y, WOOD[0]))
    c.poly([(21, gy), (21, gy - 6), (23, gy - 6), (23, gy)], lambda x, y, dx, dy: c.put(x, y, WOOD[0]))
    c.poly([(2, gy - 9), (2, gy - 14), (23, gy - 14), (23, gy - 9)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD, 0, dy, 4)))


def _p_pennant(c):
    """A pole with a string of bright bunting."""
    gy = c.h - 2
    for y in range(4, gy):
        c.put(4, y, WOOD[1])
        c.put(5, y, WOOD[2] if y % 3 else WOOD[1])
    c.ellipse(5, 3, 2, 2, lambda x, y, dx, dy: c.put(x, y, GOLD[1]))
    cols = [POPPY[1], BUTTER[1], SKY_BLUE[1], WIND[1], LEAFC[2]]
    for i in range(5):
        x0 = 7 + i * 3
        yy = 6 + (i % 2)
        c.poly([(x0, yy), (x0 + 3, yy), (x0 + 1.5, yy + 5)], lambda x, y, dx, dy, col=cols[i]: c.put(x, y, col))
    c.ellipse(5, gy, 5, 1.6, lambda x, y, dx, dy: c.put(x, y, STONE[0]) if y >= gy else None)


def _p_perch(c):
    """A small dovecote on a post: a pitched box with a round door and a perch."""
    gy = c.h - 2
    for y in range(14, gy):
        c.put(10, y, WOOD[1])
        c.put(11, y, WOOD[2] if y % 3 else WOOD[1])
    c.poly([(3, 14), (3, 5), (18, 5), (18, 14)], lambda x, y, dx, dy: c.put(x, y, lit(WASH, dx * 0.7, dy * 0.4, 10)))
    c.poly([(1, 6), (10, 0), (20, 6)], lambda x, y, dx, dy: c.put(x, y, lit(ROOF, dx * 0.6, dy * 0.6, 10)))
    c.disc(10, 9, 2, lambda x, y, dx, dy: c.put(x, y, WOOD[0]))
    for x in range(7, 14):
        c.put(x, 13, WOOD[1], solid=False)
    c.ellipse(10, gy, 5, 1.6, lambda x, y, dx, dy: c.put(x, y, STONE[0]) if y >= gy else None)


def _p_standing_stone(c):
    """A standing stone with a bird scratched into it, wings up."""
    gy = c.h - 2
    c.poly([(2, gy), (2, 8), (5, 2), (11, 1), (14, 5), (14, gy)], lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx * 0.8, dy * 0.5, 9)))
    for (x, y) in [(5, 9), (6, 10), (7, 11), (8, 10), (9, 9), (7, 12), (7, 13), (6, 14), (8, 14)]:
        c.put(x, y, SCRATCH, solid=False)
    c.ellipse(8, gy, 7, 1.6, lambda x, y, dx, dy: c.put(x, y, STONE[0]) if y >= gy else None)


def _p_hammock(c):
    """Two posts and a hammock between them."""
    gy = c.h - 2
    for x0 in (2, 26):
        for y in range(6, gy):
            c.put(x0, y, WOOD[1])
            c.put(x0 + 1, y, WOOD[2])
    for x in range(3, 27):
        t = (x - 3) / 23.0
        y = 9 + int(5 * math.sin(math.pi * t))
        c.put(x, y, SKY_BLUE[1])
        c.put(x, y + 1, SKY_BLUE[0] if x % 2 else SKY_BLUE[1])
        c.put(x, y + 2, SKY_BLUE[0], solid=False)
    c.ellipse(2, gy, 4, 1.4, lambda x, y, dx, dy: c.put(x, y, STONE[0]) if y >= gy else None)
    c.ellipse(27, gy, 4, 1.4, lambda x, y, dx, dy: c.put(x, y, STONE[0]) if y >= gy else None)


PROP_BUILDERS = {
    "lr_windmill": ((64, 110), _p_windmill),
    "lr_kite_stake": ((18, 26), _p_kite_stake),
    "lr_vane": ((26, 46), _p_vane),
    "lr_sign": ((18, 28), _p_sign),
    "lr_boulder": ((21, 17), _p_boulder),
    "lr_barrel": ((14, 18), _p_barrel),
    "lr_haystack": ((26, 20), _p_haystack),
    "lr_planter": ((23, 20), _p_planter),
    "lr_lamp": ((16, 34), _p_lamp),
    "lr_bench": ((26, 18), _p_bench),
    "lr_pennant": ((26, 40), _p_pennant),
    "lr_perch": ((22, 36), _p_perch),
    "lr_standing_stone": ((16, 28), _p_standing_stone),
    "lr_hammock": ((30, 24), _p_hammock),
}


def make_prop(name):
    """(base, tint_or_None) for a Loftreach prop. Colours are fixed (no tint layer)."""
    (w, h), fn = PROP_BUILDERS[name]
    c = Canvas(w, h)
    fn(c)
    c.outline()
    return c.img, (c.tint if c.has_tint else None)


# ------------------------------------------------------------------ preview
def preview(path, scale=3):
    """A contact sheet: every tree, the understory, the props, the clouds, the litter and both tiles."""
    bg = (150, 196, 236, 255)
    items = []
    for spec in list(GROVE.values()) + list(GREAT.values()) + list(UNDERSTORY.values()):
        t, cnp = tree_parts(spec)
        im = cnp.copy() if t is None else t.copy()
        if t is not None:
            im.alpha_composite(cnp)
        items.append(im)
    for name in PROP_BUILDERS:
        items.append(make_prop(name)[0])
    for name in list(CLOUD_LOW) + list(CLOUD_HIGH):
        items.append(cloud_sprite(name))
    atlas, _ = detail_atlas()
    items.append(atlas)
    items.append(turf_tile())
    items.append(rock_tile())
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
