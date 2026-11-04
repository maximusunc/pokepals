"""
Pixel-art portals: the small MOSSY STONE RING that stands in every world as its way home, and the
Vale's GRAND CARVED ARCH, the Gateway to every world. Same hand-crafted pixel language as trees.py /
props.py: a warm near-black outline, stone lit from the top-left in chunky dithered steps, moss and
vines in the shared leaf greens.

Each portal bakes as three layers on ONE canvas, so they line up by construction (the client draws
all three at the same anchor):

  * FRAME  (full colour) -- the stonework, moss, vines and steps. Never tinted.
  * SWIRL  (grayscale, a sheet of FRAMES frames side by side) -- the energy filling the opening, a
    spiral that turns one arm-period over the sheet so it loops seamlessly. GRAYSCALE because every
    portal carries its own colour (data): the client tints it per-portal with `modulate`, so a
    value-v pixel becomes v * colour. Drawn UNDER the frame, so the stone's inner edge tidies it.
  * RUNES  (white mask) -- the carved runes, plus a faint bleed around each, which the client draws
    over the frame in the portal's colour with a breathing alpha: the runes glow.

The breathing, the rising motes and (for the Gateway) the slow drift through the hues stay
procedural in the client (PortalView), like the trees' sway. No randomness: a tiny integer hash
stands in for noise, so every bake is identical.
"""

import math

from PIL import Image

OUTLINE = (28, 24, 22, 255)

# Stone: a weathered grey, a hair warm. Five values, dark -> light, quantized with the dither.
STONE = [(0.30, 0.30, 0.29), (0.40, 0.40, 0.38), (0.50, 0.50, 0.47), (0.61, 0.61, 0.57), (0.73, 0.72, 0.67)]
# A paler, sun-bleached stone for the Gateway (it's a monument; it should read from afar).
STONE_PALE = [(0.36, 0.35, 0.34), (0.47, 0.46, 0.43), (0.58, 0.57, 0.53), (0.69, 0.68, 0.63), (0.81, 0.80, 0.74)]
MORTAR = (0.22, 0.21, 0.20)
CARVE = (0.20, 0.19, 0.19)  # a rune's carved groove in the stone (the glow sits on top of it)
# Moss and leaves: the shared leaf greens (props.py LEAF), plus a dark and a sunlit tip.
MOSS = [(0.17, 0.30, 0.19), (0.24, 0.40, 0.26), (0.36, 0.54, 0.34), (0.52, 0.68, 0.42)]
VINE_STEM = (0.30, 0.34, 0.20)
BLOSSOM = [(0.95, 0.78, 0.86), (1.0, 0.93, 0.95)]
BLOSSOM_EYE = (0.98, 0.86, 0.45)
FLOWER_CREAM = (0.98, 0.95, 0.80)

# 4x4 Bayer matrix (normalised to [0,1)) -- the classic ordered-dither threshold pattern.
_BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
BAYER = [[v / 16.0 for v in row] for row in _BAYER]

# How many frames the swirl sheets hold (the client reads this from data/art.json too).
FRAMES = 8

# Little carved glyphs (3 wide x 5 tall), original shapes: a branch, an eye, a door, a seed, a wave,
# a star, a hook. "#" is carved.
GLYPHS = [
    ["#.#", ".#.", ".#.", "#.#", ".#."],
    [".#.", "#.#", "#.#", ".#.", ".#."],
    ["###", "#.#", "#.#", "#.#", "#.#"],
    [".#.", "#.#", ".#.", ".#.", "#.#"],
    ["#..", ".#.", "#..", ".#.", "#.."],
    [".#.", "###", ".#.", "#.#", "..."],
    ["##.", "..#", ".#.", "#..", "##."],
]


def _rgba(rgb, a=255):
    return (round(rgb[0] * 255), round(rgb[1] * 255), round(rgb[2] * 255), a)


def _h(x, y, salt=0):
    """A tiny deterministic hash -> [0, 1). Stands in for noise without any randomness."""
    n = (x * 374761393 + y * 668265263 + salt * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65536.0


def _dither_level(value, x, y, n, amount=1.0):
    """Ordered-dither `value` (0..1) onto n chunky levels; returns the level index. `amount` < 1
    narrows the stipple to just the band edges."""
    nudged = value * (n - 1) + (BAYER[y % 4][x % 4] - 0.5) * amount
    return max(0, min(n - 1, int(round(nudged))))


class Canvas:
    """One portal's three aligned layers: frame (colour), runes (white mask), and a hole mask."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.runes = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.fp = self.frame.load()
        self.rp = self.runes.load()
        self.hole = set()  # the opening's pixels (where the swirl shows); outlined from inside too

    def put(self, x, y, rgb, a=255):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.fp[x, y] = _rgba(rgb, a) if len(rgb) == 3 else rgb

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.fp[x, y]
        return (0, 0, 0, 0)

    def solid(self, x, y):
        return self.get(x, y)[3] > 0

    def rune_px(self, x, y):
        """Carve one rune pixel: a groove in the stone, and full white in the glow mask."""
        if not self.solid(x, y):
            return
        self.put(x, y, CARVE)
        self.rp[x, y] = (255, 255, 255, 255)

    def glyph(self, gx, gy, idx):
        g = GLYPHS[idx % len(GLYPHS)]
        for j, row in enumerate(g):
            for i, ch in enumerate(row):
                if ch == "#":
                    self.rune_px(gx + i, gy + j)

    def rune_bleed(self):
        """A faint halo around every rune pixel in the glow mask, so the light spills a little."""
        src = self.runes.copy().load()
        for y in range(self.h):
            for x in range(self.w):
                if src[x, y][3]:
                    continue
                near = sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                           if 0 <= x + dx < self.w and 0 <= y + dy < self.h and src[x + dx, y + dy][3] == 255)
                if near and self.solid(x, y):
                    self.rp[x, y] = (255, 255, 255, 70 + 25 * near)

    def outline(self):
        """A 1-px warm-dark outline round the silhouette, and round the opening from inside."""
        src = self.frame.copy().load()
        for y in range(self.h):
            for x in range(self.w):
                if src[x, y][3]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and src[nx, ny][3] == 255:
                        if src[nx, ny] != OUTLINE:
                            self.fp[x, y] = OUTLINE
                        break


def _lambert(nx, ny, nz):
    """Light from the top-left, a little in front: the house lighting."""
    lx, ly, lz = -0.55, -0.65, 0.52
    ln = math.sqrt(lx * lx + ly * ly + lz * lz)
    nn = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return max(0.0, (nx * lx + ny * ly + nz * lz) / (nn * ln))


def _moss_px(c, x, y, depth):
    """A moss pixel: darker deeper in, a sunlit tip on the outermost (depth 0) top-left pixels."""
    if depth <= 0:
        tone = 3 if _h(x, y, 7) < 0.55 else 2
    elif depth == 1:
        tone = 2 if _h(x, y, 8) < 0.6 else 1
    else:
        tone = 1 if _h(x, y, 9) < 0.5 else 0
    c.put(x, y, MOSS[tone])


# ============================================================================ the small stone ring

RING_W, RING_H = 46, 64
RING_ANCHOR_Y = 57           # the canvas row that sits on the world point (the ring's foot)
RING_C = (23.0, 31.0)        # the ring's centre
RING_OUT = (19.5, 26.0)      # outer radii (x, y)
RING_IN = (11.5, 18.5)       # inner radii: the opening
RING_STONES = 12
RING_RUNE_STONES = (0, 3, 9)  # keystone + one each side carry a carved rune


def _ring_geom(x, y):
    """(is_stone, is_hole, theta, u, seg, arc_d) for canvas pixel (x, y)."""
    cx, cy = RING_C
    dx, dy = x + 0.5 - cx, y + 0.5 - cy
    theta = math.atan2(dy / RING_OUT[1], dx / RING_OUT[0])
    # which stone: the keystone (seg 0) is centred at the very top
    step = 2 * math.pi / RING_STONES
    rel = (theta + math.pi / 2 + step / 2) % (2 * math.pi)
    seg = int(rel // step)
    # the keystone stands a little proud of the ring
    ro = RING_OUT if seg != 0 else (RING_OUT[0] + 1.0, RING_OUT[1] + 1.5)
    e_out = math.hypot(dx / ro[0], dy / ro[1])
    e_in = math.hypot(dx / RING_IN[0], dy / RING_IN[1])
    is_hole = e_in < 1.0
    is_stone = e_out <= 1.0 and not is_hole
    # u: 0 at the inner edge .. 1 at the outer, along this ray
    r_in = 1.0 / max(1e-6, math.hypot(math.cos(theta) * RING_OUT[0] / RING_IN[0], math.sin(theta) * RING_OUT[1] / RING_IN[1]))
    r_now = math.hypot(dx / ro[0], dy / ro[1]) * (RING_OUT[0] if seg else ro[0]) / (RING_OUT[0] if seg else ro[0])
    u = (math.hypot(dx / ro[0], dy / ro[1]) - r_in) / max(1e-6, 1.0 - r_in)
    # arc distance (in px) to the nearest joint between stones
    off = rel - (seg + 0.5) * step
    arc_d = (step / 2 - abs(off)) * math.hypot(dx, dy)
    return is_stone, is_hole, theta, max(0.0, min(1.0, u)), seg, arc_d, off


def _ring_stone_color(c, x, y, theta, u, seg, arc_d, off):
    # the stone is a rounded voussoir: its outer half faces outward, its inner half inward
    rx, ry = math.cos(theta), math.sin(theta)
    bulge = (u - 0.5) * 1.6
    shade = _lambert(rx * bulge, ry * bulge, 1.0)
    # each stone its own weathering
    shade += (_h(seg, 1, 3) - 0.5) * 0.18
    # bevelled joints: the edge facing the light catches it, the other falls into shadow
    if arc_d < 1.6:
        tang = (-ry, rx) if off > 0 else (ry, -rx)
        shade += 0.22 if (tang[0] * -0.55 + tang[1] * -0.65) > 0 else -0.22
    lvl = _dither_level(min(1.0, max(0.0, shade * 1.05 - 0.08)), x, y, len(STONE))
    rgb = STONE[lvl]
    # speckle: a few lichen-pale and pitted pixels
    n = _h(x, y, 11)
    if n < 0.04:
        rgb = STONE[min(len(STONE) - 1, lvl + 1)]
    elif n > 0.965:
        rgb = STONE[max(0, lvl - 1)]
    return rgb


def make_ring():
    """The small portal: (frame, runes) RGBA images, RING_W x RING_H."""
    c = Canvas(RING_W, RING_H)
    cx, cy = RING_C

    # chock stones either side of the foot, half sunk in the ground, so the ring stands
    for sx in (-1, 1):
        bx, by = cx + sx * 14.0, 55.0
        for y in range(48, 60):
            for x in range(RING_W):
                ddx, ddy = (x + 0.5 - bx) / 4.5, (y + 0.5 - by) / 3.2
                if ddx * ddx + ddy * ddy <= 1.0 and y <= 57:
                    s = _lambert(ddx, ddy * 1.4, 0.9)
                    c.put(x, y, STONE[_dither_level(s * 0.9, x, y, len(STONE))])

    # the ring of voussoirs
    for y in range(RING_H):
        for x in range(RING_W):
            is_stone, is_hole, theta, u, seg, arc_d, off = _ring_geom(x, y)
            if is_hole:
                c.hole.add((x, y))
            if not is_stone:
                continue
            if arc_d < 0.55:
                c.put(x, y, MORTAR)
                continue
            c.put(x, y, _ring_stone_color(c, x, y, theta, u, seg, arc_d, off))

    # a shadowed lip just inside the opening: the ring has depth
    for (x, y) in list(c.hole):
        _, _, theta, _, _, _, _ = _ring_geom(x, y)
        e = math.hypot((x + 0.5 - cx) / RING_IN[0], (y + 0.5 - cy) / RING_IN[1])
        # the lip shows on the lower-right of the hole (the side turned from the light)
        if e > 0.86 and math.sin(theta) * 0.6 + math.cos(theta) * 0.5 > 0.15:
            c.put(x, y, STONE[0])

    # moss draped over the sunlit upper-left of the ring: thickest there, thinning away round the
    # crown, with an uneven edge and a couple of drips spilling down the outer face
    ring_px = (RING_OUT[0] - RING_IN[0] + RING_OUT[1] - RING_IN[1]) / 2.0
    drips = {-2.2: 3.0, -1.55: 2.0}  # angle -> extra reach
    for y in range(RING_H):
        for x in range(RING_W):
            is_stone, _, theta, u, seg, _, _ = _ring_geom(x, y)
            if not is_stone or y > cy:
                continue
            depth = (1.0 - u) * ring_px  # px in from the outer face
            lean = math.cos(theta - (-2.0))  # 1 at the upper-left
            reach = 3.6 * max(0.0, lean) ** 1.3 + 1.4 * _h(x // 2, y // 2, 21) - 0.7
            for da, extra in drips.items():
                if abs(theta - da) < 0.09:
                    reach += extra
            if depth < reach:
                _moss_px(c, x, y, int(depth))
    # a few tufts standing up off the moss, and tiny cream flowers in it
    for x in range(RING_W):
        col = [y for y in range(RING_H) if c.solid(x, y)]
        if not col or c.get(x, col[0])[:3] not in [_rgba(m)[:3] for m in MOSS]:
            continue
        if _h(x, 4, 22) < 0.22:
            c.put(x, col[0] - 1, MOSS[2])
    for fx in (cx - 12, cx - 4):
        x = int(fx)
        col = [y for y in range(RING_H) if c.solid(x, y)]
        if col:
            c.put(x, col[0] + 1, FLOWER_CREAM)
    # one short strand of moss hanging into the opening
    x = int(cx - 4)
    ys = [y for y in range(RING_H) if (x, y) in c.hole]
    if ys:
        for k in range(3):
            c.put(x, ys[0] + k, MOSS[1] if k < 2 else MOSS[2])
            c.hole.discard((x, ys[0] + k))

    # grass at the foot
    for x in range(4, RING_W - 4):
        if _h(x, 9, 31) < 0.5 and abs(x + 0.5 - cx) > 4:
            hgt = 1 + int(_h(x, 9, 32) * 3)
            for k in range(hgt):
                y = RING_ANCHOR_Y - k
                if not c.solid(x, y) or k == 0:
                    c.put(x, y, MOSS[2] if k == hgt - 1 else MOSS[1])

    c.outline()

    # runes on three stones, carved after the outline so they sit in the stone
    for seg in RING_RUNE_STONES:
        step = 2 * math.pi / RING_STONES
        theta = seg * step - math.pi / 2
        mid_x = (RING_OUT[0] + RING_IN[0]) / 2.0 + (1.0 if seg == 0 else 0.0)
        mid_y = (RING_OUT[1] + RING_IN[1]) / 2.0 + (1.2 if seg == 0 else 0.0)
        gx = int(round(cx + math.cos(theta) * mid_x - 1.5))
        gy = int(round(cy + math.sin(theta) * mid_y - 2.5))
        c.glyph(gx, gy, seg)
    c.rune_bleed()
    return c


def ring_swirl_mask(c):
    """Where the small ring's energy shows: the opening, grown by a pixel to tuck under the stone."""
    return _grow(c.hole, 1, RING_W, RING_H)


# ============================================================================ the grand carved arch

ARCH_W, ARCH_H = 110, 136
ARCH_ANCHOR_Y = 122          # the canvas row on the world point (the top step's front edge)
ARCH_CX = 55.0
ARCH_SPRING = 62             # the row where the arch springs from the pillars
ARCH_IN = 24.0               # inner radius of the arch (half the opening)
ARCH_OUT = 42.0              # outer radius
ARCH_STONES = 9
PILLAR_W = 18
PILLAR_TOP = ARCH_SPRING
PILLAR_BOTTOM = 114          # the pillars stand on their plinths here
REVEAL = 3                   # the depth of the opening, seen on its inner faces


def _arch_regions():
    """Masks (sets of pixels) for each part of the Gateway, so we can paint them in order."""
    left_x0 = int(ARCH_CX - ARCH_OUT)
    right_x1 = int(ARCH_CX + ARCH_OUT)
    in_l = int(ARCH_CX - ARCH_IN)
    in_r = int(ARCH_CX + ARCH_IN)
    voussoir, keystone, pillar_l, pillar_r, opening, reveal = set(), set(), set(), set(), set(), set()
    for y in range(ARCH_H):
        for x in range(ARCH_W):
            dx, dy = x + 0.5 - ARCH_CX, y + 0.5 - ARCH_SPRING
            r = math.hypot(dx, dy)
            if dy <= 0:
                ang = math.atan2(-dy, dx)  # 0 right .. pi left, pi/2 at the top
                key = abs(ang - math.pi / 2) < (math.pi / ARCH_STONES) / 2
                rout = ARCH_OUT + (3.5 if key else 0.0)
                if r < ARCH_IN:
                    opening.add((x, y))
                    if r >= ARCH_IN - REVEAL:
                        reveal.add((x, y))
                elif r <= rout:
                    (keystone if key else voussoir).add((x, y))
            elif y < PILLAR_BOTTOM:
                if left_x0 <= x < left_x0 + PILLAR_W:
                    pillar_l.add((x, y))
                elif right_x1 - PILLAR_W <= x < right_x1:
                    pillar_r.add((x, y))
                elif in_l <= x < in_r:
                    opening.add((x, y))
                    if x < in_l + REVEAL or x >= in_r - REVEAL:
                        reveal.add((x, y))
    return voussoir, keystone, pillar_l, pillar_r, opening, reveal


def _block_shade(c, x, y, x0, x1, y0, y1, pal, salt):
    """A dressed stone block, face-on: lit top and left edges, shadowed bottom and right."""
    t = 0.55 + (_h(salt, 2, 40) - 0.5) * 0.2
    if y == y0:
        t += 0.32
    elif y == y1:
        t -= 0.36
    if x == x0:
        t += 0.18
    elif x == x1:
        t -= 0.22
    # weathering: a gentle top-to-bottom fall and a few pits
    t -= (y - y0) / max(1, (y1 - y0)) * 0.08
    n = _h(x, y, salt + 41)
    if n < 0.05:
        t -= 0.18
    elif n > 0.96:
        t += 0.14
    return pal[_dither_level(max(0.0, min(1.0, t)), x, y, len(pal))]


def make_arch():
    """The Gateway: (canvas, opening mask). Canvas carries the frame + rune layers."""
    c = Canvas(ARCH_W, ARCH_H)
    pal = STONE_PALE
    voussoir, keystone, pillar_l, pillar_r, opening, reveal = _arch_regions()
    left_x0 = int(ARCH_CX - ARCH_OUT)
    right_x1 = int(ARCH_CX + ARCH_OUT)

    # -- the steps up to it: two broad, shallow treads in front of the opening
    for (y0, y1, half) in ((ARCH_ANCHOR_Y - 8, ARCH_ANCHOR_Y - 3, 36), (ARCH_ANCHOR_Y - 3, ARCH_ANCHOR_Y + 3, 44),
                           (ARCH_ANCHOR_Y + 3, ARCH_ANCHOR_Y + 9, 51)):
        x0, x1 = int(ARCH_CX - half), int(ARCH_CX + half) - 1
        for y in range(y0, y1):
            for x in range(x0, x1 + 1):
                if y - y0 < 2:
                    t = 0.82  # the tread, catching the light
                elif y == y1 - 1:
                    t = 0.18
                else:
                    t = 0.48
                if x == x0:
                    t += 0.08
                if x == x1:
                    t -= 0.16
                # joints between the step stones
                if (x - x0 + (y0 * 3)) % 15 == 0 and y - y0 >= 2:
                    c.put(x, y, MORTAR)
                    continue
                if _h(x, y, 50) < 0.06:
                    t -= 0.15
                c.put(x, y, pal[_dither_level(max(0.0, min(1.0, t)), x, y, len(pal))])

    # -- plinths under each pillar, a little wider than the pillar
    for px0 in (left_x0, right_x1 - PILLAR_W):
        x0, x1, y0, y1 = px0 - 3, px0 + PILLAR_W + 2, PILLAR_BOTTOM, ARCH_ANCHOR_Y - 8
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                c.put(x, y, _block_shade(c, x, y, x0, x1, y0, y1, pal, px0 + 3))

    # -- the pillars: coursed blocks with staggered joints
    course = 9
    for region, px0 in ((pillar_l, left_x0), (pillar_r, right_x1 - PILLAR_W)):
        for (x, y) in region:
            k = (y - PILLAR_TOP) // course
            y0 = PILLAR_TOP + k * course
            y1 = min(PILLAR_BOTTOM - 1, y0 + course - 1)
            split = px0 + (PILLAR_W // 2 if k % 2 else 0)
            if y == y1 or (k % 2 and x == split):
                c.put(x, y, MORTAR)
                continue
            if k % 2:
                bx0, bx1 = (px0, split - 1) if x < split else (split + 1, px0 + PILLAR_W - 1)
            else:
                bx0, bx1 = px0, px0 + PILLAR_W - 1
            c.put(x, y, _block_shade(c, x, y, bx0, bx1, y0, y1 - 1, pal, k * 7 + px0))

    # -- the capitals (impost blocks) where the arch springs: a moulded band, wider than the pillar
    for px0 in (left_x0, right_x1 - PILLAR_W):
        x0, x1, y0, y1 = px0 - 2, px0 + PILLAR_W + 1, ARCH_SPRING - 1, ARCH_SPRING + 5
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                t = 0.86 if y <= y0 + 1 else (0.3 if y == y1 else 0.56)
                if y == y0 + 3:
                    t = 0.22  # the moulding's groove
                c.put(x, y, pal[_dither_level(t, x, y, len(pal))])

    # -- the voussoirs of the arch, and the proud keystone
    step = math.pi / ARCH_STONES
    for (x, y) in voussoir | keystone:
        dx, dy = x + 0.5 - ARCH_CX, y + 0.5 - ARCH_SPRING
        ang = math.atan2(-dy, dx)
        seg = min(ARCH_STONES - 1, int(ang // step))
        off = ang - (seg + 0.5) * step
        r = math.hypot(dx, dy)
        arc_d = (step / 2 - abs(off)) * r
        if arc_d < 0.55 and (x, y) not in keystone:
            c.put(x, y, MORTAR)
            continue
        u = (r - ARCH_IN) / (ARCH_OUT - ARCH_IN)
        nx, ny = math.cos(ang), -math.sin(ang)
        bulge = (u - 0.5) * 1.2
        t = _lambert(nx * bulge, ny * bulge, 1.0) * 1.05 - 0.05 + (_h(seg, 4, 43) - 0.5) * 0.14
        if arc_d < 1.6:
            t += 0.2 if off < 0 else -0.2  # bevels: the right-hand joint face catches the light
        if (x, y) in keystone:
            t += 0.08
        if _h(x, y, 44) < 0.04:
            t -= 0.18
        c.put(x, y, pal[_dither_level(max(0.0, min(1.0, t)), x, y, len(pal))])
    # the keystone's own outline-ish groove where it meets its neighbours
    for (x, y) in keystone:
        for ddx in (-1, 1):
            if (x + ddx, y) in voussoir:
                c.put(x, y, MORTAR)

    # -- the reveal: the opening's inner faces, in shadow on the left and up top, lit on the right
    for (x, y) in reveal:
        dx, dy = x + 0.5 - ARCH_CX, y + 0.5 - ARCH_SPRING
        if dy <= 0:
            t = 0.16 if dx < 6 else 0.34
        else:
            t = 0.14 if dx < 0 else 0.5
        c.put(x, y, pal[_dither_level(t, x, y, len(pal))])
    hole = opening - reveal
    c.hole = set(hole)

    # -- moss on the arch's back and the tops of the capitals and plinths
    for x in range(ARCH_W):
        col = [y for y in range(ARCH_H) if c.solid(x, y)]
        if not col:
            continue
        top = col[0]
        if top < ARCH_SPRING:  # the arch's crown
            dxn = (x + 0.5 - ARCH_CX) / ARCH_OUT
            thick = int(2.4 * (1.0 - abs(dxn + 0.2)) + 1.5 * _h(x, 6, 45))
            for d in range(max(0, thick)):
                _moss_px(c, x, top + d, d)
            if _h(x, 7, 46) < 0.3 and thick > 1:
                c.put(x, top - 1, MOSS[2])
    for px0 in (left_x0, right_x1 - PILLAR_W):
        for x in range(px0 - 2, px0 + PILLAR_W + 2):
            if _h(x, 8, 47) < 0.55:
                c.put(x, ARCH_SPRING - 1, MOSS[2] if _h(x, 9, 48) < 0.5 else MOSS[1])
        for x in range(px0 - 3, px0 + PILLAR_W + 3):
            if _h(x, 10, 49) < 0.45:
                c.put(x, PILLAR_BOTTOM, MOSS[2] if _h(x, 11, 50) < 0.5 else MOSS[1])

    # -- the vine: up the left pillar from its plinth, over the shoulder of the arch toward the crown
    vine = []
    for y in range(PILLAR_BOTTOM + 2, ARCH_SPRING, -1):
        x = left_x0 + 4 + 3.2 * math.sin(y / 6.0) + 1.5 * math.sin(y / 2.7)
        vine.append((int(round(x)), y))
    for i in range(0, 62):
        ang = math.pi - i * (math.pi * 0.42) / 62.0
        r = ARCH_OUT - 3 + 2.2 * math.sin(i / 5.0)
        vine.append((int(round(ARCH_CX + math.cos(ang) * r)), int(round(ARCH_SPRING - math.sin(ang) * r))))
    for (x, y) in vine:
        c.put(x, y, VINE_STEM)
    # leaves along it, alternating sides, and blossoms every so often
    for i in range(0, len(vine), 4):
        x, y = vine[i]
        side = 1 if (i // 4) % 2 else -1
        for (lx, ly, tone) in ((side, 0, 1), (side * 2, 0, 2), (side, -1, 2), (side * 2, -1, 3), (side * 3, -1, 1)):
            c.put(x + lx, y + ly, MOSS[tone])
        if (i // 4) % 5 == 2:
            for (bx, by) in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                c.put(x - side * 2 + bx, y - 1 + by, BLOSSOM[(i // 4) % 2])
            c.put(x - side * 2, y - 1, BLOSSOM_EYE)
    # a little ivy at the foot of the right pillar too
    rx0 = right_x1 - PILLAR_W
    for k in range(14):
        x = rx0 + PILLAR_W - 3 - int(2 * math.sin(k / 2.0))
        y = PILLAR_BOTTOM + 1 - k
        c.put(x, y, VINE_STEM)
        if k % 3 == 0:
            c.put(x + 1, y, MOSS[2])
            c.put(x + 2, y, MOSS[1])
            c.put(x - 1, y - 1, MOSS[3])

    # -- tall grass tufts at the foot of the plinths
    for x in list(range(left_x0 - 6, left_x0 + PILLAR_W + 4)) + list(range(rx0 - 4, right_x1 + 6)):
        if _h(x, 12, 51) < 0.45:
            hgt = 2 + int(_h(x, 13, 52) * 4)
            for k in range(hgt):
                y = ARCH_ANCHOR_Y - 8 - k + 1
                c.put(x, y, MOSS[2] if k >= hgt - 2 else MOSS[1])

    c.outline()

    # -- runes: one on each voussoir, the keystone's larger, and a column down each pillar's face
    for seg in range(ARCH_STONES):
        ang = (seg + 0.5) * step
        rmid = (ARCH_IN + ARCH_OUT) / 2.0 + (1.5 if seg == ARCH_STONES // 2 else 0.0)
        gx = int(round(ARCH_CX + math.cos(ang) * rmid - 1.5))
        gy = int(round(ARCH_SPRING - math.sin(ang) * rmid - 2.5))
        c.glyph(gx, gy, seg)
    for px0, salt in ((left_x0, 2), (right_x1 - PILLAR_W, 5)):
        for k in range(5):
            gy = PILLAR_TOP + 9 + k * 9 + 2
            c.glyph(px0 + PILLAR_W // 2 - 1 - (0 if k % 2 == 0 else 0), gy, salt + k)
    c.rune_bleed()
    return c


def arch_swirl_mask(c):
    return _grow(c.hole, 1, ARCH_W, ARCH_H)


# ============================================================================ the swirl

def _grow(pixels, n, w, h):
    out = set(pixels)
    for _ in range(n):
        nxt = set(out)
        for (x, y) in out:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= x + dx < w and 0 <= y + dy < h:
                    nxt.add((x + dx, y + dy))
        out = nxt
    return out


LEVELS = [0.24, 0.42, 0.62, 0.82, 1.0]


def _smooth(a, b, v):
    t = max(0.0, min(1.0, (v - a) / (b - a)))
    return t * t * (3 - 2 * t)


def make_swirl_sheet(mask, w, h, center, radii, arms, twist):
    """A FRAMES-wide sheet of grayscale swirl frames over `mask`. One arm-period of rotation across the
    sheet, so frame FRAMES wraps seamlessly to frame 0. Bold arms winding in to a bright heart, a dark
    rim, banded into a few chunky values (dithered only where two bands meet)."""
    sheet = Image.new("RGBA", (w * FRAMES, h), (0, 0, 0, 0))
    px = sheet.load()
    cx, cy = center
    for f in range(FRAMES):
        phase = 2 * math.pi * f / FRAMES
        for (x, y) in mask:
            dx, dy = (x + 0.5 - cx) / radii[0], (y + 0.5 - cy) / radii[1]
            r = min(1.3, math.hypot(dx, dy))
            th = math.atan2(dy, dx)
            # the arms: a logarithmic-ish wind (tighter toward the heart), sharpened into bands
            wind = arms * th + twist * math.sqrt(r) - phase
            arm = _smooth(0.15, 0.85, 0.5 + 0.5 * math.cos(wind))
            heart = _smooth(0.55, 0.0, r)
            v = 0.18 + 0.52 * arm * (0.35 + 0.65 * min(1.0, r * 1.8)) + 0.55 * heart - 0.22 * _smooth(0.75, 1.1, r)
            if r < 0.12:
                v = 1.0
            lvl = _dither_level(max(0.0, min(1.0, v)), x, y, len(LEVELS), 0.7)
            g = round(LEVELS[lvl] * 255)
            px[f * w + x, y] = (g, g, g, 255)
    return sheet


def make_ring_swirl(c):
    cx, cy = RING_C
    return make_swirl_sheet(ring_swirl_mask(c), RING_W, RING_H, (cx, cy + 1.0), (RING_IN[0] + 1, RING_IN[1] + 1), 2, 7.5)


def make_arch_swirl(c):
    return make_swirl_sheet(arch_swirl_mask(c), ARCH_W, ARCH_H, (ARCH_CX, ARCH_SPRING + 12.0), (ARCH_IN + 2, 46.0), 3, 9.0)


# ============================================================================ previews

def _tinted(img, tint, alpha=1.0):
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sp, op = img.load(), out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = sp[x, y]
            if a:
                op[x, y] = (r * tint[0] // 255, g * tint[1] // 255, b * tint[2] // 255, int(a * alpha))
    return out


def compose(frame, swirl_sheet, runes, w, h, f, tint, rune_alpha=0.9):
    """One still of a portal as the client draws it: swirl (tinted) < frame < runes (tinted)."""
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(_tinted(swirl_sheet.crop((f * w, 0, (f + 1) * w, h)), tint))
    out.alpha_composite(frame)
    bright = tuple(min(255, int(t * 0.6 + 255 * 0.4)) for t in tint)
    out.alpha_composite(_tinted(runes, bright, rune_alpha))
    return out


def preview_grid(scale=4):
    """Every portal colour on the ring, plus the Gateway, on meadow green."""
    ring = make_ring()
    rs = make_ring_swirl(ring)
    arch = make_arch()
    asw = make_arch_swirl(arch)
    tints = [(188, 168, 245), (245, 209, 128), (140, 179, 107), (168, 204, 245), (158, 143, 255), (255, 184, 224)]
    pad = 8
    width = pad + len(tints) * (RING_W + pad) + ARCH_W + pad
    height = pad + max(RING_H, ARCH_H) + pad
    sheet = Image.new("RGBA", (width, height), (104, 142, 86, 255))
    for i, t in enumerate(tints):
        sheet.alpha_composite(compose(ring.frame, rs, ring.runes, RING_W, RING_H, i % FRAMES, t),
                              (pad + i * (RING_W + pad), pad + ARCH_H - RING_H))
    sheet.alpha_composite(compose(arch.frame, asw, arch.runes, ARCH_W, ARCH_H, 0, (205, 189, 250)),
                          (pad + len(tints) * (RING_W + pad), pad))
    return sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)


if __name__ == "__main__":
    preview_grid().save("portal_preview.png")
    print("saved portal_preview.png")
