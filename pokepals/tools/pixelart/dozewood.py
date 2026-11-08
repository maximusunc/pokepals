"""
Dozewood -- the drowsy forest -- pixel art: round, heavy-crowned trees and willows trailing their
vines, mossy understory, the soft moss the ground is made of and the small litter on it, a still
dark pond, and the props of a place built for napping: hanging lamps, hammocks, cushioned hollows,
a crooked arch, a sleeping boulder. Plus the little DREAM PICTURES a dozing companion sees in its
thought bubble, one per landmark.

The look is the meadow worlds' own language (a lit blob under the upper-left light, the shared 1px
outline) in a dusky palette: moss green with a lavender shade, warm paper-pale lamps, no hard
contrast anywhere. Built from the machinery the other worlds already have:
  * trees   -- trees.make_grove_parts with new dusky foliage/bark ramps, so the shapes are the grove's;
  * ground  -- the seamless terrain atlas in ground.py's layout (R = shade role, G = accent), here soft
               moss grain, plus a detail atlas of small litter;
  * water   -- one new ramp for water.py: a still, dark pond with lamp-warm glints;
  * props   -- small procedural sprites on nocthollow.py's Canvas (ellipses/polygons/lines), BASE only.

Everything is deterministic (seeded by name), so re-running reproduces the PNGs byte for byte.
Baked by tools/gen_dozewood.py.
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
    # heavy, dusky crowns: the shade side leans lavender, the lit side is soft sage
    "doze_moss":  ((40, 66, 62), (76, 112, 92), (140, 176, 134)),
    "doze_deep":  ((34, 56, 60), (62, 94, 86), (112, 150, 118)),
    "doze_fern":  ((48, 78, 64), (92, 128, 94), (164, 192, 136)),
    "doze_willow": ((52, 80, 76), (96, 130, 108), (168, 196, 150)),
})
trees.BARK.update({
    "doze": ((52, 42, 52), (88, 72, 76), (132, 112, 108)),
})

# (design, seed, foliage ramp, bark ramp, dots) -- the grove catalog, trees.GROVE's shape.
GROVE = {
    "round_a":  ("round", 11, "doze_moss", "doze", None),
    "round_b":  ("round", 12, "doze_deep", "doze", None),
    "round_c":  ("round", 13, "doze_fern", "doze", None),
    "oak_a":    ("oak", 11, "doze_moss", "doze", None),
    "oak_b":    ("oak", 12, "doze_deep", "doze", None),
    "willow_a": ("willow", 11, "doze_willow", "doze", None),
    "willow_b": ("willow", 12, "doze_willow", "doze", None),
    "willow_c": ("willow", 13, "doze_fern", "doze", None),
}
GREAT = {
    "great_oak":    ("great_oak", 17, "doze_deep", "doze", None),
    "great_willow": ("great_willow", 19, "doze_willow", "doze", None),
}
UNDERSTORY = {
    "bush_a": ("bush", 11, "doze_deep", "doze", None),
    "bush_b": ("bush", 12, "doze_fern", "doze", None),
    "stump":  ("stump", 11, "doze_moss", "doze", None),
}


def tree_parts(spec):
    return trees.make_grove_parts(*spec)


# ------------------------------------------------------------------ the ground
TILE = ground.TILE
KINDS = ground.KINDS    # grass, lush, meadow, dirt, sand: re-grown as the moss's moods


def _terrain(kind):
    """(shade_grid, accent_grid) for one moss mood: base shade 2 with a fine grain of dimples (1) and
    soft lights (3). Like ground.make_terrain, only FINE detail is baked in; the broad swells are painted
    by the shader from world-space noise."""
    rng = random.Random("dozewood-ground-" + kind)
    g = [[2] * TILE for _ in range(TILE)]
    acc = [[0] * TILE for _ in range(TILE)]
    # (dimples, lights, hairs): moss is dense and soft; deep moss is darker and smoother; the pale mood
    # is dry lichen, the dirt kind is soft loam, the sand kind is a bed of old leaves.
    mix_by_kind = {
        "grass":  (170, 70, 30),     # moss
        "lush":   (120, 40, 12),     # deep, cushiony moss
        "meadow": (90, 90, 44),      # pale lichen and fern litter
        "dirt":   (230, 36, 8),      # soft loam
        "sand":   (110, 60, 18),     # leaf litter
    }
    n_dim, n_light, n_hair = mix_by_kind[kind]
    base = 1 if kind == "dirt" else 2
    for y in range(TILE):
        for x in range(TILE):
            g[y][x] = base
    for _ in range(n_dim):
        ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_dim // 3):
        ground._stamp(g, [(0, 0, 1), (1, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_light):
        ground._stamp(g, [(0, 0, 3)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_hair):
        # a short curl of moss: two or three pale pixels climbing, with a shadow beside
        x0, y0 = rng.randrange(TILE), rng.randrange(TILE)
        ground._stamp(g, [(0, 0, 3), (0, -1, 3), (1, -2, 3), (1, 0, 1)], x0, y0)
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


# Fine litter: ASCII maps in ground.py's format ('1' dark, '2' base, '3' light, '.' clear).
# (ramp, outlined, rows)
MOSSG = ((40, 70, 56), (78, 118, 84), (140, 180, 124))
FERN = ((44, 84, 66), (84, 130, 92), (150, 190, 132))
LEAF = ((120, 84, 52), (176, 130, 72), (222, 178, 104))
PEBBLE = ((70, 74, 92), (118, 122, 140), (172, 176, 192))
CAP = ((150, 84, 106), (214, 146, 150), (246, 214, 204))
STEM = ((190, 176, 156), (232, 222, 200), (252, 248, 236))
BUD = ((120, 104, 168), (170, 154, 210), (218, 208, 240))
TWIG = ((52, 42, 48), (92, 76, 76), (140, 120, 112))

DETAILS = {
    "mosstuft_a": (MOSSG, False, [
        "..3...",
        ".32.3.",
        ".2.32.",
        "12.21.",
        "1211..",
    ]),
    "mosstuft_b": (MOSSG, False, [
        ".3..3..",
        ".2.32..",
        "32.2.3.",
        "2.12.2.",
        "21121..",
    ]),
    "fernlet": (FERN, False, [
        "...33.",
        "..32..",
        ".322..",
        "3221..",
        "221...",
        "21....",
    ]),
    "fernlet_b": (FERN, False, [
        ".33...",
        "..23..",
        "..223.",
        "...122",
        "....21",
        "....1.",
    ]),
    "fallenleaf": (LEAF, False, [
        ".33.",
        "3221",
        ".21.",
    ]),
    "leafpair": (LEAF, False, [
        "33...",
        "321.3",
        ".1.32",
        "...21",
    ]),
    "mosspebble": (PEBBLE, True, [
        ".332.",
        "32221",
        ".211.",
    ]),
    "toadlet": (CAP, False, [
        ".33.",
        "3221",
        ".22.",
    ]),
    "sleepbud": (BUD, False, [
        ".3.",
        "321",
        ".2.",
        ".2.",
    ]),
    "drowsetwig": (TWIG, False, [
        "3.3....",
        ".23..3.",
        "..2232.",
        "....21.",
    ]),
    "reedlet": (FERN, False, [
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
# A still, dark pond: deep green-grey water whose only glints are the lamps' warm light.
water.RAMPS["doze_pond"] = ((0.10, 0.20, 0.24), (0.17, 0.30, 0.34), (0.62, 0.70, 0.50))


def pond_tile():
    return water.make_water_tile("doze_pond")


# ------------------------------------------------------------------ props
MOSS = ((0.14, 0.26, 0.22), (0.27, 0.44, 0.32), (0.48, 0.66, 0.44))
MOSS_DEEP = ((0.10, 0.20, 0.19), (0.19, 0.34, 0.29), (0.34, 0.52, 0.40))
STONE = ((0.22, 0.24, 0.32), (0.38, 0.40, 0.50), (0.58, 0.60, 0.70))
WOOD = ((0.20, 0.15, 0.17), (0.34, 0.26, 0.26), (0.54, 0.43, 0.38))
PAPER = ((0.80, 0.70, 0.54), (0.96, 0.88, 0.70), (1.00, 0.97, 0.86))
CLOTH = ((0.40, 0.31, 0.54), (0.58, 0.47, 0.72), (0.78, 0.69, 0.90))
CAPS = ((0.62, 0.34, 0.46), (0.86, 0.58, 0.62), (0.98, 0.84, 0.80))
STEMS = ((0.74, 0.68, 0.60), (0.90, 0.86, 0.78), (0.99, 0.97, 0.92))
EARTH = ((0.10, 0.08, 0.12), (0.16, 0.13, 0.19), (0.24, 0.20, 0.28))
LAMP_GLOW = (1.0, 0.92, 0.66)


def _bevel(c, mask, ramp):
    """Shade a thick-line shape from its own mask: light on the upper-left rim, dark on the lower-right."""
    for (x, y) in mask:
        up = (x, y - 1) not in mask or (x - 1, y) not in mask
        down = (x, y + 1) not in mask or (x + 1, y) not in mask
        c.put(x, y, ramp[2] if up and not down else (ramp[0] if down and not up else ramp[1]))


def _thick(c, pts, width, mask):
    """Add a thick polyline to `mask` (a set of pixels)."""
    for a, b in zip(pts[:-1], pts[1:]):
        c.line(a, b, lambda x, y, dx, dy: mask.add((x, y)), width=width)


def _p_hanging_lamp(c):
    """A crook of wood with a paper lamp hanging from it. The lamp's own light is the world's prop light."""
    gy = c.h - 2
    mask = set()
    _thick(c, [(3, gy), (3, 9), (4, 5), (8, 3), (11, 4)], 2.2, mask)
    _bevel(c, mask, WOOD)
    c.ellipse(3, gy, 5, 1.6, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 5)) if y >= gy - 1 else None)
    # the chain and the lamp
    for y in range(5, 9):
        c.put(11, y, WOOD[2])
    c.ellipse(11, 14, 4.2, 5.4, lambda x, y, dx, dy: c.put(x, y, lit(PAPER, dx, dy, 5)))
    c.ellipse(11, 14, 2.4, 3.2, lambda x, y, dx, dy: c.glow(x, y, mix(LAMP_GLOW, (1, 1, 1), 0.25 * (1 - abs(dy) / 3.2))))
    c.put(11, 8, WOOD[0])
    c.put(10, 20, WOOD[1])
    c.put(11, 20, WOOD[1])
    c.put(12, 20, WOOD[1])


def _p_hammock(c):
    """Two posts and a sagging cloth hung between them, a pillow at one end. Nothing to collide with."""
    gy = c.h - 2
    posts = set()
    _thick(c, [(3, gy), (3, 4)], 2.4, posts)
    _thick(c, [(c.w - 4, gy), (c.w - 4, 4)], 2.4, posts)
    _bevel(c, posts, WOOD)
    sag = 7.0
    span = c.w - 8
    cloth = set()
    for i in range(span + 1):
        x = 4 + i
        t = i / span
        y = 6 + sag * math.sin(math.pi * t)
        for dy in range(0, 4):
            cloth.add((x, int(round(y)) + dy))
    for (x, y) in cloth:
        top = (x, y - 1) not in cloth
        bottom = (x, y + 1) not in cloth
        c.put(x, y, CLOTH[2] if top else (CLOTH[0] if bottom else CLOTH[1]))
    # a pillow resting in the dip, and the ropes
    c.ellipse(13, 12, 4.4, 2.2, lambda x, y, dx, dy: c.put(x, y, lit(PAPER, dx, dy, 4)))
    for i in range(0, span, 3):
        t = i / span
        y = 6 + sag * math.sin(math.pi * t)
        c.put(4 + i, int(round(y)) + 4, CLOTH[0])


def _p_nap_hollow(c):
    """A nap spot: a soft ring of moss around a dip, a little cushion of lavender cloth in the middle.
    Flat on the ground (nothing solid), deliberately inviting."""
    cx, cy = c.w // 2, c.h // 2
    c.ellipse(cx, cy + 1, 16, 6.8, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx * 0.5, dy * 1.2, 8), solid=False))
    c.ellipse(cx, cy + 1.5, 12.5, 4.6, lambda x, y, dx, dy: c.put(x, y, mix(MOSS_DEEP[1], MOSS_DEEP[0], 0.5 + 0.5 * (dy / 4.6)), solid=False))
    c.ellipse(cx - 0.5, cy + 1.5, 7.5, 2.8, lambda x, y, dx, dy: c.put(x, y, lit(CLOTH, dx, dy * 1.4, 6), solid=False))
    # two sleepy flowers on the rim
    for fx, fy in [(cx - 14, cy - 2), (cx + 13, cy)]:
        c.put(fx, fy, BUD_RGB[2], solid=False)
        c.put(fx, fy + 1, BUD_RGB[1], solid=False)


BUD_RGB = tuple(tuple(v / 255.0 for v in col) for col in BUD)


def _p_moss_mound(c):
    gy = c.h - 2
    c.ellipse(c.w // 2, gy, c.w // 2 - 1, c.h - 4, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 10)), top_only=True)
    for x, y in [(6, gy - 6), (11, gy - 9), (15, gy - 5)]:
        c.put(x, y, MOSS[2])


def _p_sleepy_log(c):
    """A fallen log, mossy on top, its cut end showing rings."""
    gy = c.h - 2
    body = set()
    _thick(c, [(4, gy - 4), (c.w - 5, gy - 4)], 8.0, body)
    _bevel(c, body, WOOD)
    c.ellipse(4, gy - 4, 3.2, 4.2, lambda x, y, dx, dy: c.put(x, y, WOOD[2] if (dx * dx + dy * dy) > 2.0 else WOOD[1]))
    c.put(4, gy - 4, WOOD[0])
    c.ellipse(c.w // 2 + 2, gy - 8, 9, 2.2, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 6)), top_only=True)


def _p_fern_clump(c):
    gy = c.h - 2
    for ang, ln in [(-1.1, 11), (-0.6, 13), (-0.1, 14), (0.4, 13), (0.9, 11)]:
        pts = [(c.w / 2, gy)]
        for k in range(1, 6):
            t = k / 5
            pts.append((c.w / 2 + math.sin(ang) * ln * t, gy - math.cos(ang) * ln * t + 3 * t * t))
        for a, b in zip(pts[:-1], pts[1:]):
            c.line(a, b, lambda x, y, dx, dy: c.put(x, y, FERN_RGB[1], solid=False), width=1.0)
        c.put(pts[-1][0], pts[-1][1], FERN_RGB[2], solid=False)
        c.put(pts[-2][0], pts[-2][1] - 1, FERN_RGB[2], solid=False)


FERN_RGB = tuple(tuple(v / 255.0 for v in col) for col in FERN)


def _toadstool(c, cx, gy, r):
    for y in range(int(gy - r * 1.4), int(gy) + 1):
        c.put(cx, y, STEMS[1], solid=True)
    c.ellipse(cx, gy - r * 1.4, r, r * 0.62, lambda x, y, dx, dy: c.put(x, y, lit(CAPS, dx, dy * 1.6, r)), top_only=False)
    c.put(cx - r * 0.4, gy - r * 1.7, CAPS[2])


def _p_toadstool_ring(c):
    """LANDMARK: a ring of seven small pale toadstools round a dip in the moss."""
    cx, cy = c.w / 2, c.h - 8
    c.ellipse(cx, cy + 1, 17, 5.2, lambda x, y, dx, dy: c.put(x, y, MOSS_DEEP[1], solid=False))
    spots = []
    for k in range(7):
        a = k / 7 * math.tau + 0.3
        spots.append((cx + math.cos(a) * 16.5, cy + math.sin(a) * 5.4))
    for x, y in sorted(spots, key=lambda p: p[1]):
        _toadstool(c, int(round(x)), int(round(y)) + 2, 3.0)


def _p_crooked_arch(c):
    """LANDMARK (the secret's): an arch of old grey roots grown crooked, its left leg leaning out, its
    peak off to the right, a mossy cap on top. Under it, the ground is a little brighter."""
    gy = c.h - 2
    mask = set()
    _thick(c, [(5, gy), (6, gy - 9), (9, 16), (14, 8), (22, 4), (29, 7), (32, 14), (31, gy)], 5.0, mask)
    _bevel(c, mask, WOOD)
    # a spur of root growing off the right leg, and moss capping the peak
    spur = set()
    _thick(c, [(33, gy - 6), (37, gy - 3), (38, gy)], 2.4, spur)
    _bevel(c, spur, WOOD)
    c.ellipse(21, 4, 7, 2.2, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 6)), top_only=True)
    c.ellipse(8, 14, 2.6, 1.6, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 3)), top_only=True)
    # a vine hanging from the peak
    for y in range(8, 16):
        c.put(23, y, FERN_RGB[1])
    c.put(23, 16, FERN_RGB[2])
    c.put(24, 12, FERN_RGB[2])
    # the ground beneath, paler where a lantern might sit
    c.ellipse(19, gy, 8, 2.0, lambda x, y, dx, dy: c.put(x, y, MOSS[2], solid=False))


def _p_still_stone(c):
    """One of the three stones of the pond: smooth, round, wet on top."""
    gy = c.h - 2
    c.ellipse(c.w // 2, gy - 4, c.w // 2 - 1, 5.4, lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy, 7)))
    c.ellipse(c.w // 2 - 2, gy - 6, 3, 1.1, lambda x, y, dx, dy: c.put(x, y, STONE[2]))


def _p_lantern_log(c):
    """LANDMARK: a big hollow log lying on its side, a lamp glowing inside the hollow."""
    gy = c.h - 2
    body = set()
    _thick(c, [(12, gy - 8), (c.w - 6, gy - 8)], 15.0, body)
    _bevel(c, body, WOOD)
    # the open end, facing us at left: a dark hollow with the lamp inside
    c.ellipse(11, gy - 8, 6.6, 8.2, lambda x, y, dx, dy: c.put(x, y, WOOD[2] if (dx * dx) / 43 + (dy * dy) / 67 > 0.62 else EARTH[1]))
    c.ellipse(11, gy - 7, 4.2, 5.4, lambda x, y, dx, dy: c.put(x, y, EARTH[0]))
    c.ellipse(11, gy - 6, 2.4, 3.0, lambda x, y, dx, dy: c.glow(x, y, mix(LAMP_GLOW, PAPER[1], 0.3 * (dy / 3.0 + 1) / 2)))
    c.ellipse(c.w // 2 + 6, gy - 15, 10, 2.4, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 6)), top_only=True)
    for x, y in [(c.w - 9, gy - 10), (c.w - 12, gy - 4)]:
        c.put(x, y, WOOD[0])


def _p_sleeper_stone(c):
    """LANDMARK: a boulder like a sleeping head under a blanket of moss, one closed eye showing."""
    gy = c.h - 2
    c.ellipse(c.w // 2, gy - 8, 20, 11.5, lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy * 0.8, 20)))
    # the moss blanket across the top, with a scalloped edge
    c.ellipse(c.w // 2 + 1, gy - 12, 19, 7.4, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 14)), top_only=True)
    for x in range(8, c.w - 6, 4):
        c.ellipse(x, gy - 12, 2.2, 2.4, lambda xx, yy, dx, dy: c.put(xx, yy, MOSS[1]))
    # the closed eye, a soft curve, and a heavy brow above it
    for dx in range(-3, 4):
        c.put(c.w // 2 - 7 + dx, gy - 6 + int(round(1.4 * (1 - (dx / 3.0) ** 2))), STONE[0])
    for dx in range(-4, 5):
        c.put(c.w // 2 - 7 + dx, gy - 9, STONE[2])
    # a nose-bump and a little smile of shadow
    c.ellipse(c.w // 2 - 1, gy - 4, 1.6, 1.0, lambda x, y, dx, dy: c.put(x, y, STONE[0]))
    c.ellipse(c.w // 2 + 12, gy, 8, 1.6, lambda x, y, dx, dy: c.put(x, y, MOSS[1], solid=False))


def _p_moss_stone(c):
    gy = c.h - 2
    c.ellipse(c.w // 2, gy - 4, c.w // 2 - 1, 5.2, lambda x, y, dx, dy: c.put(x, y, lit(STONE, dx, dy, 7)))
    c.ellipse(c.w // 2 - 1, gy - 7, 5, 1.8, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 4)), top_only=True)


def _p_cap_seat(c):
    """A flat-topped fungus a small creature could sit on."""
    gy = c.h - 2
    for y in range(gy - 8, gy + 1):
        for x in range(c.w // 2 - 3, c.w // 2 + 4):
            c.put(x, y, lit(STEMS, x - c.w // 2, y - (gy - 4), 5))
    c.ellipse(c.w // 2, gy - 9, 10, 3.6, lambda x, y, dx, dy: c.put(x, y, lit(CAPS, dx, dy * 1.8, 8)))
    for x, y in [(c.w // 2 - 4, gy - 10), (c.w // 2 + 3, gy - 9), (c.w // 2 - 1, gy - 11)]:
        c.put(x, y, CAPS[2])


PROP_BUILDERS = {
    "dz_hanging_lamp": ((16, 34), _p_hanging_lamp),
    "dz_hammock": ((42, 22), _p_hammock),
    "dz_nap_hollow": ((36, 16), _p_nap_hollow),
    "dz_moss_mound": ((28, 18), _p_moss_mound),
    "dz_sleepy_log": ((34, 14), _p_sleepy_log),
    "dz_fern_clump": ((22, 16), _p_fern_clump),
    "dz_toadstool_ring": ((44, 22), _p_toadstool_ring),
    "dz_crooked_arch": ((42, 40), _p_crooked_arch),
    "dz_still_stone": ((16, 14), _p_still_stone),
    "dz_lantern_log": ((40, 26), _p_lantern_log),
    "dz_sleeper_stone": ((44, 30), _p_sleeper_stone),
    "dz_moss_stone": ((18, 14), _p_moss_stone),
    "dz_cap_seat": ((24, 18), _p_cap_seat),
}


def make_prop(name):
    """(base, tint_or_None) for a Dozewood prop. None of them has a tint layer: their colours are
    moss, wood and stone, fixed."""
    (w, h), fn = PROP_BUILDERS[name]
    c = Canvas(w, h)
    fn(c)
    c.outline()
    return c.img, (c.tint if c.has_tint else None)


# ------------------------------------------------------------------ dream pictures
# What a dozing companion dreams: one small round vignette per landmark, hazed and soft at the edge so it
# reads as remembered rather than seen. Drawn from the landmark's own sprite on a patch of moss.
DREAM_SIZE = 56
DREAM_LANDMARKS = ["crooked_arch", "three_stones", "lantern_log", "toadstool_ring", "sleeper_stone"]


def _sprite(name):
    return make_prop(name)[0]


def dream_picture(landmark):
    n = DREAM_SIZE
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    px = img.load()
    cx = cy = (n - 1) / 2
    # the dream's sky: lavender at the heart, deeper violet-blue at the rim
    for y in range(n):
        for x in range(n):
            d = math.hypot(x - cx, y - cy) / (n / 2)
            sky = mix((0.86, 0.82, 0.98), (0.50, 0.48, 0.80), min(1.0, d))
            px[x, y] = tuple(int(round(v * 255)) for v in sky) + (255,)
    # the ground: a soft moss hill across the lower third
    ground_y = int(n * 0.66)
    for y in range(ground_y - 3, n):
        for x in range(n):
            bulge = int(3 * math.sin((x / n) * math.pi))
            if y >= ground_y - bulge:
                t = (y - (ground_y - bulge)) / max(1, n - ground_y)
                col = mix((0.42, 0.62, 0.50), (0.26, 0.44, 0.38), min(1.0, t * 1.4))
                px[x, y] = tuple(int(round(v * 255)) for v in col) + (255,)

    def paste(sprite, x, y):
        img.alpha_composite(sprite, (int(x), int(y)))

    if landmark == "three_stones":
        pond = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        ppx = pond.load()
        pcx, pcy = n / 2, ground_y + 5
        for y in range(n):
            for x in range(n):
                if ((x - pcx) / 21.0) ** 2 + ((y - pcy) / 7.5) ** 2 <= 1.0:
                    glint = ((x * 73856093) ^ (y * 19349663)) % 29 == 0
                    col = (0.62, 0.70, 0.54) if glint else (0.22, 0.38, 0.44)
                    ppx[x, y] = tuple(int(round(v * 255)) for v in col) + (255,)
        img.alpha_composite(pond)
        stone = _sprite("dz_still_stone")
        for sx, sy in [(n * 0.18, ground_y - 8), (n * 0.62, ground_y - 12), (n * 0.40, ground_y + 12)]:
            paste(stone, sx, sy)
    else:
        sprite = _sprite("dz_" + landmark)
        paste(sprite, (n - sprite.width) / 2, ground_y + 4 - sprite.height)
    # the haze: a pale wash over everything, then a few drifting motes
    rng = random.Random("dream-" + landmark)
    for y in range(n):
        for x in range(n):
            r, g, b, a = px[x, y]
            wash = 0.18
            px[x, y] = (int(r + (236 - r) * wash), int(g + (230 - g) * wash), int(b + (255 - b) * wash), a)
    for _ in range(9):
        x, y = rng.randrange(6, n - 6), rng.randrange(6, int(n * 0.6))
        px[x, y] = (255, 252, 226, 255)
    # round and soft at the edge
    for y in range(n):
        for x in range(n):
            d = math.hypot(x - cx, y - cy)
            edge = (n / 2 - 0.5 - d) / 6.0
            a = max(0.0, min(1.0, edge))
            r, g, b, _ = px[x, y]
            px[x, y] = (r, g, b, int(round(a * 255)))
    return img


# ------------------------------------------------------------------ preview
def preview(path, scale=3):
    """A contact sheet: every tree, understory, prop, the pond tile, the litter and the dream pictures."""
    bg = (60, 78, 74, 255)
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
    items.append(atlas)
    items.append(pond_tile())
    for lm in DREAM_LANDMARKS:
        items.append(dream_picture(lm))
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
    print("wrote", path)
