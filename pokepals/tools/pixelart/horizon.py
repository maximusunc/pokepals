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


if __name__ == "__main__":
    hills = hills_panorama()
    clouds = clouds_panorama()
    out = Image.new("RGBA", (W, CLOUDS_H + HILLS_H), (120, 170, 228, 255))
    out.alpha_composite(clouds, (0, 0))
    out.alpha_composite(hills, (0, CLOUDS_H))
    out.save("horizon_preview.png")
    print("wrote horizon_preview.png")
