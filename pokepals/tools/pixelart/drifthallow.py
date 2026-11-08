"""
Drifthallow -- the snowfield at blue hour -- pixel art: snow-laden pines, frozen birches and oaks, a
handful of snow props, the powder the ground is made of, and the fine litter on it. The look is the
meadow worlds' own language (a lit blob under the upper-left light, the shared 1px outline), in a cold
palette: deep untouched snow in lilac-blue shade, the sky's last light on the highlights, dark teal in
the pines' hearts.

Most of it is built from the machinery the other worlds already have:
  * trees   -- trees.make_grove_parts with new cold foliage/bark ramps, so the shapes are the grove's;
  * ground  -- the seamless terrain atlas in ground.py's layout (R = shade role, G = accent), but with
               snow's fine grain instead of grass blades, plus a detail atlas of snow litter;
  * water   -- one new ramp for water.py: a frozen pond;
  * props   -- small procedural sprites on nocthollow.py's Canvas (ellipses/polygons), BASE + optional
               grayscale TINT, the props.py convention.

Everything is deterministic (seeded by name), so re-running reproduces the PNGs byte for byte.
Baked by tools/gen_drifthallow.py.
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
# trees.py reads FOLIAGE/BARK by name, so a cold look is just new ramps registered under new names.
trees.FOLIAGE.update({
    # snow piled on dark needles: shadow side keeps the pine's teal, the lit side is nearly white
    "snow_pine":  ((40, 76, 84), (132, 164, 180), (240, 246, 252)),
    "snow_pine2": ((34, 62, 76), (112, 146, 168), (226, 238, 248)),
    # frosted birch crowns: pale, blue-grey, sparse-looking
    "frost":      ((96, 116, 146), (156, 182, 206), (230, 241, 250)),
    # an old oak under snow
    "frost_dark": ((70, 88, 118), (122, 146, 174), (200, 216, 232)),
})
trees.BARK.update({
    "cold": ((50, 46, 56), (88, 84, 96), (136, 132, 146)),
})

# (design, seed, foliage ramp, bark ramp, dots) -- the grove catalog, trees.GROVE's shape.
GROVE = {
    "pine_a":  ("pine", 1, "snow_pine", "dark", None),
    "pine_b":  ("pine", 2, "snow_pine2", "dark", None),
    "pine_c":  ("pine", 3, "snow_pine", "dark", None),
    "pine_d":  ("pine", 4, "snow_pine2", "dark", None),
    "birch_a": ("birch", 1, "frost", "birch", None),
    "birch_b": ("birch", 2, "frost", "birch", None),
    "birch_c": ("birch", 3, "frost", "birch", None),
    "oak_a":   ("oak", 1, "frost_dark", "cold", None),
    "oak_b":   ("oak", 2, "frost_dark", "cold", None),
}
GREAT = {
    # (a "great_pine" doubles badly: trees._design only scales lobes, and a pine is tiers)
    "great_oak":  ("great_oak", 7, "frost_dark", "cold", None),
    "great_oak2": ("great_oak", 9, "frost", "cold", None),
}
# Understory: single-layer sprites (trees.make_grove_parts composites a stump/bush into the canopy layer).
UNDERSTORY = {
    "bush_a": ("bush", 1, "frost_dark", "cold", None),
    "bush_b": ("bush", 2, "frost", "cold", None),
    "stump":  ("stump", 1, "frost", "cold", None),
}


def tree_parts(spec):
    return trees.make_grove_parts(*spec)


# ------------------------------------------------------------------ the ground
TILE = ground.TILE
KINDS = ground.KINDS    # grass, lush, meadow, dirt, sand: re-grown as the snow's moods


def _terrain(kind):
    """(shade_grid, accent_grid) for one snow mood: base shade 2 with a fine grain of dimples (1) and
    glints (3). Like ground.make_terrain, only FINE detail is baked in; the broad light/dark swells are
    painted by the shader from world-space noise."""
    rng = random.Random("drifthallow-ground-" + kind)
    g = [[2] * TILE for _ in range(TILE)]
    acc = [[0] * TILE for _ in range(TILE)]
    # (dimples, glints, ripples): powder is soft and glittering; the deep drift is smooth; the
    # wind-scoured crust is rippled; the dirt kind is frozen earth showing through, speckled and dark.
    mix_by_kind = {
        "grass":  (90, 150, 26),     # open powder
        "lush":   (60, 70, 10),      # deep, smooth drift
        "meadow": (80, 110, 70),     # wind-scoured, rippled
        "dirt":   (260, 70, 6),      # frozen earth showing through
        "sand":   (50, 120, 30),     # ice-crusted shore
    }
    n_dim, n_glint, n_rip = mix_by_kind[kind]
    base = 1 if kind == "dirt" else 2
    for y in range(TILE):
        for x in range(TILE):
            g[y][x] = base
    for _ in range(n_dim):
        ground._stamp(g, [(0, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_dim // 3):
        ground._stamp(g, [(0, 0, 1), (1, 0, 1)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_glint):
        ground._stamp(g, [(0, 0, 3)], rng.randrange(TILE), rng.randrange(TILE))
    for _ in range(n_rip):
        # a wind ripple: a short pale line with its shadow just below (light from the upper left)
        x0, y0 = rng.randrange(TILE), rng.randrange(TILE)
        run = rng.randint(3, 7)
        for k in range(run):
            ground._stamp(g, [(k, 0, 3)], x0, y0)
            ground._stamp(g, [(k + 1, 1, 1)], x0, y0)
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


# Fine litter: ASCII maps in ground.py's format ('1' dark, '2' base, '3' light, '.' clear; letters from
# EXTRA below). (ramp, outlined, rows)
STRAW = ((112, 92, 64), (172, 150, 104), (222, 206, 164))
PALE_STONE = ((92, 98, 118), (140, 150, 172), (206, 216, 232))
ICE = ((120, 160, 200), (186, 220, 244), (246, 252, 255))
COLD_BARK = ((50, 46, 56), (88, 84, 96), (136, 132, 146))
SNOWCAP = ((176, 196, 222), (226, 236, 248), (255, 255, 255))
REEDF = ((100, 112, 118), (168, 182, 186), (232, 242, 244))
CONE = ((72, 48, 36), (112, 80, 56), (162, 124, 90))

DETAILS = {
    # dry grass poking up through the snow, frosted at the tips
    "snowtuft_a": (STRAW, False, [
        "..3...",
        ".32.3.",
        ".2.32.",
        "12.21.",
        "1211..",
    ]),
    "snowtuft_b": (STRAW, False, [
        ".3..3..",
        ".2.32..",
        "32.2.3.",
        "2.12.2.",
        "21121..",
    ]),
    # a pebble or two dusted with snow
    "snowpebbles": (PALE_STONE, False, [
        ".33..3",
        ".21.31",
        "......",
        "..32..",
        "..21..",
    ]),
    "snowstone": (PALE_STONE, True, [
        ".3332..",
        "332222.",
        "3222221",
        ".22111.",
    ]),
    # a tiny crystal of rime
    "rime": (ICE, False, [
        "..3..",
        ".323.",
        "32223",
        ".212.",
        "..1..",
    ]),
    "iceshard": (ICE, False, [
        "...3.",
        "..32.",
        ".322.",
        "3221.",
        ".21..",
    ]),
    # a fallen twig with snow along its top
    "snowtwig": (COLD_BARK, False, [
        "3.3....",
        ".23..3.",
        "..2232.",
        "....21.",
    ]),
    "pinecone": (CONE, False, [
        ".3.",
        "321",
        "121",
        ".1.",
    ]),
    # a pale frosted reed, for the shore of the frozen ponds
    "frostreed": (REEDF, False, [
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
    # a soft little windblown crest of snow, to break up the flat
    "snowcrest": (SNOWCAP, False, [
        "..333..",
        ".32222.",
        "3222211",
        ".11111.",
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
# A frozen pond: pale, calm, blue-white ice whose glints are the sky's last light.
water.RAMPS["ice"] = ((0.50, 0.62, 0.78), (0.67, 0.79, 0.90), (0.93, 0.97, 1.00))


def ice_tile():
    return water.make_water_tile("ice")


# ------------------------------------------------------------------ props
SNOW = ((0.62, 0.70, 0.86), (0.84, 0.90, 0.97), (1.00, 1.00, 1.00))
SNOW_SHADE = ((0.46, 0.54, 0.72), (0.62, 0.70, 0.86), (0.82, 0.88, 0.96))
ROCK = ((0.26, 0.28, 0.38), (0.42, 0.45, 0.57), (0.62, 0.66, 0.78))
BARK = ((0.20, 0.18, 0.24), (0.34, 0.32, 0.40), (0.52, 0.50, 0.60))
ICEC = ((0.45, 0.62, 0.82), (0.70, 0.86, 0.96), (0.96, 1.00, 1.00))
EARTH = ((0.10, 0.09, 0.14), (0.16, 0.14, 0.22), (0.24, 0.22, 0.32))


def _snow(c, x, y, dx, dy, r=8.0):
    c.put(x, y, lit(SNOW, dx, dy, r))


def _p_snow_drift(c):
    gy = c.h - 2
    c.ellipse(15, gy - 2, 14, 4.5, lambda x, y, dx, dy: _snow(c, x, y, dx, dy * 1.4, 9))
    c.ellipse(24, gy - 1, 8, 3.2, lambda x, y, dx, dy: _snow(c, x, y, dx, dy * 1.4, 7))


def _p_snow_rock(c):
    gy = c.h - 2
    pts = [(2, gy), (1, 9), (4, 4), (10, 2), (16, 4), (19, 9), (18, gy)]
    c.poly(pts, lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx, dy * 0.7, 9)))
    # the snow cap sits on the upper left, where the light is
    c.poly([(3, 8), (4, 4), (10, 2), (16, 4), (18, 7), (14, 6), (10, 8), (6, 7)],
           lambda x, y, dx, dy: c.put(x, y, lit(SNOW, dx, dy, 8)))
    c.ellipse(10, gy, 10, 2, lambda x, y, dx, dy: _snow(c, x, y, dx, dy, 6) if y >= gy else None)


def _p_frozen_stump(c):
    gy = c.h - 2
    c.poly([(2, gy), (3, 6), (5, 4), (11, 4), (13, 6), (14, gy)], lambda x, y, dx, dy: c.put(x, y, lit(BARK, dx, dy * 0.5, 7)))
    c.ellipse(8, 5, 5.5, 2.4, lambda x, y, dx, dy: _snow(c, x, y, dx, dy, 4))
    c.ellipse(8, gy, 8, 1.6, lambda x, y, dx, dy: _snow(c, x, y, dx, dy, 5) if y >= gy else None)


def _p_ice_spikes(c):
    gy = c.h - 2
    for cx, top, half in [(5, 6, 2.5), (10, 1, 3), (15, 8, 2.2), (8, 11, 2)]:
        c.poly([(cx - half, gy), (cx, top), (cx + half, gy)],
               lambda x, y, dx, dy: c.put(x, y, lit(ICEC, dx * 1.4, dy * 0.4, 5)))
    c.ellipse(10, gy, 9, 1.6, lambda x, y, dx, dy: _snow(c, x, y, dx, dy, 5))


def _p_snow_cairn(c):
    gy = c.h - 2
    for cx, cy, rx, ry in [(8, gy - 3, 7.2, 3.4), (8, gy - 8, 5.4, 2.8), (8, gy - 12, 3.4, 2.4)]:
        c.ellipse(cx, cy, rx, ry, lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx, dy, rx)))
        c.ellipse(cx - 0.5, cy - ry * 0.55, rx * 0.8, ry * 0.5, lambda x, y, dx, dy: _snow(c, x, y, dx, dy, 5))


def _p_hare_hollow(c):
    """The scent spot: a scoop in the snow, the shape of something small that lay very still, with a
    pale lip on the lit side. Deliberately modest: you walk past it unless you look."""
    cy = c.h // 2
    c.ellipse(11, cy + 1, 10, 4.4, lambda x, y, dx, dy: c.put(x, y, mix(SNOW_SHADE[1], SNOW_SHADE[0], 0.5 + 0.5 * (dy / 4.4)), solid=False))
    c.ellipse(11.5, cy + 2, 7.5, 2.8, lambda x, y, dx, dy: c.put(x, y, SNOW_SHADE[0], solid=False))
    c.ellipse(9, cy - 2, 6, 1.4, lambda x, y, dx, dy: c.put(x, y, SNOW[2], solid=False))


def _p_hare_den(c):
    """The den: a drift with a round dark doorway at its foot."""
    gy = c.h - 2
    c.ellipse(15, gy - 4, 14, 8.5, lambda x, y, dx, dy: _snow(c, x, y, dx * 0.8, dy * 1.2, 12), top_only=True)
    c.ellipse(15, gy - 3, 14, 4.5, lambda x, y, dx, dy: _snow(c, x, y, dx, dy * 1.2, 11))
    c.ellipse(15, gy - 3, 4.4, 3.6, lambda x, y, dx, dy: c.put(x, y, EARTH[1] if dy < 0.5 else EARTH[0]))
    c.ellipse(15, gy - 4, 2.6, 2.0, lambda x, y, dx, dy: c.put(x, y, EARTH[0]))
    # a little frozen lip round the doorway
    for x, y in [(10, gy - 5), (11, gy - 6), (14, gy - 7), (16, gy - 7), (19, gy - 6), (20, gy - 5)]:
        c.put(x, y, SNOW[2])


PROP_BUILDERS = {
    "snow_drift": ((30, 14), _p_snow_drift),
    "snow_rock": ((21, 17), _p_snow_rock),
    "frozen_stump": ((16, 14), _p_frozen_stump),
    "ice_spikes": ((20, 20), _p_ice_spikes),
    "snow_cairn": ((16, 24), _p_snow_cairn),
    "hare_hollow": ((22, 12), _p_hare_hollow),
    "hare_den": ((30, 18), _p_hare_den),
}


def make_prop(name):
    """(base, tint_or_None) for a Drifthallow prop. None of them has a tint layer: their colours are
    snow and stone, fixed."""
    (w, h), fn = PROP_BUILDERS[name]
    c = Canvas(w, h)
    fn(c)
    c.outline()
    return c.img, (c.tint if c.has_tint else None)


# ------------------------------------------------------------------ preview
def preview(path, scale=3):
    """A contact sheet: every tree, understory, prop, the ice tile and the litter on a snow backdrop."""
    bg = (150, 168, 204, 255)
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
    items.append(ice_tile())
    pad = 8
    w = sum(i.width + pad for i in items[:14]) + pad
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
