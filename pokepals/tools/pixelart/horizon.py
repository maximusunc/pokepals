"""Horizon's pixel art: what you see from inside a perspective world.

The perspective view (PerspectiveView) draws a sky over the far ground. A world can hang a BACKDROP there: a ring
of distant hills right round the horizon and a band of clouds above it, each a panorama that wraps through 360
degrees (column x is the bearing x / width * 360, 0 = north, clockwise), so turning on the spot slides the world's
far distance past you. Both are pixel art at one texel per screen pixel at the horizon.

  hills_panorama()   far blue ridges, a nearer green range with trees on its crest, the meadow's own rolling
                     hills nearest; at north (where the long road runs) the far ridge carries the ruin of an old
                     keep; windmills stand here and there on the near hills. The bottom rows fade into the haze
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

HAZE = (219, 230, 235)
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


def _keep(img, cx, ground, color):
    """The ruin of an old keep on the far ridge, due north: a broken curtain wall between two towers, one fallen."""
    px = img.load()
    shade = _mix(color, (0, 0, 0), 0.1)

    def rect(x0, y0, w, h, c):
        for x in range(x0, x0 + w):
            for y in range(y0, y0 + h):
                xx = x % W
                if 0 <= y < HILLS_H:
                    px[xx, y] = c + (255,)

    top = HILLS_H - ground
    rect(cx - 22, top - 10, 44, 12, color)              # curtain wall
    for i, x in enumerate(range(cx - 22, cx + 22, 4)):  # crenellations, broken toward the east
        if i < 7 or i % 3 == 0:
            rect(x, top - 12, 2, 2, color)
    rect(cx - 28, top - 24, 9, 26, color)               # the tall west tower
    rect(cx - 28, top - 26, 2, 2, color)
    rect(cx - 24, top - 26, 2, 2, color)
    rect(cx - 21, top - 26, 2, 2, color)
    rect(cx - 25, top - 18, 2, 3, shade)                # a window
    rect(cx + 19, top - 16, 8, 18, color)               # the east tower, its top fallen
    rect(cx + 19, top - 18, 3, 2, color)
    rect(cx - 4, top - 6, 5, 6, shade)                  # the gate


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
    far_h = _ridge(img, far, 30, 34, seed=11, waves=8)
    _keep(img, 0, int(far_h[0]) - 1, _mix(far, (40, 50, 70), 0.18))
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
            # the door and a window, on the front face, where they turn to
            if math.cos(th) > 0.15:
                dx = math.sin(th) * 8
                sp.rect(cx + dx - 2, base_y - 9, 4, 9, door_c)
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
        # a small shadow at its foot
        for x in range(cx - 14, cx + 15):
            for y in range(base_y, base_y + 4):
                if ((x - cx) / 14.0) ** 2 + ((y - base_y - 1) / 3.0) ** 2 <= 1 and sp.px[x, y][3] == 0:
                    sp.put(x, y, (0, 0, 0), 46)
        frames.append(sp.outline() if True else sp.img)
    return frames


def ruin_keep():
    """The ruin at the end of the long road: a round stone keep, its top broken off, an arched door and a window,
    ivy up one side. Round, so it looks the same from every side."""
    W_, H_ = 120, 200
    sp = Sprite(W_, H_)
    cx = W_ // 2
    stone = (168, 160, 148)
    base_y = H_ - 10
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
    # the arched door and an upper window, dark inside
    for y in range(base_y - 30, base_y):
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
    # fallen stones at its foot
    for _ in range(9):
        x = cx + rnd.randint(-48, 48)
        y = base_y + rnd.randint(-3, 4)
        sp.rect(x, y, rnd.randint(3, 6), 3, _mix(stone, (60, 60, 60), 0.15))
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


if __name__ == "__main__":
    hills = hills_panorama()
    clouds = clouds_panorama()
    out = Image.new("RGBA", (W, CLOUDS_H + HILLS_H), (120, 170, 228, 255))
    out.alpha_composite(clouds, (0, 0))
    out.alpha_composite(hills, (0, CLOUDS_H))
    out.save("horizon_preview.png")
    print("wrote horizon_preview.png")
