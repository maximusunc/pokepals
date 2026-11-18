"""Horizon's pixel art: what you see from inside a perspective world.

The perspective view (PerspectiveView) draws a sky over the far ground. A world can hang a BACKDROP there: a ring
of distant hills right round the horizon and a band of clouds above it, each a panorama that wraps through 360
degrees (column x is the bearing x / width * 360, 0 = north, clockwise), so turning on the spot slides the world's
far distance past you. Both are pixel art at one texel per screen pixel at the horizon.

  hills_panorama()   far blue ridges, a nearer green range with trees on its crest, the meadow's own rolling
                     hills nearest; windmills stand here and there on the near hills. (A world's own landmarks
                     stand in front of it at any distance: PerspectiveView draws them past the draw distance.) The bottom rows fade into the haze
                     the far ground ends in, so the hills sit on the land with no seam.
  clouds_panorama()  soft cumulus with flat, shaded bottoms, drifting (the shader slides it slowly).

Run directly for a preview:  python3 horizon.py  -> horizon_preview.png
"""
import math
import random

from PIL import Image

W = 1440       # 4 columns per degree, ~1 texel per screen pixel at the view's focal length
HILLS_H = 120
CLOUDS_H = 150

HAZE = (158, 178, 153)  # the land haze (data/view.json sky.land_haze): the far ground fades into it, and so do the hills' feet
BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def _bayer(x, y):
    return (BAYER4[y % 4][x % 4] + 0.5) / 16.0 - 0.5


def _periodic(seed, x, waves):
    """A seamless (period W) ridge: a sum of whole-number sine waves round the circle."""
    rnd = random.Random(seed)
    th = x / W * math.tau
    v = 0.0
    for _ in range(waves):
        k = rnd.randint(1, 14)
        v += math.sin(k * th + rnd.random() * math.tau) / math.sqrt(k)
    return v


def _mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _ridge(img, color, base, amp, seed, waves=7, dither=0.9):
    """Fill everything below a ridge line base + amp * noise (heights from the bottom), dithered at its edge."""
    px = img.load()
    heights = []
    lo = min(_periodic(seed, x, waves) for x in range(0, W, 4))
    hi = max(_periodic(seed, x, waves) for x in range(0, W, 4))
    for x in range(W):
        n = (_periodic(seed, x, waves) - lo) / (hi - lo)
        h = base + amp * n
        heights.append(h)
        for y in range(HILLS_H):
            from_bottom = HILLS_H - y
            if from_bottom < h + _bayer(x, y) * dither:
                px[x, y] = color + (255,)
    return heights


def _windmill(img, cx, ground, color):
    px = img.load()
    top = HILLS_H - ground
    for y in range(top - 9, top + 1):                   # a tapering tower
        half = 1 + (y - (top - 9)) // 4
        for x in range(cx - half, cx + half + 1):
            px[x % W, y] = color + (255,)
    hub = (cx, top - 9)
    for ang in (0.6, 0.6 + math.pi / 2, 0.6 + math.pi, 0.6 + 1.5 * math.pi):  # four sails
        for r in range(1, 8):
            x = int(round(hub[0] + math.cos(ang) * r))
            y = int(round(hub[1] + math.sin(ang) * r))
            if 0 <= y < HILLS_H:
                px[x % W, y] = color + (255,)


def _crest_trees(img, heights, color, seed, every=(9, 30)):
    """Little round trees standing along a ridge line."""
    px = img.load()
    rnd = random.Random(seed)
    x = rnd.randint(0, 20)
    while x < W:
        h = heights[x]
        r = rnd.choice([2, 2, 3])
        cy = HILLS_H - int(h) - r + 1
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r + 1 and 0 <= cy + dy < HILLS_H:
                    px[(x + dx) % W, cy + dy] = color + (255,)
        x += rnd.randint(*every)


def hills_panorama():
    img = Image.new("RGBA", (W, HILLS_H), (0, 0, 0, 0))
    far = (168, 186, 202)
    mid = (126, 156, 150)
    near = (98, 138, 94)
    _ridge(img, far, 30, 34, seed=11, waves=8)
    mid_h = _ridge(img, mid, 16, 22, seed=23, waves=7)
    _crest_trees(img, mid_h, _mix(mid, (20, 40, 30), 0.25), seed=5, every=(14, 44))
    near_h = _ridge(img, near, 9, 20, seed=37, waves=6)
    _crest_trees(img, near_h, _mix(near, (20, 40, 20), 0.3), seed=9, every=(18, 60))
    for bearing in (52, 131, 248, 305):  # windmills on the near hills
        x = int(bearing / 360.0 * W)
        _windmill(img, x, int(near_h[x]), _mix(near, (240, 236, 222), 0.35))
    # the bottom rows sink into the haze the far ground ends in
    px = img.load()
    fade = 14
    for y in range(HILLS_H - fade, HILLS_H):
        t = (y - (HILLS_H - fade)) / float(fade - 1)
        for x in range(W):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = _mix((r, g, b), HAZE, min(1.0, t * 1.05 + _bayer(x, y) * 0.15)) + (255,)
    return img


def _cloud(img, cx, cy, w, h, rnd):
    """A cumulus: a heap of overlapping round lobes over a flat base, lit from above, shaded underneath."""
    px = img.load()
    white = (252, 252, 250)
    light = (236, 240, 246)
    shade = (212, 222, 234)
    lobes = []
    for _ in range(6 + int(w / 14)):
        lx = cx + rnd.uniform(-w * 0.42, w * 0.42)
        r = rnd.uniform(h * 0.32, h * 0.62) * (1.0 - abs(lx - cx) / (w * 0.9))
        lobes.append((lx, cy - r * 0.35, max(3.0, r)))
    base = cy + h * 0.18
    for x in range(int(cx - w * 0.7), int(cx + w * 0.7)):
        for y in range(int(cy - h * 1.2), int(base) + 1):
            if not 0 <= y < CLOUDS_H:
                continue
            inside = None
            for lx, ly, r in lobes:
                d = math.hypot(x - lx, y - ly) / r
                if d <= 1.0 and (inside is None or d < inside[0]):
                    inside = (d, ly, r)
            if inside is None:
                continue
            d, ly, r = inside
            up = (y - (ly - r)) / (2 * r)  # 0 at the lobe's top .. 1 at its bottom
            c = white if up + _bayer(x, y) * 0.2 < 0.45 else light
            if y > base - 3 + _bayer(x, y) * 2:
                c = shade
            px[x % W, y] = c + (235,)


def clouds_panorama():
    img = Image.new("RGBA", (W, CLOUDS_H), (0, 0, 0, 0))
    rnd = random.Random(71)
    x = 30
    while x < W - 40:
        w = rnd.uniform(70, 170)
        h = rnd.uniform(18, 34)
        cy = rnd.uniform(36, CLOUDS_H - 18)
        _cloud(img, x + w * 0.5, cy, w, h, rnd)
        x += w + rnd.uniform(40, 140)
    return img


# ------------------------------------------------------------------------------------------------ the land

OUTLINE = (52, 44, 40)


class Sprite:
    """A little RGBA canvas with the few primitives the props need."""

    def __init__(self, w, h):
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px = self.img.load()
        self.w, self.h = w, h

    def put(self, x, y, c, a=255):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = tuple(c) + (a,)

    def rect(self, x0, y0, w, h, c):
        for x in range(int(x0), int(x0 + w)):
            for y in range(int(y0), int(y0 + h)):
                self.put(x, y, c)

    def outline(self):
        """A dark one-pixel rim round everything drawn (the game's sprite convention)."""
        src = self.img.copy().load()
        for x in range(self.w):
            for y in range(self.h):
                if src[x, y][3] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < self.w and 0 <= yy < self.h and src[xx, yy][3] > 0:
                            self.px[x, y] = OUTLINE + (255,)
                            break
        return self.img


def _shade3(c, t):
    """Light from the left: t in -1 (lit) .. 1 (shadow) picks one of three tones, dithered between them."""
    lit = _mix(c, (255, 250, 236), 0.22)
    dark = _mix(c, (30, 30, 50), 0.32)
    if t < -0.35:
        return lit
    if t > 0.45:
        return dark
    return c


def _plant(sp, cx, half, base_y, arc, wall_at, seed, grass=True):
    """Stand a round building on the ground. Seen from a little above, the foot of a round wall curves toward you
    (lowest at the middle, `arc` pixels below `base_y`), darkens where it meets the earth, and grass grows up over
    it. A straight bottom edge is what makes a sprite look like it's hovering. `wall_at(x, y)` is the wall's
    colour there (so the courses and shading carry on down)."""
    rnd = random.Random(seed)
    foot = {}
    for x in range(int(cx - half), int(cx + half) + 1):
        u = max(-1.0, min(1.0, (x - cx) / float(half)))
        bottom = base_y + int(round(arc * math.sqrt(1.0 - u * u)))
        foot[x] = bottom
        for y in range(base_y, bottom + 1):
            sp.put(x, y, wall_at(x, y))
        for y in (bottom, bottom - 1):  # the dark line where it meets the ground
            c = sp.px[x, y]
            if c[3]:
                sp.put(x, y, _mix(c[:3], (40, 46, 36), 0.45 if y == bottom else 0.2))
    if grass:
        greens = [(76, 120, 60), (98, 146, 70), (62, 100, 52)]
        for x in range(int(cx - half) - 1, int(cx + half) + 2):
            if rnd.random() < 0.55:
                h = rnd.choice([1, 2, 2, 3])
                b = foot.get(x, base_y + 1) + 1
                for y in range(b - h, b + 1):
                    sp.put(x, y, rnd.choice(greens))
    return foot


def windmill_frames(n=8):
    """A white tower windmill seen from n bearings round it. Frame k: the viewer has turned k steps clockwise from
    looking straight at its front (where the door and the sails are), so the mill appears turned the other way."""
    frames = []
    W_, H_ = 64, 96
    wall = (232, 226, 210)
    cap = (150, 92, 64)
    sail = (238, 232, 218)
    frame_c = (120, 84, 60)
    door_c = (112, 78, 52)
    base_y = H_ - 8
    for k in range(n):
        th = -k * math.tau / n  # the mill's front, relative to the viewer (0 = facing us)
        sp = Sprite(W_, H_)
        cx = W_ // 2

        def tower():
            for y in range(base_y - 46, base_y):
                hy = (base_y - y) / 46.0
                half = 10 - 4 * hy
                for x in range(int(cx - half), int(cx + half) + 1):
                    u = (x - cx) / max(half, 1)
                    sp.put(x, y, _shade3(wall, u * 1.1 + _bayer(x, y) * 0.3))
            _plant(sp, cx, 10, base_y, 2, lambda x, y: _shade3(wall, (x - cx) / 10.0 * 1.1 + _bayer(x, y) * 0.3), seed=k, grass=False)
            # the door and a window, on the front face, where they turn to
            if math.cos(th) > 0.15:
                dx = math.sin(th) * 8
                sp.rect(cx + dx - 2, base_y - 9, 4, 11, door_c)
                sp.rect(cx + math.sin(th) * 6 - 1, base_y - 30, 3, 4, (80, 96, 120))
            # the cap
            for y in range(base_y - 56, base_y - 45):
                hy = (base_y - 45 - y) / 11.0
                half = 7 - 6 * hy * hy
                for x in range(int(cx - half), int(cx + half) + 1):
                    u = (x - cx) / max(half, 1)
                    sp.put(x, y, _shade3(cap, u + _bayer(x, y) * 0.3))

        hub = (cx + math.sin(th) * 6, base_y - 50)
        fore = math.cos(th) >= 0

        def sails(dim):
            c_sail = _mix(sail, (120, 120, 130), 0.25) if dim else sail
            c_frame = _mix(frame_c, (60, 60, 70), 0.3) if dim else frame_c
            for a in (0.5, 0.5 + math.pi / 2, 0.5 + math.pi, 0.5 + 1.5 * math.pi):
                for r in range(2, 27):
                    x = hub[0] + math.cos(a) * r * math.cos(th)
                    y = hub[1] + math.sin(a) * r
                    sp.put(x, y, c_frame)
                    if r > 6:  # the sailcloth, to one side of the stock
                        for w in (1, 2, 3):
                            sx = x + (-math.sin(a)) * w * math.cos(th)
                            sy = y + math.cos(a) * w
                            sp.put(sx, sy, c_sail)
            sp.rect(hub[0] - 1, hub[1] - 1, 3, 3, c_frame)

        if fore:
            tower()
            sails(False)
        else:
            sails(True)
            tower()
        # grass growing up round its foot
        rnd = random.Random(100 + k)
        for x in range(cx - 11, cx + 12):
            if rnd.random() < 0.5:
                u = max(-1.0, min(1.0, (x - cx) / 10.0))
                b = base_y + int(round(2 * math.sqrt(1.0 - u * u))) + 1
                for y in range(b - rnd.choice([1, 2, 2]), b + 1):
                    sp.put(x, y, rnd.choice([(76, 120, 60), (98, 146, 70), (62, 100, 52)]))
        frames.append(sp.outline() if True else sp.img)
    return frames


def ruin_keep():
    """The ruin at the end of the long road: a round stone keep, its top broken off, an arched door and a window,
    ivy up one side. Round, so it looks the same from every side."""
    W_, H_ = 120, 200
    sp = Sprite(W_, H_)
    cx = W_ // 2
    stone = (168, 160, 148)
    base_y = H_ - 12  # the wall's curved foot reaches 4 lower, H - 8: TreeView stands a landmark's sprite there
    rnd = random.Random(4)
    top_line = [base_y - 150 + int(abs(math.sin(x * 0.21)) * 18 + (x % 7) * 2) for x in range(W_)]
    for y in range(base_y - 170, base_y):
        for x in range(cx - 34, cx + 35):
            if y < top_line[x]:
                continue
            u = (x - cx) / 34.0
            c = _shade3(stone, u * 1.15 + _bayer(x, y) * 0.35)
            # courses of stone: a mortar line every 7 rows, joints staggered
            row = (base_y - y) // 7
            if (base_y - y) % 7 == 0 or ((x + row * 5) % 11 == 0):
                c = _mix(c, (90, 86, 82), 0.35)
            sp.put(x, y, c)
    def keep_wall(x, y):
        u = (x - cx) / 34.0
        c = _shade3(stone, u * 1.15 + _bayer(x, y) * 0.35)
        row = (base_y - y) // 7
        if (base_y - y) % 7 == 0 or ((x + row * 5) % 11 == 0):
            c = _mix(c, (90, 86, 82), 0.35)
        return c

    _plant(sp, cx, 34, base_y, 4, keep_wall, seed=4, grass=False)
    # the arched door and an upper window, dark inside
    for y in range(base_y - 30, base_y + 4):
        for x in range(cx - 9, cx + 10):
            if y > base_y - 22 or (x - cx) ** 2 + (y - (base_y - 22)) ** 2 <= 81:
                sp.put(x, y, (46, 42, 44))
    for y in range(base_y - 100, base_y - 84):
        for x in range(cx + 4, cx + 11):
            if y > base_y - 96 or (x - cx - 7.5) ** 2 + (y - (base_y - 96)) ** 2 <= 12:
                sp.put(x, y, (46, 42, 44))
    # ivy climbing the left (lit) side
    ivy = [(70, 112, 60), (92, 138, 70), (54, 90, 52)]
    for _ in range(420):
        x = cx - 34 + int(abs(rnd.gauss(0, 9)))
        y = base_y - int(abs(rnd.gauss(0, 60)))
        if sp.px[min(max(x, 0), W_ - 1), min(max(y, 0), H_ - 1)][3] > 0:
            sp.put(x, y, rnd.choice(ivy))
    # fallen stones at its foot, and the grass grown up round it
    for _ in range(9):
        x = cx + rnd.randint(-48, 48)
        y = base_y + 2 + rnd.randint(-1, 4)
        sp.rect(x, y, rnd.randint(3, 6), 3, _mix(stone, (60, 60, 60), 0.15))
    greens = [(76, 120, 60), (98, 146, 70), (62, 100, 52)]
    for x in range(cx - 36, cx + 37):
        if rnd.random() < 0.6:
            u = max(-1.0, min(1.0, (x - cx) / 34.0))
            b = base_y + int(round(4 * math.sqrt(1.0 - u * u))) + 1
            for y in range(b - rnd.choice([1, 2, 3, 3]), b + 1):
                sp.put(x, y, rnd.choice(greens))
    return sp.outline()


def fence_panel():
    """A length of split-rail fence between two posts (a 'card': PerspectiveView narrows it edge-on)."""
    sp = Sprite(34, 24)
    wood = (150, 108, 72)
    for x in (1, 30):
        sp.rect(x, 2, 3, 22, _mix(wood, (40, 30, 30), 0.15))
        sp.rect(x, 2, 1, 22, _mix(wood, (255, 240, 220), 0.2))
    for y in (6, 13):
        sp.rect(2, y, 30, 3, wood)
        sp.rect(2, y, 30, 1, _mix(wood, (255, 240, 220), 0.25))
    return sp.outline()


def signpost():
    """A fingerpost: two arms, one pointing on up the road, one back the way you came (a card)."""
    sp = Sprite(40, 48)
    wood = (140, 100, 66)
    sp.rect(18, 8, 4, 40, wood)
    sp.rect(18, 8, 1, 40, _mix(wood, (255, 240, 220), 0.22))
    board = (196, 164, 116)
    for (x0, y0, d) in ((20, 10, 1), (20, 22, -1)):
        for i in range(17):
            x = x0 + i * d
            h = 7 if i < 14 else 7 - (i - 13) * 2
            sp.rect(x, y0 + (7 - h) // 2, 1, max(h, 1), board)
        for i in range(2, 12, 3):
            sp.put(x0 + i * d, y0 + 3, (110, 80, 52))
    return sp.outline()


def haystack():
    """A round haystack (round: the same from every side)."""
    sp = Sprite(40, 34)
    hay = (214, 182, 104)
    for y in range(4, 32):
        for x in range(2, 38):
            u = (x - 20) / 18.0
            v = (y - 30) / 26.0
            if u * u + v * v <= 1.0:
                c = _shade3(hay, u * 1.1 + v * 0.3 + _bayer(x, y) * 0.4)
                if (x * 3 + y * 7) % 11 == 0:
                    c = _mix(c, (150, 120, 60), 0.4)
                sp.put(x, y, c)
    return sp.outline()


# ----------------------------------------------------------------------------------------- the skylark picture
#
# Farmeadow's secret: a picture painted across eight old boards on posts, scattered through a field at different
# distances. From one spot, looking south, the boards line up into one picture: a skylark over a low sun. From
# anywhere else they're odd painted boards. The picture is laid out in SCREEN pixels as the perspective camera sees
# it from that spot (data/view.json's camera, PerspectiveView / ViewProjection); each board stands at its own depth,
# drawn at one texel per screen pixel (its "tex_scale" is depth / focal), on a post reaching down to the ground.
# skylark_boards() writes the boards and data/hz_skylark.json, which tools/gen_farmeadow_world.py reads to stand
# them in the world. The upper board in each column stands farther off than the one below it, so its post hides
# behind the lower board and never crosses the picture.

PIC_X0, PIC_Y0 = -83, -46            # the picture's top-left on screen, from the view's centre (y down)
BOARD_W, BOARD_H, GAP = 40, 32, 2
# depth (distance ahead of the camera's foot) of each board: [column][row]; row 0 (upper) farther than row 1.
# Kept close together: a board's size in the world grows with its depth, and a far one would be a billboard.
BOARD_DEPTHS = [(440, 290), (360, 268), (480, 322), (400, 300)]
LARK_AT = (0.47, 0.47)  # the lark's middle, as a share of the picture's width and height
LARK_SPAN = 45.0        # its wingspan on screen


def _paint_picture(w, h, with_lark=True):
    """The whole picture, w x h screen pixels: a warm evening sky, a low sun, two streaks of cloud, and a skylark
    in flight crossing in front of the sun."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    px = img.load()
    top, low = (222, 146, 140), (250, 192, 104)
    sun_c, sun_r = (w * 0.58, h + 2), 23.0
    for y in range(h):
        for x in range(w):
            t = y / float(h - 1)
            c = _mix(top, low, min(1.0, t + _bayer(x, y) * 0.12))
            d = math.hypot(x - sun_c[0], y - sun_c[1])
            if d < sun_r + 10:
                c = _mix(c, (255, 232, 168), max(0.0, 1.0 - (d - sun_r) / 10.0) * 0.6)
            if d < sun_r:
                c = (255, 242, 196) if d < sun_r - 3 + _bayer(x, y) * 2 else (250, 178, 88)
            px[x, y] = c + (255,)
    # cloud streaks
    for (cx, cy, ln) in ((30, 16, 44), (112, 28, 34), (84, 11, 22)):
        for x in range(int(cx - ln / 2), int(cx + ln / 2)):
            for dy in (0, 1):
                if 0 <= x < w and (x + dy) % 7 != 0:
                    px[x, cy + dy] = _mix(px[x, cy + dy][:3], (214, 170, 176), 0.7) + (255,)
    if not with_lark:
        return img
    # the skylark: crossing in front of the sun, wings raised mid-beat, tail fanned, heading right
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    lark = (104, 76, 54)
    shade = (70, 50, 38)
    belly = (196, 160, 120)
    bx, by = w * LARK_AT[0], h * LARK_AT[1]
    k = LARK_SPAN / 60.0

    def P(pts):
        return [(bx + x * k, by + y * k) for x, y in pts]
    d.polygon(P([(-4, -2), (-30, -30), (-26, -33), (-14, -24), (2, -6)]), fill=lark, outline=shade)    # far wing
    d.polygon(P([(2, -3), (24, -34), (29, -31), (20, -14), (8, -1)]), fill=lark, outline=shade)        # near wing
    d.polygon(P([(-14, 1), (-26, -3), (-27, 6), (-14, 4)]), fill=lark, outline=shade)                 # tail
    d.ellipse([bx - 15 * k, by - 4 * k, bx + 10 * k, by + 5 * k], fill=lark, outline=shade)             # body
    d.line(P([(-10, 3), (6, 3)]), fill=belly, width=1)                                                   # pale belly
    d.ellipse([bx + 6 * k, by - 7 * k, bx + 14 * k, by + 1 * k], fill=lark, outline=shade)              # head
    d.polygon(P([(14, -4), (19, -3), (14, -2)]), fill=shade)                                            # beak
    d.point((bx + 11 * k, by - 4 * k), fill=(30, 22, 18))                                               # eye
    d.polygon(P([(9, -9), (11, -13), (13, -8)]), fill=lark)                                             # its little crest
    return img


def _canvas_camera():
    import json
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "..", "..", "data", "view.json")) as f:
        cam = json.load(f)["camera"]
    pitch = math.radians(cam.get("pitch_deg", 0.0))
    focal = cam["back"] * math.cos(pitch) + cam["height"] * math.sin(pitch)
    return cam, focal


def skylark_boards():
    """The eight boards: [(name, image, info)], info = rect on screen, depth and tex_scale; plus the whole picture."""
    cam, f = _canvas_camera()
    h, shift = cam["height"], cam["shift"]
    pic_w = 4 * BOARD_W + 3 * GAP
    pic_h = 2 * BOARD_H + GAP
    picture = _paint_picture(pic_w, pic_h)
    bare_picture = _paint_picture(pic_w, pic_h, with_lark=False)
    wood = (150, 112, 78)
    out = []
    for col in range(4):
        for row in range(2):
            z = float(BOARD_DEPTHS[col][row])
            sc = f / z                                   # screen pixels per world unit at that depth
            x0 = PIC_X0 + col * (BOARD_W + GAP)
            y0 = PIC_Y0 + row * (BOARD_H + GAP)
            y_foot = shift + f * h / z                   # where its foot lands on screen
            tall = int(round(y_foot + 6 * sc - y0))      # TreeView stands a sprite's bottom 6 units below its foot
            post_end = int(round(y_foot - y0))
            sp = Sprite(BOARD_W, tall)
            box = (col * (BOARD_W + GAP), row * (BOARD_H + GAP), col * (BOARD_W + GAP) + BOARD_W, row * (BOARD_H + GAP) + BOARD_H)

            def board(tile):
                sp = Sprite(BOARD_W, tall)
                # the painted face, with the boards' planks showing faintly through the paint
                for yy in range(BOARD_H):
                    for xx in range(BOARD_W):
                        c = tile.getpixel((xx, yy))[:3]
                        if xx % 9 == 0:
                            c = _mix(c, (90, 70, 52), 0.18)
                        sp.put(xx, yy, c)
                # its post, from under the board down to the ground
                for yy in range(BOARD_H, post_end):
                    for xx in range(BOARD_W // 2 - 1, BOARD_W // 2 + 2):
                        sp.put(xx, yy, _mix(wood, (40, 30, 20), 0.25) if xx == BOARD_W // 2 + 1 else wood)
                return sp.outline()

            tile = picture.crop(box)
            bare = bare_picture.crop(box)
            name = "hz_board_%d" % (col * 2 + row)
            info = {"id": name, "rect": [x0, y0, BOARD_W, BOARD_H], "depth": z, "tex_scale": round(z / f, 6)}
            out.append((name, board(tile), info))
            if list(tile.getdata()) != list(bare.getdata()):  # the lark crosses this board: a version without it
                info["bare"] = "res://assets/sprites/%s_bare.png" % name
                out.append((name + "_bare", board(bare), None))
    # where the painted lark is, so the one that comes alive can start exactly there
    lx = PIC_X0 + pic_w * LARK_AT[0]
    ly = PIC_Y0 + pic_h * LARK_AT[1]
    col = min(3, int((lx - PIC_X0) // (BOARD_W + GAP)))
    row = min(1, int((ly - PIC_Y0) // (BOARD_H + GAP)))
    lark = {"screen": [round(lx, 1), round(ly, 1)], "depth": float(BOARD_DEPTHS[col][row]), "span": LARK_SPAN}
    return out, picture, cam, lark


if __name__ == "__main__":
    hills = hills_panorama()
    clouds = clouds_panorama()
    out = Image.new("RGBA", (W, CLOUDS_H + HILLS_H), (120, 170, 228, 255))
    out.alpha_composite(clouds, (0, 0))
    out.alpha_composite(hills, (0, CLOUDS_H))
    out.save("horizon_preview.png")
    print("wrote horizon_preview.png")
