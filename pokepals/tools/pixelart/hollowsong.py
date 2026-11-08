"""
Hollowsong -- the echo canyon -- pixel art: junipers and sage on red-rock benches, gold cottonwoods and
dry willows along the old riverbed, sun-baked ground in five moods, the small things lying about (boulders,
cairns, hoodoos, a dry log, agave and yucca, a fire ring, a notice board) and the two greyscale tiles the
cliffs are drawn from (rock grain and a sandy mesa top; CliffView tints them per band).

Same language as the other worlds (a lit blob under the upper-left light, the shared 1px outline), in a
warm sunset palette: banded red, ochre and cream stone, dusty sage, gold leaf.

Most of it is built from machinery the other worlds already have:
  * trees   -- trees.make_grove_parts with new foliage/bark ramps (the grove's shapes);
  * ground  -- the seamless terrain atlas in ground.py's layout (R = shade role, G = accent), with a
               sun-baked grain, plus a detail atlas of dry litter;
  * water   -- one new ramp for water.py: still pools that hold the sunset;
  * props   -- small procedural sprites on nocthollow.py's Canvas, BASE + optional TINT.

Everything is deterministic (seeded by name), so re-running reproduces the PNGs byte for byte.
Baked by tools/gen_hollowsong.py.
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
    "juniper":   ((38, 62, 46), (66, 96, 66), (122, 148, 96)),
    "juniper2":  ((46, 70, 50), (78, 106, 72), (134, 158, 104)),
    "sage":      ((72, 92, 80), (112, 134, 116), (170, 190, 164)),
    "cotton":    ((156, 104, 28), (214, 158, 48), (250, 214, 112)),
    "cotton_lo": ((130, 84, 26), (190, 128, 40), (240, 188, 92)),
    "drywillow": ((120, 108, 52), (176, 160, 82), (226, 208, 130)),
})
trees.BARK.update({
    "redbark": ((70, 40, 34), (112, 68, 50), (160, 108, 76)),
    "pale":    ((96, 80, 68), (150, 126, 104), (206, 186, 160)),
})

GROVE = {
    "juniper_a": ("pine", 1, "juniper", "redbark", None),
    "juniper_b": ("pine", 2, "juniper2", "redbark", None),
    "juniper_c": ("pine", 3, "juniper", "redbark", None),
    "juniper_d": ("pine", 4, "juniper2", "redbark", None),
    "sage_a":    ("round", 1, "sage", "pale", None),
    "sage_b":    ("round", 2, "sage", "pale", None),
    "cotton_a":  ("oak", 1, "cotton", "pale", None),
    "cotton_b":  ("oak", 2, "cotton_lo", "pale", None),
    "cotton_c":  ("round", 6, "cotton", "pale", None),
    "dryw_a":    ("willow", 1, "drywillow", "pale", None),
    "dryw_b":    ("willow", 3, "drywillow", "pale", None),
}
GREAT = {
    "great_cotton": ("great_oak", 7, "cotton", "pale", None),
    "great_dryw":   ("great_willow", 9, "drywillow", "pale", None),
}
UNDERSTORY = {
    "bush_a": ("bush", 1, "sage", "pale", None),
    "bush_b": ("bush", 2, "juniper2", "redbark", None),
    "stump":  ("stump", 1, "sage", "pale", None),
}


def tree_parts(spec):
    return trees.make_grove_parts(*spec)


# ------------------------------------------------------------------ the ground
TILE = ground.TILE
KINDS = ground.KINDS


def _terrain(kind):
    """(shade_grid, accent_grid) for one sun-baked mood: base shade 2 with a fine grain of dark pits (1) and
    lit grains (3). Only FINE detail is baked in; the broad swells are the shader's."""
    rng = random.Random("hollowsong-ground-" + kind)
    base = 1 if kind == "dirt" else 2
    g = [[base] * TILE for _ in range(TILE)]
    acc = [[0] * TILE for _ in range(TILE)]
    # (pits, grains, ripples): scrub is flecked; gravel is dense and rough; straw is pale and sparse; clay is
    # dark and cracked; the riverbed sand is smooth with long ripples.
    mix_by_kind = {
        "grass":  (110, 120, 10),
        "lush":   (170, 90, 14),
        "meadow": (70, 150, 18),
        "dirt":   (210, 70, 4),
        "sand":   (30, 150, 34),
    }
    n_pit, n_grain, n_ripple = mix_by_kind[kind]
    for _ in range(n_pit):
        ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_pit // 3):
        ground._stamp(g, [(0, 0, 1), (1, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_grain):
        ground._stamp(g, [(0, 0, 3)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_ripple):
        # a short wind ripple: a lit run over a dark one
        x0, y0 = rng.randrange(TILE), rng.randrange(TILE)
        for k in range(rng.randint(3, 6)):
            ground._stamp(g, [(k, 0, 3), (k, 1, 1)], x0, y0)
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


STRAW = ((120, 96, 52), (176, 150, 88), (230, 208, 142))
SAGE = ((66, 86, 74), (108, 130, 112), (164, 186, 158))
PRICKLY = ((52, 90, 62), (86, 134, 84), (140, 182, 112))
REDSTONE = ((98, 44, 34), (150, 72, 50), (206, 118, 78))
PALE_STONE = ((150, 120, 98), (200, 170, 140), (238, 216, 186))
BONE = ((176, 162, 138), (226, 214, 188), (252, 246, 226))
LEAF_GOLD = ((170, 118, 30), (226, 176, 56), (252, 226, 124))
TWIG = ((70, 50, 40), (110, 84, 64), (156, 126, 98))
SAND_RIPPLE = ((200, 168, 130), (232, 204, 164), (252, 234, 200))
BLOOM = ((196, 80, 70), (238, 130, 96), (252, 200, 140))

DETAILS = {
    "strawtuft_a": (STRAW, False, [
        "..3...3.",
        ".3.3.32.",
        ".32.32..",
        "3221221.",
        "121.121.",
    ]),
    "strawtuft_b": (STRAW, False, [
        "...3..3",
        ".3.32.2",
        "32.22.2",
        "2212.21",
        "1.11.1.",
    ]),
    "sagebrush": (SAGE, False, [
        "..333..",
        ".32232.",
        "3222233",
        "2221222",
        ".11211.",
        "...1...",
    ]),
    "yucca_spike": (PRICKLY, False, [
        "3..3.3",
        ".3.32.",
        "..322.",
        "..22..",
        "..21..",
        "..1...",
    ]),
    "pricklypear": (PRICKLY, True, [
        ".333.",
        "32222",
        "22122",
        ".211.",
    ]),
    "pebbles": (REDSTONE, False, [
        ".33..3",
        ".21.31",
        "......",
        "..32..",
        "..21..",
    ]),
    "redstone": (REDSTONE, True, [
        ".3332..",
        "332222.",
        "3222221",
        ".22111.",
    ]),
    "palestone": (PALE_STONE, True, [
        ".333.",
        "32222",
        "22221",
        ".211.",
    ]),
    "bone": (BONE, False, [
        "3.....3.",
        ".322232.",
        ".1.....1",
    ]),
    "goldleaf": (LEAF_GOLD, False, [
        ".3.3.",
        "32223",
        ".222.",
        "..1..",
    ]),
    "twig": (TWIG, False, [
        "3.3....",
        ".23..3.",
        "..2232.",
        "....21.",
    ]),
    "ripple": (SAND_RIPPLE, False, [
        ".3333...",
        "2.....3.",
        "......21",
    ]),
    "desertbloom": (BLOOM, False, [
        ".3.",
        "323",
        ".2.",
        ".1.",
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
# A still seep in the riverbed: dark rock-pool blue-grey that holds the sunset's copper in its glints.
water.RAMPS["canyon"] = ((0.22, 0.30, 0.38), (0.38, 0.50, 0.56), (0.98, 0.76, 0.50))


def pool_tile():
    return water.make_water_tile("canyon")


# ------------------------------------------------------------------ cliff tiles (greyscale, tinted by band)
def rock_tile():
    """32 x 32 greyscale rock face: fine horizontal strata (the bands the CliffView tints), a few hairline
    fissures and a grain of lit and dark specks. Multiplied by each band's colour."""
    rng = random.Random("hs-rock")
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 255))
    px = img.load()
    for y in range(32):
        row_tone = 0.84 + 0.06 * math.sin(y * math.tau / 32.0 * 3.0) + rng.uniform(-0.03, 0.03)
        for x in range(32):
            g = round(max(0.0, min(1.0, row_tone)) * 255)
            px[x, y] = (g, g, g, 255)
    for _ in range(5):                          # thin dark strata lines
        y = rng.randrange(32)
        for x in range(32):
            if rng.random() < 0.8:
                g = round(0.62 * 255)
                px[x, y] = (g, g, g, 255)
    for _ in range(3):                          # a fissure: a short vertical crack
        x0, y0 = rng.randrange(32), rng.randrange(32)
        for k in range(rng.randint(4, 8)):
            g = round(0.50 * 255)
            px[(x0 + (k // 3) % 2) % 32, (y0 + k) % 32] = (g, g, g, 255)
    for _ in range(70):                         # grain
        x, y = rng.randrange(32), rng.randrange(32)
        g = round(rng.choice([0.70, 0.97, 1.0]) * 255)
        px[x, y] = (g, g, g, 255)
    return img


def top_tile():
    """24 x 24 greyscale mesa top: windblown sand and flat stone, a speckle of lit and dark grains."""
    rng = random.Random("hs-top")
    img = Image.new("RGBA", (24, 24), (0, 0, 0, 255))
    px = img.load()
    for y in range(24):
        for x in range(24):
            g = round(rng.uniform(0.86, 0.94) * 255)
            px[x, y] = (g, g, g, 255)
    for _ in range(46):
        x, y = rng.randrange(24), rng.randrange(24)
        g = round(rng.choice([0.66, 0.74, 1.0]) * 255)
        px[x, y] = (g, g, g, 255)
    return img


# ------------------------------------------------------------------ props
RED = ((0.34, 0.14, 0.11), (0.58, 0.27, 0.18), (0.82, 0.46, 0.30))
CREAM = ((0.52, 0.38, 0.28), (0.76, 0.60, 0.44), (0.94, 0.82, 0.64))
DRYWOOD = ((0.30, 0.24, 0.20), (0.52, 0.42, 0.34), (0.74, 0.64, 0.52))
WOOD = ((0.26, 0.18, 0.13), (0.44, 0.32, 0.22), (0.62, 0.48, 0.34))
DARKWOOD = ((0.16, 0.11, 0.09), (0.28, 0.20, 0.15), (0.42, 0.32, 0.24))
AGAVE = ((0.22, 0.38, 0.34), (0.38, 0.58, 0.50), (0.62, 0.80, 0.66))
SOOT = ((0.10, 0.09, 0.09), (0.20, 0.17, 0.16), (0.34, 0.30, 0.28))
EMBER = (1.0, 0.62, 0.28)
CLOTH_RED = ((0.50, 0.18, 0.14), (0.78, 0.32, 0.22), (0.94, 0.52, 0.34))


def _p_boulder(c):
    gy = c.h - 2
    pts = [(2, gy), (1, 9), (5, 3), (12, 1), (19, 3), (23, 9), (22, gy)]
    c.poly(pts, lambda x, y, dx, dy: c.put(x, y, lit(RED, dx, dy * 0.7, 10)))
    c.poly([(5, 8), (7, 4), (12, 3), (16, 6), (11, 7)], lambda x, y, dx, dy: c.put(x, y, lit(CREAM, dx, dy, 5)))
    c.line((6, 12), (15, 12), lambda x, y, dx, dy: c.put(x, y, RED[0]))           # a strata seam
    c.line((4, 9), (19, 9), lambda x, y, dx, dy: c.put(x, y, RED[2]) if x % 3 else None)


def _p_cairn(c):
    gy = c.h - 2
    cx = c.w // 2
    for (rx, ry, yy) in [(6.0, 2.6, gy - 2), (4.6, 2.2, gy - 6), (3.4, 2.0, gy - 10), (2.2, 1.6, gy - 13)]:
        c.ellipse(cx, yy, rx, ry, lambda x, y, dx, dy: c.put(x, y, lit(CREAM, dx, dy, 5)))
    c.ellipse(cx - 1, gy - 6, 2, 1, lambda x, y, dx, dy: c.put(x, y, RED[1]))


def _p_hoodoo(c):
    """A tall wind-carved column with a cap-stone, banded red and cream."""
    gy = c.h - 2
    cx = c.w // 2
    bands = [RED, CREAM, RED, CREAM, RED]
    top = 8
    for i in range(top, gy):
        w = 4 + (3 if i > gy - 6 else 0) + (1 if (i // 5) % 2 else 0)
        ramp = bands[((i - top) // 7) % len(bands)]
        for x in range(cx - w, cx + w + 1):
            dx = x - cx
            c.put(x, i, lit(ramp, dx * 1.3, 0.0, w))
    c.poly([(cx - 8, top), (cx + 8, top), (cx + 6, top - 5), (cx - 6, top - 5)], lambda x, y, dx, dy: c.put(x, y, lit(RED, dx, dy, 7)))
    c.line((cx - 7, top), (cx + 7, top), lambda x, y, dx, dy: c.put(x, y, RED[0]))


def _p_log(c):
    gy = c.h - 2
    c.poly([(1, gy - 3), (3, gy - 8), (26, gy - 8), (28, gy - 3), (26, gy), (3, gy)], lambda x, y, dx, dy: c.put(x, y, lit(DRYWOOD, dx * 0.2, dy * 1.6, 10)))
    c.ellipse(27, gy - 4, 1.8, 3.4, lambda x, y, dx, dy: c.put(x, y, DRYWOOD[2]))
    for x in (6, 11, 17, 22):
        c.line((x, gy - 7), (x + 2, gy - 2), lambda x_, y_, dx, dy: c.put(x_, y_, DRYWOOD[0]))
    c.line((12, gy - 8), (15, gy - 12), lambda x, y, dx, dy: c.put(x, y, DRYWOOD[1]))   # a broken branch


def _p_agave(c):
    gy = c.h - 2
    cx = c.w // 2
    for ang in (-1.25, -0.8, -0.35, 0.0, 0.35, 0.8, 1.25):
        tip = (cx + math.sin(ang) * 9, gy - 3 - math.cos(ang) * 11)
        c.line((cx, gy - 1), tip, lambda x, y, dx, dy: c.put(x, y, lit(AGAVE, dx * 0.1 + ang, dy, 4)), width=2.2)
    c.ellipse(cx, gy - 1, 3, 1.4, lambda x, y, dx, dy: c.put(x, y, AGAVE[0]))


def _p_yucca(c):
    gy = c.h - 2
    cx = c.w // 2
    c.line((cx, gy), (cx, gy - 14), lambda x, y, dx, dy: c.put(x, y, DRYWOOD[1]), width=3.0)
    for ang in (-1.3, -0.9, -0.45, 0.0, 0.45, 0.9, 1.3):
        tip = (cx + math.sin(ang) * 8, gy - 14 - math.cos(ang) * 7)
        c.line((cx, gy - 13), tip, lambda x, y, dx, dy: c.put(x, y, lit(AGAVE, ang, dy, 4)), width=1.6)
    c.line((cx, gy - 18), (cx, gy - 29), lambda x, y, dx, dy: c.put(x, y, DRYWOOD[2]))      # the flower stalk
    for yy in (gy - 26, gy - 24, gy - 22):
        c.put(cx - 1, yy, (0.96, 0.92, 0.80))
        c.put(cx + 1, yy - 1, (0.96, 0.92, 0.80))


def _p_ring(c):
    """A ring of stones round old ashes, one ember still red."""
    gy = c.h - 2
    cx = c.w // 2
    c.ellipse(cx, gy - 3, 8.4, 3.8, lambda x, y, dx, dy: c.put(x, y, lit(CREAM, dx, dy * 1.2, 8)))
    c.ellipse(cx, gy - 3, 5.6, 2.2, lambda x, y, dx, dy: c.put(x, y, SOOT[1], solid=False))
    c.put(cx - 1, gy - 3, EMBER)
    c.put(cx + 2, gy - 4, mix(EMBER, (1.0, 0.9, 0.6), 0.5))
    c.line((cx - 4, gy - 4), (cx + 3, gy - 2), lambda x, y, dx, dy: c.put(x, y, DARKWOOD[1]) if x % 2 else None)


def _p_board(c):
    """A notice board: two posts, a plank face with a few faded lines of writing and a little roof."""
    gy = c.h - 2
    for lx in (2, 13):
        c.poly([(lx, 6), (lx + 2, 6), (lx + 2, gy), (lx, gy)], lambda x, y, dx, dy: c.put(x, y, lit(DARKWOOD, dx * 1.4, dy * 0.1, 3)))
    c.poly([(1, 7), (16, 7), (16, 19), (1, 19)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx * 0.4, dy * 0.4, 8)))
    for yy in (10, 13, 16):
        c.line((4, yy), (13 - (yy % 3), yy), lambda x, y, dx, dy: c.put(x, y, DARKWOOD[1]))
    c.poly([(0, 7), (17, 7), (15, 4), (2, 4)], lambda x, y, dx, dy: c.put(x, y, lit(CLOTH_RED, dx, dy, 6)))


PROP_BUILDERS = {
    "hs_boulder": ((25, 18), _p_boulder),
    "hs_cairn": ((15, 20), _p_cairn),
    "hs_hoodoo": ((19, 46), _p_hoodoo),
    "hs_log": ((30, 14), _p_log),
    "hs_agave": ((21, 16), _p_agave),
    "hs_yucca": ((19, 32), _p_yucca),
    "hs_ring": ((21, 12), _p_ring),
    "hs_board": ((18, 28), _p_board),
}


def make_prop(name):
    """(base, tint_or_None) for a Hollowsong prop. None has a tint layer: their colours are fixed."""
    (w, h), fn = PROP_BUILDERS[name]
    c = Canvas(w, h)
    fn(c)
    c.outline()
    return c.img, (c.tint if c.has_tint else None)


# ------------------------------------------------------------------ preview
def preview(path, scale=3):
    """A contact sheet: every tree, understory, prop, the tiles and the litter on a sand backdrop."""
    bg = (176, 138, 108, 255)
    items = []
    for spec in list(GROVE.values()) + list(GREAT.values()) + list(UNDERSTORY.values()):
        t, cnp = tree_parts(spec)
        im = cnp.copy() if t is None else t.copy()
        if t is not None:
            im.alpha_composite(cnp)
        items.append(im)
    for name in PROP_BUILDERS:
        items.append(make_prop(name)[0])
    atlas, _ = detail_atlas()
    items += [atlas, pool_tile().resize((64, 64), Image.NEAREST), rock_tile(), top_tile()]
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
