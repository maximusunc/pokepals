"""
Ohmstead -- the machine behind the Gateway -- line art: everything is a bright outline on the dark, with a soft
halo baked round it (the web build has no bloom pass, so the glow is in the pixels).

The look is ONE idea: things are DRAWN, not painted. A shape is a dark, nearly opaque fill (so what stands
behind it doesn't tangle with it), a one-pixel bright outline, a few dimmer inner lines that give it facets,
and a blurred copy of those lines underneath as its glow. Each colour has one job (see the world's design
notes): cyan is the world, amber is warmth (lamps, doors), white is signage, red marks where the power is out,
mint is the runners, violet the way home.

No shared machinery is touched: this module draws with Pillow's ImageDraw on its own small `Wire` canvas.
Everything is deterministic (seeded by name), so re-running reproduces the PNGs byte for byte.
Baked by tools/gen_ohmstead.py.
"""

import math
import random

from PIL import Image, ImageDraw, ImageFilter

CYAN = (94, 242, 255, 255)
CYAN_DIM = (58, 150, 190, 210)
AMBER = (255, 181, 71, 255)
AMBER_DIM = (190, 120, 50, 220)
WHITE = (236, 252, 255, 255)
WHITE_DIM = (150, 190, 210, 220)
RED = (255, 79, 109, 255)
RED_DIM = (170, 60, 90, 220)
MINT = (125, 255, 176, 255)
MINT_DIM = (70, 170, 120, 220)
VIOLET = (183, 139, 255, 255)
FILL = (7, 6, 22, 214)


class Wire:
    """A small canvas: dark fills, bright lines, and a baked halo of the lines."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.fill = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.lines = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self._f = ImageDraw.Draw(self.fill)
        self._l = ImageDraw.Draw(self.lines)

    def poly(self, pts, col=CYAN, fill=FILL):
        pts = [(round(x), round(y)) for x, y in pts]
        if fill is not None:
            self._f.polygon(pts, fill=fill)
        self._l.line(pts + [pts[0]], fill=col, width=1)

    def line(self, pts, col=CYAN_DIM):
        self._l.line([(round(x), round(y)) for x, y in pts], fill=col, width=1)

    def dot(self, x, y, col=WHITE):
        self._l.point((round(x), round(y)), fill=col)

    def rect(self, x0, y0, x1, y1, col=CYAN, fill=FILL):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], col, fill)

    def ellipse(self, cx, cy, rx, ry, col=CYAN_DIM, fill=None):
        box = [round(cx - rx), round(cy - ry), round(cx + rx), round(cy + ry)]
        if fill is not None:
            self._f.ellipse(box, fill=fill)
        self._l.ellipse(box, outline=col)

    def solid(self, x0, y0, x1, y1, col):
        self._l.rectangle([round(x0), round(y0), round(x1), round(y1)], fill=col)

    def bake(self, glow=0.6, blur=1.5):
        halo = self.lines.filter(ImageFilter.GaussianBlur(blur))
        r, g, b, a = halo.split()
        a = a.point(lambda v: int(min(255, v * glow * 1.6)))
        halo = Image.merge("RGBA", (r, g, b, a))
        out = self.fill.copy()
        out.alpha_composite(halo)
        out.alpha_composite(self.lines)
        return out


def _blank(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


# ------------------------------------------------------------------ trees: (trunk, canopy) pairs, base at bottom centre
def _trunk(w, h, stem, ring=9):
    t = Wire(w, h)
    cx = w // 2
    t.ellipse(cx, h - 4, ring, 3, CYAN_DIM)
    t.line([(cx - 2, h - 4), (cx - 2, h - 4 - stem)], CYAN)
    t.line([(cx + 2, h - 4), (cx + 2, h - 4 - stem)], CYAN)
    t.line([(cx - 2, h - 4), (cx + 2, h - 4)], CYAN)
    return t.bake()


def pine(tiers, w=44, step=14, half=17):
    h = 20 + tiers * step + 12
    cx = w // 2
    c = Wire(w, h)
    base = h - 16
    for k in range(tiers):
        hw = half - k * 4
        y0 = base - k * (step - 2)
        apex = y0 - step - 4
        c.poly([(cx - hw, y0), (cx, apex), (cx + hw, y0)])
        c.line([(cx - hw, y0), (cx, y0 - 5), (cx + hw, y0)], CYAN_DIM)
        c.line([(cx, apex), (cx, y0 - 5)], CYAN_DIM)
    return _trunk(w, h, 12), c.bake()


def geo(seed, w=48, h=60, sides=7, r=17):
    rnd = random.Random(seed)
    cx, cy = w // 2, h - 36
    c = Wire(w, h)
    pts = []
    for k in range(sides):
        a = -math.pi / 2 + k * 2 * math.pi / sides + rnd.uniform(-0.18, 0.18)
        rr = r * rnd.uniform(0.86, 1.08)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.92))
    c.poly(pts)
    hub = (cx + rnd.uniform(-3, 3), cy + rnd.uniform(-3, 2))
    for p in pts:
        c.line([hub, p], CYAN_DIM)
    return _trunk(w, h, 18), c.bake()


def ball(w=46, h=58, r=16):
    """A regular faceted ball: an octagon with a smaller one inside, joined corner to corner."""
    cx, cy = w // 2, h - 34
    c = Wire(w, h)
    outer = [(cx + math.cos(k * math.pi / 4 + math.pi / 8) * r, cy + math.sin(k * math.pi / 4 + math.pi / 8) * r) for k in range(8)]
    inner = [(cx - 2 + math.cos(k * math.pi / 4 + math.pi / 8) * r * 0.48, cy - 2 + math.sin(k * math.pi / 4 + math.pi / 8) * r * 0.48) for k in range(8)]
    c.poly(outer)
    c.line(inner + [inner[0]], CYAN_DIM)
    for a, b in zip(outer, inner):
        c.line([a, b], CYAN_DIM)
    return _trunk(w, h, 16), c.bake()


def cube(w=40, h=52, s=13):
    """A cube on a stem, seen a little from above: the machine's idea of a shrub."""
    cx, top = w // 2, h - 46
    c = Wire(w, h)
    d = 6
    hexa = [(cx - s, top + d), (cx, top), (cx + s, top + d), (cx + s, top + d + s + 3), (cx, top + 2 * d + s + 3), (cx - s, top + d + s + 3)]
    c.poly(hexa)
    mid = (cx, top + 2 * d)
    c.line([(cx - s, top + d), mid, (cx + s, top + d)], CYAN)
    c.line([mid, (cx, top + 2 * d + s + 3)], CYAN)
    c.line([(cx - s // 2, top + d + d // 2 + 4), (cx - s // 2, top + d + s)], CYAN_DIM)
    c.line([(cx + s // 2, top + d + d // 2 + 4), (cx + s // 2, top + d + s)], CYAN_DIM)
    return _trunk(w, h, 14), c.bake()


def great_mast(w=96, h=132):
    """A landmark: a tall lattice mast with a dish and a slow amber lamp at its tip."""
    cx = w // 2
    t = Wire(w, h)
    t.ellipse(cx, h - 5, 26, 6, CYAN_DIM)
    t.line([(cx - 20, h - 5), (cx - 5, h - 104)], CYAN)
    t.line([(cx + 20, h - 5), (cx + 5, h - 104)], CYAN)
    t.line([(cx - 20, h - 5), (cx + 20, h - 5)], CYAN)
    levels = 6
    prev = None
    for k in range(levels + 1):
        f = k / levels
        y = h - 5 - f * 99
        hw = 20 - f * 15
        t.line([(cx - hw, y), (cx + hw, y)], CYAN_DIM)
        if prev is not None:
            t.line([(cx - prev[1], prev[0]), (cx + hw, y)], CYAN_DIM)
            t.line([(cx + prev[1], prev[0]), (cx - hw, y)], CYAN_DIM)
        prev = (y, hw)
    c = Wire(w, h)
    c.line([(cx, h - 104), (cx, h - 124)], CYAN)
    c.poly([(cx - 4, h - 124), (cx, h - 129), (cx + 4, h - 124), (cx, h - 119)], AMBER, FILL)
    c.dot(cx, h - 124, WHITE)
    c.poly([(cx + 8, h - 86), (cx + 28, h - 96), (cx + 30, h - 78)], CYAN)
    c.line([(cx + 8, h - 86), (cx + 22, h - 86)], CYAN_DIM)
    c.poly([(cx - 8, h - 66), (cx - 30, h - 72), (cx - 28, h - 56)], CYAN)
    c.line([(cx - 8, h - 66), (cx - 22, h - 64)], CYAN_DIM)
    return t.bake(), c.bake(0.7)


def great_dome(w=112, h=118):
    """A landmark: a big geodesic dome of a tree, three rings of facets on a thick stem."""
    cx, cy, r = w // 2, h - 66, 46
    t = Wire(w, h)
    t.ellipse(cx, h - 5, 22, 5, CYAN_DIM)
    for dx in (-5, 5):
        t.line([(cx + dx, h - 5), (cx + dx, h - 30)], CYAN)
    t.line([(cx - 5, h - 5), (cx + 5, h - 5)], CYAN)
    c = Wire(w, h)
    rings = []
    for ring, (rr, n) in enumerate([(1.0, 12), (0.68, 9), (0.36, 6)]):
        pts = [(cx + math.cos(k * 2 * math.pi / n + ring * 0.3) * r * rr, cy - 4 * ring + math.sin(k * 2 * math.pi / n + ring * 0.3) * r * rr * 0.8) for k in range(n)]
        rings.append(pts)
    c.poly(rings[0])
    for pts in rings[1:]:
        c.line(pts + [pts[0]], CYAN_DIM)
    for a, b in zip(rings, rings[1:]):
        for i, p in enumerate(a):
            q = b[int(i * len(b) / len(a)) % len(b)]
            c.line([p, q], CYAN_DIM)
    hub = (cx, cy - 10)
    for p in rings[2]:
        c.line([hub, p], CYAN_DIM)
    return t.bake(), c.bake(0.7)


GROVE = {
    "pine_a": lambda: pine(3),
    "pine_b": lambda: pine(4),
    "pine_c": lambda: pine(2, w=36, half=13),
    "geo_a": lambda: geo(11),
    "geo_b": lambda: geo(29, sides=6, r=15),
    "ball_a": ball,
    "cube_a": cube,
}
GREAT = {"great_mast": great_mast, "great_dome": great_dome}


def bush_a():
    c = Wire(22, 16)
    pts = [(3, 13), (5, 6), (11, 3), (17, 6), (19, 13)]
    c.poly(pts)
    c.line([(5, 6), (11, 10), (17, 6)], CYAN_DIM)
    c.line([(11, 10), (11, 13)], CYAN_DIM)
    return c.bake(0.5)


def bush_b():
    c = Wire(24, 16)
    for x, s in ((6, 5), (13, 8), (19, 4)):
        c.poly([(x - s * 0.7, 13), (x, 13 - s * 1.3), (x + s * 0.7, 13)])
    return c.bake(0.5)


def stump():
    c = Wire(16, 14)
    c.poly([(3, 6), (8, 3), (13, 6), (13, 11), (8, 13), (3, 11)])
    c.line([(3, 6), (8, 8), (13, 6)], CYAN)
    c.line([(8, 8), (8, 13)], CYAN)
    return c.bake(0.5)


UNDERSTORY = {"bush_a": bush_a, "bush_b": bush_b, "stump": stump}

# ------------------------------------------------------------------ a tiny 3x5 pixel alphabet, for signs
FONT = {
    "A": "010101111101101", "R": "110101110101101", "C": "011100100100011", "D": "110101101101110",
    "E": "111100110100111", "T": "111010010010010", "O": "010101101101010", "Y": "101101010010010",
    "H": "101101111101101", "M": "101111111101101", "S": "011100010001110", "N": "110101101101101",
    "L": "100100100100111", "I": "111010010010111", "G": "011100101101011", " ": "000000000000000",
}


def text(w, x, y, s, col=WHITE):
    for ch in s:
        bits = FONT.get(ch, FONT[" "])
        for i, b in enumerate(bits):
            if b == "1":
                w.dot(x + i % 3, y + i // 3, col)
        x += 4
    return x


# ------------------------------------------------------------------ props: base images, feet at bottom centre
def lamp():
    w = Wire(15, 36)
    cx = 7
    w.line([(cx, 33), (cx, 15)], AMBER_DIM)
    w.line([(cx - 3, 33), (cx + 3, 33)], AMBER_DIM)
    w.poly([(cx, 3), (cx + 5, 9), (cx, 15), (cx - 5, 9)], AMBER, (60, 34, 8, 220))
    w.line([(cx - 5, 9), (cx + 5, 9)], AMBER_DIM)
    w.dot(cx, 9, WHITE)
    return w.bake(0.9, 1.8)


def cabin():
    w = Wire(54, 46)
    # front, roof, and the side going back to the right
    w.rect(5, 22, 35, 42)
    w.poly([(5, 22), (20, 8), (35, 22)])
    w.poly([(35, 22), (48, 15), (48, 35), (35, 42)])
    w.poly([(20, 8), (33, 2), (48, 15), (35, 22)])
    w.rect(15, 28, 24, 42, AMBER, (60, 34, 8, 220))
    w.rect(28, 27, 32, 31, CYAN_DIM, None)
    w.line([(39, 26), (44, 23), (44, 28), (39, 31), (39, 26)], CYAN_DIM)
    return w.bake(0.6)


def tower():
    w = Wire(34, 74)
    cx = 17
    w.ellipse(cx, 70, 11, 3, CYAN_DIM)
    w.line([(cx - 8, 70), (cx - 3, 20)], CYAN)
    w.line([(cx + 8, 70), (cx + 3, 20)], CYAN)
    prev = None
    for k in range(6):
        f = k / 5
        y = 70 - f * 50
        hw = 8 - f * 5
        w.line([(cx - hw, y), (cx + hw, y)], CYAN_DIM)
        if prev:
            w.line([(cx - prev[1], prev[0]), (cx + hw, y)], CYAN_DIM)
        prev = (y, hw)
    w.line([(cx, 20), (cx, 8)], CYAN)
    w.poly([(cx - 3, 8), (cx, 4), (cx + 3, 8), (cx, 12)], WHITE, FILL)
    w.poly([(cx + 4, 30), (cx + 14, 25), (cx + 15, 36)], CYAN)
    return w.bake(0.6)


def sign(label=None, w_=26):
    w = Wire(w_, 26)
    w.line([(w_ // 2, 23), (w_ // 2, 13)], WHITE_DIM)
    w.line([(w_ // 2 - 3, 23), (w_ // 2 + 3, 23)], WHITE_DIM)
    w.rect(2, 2, w_ - 3, 13, WHITE)
    if label:
        text(w, 5, 5, label, WHITE)
    else:
        w.line([(5, 6), (w_ - 6, 6)], WHITE_DIM)
        w.line([(5, 9), (w_ - 9, 9)], WHITE_DIM)
    return w.bake(0.5)


def terminal():
    w = Wire(22, 26)
    w.poly([(4, 23), (4, 12), (17, 12), (17, 23)])
    w.poly([(4, 12), (7, 3), (20, 3), (17, 12)])
    w.line([(9, 5), (17, 5)], MINT)
    w.line([(8, 7), (14, 7)], MINT_DIM)
    w.line([(8, 9), (16, 9)], MINT_DIM)
    w.line([(17, 23), (20, 20), (20, 3)], CYAN_DIM)
    return w.bake(0.6)


def chip():
    w = Wire(46, 30)
    w.poly([(6, 20), (14, 8), (40, 8), (32, 20)])
    w.poly([(6, 20), (32, 20), (32, 25), (6, 25)])
    w.poly([(32, 20), (40, 8), (40, 13), (32, 25)])
    for k in range(5):
        x = 9 + k * 5
        w.line([(x, 25), (x, 28)], CYAN_DIM)
    w.line([(15, 12), (33, 12)], CYAN_DIM)
    w.line([(13, 15), (27, 15)], CYAN_DIM)
    w.dot(12, 17, AMBER)
    return w.bake(0.6)


def capacitor():
    w = Wire(18, 30)
    w.ellipse(9, 6, 6, 3, CYAN, FILL)
    w.line([(3, 6), (3, 24)], CYAN)
    w.line([(15, 6), (15, 24)], CYAN)
    w.ellipse(9, 24, 6, 3, CYAN, FILL)
    w.solid(4, 20, 14, 23, (0, 0, 0, 0))
    w._f.rectangle([3, 6, 15, 24], fill=FILL)
    w.line([(4, 12), (14, 12)], CYAN_DIM)
    w.line([(12, 8), (12, 24)], AMBER_DIM)
    return w.bake(0.6)


def coil():
    w = Wire(26, 28)
    for k in range(5):
        y = 6 + k * 4
        w.ellipse(13, y, 8, 3, CYAN if k % 2 == 0 else CYAN_DIM)
    w.line([(13, 2), (13, 25)], AMBER)
    w.line([(9, 25), (17, 25)], CYAN_DIM)
    return w.bake(0.7)


def pylon():
    """Stands round the sector with no power: a red marker, the one place red is used."""
    w = Wire(14, 30)
    cx = 7
    w.poly([(cx - 4, 27), (cx, 6), (cx + 4, 27)], RED)
    w.line([(cx - 2, 18), (cx + 2, 18)], RED_DIM)
    w.line([(cx - 3, 23), (cx + 3, 23)], RED_DIM)
    w.dot(cx, 4, RED)
    w.dot(cx, 3, WHITE)
    return w.bake(0.8)


def bit():
    w = Wire(10, 10)
    w.poly([(2, 4), (5, 2), (8, 4), (8, 7), (5, 9), (2, 7)], CYAN_DIM)
    w.line([(2, 4), (5, 6), (8, 4)], CYAN_DIM)
    w.line([(5, 6), (5, 9)], CYAN_DIM)
    return w.bake(0.4)


def marquee(label, w_):
    w = Wire(w_, 36)
    w.line([(5, 33), (5, 14)], WHITE_DIM)
    w.line([(w_ - 6, 33), (w_ - 6, 14)], WHITE_DIM)
    w.rect(2, 3, w_ - 3, 15, WHITE)
    x0 = (w_ - (len(label) * 4 - 1)) // 2
    text(w, x0, 7, label, WHITE)
    w.dot(4, 5, AMBER)
    w.dot(w_ - 5, 5, AMBER)
    w.dot(4, 13, AMBER)
    w.dot(w_ - 5, 13, AMBER)
    return w.bake(0.8)


def fount():
    """The plaza's landmark: rings of light with a thin beam going up out of them."""
    w = Wire(44, 56)
    cx = 22
    w.ellipse(cx, 48, 17, 5, CYAN, FILL)
    w.ellipse(cx, 44, 12, 4, CYAN_DIM)
    w.ellipse(cx, 40, 7, 3, WHITE_DIM)
    w.line([(cx, 40), (cx, 4)], WHITE)
    w.line([(cx - 2, 34), (cx - 2, 16)], CYAN_DIM)
    w.line([(cx + 2, 30), (cx + 2, 10)], CYAN_DIM)
    return w.bake(0.9, 2.0)


def gate():
    """The Arcade's way in: two posts and a lintel, lit white."""
    w = Wire(44, 44)
    w.line([(6, 41), (6, 8)], WHITE)
    w.line([(37, 41), (37, 8)], WHITE)
    w.poly([(3, 8), (22, 2), (40, 8)], WHITE)
    w.line([(3, 41), (9, 41)], WHITE_DIM)
    w.line([(34, 41), (40, 41)], WHITE_DIM)
    w.dot(22, 5, AMBER)
    return w.bake(0.7)


PROP_BUILDERS = {
    "oh_lamp": lamp,
    "oh_cabin": cabin,
    "oh_tower": tower,
    "oh_sign": sign,
    "oh_terminal": terminal,
    "oh_chip": chip,
    "oh_capacitor": capacitor,
    "oh_coil": coil,
    "oh_pylon": pylon,
    "oh_bit": bit,
    "oh_arcade_sign": lambda: marquee("ARCADE", 40),
    "oh_today_sign": lambda: marquee("TODAY", 36),
    "oh_fount": fount,
    "oh_gate": gate,
}


# ------------------------------------------------------------------ the runners: 4 frames of a little trot, facing right
def runner_sheet():
    """16x16 frames in a row: a wedge of a body on two legs, a bright packet of light carried on its back."""
    sheet = _blank(16 * 4, 16)
    legs = [((5, 13), (10, 13)), ((6, 12), (9, 13)), ((7, 13), (8, 12)), ((6, 13), (9, 12))]
    for f in range(4):
        w = Wire(16, 16)
        bob = 1 if f in (1, 3) else 0
        w.poly([(3, 6 + bob), (10, 6 + bob), (13, 9 + bob), (10, 11 + bob), (3, 11 + bob)], MINT)
        w.dot(10, 8 + bob, WHITE)
        (ax, ay), (bx, by) = legs[f]
        w.line([(5, 11 + bob), (ax, ay)], MINT)
        w.line([(9, 11 + bob), (bx, by)], MINT)
        w.solid(4, 2 + bob, 7, 4 + bob, WHITE)
        sheet.alpha_composite(w.bake(0.7, 1.2), (16 * f, 0))
    return sheet


def preview(path):
    items = []
    for name, fn in GROVE.items():
        t, c = fn()
        t.alpha_composite(c)
        items.append(t)
    for name, fn in GREAT.items():
        t, c = fn()
        t.alpha_composite(c)
        items.append(t)
    for fn in UNDERSTORY.values():
        items.append(fn())
    for fn in PROP_BUILDERS.values():
        items.append(fn())
    items.append(runner_sheet())
    pad = 6
    wsum = sum(i.width + pad for i in items) + pad
    hmax = max(i.height for i in items) + 2 * pad
    canvas = Image.new("RGBA", (wsum, hmax), (5, 3, 13, 255))
    x = pad
    for i in items:
        canvas.alpha_composite(i, (x, hmax - pad - i.height))
        x += i.width + pad
    canvas = canvas.resize((canvas.width * 3, canvas.height * 3), Image.NEAREST)
    canvas.save(path)
    print("wrote preview", path)
