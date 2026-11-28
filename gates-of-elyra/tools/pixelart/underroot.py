"""
Underroot -- the caves beneath the great tree -- pixel art: hanging root pillars and mossy mounds, pale cave
fungus, the loam and mud of a cave floor, a seamless tangle-of-roots wall tile, a still black pool, and the
small things lying about (glow-moss, glowcaps, stalagmites, a cold lantern, a tiny door in a root...).

The look is the meadow worlds' own language (a lit blob under the upper-left light, the shared 1px outline)
in a hushed, close palette: earth browns and blue-blacks, with the only bright things being the soft green-gold
glow of the moss and the fungus. The darkness itself is not art: it is MistVeil's veil, laid over the view
(tuned by the spec's atmosphere.fog), so everything here is drawn in a dim, readable light that the veil then
takes away from.

Most of it is built from machinery the other worlds already have:
  * trees   -- trees.make_grove_parts with new foliage/bark ramps (the willow shape's hanging strands make
               a fine hanging-root pillar; "round" with a moss ramp makes a mossy mound);
  * ground  -- the seamless terrain atlas in ground.py's layout (R = shade role, G = accent), plus a detail
               atlas of cave litter;
  * water   -- one new ramp for water.py: a black, still pool;
  * props   -- small procedural sprites on nocthollow.py's Canvas, BASE + optional TINT (the tint layer is
               the part that glows: the client colours it per instance, so one sprite serves any hue);
  * the wall -- one small seamless tile of tangled roots, laid along every tunnel wall as the maze's hedge.

Everything is deterministic (seeded by name), so re-running reproduces the PNGs byte for byte.
Baked by tools/gen_underroot.py.
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
    # hanging roots, as the willow's "foliage": warm earth browns with a pale lit side
    "ur_root":   ((46, 30, 26), (84, 56, 40), (140, 100, 68)),
    "ur_root2":  ((40, 28, 30), (72, 52, 44), (122, 92, 70)),
    # moss: a deep teal-green with a soft bright edge
    "ur_moss":   ((18, 46, 42), (36, 84, 70), (92, 156, 120)),
    # pale cave fungus, violet-grey
    "ur_fungus": ((54, 40, 74), (100, 78, 128), (168, 146, 196)),
})
trees.BARK.update({
    "ur_bark": ((30, 20, 18), (58, 40, 30), (98, 70, 50)),
})

GROVE = {
    "pillar_a": ("willow", 1, "ur_root", "ur_bark", None),
    "pillar_b": ("willow", 3, "ur_root2", "ur_bark", None),
    "pillar_c": ("willow", 5, "ur_root", "ur_bark", None),
    "mound_a":  ("round", 1, "ur_moss", "ur_bark", None),
    "mound_b":  ("round", 2, "ur_moss", "ur_bark", None),
    "fungus_a": ("round", 4, "ur_fungus", "ur_bark", None),
    "fungus_b": ("round", 6, "ur_fungus", "ur_bark", None),
    # a thinner crystal-clear hanging root, for the narrow places
    "rootlet_a": ("birch", 1, "ur_root2", "ur_bark", None),
}
GREAT = {
    "great_root": ("great_willow", 11, "ur_root", "ur_bark", None),
    "great_moss": ("great_round", 12, "ur_moss", "ur_bark", None),
}
UNDERSTORY = {
    "fern_a": ("bush", 1, "ur_moss", "ur_bark", None),
    "fern_b": ("bush", 2, "ur_root2", "ur_bark", None),
    "stump":  ("stump", 1, "ur_moss", "ur_bark", None),
}


def tree_parts(spec):
    return trees.make_grove_parts(*spec)


# ------------------------------------------------------------------ the ground
TILE = ground.TILE
KINDS = ground.KINDS


def _terrain(kind):
    """(shade_grid, accent_grid) for one cave-floor mood: base shade 2 with a fine grain of dark pits (1)
    and lit flecks (3). Only FINE detail is baked in; the broad swells are the shader's."""
    rng = random.Random("underroot-ground-" + kind)
    base = 1 if kind == "dirt" else 2
    g = [[base] * TILE for _ in range(TILE)]
    acc = [[0] * TILE for _ in range(TILE)]
    # (pits, flecks, runs): loam is dense and dark; moss is soft; dusty roots are paler and flecked; mud is
    # dark and speckled; pale clay (the paths) is smooth and glints a little.
    mix_by_kind = {
        "grass":  (190, 60, 14),
        "lush":   (210, 80, 26),
        "meadow": (120, 110, 40),
        "dirt":   (260, 40, 4),
        "sand":   (50, 130, 10),
    }
    n_pit, n_fleck, n_run = mix_by_kind[kind]
    for _ in range(n_pit):
        ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_pit // 3):
        ground._stamp(g, [(0, 0, 1), (1, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_fleck):
        ground._stamp(g, [(0, 0, 3)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_run):
        # a short rootlet streak: a lit pixel with a dark one under it
        x0, y0 = rng.randrange(TILE), rng.randrange(TILE)
        for k in range(rng.randint(2, 5)):
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


MOSS = ((26, 62, 50), (50, 112, 82), (110, 176, 118))
GLOW = ((32, 96, 92), (84, 196, 166), (200, 255, 220))       # glow-moss: its lit pixels are the light
ROOT = ((46, 30, 24), (84, 58, 40), (136, 100, 68))
STONE_D = ((34, 36, 48), (62, 66, 82), (104, 110, 128))
CLAY = ((92, 70, 52), (132, 104, 78), (178, 148, 112))
CAP = ((120, 100, 150), (176, 156, 204), (226, 214, 240))
PUDDLE = ((20, 34, 50), (36, 62, 84), (96, 140, 164))
BONE = ((150, 138, 118), (200, 190, 168), (240, 232, 212))
SEED_P = ((120, 90, 40), (196, 150, 60), (250, 220, 130))

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
    "glowpatch": (GLOW, False, [
        "..2.2..",
        ".23332.",
        "2333332",
        ".23332.",
        "..222..",
    ]),
    "glowspeck": (GLOW, False, [
        ".3.",
        "323",
        ".3.",
    ]),
    "rootlet": (ROOT, False, [
        "3.....",
        ".32...",
        "..2231",
        "....21",
    ]),
    "rootlet_b": (ROOT, False, [
        "..3.2.",
        ".32.2.",
        "32.22.",
        "2..21.",
    ]),
    "pebbles": (STONE_D, False, [
        ".33..3",
        ".21.31",
        "......",
        "..32..",
        "..21..",
    ]),
    "stone": (STONE_D, True, [
        ".3332..",
        "332222.",
        "3222221",
        ".22111.",
    ]),
    "cap": (CAP, False, [
        ".333.",
        "32222",
        ".2.1.",
        "..2..",
    ]),
    "capcluster": (CAP, False, [
        ".33...3..",
        "3222.322.",
        ".2...2.1.",
        ".2.3.2...",
        "...222...",
    ]),
    "puddle": (PUDDLE, False, [
        "..2222...",
        ".223322..",
        "222222221",
        ".2222211.",
    ]),
    "bone": (BONE, False, [
        "3.....3",
        ".22222.",
        "3.....3",
    ]),
    "seedpod": (SEED_P, False, [
        ".33.",
        "3221",
        ".21.",
    ]),
    "clayflake": (CLAY, False, [
        ".33.",
        "3221",
        ".11.",
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
# A still, black pool, with a faint cold glint where the drips fall.
water.RAMPS["ur_pool"] = ((0.03, 0.06, 0.10), (0.06, 0.12, 0.18), (0.22, 0.40, 0.46))


def pool_tile():
    return water.make_water_tile("ur_pool")


# ------------------------------------------------------------------ the tunnel wall: a tangle of roots
WALL_SOIL = (24, 17, 17)
WALL_ROOT = ((56, 38, 28), (96, 68, 46), (148, 110, 76))
_BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def root_wall_tile():
    """32 x 32, seamless: thick roots weaving through dark soil. Two sets of strands cross at INTEGER
    frequencies (so the tile repeats with no seam), each wobbling as it runs; where a strand's centre passes
    the root is lit, its edges fall into shadow. Fully opaque: the wall is a solid thing. The client lays it
    on the tunnel walls (the maze's hedge slot), darkening the front face."""
    T = 32
    img = Image.new("RGBA", (T, T), WALL_SOIL + (255,))
    px = img.load()
    for y in range(T):
        for x in range(T):
            a = 2 * math.pi * (2.0 * x / T + 0.30 * math.sin(2 * math.pi * y / T + 0.6))
            b = 2 * math.pi * (3.0 * y / T + 0.22 * math.sin(2 * math.pi * 2.0 * x / T + 1.9))
            s1 = abs(math.cos(a))
            s2 = abs(math.cos(b))
            s = max(s1, s2 * 0.96)
            d = (_BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.10
            if s + d > 0.70:
                edge = (s + d - 0.70) / 0.30     # 0 at the strand's edge, 1 at its centre
                role = 2 if edge > 0.72 else (0 if edge < 0.22 else 1)
                px[x, y] = WALL_ROOT[role] + (255,)
            elif ((x * 7 + y * 13) % 11) == 0:
                px[x, y] = (34, 24, 22, 255)      # a grain of soil
    return img


# ------------------------------------------------------------------ props
BARK_D = ((0.14, 0.09, 0.07), (0.26, 0.17, 0.12), (0.42, 0.30, 0.20))
ROCK = ((0.13, 0.14, 0.19), (0.24, 0.26, 0.32), (0.40, 0.43, 0.50))
MOSSY = ((0.10, 0.22, 0.19), (0.19, 0.38, 0.30), (0.34, 0.58, 0.42))
IRON = ((0.12, 0.12, 0.15), (0.22, 0.22, 0.27), (0.38, 0.38, 0.44))
STEM = ((0.50, 0.46, 0.58), (0.72, 0.68, 0.80), (0.90, 0.88, 0.96))
SEEDLING = ((0.52, 0.64, 0.50), (0.74, 0.86, 0.66), (0.92, 0.98, 0.84))
DOORWOOD = ((0.30, 0.20, 0.14), (0.50, 0.34, 0.22), (0.68, 0.50, 0.34))
BRASS = (0.78, 0.64, 0.30)


def _p_glowmoss(c):
    """A low, flat patch of moss whose lit pixels are the light (the tint layer: coloured per instance)."""
    gy = c.h - 2
    c.ellipse(11, gy - 2, 10, 3.4, lambda x, y, dx, dy: c.put(x, y, lit(MOSSY, dx, dy, 8)))
    for px, py in [(4, gy - 3), (8, gy - 4), (12, gy - 4), (16, gy - 3), (6, gy - 1), (11, gy - 2), (15, gy - 1), (9, gy - 3), (3, gy - 1), (18, gy - 2)]:
        c.tint_px(px, py, "3" if (px + py) % 3 else "2")


def _p_glowcap(c):
    """Three small mushrooms, their caps glowing (tint layer)."""
    gy = c.h - 2
    for x0, h, r in [(4, 6, 3.4), (9, 9, 4.4), (14, 5, 3.0)]:
        c.ellipse(x0, gy, 1.2, 0.6, lambda x, y, dx, dy: c.put(x, y, STEM[1]))
        for y in range(gy - h, gy + 1):
            c.put(x0, y, STEM[2])
            c.put(x0 + 1, y, STEM[0])
        c.ellipse(x0 + 0.5, gy - h, r, r * 0.7, lambda x, y, dx, dy, rr=r: c.tint_px(x, y, _role_(dx, dy, rr)), top_only=True)


def _role_(dx, dy, r):
    t = (-dx - dy) / max(1.0, r * 1.3)
    return "3" if t > 0.32 else ("1" if t < -0.34 else "2")


def _p_drip(c):
    """A stalagmite with a ring of wet at its foot and a single bright drop falling (the tint)."""
    gy = c.h - 2
    cx = c.w // 2
    c.ellipse(cx, gy - 1, 6.2, 2.0, lambda x, y, dx, dy: c.put(x, y, PUDDLE_F(dx, dy)))
    c.poly([(cx - 5, gy - 1), (cx - 3, gy - 9), (cx - 1, gy - 17), (cx, gy - 21), (cx + 2, gy - 15), (cx + 4, gy - 8), (cx + 6, gy - 1)],
           lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx * 1.5, dy * 0.4, 6)))
    c.tint_px(cx + 5, gy - 12, "3")


def PUDDLE_F(dx, dy):
    return (0.10, 0.18, 0.26) if dy > -0.4 else (0.20, 0.34, 0.42)


def _p_rootknot(c):
    """A gnarled knot of root rising out of the floor and arching over, like a low doorway nobody uses."""
    gy = c.h - 2
    c.poly([(1, gy), (2, 8), (5, 2), (10, 1), (14, 4), (13, 9), (11, 5), (8, 5), (7, 12), (9, gy)],
           lambda x, y, dx, dy: c.put(x, y, lit(BARK_D, dx * 1.2, dy * 0.6, 8)))
    c.poly([(14, gy), (15, 10), (18, 3), (22, 2), (23, 8), (21, gy)],
           lambda x, y, dx, dy: c.put(x, y, lit(BARK_D, dx * 1.2, dy * 0.6, 7)))
    c.ellipse(11, gy, 10, 1.4, lambda x, y, dx, dy: c.put(x, y, MOSSY[0]) if y >= gy else None)
    for x, y in [(5, 3), (10, 2), (19, 3)]:
        c.put(x, y, MOSSY[2])


def _p_stone(c):
    gy = c.h - 2
    pts = [(2, gy), (1, 6), (4, 2), (10, 1), (15, 3), (18, 7), (17, gy)]
    c.poly(pts, lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx, dy * 0.7, 8)))
    c.poly([(3, 6), (4, 3), (10, 1), (15, 3), (17, 6), (12, 5), (9, 6), (6, 5)],
           lambda x, y, dx, dy: c.put(x, y, lit(MOSSY, dx, dy, 7)))


def _p_lantern(c):
    """An old iron lantern, long cold, sitting on the floor where someone set it down. Its glass is dark."""
    gy = c.h - 2
    cx = c.w // 2
    c.poly([(cx - 4, gy), (cx - 4, gy - 2), (cx + 4, gy - 2), (cx + 4, gy)], lambda x, y, dx, dy: c.put(x, y, lit(IRON, dx, dy, 4)))
    c.poly([(cx - 3, gy - 2), (cx - 3, gy - 11), (cx + 3, gy - 11), (cx + 3, gy - 2)], lambda x, y, dx, dy: c.put(x, y, (0.10, 0.14, 0.18), solid=False))
    for x in (cx - 3, cx + 3):
        c.line((x, gy - 2), (x, gy - 11), lambda xx, yy, dx, dy: c.put(xx, yy, IRON[2]))
    c.poly([(cx - 5, gy - 11), (cx + 5, gy - 11), (cx + 2, gy - 14), (cx - 2, gy - 14)], lambda x, y, dx, dy: c.put(x, y, lit(IRON, dx, dy, 5)))
    c.line((cx - 2, gy - 15), (cx + 2, gy - 15), lambda x, y, dx, dy: c.put(x, y, IRON[1]))
    c.line((cx, gy - 14), (cx, gy - 16), lambda x, y, dx, dy: c.put(x, y, IRON[2]))


def _p_sprout(c):
    """A pale seedling that has grown, with great effort, toward a light that is not here. The tip glows."""
    gy = c.h - 2
    cx = c.w // 2
    c.line((cx, gy), (cx, gy - 9), lambda x, y, dx, dy: c.put(x, y, SEEDLING[1]))
    c.ellipse(cx - 3, gy - 7, 3.0, 1.4, lambda x, y, dx, dy: c.put(x, y, lit(SEEDLING, dx, dy, 3)))
    c.ellipse(cx + 3, gy - 9, 3.0, 1.4, lambda x, y, dx, dy: c.put(x, y, lit(SEEDLING, dx, dy, 3)))
    c.tint_px(cx, gy - 10, "3")
    c.tint_px(cx, gy - 11, "2")
    c.ellipse(cx, gy, 3.6, 1.2, lambda x, y, dx, dy: c.put(x, y, MOSSY[1]))


def _p_door(c):
    """A tiny round door set into the side of a root, with a brass knob and one worn step. Someone small lives here."""
    gy = c.h - 2
    cx = c.w // 2
    c.poly([(cx - 8, gy), (cx - 7, 4), (cx - 3, 1), (cx + 3, 1), (cx + 7, 4), (cx + 8, gy)],
           lambda x, y, dx, dy: c.put(x, y, lit(BARK_D, dx, dy * 0.4, 10)))
    c.ellipse(cx, gy - 5, 4.0, 6.0, lambda x, y, dx, dy: c.put(x, y, lit(DOORWOOD, dx * 1.2, dy * 0.3, 5)))
    c.put(cx + 2, gy - 5, BRASS)
    c.line((cx - 3, gy - 9), (cx - 3, gy - 2), lambda x, y, dx, dy: c.put(x, y, DOORWOOD[0]))
    c.ellipse(cx, gy, 6, 1.4, lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx, dy, 5)))


def _p_cairn(c):
    gy = c.h - 2
    c.ellipse(5, gy - 1, 4.6, 2.0, lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx, dy, 4)))
    c.ellipse(5, gy - 4, 3.2, 1.6, lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx, dy, 3)))
    c.ellipse(5, gy - 6, 2.0, 1.2, lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx, dy, 2)))


PROP_BUILDERS = {
    "ur_glowmoss": ((22, 10), _p_glowmoss),
    "ur_glowcap": ((18, 16), _p_glowcap),
    "ur_drip": ((16, 26), _p_drip),
    "ur_rootknot": ((24, 20), _p_rootknot),
    "ur_stone": ((20, 14), _p_stone),
    "ur_lantern": ((14, 20), _p_lantern),
    "ur_sprout": ((12, 16), _p_sprout),
    "ur_door": ((18, 24), _p_door),
    "ur_cairn": ((11, 12), _p_cairn),
}


def make_prop(name):
    """(base, tint_or_None) for an Underroot prop."""
    (w, h), fn = PROP_BUILDERS[name]
    c = Canvas(w, h)
    fn(c)
    c.outline()
    return c.img, (c.tint if c.has_tint else None)


# ------------------------------------------------------------------ preview
def preview(path, scale=3):
    """A contact sheet: every tree, understory, prop, the tiles and the litter on a dark-earth backdrop."""
    bg = (52, 44, 40, 255)
    items = []
    for spec in list(GROVE.values()) + list(GREAT.values()) + list(UNDERSTORY.values()):
        t, cnp = tree_parts(spec)
        im = cnp.copy() if t is None else t.copy()
        if t is not None:
            im.alpha_composite(cnp)
        items.append(im)
    for name in PROP_BUILDERS:
        base, tint = make_prop(name)
        im = base.copy()
        if tint is not None:
            tinted = tint.copy()
            tp = tinted.load()
            for y in range(tinted.height):
                for x in range(tinted.width):
                    v = tp[x, y]
                    if v[3]:
                        k = v[0] / 255.0
                        tp[x, y] = (round(120 * k + 100 * k), round(255 * k), round(190 * k), 255)
            im.alpha_composite(tinted)
        items.append(im)
    atlas, _ = detail_atlas()
    items += [atlas, pool_tile().resize((64, 64), Image.NEAREST), root_wall_tile(), root_wall_tile().crop((0, 0, 32, 32))]
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
