"""
Thimblewick -- a tiny cottage garden, seen at beetle size -- pixel art. Everything is GIANT next to you:
flower stalks stand like trees, a clover leaf is an umbrella, a teacup is a pond, the garden fence is a
castle wall of whitewashed pickets, and a dropped button, a coiled hose and a watering can are landmarks.

The look is the meadow worlds' own language (a lit blob under the upper-left light, the shared 1px
outline), in a warm, saturated late-afternoon palette. Built on the machinery the other worlds already
have, but with its own shapes:
  * trees   -- hand-painted trunk (stalk) + canopy (flower head) layers on nocthollow.py's Canvas, plus
               whole-sprite grass clumps and the fence's pickets (one picket is one "tree": y-sorted, so
               you walk behind the fence; a missing picket is a gap only something small can use);
  * ground  -- the seamless terrain atlas in ground.py's layout (R = shade role, G = accent) with
               blades, clover and loam sized for a beetle, plus a detail atlas of garden litter;
  * water   -- one new ramp for water.py: a cup of tea;
  * props   -- small procedural sprites on Canvas, BASE + optional grayscale TINT, the props.py convention.

Everything is deterministic (seeded by name), so re-running reproduces the PNGs byte for byte.
Baked by tools/gen_thimblewick.py.
"""

import math
import random

from PIL import Image

import ground
import nocthollow as noc  # noqa: F401
import water
from nocthollow import Canvas, lit, mix

# ------------------------------------------------------------------ palettes (0..1)
LEAF = ((0.14, 0.34, 0.14), (0.28, 0.56, 0.20), (0.52, 0.78, 0.32))
LEAF_DEEP = ((0.09, 0.26, 0.14), (0.18, 0.42, 0.20), (0.36, 0.62, 0.30))
STEM = ((0.20, 0.40, 0.16), (0.34, 0.58, 0.24), (0.56, 0.78, 0.38))
WHITE = ((0.74, 0.74, 0.80), (0.93, 0.93, 0.92), (1.0, 1.0, 0.98))
YELLOW = ((0.76, 0.52, 0.06), (0.97, 0.78, 0.14), (1.0, 0.93, 0.50))
GOLD = ((0.62, 0.40, 0.08), (0.86, 0.64, 0.14), (1.0, 0.86, 0.40))
POPPY = ((0.58, 0.06, 0.10), (0.86, 0.15, 0.14), (0.99, 0.44, 0.33))
PINK = ((0.72, 0.30, 0.50), (0.94, 0.52, 0.70), (1.0, 0.80, 0.88))
FOXGLOVE = ((0.46, 0.18, 0.46), (0.72, 0.34, 0.68), (0.94, 0.62, 0.88))
BLUEBELL = ((0.24, 0.28, 0.60), (0.42, 0.48, 0.86), (0.72, 0.76, 1.0))
FLUFF = ((0.70, 0.76, 0.82), (0.90, 0.93, 0.96), (1.0, 1.0, 1.0))
SOIL = ((0.20, 0.12, 0.08), (0.34, 0.22, 0.14), (0.52, 0.36, 0.24))
WASH = ((0.66, 0.64, 0.58), (0.88, 0.86, 0.80), (1.0, 0.98, 0.94))   # whitewashed boards
GRAIN = (0.50, 0.46, 0.40)
ROCK = ((0.30, 0.28, 0.28), (0.52, 0.50, 0.48), (0.76, 0.74, 0.70))
CLAY = ((0.52, 0.22, 0.12), (0.78, 0.38, 0.20), (0.94, 0.60, 0.40))
COPPER = ((0.34, 0.40, 0.30), (0.56, 0.62, 0.44), (0.80, 0.84, 0.64))
HOSE = ((0.08, 0.30, 0.18), (0.14, 0.50, 0.28), (0.34, 0.74, 0.46))
BRASS = ((0.50, 0.34, 0.08), (0.80, 0.60, 0.18), (1.0, 0.88, 0.50))
CHINA = ((0.74, 0.78, 0.86), (0.93, 0.95, 0.98), (1.0, 1.0, 1.0))
SHELL = ((0.58, 0.40, 0.22), (0.84, 0.66, 0.40), (0.98, 0.88, 0.66))
PLASTIC = ((0.20, 0.40, 0.70), (0.34, 0.60, 0.90), (0.66, 0.84, 1.0))
PEARL = ((0.70, 0.60, 0.58), (0.92, 0.86, 0.82), (1.0, 0.98, 0.94))
THREAD = ((0.56, 0.06, 0.10), (0.82, 0.14, 0.18), (0.98, 0.42, 0.38))
PEG = ((0.52, 0.38, 0.22), (0.76, 0.58, 0.36), (0.92, 0.80, 0.58))
CAP = ((0.54, 0.10, 0.10), (0.82, 0.20, 0.18), (0.98, 0.52, 0.44))
PAPER = ((0.70, 0.66, 0.52), (0.92, 0.89, 0.76), (1.0, 0.99, 0.92))
SILVER = ((0.46, 0.50, 0.58), (0.74, 0.78, 0.84), (0.98, 1.0, 1.0))


def _rgb8(c):
    return (round(c[0] * 255), round(c[1] * 255), round(c[2] * 255))


# ======================================================================= painting helpers
def _stalk(c, x0, gy, top, lean=0.0, half=2.4, ramp=STEM):
    """A vertical stalk from the ground row `gy` up to `top`, leaning a little and lit from the left.
    Returns the x of the stalk at its top."""
    cx_top = x0
    for y in range(top, gy + 1):
        t = (gy - y) / max(1, gy - top)
        cx = x0 + lean * math.sin(t * 1.6)
        hw = half * (1.0 - 0.18 * t) + (0.8 if y > gy - 4 else 0.0)
        for x in range(int(round(cx - hw)), int(round(cx + hw)) + 1):
            dx = x - cx
            c.put(x, y, ramp[2] if dx < -hw * 0.35 else (ramp[0] if dx > hw * 0.45 else ramp[1]))
        if y == top:
            cx_top = cx
    return cx_top


def _blade_leaf(c, x, y, length, direction, width, ramp=LEAF, droop=0.25):
    """A pointed leaf blade from (x, y) sweeping out and up/down: a lens polygon, lit from above."""
    n = 8
    top, bot = [], []
    for i in range(n + 1):
        t = i / n
        px = x + direction * length * t
        py = y - length * 0.55 * math.sin(t * math.pi * 0.8) + length * droop * t * t
        w = width * math.sin(t * math.pi) ** 0.8
        top.append((px, py - w * 0.5))
        bot.append((px, py + w * 0.5))
    pts = top + bot[::-1]
    c.poly(pts, lambda xx, yy, dx, dy: c.put(xx, yy, ramp[2] if dy < -width * 0.12 else (ramp[1] if dy < width * 0.18 else ramp[0])))
    for i in range(1, n):
        px, py = (top[i][0] + bot[i][0]) / 2, (top[i][1] + bot[i][1]) / 2
        c.put(px, py, mix(ramp[2], (1, 1, 1), 0.25))


def _petal(c, hx, hy, ang, length, width, sq, ramp, inner=0.0):
    """One petal radiating from the head's centre at angle `ang` (the head is seen at a slant: y squashed)."""
    ca, sa = math.cos(ang), math.sin(ang)
    px, py = -sa, ca
    pts = []
    n = 6
    for i in range(n + 1):
        t = i / n
        w = width * 0.5 * math.sin(math.pi * (0.1 + 0.9 * t) ** 0.9)
        d = inner + (length - inner) * t
        pts.append((hx + ca * d + px * w, hy + (sa * d + py * w) * sq))
    for i in range(n, -1, -1):
        t = i / n
        w = width * 0.5 * math.sin(math.pi * (0.1 + 0.9 * t) ** 0.9)
        d = inner + (length - inner) * t
        pts.append((hx + ca * d - px * w, hy + (sa * d - py * w) * sq))
    c.poly(pts, lambda xx, yy, dx, dy: c.put(xx, yy, lit(ramp, dx * 0.6, dy * 1.6, length * 0.5)))


def _flower_head(c, hx, hy, n, length, width, ramp, centre, centre_r, sq=0.62, inner=0.0, dots=0, seed=1):
    """A round-petalled flower seen from a slant: back petals first, then the front, then the eye."""
    angs = [i / n * math.tau + 0.3 for i in range(n)]
    angs.sort(key=lambda a: math.sin(a))
    for a in angs:
        _petal(c, hx, hy, a, length, width, sq, ramp, inner)
    c.ellipse(hx, hy + 1, centre_r, centre_r * sq + 0.4, lambda x, y, dx, dy: c.put(x, y, lit(centre, dx, dy * 1.5, centre_r)))
    rng = random.Random(seed)
    for _ in range(dots):
        a = rng.random() * math.tau
        r = rng.random() * centre_r * 0.8
        c.put(hx + math.cos(a) * r, hy + 1 + math.sin(a) * r * sq, centre[0])


def _bell_spire(c, sx, base_y, top_y, side, ramp, n, size, inside):
    """Foxglove/bluebell: bells hung down one side of the stalk, big at the bottom, small at the top."""
    for i in range(n):
        t = i / max(1, n - 1)
        y = base_y + (top_y - base_y) * t
        s = size * (1.0 - 0.55 * t)
        bx = sx + side * (s * 0.55)
        pts = [(bx - s * 0.30, y - s * 0.5), (bx + s * 0.30, y - s * 0.5), (bx + s * 0.55, y + s * 0.55), (bx - s * 0.55, y + s * 0.55)]
        c.poly(pts, lambda xx, yy, dx, dy: c.put(xx, yy, lit(ramp, dx, dy * 1.2, s * 0.6)))
        c.ellipse(bx, y + s * 0.55, s * 0.55, s * 0.22, lambda xx, yy, dx, dy: c.put(xx, yy, inside[1] if dy > -s * 0.05 else inside[0]))
        c.put(bx - s * 0.1, y + s * 0.5, inside[2])
    c.ellipse(sx + side * 1.0, top_y - 2, 2.2, 2.6, lambda xx, yy, dx, dy: c.put(xx, yy, lit(ramp, dx, dy, 3)))


# ======================================================================= FLOWER STALKS ("trees")
FLOWER_W, FLOWER_H = 76, 150


def flower_stalk(name):
    """(trunk, canopy) for one tall garden flower: the stalk (with its leaves) is the trunk layer, the head
    the canopy layer. Both share one canvas so they register; the foot is flush with the bottom edge."""
    seed = sum(ord(ch) for ch in name)
    rng = random.Random("tw-flower-" + name)
    w, h = FLOWER_W, FLOWER_H
    gy = h - 2
    cx = w // 2
    tall = {"daisy": 112, "poppy": 96, "cosmos": 120, "dandelion": 104, "foxglove": 126, "bluebell": 100}[name]
    top = gy - tall
    lean = rng.choice([-3.0, -1.5, 1.5, 3.0])
    trunk, canopy = Canvas(w, h), Canvas(w, h)
    half = 2.6 if name != "dandelion" else 2.0
    top_x = _stalk(trunk, cx, gy, top, lean=lean, half=half)
    _blade_leaf(trunk, cx, gy - 2, 24, -1, 9, LEAF_DEEP, droop=0.5)
    _blade_leaf(trunk, cx, gy - 2, 22, 1, 8, LEAF, droop=0.5)
    _blade_leaf(trunk, cx - 0.5, gy - tall * 0.42, 22, 1, 8, LEAF, droop=0.2)
    _blade_leaf(trunk, cx + 0.5, gy - tall * 0.62, 18, -1, 7, LEAF_DEEP, droop=0.2)
    trunk.outline()

    hx, hy = top_x, top
    if name == "daisy":
        _flower_head(canopy, hx, hy, 15, 25, 7.5, WHITE, YELLOW, 8.5, dots=10, seed=seed)
    elif name == "poppy":
        _flower_head(canopy, hx, hy, 5, 21, 17, POPPY, ((0.10, 0.06, 0.10), (0.20, 0.12, 0.18), (0.36, 0.26, 0.30)), 6.5, sq=0.7, dots=14, seed=seed)
        for a in range(10):
            ang = a / 10 * math.tau
            canopy.put(hx + math.cos(ang) * 4.8, hy + 1 + math.sin(ang) * 3.4, (0.96, 0.84, 0.30))
    elif name == "cosmos":
        _flower_head(canopy, hx, hy, 8, 24, 13, PINK, ((0.86, 0.50, 0.08), (1.0, 0.76, 0.16), (1.0, 0.92, 0.5)), 6.0, dots=6, seed=seed)
    elif name == "dandelion":
        canopy.ellipse(hx, hy, 21, 19, lambda x, y, dx, dy: canopy.put(x, y, lit(FLUFF, dx, dy, 20)))
        canopy.ellipse(hx, hy, 5, 4.4, lambda x, y, dx, dy: canopy.put(x, y, (0.62, 0.66, 0.54)))
        for i in range(34):
            a = i / 34 * math.tau + 0.2
            for r in range(6, 21):
                if (r + i) % 3 == 0:
                    canopy.put(hx + math.cos(a) * r, hy + math.sin(a) * r * 0.92, (0.76, 0.80, 0.86))
            canopy.put(hx + math.cos(a) * 20.5, hy + math.sin(a) * 19, (1, 1, 1))
        for dx_, dy_ in [(28, -6), (32, -14), (-27, -12), (-30, -2)]:
            canopy.put(hx + dx_, hy + dy_, (1, 1, 1))
            canopy.put(hx + dx_, hy + dy_ + 1, (0.76, 0.8, 0.86))
    elif name == "foxglove":
        _bell_spire(canopy, hx, top + 34, top - 6, 1, FOXGLOVE, 7, 12, ((0.40, 0.14, 0.36), (0.94, 0.80, 0.90), (0.6, 0.2, 0.4)))
        canopy.ellipse(hx, top - 8, 2.4, 3.2, lambda x, y, dx, dy: canopy.put(x, y, lit(LEAF, dx, dy, 3)))
    elif name == "bluebell":
        _bell_spire(canopy, hx, top + 24, top - 2, -1, BLUEBELL, 6, 11, ((0.18, 0.20, 0.50), (0.84, 0.88, 1.0), (0.6, 0.6, 0.9)))
        canopy.ellipse(hx - 1, top - 4, 2.2, 2.8, lambda x, y, dx, dy: canopy.put(x, y, lit(BLUEBELL, dx, dy, 3)))
    canopy.outline()
    return trunk.img, canopy.img


# ------------------------------------------------------------------ the great sunflowers (landmarks)
GREAT_W, GREAT_H = 132, 250


def sunflower(variant):
    """A great sunflower: a thick stalk, huge heart leaves and a face as wide as a house. (trunk, canopy)."""
    w, h = GREAT_W, GREAT_H
    gy = h - 2
    cx = w // 2
    petal_ramp = {"gold": GOLD, "ember": ((0.58, 0.20, 0.06), (0.86, 0.38, 0.10), (1.0, 0.64, 0.30))}[variant]
    seed_ramp = {"gold": ((0.22, 0.12, 0.06), (0.38, 0.22, 0.10), (0.56, 0.38, 0.18)),
                 "ember": ((0.18, 0.06, 0.06), (0.32, 0.12, 0.08), (0.50, 0.24, 0.14))}[variant]
    trunk, canopy = Canvas(w, h), Canvas(w, h)
    top = 78
    top_x = _stalk(trunk, cx, gy, top, lean=4.0, half=5.4, ramp=STEM)
    for dy_, dirn, ln, wd, ramp in [(-12, -1, 44, 20, LEAF_DEEP), (-30, 1, 46, 21, LEAF), (-72, -1, 40, 18, LEAF),
                                    (-104, 1, 36, 17, LEAF_DEEP), (-140, -1, 30, 14, LEAF)]:
        _blade_leaf(trunk, cx, gy + dy_, ln, dirn, wd, ramp, droop=0.35)
    trunk.outline()
    hx, hy = top_x, 60
    n = 24
    for a in sorted([i / n * math.tau + 0.1 for i in range(n)], key=lambda a: math.sin(a)):
        _petal(canopy, hx, hy, a, 56, 15, 0.7, petal_ramp)
    for a in sorted([i / n * math.tau + 0.3 for i in range(n)], key=lambda a: math.sin(a)):
        _petal(canopy, hx, hy, a, 44, 13, 0.7, petal_ramp, inner=16)
    canopy.ellipse(hx, hy + 2, 27, 20, lambda x, y, dx, dy: canopy.put(x, y, lit(seed_ramp, dx, dy * 1.4, 26)))
    for i in range(1, 150):
        r = math.sqrt(i / 150.0) * 25
        a = i * 2.39996
        canopy.put(hx + math.cos(a) * r, hy + 2 + math.sin(a) * r * 0.72, seed_ramp[2] if i % 3 else mix(seed_ramp[2], (1.0, 0.8, 0.3), 0.5))
    canopy.outline()
    return trunk.img, canopy.img


# ------------------------------------------------------------------ clover umbrellas
CLOVER_W, CLOVER_H = 92, 96


def clover(variant):
    """A clover leaf big enough to shelter under: broad leaflets with a pale chevron and a dew drop, on a thin
    stalk. `variant` 0 = three leaflets, 1 = four (a lucky one). (trunk, canopy)."""
    rng = random.Random("tw-clover-%d" % variant)
    w, h = CLOVER_W, CLOVER_H
    gy = h - 2
    cx = w // 2
    trunk, canopy = Canvas(w, h), Canvas(w, h)
    cy = 36
    _stalk(trunk, cx, gy, cy, lean=rng.choice([-2.0, 2.0]), half=1.6, ramp=STEM)
    _blade_leaf(trunk, cx, gy - 2, 18, -1, 7, LEAF_DEEP, droop=0.5)
    _blade_leaf(trunk, cx, gy - 2, 16, 1, 6, LEAF, droop=0.5)
    trunk.outline()
    leaflets = [(-21, 6, 1.0), (21, 6, 1.0), (0, -9, 1.0)] if variant == 0 else [(-21, 2, 1.0), (21, 2, 1.0), (-8, -12, 0.9), (9, 11, 0.9)]
    order = sorted(leaflets, key=lambda l: l[1])
    for lx, ly, k in order:
        ex, ey = cx + lx, cy + ly
        rx, ry = 25 * k, 15 * k
        canopy.ellipse(ex, ey, rx, ry, lambda x, y, dx, dy, ry=ry: canopy.put(x, y, lit(LEAF, dx * 0.7, dy * 1.5, ry * 1.2)))
        for t in range(-10, 11):
            canopy.put(ex + t, ey - 1 + abs(t) * 0.42, mix(LEAF[2], (0.9, 1.0, 0.8), 0.7))
            canopy.put(ex + t, ey + abs(t) * 0.42, mix(LEAF[2], (0.9, 1.0, 0.8), 0.45))
    fx, fy, _ = order[-1]
    dx0, dy0 = cx + fx + 6, cy + fy + 3
    canopy.ellipse(dx0, dy0, 4.2, 3.4, lambda x, y, dx, dy: canopy.put(x, y, (0.64, 0.84, 0.96) if dy > -0.5 else (0.86, 0.96, 1.0)))
    canopy.put(dx0 - 1, dy0 - 1, (1, 1, 1))
    canopy.put(dx0 + 1, dy0 + 2, (0.34, 0.52, 0.72))
    canopy.outline()
    return trunk.img, canopy.img


# ------------------------------------------------------------------ whole-sprite scenery: grass clumps, pickets
GRASS_W, GRASS_H = 60, 96


def grass_clump(variant):
    """A tall tuft of grass: a fan of curved blades, lit on their left edges. One whole sprite (it sways as one)."""
    rng = random.Random("tw-grass-%d" % variant)
    w, h = GRASS_W, GRASS_H
    gy = h - 2
    c = Canvas(w, h)
    blades = 8 + variant % 3
    ramps = [LEAF, LEAF_DEEP]
    order = sorted(range(blades), key=lambda i: abs(i - blades / 2), reverse=True)
    for i in order:
        t = (i + 0.5) / blades - 0.5
        length = rng.randint(54, 88) - int(abs(t) * 34)
        bend = t * rng.uniform(20, 34) + rng.uniform(-4, 4)
        x0 = w / 2 + t * 14
        ramp = ramps[i % 2]
        pts_l, pts_r = [], []
        for s in range(length + 1):
            u = s / length
            x = x0 + bend * u * u + math.sin(u * 3.0 + i) * 1.2
            y = gy - length * u
            wd = 2.6 * (1.0 - u) ** 0.8 + 0.4
            pts_l.append((x - wd, y))
            pts_r.append((x + wd, y))
        c.poly(pts_l + pts_r[::-1], lambda xx, yy, dx, dy, ramp=ramp: c.put(xx, yy, ramp[2] if dx < -0.4 else (ramp[0] if dx > 1.2 else ramp[1])))
    c.outline()
    return c.img


PICKET_W, PICKET_H = 12, 72
PICKET_STYLES = ["plain", "plain", "chip", "knot", "lean", "moss"]


def picket(style, seed=0):
    """One whitewashed fence picket, 12 px wide (the fence's spacing), with the two rails running edge to
    edge so neighbours join. A missing picket is a gap a rabbit can slip through. One whole sprite."""
    rng = random.Random("tw-picket-%s-%d" % (style, seed))
    w, h = PICKET_W, PICKET_H
    gy = h - 2
    c = Canvas(w, h)
    tip = 7
    for y in range(tip - 5, gy + 1):
        half = (y - (tip - 5)) / 5.0 * 4.6 + 0.4 if y < tip else 4.6   # the pointed top
        for x in range(w):
            dx = x - (w - 1) / 2.0
            if abs(dx) <= half + 0.4:
                c.put(x, y, WASH[2] if dx < -2.2 else (WASH[0] if dx > 2.6 else WASH[1]))
    for ry in (gy - 52, gy - 20):           # the rails
        for y in range(ry, ry + 5):
            for x in range(w):
                c.put(x, y, WASH[2] if y == ry else (WASH[0] if y == ry + 4 else WASH[1]))
        c.put(5, ry + 2, GRAIN)             # a nail
        c.put(6, ry + 2, (0.34, 0.32, 0.30))
    for _ in range(5):                       # weathered grain
        x = rng.randint(2, 8)
        y0 = rng.randint(tip + 3, gy - 8)
        for y in range(y0, y0 + rng.randint(3, 9)):
            c.put(x, y, mix(WASH[1], GRAIN, 0.55))
    if style == "chip":
        for x, y in [(3, tip - 4), (4, tip - 4), (3, tip - 3)]:
            c.clear(x, y)
    elif style == "knot":
        c.ellipse(5.5, gy - 36, 2.2, 3.0, lambda x, y, dx, dy: c.put(x, y, SOIL[1] if abs(dx) + abs(dy) < 2.6 else SOIL[2]))
    elif style == "moss":
        for x in range(1, 10):
            for y in range(gy - 8, gy + 1):
                if rng.random() < 0.55:
                    c.put(x, y, LEAF_DEEP[1] if rng.random() < 0.7 else LEAF[1])
    for x in range(1, 11):                   # the foot
        c.put(x, gy, mix(WASH[0], SOIL[1], 0.5))
    c.outline()
    img = c.img
    if style == "lean":
        # a tired picket leans a pixel or two: shear the top rows over
        out = Image.new("RGBA", img.size, (0, 0, 0, 0))
        px_in, px_out = img.load(), out.load()
        for y in range(h):
            shift = int(round((h - y) / h * 1.6))
            for x in range(w):
                nx = x + shift
                if 0 <= nx < w and px_in[x, y][3] > 0:
                    px_out[nx, y] = px_in[x, y]
        img = out
    return img


# ------------------------------------------------------------------ understory (single-layer sprites)
def leaf_rosette(variant):
    """A low rosette of broad leaves (a lettuce, a dock): the garden's bushes."""
    rng = random.Random("tw-rosette-%d" % variant)
    w, h = 44, 24
    gy = h - 2
    c = Canvas(w, h)
    ramp = LEAF if variant == 0 else LEAF_DEEP
    for i, (ang, ln) in enumerate([(-1, 20), (1, 20), (-1, 15), (1, 16), (-1, 9), (1, 10)]):
        _blade_leaf(c, w / 2 + rng.uniform(-1, 1), gy - 1 - (i % 3), ln, ang, 8, ramp if i % 2 else LEAF, droop=0.3)
    c.outline()
    return c.img


def toadstool():
    """A small spotted toadstool for the understory."""
    w, h = 22, 22
    gy = h - 2
    c = Canvas(w, h)
    for y in range(11, gy + 1):
        for x in range(8, 14):
            dx = x - 10.5
            c.put(x, y, WASH[2] if dx < -1.5 else (WASH[0] if dx > 1.5 else WASH[1]))
    c.ellipse(11, 10, 10, 7, lambda x, y, dx, dy: c.put(x, y, lit(CAP, dx, dy * 1.4, 9)), top_only=True)
    for sx, sy in [(7, 6), (12, 4), (16, 8), (10, 8)]:
        c.put(sx, sy, (1, 0.96, 0.9))
        c.put(sx + 1, sy, (1, 0.96, 0.9))
    c.outline()
    return c.img


UNDERSTORY = {"bush_a": lambda: leaf_rosette(0), "bush_b": lambda: leaf_rosette(1), "stump": toadstool}

FLOWERS = ["daisy", "poppy", "cosmos", "dandelion", "foxglove", "bluebell"]
GREAT = ["gold", "ember"]
CLOVERS = [0, 0, 1]
GRASSES = [0, 1, 2]
PICKETS = [(s, i) for i, s in enumerate(PICKET_STYLES)]

# ======================================================================= THE GROUND
TILE = ground.TILE
KINDS = ground.KINDS


def _terrain(kind):
    """(shade_grid, accent_grid) for one mood of the garden floor, sized for a beetle: grass is a thicket of
    long blades, the lush kind is clover, the meadow kind is blades with tiny flowers, dirt is loam with
    clods, sand is a gravel path."""
    rng = random.Random("thimblewick-ground-" + kind)
    g = [[1] * TILE for _ in range(TILE)]
    acc = [[0] * TILE for _ in range(TILE)]
    blade = [(0, 0, 0), (0, -1, 2), (0, -2, 2), (0, -3, 3), (1, -4, 3), (1, -5, 3), (2, -6, 3)]
    blade_l = [(0, 0, 0), (0, -1, 2), (0, -2, 2), (0, -3, 3), (-1, -4, 3), (-1, -5, 3)]
    clover_leaf = [(0, -1, 2), (-1, 0, 3), (1, 0, 2), (0, 0, 3), (-1, 1, 2), (1, 1, 0), (0, 1, 0), (0, -2, 3)]
    shadow = [(0, 0, 0), (1, 0, 0), (2, 0, 0)]
    if kind in ("grass", "meadow"):
        for _ in range(110):
            ground._stamp(g, shadow, rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(120):
            ground._stamp(g, rng.choice([blade, blade_l]), rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(180):
            ground._stamp(g, ground.BLADE, rng.randrange(TILE), rng.randrange(TILE))
        if kind == "meadow":
            for _ in range(46):
                glyph = ground.FLOWER_PLUS if rng.random() < 0.5 else ground.FLOWER_DOT
                ground._stamp(g, glyph, rng.randrange(TILE), rng.randrange(TILE), acc)
            for y in range(TILE):
                for x in range(TILE):
                    if acc[y][x] and g[y][x] == 0:
                        acc[y][x] = 0
    elif kind == "lush":
        for _ in range(95):
            ground._stamp(g, clover_leaf, rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(200):
            ground._stamp(g, ground.TUFT, rng.randrange(TILE), rng.randrange(TILE))
    elif kind == "dirt":
        clod = [(0, 0, 2), (1, 0, 3), (0, 1, 0), (1, 1, 0), (2, 1, 0), (-1, 1, 0)]
        for _ in range(70):
            ground._stamp(g, clod, rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(240):
            ground._stamp(g, ground.PIT, rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(160):
            ground._stamp(g, ground.SPECK_LIGHT, rng.randrange(TILE), rng.randrange(TILE))
    else:  # sand: a gravel path
        g = [[2] * TILE for _ in range(TILE)]
        pebble = [(0, 0, 3), (1, 0, 3), (0, 1, 1), (1, 1, 1)]
        for _ in range(110):
            ground._stamp(g, pebble, rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(260):
            ground._stamp(g, ground.SPECK_DARK, rng.randrange(TILE), rng.randrange(TILE))
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


def _r(ramp):
    return tuple(_rgb8(c) for c in ramp)


G_BLADE = _r(LEAF)
G_DEEP = _r(LEAF_DEEP)
G_CLOVER = _r(((0.12, 0.40, 0.18), (0.24, 0.60, 0.26), (0.52, 0.84, 0.42)))
G_PETAL_W = _r(WASH)
G_PETAL_P = _r(PINK)
G_PETAL_Y = _r(YELLOW)
G_SEED = _r(((0.30, 0.20, 0.10), (0.52, 0.38, 0.20), (0.76, 0.62, 0.40)))
G_STONE = _r(ROCK)
G_TWIG = _r(((0.30, 0.20, 0.12), (0.46, 0.32, 0.20), (0.66, 0.50, 0.34)))
G_ACORN = _r(((0.40, 0.24, 0.10), (0.62, 0.42, 0.20), (0.84, 0.66, 0.38)))
G_TEA = _r(((0.24, 0.30, 0.10), (0.42, 0.50, 0.18), (0.66, 0.74, 0.34)))
G_CRUMB = _r(SOIL)

# Fine litter: ASCII maps in ground.py's format ('1' dark, '2' base, '3' light, '.' clear): (ramp, outlined, rows)
DETAILS = {
    "grassblade_a": (G_BLADE, False, [
        "..3...",
        "..32..",
        ".32...",
        ".32...",
        ".22.3.",
        "32.32.",
        "21.21.",
        "21.2..",
    ]),
    "grassblade_b": (G_DEEP, False, [
        "...3.",
        "..32.",
        ".32..",
        "32.3.",
        "2.32.",
        "21.2.",
        "21.2.",
    ]),
    "cloverleaf": (G_CLOVER, False, [
        ".33.33.",
        "3223223",
        "3222223",
        ".32223.",
        "..121..",
        "...1...",
    ]),
    "petal_white": (G_PETAL_W, False, [
        ".33.",
        "3222",
        ".221",
        "..1.",
    ]),
    "petal_pink": (G_PETAL_P, False, [
        ".33.",
        "3222",
        ".221",
        "..1.",
    ]),
    "seed": (G_SEED, False, [
        ".33.",
        "3221",
        ".21.",
    ]),
    "pebble_a": (G_STONE, True, [
        ".333.",
        "32221",
        "22211",
        ".111.",
    ]),
    "crumb": (G_CRUMB, False, [
        "33..",
        "221.",
        ".11.",
    ]),
    "twig": (G_TWIG, False, [
        "3.3.....",
        ".23..3..",
        "..2232..",
        ".....21.",
    ]),
    "acorncap": (G_ACORN, True, [
        ".3333.",
        "322221",
        "212121",
        ".1111.",
    ]),
    "tealeaf": (G_TEA, False, [
        "..33..",
        ".3223.",
        "322221",
        ".2221.",
        "..11..",
    ]),
    "buttercup": (G_PETAL_Y, False, [
        ".3.3.",
        "32223",
        ".222.",
        "..1..",
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


# ------------------------------------------------------------------ water: a cup of tea
water.RAMPS["tea"] = ((0.34, 0.18, 0.08), (0.52, 0.32, 0.14), (0.86, 0.62, 0.34))


def tea_tile():
    return water.make_water_tile("tea")


# ======================================================================= PROPS
def _p_lost_button(c):
    """The dropped button: a big four-holed sewing button on the ground, cream with a raised rim, a cross of
    red thread still stitched through it."""
    cx, cy = c.w / 2, c.h / 2 + 1
    rx, ry = c.w / 2 - 2, c.h / 2 - 3
    c.ellipse(cx, cy + 2, rx, ry, lambda x, y, dx, dy: c.put(x, y, PEARL[0]))
    c.ellipse(cx, cy, rx, ry, lambda x, y, dx, dy: c.put(x, y, lit(PEARL, dx * 0.7, dy * 1.4, rx)))
    c.ellipse(cx, cy, rx * 0.74, ry * 0.72, lambda x, y, dx, dy: c.put(x, y, PEARL[0] if (dx < -rx * 0.5 and dy < 0) else (PEARL[1] if dy < ry * 0.3 else PEARL[2])))
    holes = [(-4.5, -2.0), (4.5, -2.0), (-4.5, 2.0), (4.5, 2.0)]
    for (a, b), (e, f) in [((holes[0], holes[3])), ((holes[1], holes[2]))]:
        c.line((cx + a, cy + b), (cx + e, cy + f), lambda x, y, dx, dy: c.put(x, y, THREAD[1]))
    for hx, hy in holes:
        c.ellipse(cx + hx, cy + hy, 1.7, 1.3, lambda x, y, dx, dy: c.put(x, y, (0.16, 0.12, 0.12)))
    for x, y in [(cx - 4.5, cy - 2.6), (cx + 4.5, cy - 2.6)]:
        c.put(x, y, THREAD[2])


def _p_coiled_hose(c):
    """A garden hose coiled on the grass, brass nozzle poking out."""
    cx, cy = c.w / 2, c.h / 2
    for k, (rx, ry) in enumerate([(31, 17), (24, 12.5), (17, 8.4)]):
        cyk = cy + 3 - k * 3
        c.ellipse(cx, cyk + 2.4, rx, ry, lambda x, y, dx, dy: c.put(x, y, HOSE[0]))
        c.ellipse(cx, cyk, rx, ry, lambda x, y, dx, dy, ry=ry: c.put(x, y, lit(HOSE, dx * 0.5, dy * 1.2, ry)))
        c.ellipse(cx, cyk, rx - 4.2, ry - 2.6, lambda x, y, dx, dy: c.put(x, y, HOSE[0] if dy < 0 else HOSE[1]))
    c.ellipse(cx, cy - 4, 9, 4, lambda x, y, dx, dy: c.put(x, y, (0.18, 0.40, 0.24)))
    c.poly([(cx + 24, cy + 9), (cx + 36, cy + 11), (cx + 37, cy + 15), (cx + 24, cy + 14)], lambda x, y, dx, dy: c.put(x, y, lit(BRASS, dx, dy, 6)))
    c.ellipse(cx + 37, cy + 13, 1.8, 2.8, lambda x, y, dx, dy: c.put(x, y, BRASS[0]))


def _p_watering_can(c):
    """A copper watering can, verdigris at the seams: body, spout with a rose, a handle."""
    gy = c.h - 2
    c.ellipse(20, gy - 12, 15, 12, lambda x, y, dx, dy: c.put(x, y, lit(COPPER, dx * 0.9, dy * 0.7, 14)))
    c.ellipse(20, gy - 22, 14, 4.2, lambda x, y, dx, dy: c.put(x, y, mix(COPPER[2], COPPER[1], 0.5)))
    c.ellipse(20, gy - 22, 10, 2.6, lambda x, y, dx, dy: c.put(x, y, (0.10, 0.12, 0.12)))
    c.poly([(33, gy - 10), (47, gy - 24), (49, gy - 22), (35, gy - 6)], lambda x, y, dx, dy: c.put(x, y, lit(COPPER, dx, dy, 8)))
    c.ellipse(49, gy - 24, 4.2, 3.2, lambda x, y, dx, dy: c.put(x, y, lit(COPPER, dx, dy, 4)))
    for dx_, dy_ in [(47, -25), (49, -26), (51, -24), (50, -22)]:
        c.put(dx_, gy + dy_, (0.14, 0.16, 0.16))
    c.line((7, gy - 20), (3, gy - 12), lambda x, y, dx, dy: c.put(x, y, COPPER[1]), width=3.0)
    c.line((3, gy - 12), (9, gy - 4), lambda x, y, dx, dy: c.put(x, y, COPPER[1]), width=3.0)


def _p_tipped_pot(c):
    """A terracotta flowerpot tipped on its side: a dark cave mouth you could (nearly) walk into."""
    cx, cy = c.w / 2, c.h / 2 + 2
    c.poly([(8, cy - 12), (cx + 6, cy - 14), (cx + 6, cy + 13), (8, cy + 9)], lambda x, y, dx, dy: c.put(x, y, lit(CLAY, dx * 0.4, dy * 1.3, 12)))
    c.ellipse(cx + 6, cy, 5.5, 14, lambda x, y, dx, dy: c.put(x, y, lit(CLAY, dx, dy * 0.4, 12)))
    c.ellipse(cx + 7, cy, 3.6, 11, lambda x, y, dx, dy: c.put(x, y, (0.10, 0.06, 0.05) if dx < 1.5 else SOIL[0]))
    c.ellipse(cx + 8, cy + 6, 3, 4, lambda x, y, dx, dy: c.put(x, y, SOIL[1]))
    c.ellipse(cx + 16, cy + 11, 6, 2.4, lambda x, y, dx, dy: c.put(x, y, SOIL[2]))
    c.ellipse(8, cy - 1, 2.4, 10, lambda x, y, dx, dy: c.put(x, y, CLAY[0]))


def _p_peg(c):
    """A wooden clothes-peg that fell off the line."""
    cy = c.h / 2
    c.line((3, cy - 3), (c.w - 4, cy - 3), lambda x, y, dx, dy: c.put(x, y, PEG[2] if y < cy - 3 else PEG[1]), width=4.0)
    c.line((3, cy + 2), (c.w - 4, cy + 2), lambda x, y, dx, dy: c.put(x, y, PEG[0] if y > cy + 2 else PEG[1]), width=4.0)
    c.ellipse(c.w - 12, cy - 0.5, 3.6, 4.4, lambda x, y, dx, dy: c.put(x, y, SILVER[1] if dy < 1 else SILVER[0]))
    c.put(c.w - 12, cy - 1, SILVER[2])


def _p_snail_shell(c):
    """An empty snail shell, big as a boulder: a banded spiral."""
    cx, cy = c.w / 2, c.h / 2 + 1
    r = min(c.w, c.h) / 2 - 2
    c.ellipse(cx, cy + 1, r + 1, r * 0.9, lambda x, y, dx, dy: c.put(x, y, SHELL[0]))
    c.ellipse(cx, cy, r, r * 0.9, lambda x, y, dx, dy: c.put(x, y, lit(SHELL, dx, dy * 1.2, r)))
    for k, rr in enumerate([r * 0.78, r * 0.52, r * 0.28]):
        for i in range(60):
            a = i / 60 * math.tau
            c.put(cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.9, SHELL[0] if (i + k * 3) % 11 else SHELL[2])
    c.put(cx, cy, SHELL[0])
    c.ellipse(cx + r * 0.62, cy + r * 0.28, 4.4, 5.4, lambda x, y, dx, dy: c.put(x, y, (0.22, 0.12, 0.08)))


def _p_dewdrop(c):
    """A drop of dew as big as a beehive: a glass bead, bright at the upper left, a sky in it."""
    cx, cy = c.w / 2, c.h / 2 + 1
    rx, ry = c.w / 2 - 2, c.h / 2 - 2
    c.ellipse(cx, cy + 1, rx, ry, lambda x, y, dx, dy: c.put(x, y, (0.40, 0.58, 0.78)))
    c.ellipse(cx, cy, rx - 0.5, ry - 0.5, lambda x, y, dx, dy: c.put(x, y, mix((0.62, 0.82, 0.94), (0.30, 0.50, 0.30), max(0.0, dy / ry) * 0.7)))
    c.ellipse(cx - 3, cy - 4, 3, 2.2, lambda x, y, dx, dy: c.put(x, y, (1, 1, 1)))
    c.put(cx + 3, cy + 3, (0.94, 0.98, 1.0))


def _p_spool(c):
    """A wooden cotton reel on its end, a loose tail of red thread curling away from it."""
    gy = c.h - 2
    cx = c.w / 2 - 3
    for y in range(gy - 26, gy - 20):
        for x in range(int(cx - 9), int(cx + 10)):
            c.put(x, y, lit(PEG, x - cx, y - (gy - 23), 6))
    for y in range(gy - 8, gy - 2):
        for x in range(int(cx - 9), int(cx + 10)):
            c.put(x, y, lit(PEG, x - cx, y - (gy - 5), 6))
    for y in range(gy - 21, gy - 8):
        for x in range(int(cx - 7), int(cx + 8)):
            dx = x - cx
            c.put(x, y, THREAD[2] if dx < -3 else (THREAD[0] if dx > 3 else THREAD[1]))
            if (y + x) % 4 == 0:
                c.put(x, y, THREAD[0])
    for x, y in [(cx + 8, gy - 6), (cx + 11, gy - 4), (cx + 14, gy - 3), (cx + 17, gy - 4), (cx + 19, gy - 2)]:
        c.put(x, y, THREAD[1])
        c.put(x, y + 1, THREAD[0])


def _p_red_thread(c):
    """A tangle of red cotton snagged and trailing along the ground, as if dragged through the fence."""
    cy = c.h / 2
    for i in range(0, 60):
        t = i / 59
        x = 2 + t * (c.w - 6)
        y = cy + math.sin(t * 9.0) * 3.2 * (1.0 - 0.3 * t) + t * 1.5
        c.put(x, y, THREAD[1], solid=False)
        c.put(x, y + 1, THREAD[0], solid=False)
        if int(x) % 3 == 0:
            c.put(x, y - 1, THREAD[2], solid=False)
    c.ellipse(c.w - 7, cy - 2, 3.4, 2.6, lambda x, y, dx, dy: c.put(x, y, THREAD[1], solid=False))
    c.ellipse(c.w - 8, cy - 3, 1.4, 1.0, lambda x, y, dx, dy: c.put(x, y, THREAD[2], solid=False))


def _p_gap_worn(c):
    """The worn earth at the foot of a gap in the fence: a smooth dip in the dust."""
    cy = c.h / 2
    c.ellipse(c.w / 2, cy + 1, c.w / 2 - 1, c.h / 2 - 1, lambda x, y, dx, dy: c.put(x, y, mix(SOIL[2], SOIL[1], 0.5 + 0.5 * dy / max(1, c.h / 2)), solid=False))
    c.ellipse(c.w / 2 + 1, cy + 2, c.w / 2 - 5, c.h / 2 - 3, lambda x, y, dx, dy: c.put(x, y, SOIL[0], solid=False))
    for x in range(2, c.w - 2, 3):
        c.put(x, cy - c.h // 2 + 2, SOIL[2], solid=False)


def _p_bottle_cap(c):
    """A bottle-top lying in the grass: a red crown with a crimped edge, a bowl for the rain."""
    cx, cy = c.w / 2, c.h / 2 + 1
    rx, ry = c.w / 2 - 2, c.h / 2 - 2
    c.ellipse(cx, cy + 2, rx, ry, lambda x, y, dx, dy: c.put(x, y, CAP[0]))
    c.ellipse(cx, cy, rx, ry, lambda x, y, dx, dy: c.put(x, y, lit(CAP, dx * 0.7, dy * 1.4, rx)))
    for i in range(18):
        a = i / 18 * math.tau
        c.put(cx + math.cos(a) * rx, cy + math.sin(a) * ry, CAP[2] if i % 2 else CAP[0])
    c.ellipse(cx, cy, rx - 4, ry - 3, lambda x, y, dx, dy: c.put(x, y, mix(CAP[0], CAP[1], 0.4 + 0.4 * (-dy / ry))))
    c.ellipse(cx - 2, cy - 1, 3, 1.6, lambda x, y, dx, dy: c.put(x, y, (0.6, 0.74, 0.86)))


def _p_seed_packet(c):
    """A seed packet that blew over the wall and stands against a stone: a tiny painted flower on it."""
    gy = c.h - 2
    c.poly([(4, gy), (6, 4), (c.w - 6, 3), (c.w - 4, gy - 1)], lambda x, y, dx, dy: c.put(x, y, PAPER[2] if dx < -3 else (PAPER[0] if dx > 4 else PAPER[1])))
    for x in range(8, c.w - 9):
        c.put(x, 9, (0.84, 0.30, 0.20))
        c.put(x, 10, (0.84, 0.30, 0.20))
    c.ellipse(c.w / 2, 19, 5, 4, lambda x, y, dx, dy: c.put(x, y, YELLOW[1]))
    for a in range(6):
        ang = a / 6 * math.tau
        c.ellipse(c.w / 2 + math.cos(ang) * 6, 19 + math.sin(ang) * 5, 2.2, 2.2, lambda x, y, dx, dy: c.put(x, y, POPPY[1]))
    c.ellipse(c.w / 2, 19, 2.4, 2, lambda x, y, dx, dy: c.put(x, y, YELLOW[2]))
    for y in range(24, gy - 2):
        c.put(c.w / 2, y, LEAF[1])
    c.put(c.w / 2 + 1, 26, LEAF[2])
    c.put(c.w / 2 - 1, 29, LEAF[2])


def _p_flagstone(c):
    """A flagstone from the garden path, big as a dance floor: pale, cracked, a moss edge. Walk-over."""
    cx, cy = c.w / 2, c.h / 2 + 1
    rx, ry = c.w / 2 - 1, c.h / 2 - 2
    c.ellipse(cx, cy + 1.5, rx, ry, lambda x, y, dx, dy: c.put(x, y, ROCK[0], solid=False))
    c.ellipse(cx, cy, rx, ry, lambda x, y, dx, dy: c.put(x, y, lit(ROCK, dx * 0.4, dy * 1.4, ry), solid=False))
    for x in range(int(cx - 6), int(cx + 4)):
        c.put(x, cy - 1 + (x - cx) * 0.35, ROCK[0], solid=False)
    for i in range(7):
        c.put(cx - rx + 1 + i * 1.2, cy + ry * 0.4 + (i % 2), LEAF_DEEP[1], solid=False)


def _p_teacup(c):
    """A teacup and saucer for a pond. The sprite is a RING: the cup's wall, its gold rim, the saucer under it
    and the handle, around a clear round middle where the pond's tea shows through. Drawn round (top-down),
    centred on the sprite (the world places it so the centre lands on the pond)."""
    cx, cy = c.w / 2, c.h / 2
    rim_r = 112
    wall = 124
    saucer = 160
    for y in range(int(cy - saucer), int(cy + saucer) + 2):
        for x in range(int(cx - saucer), int(cx + saucer) + 2):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            if r > saucer or r < rim_r:
                continue
            k = (-dx - dy) / (r + 1)
            col = CHINA[2] if k > 0.35 else (CHINA[0] if k < -0.35 else CHINA[1])
            if r > saucer - 2:
                col = GOLD[1]
            elif r > saucer - 4:
                col = GOLD[2]
            elif saucer - 20 < r < saucer - 16:
                col = (0.62, 0.74, 0.90)
            elif saucer - 16 <= r < saucer - 14:
                col = GOLD[2]
            elif wall + 11 < r < wall + 14:
                col = mix(col, (0.5, 0.52, 0.6), 0.45)
            c.put(x, y, col, solid=False)
    for y in range(int(cy - wall - 4), int(cy + wall + 5)):
        for x in range(int(cx - wall - 4), int(cx + wall + 5)):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            if r > wall or r < rim_r:
                continue
            k = (-dx - dy) / (r + 1)
            col = CHINA[2] if k > 0.4 else (CHINA[0] if k < -0.4 else CHINA[1])
            if r < rim_r + 3:
                col = GOLD[2] if k > 0 else GOLD[1]
            elif rim_r + 14 < r < rim_r + 16:
                col = (0.62, 0.74, 0.90)
            c.put(x, y, col, solid=False)
    for y in range(int(cy - rim_r), int(cy + rim_r) + 1):
        for x in range(int(cx - rim_r), int(cx + rim_r) + 1):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            if rim_r - 5 <= r < rim_r:
                k = (-dx - dy) / (r + 1)
                c.put(x, y, (0.36, 0.20, 0.10) if k < 0 else (0.62, 0.42, 0.22), solid=False)
    hx, hy = cx + wall + 14, cy
    for y in range(int(hy - 34), int(hy + 35)):
        for x in range(int(cx + wall - 4), int(hx + 31)):
            dx, dy = x - hx, y - hy
            r = math.hypot(dx, dy / 1.15)
            if 18 <= r <= 30 and dx > -26:
                k = (-dx - dy) / (r + 1)
                c.put(x, y, CHINA[2] if k > 0.3 else (CHINA[0] if k < -0.3 else CHINA[1]), solid=False)


PROP_BUILDERS = {
    "lost_button": ((38, 28), _p_lost_button),
    "coiled_hose": ((80, 50), _p_coiled_hose),
    "watering_can": ((56, 50), _p_watering_can),
    "tipped_pot": ((66, 46), _p_tipped_pot),
    "clothes_peg": ((46, 16), _p_peg),
    "snail_shell": ((44, 40), _p_snail_shell),
    "dewdrop": ((26, 28), _p_dewdrop),
    "cotton_reel": ((44, 38), _p_spool),
    "red_thread": ((50, 16), _p_red_thread),
    "gap_worn": ((30, 14), _p_gap_worn),
    "bottle_cap": ((40, 22), _p_bottle_cap),
    "seed_packet": ((34, 44), _p_seed_packet),
    "flagstone": ((54, 30), _p_flagstone),
}


def teacup_image():
    """The teacup-and-saucer RING (see _p_teacup), a plain image the world draws centred on the pond (it is not a
    sprite prop: props anchor at their feet, and this one has to centre on its position)."""
    c = Canvas(344, 344)
    _p_teacup(c)
    return c.img


def make_prop(name):
    """(base, tint_or_None) for a Thimblewick prop. None has a tint layer: their colours are fixed."""
    (w, h), fn = PROP_BUILDERS[name]
    c = Canvas(w, h)
    fn(c)
    c.outline()
    return c.img, (c.tint if c.has_tint else None)


# ------------------------------------------------------------------ preview
def preview(path, scale=2):
    """A contact sheet: flowers, clover, grass, pickets, sunflowers, understory, props, the tile and litter."""
    bg = (130, 160, 96, 255)
    items = []
    for n in FLOWERS:
        t, cnp = flower_stalk(n)
        im = t.copy()
        im.alpha_composite(cnp)
        items.append(im)
    for v in (0, 1):
        t, cnp = clover(v)
        im = t.copy()
        im.alpha_composite(cnp)
        items.append(im)
    for v in GRASSES:
        items.append(grass_clump(v))
    for st, i in PICKETS:
        items.append(picket(st, i))
    for v in GREAT:
        t, cnp = sunflower(v)
        im = t.copy()
        im.alpha_composite(cnp)
        items.append(im)
    for fn in UNDERSTORY.values():
        items.append(fn())
    for name in PROP_BUILDERS:
        items.append(make_prop(name)[0])
    items.append(teacup_image().resize((172, 172), Image.NEAREST))
    atlas, _ = detail_atlas()
    items.append(atlas)
    items.append(tea_tile())
    items.append(terrain_atlas())
    pad = 8
    rows, row, rw = [], [], pad
    for im in items:
        if rw + im.width + pad > 1000 and row:
            rows.append(row)
            row, rw = [], pad
        row.append(im)
        rw += im.width + pad
    rows.append(row)
    H = sum(max(i.height for i in r) + pad for r in rows) + pad
    sheet = Image.new("RGBA", (1000, H), bg)
    y = pad
    for r in rows:
        x = pad
        rh = max(i.height for i in r)
        for im in r:
            sheet.alpha_composite(im, (x, y + rh - im.height))
            x += im.width + pad
        y += rh + pad
    sheet = sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)
    sheet.save(path)
    print("wrote preview", path)
