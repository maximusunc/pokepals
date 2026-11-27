"""
Brick art -- the look of CLICKTON, the little city made entirely of small colourful bricks.

Everything in that world is built from the same few ideas, so it reads as one toy box:

  * a PIECE is a box of studs: nx x ny studs wide and deep, `ph` plates tall (a brick is 3 plates, a
    flat plate is 1). It is drawn in the same oblique view as the rest of the game -- the front face,
    and the top face seen from a little above, with its studs standing on it.
  * a MODEL is a list of pieces. `render()` paints them back to front into a pixel-art image, in one
    of two layers: `base` (the pieces with their own colours) and `tint` (pieces flagged `tint`, drawn
    in white shades so the client can colour them per prop, the way every other prop's tint layer works).
  * tiles (the baseplate the ground is made of, the wall, the roof and the road plates) are pixel
    patterns of the same studs and seams.

Pure Pillow, seeded and deterministic. Scale is a parameter: the world uses W=8 px per stud, the little
loose bricks scattered on the ground use half of that.
"""

import random

from PIL import Image

# ── the colours of the box ────────────────────────────────────────────────────────────────────────
RED = (196, 40, 27)
DKRED = (123, 46, 47)
BLUE = (13, 105, 171)
SKY = (116, 184, 222)
YELLOW = (245, 205, 48)
GREEN = (40, 127, 70)
LIME = (164, 189, 71)
DKGREEN = (36, 100, 52)
ORANGE = (218, 133, 64)
WHITE = (242, 243, 243)
BLACK = (27, 42, 52)
GREY = (163, 162, 165)
DKGREY = (99, 95, 98)
TAN = (215, 197, 153)
BROWN = (105, 64, 40)
PINK = (255, 152, 220)
LAVENDER = (167, 131, 200)
TEAL = (18, 157, 157)
NOUGAT = (204, 142, 105)
CLEARYELLOW = (255, 240, 150)

RAINBOW = [(196, 40, 27), (218, 133, 64), (245, 205, 48), (40, 150, 70), (13, 105, 171), (123, 70, 190)]


def mul(c, k):
    return tuple(max(0, min(255, int(round(v * k)))) for v in c[:3])


# ── a model ───────────────────────────────────────────────────────────────────────────────────────
class Part:
    __slots__ = ("x", "y", "z", "nx", "ny", "ph", "color", "tint", "studs")

    def __init__(self, x, y, z, nx, ny, ph, color, tint=False, studs=True):
        self.x, self.y, self.z, self.nx, self.ny, self.ph = x, y, z, nx, ny, ph
        self.color, self.tint, self.studs = color, tint, studs


class Model:
    """A list of pieces. x runs right, y runs BACK (0 = the front row), z runs up in plates."""

    def __init__(self):
        self.parts = []

    def add(self, x, y, z, nx, ny, ph, color, tint=False, studs=True):
        self.parts.append(Part(x, y, z, nx, ny, ph, color, tint, studs))
        return self

    def brick(self, x, y, z, nx, ny, color, tint=False):
        return self.add(x, y, z, nx, ny, 3, color, tint)

    def plate(self, x, y, z, nx, ny, color, tint=False, studs=True):
        return self.add(x, y, z, nx, ny, 1, color, tint, studs)

    def top(self):
        return max((p.z + p.ph for p in self.parts), default=0)

    def bounds_x(self):
        return min(p.x for p in self.parts), max(p.x + p.nx for p in self.parts)


def _order(parts):
    """Back to front: a piece farther away goes first; a piece on top of another goes after it."""
    n = len(parts)
    after = [set() for _ in range(n)]      # after[i] = parts that must be drawn before i
    indeg = [0] * n
    for i in range(n):
        a = parts[i]
        for j in range(i + 1, n):
            b = parts[j]
            if a.x >= b.x + b.nx or b.x >= a.x + a.nx:
                continue                    # side by side: they never cover each other
            if a.y < b.y + b.ny and b.y < a.y + a.ny:     # overlapping depth: the lower one first
                if a.z == b.z:
                    first, second = (i, j) if a.y >= b.y else (j, i)
                else:
                    first, second = (i, j) if a.z < b.z else (j, i)
            else:
                first, second = (i, j) if a.y > b.y else (j, i)    # the farther one first
            after[second].add(first)
    for i in range(n):
        indeg[i] = len(after[i])
    out, ready = [], sorted((i for i in range(n) if indeg[i] == 0), key=lambda i: (-parts[i].y, parts[i].z))
    done = set()
    while ready:
        i = ready.pop(0)
        out.append(i)
        done.add(i)
        for k in range(n):
            if i in after[k]:
                after[k].discard(i)
                if not after[k] and k not in done and k not in ready:
                    ready.append(k)
        ready.sort(key=lambda i: (-parts[i].y, parts[i].z))
    for i in range(n):      # a cycle (never in a sane model): fall back to a plain sort
        if i not in done:
            out.append(i)
    return [parts[i] for i in out]


def _rect(px, x0, y0, x1, y1, c):
    w, h = px.size
    for y in range(max(0, y0), min(h, y1 + 1)):
        for x in range(max(0, x0), min(w, x1 + 1)):
            px.putpixel((x, y), c + (255,) if len(c) == 3 else c)


def _draw_part(img, p, ox, oy, W, PL, D, layer):
    """Paint one piece. (ox, oy) is where the front-left foot of stud 0 meets the ground."""
    is_tint = p.tint
    if layer == "tint" and not is_tint:
        return
    if layer == "base" and is_tint:
        return
    c = (236, 236, 236) if is_tint else p.color
    X0 = ox + p.x * W
    X1 = X0 + p.nx * W - 1
    fh = p.ph * PL
    top = oy - (p.z + p.ph) * PL - p.y * D          # the front face's top edge
    bot = top + fh - 1
    back = top - p.ny * D                            # the back edge of the top face
    # top face
    ctop = mul(c, 1.16)
    _rect(img, X0, back, X1, top - 1, ctop)
    # a bright rim along the back and left, a darker one along the right
    _rect(img, X0, back, X1, back, mul(c, 1.28))
    _rect(img, X0, back, X0, top - 1, mul(c, 1.24))
    _rect(img, X1, back, X1, top - 1, mul(c, 1.0))
    # front face
    _rect(img, X0, top, X1, bot, c)
    _rect(img, X0, top, X0, bot, mul(c, 1.14))          # lit left edge
    _rect(img, X1, top, X1, bot, mul(c, 0.84))          # shaded right edge
    _rect(img, X0, bot, X1, bot, mul(c, 0.74))          # the seam underneath
    # a brick of 2+ studs shows its joins on the front face too (a hint of the pieces' seams)
    # studs on the top face
    if p.studs:
        sw = max(2, W // 2)                              # stud width
        sd = max(1, D // 2)                              # stud top depth
        for ix in range(p.nx):
            for iy in range(p.ny):
                cx = X0 + ix * W + (W - sw) // 2
                # row iy counts from the front; its cell spans [top - (iy+1)*D, top - iy*D - 1]
                cell_bot = top - iy * D - 1
                ty1 = cell_bot - (1 if D >= 3 else 0)           # the stud's top ellipse bottom row
                ty0 = ty1 - sd + 1
                _rect(img, cx, ty0, cx + sw - 1, ty1, mul(c, 1.3))
                if sw >= 4:
                    _rect(img, cx, ty0, cx, ty0, mul(c, 1.5))                   # a glint
                if D >= 3:
                    _rect(img, cx, cell_bot, cx + sw - 1, cell_bot, mul(c, 0.8))   # its side


def render(model, layer="base", W=8, PL=2, D=4, pad=2, foot=8, min_size=None, extra_h=0):
    """Paint `model`. Returns an RGBA image whose bottom edge sits `foot` px below the front-bottom of the
    model's base (so a prop's image can use the same anchor the rest of the game uses), centred on the
    model's width."""
    parts = _order(model.parts)
    x0, x1 = model.bounds_x()
    ymax = max(p.y + p.ny for p in model.parts)
    height = (model.top()) * PL + ymax * D + 2 + extra_h
    wpx = (x1 - x0) * W
    w = wpx + pad * 2
    h = height + pad + foot
    if min_size:
        w = max(w, min_size[0])
        h = max(h, min_size[1])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ox = (w - wpx) // 2 - x0 * W
    oy = h - foot
    for p in parts:
        _draw_part(img, p, ox, oy, W, PL, D, layer)
    return img


def shadow_for(model, W=8, D=4, PL=2, foot=8, size=None, alpha=70):
    """A flat shadow of the model's footprint, thrown down and to the right, as its own image."""
    x0, x1 = model.bounds_x()
    ymax = max(p.y + p.ny for p in model.parts)
    return x0, x1, ymax


def with_shadow(img, model, W=8, D=4, foot=8, alpha=64):
    """Composite a hard ground shadow under `img` (the footprint, offset a stud down-right)."""
    x0, x1 = model.bounds_x()
    ymax = max(p.y + p.ny for p in model.parts)
    w, h = img.size
    ox = (w - (x1 - x0) * W) // 2
    oy = h - foot
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    _rect(sh, ox + 2, oy - ymax * D + 2, ox + (x1 - x0) * W + W // 2, oy + 2, (20, 20, 40, alpha))
    sh.alpha_composite(img)
    return sh


# ── blobs and runs: the tree builders ─────────────────────────────────────────────────────────────
def disc(cx, cy, r):
    out = []
    n = int(r) + 2
    for x in range(int(cx) - n, int(cx) + n + 1):
        for y in range(int(cy) - n, int(cy) + n + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.3:
                out.append((x, y))
    return out


def fill_layer(m, cells, z, ph, palette, rng, tint=False, max_run=3):
    """Cover a set of (x, y) cells with bricks: runs along x, split into random lengths, each its own
    colour from `palette` -- the patchwork a real brick build has."""
    rows = {}
    for x, y in cells:
        rows.setdefault(y, []).append(x)
    for y, xs in rows.items():
        xs.sort()
        run = [xs[0]]
        runs = []
        for x in xs[1:]:
            if x == run[-1] + 1:
                run.append(x)
            else:
                runs.append(run)
                run = [x]
        runs.append(run)
        for run in runs:
            i = 0
            while i < len(run):
                n = min(rng.choice([1, 2, 2, 3][: max_run + 1]), len(run) - i)
                m.add(run[i], y, z, n, 1, ph, rng.choice(palette), tint)
                i += n


GREENS = [(40, 127, 70), (75, 151, 74), (36, 100, 52), (88, 171, 80)]
LIMES = [(164, 189, 71), (120, 168, 60), (190, 210, 90), (75, 151, 74)]
PINES = [(30, 90, 60), (36, 100, 52), (22, 70, 50), (50, 120, 70)]
AUTUMN = [(218, 133, 64), (196, 40, 27), (245, 205, 48), (190, 90, 40)]
BLOSSOM = [(255, 152, 220), (255, 190, 235), (242, 243, 243), (230, 120, 190)]
TEALS = [(18, 157, 157), (40, 180, 170), (13, 105, 171), (80, 200, 190)]
TREE_VARIANTS = {
    "green": GREENS, "lime": LIMES, "pine": PINES, "autumn": AUTUMN, "blossom": BLOSSOM, "teal": TEALS,
}


def tree_model(variant, great=False, seed=0):
    rng = random.Random(hash((variant, great, seed)) & 0xFFFFFF)
    pal = TREE_VARIANTS[variant]
    m = Model()
    k = 1.6 if great else 1.0
    trunk_w = 2
    trunk_h = 2 if not great else 3
    # a rooted trunk of two-stud bricks, two colours of brown
    for i in range(trunk_h):
        m.add(0, 0, i * 3, trunk_w, 2, 3, BROWN if i % 2 == 0 else mul(BROWN, 1.12))
    cx, cy = (trunk_w - 1) / 2.0, 0.5
    z = trunk_h * 3
    if variant == "pine":
        radii = [2.9, 2.5, 2.1, 1.7, 1.3, 0.9] if not great else [4.4, 3.9, 3.4, 2.9, 2.4, 1.9, 1.4, 0.9]
    else:
        radii = [1.9, 2.7, 2.9, 2.5, 1.7, 0.8] if not great else [3.2, 4.2, 4.6, 4.4, 3.6, 2.6, 1.6, 0.8]
    for r in radii:
        fill_layer(m, disc(cx, cy, r), z, 3, pal, rng, max_run=3)
        z += 3
    return m


# ── props ─────────────────────────────────────────────────────────────────────────────────────────
def _post(m, x, y, z, n, color):
    for i in range(n):
        m.brick(x, y, z + i * 3, 1, 1, color)
    return z + n * 3


def prop_lamp():
    m = Model()
    m.plate(0, 0, 0, 3, 2, DKGREY)
    _post(m, 1, 0, 1, 5, mul(GREY, 0.8))
    m.plate(0, 0, 16, 3, 1, BLACK)
    m.brick(1, 0, 17, 1, 1, CLEARYELLOW)
    m.plate(1, 0, 20, 1, 1, BLACK)
    return m


def prop_bench():
    m = Model()
    m.brick(0, 0, 0, 1, 2, DKGREY)
    m.brick(3, 0, 0, 1, 2, DKGREY)
    m.add(0, 0, 3, 4, 2, 1, (240, 240, 240), tint=True)
    m.add(0, 1, 4, 4, 1, 3, (240, 240, 240), tint=True)
    return m


def prop_hydrant():
    m = Model()
    m.plate(0, 0, 0, 2, 2, DKRED)
    m.brick(0, 0, 1, 2, 2, RED)
    m.brick(0, 0, 4, 2, 2, RED)
    m.plate(0, 0, 7, 2, 2, YELLOW)
    m.brick(-1, 0, 3, 1, 1, RED)
    return m


def prop_mailbox():
    m = Model()
    _post(m, 1, 0, 0, 2, DKGREY)
    m.add(0, 0, 6, 3, 2, 3, BLUE, studs=True)
    m.plate(2, 0, 9, 1, 1, RED)
    return m


def prop_planter(seed=3):
    rng = random.Random(seed)
    m = Model()
    m.add(0, 0, 0, 4, 2, 3, (200, 200, 200), tint=True)
    m.plate(0, 0, 3, 4, 2, BROWN, studs=False)
    for x in range(4):
        for y in range(2):
            m.plate(x, y, 4, 1, 1, rng.choice([RED, YELLOW, WHITE, PINK, ORANGE, LAVENDER]))
            if rng.random() < 0.6:
                m.plate(x, y, 5, 1, 1, rng.choice([GREEN, LIME]))
    return m


def prop_fountain():
    m = Model()
    rng = random.Random(5)
    ring = set(disc(0, 0, 3.4)) - set(disc(0, 0, 2.4))
    inner = set(disc(0, 0, 2.4))
    for z in (0, 3):
        fill_layer(m, ring, z, 3, [GREY, mul(GREY, 0.88), mul(GREY, 1.08)], rng)
    fill_layer(m, inner, 0, 1, [DKGREY], rng)
    fill_layer(m, inner, 1, 2, [(120, 190, 235), (96, 170, 225)], rng, tint=False)
    fill_layer(m, inner, 3, 1, [(150, 210, 245), (130, 195, 240)], rng)
    _post(m, 0, 0, 4, 3, mul(GREY, 1.1))
    for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
        m.plate(dx, dy, 13, 1, 1, (170, 220, 250))
    m.plate(0, 0, 13, 1, 1, (200, 235, 255))
    return m


def prop_cone():
    m = Model()
    m.plate(0, 0, 0, 3, 3, BLACK)
    m.brick(1, 1, 1, 1, 1, ORANGE)
    m.plate(1, 1, 4, 1, 1, WHITE)
    m.brick(1, 1, 5, 1, 1, ORANGE)
    return m


def prop_crates():
    m = Model()
    m.add(0, 0, 0, 2, 2, 3, (190, 190, 190), tint=True)
    m.add(2, 0, 0, 2, 2, 3, (170, 170, 170), tint=True)
    m.add(1, 0, 3, 2, 2, 3, (205, 205, 205), tint=True)
    return m


def prop_sign(lines=2):
    m = Model()
    _post(m, 1, 1, 0, 3, DKGREY)
    m.add(0, 1, 9, 3, 1, 3, (230, 230, 230), tint=True)
    for i in range(lines):
        m.plate(0 if i == 0 else 1, 0, 10, 2 if i == 0 else 1, 1, WHITE, studs=False)
    return m


def prop_duck():
    m = Model()
    m.brick(0, 0, 0, 4, 3, DKGREY)
    m.plate(0, 0, 3, 4, 3, GREY)
    m.brick(0, 1, 4, 3, 2, YELLOW)
    m.brick(2, 1, 7, 1, 1, YELLOW)
    m.plate(3, 1, 7, 1, 1, ORANGE)
    m.plate(2, 1, 10, 1, 1, YELLOW)
    m.plate(2, 0, 8, 1, 1, ORANGE)
    return m


def prop_trashcan():
    m = Model()
    m.brick(0, 0, 0, 2, 2, DKGREY)
    m.plate(0, 0, 3, 2, 2, GREY)
    m.plate(0, 0, 4, 1, 1, DKGREY)
    return m


def prop_picnic():
    m = Model()
    m.brick(0, 1, 0, 1, 2, DKGREY)
    m.brick(5, 1, 0, 1, 2, DKGREY)
    m.add(0, 1, 3, 6, 2, 1, (210, 210, 210), tint=True)
    for x in range(6):
        m.plate(x, 1, 4, 1, 2, WHITE if x % 2 == 0 else RED)
    m.plate(0, 0, 1, 6, 1, (170, 120, 80), studs=True)
    m.plate(0, 3, 1, 6, 1, (170, 120, 80), studs=True)
    return m


def prop_flagpole():
    m = Model()
    m.plate(0, 0, 0, 2, 2, DKGREY)
    for i in range(7):
        m.brick(0, 0, 1 + i * 3, 1, 1, WHITE)
    m.plate(0, 0, 22, 1, 1, YELLOW)
    m.add(1, 0, 14, 3, 1, 3, (230, 230, 230), tint=True)
    return m


def prop_pile():
    m = Model()
    m.brick(0, 1, 0, 2, 1, RED)
    m.brick(2, 0, 0, 2, 2, BLUE)
    m.brick(0, 0, 0, 1, 1, YELLOW)
    m.brick(1, 1, 3, 2, 1, GREEN)
    m.plate(2, 0, 3, 2, 1, ORANGE)
    m.brick(0, 2, 0, 1, 1, PINK)
    return m


def prop_bush(seed=2):
    rng = random.Random(seed)
    m = Model()
    fill_layer(m, set(disc(1, 0.5, 1.6)) | {(0, 0), (1, 0), (2, 0)}, 0, 3, GREENS, rng)
    fill_layer(m, disc(1, 0.4, 1.0), 3, 3, GREENS, rng)
    for x, y, c in [(0, 0, PINK), (2, 0, YELLOW), (1, 1, WHITE)]:
        m.plate(x, y, 6, 1, 1, c)
    return m


def prop_flowerbed(seed=4):
    rng = random.Random(seed)
    m = Model()
    m.plate(0, 0, 0, 5, 2, DKGREEN)
    for x in range(5):
        for y in range(2):
            if rng.random() < 0.8:
                m.plate(x, y, 1, 1, 1, rng.choice([RED, YELLOW, WHITE, PINK, LAVENDER, ORANGE]))
    return m


def prop_boat():
    m = Model()
    m.add(1, 0, 0, 3, 2, 3, (220, 220, 220), tint=True)
    m.add(0, 0, 3, 5, 2, 3, (220, 220, 220), tint=True)
    m.plate(0, 0, 6, 5, 1, WHITE)
    m.plate(0, 1, 6, 5, 1, WHITE)
    _post(m, 2, 1, 7, 4, GREY)
    m.add(3, 1, 10, 2, 1, 3, WHITE)
    m.add(3, 1, 13, 1, 1, 3, WHITE)
    m.plate(2, 1, 19, 1, 1, YELLOW)
    return m


def prop_barrel():
    m = Model()
    m.brick(0, 0, 0, 2, 2, (200, 200, 200), tint=True)
    m.plate(0, 0, 3, 2, 2, DKGREY)
    m.brick(0, 0, 4, 2, 2, (200, 200, 200), tint=True)
    return m


def prop_stall():
    m = Model()
    m.add(0, 1, 0, 1, 1, 6, BROWN)
    m.add(4, 1, 0, 1, 1, 6, BROWN)
    m.add(0, 0, 0, 5, 1, 3, (210, 210, 210), tint=True)
    for x in range(5):
        m.plate(x, 0, 6, 1, 2, RED if x % 2 == 0 else WHITE)
        m.plate(x, 0, 7, 1, 2, RED if x % 2 == 0 else WHITE)
    m.plate(0, 1, 3, 5, 1, TAN, studs=False)
    for x, c in [(1, RED), (2, YELLOW), (3, GREEN)]:
        m.plate(x, 0, 3, 1, 1, c)
    return m


def prop_slide():
    m = Model()
    for i, h in enumerate([3, 6, 9]):
        m.add(0, 0, 0, 1, 2, h, RED if i % 2 == 0 else YELLOW)
    # shift steps to read as a ladder
    m.parts = []
    m.add(0, 0, 0, 1, 3, 3, RED)
    m.add(1, 0, 0, 1, 3, 6, YELLOW)
    m.add(2, 0, 0, 1, 3, 9, RED)
    m.add(3, 0, 6, 1, 3, 1, BLUE)
    m.add(4, 0, 4, 1, 3, 1, BLUE)
    m.add(5, 0, 2, 1, 3, 1, BLUE)
    m.add(6, 0, 0, 1, 3, 1, BLUE)
    return m


def prop_seesaw():
    m = Model()
    m.brick(2, 0, 0, 1, 2, DKGREY)
    m.add(0, 0, 3, 5, 2, 1, (230, 230, 230), tint=True)
    m.brick(0, 0, 4, 1, 1, YELLOW)
    m.brick(4, 0, 4, 1, 1, YELLOW)
    return m


def prop_bollard():
    m = Model()
    m.brick(0, 0, 0, 1, 1, YELLOW)
    m.plate(0, 0, 3, 1, 1, BLACK)
    m.brick(0, 0, 4, 1, 1, YELLOW)
    return m


def prop_rock():
    m = Model()
    rng = random.Random(9)
    fill_layer(m, set(disc(1, 0.5, 1.5)) | {(0, 0), (1, 0), (2, 0)}, 0, 3, [GREY, mul(GREY, 0.9), DKGREY], rng)
    fill_layer(m, disc(1, 0.4, 0.9), 3, 3, [GREY, mul(GREY, 1.1)], rng)
    return m


PROPS = {
    # name: (builder, anchors)
    "brick_lamp": prop_lamp, "brick_bench": prop_bench, "brick_hydrant": prop_hydrant,
    "brick_mailbox": prop_mailbox, "brick_planter": prop_planter, "brick_fountain": prop_fountain,
    "brick_cone": prop_cone, "brick_crates": prop_crates, "brick_sign": prop_sign,
    "brick_duck": prop_duck, "brick_trashcan": prop_trashcan, "brick_picnic": prop_picnic,
    "brick_flagpole": prop_flagpole, "brick_pile": prop_pile, "brick_bush": prop_bush,
    "brick_flowerbed": prop_flowerbed, "brick_boat": prop_boat, "brick_barrel": prop_barrel,
    "brick_stall": prop_stall, "brick_slide": prop_slide, "brick_seesaw": prop_seesaw,
    "brick_bollard": prop_bollard, "brick_rock": prop_rock,
}


def make_prop(name):
    """(base, tint) images for a prop, in the convention the client's prop sprites use (the image's bottom
    edge is 8 px below the prop's ground point, centred on it)."""
    model = PROPS[name]()
    base = render(model, "base")
    base = with_shadow(base, model)
    tint = render(model, "tint")
    has_tint = any(p.tint for p in model.parts)
    return base, (tint if has_tint else None)


def make_tree(variant, great=False):
    """(trunk, canopy) for a tree: two layers on one canvas, bottom-anchored, so the client can draw them
    exactly like every other tree. The trunk is the bottom bricks, the canopy everything above. Bricks
    don't sway, so the world sets the tree's sway to 0."""
    model = tree_model(variant, great)
    trunk_n = 3 if great else 2
    trunk_parts = [p for p in model.parts if p.z < trunk_n * 3]
    canopy_parts = [p for p in model.parts if p.z >= trunk_n * 3]
    full = Model()
    full.parts = model.parts
    # both layers share the full model's canvas
    foot = 6
    sample = render(full, "base", foot=foot)
    w, h = sample.size
    out = []
    for parts in (trunk_parts, canopy_parts):
        sub = Model()
        sub.parts = full.parts
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        # draw ALL parts for correct occlusion order, but only keep the pixels of this layer's parts
        ordered = _order(full.parts)
        x0, x1 = full.bounds_x()
        wpx = (x1 - x0) * 8
        ox = (w - wpx) // 2 - x0 * 8
        oy = h - foot
        for p in ordered:
            if p in parts:
                _draw_part(img, p, ox, oy, 8, 2, 4, "base")
        out.append(img)
    trunk, canopy = out
    # a hard shadow under the trunk
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    _rect(sh, w // 2 - 14, h - foot - 5, w // 2 + 18, h - foot + 2, (20, 20, 40, 60))
    sh.alpha_composite(trunk)
    return sh, canopy


# ── tiles ─────────────────────────────────────────────────────────────────────────────────────────
STUD = 8   # world pixels per stud: the ground's, the roofs' and the plates' shared pitch


def _stud_role_tile(kind, seed):
    """One 128x128 baseplate tile for the ground shader: R = shade role 0..3 (stored 0/85/170/255),
    G = 255 on a flower stud (meadow). Studs on an 8 px pitch over a plate with seams every 64 px."""
    rng = random.Random(seed)
    T = 128
    R = [[1] * T for _ in range(T)]
    G = [[0] * T for _ in range(T)]
    smooth = kind == "dirt"
    for cy in range(T // STUD):
        for cx in range(T // STUD):
            x0, y0 = cx * STUD, cy * STUD
            flat = (not smooth) and rng.random() < (0.10 if kind != "sand" else 0.04)
            if smooth:
                for y in range(STUD):
                    for x in range(STUD):
                        R[y0 + y][x0 + x] = 2 if (x < STUD - 1 and y < STUD - 1) else 1
                for x in range(STUD):
                    R[y0][x0 + x] = 3 if rng.random() < 0.5 else 2
                continue
            if flat:
                for y in range(1, STUD - 1):
                    for x in range(1, STUD - 1):
                        R[y0 + y][x0 + x] = 2
                for x in range(1, STUD - 1):
                    R[y0 + 1][x0 + x] = 3
                continue
            for y in range(STUD):
                for x in range(STUD):
                    dx, dy = x - 3.5, y - 3.5
                    d2 = dx * dx + dy * dy
                    if d2 <= 7.5:
                        role = 2
                        if dx < 0 and dy < 0 and d2 > 2.0:
                            role = 3
                        if dx > 0.5 and dy > 0.5 and d2 > 4.0:
                            role = 0
                        R[y0 + y][x0 + x] = role
                        if kind == "meadow" and role == 2:
                            G[y0 + y][x0 + x] = 1 if (cx * 7 + cy * 13) % 5 == 0 else 0
                    elif d2 <= 14 and dx > 0 and dy > 0:
                        R[y0 + y][x0 + x] = 0      # the stud's drop shadow on the plate
    # seams between plates
    for i in range(T):
        for s in (0, 64):
            R[i][s] = 0
            R[s][i] = 0
            R[i][s + 1] = max(R[i][s + 1], 2) if R[i][s + 1] < 2 else R[i][s + 1]
    out = Image.new("RGBA", (T, T))
    for y in range(T):
        for x in range(T):
            out.putpixel((x, y), (R[y][x] * 85, 255 if G[y][x] else 0, 0, 255))
    return out


def terrain_atlas():
    kinds = ["grass", "lush", "meadow", "dirt", "sand"]
    atlas = Image.new("RGBA", (128 * len(kinds), 128))
    for i, k in enumerate(kinds):
        atlas.paste(_stud_role_tile(k, 11 + i), (i * 128, 0))
    return atlas


def stud_tile(size=32, base=0.80, flat=False):
    """A greyscale stud plate tile (tinted by the client with each plate's colour). Seamless at `size`."""
    img = Image.new("RGBA", (size, size))
    def g(v):
        v = max(0, min(255, int(255 * v)))
        return (v, v, v, 255)
    for y in range(size):
        for x in range(size):
            img.putpixel((x, y), g(base))
    if flat:
        for i in range(size):
            for s in (0, size // 2):
                img.putpixel((i, s), g(0.62))
                img.putpixel((s, i), g(0.62))
                img.putpixel((i, (s + 1) % size), g(0.9))
                img.putpixel(((s + 1) % size, i), g(0.9))
        return img
    for cy in range(size // STUD):
        for cx in range(size // STUD):
            for y in range(STUD):
                for x in range(STUD):
                    dx, dy = x - 3.5, y - 3.5
                    d2 = dx * dx + dy * dy
                    if d2 <= 7.5:
                        v = 1.0
                        if dx < 0 and dy < 0 and d2 > 2.0:
                            v = 1.22
                        if dx > 0.5 and dy > 0.5 and d2 > 4.0:
                            v = 0.82
                        img.putpixel((cx * STUD + x, cy * STUD + y), g(v * 0.97))
                    elif d2 <= 14 and dx > 0 and dy > 0:
                        img.putpixel((cx * STUD + x, cy * STUD + y), g(0.62))
    return img


def wall_tile():
    """Brick courses for a building's front: 16 x 6 px bricks in running bond, with a joint and a lit top
    edge, and each brick a hair lighter or darker than its neighbours. 32 x 24 px, seamless."""
    rng = random.Random(21)
    img = Image.new("RGBA", (32, 24))
    for course in range(4):
        off = 8 if course % 2 else 0
        for bx in range(-1, 3):
            x0 = bx * 16 + off
            v = 0.93 + rng.uniform(-0.05, 0.05)
            for y in range(6):
                for x in range(16):
                    px, py = x0 + x, course * 6 + y
                    if not (0 <= px < 32):
                        continue
                    val = v
                    if y == 5 or x == 15:
                        val = v * 0.74
                    elif y == 0 or x == 0:
                        val = min(1.0, v * 1.12)
                    elif y in (2, 3) and x in (3, 4, 5, 10, 11, 12) and False:
                        val = v
                    c = max(0, min(255, int(255 * val)))
                    img.putpixel((px, py), (c, c, c, 255))
        # studs peeking along the top of each course would be hidden: keep the face clean
    return img


def roof_slope_tile():
    """A pitched roof seen from the front: rows of 8 px bricks stepping a half-brick each row, each row a
    lit lip then a shadow. 32 x 24, seamless."""
    img = Image.new("RGBA", (32, 24))
    rng = random.Random(33)
    for row in range(4):
        off = 4 if row % 2 else 0
        for bx in range(-1, 5):
            x0 = bx * 8 + off
            v = 0.92 + rng.uniform(-0.05, 0.05)
            for y in range(6):
                for x in range(8):
                    px, py = x0 + x, row * 6 + y
                    if not (0 <= px < 32):
                        continue
                    val = v
                    if y == 5 or x == 7:
                        val = v * 0.7
                    elif y == 0:
                        val = min(1.0, v * 1.2)
                    c = max(0, min(255, int(255 * val)))
                    img.putpixel((px, py), (c, c, c, 255))
    return img


def road_tile():
    """A smooth plate for roads: 32 x 32 grey with a fine joint every 32 px and a few specks of wear."""
    img = Image.new("RGBA", (32, 32), (214, 214, 214, 255))
    rng = random.Random(4)
    for _ in range(14):
        x, y = rng.randrange(32), rng.randrange(32)
        c = rng.choice([200, 224])
        img.putpixel((x, y), (c, c, c, 255))
    for i in range(32):
        img.putpixel((i, 0), (170, 170, 170, 255))
        img.putpixel((0, i), (170, 170, 170, 255))
        img.putpixel((i, 1), (236, 236, 236, 255))
        img.putpixel((1, i), (236, 236, 236, 255))
    return img


def rainbow_brick():
    """The secret: one 2x1 brick, striped in every colour. 20 x 14, drawn into a wall at its own size."""
    m = Model()
    img = Image.new("RGBA", (20, 14), (0, 0, 0, 0))
    # front face 16 x 6 of vertical-ish diagonal stripes, top with two studs
    for y in range(6):
        for x in range(16):
            c = RAINBOW[((x + y) // 3) % len(RAINBOW)]
            if y == 5 or x == 15:
                c = mul(c, 0.78)
            elif x == 0 or y == 0:
                c = mul(c, 1.12)
            img.putpixel((2 + x, 7 + y), c + (255,))
    for y in range(4):
        for x in range(16):
            c = mul(RAINBOW[((x + 2) // 3) % len(RAINBOW)], 1.18)
            img.putpixel((2 + x, 3 + y), c + (255,))
    for sx in (4, 12):
        for y in range(2):
            for x in range(4):
                c = mul(RAINBOW[((sx + x) // 3) % len(RAINBOW)], 1.32)
                img.putpixel((sx + x, 1 + y), c + (255,))
        for x in range(4):
            img.putpixel((sx + x, 3), mul(RAINBOW[((sx + x) // 3) % len(RAINBOW)], 0.8) + (255,))
    return img


# loose bricks on the ground: half-scale pieces scattered as litter
LOOSE = {
    "lb_red_2x1": ((2, 1), RED, 3), "lb_blue_2x2": ((2, 2), BLUE, 3), "lb_yellow_1x1": ((1, 1), YELLOW, 3),
    "lb_green_2x1": ((2, 1), GREEN, 3), "lb_white_4x1": ((4, 1), WHITE, 3), "lb_orange_2x2": ((2, 2), ORANGE, 3),
    "lb_pink_1x1": ((1, 1), PINK, 3), "lb_lime_plate": ((2, 2), LIME, 1), "lb_teal_2x1": ((2, 1), TEAL, 3),
    "lb_red_plate": ((2, 1), RED, 1), "lb_blue_1x1": ((1, 1), BLUE, 3), "lb_yellow_2x1": ((2, 1), YELLOW, 3),
}


def detail_atlas():
    """The litter atlas + its index {name: [x, y, w, h]} (the same shape data/ground_details.json uses)."""
    sprites = []
    for name, ((nx, ny), c, ph) in LOOSE.items():
        m = Model()
        m.add(0, 0, 0, nx, ny, ph, c)
        img = render(m, "base", W=4, PL=1, D=2, pad=1, foot=1)
        sprites.append((name, img))
    # a few little heaps: two or three pieces together
    for i, (cols) in enumerate([(RED, YELLOW, BLUE), (GREEN, WHITE), (ORANGE, PINK, LIME)]):
        m = Model()
        m.add(0, 1, 0, 2, 1, 3, cols[0])
        m.add(2, 0, 0, 1, 2, 3, cols[1])
        if len(cols) > 2:
            m.add(0, 0, 3, 1, 1, 3, cols[2])
        sprites.append(("lb_heap_%d" % i, render(m, "base", W=4, PL=1, D=2, pad=1, foot=1)))
    width = sum(s.width + 1 for _, s in sprites)
    height = max(s.height for _, s in sprites)
    atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    index, x = {}, 0
    for name, s in sprites:
        atlas.paste(s, (x, 0))
        index[name] = [x, 0, s.width, s.height]
        x += s.width + 1
    return atlas, index
