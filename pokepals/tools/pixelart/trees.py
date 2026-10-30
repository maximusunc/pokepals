"""
Pixel-art tree generator -- same shading language as the character and daemon
generators, so trees read as part of the same hand-crafted world instead of the
engine's flat circles.

Shared conventions (see generator.py / animals.py):
  * shade ROLES, not colors -- '1' dark, '2' base, '3' highlight -- so recoloring
    a tree is just picking a different ramp;
  * light from the upper-left -- highlights land up/left, shadows fall down/right;
  * a 1px near-black auto-outline around the finished silhouette.

Where the character maps are hand-shaded pixel by pixel, a tree's canopy is too
big and too round for that to stay clean. So a tree is authored as a LAYOUT --
a few overlapping canopy "lobes" (the same overlapping foliage blobs the game
already draws in TreeView) plus a trunk box -- and the shading is DERIVED from
it, exactly like the outline and the daemons' back-views are derived elsewhere:

  1. rasterize the lobes + trunk into a silhouette,
  2. shade the canopy as a LIT BLOB (bright toward the light, a dark rim on the
     shadow side -- the pixel twin of ArtStyle.draw_blob),
  3. shade the trunk with a lit left edge,
  4. add the shared 1px outline.

Reshape a tree by editing its lobes; recolor it by swapping a ramp. No
randomness, no external art -- every tree is reproducible from the numbers below.
"""

from PIL import Image

# Near-black outline, a hair warmer than pure black so it sits in the bark family
# rather than reading as ink (matches the world's dark tones in data/art.json).
OUTLINE = (28, 24, 22, 255)

# Unit-ish direction the light comes FROM, pointing up-left. Kept in the same
# spirit as data/art.json's light.dir (up and a little left) so a baked tree is
# lit from the same side as everything drawn procedurally around it.
LIGHT = (-0.55, -0.83)

# ------------------------------------------------------------------- palettes
# (dark, base, light) for foliage and for bark. "summer" is tuned to the world
# palette in data/art.json (foliage_dark/mid/light + bark) so a baked tree drops
# straight into the existing scene; the others are honest ramp swaps.
RAMPS = {
    "summer": {
        "foliage": ((44, 82, 52), (71, 117, 77), (120, 168, 108)),
        "bark":    ((74, 54, 38), (105, 77, 54), (150, 116, 84)),
    },
    "pine": {
        "foliage": ((26, 58, 44), (40, 86, 60), (86, 140, 100)),
        "bark":    ((62, 46, 34), (94, 68, 48), (136, 104, 74)),
    },
    "autumn": {
        "foliage": ((150, 74, 26), (198, 120, 40), (238, 178, 84)),
        "bark":    ((74, 54, 38), (105, 77, 54), (150, 116, 84)),
    },
}

# --------------------------------------------------------------------- layouts
# size: (W, H). The client draws the sprite feet-at-bottom-centre, so the trunk
#   base sits flush with the bottom-centre of the canvas.
# lobes: (cx, cy, r) foliage discs, unioned into the canopy silhouette.
# trunk: (width, top) -- a bark column, horizontally centred, from row `top`
#   down to the base, widening by `flare` at the very bottom (a little root spread).
LAYOUTS = {
    "tree": {
        "size": (52, 60),
        "lobes": [
            (26, 30, 15),   # broad middle mass
            (14, 33, 12),   # left shoulder
            (38, 33, 12),   # right shoulder
            (25, 20, 17),   # upper crown
            (26, 12, 10),   # top bump
        ],
        "trunk": {"width": 8, "top": 34, "flare": 3},
    },
    "great_tree": {
        "size": (104, 122),
        "lobes": [
            (52, 60, 30),   # broad middle mass
            (26, 64, 24),   # left shoulder
            (78, 64, 24),   # right shoulder
            (50, 40, 34),   # upper crown
            (52, 22, 20),   # top bump
        ],
        "trunk": {"width": 18, "top": 66, "flare": 7},
    },
}


def _blank(w, h):
    return [[0] * w for _ in range(h)]


def _canopy_mask(layout):
    """Union the foliage lobes into a boolean silhouette grid."""
    w, h = layout["size"]
    mask = _blank(w, h)
    for (cx, cy, r) in layout["lobes"]:
        r2 = r * r
        for y in range(max(0, cy - r), min(h, cy + r + 1)):
            dy = y - cy
            for x in range(max(0, cx - r), min(w, cx + r + 1)):
                dx = x - cx
                if dx * dx + dy * dy <= r2:
                    mask[y][x] = 1
    return mask


def _trunk_mask(layout):
    """A centred bark column with a little root flare at the base."""
    w, h = layout["size"]
    t = layout["trunk"]
    mask = _blank(w, h)
    cx = w / 2.0
    for y in range(t["top"], h):
        # widen toward the very bottom for a rooted, planted look
        grow = t["flare"] * (y - t["top"]) / max(1, h - 1 - t["top"])
        half = (t["width"] + grow) / 2.0
        for x in range(int(round(cx - half)), int(round(cx + half))):
            if 0 <= x < w:
                mask[y][x] = 1
    return mask


def _solid(mask, x, y):
    return 0 <= y < len(mask) and 0 <= x < len(mask[0]) and mask[y][x]


def _shade_canopy(mask):
    """Derive a lit-blob shade grid (1 dark / 2 base / 3 light) from the mask.

    Interior volume is a radial ramp brightest toward a light-centre pulled up-left;
    then the true edges are re-asserted -- a crisp dark rim wherever the canopy faces
    away from the light (down/right), a bright rim where it faces into it (up/left) --
    so the silhouette stays readable at this size. This is the pixel-art reading of
    ArtStyle.draw_blob (base fill, lightened cap toward the light, bright rim cap)."""
    h, w = len(mask), len(mask[0])
    pts = [(x, y) for y in range(h) for x in range(w) if mask[y][x]]
    if not pts:
        return _blank(w, h)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    cx = sum(xs) / len(xs)
    cy = sum(ys) / len(ys)
    radius = 0.5 * max(max(xs) - min(xs), max(ys) - min(ys)) or 1.0
    # light-centre sits off the middle, toward the light
    lx = cx + LIGHT[0] * radius * 0.55
    ly = cy + LIGHT[1] * radius * 0.55

    shade = _blank(w, h)
    for (x, y) in pts:
        d = (((x - lx) ** 2 + (y - ly) ** 2) ** 0.5) / radius
        s = 3 if d < 0.52 else (2 if d < 0.92 else 1)
        # shadow rim: any leaf pixel whose down/right neighbour is open sky
        if not (_solid(mask, x + 1, y) and _solid(mask, x, y + 1)
                and _solid(mask, x + 1, y + 1)):
            s = 1
        # lit rim: a leaf pixel facing the light with open sky up/left
        elif not (_solid(mask, x - 1, y) and _solid(mask, x, y - 1)
                  and _solid(mask, x - 1, y - 1)):
            s = 3
        shade[y][x] = s
    return shade


def _shade_trunk(mask):
    """Bark shading: lit left edge, base middle, shadowed right edge (1/2/3)."""
    h, w = len(mask), len(mask[0])
    shade = _blank(w, h)
    for y in range(h):
        row = [x for x in range(w) if mask[y][x]]
        if not row:
            continue
        left, right = row[0], row[-1]
        span = max(1, right - left)
        for x in row:
            rel = (x - left) / span
            shade[y][x] = 3 if rel < 0.30 else (1 if rel > 0.72 else 2)
    return shade


def _add_outline(px, solid, w, h):
    """1px near-black outline hugging the silhouette (same idea as generator.add_outline,
    but size-agnostic and reading the union mask so it never bites into the trunk seam)."""
    edge = []
    for y in range(h):
        for x in range(w):
            if solid[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if _solid(solid, x + dx, y + dy):
                    edge.append((x, y))
                    break
    for (x, y) in edge:
        px[x, y] = OUTLINE


def _paint_part(shade, mask, ramp3):
    """One part (trunk or canopy) on its OWN full-size canvas, painted + outlined.

    Keeping each part on the full canvas (not cropped) is what lets the client draw
    them as two layers that line up perfectly: both are bottom-anchored at the same
    origin, so the only difference at draw time is the canopy's horizontal wind
    offset. Each part carries its own outline so its silhouette stays crisp when the
    canopy slides off the trunk in the wind."""
    h, w = len(mask), len(mask[0])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            if shade[y][x]:
                px[x, y] = ramp3[shade[y][x] - 1] + (255,)
    _add_outline(px, mask, w, h)
    return img


def make_tree_parts(kind="tree", variant="summer"):
    """The two independently-drawable layers of a tree: (trunk_img, canopy_img).

    The trunk is baked whole (including the stretch the canopy normally hides), so it
    stays complete when the canopy sways aside. `kind` picks a LAYOUT, `variant` a RAMP."""
    layout = LAYOUTS[kind]
    ramp = RAMPS[variant]
    trunk = _trunk_mask(layout)
    canopy = _canopy_mask(layout)
    trunk_img = _paint_part(_shade_trunk(trunk), trunk, ramp["bark"])
    canopy_img = _paint_part(_shade_canopy(canopy), canopy, ramp["foliage"])
    return trunk_img, canopy_img


def make_tree(kind="tree", variant="summer"):
    """The whole tree as one image (trunk with the canopy composited over it).

    This is the at-rest look for previews/tooling; the game draws the two parts from
    `make_tree_parts` separately so only the canopy catches the wind."""
    trunk_img, canopy_img = make_tree_parts(kind, variant)
    img = Image.new("RGBA", trunk_img.size, (0, 0, 0, 0))
    img.alpha_composite(trunk_img)
    img.alpha_composite(canopy_img)
    return img


# ======================================================================= the grove
# Every tree used to be one of three identical sprites. The GROVE is a catalog of tree
# DESIGNS (round, oak, birch, pine, willow, fruit) plus the understory (bushes, stumps),
# each baked in several SEEDED variations, so no two neighbours match. The client picks a
# variant per tree from its position (data/art.json's "tree" variants).
#
# The canopy shading is richer than the lit-blob above: each foliage lobe is treated as a
# little SPHERE, the canopy is the union of those spheres as a height field, and every
# pixel is lit by its own sphere's normal. So a canopy reads as clumps of leaves, each
# lit from the upper-left with a shadowed underside, with dark creases where one clump
# tucks under another, instead of one flat disc.

import math as _math
import random as _random

FOLIAGE = {
    "summer":        ((44, 82, 52), (71, 117, 77), (120, 168, 108)),
    "summer_bright": ((58, 98, 52), (96, 142, 72), (154, 194, 104)),
    "summer_deep":   ((32, 66, 46), (54, 98, 66), (96, 144, 92)),
    "birch":         ((82, 118, 58), (124, 164, 82), (184, 212, 124)),
    "willow":        ((58, 94, 58), (94, 136, 80), (148, 184, 112)),
    "pine":          ((26, 58, 44), (40, 86, 60), (86, 140, 100)),
    "autumn":        ((150, 74, 26), (198, 120, 40), (238, 178, 84)),
    "autumn_red":    ((120, 40, 30), (174, 70, 42), (224, 128, 76)),
}
BARK = {
    "brown": ((74, 54, 38), (105, 77, 54), (150, 116, 84)),
    "dark":  ((58, 42, 32), (86, 64, 46), (126, 98, 72)),
    "birch": ((98, 94, 90), (196, 192, 184), (238, 236, 230)),
}
LIGHT3 = (-0.50, -0.72, 0.48)
_ln = _math.sqrt(sum(c * c for c in LIGHT3))
LIGHT3 = tuple(c / _ln for c in LIGHT3)


def _j(rng, v, amt):
    return v + rng.randint(-amt, amt)


def _design(kind, seed):
    """A seeded layout for one grove design: size, lobes, trunk and extras. A "great_" prefix
    doubles a design into a landmark-sized great tree."""
    if kind.startswith("great_"):
        base = _design(kind[len("great_"):], seed)
        w, h = base["size"]
        out = dict(base, size=(w * 2, h * 2))
        if "lobes" in base:
            # fill the doubled outline with many normal-sized clumps (a doubled lobe is a bland ball)
            rng = _random.Random("great-%s-%d" % (kind, seed))
            lobes = []
            for x, y, r in base["lobes"]:
                X, Y, R = x * 2, y * 2, r * 2
                lobes.append((X, Y, int(R * 0.72)))
                a0 = rng.random() * 6.28
                for k in range(4):
                    a = a0 + k * 1.57 + rng.uniform(-0.3, 0.3)
                    lobes.append((int(X + _math.cos(a) * R * 0.42), int(Y + _math.sin(a) * R * 0.42), int(R * 0.5)))
            out["lobes"] = lobes
        if base.get("trunk"):
            t = base["trunk"]
            out["trunk"] = dict(t, width=t["width"] * 2, top=t["top"] * 2, flare=t["flare"] * 2, lean=t.get("lean", 0) * 2)
        return out
    rng = _random.Random("%s-%d" % (kind, seed))
    if kind == "round":
        lobes = [(26, 30, 15), (14, 33, 12), (38, 33, 12), (25, 20, 17), (26, 12, 10)]
        return {"size": (52, 60), "lobes": [(_j(rng, x, 2), _j(rng, y, 2), _j(rng, r, 2)) for x, y, r in lobes],
                "trunk": {"width": rng.choice([7, 8, 9]), "top": 34, "flare": 3, "lean": rng.randint(-2, 2)}}
    if kind == "oak":
        lobes = [(32, 31, 16), (14, 35, 12), (50, 35, 12), (23, 21, 14), (41, 21, 14), (32, 12, 11), (8, 28, 8), (56, 28, 8)]
        lobes = [(_j(rng, x, 2), _j(rng, y, 2), _j(rng, r, 1)) for x, y, r in lobes]
        if rng.random() < 0.5:
            lobes = lobes[:-2]
        return {"size": (64, 64), "lobes": lobes,
                "trunk": {"width": rng.choice([10, 11]), "top": 36, "flare": 5, "lean": rng.randint(-2, 2)}}
    if kind == "birch":
        lobes = [(20, 26, 11), (13, 33, 8), (27, 33, 9), (20, 15, 9), (21, 7, 6)]
        return {"size": (40, 68), "lobes": [(_j(rng, x, 1), _j(rng, y, 2), _j(rng, r, 1)) for x, y, r in lobes],
                "trunk": {"width": 5, "top": 30, "flare": 1, "lean": rng.randint(-3, 3)}, "bark_marks": True}
    if kind == "pine":
        n = rng.choice([4, 5])
        tiers, top = [], 3
        for i in range(n):
            half = 7 + i * (13 // max(1, n - 1)) + rng.randint(0, 2)
            bottom = top + 12 + rng.randint(0, 2)
            tiers.append((top, bottom, half))
            top = bottom - 6
        h = tiers[-1][1] + 14
        return {"size": (44, h), "tiers": tiers, "trunk": {"width": 5, "top": tiers[-1][1] - 4, "flare": 2, "lean": 0}}
    if kind == "willow":
        lobes = [(32, 24, 17), (16, 28, 13), (48, 28, 13), (32, 13, 12)]
        return {"size": (64, 64), "lobes": [(_j(rng, x, 2), _j(rng, y, 2), _j(rng, r, 1)) for x, y, r in lobes],
                "trunk": {"width": 8, "top": 34, "flare": 3, "lean": rng.randint(-2, 2)}, "strands": True}
    if kind == "bush":
        lobes = [(11, 9, 7), (6, 11, 5), (16, 11, 5)]
        return {"size": (23, 17), "lobes": [(_j(rng, x, 1), _j(rng, y, 1), _j(rng, r, 1)) for x, y, r in lobes], "trunk": None}
    if kind == "stump":
        return {"size": (16, 12), "stump": True, "trunk": None}
    raise KeyError(kind)


def _fit(layout):
    """Widen the canvas (keeping the trunk centred) so jittered lobes never clip its edge."""
    lobes = layout.get("lobes")
    if not lobes:
        return layout
    w, h = layout["size"]
    lo = min(cx - r for cx, cy, r in lobes) - 2
    hi = max(cx + r for cx, cy, r in lobes) + 2
    need = int(2 * max(w / 2.0 - lo, hi - w / 2.0))
    if need > w:
        need += need % 2
        shift = (need - w) // 2
        layout = dict(layout, size=(need, h), lobes=[(cx + shift, cy, r) for cx, cy, r in lobes])
    return layout


def _sphere_canopy(layout, rng):
    """(mask, shade) for a lobed canopy, lit per-lobe as spheres in a height field."""
    w, h = layout["size"]
    best = [[None] * w for _ in range(h)]
    for li, (cx, cy, r) in enumerate(layout["lobes"]):
        lift = (h - cy) * 0.35            # higher lobes sit "in front", over lower ones
        for y in range(max(0, cy - r), min(h, cy + r + 1)):
            for x in range(max(0, cx - r), min(w, cx + r + 1)):
                d2 = (x - cx) ** 2 + (y - cy) ** 2
                if d2 > r * r:
                    continue
                z = _math.sqrt(r * r - d2) + lift
                if best[y][x] is None or z > best[y][x][0]:
                    best[y][x] = (z, li, (x - cx) / r, (y - cy) / r, _math.sqrt(max(0.0, 1 - d2 / (r * r))))
    mask = [[1 if best[y][x] else 0 for x in range(w)] for y in range(h)]
    shade = _blank(w, h)
    for y in range(h):
        for x in range(w):
            b = best[y][x]
            if not b:
                continue
            _, li, nx, ny, nz = b
            lam = nx * LIGHT3[0] + ny * LIGHT3[1] + nz * LIGHT3[2]
            s = 3 if lam > 0.66 else (2 if lam > 0.12 else 1)
            # a crease: this clump tucks under a neighbouring one just below/right of it
            for dx, dy in ((1, 0), (0, 1)):
                nb = best[y + dy][x + dx] if (y + dy < h and x + dx < w) else None
                if nb and nb[1] != li and nb[0] > b[0] + 0.5:
                    s = 1
            # leaf texture: a few glints in the mid-tones, a few shadows in the light
            roll = rng.random()
            if s == 2 and roll < 0.035:
                s = 3
            elif s == 3 and roll < 0.03:
                s = 2
            elif s == 2 and roll > 0.975:
                s = 1
            shade[y][x] = s
    # crisp silhouette: the shadow side's very edge is always dark
    for y in range(h):
        for x in range(w):
            if mask[y][x] and not (_solid(mask, x + 1, y) and _solid(mask, x, y + 1)):
                shade[y][x] = 1
    return mask, shade


def _pine_canopy(layout, rng):
    w, h = layout["size"]
    mask, shade = _blank(w, h), _blank(w, h)
    cx = w / 2.0
    for (top, bottom, half) in layout["tiers"]:
        for y in range(top, min(h, bottom + 1)):
            t = (y - top) / max(1, bottom - top)
            hw = half * t + (1 if (y % 3 == 0 and t > 0.3) else 0)   # jagged needle edge
            for x in range(int(round(cx - hw)), int(round(cx + hw)) + 1):
                if 0 <= x < w:
                    rel = (x - cx) / max(1.0, hw)
                    s = 3 if rel < -0.30 else (1 if rel > 0.42 else 2)
                    if y >= bottom - 1:
                        s = 1                                  # each tier's shadowed underside
                    if s == 2 and rng.random() < 0.08:
                        s = 3
                    mask[y][x] = 1
                    shade[y][x] = s
    return mask, shade


def _strands(layout, mask, rng):
    """A willow's hanging curtains: soft strands of leaves drooping from the canopy's lower edge,
    painted AFTER the outline (an outlined 1px strand would read as a black fringe). Returns
    [(x, y, shade)]; lengths swell and shrink along the edge so the curtain hangs in locks."""
    w, h = layout["size"]
    out = []
    phase = rng.random() * 6.28
    for x in range(3, w - 3):
        if x % 3 == 0:
            continue                                   # gaps between the locks
        lowest = max((y for y in range(h) if mask[y][x]), default=None)
        if lowest is None or lowest < 18:
            continue
        length = int(7 + 5 * _math.sin(x * 0.45 + phase) + rng.randint(0, 3))
        for k, y in enumerate(range(lowest - 1, min(h - 8, lowest + length))):
            out.append((x, y, 3 if (x % 3 == 1 and k % 4 == 0) else (1 if k == length - 1 else 2)))
    return out


def _trunk(layout):
    w, h = layout["size"]
    t = layout["trunk"]
    mask = _blank(w, h)
    cx0 = w / 2.0
    for y in range(t["top"], h):
        u = (y - t["top"]) / max(1, h - 1 - t["top"])
        grow = t["flare"] * u
        cx = cx0 + t.get("lean", 0) * (1 - u)          # leans at the top, planted at the base
        half = (t["width"] + grow) / 2.0
        for x in range(int(round(cx - half)), int(round(cx + half))):
            if 0 <= x < w:
                mask[y][x] = 1
    return mask


def _stump(layout):
    w, h = layout["size"]
    mask, shade = _blank(w, h), _blank(w, h)
    for y in range(h):
        for x in range(w):
            top = ((x - 7.5) / 6.5) ** 2 + ((y - 3.5) / 2.6) ** 2 <= 1.0
            side = 2 <= x <= 13 and 3 <= y <= 10
            if top or side:
                mask[y][x] = 1
                if top:
                    ring = ((x - 7.5) / 4.0) ** 2 + ((y - 3.5) / 1.6) ** 2
                    shade[y][x] = 2 if 0.5 < ring <= 1.0 else 3
                else:
                    shade[y][x] = 3 if x < 5 else (1 if x > 11 else 2)
    return mask, shade


FRUIT = ((150, 30, 30), (204, 52, 40), (246, 140, 110))
BERRY = ((44, 40, 110), (70, 72, 168), (150, 160, 230))
BLOSSOM = ((206, 120, 150), (240, 170, 196), (255, 232, 240))


def _dots(mask, shade, ramp, n, rng, size=2):
    """Scatter little fruit/berries/blossoms over the lit part of a canopy: [(x, y, rgba)]."""
    h, w = len(mask), len(mask[0])
    cand = [(x, y) for y in range(2, h - 3) for x in range(2, w - 3)
            if mask[y][x] and shade[y][x] >= 2 and _solid(mask, x + 1, y + 1)
            and _solid(mask, x - 1, y - 1) and _solid(mask, x + 2, y + 2)]
    rng.shuffle(cand)
    out, taken = [], set()
    for (x, y) in cand:
        if len(out) >= n * size * size:
            break
        if any((x + dx, y + dy) in taken for dx in range(-2, 3) for dy in range(-2, 3)):
            continue
        cells = [(0, 0, 2), (1, 0, 1), (0, 1, 1), (1, 1, 0)] if size == 2 else [(0, 0, 1)]
        for dx, dy, k in cells:
            out.append((x + dx, y + dy, ramp[k] + (255,)))
            taken.add((x + dx, y + dy))
    return out


def make_grove_parts(kind, seed, foliage="summer", bark="brown", dots=None):
    """(trunk_img or None, canopy_img) for one seeded grove design."""
    layout = _fit(_design(kind, seed))
    rng = _random.Random("shade-%s-%d-%s" % (kind, seed, foliage))
    w, h = layout["size"]
    if layout.get("stump"):
        mask, shade = _stump(layout)
        return None, _paint_part(shade, mask, BARK[bark])
    if "tiers" in layout:
        mask, shade = _pine_canopy(layout, rng)
    else:
        mask, shade = _sphere_canopy(layout, rng)
    canopy = _paint_part(shade, mask, FOLIAGE[foliage])
    if layout.get("strands"):
        cpx = canopy.load()
        for x, y, sh in _strands(layout, mask, rng):
            cpx[x, y] = FOLIAGE[foliage][sh - 1] + (255,)
    if dots:
        ramp, n = {"fruit": (FRUIT, 7), "berry": (BERRY, 6), "blossom": (BLOSSOM, 9)}[dots]
        px = canopy.load()
        for x, y, c in _dots(mask, shade, ramp, n, rng, 2 if dots == "fruit" else 1):
            px[x, y] = c
    trunk_img = None
    if layout.get("trunk"):
        tm = _trunk(layout)
        ts = _shade_trunk(tm)
        trunk_img = _paint_part(ts, tm, BARK[bark])
        if layout.get("bark_marks"):
            tpx = trunk_img.load()
            for y in range(layout["trunk"]["top"], h - 1):
                if rng.random() < 0.22:
                    row = [x for x in range(w) if tm[y][x]]
                    if row:
                        x0 = rng.choice(row)
                        for x in range(x0, min(x0 + rng.randint(1, 3), row[-1] + 1)):
                            tpx[x, y] = (46, 40, 38, 255)
    return trunk_img, canopy


# The catalog the game bakes: name -> (design, seed, foliage, bark, dots). Several seeds per
# design so a grove never repeats; the ramps vary too. art.json's "tree" variants list these
# (a name may be listed more than once to weight it).
GROVE = {
    "round_a":  ("round", 1, "summer", "brown", None),
    "round_b":  ("round", 2, "summer_bright", "brown", None),
    "round_c":  ("round", 3, "summer_deep", "dark", None),
    "oak_a":    ("oak", 1, "summer", "dark", None),
    "oak_b":    ("oak", 2, "summer_deep", "brown", None),
    "birch_a":  ("birch", 1, "birch", "birch", None),
    "birch_b":  ("birch", 2, "birch", "birch", None),
    "pine_a":   ("pine", 1, "pine", "dark", None),
    "pine_b":   ("pine", 2, "pine", "dark", None),
    "willow_a": ("willow", 1, "willow", "brown", None),
    "fruit_a":  ("round", 4, "summer_bright", "brown", "fruit"),
    "blossom_a": ("round", 5, "summer", "brown", "blossom"),
    "autumn_a": ("round", 6, "autumn", "brown", None),
    "autumn_b": ("oak", 3, "autumn_red", "dark", None),
}
GREAT = {
    "great_a": ("great_oak", 7, "summer", "dark", None),
    "great_b": ("great_round", 8, "summer_deep", "brown", None),
    "great_c": ("great_willow", 9, "willow", "brown", None),
}
UNDERSTORY = {
    "bush_a":     ("bush", 1, "summer", "brown", None),
    "bush_b":     ("bush", 2, "summer_deep", "brown", None),
    "bush_c":     ("bush", 3, "summer_bright", "brown", None),
    "bush_berry": ("bush", 4, "summer_deep", "brown", "berry"),
    "bush_bloom": ("bush", 5, "summer", "brown", "blossom"),
    "stump":      ("stump", 1, "summer", "brown", None),
}


def grove_preview(scale=3):
    items = list(GROVE.items()) + list(UNDERSTORY.items()) + list(GREAT.items())
    cellw, cellh = 140, 140
    cols = 7
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cellw + 8, rows * cellh + 8), (86, 126, 74, 255))
    for i, (name, spec) in enumerate(items):
        trunk, canopy = make_grove_parts(spec[0], spec[1], spec[2], spec[3], spec[4])
        r, c = divmod(i, cols)
        for img in (trunk, canopy):
            if img is None:
                continue
            ox = 8 + c * cellw + (cellw - 8 - img.width) // 2
            oy = 8 + r * cellh + (cellh - 8 - img.height)
            sheet.paste(img, (ox, oy), img)
    return sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)


def preview_grid(scale=4):
    """One row per kind, one column per variant -- eyeball the shape and the ramps."""
    kinds = list(LAYOUTS)
    variants = list(RAMPS)
    cellw = max(LAYOUTS[k]["size"][0] for k in kinds) + 8
    cellh = max(LAYOUTS[k]["size"][1] for k in kinds) + 8
    sheet = Image.new("RGBA",
                      (len(variants) * cellw + 8, len(kinds) * cellh + 8),
                      (58, 58, 70, 255))
    for r, kind in enumerate(kinds):
        for c, variant in enumerate(variants):
            spr = make_tree(kind, variant)
            # bottom-align in the cell, like the trees sit on the ground
            ox = 8 + c * cellw + (cellw - 8 - spr.width) // 2
            oy = 8 + r * cellh + (cellh - 8 - spr.height)
            sheet.paste(spr, (ox, oy), spr)
    return sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)


if __name__ == "__main__":
    preview_grid().save("trees.png")
    grove_preview().save("grove.png")
    print("saved trees.png, grove.png")
