"""
Steamhollow -- the bathhouse village lost in fog -- pixel art: cedars, maples and willows in a damp
green-grey light, the mossy ground and wet stone the village is built on, the planks of its boardwalks,
the timber and tile of its bathhouses, a milky hot-spring surface, and the small things lying about
(lanterns, buckets, stools, towel racks, steam vents, a notice board). The look is the meadow worlds'
own language (a lit blob under the upper-left light, the shared 1px outline) in a warm, damp palette:
lamplight amber against fog-blue, deep teal-green cedar, maple red and gold.

Most of it is built from machinery the other worlds already have:
  * trees   -- trees.make_grove_parts with new foliage/bark ramps (the grove's shapes);
  * ground  -- the seamless terrain atlas in ground.py's layout (R = shade role, G = accent), with
               moss's fine grain, plus a detail atlas of damp litter;
  * water   -- one new ramp for water.py: milky hot-spring water;
  * props   -- small procedural sprites on nocthollow.py's Canvas, BASE + optional TINT;
  * planks / wall / roof tiles -- small seamless greyscale-or-colour tiles drawn here.

Everything is deterministic (seeded by name), so re-running reproduces the PNGs byte for byte.
Baked by tools/gen_steamhollow.py.
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
    # cedars: deep teal-green needles, the lit side silvered by the mist
    "cedar":      ((22, 52, 48), (40, 84, 70), (92, 140, 114)),
    "cedar2":     ((28, 58, 54), (52, 94, 82), (108, 152, 128)),
    # maples at their turn: red, and a gold one
    "maple":      ((118, 34, 34), (184, 70, 44), (238, 140, 82)),
    "maple_gold": ((150, 92, 30), (206, 150, 52), (246, 208, 112)),
    # soft misty broadleaves, grey-green
    "mist":       ((56, 86, 80), (94, 128, 114), (152, 182, 160)),
    "willow_sh":  ((60, 96, 84), (100, 142, 118), (158, 194, 166)),
})
trees.BARK.update({
    "wet": ((46, 36, 34), (78, 62, 52), (122, 100, 84)),
})

GROVE = {
    "cedar_a": ("pine", 1, "cedar", "wet", None),
    "cedar_b": ("pine", 2, "cedar2", "wet", None),
    "cedar_c": ("pine", 3, "cedar", "wet", None),
    "cedar_d": ("pine", 4, "cedar2", "wet", None),
    "maple_a": ("oak", 1, "maple", "wet", None),
    "maple_b": ("oak", 2, "maple", "wet", None),
    "maple_c": ("round", 6, "maple_gold", "wet", None),
    "mist_a":  ("round", 1, "mist", "wet", None),
    "mist_b":  ("round", 2, "mist", "wet", None),
    "willow_a": ("willow", 1, "willow_sh", "wet", None),
    "willow_b": ("willow", 3, "willow_sh", "wet", None),
}
GREAT = {
    "great_maple": ("great_oak", 7, "maple", "wet", None),
    "great_willow": ("great_willow", 9, "willow_sh", "wet", None),
}
UNDERSTORY = {
    "bush_a": ("bush", 1, "mist", "wet", None),
    "bush_b": ("bush", 2, "cedar2", "wet", None),
    "stump":  ("stump", 1, "mist", "wet", None),
}


def tree_parts(spec):
    return trees.make_grove_parts(*spec)


# ------------------------------------------------------------------ the ground
TILE = ground.TILE
KINDS = ground.KINDS


def _terrain(kind):
    """(shade_grid, accent_grid) for one damp-ground mood: base shade 2 with a fine grain of dark
    dimples (1) and lit flecks (3). Only FINE detail is baked in; the broad swells are the shader's."""
    rng = random.Random("steamhollow-ground-" + kind)
    base = 1 if kind == "dirt" else 2
    g = [[base] * TILE for _ in range(TILE)]
    acc = [[0] * TILE for _ in range(TILE)]
    # (dimples, flecks, runs): moss is dense and soft; ferny meadow is paler and flecked; wet earth is
    # dark and speckled; the mineral shore (sand) is smooth and glints.
    mix_by_kind = {
        "grass":  (150, 90, 24),
        "lush":   (220, 70, 30),
        "meadow": (90, 130, 50),
        "dirt":   (250, 60, 6),
        "sand":   (40, 170, 18),
    }
    n_dim, n_fleck, n_run = mix_by_kind[kind]
    for _ in range(n_dim):
        ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_dim // 3):
        ground._stamp(g, [(0, 0, 1), (1, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_fleck):
        ground._stamp(g, [(0, 0, 3)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_run):
        # a short mossy streak: a lit pixel with a dark one under it
        x0, y0 = rng.randrange(TILE), rng.randrange(TILE)
        for k in range(rng.randint(2, 4)):
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


MOSS = ((44, 74, 52), (84, 124, 76), (140, 178, 104))
FERN = ((38, 78, 62), (70, 124, 92), (128, 176, 132))
WET_STONE = ((70, 76, 90), (112, 120, 136), (170, 178, 192))
MAPLE_LEAF = ((140, 40, 32), (204, 78, 44), (240, 150, 84))
GINKGO = ((170, 124, 36), (224, 184, 64), (250, 226, 130))
TWIG = ((52, 40, 34), (88, 70, 58), (132, 110, 92))
REED = ((70, 96, 76), (124, 152, 112), (182, 204, 156))
MINERAL = ((176, 172, 150), (222, 218, 196), (250, 248, 236))
SHELL = ((120, 132, 150), (176, 188, 204), (232, 238, 246))

DETAILS = {
    "mosstuft_a": (MOSS, False, [
        "..3...",
        ".32.3.",
        ".2.32.",
        "12.21.",
        "1211..",
    ]),
    "mosstuft_b": (MOSS, False, [
        ".3..3..",
        ".2.32..",
        "32.2.3.",
        "2.12.2.",
        "21121..",
    ]),
    "fern": (FERN, False, [
        "..3...3..",
        ".32..32..",
        "3.23.2.3.",
        "..22322..",
        "...212...",
        "....1....",
    ]),
    "sprout": (FERN, False, [
        ".3.",
        "322",
        ".2.",
        ".1.",
    ]),
    "pebbles": (WET_STONE, False, [
        ".33..3",
        ".21.31",
        "......",
        "..32..",
        "..21..",
    ]),
    "wetstone": (WET_STONE, True, [
        ".3332..",
        "332222.",
        "3222221",
        ".22111.",
    ]),
    "mapleleaf": (MAPLE_LEAF, False, [
        ".3.3.",
        "32223",
        ".222.",
        "..1..",
    ]),
    "ginkgo": (GINKGO, False, [
        ".333.",
        "32222",
        ".211.",
        "..1..",
    ]),
    "twig": (TWIG, False, [
        "3.3....",
        ".23..3.",
        "..2232.",
        "....21.",
    ]),
    "reed": (REED, False, [
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
    "mineral": (MINERAL, False, [
        "..3.3..",
        ".32232.",
        "3222223",
        ".21212.",
    ]),
    "shell": (SHELL, False, [
        ".33.",
        "3221",
        ".21.",
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
# A hot spring: milky, warm blue-green water whose glints are the lamplight.
water.RAMPS["onsen"] = ((0.20, 0.50, 0.50), (0.36, 0.70, 0.68), (0.80, 0.96, 0.90))


def onsen_tile():
    return water.make_water_tile("onsen")


# ------------------------------------------------------------------ planks, walls and roofs (tiles)
PLANK = ((88, 60, 42), (132, 94, 64), (172, 130, 92))     # dark, base, light
PLANK_SEAM = (52, 34, 26)


def boards_tile(horizontal=True):
    """32 x 32 of weathered boards with staggered end joints. horizontal=True: boards run along x (a
    walkway going east-west); False: along y (north-south). Seamless; the colours are baked (tint it
    white)."""
    rng = random.Random("sh-boards")
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 255))
    px = img.load()
    strips = 4
    for s in range(strips):
        y0 = s * 8
        shade = rng.choice([0, 0, 1, -1])
        joint = rng.randrange(32)
        for y in range(8):
            for x in range(32):
                if y == 0:
                    c = PLANK_SEAM
                elif y == 1:
                    c = PLANK[2]
                elif y == 7:
                    c = PLANK[0]
                else:
                    c = PLANK[1]
                if 1 < y < 7 and shade:
                    c = tuple(max(0, min(255, v + shade * 9)) for v in c)
                if x == joint and y > 0:
                    c = PLANK_SEAM
                px[x, y0 + y] = c + (255,)
        # grain: short dashes along the board
        for _ in range(7):
            gx, gy = rng.randrange(30), y0 + rng.randint(2, 6)
            col = PLANK[0] if rng.random() < 0.6 else PLANK[2]
            for k in range(rng.randint(2, 4)):
                px[(gx + k) % 32, gy] = col + (255,)
        # a nail at each end of the joint
        for nx in ((joint + 3) % 32, (joint - 3) % 32):
            px[nx, y0 + 3] = (60, 50, 46, 255)
    if not horizontal:
        img = img.transpose(Image.TRANSPOSE)
    return img


def wall_tile():
    """24 x 24 greyscale board-and-batten (vertical planks, 6 px each), multiplied by the building's wall
    colour in BuildingView. A dark seam, a lit left edge and a little grain on each board."""
    rng = random.Random("sh-wall")
    img = Image.new("RGBA", (24, 24), (0, 0, 0, 255))
    px = img.load()
    for b in range(4):
        tone = rng.uniform(-0.05, 0.05)
        for y in range(24):
            for x in range(6):
                v = 0.80 + tone
                if x == 0:
                    v = 0.50
                elif x == 1:
                    v = 0.96
                elif x == 5:
                    v = 0.70
                g = round(max(0.0, min(1.0, v)) * 255)
                px[b * 6 + x, y] = (g, g, g, 255)
        for _ in range(5):
            gy, gx = rng.randrange(20), b * 6 + rng.randint(2, 4)
            for k in range(rng.randint(2, 5)):
                g = round(0.64 * 255)
                px[gx, (gy + k) % 24] = (g, g, g, 255)
    return img


def roof_tile():
    """24 x 12 greyscale kawara roof tiles: scalloped courses, offset each row, a lit crest on each tile
    and a dark seam under its curved edge. Multiplied by the roof colour in BuildingView."""
    img = Image.new("RGBA", (24, 12), (0, 0, 0, 255))
    px = img.load()
    for y in range(12):
        row, ry = divmod(y, 6)
        off = 3 * (row % 2)
        for x in range(24):
            tx = (x + off) % 6
            v = 0.78
            if ry <= 1 and 1 <= tx <= 3:
                v = 1.0
            elif ry == 5 and 1 <= tx <= 4:
                v = 0.40
            elif ry == 4 and tx in (0, 5):
                v = 0.40
            elif tx in (0, 5) and ry >= 1:
                v = 0.62
            g = round(v * 255)
            px[x, y] = (g, g, g, 255)
    return img


# ------------------------------------------------------------------ props
WOOD = ((0.26, 0.18, 0.13), (0.44, 0.32, 0.22), (0.62, 0.48, 0.34))
DARKWOOD = ((0.16, 0.11, 0.09), (0.28, 0.20, 0.15), (0.42, 0.32, 0.24))
STONE = ((0.34, 0.36, 0.42), (0.52, 0.55, 0.62), (0.72, 0.75, 0.80))
MOSSY = ((0.16, 0.26, 0.20), (0.28, 0.44, 0.30), (0.46, 0.64, 0.42))
LAMP = (1.0, 0.84, 0.50)
LAMP_HOT = (1.0, 0.95, 0.74)
PAPER_RED = ((0.62, 0.22, 0.16), (0.88, 0.40, 0.24), (1.0, 0.62, 0.38))
CLOTH = ((0.80, 0.78, 0.72), (0.94, 0.92, 0.86), (1.0, 1.0, 0.96))
INDIGO = ((0.14, 0.18, 0.36), (0.22, 0.28, 0.52), (0.36, 0.42, 0.70))
HOOP = (0.58, 0.52, 0.42)


def _p_lantern(c):
    """A tall wooden post with a glowing paper lantern hung from a short arm. The light is data on the
    client side (prop_lights); here the paper itself is drawn lit."""
    gy = c.h - 2
    c.poly([(5, gy), (5, 3), (7, 3), (7, gy)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx * 2, dy * 0.3, 3)))
    c.poly([(5, 4), (12, 4), (12, 6), (5, 6)], lambda x, y, dx, dy: c.put(x, y, lit(DARKWOOD, dx, dy, 4)))
    c.line((11, 6), (11, 8), lambda x, y, dx, dy: c.put(x, y, DARKWOOD[1]))
    c.ellipse(11, 12, 3.4, 4.6, lambda x, y, dx, dy: c.put(x, y, mix(LAMP, LAMP_HOT, max(0.0, 1.0 - (abs(dx) + abs(dy)) / 3.0))))
    c.line((8, 9), (14, 9), lambda x, y, dx, dy: c.put(x, y, PAPER_RED[0]))
    c.line((8, 15), (14, 15), lambda x, y, dx, dy: c.put(x, y, PAPER_RED[0]))
    c.ellipse(6, gy, 3.2, 1.2, lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy, 3)))


def _p_stone_lantern(c):
    """A stone toro: a base, a post, a firebox with a glowing window, a roofed cap and a finial."""
    gy = c.h - 2
    cx = c.w // 2
    c.poly([(cx - 5, gy), (cx - 4, gy - 3), (cx + 4, gy - 3), (cx + 5, gy)], lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy * 0.4, 6)))
    c.poly([(cx - 2, gy - 3), (cx - 2, gy - 10), (cx + 2, gy - 10), (cx + 2, gy - 3)], lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx * 1.6, dy * 0.2, 3)))
    c.poly([(cx - 5, gy - 10), (cx + 5, gy - 10), (cx + 4, gy - 12), (cx - 4, gy - 12)], lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy, 5)))
    c.poly([(cx - 4, gy - 12), (cx + 4, gy - 12), (cx + 4, gy - 18), (cx - 4, gy - 18)], lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy, 6)))
    c.poly([(cx - 2, gy - 13), (cx + 2, gy - 13), (cx + 2, gy - 17), (cx - 2, gy - 17)], lambda x, y, dx, dy: c.put(x, y, mix(LAMP, LAMP_HOT, 0.5), solid=False))
    c.poly([(cx - 7, gy - 18), (cx + 7, gy - 18), (cx + 4, gy - 21), (cx - 4, gy - 21)], lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy * 0.6, 7)))
    c.disc(cx, gy - 22, 1.6, lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy, 2)))
    c.ellipse(cx - 2, gy - 18, 2, 1, lambda x, y, dx, dy: c.put(x, y, MOSSY[1]) if y > gy - 20 else None, top_only=True)


def _p_bucket(c):
    """A small wooden bath bucket with two iron-ish hoops and a ladle across its brim."""
    gy = c.h - 2
    c.poly([(2, gy), (1, 3), (11, 3), (10, gy)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx * 1.4, dy * 0.3, 5)))
    c.ellipse(6, 3, 5, 1.6, lambda x, y, dx, dy: c.put(x, y, WOOD[2] if dy < 0 else (0.62, 0.78, 0.80)))
    for yy in (5, gy - 2):
        c.line((1, yy), (11, yy), lambda x, y, dx, dy: c.put(x, y, HOOP))
    c.line((0, 1), (9, 2), lambda x, y, dx, dy: c.put(x, y, DARKWOOD[2]))


def _p_stool(c):
    """A low bath stool, three-legged."""
    gy = c.h - 2
    c.ellipse(6, gy - 5, 5.4, 1.8, lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx, dy, 4)))
    for lx in (2, 6, 10):
        c.line((lx, gy - 4), (lx + (1 if lx > 6 else 0), gy), lambda x, y, dx, dy: c.put(x, y, DARKWOOD[1]))


def _p_mossrock(c):
    gy = c.h - 2
    pts = [(2, gy), (1, 8), (4, 3), (10, 1), (17, 3), (20, 8), (19, gy)]
    c.poly(pts, lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy * 0.7, 9)))
    c.poly([(3, 7), (4, 3), (10, 1), (17, 3), (19, 6), (14, 5), (10, 7), (6, 6)],
           lambda x, y, dx, dy: c.put(x, y, lit(MOSSY, dx, dy, 8)))
    c.ellipse(10, gy, 9, 1.6, lambda x, y, dx, dy: c.put(x, y, MOSSY[0]) if y >= gy else None)


def _p_bench(c):
    """A plank bench with two stout legs."""
    gy = c.h - 2
    c.poly([(1, gy - 6), (27, gy - 6), (27, gy - 9), (1, gy - 9)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx * 0.2, dy * 2, 6)))
    for lx in (4, 22):
        c.poly([(lx, gy - 6), (lx + 2, gy - 6), (lx + 2, gy), (lx, gy)], lambda x, y, dx, dy: c.put(x, y, lit(DARKWOOD, dx, dy * 0.2, 3)))
    c.line((2, gy - 9), (26, gy - 9), lambda x, y, dx, dy: c.put(x, y, WOOD[2]))


def _p_towel_rack(c):
    """A drying rack: two posts, a crossbar and towels (cream and indigo) hanging in the damp."""
    gy = c.h - 2
    for lx in (3, 26):
        c.poly([(lx, 4), (lx + 2, 4), (lx + 2, gy), (lx, gy)], lambda x, y, dx, dy: c.put(x, y, lit(DARKWOOD, dx * 1.4, dy * 0.1, 3)))
    c.poly([(2, 4), (29, 4), (29, 6), (2, 6)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx * 0.2, dy * 2, 4)))
    for x0, w, h, ramp in [(6, 6, 13, CLOTH), (14, 5, 15, INDIGO), (21, 4, 11, CLOTH)]:
        c.poly([(x0, 6), (x0 + w, 6), (x0 + w, 6 + h), (x0, 6 + h)], lambda x, y, dx, dy, ramp=ramp: c.put(x, y, lit(ramp, dx * 1.2, dy * 0.2, 6)))
        c.line((x0, 6 + h - 1), (x0 + w, 6 + h - 1), lambda x, y, dx, dy, ramp=ramp: c.put(x, y, ramp[0]))


def _p_steam_vent(c):
    """A low ring of wet stone round a dark hole, a pale mineral crust on the rim."""
    gy = c.h - 2
    c.ellipse(8, gy - 2, 7.4, 3.6, lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy * 1.2, 6)))
    c.ellipse(8, gy - 3, 4.6, 2.0, lambda x, y, dx, dy: c.put(x, y, (0.08, 0.10, 0.14), solid=False))
    for x, y in [(3, gy - 4), (5, gy - 6), (12, gy - 5), (13, gy - 3)]:
        c.put(x, y, (0.92, 0.90, 0.78))


def _p_jizo(c):
    """A small stone guardian figure, mossy at the foot, wearing a faded red bib."""
    gy = c.h - 2
    c.poly([(2, gy), (3, gy - 8), (9, gy - 8), (10, gy)], lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy * 0.5, 6)))
    c.disc(6, gy - 11, 3.2, lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy, 4)))
    c.poly([(4, gy - 8), (8, gy - 8), (7, gy - 5), (5, gy - 5)], lambda x, y, dx, dy: c.put(x, y, PAPER_RED[1]))
    c.ellipse(6, gy, 5, 1.4, lambda x, y, dx, dy: c.put(x, y, MOSSY[1]) if y >= gy - 1 else None)


def _p_board(c):
    """A notice board: two posts, a plank face with a few lines of faded 'writing' and a little roof."""
    gy = c.h - 2
    for lx in (2, 13):
        c.poly([(lx, 6), (lx + 2, 6), (lx + 2, gy), (lx, gy)], lambda x, y, dx, dy: c.put(x, y, lit(DARKWOOD, dx * 1.4, dy * 0.1, 3)))
    c.poly([(1, 7), (16, 7), (16, 19), (1, 19)], lambda x, y, dx, dy: c.put(x, y, lit(WOOD, dx * 0.4, dy * 0.4, 8)))
    for yy in (10, 13, 16):
        c.line((4, yy), (13 - (yy % 3), yy), lambda x, y, dx, dy: c.put(x, y, DARKWOOD[1]))
    c.poly([(0, 7), (17, 7), (15, 4), (2, 4)], lambda x, y, dx, dy: c.put(x, y, lit(INDIGO, dx, dy, 6)))


PROP_BUILDERS = {
    "sh_lantern": ((16, 34), _p_lantern),
    "sh_stone_lantern": ((16, 28), _p_stone_lantern),
    "sh_bucket": ((13, 12), _p_bucket),
    "sh_stool": ((13, 12), _p_stool),
    "sh_mossrock": ((22, 17), _p_mossrock),
    "sh_bench": ((30, 14), _p_bench),
    "sh_towel_rack": ((31, 30), _p_towel_rack),
    "sh_steam_vent": ((17, 12), _p_steam_vent),
    "sh_jizo": ((13, 18), _p_jizo),
    "sh_board": ((18, 28), _p_board),
}


def make_prop(name):
    """(base, tint_or_None) for a Steamhollow prop. None has a tint layer: their colours are fixed."""
    (w, h), fn = PROP_BUILDERS[name]
    c = Canvas(w, h)
    fn(c)
    c.outline()
    return c.img, (c.tint if c.has_tint else None)


# ------------------------------------------------------------------ preview
def preview(path, scale=3):
    """A contact sheet: every tree, understory, prop, the tiles and the litter on a damp-green backdrop."""
    bg = (96, 122, 104, 255)
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
    items += [atlas, onsen_tile().resize((64, 64), Image.NEAREST), boards_tile(True), boards_tile(False), wall_tile(), roof_tile()]
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
