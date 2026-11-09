"""
Lanternfold -- the shadow-puppet world -- pixel art: flat, layered paper-cut silhouettes against a warm amber
sky, every one of them lit by a single great lantern.

The look is ONE idea: things are CUT OUT. Trees are dark umber silhouettes in three depths (the near layer
almost black, the middle a burnt sienna, the far layer a pale apricot that has half dissolved into the light),
the ground is warm paper with a fibre grain, and the small things (houses, posts, a puppeteer's cart, a
puppet on a stick) are flat cut shapes with a little warm window-light in them. The only thing that glows
is the lantern, and what it lights.

Built from machinery the other worlds already have:
  * trees   -- trees.make_grove_parts with new, deliberately FLAT foliage ramps (three tones a hair apart, so
               a canopy reads as one cut shape) in the three depths;
  * ground  -- the seamless terrain atlas in ground.py's layout (R = shade role, G = accent) with a paper-fibre
               grain, plus a detail atlas of paper scraps;
  * water   -- one new ramp for water.py: an inky mirror holding amber glints;
  * props   -- small procedural sprites on nocthollow.py's Canvas, BASE + optional TINT, with GLOW pixels for
               lamplight (opaque but never outlined).

Everything is deterministic (seeded by name), so re-running reproduces the PNGs byte for byte.
Baked by tools/gen_lanternfold.py.
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
# Flat on purpose: the three tones of a ramp sit close together, so a canopy reads as one cut shape.
trees.FOLIAGE.update({
    "paper_near": ((30, 15, 13), (42, 21, 17), (62, 34, 26)),
    "paper_mid":  ((86, 42, 28), (112, 58, 36), (140, 80, 46)),
    "paper_far":  ((176, 104, 60), (198, 124, 72), (222, 152, 90)),
})
trees.BARK.update({
    "paper_trunk": ((26, 14, 12), (40, 22, 18), (58, 34, 26)),
    "paper_trunk_far": ((150, 88, 52), (170, 104, 60), (194, 126, 74)),
})

GROVE = {
    "near_pine_a":  ("pine", 1, "paper_near", "paper_trunk", None),
    "near_pine_b":  ("pine", 2, "paper_near", "paper_trunk", None),
    "near_pine_c":  ("pine", 4, "paper_near", "paper_trunk", None),
    "near_round_a": ("round", 1, "paper_near", "paper_trunk", None),
    "near_oak_a":   ("oak", 1, "paper_near", "paper_trunk", None),
    "mid_pine_a":   ("pine", 3, "paper_mid", "paper_trunk", None),
    "mid_round_a":  ("round", 2, "paper_mid", "paper_trunk", None),
    "mid_oak_a":    ("oak", 2, "paper_mid", "paper_trunk", None),
    "mid_willow_a": ("willow", 1, "paper_mid", "paper_trunk", None),
    "far_pine_a":   ("pine", 2, "paper_far", "paper_trunk_far", None),
    "far_round_a":  ("round", 3, "paper_far", "paper_trunk_far", None),
    "far_oak_a":    ("oak", 3, "paper_far", "paper_trunk_far", None),
}
GREAT = {
    "great_near": ("great_oak", 7, "paper_near", "paper_trunk", None),
    "great_mid":  ("great_willow", 9, "paper_mid", "paper_trunk", None),
}
UNDERSTORY = {
    "bush_a": ("bush", 1, "paper_near", "paper_trunk", None),
    "bush_b": ("bush", 2, "paper_mid", "paper_trunk", None),
    "stump":  ("stump", 1, "paper_near", "paper_trunk", None),
}


def tree_parts(spec):
    return trees.make_grove_parts(*spec)


# ------------------------------------------------------------------ the ground: warm paper
TILE = ground.TILE
KINDS = ground.KINDS


def _terrain(kind):
    """(shade_grid, accent_grid) for one paper mood: base shade 2 with a fine fibre grain (short pale strokes
    and the odd dark fleck). Only FINE detail is baked in; the broad swells are the shader's."""
    rng = random.Random("lanternfold-ground-" + kind)
    base = 1 if kind == "dirt" else 2
    g = [[base] * TILE for _ in range(TILE)]
    acc = [[0] * TILE for _ in range(TILE)]
    # (flecks, grains, fibres): meadow is pale and sparse, dirt dark and dense, sand all fibre
    mix_by_kind = {
        "grass":  (70, 90, 26),
        "lush":   (110, 70, 22),
        "meadow": (40, 120, 30),
        "dirt":   (150, 50, 10),
        "sand":   (20, 110, 44),
    }
    n_fleck, n_grain, n_fibre = mix_by_kind[kind]
    for _ in range(n_fleck):
        ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_grain):
        ground._stamp(g, [(0, 0, 3)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_fibre):
        # a paper fibre: a short, slightly bent pale stroke over a faint dark one
        x0, y0 = rng.randrange(TILE), rng.randrange(TILE)
        ln = rng.randint(3, 7)
        dy = rng.choice([-1, 0, 0, 1])
        for k in range(ln):
            ground._stamp(g, [(k, (k * dy) // 3, 3), (k, (k * dy) // 3 + 1, 1)], x0, y0)
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


INK = ((22, 11, 9), (38, 19, 15), (62, 34, 26))
INK_MID = ((80, 38, 26), (112, 58, 36), (150, 86, 50))
SCRAP = ((200, 160, 110), (238, 208, 150), (255, 240, 200))
GOLD = ((210, 140, 40), (250, 196, 80), (255, 236, 150))
EMBER = ((178, 70, 34), (226, 112, 52), (252, 168, 92))
PEBBLE = ((96, 54, 36), (136, 82, 52), (186, 128, 82))
RIBBON = ((150, 60, 40), (206, 96, 60), (240, 150, 100))

DETAILS = {
    "bladetuft_a": (INK, False, [
        "3..3..3.",
        "23.32.32",
        "22.22.22",
        "12.21.21",
        "1..1..1.",
    ]),
    "bladetuft_b": (INK, False, [
        "..3...3",
        ".23.3.2",
        ".22.22.",
        "212.21.",
        "1.1.1..",
    ]),
    "midtuft": (INK_MID, False, [
        "3.3.3",
        "232.2",
        "222.2",
        ".121.",
    ]),
    "scrap_a": (SCRAP, False, [
        "33.",
        "322",
        ".21",
    ]),
    "scrap_b": (SCRAP, False, [
        ".33",
        "322",
        "21.",
    ]),
    "star": (GOLD, False, [
        "..3..",
        "..3..",
        "33233",
        ".222.",
        ".2.2.",
    ]),
    "pebbles": (PEBBLE, False, [
        ".33..3",
        ".21.31",
        "......",
        "..32..",
        "..21..",
    ]),
    "flatstone": (INK_MID, True, [
        ".3332..",
        "332222.",
        "3222221",
        ".22111.",
    ]),
    "ribbonbit": (RIBBON, False, [
        "3.....",
        ".32...",
        "..232.",
        "....21",
    ]),
    "ember": (EMBER, False, [
        ".3.",
        "323",
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


# ------------------------------------------------------------------ water: an inky mirror, amber glints
water.RAMPS["inkpool"] = ((0.10, 0.05, 0.06), (0.24, 0.12, 0.10), (0.98, 0.72, 0.40))


def pool_tile():
    return water.make_water_tile("inkpool")


# ------------------------------------------------------------------ the screen's face (greyscale, tinted)
def face_tile():
    """32 x 32 greyscale limestone-and-paper: a fine fibre grain and a few faint seams, light overall (the
    ScreenView tints it warm and lights it from the lantern)."""
    rng = random.Random("lf-face")
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 255))
    px = img.load()
    for y in range(32):
        for x in range(32):
            g = round(rng.uniform(0.90, 0.97) * 255)
            px[x, y] = (g, g, g, 255)
    for _ in range(4):                       # a faint horizontal seam
        y = rng.randrange(32)
        for x in range(32):
            if rng.random() < 0.7:
                g = round(0.80 * 255)
                px[x, y] = (g, g, g, 255)
    for _ in range(90):                      # fibre flecks, short and pale or dark
        x, y = rng.randrange(32), rng.randrange(32)
        for k in range(rng.randint(1, 3)):
            g = round(rng.choice([0.74, 0.84, 1.0]) * 255)
            px[(x + k) % 32, y] = (g, g, g, 255)
    return img


# ------------------------------------------------------------------ props
DARK = ((0.09, 0.045, 0.04), (0.17, 0.09, 0.07), (0.28, 0.16, 0.12))
SIENNA = ((0.30, 0.14, 0.09), (0.44, 0.22, 0.13), (0.60, 0.34, 0.20))
PAPER = ((0.76, 0.52, 0.30), (0.92, 0.70, 0.42), (0.99, 0.88, 0.62))
LAMP_BODY = ((1.0, 0.62, 0.20), (1.0, 0.80, 0.34), (1.0, 0.95, 0.66))
LAMP_CORE = (1.0, 0.98, 0.84)
WARM_WINDOW = (1.0, 0.82, 0.40)
CLOTH = ((0.46, 0.14, 0.12), (0.70, 0.24, 0.18), (0.90, 0.44, 0.30))


def _p_great_lantern(c):
    """THE lantern: a tall dark pole and a big round paper lantern hung from a crook, glowing from inside."""
    cx = c.w // 2
    gy = c.h - 2
    c.poly([(cx - 2, 26), (cx + 2, 26), (cx + 3, gy), (cx - 3, gy)], lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx * 1.2, dy * 0.2, 4)))
    c.poly([(cx - 6, gy - 1), (cx + 6, gy - 1), (cx + 4, gy - 5), (cx - 4, gy - 5)], lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx, dy, 6)))
    # the crook the lantern hangs from
    c.line((cx, 8), (cx, 3), lambda x, y, dx, dy: c.put(x, y, DARK[1]))
    # the body: a plump paper lantern, brightest at its middle
    cy = 19
    for y in range(cy - 14, cy + 15):
        for x in range(cx - 13, cx + 14):
            dx, dy = x - cx, y - cy
            e = (dx * dx) / (12.5 * 12.5) + (dy * dy) / (14.0 * 14.0)
            if e <= 1.0:
                core = 1.0 - e
                col = LAMP_BODY[0] if core < 0.18 else (LAMP_BODY[1] if core < 0.55 else LAMP_BODY[2])
                c.glow(x, y, col)
    for ang in (-0.72, -0.36, 0.0, 0.36, 0.72):       # the ribs: thin dark curves down the paper
        for k in range(-13, 14):
            t = k / 14.0
            x = cx + math.sin(ang * 2.1) * 12.5 * math.sqrt(max(0.0, 1.0 - t * t))
            c.put(int(round(x)), cy + k, mix(LAMP_BODY[0], DARK[1], 0.55), solid=False)
    c.ellipse(cx, cy - 14, 6, 2, lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx, dy, 6)))     # the cap
    c.ellipse(cx, cy + 14, 5, 2, lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx, dy, 6)))     # the base
    for k in range(-2, 3):                                                                     # a tassel
        c.put(cx + k, cy + 17 + abs(k) // 2, CLOTH[1])
    c.glow(cx, cy, LAMP_CORE)


def _p_lantern_post(c):
    """A small paper lantern on a crooked post: the footlights."""
    cx = c.w // 2
    gy = c.h - 2
    c.poly([(cx - 1, 9), (cx + 1, 9), (cx + 2, gy), (cx - 2, gy)], lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx, dy * 0.2, 3)))
    c.line((cx, 8), (cx + 3, 5), lambda x, y, dx, dy: c.put(x, y, DARK[1]))
    for y in range(3, 14):
        for x in range(cx - 4, cx + 5):
            dx, dy = x - (cx + 0.5), y - 8.5
            if (dx * dx) / 20.0 + (dy * dy) / 30.0 <= 1.0:
                c.glow(x, y, LAMP_BODY[1] if abs(dx) + abs(dy) * 0.4 > 2.0 else LAMP_BODY[2])
    c.put(cx, 2, DARK[1])


def _p_cutout_house(c):
    """A flat paper house: a dark cut shape, a lit window or two, a pitched roof with a chimney."""
    gy = c.h - 2
    c.poly([(2, gy), (2, 18), (c.w // 2, 4), (c.w - 3, 18), (c.w - 3, gy)], lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx * 0.3, dy * 0.3, 40)))
    c.poly([(c.w - 12, 12), (c.w - 12, 3), (c.w - 7, 3), (c.w - 7, 15)], lambda x, y, dx, dy: c.put(x, y, DARK[1]))
    for wx, wy in ((8, 20), (c.w - 16, 20)):
        for y in range(wy, wy + 8):
            for x in range(wx, wx + 7):
                c.glow(x, y, WARM_WINDOW if y < wy + 5 else mix(WARM_WINDOW, LAMP_BODY[0], 0.5))
        c.put(wx + 3, wy + 3, DARK[1], solid=False)       # a mullion: the window is a cut shape too
        for y in range(wy, wy + 8):
            c.put(wx + 3, y, DARK[1], solid=False)
    for y in range(gy - 11, gy + 1):                        # a door, dark with a warm slit
        for x in range(c.w // 2 - 3, c.w // 2 + 4):
            c.put(x, y, DARK[0])
    for y in range(gy - 9, gy - 2):
        c.glow(c.w // 2, y, WARM_WINDOW)


def _p_cutout_tower(c):
    """A tall narrow tower with a lit top window and a little onion cap, for the silhouettes' skyline."""
    gy = c.h - 2
    cx = c.w // 2
    c.poly([(cx - 8, gy), (cx - 8, 20), (cx + 8, 20), (cx + 8, gy)], lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx * 0.3, dy * 0.3, 40)))
    c.ellipse(cx, 16, 10, 8, lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx * 0.3, dy * 0.3, 40)))
    c.poly([(cx - 4, 12), (cx, 0), (cx + 4, 12)], lambda x, y, dx, dy: c.put(x, y, DARK[1]))
    for y in range(24, 32):
        for x in range(cx - 3, cx + 4):
            c.glow(x, y, WARM_WINDOW)
    for y in range(40, 45):
        for x in range(cx - 2, cx + 3):
            c.glow(x, y, mix(WARM_WINDOW, LAMP_BODY[0], 0.4))


def _p_fence(c):
    """A low run of paper pickets, cut at the top into points."""
    gy = c.h - 2
    for x in range(1, c.w - 1, 5):
        c.poly([(x, gy), (x, gy - 8), (x + 1.5, gy - 11), (x + 3, gy - 8), (x + 3, gy)], lambda px, py, dx, dy: c.put(px, py, lit(DARK, dx, dy * 0.3, 5)))
    c.line((0, gy - 5), (c.w - 1, gy - 5), lambda x, y, dx, dy: c.put(x, y, DARK[1]))


def _p_signboard(c):
    """A notice board: a dark plank cut out with a warm paper notice pinned to it."""
    gy = c.h - 2
    cx = c.w // 2
    c.poly([(cx - 1, 10), (cx + 1, 10), (cx + 1, gy), (cx - 1, gy)], lambda x, y, dx, dy: c.put(x, y, DARK[1]))
    c.poly([(1, 2), (c.w - 2, 2), (c.w - 2, 18), (1, 18)], lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx * 0.4, dy * 0.4, 8)))
    for y in range(4, 16):
        for x in range(3, c.w - 4):
            c.put(x, y, PAPER[1] if (x + y) % 11 else PAPER[2], solid=False)
    for yy in (7, 10, 13):
        c.line((5, yy), (c.w - 7 - (yy % 3), yy), lambda x, y, dx, dy: c.put(x, y, SIENNA[0], solid=False))


def _p_puppet_stick(c):
    """A little paper puppet on a stick: a cut-out figure with jointed arms and a lit eye."""
    gy = c.h - 2
    cx = c.w // 2
    c.line((cx, gy), (cx, 11), lambda x, y, dx, dy: c.put(x, y, DARK[1]))
    c.ellipse(cx, 7, 3.2, 3.6, lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx, dy, 4)))
    c.poly([(cx - 4, 12), (cx + 4, 12), (cx + 5, 22), (cx - 5, 22)], lambda x, y, dx, dy: c.put(x, y, lit(CLOTH, dx, dy, 6)))
    c.line((cx - 4, 13), (cx - 9, 18), lambda x, y, dx, dy: c.put(x, y, DARK[1]))
    c.line((cx + 4, 13), (cx + 9, 9), lambda x, y, dx, dy: c.put(x, y, DARK[1]))
    c.glow(cx + 1, 7, WARM_WINDOW)


def _p_reed(c):
    """A few flat reeds, cut like paper strips, one with a cattail."""
    gy = c.h - 2
    for i, (x, top) in enumerate(((3, 6), (6, 2), (9, 8), (12, 4))):
        c.line((x, gy), (x + (i % 2) - 0.5, top), lambda px, py, dx, dy: c.put(px, py, DARK[1 + (i % 2)]))
    c.ellipse(7, 4, 1.6, 3.0, lambda x, y, dx, dy: c.put(x, y, SIENNA[1]))


def _p_rock(c):
    gy = c.h - 2
    pts = [(2, gy), (1, 7), (6, 2), (13, 1), (19, 4), (21, gy)]
    c.poly(pts, lambda x, y, dx, dy: c.put(x, y, lit(SIENNA, dx * 0.5, dy * 0.5, 14)))
    c.line((5, 7), (15, 6), lambda x, y, dx, dy: c.put(x, y, SIENNA[0]))


def _p_cart(c):
    """The puppeteer's cart: a dark box on two wheels with a small lit stage in the front and a curtain."""
    gy = c.h - 2
    c.poly([(3, gy - 4), (3, 7), (c.w - 4, 7), (c.w - 4, gy - 4)], lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx * 0.3, dy * 0.3, 30)))
    c.poly([(1, 7), (c.w - 2, 7), (c.w - 6, 2), (5, 2)], lambda x, y, dx, dy: c.put(x, y, lit(CLOTH, dx, dy, 14)))
    for y in range(10, 19):
        for x in range(8, c.w - 9):
            c.glow(x, y, mix(WARM_WINDOW, LAMP_BODY[0], (x - 8) / max(1.0, c.w - 17)) if y < 16 else LAMP_BODY[0])
    for wx in (7, c.w - 8):
        c.disc(wx, gy - 3, 4.2, lambda x, y, dx, dy: c.put(x, y, lit(DARK, dx, dy, 5)))
        c.disc(wx, gy - 3, 1.4, lambda x, y, dx, dy: c.put(x, y, SIENNA[1]))
    c.line((c.w - 4, 10), (c.w + 0, 14), lambda x, y, dx, dy: c.put(x, y, DARK[1]))   # the shaft


def _p_moon(c):
    """A cut paper moon on a pole: a pale crescent for a night that never comes."""
    gy = c.h - 2
    cx = c.w // 2
    c.line((cx, gy), (cx, 18), lambda x, y, dx, dy: c.put(x, y, DARK[1]))
    for y in range(0, 19):
        for x in range(0, c.w):
            dx, dy = x - cx, y - 9
            if dx * dx + dy * dy <= 81 and (dx - 3) ** 2 + (dy + 1) ** 2 > 64:
                c.put(x, y, PAPER[2] if dx + dy < 0 else PAPER[1])


PROP_BUILDERS = {
    "lf_great_lantern": ((30, 64), _p_great_lantern),
    "lf_lantern_post": ((13, 32), _p_lantern_post),
    "lf_cutout_house": ((44, 38), _p_cutout_house),
    "lf_cutout_tower": ((22, 56), _p_cutout_tower),
    "lf_fence": ((28, 16), _p_fence),
    "lf_signboard": ((20, 30), _p_signboard),
    "lf_puppet_stick": ((20, 34), _p_puppet_stick),
    "lf_reed": ((15, 24), _p_reed),
    "lf_rock": ((24, 16), _p_rock),
    "lf_cart": ((40, 30), _p_cart),
    "lf_moon": ((20, 36), _p_moon),
}


def make_prop(name):
    """(base, tint_or_None) for a Lanternfold prop. None has a tint layer: their colours are fixed."""
    (w, h), fn = PROP_BUILDERS[name]
    c = Canvas(w, h)
    fn(c)
    c.outline()
    return c.img, (c.tint if c.has_tint else None)


# ------------------------------------------------------------------ preview
def preview(path, scale=3):
    """A contact sheet: every tree, understory, prop, the tiles and the litter on a warm amber backdrop."""
    bg = (236, 172, 98, 255)
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
    items += [atlas, pool_tile().resize((64, 64), Image.NEAREST), face_tile()]
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
