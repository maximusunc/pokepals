"""
Nocthollow -- the bioluminescent night-planet's pixel art: its trees, its tall growths,
its small props, and its creatures. One module because the whole planet shares ONE
look that is deliberately unlike the meadow worlds:

  * a night palette -- deep indigo/violet materials instead of greens and browns;
  * GLOW pixels -- the luminous parts (gills, spots, tendrils, antennae, runes) are
    painted in bright emissive colours that the client also haloes with a soft light,
    so the art reads as lit FROM WITHIN rather than by the sun;
  * the same pixel language as the rest of the game otherwise -- light from the
    upper-left on solid materials, the shared 1px near-black outline -- so it still
    sits beside the player and companion as part of one hand-made world.

Everything is procedural primitives (discs, ellipses, polygons, lines) on a small
canvas, like the round props in props.py -- far less error-prone than hand-counting
curves. No randomness: every sprite is reproducible from the numbers below.

Outputs (baked by tools/gen_nocthollow.py):
  * trees  -- trunk + canopy layers (only the canopy sways), several colour variants;
  * tall growths -- single-layer sprites drawn as y-sorted scenery (crystal spires,
    bell-flowers, spore-stalks) so you can walk behind them;
  * props  -- BASE + optional grayscale TINT layer, the props.py convention (the tint is
    the part whose colour is data on the prop, e.g. a bloom's glow);
  * creatures -- ambient-pal sheets in the PalView layout (8 motion columns x the five
    right-handed facings), several colour variants per species.
"""

import math

from PIL import Image

from props import OUTLINE, TINT_VALUE, _c, _role

# ----------------------------------------------------------------------- canvas


class Canvas:
    """A small RGBA canvas with a solid mask (for the outline) plus a parallel grayscale
    TINT image, mirroring props.Canvas -- extended with ellipse/polygon/line primitives and
    GLOW pixels, which are opaque like any other but skip the outline so a light reads as
    light rather than as an inked shape."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.tint = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px, self.tpx = self.img.load(), self.tint.load()
        self.solid = [[0] * w for _ in range(h)]
        self.has_tint = False

    def inside(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h

    def put(self, x, y, rgb, solid=True, alpha=1.0):
        x, y = int(x), int(y)
        if not self.inside(x, y):
            return
        r, g, b, _ = _c(rgb)
        self.px[x, y] = (r, g, b, round(255 * alpha))
        self.solid[y][x] = 1 if solid else self.solid[y][x]

    def glow(self, x, y, rgb):
        # Opaque, but NOT marked solid: the outline pass leaves light un-inked.
        self.put(x, y, rgb, solid=False)

    def tint_px(self, x, y, role):
        x, y = int(x), int(y)
        if not self.inside(x, y):
            return
        v = round(TINT_VALUE[role] * 255)
        self.tpx[x, y] = (v, v, v, 255)
        self.solid[y][x] = 1
        self.has_tint = True

    def clear(self, x, y):
        x, y = int(x), int(y)
        if self.inside(x, y):
            self.px[x, y] = (0, 0, 0, 0)
            self.tpx[x, y] = (0, 0, 0, 0)
            self.solid[y][x] = 0

    # -- shapes: each calls fn(x, y, dx, dy) for every covered pixel
    def ellipse(self, cx, cy, rx, ry, fn, top_only=False):
        for y in range(int(math.floor(cy - ry)), int(math.ceil(cy + ry)) + 1):
            for x in range(int(math.floor(cx - rx)), int(math.ceil(cx + rx)) + 1):
                dx, dy = x - cx, y - cy
                if (dx * dx) / max(0.01, rx * rx) + (dy * dy) / max(0.01, ry * ry) <= 1.0:
                    if not top_only or dy <= 0:
                        fn(x, y, dx, dy)

    def disc(self, cx, cy, r, fn, top_only=False):
        self.ellipse(cx, cy, r, r, fn, top_only)

    def poly(self, pts, fn):
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            for x in range(int(min(xs)), int(max(xs)) + 1):
                if _in_poly(x + 0.5, y + 0.5, pts):
                    fn(x, y, x - sum(xs) / len(xs), y - sum(ys) / len(ys))

    def line(self, a, b, fn, width=1.0):
        steps = int(max(abs(b[0] - a[0]), abs(b[1] - a[1]))) + 1
        for i in range(steps + 1):
            t = i / max(1, steps)
            x = a[0] + (b[0] - a[0]) * t
            y = a[1] + (b[1] - a[1]) * t
            if width <= 1.0:
                fn(int(round(x)), int(round(y)), 0, 0)
            else:
                self.disc(x, y, width * 0.5, fn)

    def outline(self):
        out = []
        for y in range(self.h):
            for x in range(self.w):
                if self.solid[y][x]:
                    continue
                if self.px[x, y][3] > 0:  # a glow pixel: light stays un-inked
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and self.solid[ny][nx]:
                        out.append((x, y))
                        break
        for x, y in out:
            self.px[x, y] = OUTLINE


def _in_poly(x, y, pts):
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi:
            inside = not inside
        j = i
    return inside


def lit(ramp, dx, dy, r):
    """A fixed-material lit-blob shade from an offset: (dark, base, light) ramp picked by the
    same upper-left light rule as props._role."""
    return ramp[{"1": 0, "2": 1, "3": 2}[_role(dx, dy, r)]]


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# ------------------------------------------------------------------- palettes
# Night materials (dark, base, light): what Nocthollow is MADE of in place of bark/leaf/stone.
STALK = ((0.30, 0.24, 0.44), (0.48, 0.42, 0.64), (0.70, 0.66, 0.84))   # pale fungal stems
BARK = ((0.08, 0.06, 0.17), (0.16, 0.12, 0.30), (0.28, 0.22, 0.44))    # elder-tree bark
CROWN = ((0.06, 0.08, 0.22), (0.12, 0.16, 0.36), (0.22, 0.28, 0.54))   # elder foliage
MOSS = ((0.04, 0.16, 0.20), (0.08, 0.28, 0.32), (0.16, 0.44, 0.44))    # teal moss / leaves
ROCK = ((0.12, 0.10, 0.22), (0.22, 0.20, 0.36), (0.36, 0.34, 0.52))    # violet stone

# The colour sets the trees come in: cap ramp + the glow its gills/spots give off.
CAP_VARIANTS = {
    "teal":   {"cap": ((0.04, 0.20, 0.28), (0.08, 0.34, 0.44), (0.20, 0.56, 0.62)), "glow": (0.56, 1.00, 0.92)},
    "violet": {"cap": ((0.18, 0.06, 0.30), (0.32, 0.12, 0.50), (0.52, 0.28, 0.70)), "glow": (1.00, 0.58, 0.96)},
    "azure":  {"cap": ((0.05, 0.08, 0.30), (0.10, 0.18, 0.50), (0.24, 0.36, 0.76)), "glow": (0.58, 0.80, 1.00)},
}
ELDER_VARIANTS = {
    "cyan":    (0.50, 0.98, 1.00),
    "magenta": (1.00, 0.52, 0.90),
}


# ======================================================================= TREES
# The size + feet convention the client's TreeView expects (same as trees.py): a normal tree
# is 52x60 with its ground point 6px above the bottom edge, a great tree 104x122 / 8px.
TREE_W, TREE_H, TREE_FOOT = 52, 60, 6
GREAT_W, GREAT_H, GREAT_FOOT = 104, 122, 8


def glowcap_tree(variant):
    """A tall mushroom-tree: a pale, gently curving stalk (trunk layer) under a broad domed cap
    whose underside gills and scattered spots glow (canopy layer). Returns (trunk, canopy)."""
    v = CAP_VARIANTS[variant]
    gy = TREE_H - TREE_FOOT - 1  # ground row
    trunk = Canvas(TREE_W, TREE_H)
    # root bulb, then the stalk tapering upward with a slight lean
    trunk.ellipse(26, gy - 2, 6, 3, lambda x, y, dx, dy: trunk.put(x, y, lit(STALK, dx, dy, 6)))
    for y in range(18, gy):
        t = (gy - y) / (gy - 18)
        cx = 26 + 2.0 * math.sin(t * 2.2)
        half = 3.2 - 1.2 * t
        for x in range(int(cx - half), int(cx + half) + 1):
            dx = x - cx
            trunk.put(x, y, STALK[2] if dx < -half * 0.4 else (STALK[0] if dx > half * 0.5 else STALK[1]))
    # a faint glowing ring partway up the stalk
    for x in range(24, 29):
        trunk.glow(x, 34, mix(STALK[2], v["glow"], 0.6))
    trunk.outline()

    canopy = Canvas(TREE_W, TREE_H)
    cx, cy = 26, 20
    canopy.ellipse(cx, cy, 24, 14, lambda x, y, dx, dy: canopy.put(x, y, lit(v["cap"], dx, dy * 1.4, 18)), top_only=True)
    # a thin lip under the dome so it reads as a cap, not a half-disc
    for x in range(cx - 23, cx + 24):
        canopy.put(x, cy + 1, v["cap"][0])
    canopy.outline()
    # the glowing gills: a lighter band just under the lip, brightest at the centre
    for x in range(cx - 20, cx + 21):
        k = 1.0 - abs(x - cx) / 21.0
        canopy.glow(x, cy + 2, mix(v["cap"][2], v["glow"], 0.45 + 0.5 * k))
        if abs(x - cx) < 15:
            canopy.glow(x, cy + 3, mix(v["cap"][1], v["glow"], 0.25 + 0.4 * k))
    # luminous spots on the dome
    for sx, sy, r in [(14, 13, 1.6), (22, 9, 1.2), (31, 11, 1.8), (38, 15, 1.2), (19, 16, 1.0), (28, 16, 1.1), (35, 8, 0.9)]:
        canopy.disc(sx, sy, r, lambda x, y, dx, dy: canopy.glow(x, y, v["glow"]))
    return trunk.img, canopy.img


def elder_tree(variant):
    """The Lumen Elder: a huge, twisting dark tree whose crown trails curtains of glowing
    tendrils (a weeping willow made of light). Returns (trunk, canopy)."""
    glow = ELDER_VARIANTS[variant]
    gy = GREAT_H - GREAT_FOOT - 1
    trunk = Canvas(GREAT_W, GREAT_H)
    # spreading roots
    for ex, ey in [(30, gy), (40, gy + 1), (64, gy + 1), (76, gy)]:
        trunk.line((52, gy - 10), (ex, ey), lambda x, y, dx, dy: trunk.put(x, y, BARK[1]), width=4.0)
    # the twisting bole
    for y in range(44, gy - 4):
        t = (gy - y) / (gy - 44)
        cx = 52 + 4.0 * math.sin(t * 3.4)
        half = 9.0 - 4.0 * t
        for x in range(int(cx - half), int(cx + half) + 1):
            dx = x - cx
            trunk.put(x, y, BARK[2] if dx < -half * 0.45 else (BARK[0] if dx > half * 0.4 else BARK[1]))
    trunk.outline()
    # glowing veins climbing the bark
    for k, off in enumerate((-4, 2, 6)):
        for y in range(52, gy - 6):
            t = (gy - y) / (gy - 44)
            x = 52 + 4.0 * math.sin(t * 3.4) + off + 1.5 * math.sin(y * 0.35 + k * 2.0)
            if (y + k * 3) % 9 < 6:
                trunk.glow(int(round(x)), y, mix(BARK[2], glow, 0.7))

    canopy = Canvas(GREAT_W, GREAT_H)
    lobes = [(52, 30, 30), (28, 40, 20), (76, 40, 20), (40, 22, 18), (64, 22, 18), (52, 46, 22)]
    for lx, ly, lr in lobes:
        canopy.ellipse(lx, ly, lr, lr * 0.8, lambda x, y, dx, dy, lr=lr: canopy.put(x, y, lit(CROWN, dx, dy, lr)))
    canopy.outline()
    # speckles of light in the crown
    for sx, sy in [(30, 34), (44, 18), (60, 26), (72, 36), (52, 40), (38, 44), (66, 46), (56, 14), (24, 42), (80, 42)]:
        canopy.glow(sx, sy, mix(CROWN[2], glow, 0.8))
    # hanging tendrils from the crown's underside, bright beads toward their tips
    for i, tx in enumerate(range(14, 92, 4)):
        top = 44 + int(10 * (1 - abs(tx - 52) / 40.0))
        length = 14 + (i * 7) % 22
        for y in range(top, min(GREAT_H - 2, top + length)):
            sway = int(round(math.sin((y - top) * 0.25 + i) * 0.8))
            k = (y - top) / max(1, length)
            canopy.glow(tx + sway, y, mix(CROWN[1], glow, 0.35 + 0.6 * k))
        canopy.glow(tx + int(round(math.sin(length * 0.25 + i) * 0.8)), min(GREAT_H - 2, top + length), (1.0, 1.0, 1.0))
    return trunk.img, canopy.img


# ================================================================ TALL GROWTHS
# Single-layer sprites drawn as y-sorted scenery (so you can walk behind them). Same feet
# convention as a normal tree (52x60, ground 6px above the bottom).

def crystal_spire(variant):
    """A cluster of tall, faceted crystals humming with light."""
    hue = {"cyan": ((0.10, 0.40, 0.56), (0.30, 0.74, 0.86), (0.78, 1.00, 1.00)),
           "rose": ((0.40, 0.12, 0.40), (0.76, 0.36, 0.78), (1.00, 0.80, 1.00)),
           "gold": ((0.40, 0.28, 0.10), (0.80, 0.64, 0.30), (1.00, 0.94, 0.70))}[variant]
    c = Canvas(TREE_W, TREE_H)
    gy = TREE_H - TREE_FOOT - 1
    shards = [
        # (base x, base half-width, top x, top y)
        (18, 4, 13, 22),
        (34, 4, 39, 26),
        (26, 6, 26, 4),
        (22, 3, 20, 34),
        (31, 3, 33, 38),
    ]
    for bx, bw, tx, ty in shards:
        pts = [(bx - bw, gy), (bx - bw, gy - 6), (tx - 1, ty + 4), (tx, ty), (tx + 1, ty + 4), (bx + bw, gy - 6), (bx + bw, gy)]
        mid = (bx + tx) / 2.0

        def facet(x, y, dx, dy, mid=mid, tx=tx, bx=bx):
            # left facet bright, right facet dark, a lit ridge down the middle
            axis = tx + (bx - tx) * ((y - 0) / max(1, gy))
            if abs(x - axis) < 0.8:
                c.put(x, y, hue[2])
            elif x < axis:
                c.put(x, y, mix(hue[1], hue[2], 0.35))
            else:
                c.put(x, y, hue[0] if x > axis + 2 else hue[1])
        c.poly(pts, facet)
    c.outline()
    # a few glint pixels
    for gx, gyy in [(26, 7), (13, 25), (39, 29), (25, 20)]:
        c.glow(gx, gyy, (1.0, 1.0, 1.0))
    return c.img


def bell_flower(variant):
    """A giant arching flower whose hanging bell glows from its open mouth."""
    glow = {"blue": (0.55, 0.85, 1.00), "pink": (1.00, 0.62, 0.92), "lime": (0.78, 1.00, 0.60)}[variant]
    petal = mix((0.10, 0.10, 0.30), glow, 0.45)
    c = Canvas(TREE_W, TREE_H)
    gy = TREE_H - TREE_FOOT - 1
    # leaves at the foot
    c.ellipse(20, gy - 3, 7, 3, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 6)))
    c.ellipse(31, gy - 2, 6, 2.5, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 6)))
    # the arching stem: up from the foot, over, and down to the bell
    pts = []
    for i in range(0, 41):
        t = i / 40.0
        x = 24 + 12 * math.sin(t * math.pi * 0.9) - 2 * t
        y = gy - 44 * math.sin(t * math.pi * 0.62)
        pts.append((x, y))
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        c.line((ax, ay), (bx, by), lambda x, y, dx, dy: c.put(x, y, MOSS[1]), width=2.0)
    hx, hy = pts[-1]
    # the bell, hanging below the stem's tip
    bell = [(hx - 3, hy + 1), (hx + 3, hy + 1), (hx + 7, hy + 12), (hx - 7, hy + 12)]
    c.poly(bell, lambda x, y, dx, dy: c.put(x, y, mix(petal, glow, 0.25) if dx < -1 else petal))
    c.outline()
    for x in range(int(hx - 7), int(hx + 8)):
        c.glow(x, hy + 13, glow)
    for x in range(int(hx - 5), int(hx + 6)):
        c.glow(x, hy + 14, mix(glow, (1, 1, 1), 0.5))
    c.glow(int(hx), hy + 16, (1.0, 1.0, 1.0))  # the stamen's bright drip
    return c.img


def spore_stalk(variant):
    """A tall fungal stalk crowned with glowing spore-pods that look like strings of lanterns."""
    glow = {"amber": (1.00, 0.80, 0.42), "mint": (0.62, 1.00, 0.78)}[variant]
    c = Canvas(TREE_W, TREE_H)
    gy = TREE_H - TREE_FOOT - 1
    for i, (bx, h, lean) in enumerate([(22, 40, -6), (28, 46, 4), (32, 30, 9)]):
        top = (bx + lean, gy - h)
        c.line((bx, gy), top, lambda x, y, dx, dy: c.put(x, y, STALK[1] if (x + y) % 3 else STALK[2]), width=2.0)
        c.disc(top[0], top[1], 4.0 - i * 0.6, lambda x, y, dx, dy: c.put(x, y, lit(STALK, dx, dy, 4)))
    c.outline()
    for i, (bx, h, lean) in enumerate([(22, 40, -6), (28, 46, 4), (32, 30, 9)]):
        tx, ty = bx + lean, gy - h
        c.disc(tx, ty + 0.5, 2.0 - i * 0.3, lambda x, y, dx, dy: c.glow(x, y, glow))
        # little pods dangling along the stalk
        for k in range(1, 4):
            t = k / 4.5
            c.glow(int(round(bx + lean * (1 - t))) + 2, int(round(ty + h * t)), mix(glow, STALK[2], 0.3))
    return c.img


# ======================================================================= PROPS
# BASE + TINT (props.py convention): the tint layer is grayscale and drawn with the prop's own
# colour, so one sprite makes every hue a world author picks.

def _p_glowcaps(c):
    for x0, h, r in [(5, 7, 4.0), (11, 10, 5.0), (17, 5, 3.0)]:
        gy = c.h - 2
        c.ellipse(x0, gy, 1.2, 0.6, lambda x, y, dx, dy: c.put(x, y, STALK[1]))
        for y in range(gy - h, gy + 1):
            c.put(x0, y, STALK[2])
            c.put(x0 + 1, y, STALK[0])
        c.ellipse(x0 + 0.5, gy - h, r, r * 0.7, lambda x, y, dx, dy, rr=r: c.tint_px(x, y, _role(dx, dy, rr)), top_only=True)


def _p_lumen_bloom(c):
    gy = c.h - 2
    c.ellipse(6, gy - 1, 5, 2, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 5)))
    c.ellipse(14, gy - 2, 5, 2, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 5)))
    c.line((10, gy), (10, 10), lambda x, y, dx, dy: c.put(x, y, MOSS[1]))
    c.line((11, gy), (11, 11), lambda x, y, dx, dy: c.put(x, y, MOSS[0]))
    for ang in range(5):
        a = ang * math.tau / 5 - math.pi / 2
        px, py = 10.5 + math.cos(a) * 4.0, 8 + math.sin(a) * 4.0
        c.disc(px, py, 2.6, lambda x, y, dx, dy: c.tint_px(x, y, _role(x - 10.5, y - 8, 6)))
    c.disc(10.5, 8, 2.0, lambda x, y, dx, dy: c.tint_px(x, y, "3"))


def _p_spore_puff(c):
    gy = c.h - 2
    c.ellipse(11, gy - 6, 8, 6.5, lambda x, y, dx, dy: c.tint_px(x, y, _role(dx, dy, 7)))
    c.ellipse(18, gy - 2, 3, 2.5, lambda x, y, dx, dy: c.tint_px(x, y, _role(dx, dy, 3)))
    for px, py in [(8, gy - 9), (13, gy - 10), (10, gy - 5), (15, gy - 6), (7, gy - 4)]:
        c.put(px, py, ROCK[0])


def _p_curl_fern(c):
    gy = c.h - 2
    for k, (bx, sgn, h) in enumerate([(9, -1, 14), (13, 1, 16), (11, -1, 10)]):
        prev = None
        for i in range(0, 30):
            t = i / 29.0
            ang = t * 4.2
            rad = 5.0 * (1 - t) + 1.0
            x = bx + sgn * (t * 5 + math.sin(ang) * rad * t)
            y = gy - h * math.sin(t * math.pi * 0.5) + math.cos(ang) * rad * t * 0.6
            if prev:
                c.line(prev, (x, y), lambda xx, yy, dx, dy: c.put(xx, yy, MOSS[2] if sgn < 0 else MOSS[1]))
            prev = (x, y)
        c.disc(prev[0], prev[1], 1.4, lambda xx, yy, dx, dy: c.tint_px(xx, yy, "3"))


def _p_moonstone(c):
    gy = c.h - 2
    pts = [(4, gy), (3, 10), (6, 4), (11, 2), (16, 4), (19, 10), (18, gy)]
    c.poly(pts, lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx, dy * 0.6, 8)))
    # runes, in the tint (their glow colour is data)
    for x, y in [(11, 7), (11, 8), (10, 9), (12, 9), (11, 10), (11, 13), (10, 14), (12, 14), (9, 15), (13, 15),
                 (11, 18), (11, 19), (10, 20), (11, 21), (12, 20), (8, 11), (14, 11)]:
        c.tint_px(x, y, "3" if (x + y) % 2 else "2")


def _p_star_shard(c):
    gy = c.h - 2
    c.ellipse(9, gy, 8, 2.2, lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx, dy, 6)))
    c.poly([(5, gy - 1), (8, 2), (11, gy - 3), (14, gy - 1)], lambda x, y, dx, dy: c.tint_px(x, y, "3" if dx < 0 else "2"))
    c.poly([(11, gy - 1), (15, 6), (16, gy - 1)], lambda x, y, dx, dy: c.tint_px(x, y, "2" if dx < 0 else "1"))


def _p_lily_light(c):
    c.ellipse(9, 6, 8, 3, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 6)))
    for y in range(4, 7):
        c.clear(13 + (6 - y), y)
    c.disc(8, 3, 2.4, lambda x, y, dx, dy: c.tint_px(x, y, _role(dx, dy, 2.4)))


def _p_glow_moss(c):
    gy = c.h - 2
    c.ellipse(10, gy - 2, 9, 3.2, lambda x, y, dx, dy: c.put(x, y, lit(MOSS, dx, dy, 7)))
    for px, py in [(5, gy - 3), (9, gy - 4), (13, gy - 3), (16, gy - 2), (7, gy - 1), (12, gy - 1), (3, gy - 2)]:
        c.tint_px(px, py, "3")


def _p_vent(c):
    gy = c.h - 2
    c.ellipse(12, gy - 3, 11, 4.5, lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx, dy, 8)))
    c.ellipse(12, gy - 4, 5.5, 2.0, lambda x, y, dx, dy: c.tint_px(x, y, "2" if dy > 0 else "1"))
    c.ellipse(12, gy - 4, 3.0, 1.0, lambda x, y, dx, dy: c.tint_px(x, y, "3"))


def _p_driftwood_arch(c):
    """A low bench-like arch of pale fungal wood -- a place to sit and look at the lake."""
    gy = c.h - 2
    for y in range(gy - 8, gy + 1):
        for x in (3, 4, 25, 26):
            c.put(x, y, STALK[1] if x in (3, 25) else STALK[0])
    for x in range(1, 29):
        y = gy - 9 - int(round(2.5 * math.sin((x - 1) / 27.0 * math.pi)))
        for yy in (y, y + 1, y + 2):
            c.put(x, yy, STALK[2] if yy == y else STALK[1])
    for x in range(4, 26, 3):
        c.tint_px(x, gy - 10 - int(round(2.5 * math.sin((x - 1) / 27.0 * math.pi))), "3")


PROP_BUILDERS = {
    "glowcaps": ((22, 14), _p_glowcaps),
    "lumen_bloom": ((22, 24), _p_lumen_bloom),
    "spore_puff": ((24, 18), _p_spore_puff),
    "curl_fern": ((24, 20), _p_curl_fern),
    "moonstone": ((22, 30), _p_moonstone),
    "star_shard": ((19, 16), _p_star_shard),
    "lily_light": ((18, 10), _p_lily_light),
    "glow_moss": ((21, 9), _p_glow_moss),
    "vent": ((25, 12), _p_vent),
    "lumen_bench": ((30, 18), _p_driftwood_arch),
}


def make_prop(name):
    """(base, tint_or_None) for a Nocthollow prop."""
    (w, h), fn = PROP_BUILDERS[name]
    c = Canvas(w, h)
    fn(c)
    c.outline()
    return c.img, (c.tint if c.has_tint else None)


# =================================================================== CREATURES
# PalView sheet layout: 32x32 cells, 8 motion columns (col 0 = idle), rows in VIEWS order. The
# left-facing family is mirrored at runtime. Feet sit on row 25 (the pal convention); floaters
# hover above a faint shadow on that row.
CELL = 32
COLS = 8
VIEWS = ["down", "down_right", "right", "up_right", "up"]
FOOT = 25
EYE = (0.06, 0.04, 0.10)
SHADOW = (0.02, 0.02, 0.06)

# (body ramp, glow colour) per colour variant.
CREATURE_VARIANTS = {
    "lumejelly": [
        (((0.16, 0.30, 0.56), (0.30, 0.52, 0.80), (0.60, 0.80, 1.00)), (0.70, 0.95, 1.00)),
        (((0.36, 0.14, 0.50), (0.60, 0.30, 0.76), (0.86, 0.60, 0.98)), (1.00, 0.70, 1.00)),
        (((0.10, 0.36, 0.34), (0.22, 0.60, 0.54), (0.50, 0.90, 0.80)), (0.70, 1.00, 0.86)),
    ],
    "glimmerhop": [
        (((0.22, 0.16, 0.40), (0.38, 0.30, 0.62), (0.58, 0.52, 0.84)), (1.00, 0.86, 0.44)),
        (((0.10, 0.26, 0.32), (0.20, 0.44, 0.52), (0.40, 0.68, 0.74)), (0.58, 1.00, 0.86)),
        (((0.36, 0.14, 0.30), (0.58, 0.26, 0.48), (0.82, 0.48, 0.70)), (0.86, 0.94, 1.00)),
    ],
    "stiltwhisk": [
        (((0.18, 0.18, 0.36), (0.32, 0.32, 0.56), (0.52, 0.54, 0.78)), (0.56, 0.98, 1.00)),
        (((0.30, 0.16, 0.24), (0.50, 0.30, 0.42), (0.72, 0.50, 0.62)), (1.00, 0.66, 0.80)),
        (((0.14, 0.24, 0.20), (0.26, 0.42, 0.36), (0.46, 0.64, 0.56)), (0.86, 1.00, 0.56)),
    ],
    "driftray": [
        (((0.08, 0.10, 0.28), (0.16, 0.22, 0.48), (0.32, 0.42, 0.72)), (0.50, 0.90, 1.00)),
        (((0.22, 0.06, 0.26), (0.40, 0.14, 0.46), (0.62, 0.32, 0.68)), (1.00, 0.50, 0.86)),
        (((0.06, 0.18, 0.22), (0.12, 0.32, 0.38), (0.26, 0.52, 0.56)), (0.60, 1.00, 0.80)),
    ],
    "lanternsnail": [
        (((0.26, 0.22, 0.40), (0.44, 0.40, 0.60), (0.66, 0.62, 0.80)), (0.56, 1.00, 0.96)),
        (((0.24, 0.24, 0.30), (0.42, 0.42, 0.50), (0.64, 0.64, 0.72)), (1.00, 0.76, 0.46)),
        (((0.30, 0.20, 0.30), (0.50, 0.36, 0.48), (0.72, 0.56, 0.68)), (0.92, 0.60, 1.00)),
    ],
}


def _shadow(c, cx, rx):
    c.ellipse(cx, FOOT, rx, 1.2, lambda x, y, dx, dy: c.put(x, y, SHADOW, solid=False, alpha=0.35))


def _eyes(c, cx, cy, view, gap):
    if view == "up":
        return
    if view in ("right", "up_right"):
        if view == "right":
            c.put(cx + gap, cy, EYE)
            c.put(cx + gap, cy - 1, (1, 1, 1), )
        return
    if view == "down_right":
        c.put(cx - gap + 2, cy, EYE)
        c.put(cx + gap + 1, cy, EYE)
        return
    c.put(cx - gap, cy, EYE)
    c.put(cx + gap, cy, EYE)


def _lumejelly(c, view, f, ramp, glow):
    """A floating jelly: a translucent dome trailing swaying, glowing tendrils. Drifts with a slow
    bob; views barely differ (it's round), it only leans into its travel."""
    _shadow(c, 16, 5)
    bob = [0, -1, -1, -2, -2, -1, -1, 0][f]
    lean = {"right": 2, "down_right": 1, "up_right": 1}.get(view, 0)
    cx, cy = 16 - lean, 10 + bob
    for i, tx in enumerate(range(cx - 5, cx + 6, 2)):
        for k in range(0, 9):
            sway = math.sin(f * math.tau / COLS + i * 0.9 + k * 0.5) * (0.4 + k * 0.12) + lean * k * 0.25
            c.glow(int(round(tx + sway)), cy + 4 + k, mix(ramp[1], glow, 0.3 + k * 0.07))
    c.ellipse(cx, cy + 1, 7, 6, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 6)), top_only=True)
    for x in range(cx - 7, cx + 8):
        c.put(x, cy + 2, ramp[0])
    c.outline()
    for x in range(cx - 5, cx + 6, 2):
        c.glow(x, cy + 3, glow)
    c.disc(cx - 2, cy - 2, 1.0, lambda x, y, dx, dy: c.glow(x, y, mix(ramp[2], (1, 1, 1), 0.6)))
    if view != "up":
        c.put(cx - 2 + lean, cy, EYE)
        c.put(cx + 2 + lean, cy, EYE)


def _glimmerhop(c, view, f, ramp, glow):
    """A round, big-eyed hopper with a lantern-bulb on a curling antenna."""
    hop = [0, -1, -3, -4, -3, -1, 0, 0][f]
    squash = 1 if f in (0, 6) else 0
    _shadow(c, 16, 5 - (1 if hop < -2 else 0))
    cx, cy = 16, 19 + hop
    side = view in ("right", "up_right")
    # little feet
    c.put(cx - 3, FOOT - 1 + min(0, hop + 2), ramp[0])
    c.put(cx + 3, FOOT - 1 + min(0, hop + 2), ramp[0])
    c.ellipse(cx, cy, 6 + squash, 5.5 - squash, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 6)))
    # the antenna: up from the head, curling forward in profile
    ax = 1 if side or view == "down_right" else 0
    pts = [(cx, cy - 5), (cx + ax, cy - 8), (cx + 2 * ax + 1, cy - 10), (cx + 3 * ax + 2, cy - 10)]
    if view in ("down", "up"):
        pts = [(cx, cy - 5), (cx, cy - 8), (cx + 1, cy - 10), (cx + 2, cy - 11)]
    for a, b in zip(pts, pts[1:]):
        c.line(a, b, lambda x, y, dx, dy: c.put(x, y, ramp[0]))
    c.outline()
    bx, by = pts[-1]
    c.disc(bx, by - 1, 1.6, lambda x, y, dx, dy: c.glow(x, y, glow))
    c.glow(bx, by - 1, (1, 1, 1))
    # belly glow + big eyes
    if view != "up":
        c.ellipse(cx, cy + 2, 3, 1.5, lambda x, y, dx, dy: c.glow(x, y, mix(ramp[2], glow, 0.4)))
    if view == "down":
        for ex in (cx - 3, cx + 2):
            c.put(ex, cy - 1, EYE); c.put(ex + 1, cy - 1, EYE); c.put(ex, cy - 2, (1, 1, 1)); c.put(ex + 1, cy - 2, EYE)
    elif view == "down_right":
        for ex in (cx - 1, cx + 3):
            c.put(ex, cy - 1, EYE); c.put(ex, cy - 2, (1, 1, 1))
    elif view == "right":
        c.put(cx + 3, cy - 1, EYE); c.put(cx + 4, cy - 1, EYE); c.put(cx + 3, cy - 2, (1, 1, 1))


def _stiltwhisk(c, view, f, ramp, glow):
    """A tall, gentle grazer on long thin legs, with a swan neck and a row of glowing spots
    down its back. Walks with a slow, high-stepping gait."""
    phase = f * math.tau / COLS
    _shadow(c, 16, 6)
    side = view in ("right", "up_right", "down_right")
    if side:
        bx, by = 14, 13
        # four legs: near pair and far pair, swinging opposite
        for k, (lx, ph) in enumerate([(10, 0), (12, math.pi), (17, math.pi), (19, 0)]):
            swing = int(round(math.sin(phase + ph) * 1.6)) if f else 0
            col = ramp[0] if k in (1, 2) else ramp[1]
            c.line((lx, by + 3), (lx + swing, FOOT - 1), lambda x, y, dx, dy, col=col: c.put(x, y, col))
        c.ellipse(bx + 1, by + 1, 7, 3.5, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 6)))
        # neck + head reaching forward-up
        nx = 21 if view != "up_right" else 20
        neck = [(bx + 6, by), (nx, by - 4), (nx + 1, by - 8)]
        for a, b in zip(neck, neck[1:]):
            c.line(a, b, lambda x, y, dx, dy: c.put(x, y, ramp[1]), width=2.0)
        hx, hy = nx + 2, by - 9 + (1 if f in (3, 4) else 0)
        c.ellipse(hx, hy, 2.5, 1.6, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 2)))
        # tail tuft
        c.line((bx - 6, by), (bx - 8, by - 2), lambda x, y, dx, dy: c.put(x, y, ramp[2]))
        c.outline()
        for sx in range(bx - 4, bx + 5, 2):
            c.glow(sx, by - 2, glow)
        c.glow(bx - 8, by - 3, glow)
        if view != "up_right":
            c.put(hx + 1, hy, EYE)
        # antennae-whiskers
        c.glow(hx + 2, hy - 2, mix(glow, (1, 1, 1), 0.5))
    else:
        bx, by = 16, 13
        for k, lx in enumerate([12, 14, 18, 20]):
            lift = (1 if math.sin(phase + (0 if k in (0, 3) else math.pi)) > 0.5 else 0) if f else 0
            c.line((lx, by + 3), (lx, FOOT - 1 - lift), lambda x, y, dx, dy, k=k: c.put(x, y, ramp[1] if k in (0, 3) else ramp[0]))
        c.ellipse(bx, by + 1, 5.5, 4, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 5)))
        c.line((bx, by - 2), (bx, by - 8), lambda x, y, dx, dy: c.put(x, y, ramp[1]), width=2.0)
        hy = by - 10 + (1 if f in (3, 4) else 0)
        c.ellipse(bx, hy, 2.5, 2, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 2)))
        c.outline()
        if view == "down":
            c.put(bx - 1, hy, EYE)
            c.put(bx + 1, hy, EYE)
            c.glow(bx - 2, hy - 3, mix(glow, (1, 1, 1), 0.5))
            c.glow(bx + 2, hy - 3, mix(glow, (1, 1, 1), 0.5))
        else:
            for sy in range(by - 1, by + 4, 2):
                c.glow(bx, sy, glow)


def _driftray(c, view, f, ramp, glow):
    """A small manta that glides through the air, its wings rippling; it hovers high above a
    faint shadow and trails a glowing tail."""
    phase = f * math.tau / COLS
    _shadow(c, 16, 6)
    hover = int(round(math.sin(phase) * 1.0))
    if view in ("right", "up_right"):
        cy = 9 + hover
        # profile: a slim body with the wing tip rising and falling
        c.ellipse(16, cy, 7, 2, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 5)))
        tip = int(round(math.sin(phase) * 4))
        c.poly([(13, cy - 1), (18, cy - 1), (15, cy - 2 - tip)], lambda x, y, dx, dy: c.put(x, y, ramp[2]))
        c.outline()
        for k in range(1, 9):
            c.glow(9 - k, cy + int(round(math.sin(phase + k * 0.6) * 1.2)), mix(ramp[1], glow, 0.4 + 0.07 * k))
        if view == "right":
            c.put(21, cy - 1, EYE)
        c.glow(16, cy + 1, glow)
    else:
        cy = 10 + hover
        flap = math.sin(phase)
        span = 11
        wing_y = int(round(flap * 2.5))
        pts = [(16, cy - 4), (16 + span, cy + wing_y), (16 + 3, cy + 3), (16, cy + 4), (16 - 3, cy + 3), (16 - span, cy + wing_y)]
        c.poly(pts, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 8)))
        c.outline()
        for k in range(1, 8):
            ty = cy + 4 + k if view in ("down", "down_right") else cy - 4 - k
            if view == "up":
                ty = cy + 4 + k
            c.glow(16 + int(round(math.sin(phase + k * 0.7))), ty, mix(ramp[1], glow, 0.4 + 0.08 * k))
        # glowing wing edges + spots
        c.glow(16 + span - 1, cy + wing_y, glow)
        c.glow(16 - span + 1, cy + wing_y, glow)
        c.glow(12, cy + 1, glow)
        c.glow(20, cy + 1, glow)
        if view in ("down", "down_right"):
            off = 1 if view == "down_right" else 0
            c.put(14 + off, cy - 2, EYE)
            c.put(18 + off, cy - 2, EYE)


def _lanternsnail(c, view, f, ramp, glow):
    """A slow snail carrying a glowing crystal shell like a lantern."""
    stretch = [0, 1, 1, 2, 2, 1, 1, 0][f]
    side = view in ("right", "up_right", "down_right")
    shell = mix(ramp[0], glow, 0.35)
    if side:
        _shadow(c, 15, 8)
        # the foot: a long low body, stretching as it glides
        c.ellipse(16 + stretch * 0.5, FOOT - 2, 9 + stretch * 0.5, 2.2, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 6)))
        hx = 24 + stretch
        c.ellipse(hx, FOOT - 4, 2.5, 2.5, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 3)))
        c.line((hx, FOOT - 6), (hx + 1, FOOT - 10), lambda x, y, dx, dy: c.put(x, y, ramp[1]))
        c.line((hx - 1, FOOT - 6), (hx - 2, FOOT - 9), lambda x, y, dx, dy: c.put(x, y, ramp[0]))
        # the crystal shell: a faceted dome on its back
        sx, sy = 13, FOOT - 9
        c.poly([(sx - 7, sy + 6), (sx - 5, sy - 3), (sx, sy - 7), (sx + 5, sy - 3), (sx + 7, sy + 6)],
               lambda x, y, dx, dy: c.put(x, y, mix(shell, glow, 0.35) if dx < -1 else shell))
        c.outline()
        c.glow(hx + 1, FOOT - 11, glow)
        c.glow(hx - 2, FOOT - 10, mix(glow, ramp[2], 0.5))
        if view != "up_right":
            c.put(hx + 1, FOOT - 4, EYE)
        for gx, gy in [(sx - 2, sy - 3), (sx, sy - 5), (sx + 2, sy), (sx - 3, sy + 2), (sx + 1, sy + 3)]:
            c.glow(gx, gy, glow)
    else:
        _shadow(c, 16, 6)
        c.ellipse(16, FOOT - 2, 5, 2.4, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 5)))
        sx, sy = 16, FOOT - 9 + (0 if stretch < 2 else -1)
        c.poly([(sx - 7, sy + 6), (sx - 5, sy - 3), (sx, sy - 7), (sx + 5, sy - 3), (sx + 7, sy + 6)],
               lambda x, y, dx, dy: c.put(x, y, mix(shell, glow, 0.35) if dx < -1 else shell))
        if view == "down":
            c.ellipse(16, FOOT - 4, 3, 2.2, lambda x, y, dx, dy: c.put(x, y, lit(ramp, dx, dy, 3)))
            c.line((14, FOOT - 6), (13, FOOT - 9), lambda x, y, dx, dy: c.put(x, y, ramp[1]))
            c.line((18, FOOT - 6), (19, FOOT - 9), lambda x, y, dx, dy: c.put(x, y, ramp[1]))
        c.outline()
        for gx, gy in [(sx - 2, sy - 3), (sx, sy - 5), (sx + 2, sy), (sx - 3, sy + 2), (sx + 3, sy + 3), (sx, sy + 1)]:
            c.glow(gx, gy, glow)
        if view == "down":
            c.glow(13, FOOT - 10, glow)
            c.glow(19, FOOT - 10, glow)
            c.put(15, FOOT - 4, EYE)
            c.put(17, FOOT - 4, EYE)


CREATURES = {
    "lumejelly": _lumejelly,
    "glimmerhop": _glimmerhop,
    "stiltwhisk": _stiltwhisk,
    "driftray": _driftray,
    "lanternsnail": _lanternsnail,
}


def creature_frame(species, view, frame, variant):
    ramp, glow = CREATURE_VARIANTS[species][variant]
    c = Canvas(CELL, CELL)
    CREATURES[species](c, view, frame, ramp, glow)
    return c.img


def creature_sheet(species, variant):
    sheet = Image.new("RGBA", (COLS * CELL, len(VIEWS) * CELL), (0, 0, 0, 0))
    for r, view in enumerate(VIEWS):
        for f in range(COLS):
            img = creature_frame(species, view, f, variant)
            sheet.paste(img, (f * CELL, r * CELL), img)
    return sheet


def creature_glow(species, variant):
    """The creature's glow colour (what PalView haloes it with), as [r, g, b] in 0..1."""
    return list(CREATURE_VARIANTS[species][variant][1])


# ===================================================================== preview
def preview(path="nocthollow.png", scale=3):
    """Everything on a night ground: tree variants, the elder, tall growths, props, and every
    creature's variant-0 sheet -- for eyeballing."""
    bg = (14, 12, 30, 255)
    items = []
    for v in CAP_VARIANTS:
        t, cnp = glowcap_tree(v)
        im = t.copy(); im.alpha_composite(cnp); items.append(im)
    for v in ELDER_VARIANTS:
        t, cnp = elder_tree(v)
        im = t.copy(); im.alpha_composite(cnp); items.append(im)
    for v in ("cyan", "rose", "gold"):
        items.append(crystal_spire(v))
    for v in ("blue", "pink", "lime"):
        items.append(bell_flower(v))
    for v in ("amber", "mint"):
        items.append(spore_stalk(v))
    demo = [(0.56, 1.0, 0.92), (1.0, 0.6, 0.95), (0.6, 0.8, 1.0)]
    for i, name in enumerate(PROP_BUILDERS):
        base, tint = make_prop(name)
        im = base.copy()
        if tint is not None:
            col = demo[i % 3]
            tp = tint.load()
            tinted = Image.new("RGBA", tint.size, (0, 0, 0, 0))
            tt = tinted.load()
            for y in range(tint.size[1]):
                for x in range(tint.size[0]):
                    r, g, b, a = tp[x, y]
                    if a:
                        tt[x, y] = (int(r * col[0]), int(g * col[1]), int(b * col[2]), a)
            im.alpha_composite(tinted)
        items.append(im)
    sheets = [creature_sheet(sp, 0) for sp in CREATURES]
    pad = 8
    row_w = sum(i.width + pad for i in items) + pad
    w = max(row_w, max(s.width for s in sheets) + 2 * pad)
    h = max(i.height for i in items) + 2 * pad + sum(s.height + pad for s in sheets) + pad
    canvas = Image.new("RGBA", (w, h), bg)
    x = pad
    top = max(i.height for i in items) + pad
    for im in items:
        canvas.alpha_composite(im, (x, top - im.height))
        x += im.width + pad
    y = top + 2 * pad
    for s in sheets:
        canvas.alpha_composite(s, (pad, y))
        y += s.height + pad
    canvas = canvas.resize((canvas.width * scale, canvas.height * scale), Image.NEAREST)
    canvas.save(path)
    print("wrote", path)


if __name__ == "__main__":
    preview()
