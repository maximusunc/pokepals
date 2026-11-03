"""
Bobbledown -- the soft world's art. Deliberately NOT pixel art: every other world is drawn in the
house pixel language (hard edges, a 1px ink outline, stepped light), and Bobbledown is the one place
that breaks from it. Here everything is ROUND:

  * shapes are shaded as smooth spheres and domes (a real per-pixel normal, a soft key light from the
    upper left, a cool bounce light from below, and a glossy specular spot), so a gumdrop reads like a
    sweet you could pick up and a bobbling like a rubber ball;
  * there is no outline anywhere: forms separate by light and a soft contact shadow, never by ink;
  * the palette is pastel candy -- strawberry, mint, lemon, lilac, peach, sky -- on cream;
  * everything is SUPERSAMPLED (drawn at SS x the output size, then box-filtered down), so every edge is
    anti-aliased, and baked at TWICE the world resolution ("@2x" files). The client draws an @2x file at
    half size with linear filtering, so on a phone or a big monitor the curves stay smooth instead of
    turning into stairs.

Procedural primitives only, no randomness: every image is reproducible from the numbers below. Needs
Pillow + numpy (tools-only, like the pixel-art modules; the PNGs are committed).

Outputs (baked by tools/gen_bobbledown.py):
  * trees  -- puff-trees and great puffs (trunk + canopy layers, only the canopy sways), plus tall
              y-sorted growths: gumdrops, lollipop trees, bubble-stalks;
  * props  -- BASE + grayscale TINT + untinted GLOSS layers (the gloss sits over the tint, so a
              coloured sweet keeps its white shine);
  * creatures -- ambient-pal sheets in the PalView layout (8 motion columns + 16 idle columns x the five
              right-handed facings), 64 px cells (32 world px), three colours each.
"""

import math

import numpy as np
from PIL import Image

SS = 4  # supersampling factor

# ------------------------------------------------------------------------------------------- palette
CREAM = (1.00, 0.96, 0.90)
INK = (0.29, 0.22, 0.33)        # eyes and mouths: a soft plum, never black
BLUSH = (1.00, 0.55, 0.62)
STRAWBERRY = (1.00, 0.56, 0.66)
MINT = (0.56, 0.92, 0.78)
LEMON = (1.00, 0.89, 0.50)
LILAC = (0.77, 0.66, 1.00)
PEACH = (1.00, 0.72, 0.56)
SKY = (0.58, 0.82, 1.00)
BUBBLEGUM = (1.00, 0.68, 0.88)
CARAMEL = (0.86, 0.62, 0.46)

KEY = np.array([-0.52, -0.62, 0.59])
KEY = KEY / np.linalg.norm(KEY)


# -------------------------------------------------------------------------------------------- canvas
class Canvas:
    """A premultiplied float RGBA canvas at SS x the output size. Draw in OUTPUT pixel coordinates;
    `finish()` box-filters it down to the output size."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.W, self.H = w * SS, h * SS
        self.rgb = np.zeros((self.H, self.W, 3))
        self.a = np.zeros((self.H, self.W))
        ys, xs = np.mgrid[0:self.H, 0:self.W]
        self.X = (xs + 0.5) / SS
        self.Y = (ys + 0.5) / SS

    def over(self, rgb, alpha, mask=None):
        """Composite a straight-colour layer (rgb HxWx3, alpha HxW) over the canvas."""
        if mask is not None:
            alpha = alpha * mask
        alpha = np.clip(alpha, 0.0, 1.0)
        self.rgb = rgb * alpha[..., None] + self.rgb * (1.0 - alpha[..., None])
        self.a = alpha + self.a * (1.0 - alpha)

    def finish(self):
        k = SS
        rgb = self.rgb.reshape(self.h, k, self.w, k, 3).mean(axis=(1, 3))
        a = self.a.reshape(self.h, k, self.w, k).mean(axis=(1, 3))
        safe = np.where(a > 1e-5, a, 1.0)
        out = np.zeros((self.h, self.w, 4))
        out[..., :3] = np.clip(rgb / safe[..., None], 0, 1)
        out[..., 3] = np.clip(a, 0, 1)
        return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")

    def ellipse_uv(self, cx, cy, rx, ry, rot=0.0):
        dx, dy = self.X - cx, self.Y - cy
        if rot:
            c, s = math.cos(rot), math.sin(rot)
            dx, dy = dx * c + dy * s, -dx * s + dy * c
        return dx / rx, dy / ry


def _col(c):
    return np.array(c[:3], dtype=float)


def _edge(d2, soft=0.0):
    """Coverage of an ellipse from its normalised squared distance (supersampling does the AA)."""
    if soft <= 0:
        return (d2 <= 1.0).astype(float)
    d = np.sqrt(d2)
    return np.clip((1.0 - d) / soft, 0.0, 1.0)


# ----------------------------------------------------------------------------------------- primitives
def sphere(cv, cx, cy, rx, ry, color, gloss=1.0, alpha=1.0, rot=0.0, spec_size=1.0, flat=0.0, bounce=SKY):
    """A smooth shaded ellipsoid: key light, soft wrap, a cool bounce from below, a glossy spot.
    `flat` (0..1) squashes the normal toward the viewer so a dome reads flatter (a cushion)."""
    u, v = cv.ellipse_uv(cx, cy, rx, ry, rot)
    d2 = u * u + v * v
    cover = _edge(d2)
    if not cover.any():
        return
    nz = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
    n = np.stack([u * (1 - flat), v * (1 - flat), nz + flat], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
    lam = np.clip(n @ KEY, -1, 1)
    wrap = np.clip((lam + 0.45) / 1.45, 0, 1)
    base = _col(color)
    shade = 0.70 + 0.38 * wrap
    rgb = base[None, None, :] * shade[..., None]
    # bounce light from below (cool, faint) and a warm cream lift on the lit side
    up = np.clip(n[..., 1], 0, 1) ** 2
    rgb = rgb * (1 - 0.18 * up[..., None]) + _col(bounce)[None, None, :] * 0.18 * up[..., None]
    rgb = rgb + (_col(CREAM) - rgb) * (0.22 * np.clip(lam, 0, 1) ** 3)[..., None]
    # a soft rim darkening so the edge rounds away (not an outline: it fades, never inks)
    rim = np.clip((d2 - 0.72) / 0.28, 0, 1) ** 2
    rgb = rgb * (1 - 0.16 * rim[..., None])
    # glossy specular spot: Blinn-Phong with a view vector straight at us
    if gloss > 0:
        h = KEY + np.array([0, 0, 1.0])
        h /= np.linalg.norm(h)
        sp = np.clip(n @ h, 0, 1) ** (38.0 / spec_size)
        rgb = rgb + (1.0 - rgb) * (gloss * 0.85 * sp)[..., None]
    cv.over(np.clip(rgb, 0, 1), cover * alpha)


def flat_ellipse(cv, cx, cy, rx, ry, color, alpha=1.0, rot=0.0, soft=0.0):
    u, v = cv.ellipse_uv(cx, cy, rx, ry, rot)
    cover = _edge(u * u + v * v, soft)
    cv.over(np.broadcast_to(_col(color), cv.rgb.shape), cover * alpha)


def shadow(cv, cx, cy, rx, ry, alpha=0.22, color=(0.42, 0.30, 0.48)):
    """A soft contact shadow: a gaussian-ish falloff, never a hard ellipse."""
    u, v = cv.ellipse_uv(cx, cy, rx, ry)
    d2 = u * u + v * v
    fall = np.exp(-d2 * 2.2) * (d2 < 2.2)
    cv.over(np.broadcast_to(_col(color), cv.rgb.shape), fall * alpha)


def capsule(cv, x0, y0, x1, y1, r, color, gloss=0.6, alpha=1.0, stripes=None):
    """A rounded stick/trunk from (x0,y0) to (x1,y1), shaded like a cylinder with domed ends.
    `stripes` = (color, period, slant) paints candy-cane bands."""
    ax, ay = x1 - x0, y1 - y0
    L2 = ax * ax + ay * ay
    t = np.clip(((cv.X - x0) * ax + (cv.Y - y0) * ay) / max(L2, 1e-9), 0, 1)
    px, py = x0 + ax * t, y0 + ay * t
    dx, dy = (cv.X - px) / r, (cv.Y - py) / r
    d2 = dx * dx + dy * dy
    cover = _edge(d2)
    nz = np.sqrt(np.clip(1 - d2, 0, 1))
    n = np.stack([dx, dy, nz], axis=-1)
    lam = np.clip(n @ KEY, -1, 1)
    wrap = np.clip((lam + 0.45) / 1.45, 0, 1)
    base = np.broadcast_to(_col(color), cv.rgb.shape).copy()
    if stripes is not None:
        sc, period, slant = stripes
        along = ((cv.X - x0) * ax + (cv.Y - y0) * ay) / math.sqrt(max(L2, 1e-9))
        band = (np.sin((along + dx * r * slant) / period * math.tau) > 0.15)
        base[band] = _col(sc)
    rgb = base * (0.70 + 0.38 * wrap)[..., None]
    if gloss:
        h = KEY + np.array([0, 0, 1.0])
        h /= np.linalg.norm(h)
        sp = np.clip(n @ h, 0, 1) ** 30
        rgb = rgb + (1 - rgb) * (gloss * 0.7 * sp)[..., None]
    cv.over(np.clip(rgb, 0, 1), cover * alpha)


def bubble(cv, cx, cy, r, alpha=1.0, tint=(1, 1, 1)):
    """A soap bubble: clear in the middle, an iridescent film round the rim, a bright window glint."""
    u, v = cv.ellipse_uv(cx, cy, r, r)
    d2 = u * u + v * v
    cover = _edge(d2)
    d = np.sqrt(d2)
    ang = np.arctan2(v, u)
    # thin-film colours sliding round the rim
    hue = (ang / math.tau + d * 0.6) % 1.0
    film = np.stack([0.5 + 0.5 * np.cos(math.tau * (hue + k / 3.0)) for k in range(3)], axis=-1)
    film = film * 0.55 + 0.45 * _col(tint)[None, None, :]
    rim = np.clip((d - 0.55) / 0.45, 0, 1) ** 2.2
    a = (0.10 + 0.62 * rim) * cover
    cv.over(film, a * alpha)
    # window glint (upper left) and a small secondary glint (lower right)
    flat_ellipse(cv, cx - r * 0.38, cy - r * 0.42, r * 0.22, r * 0.13, (1, 1, 1), 0.85 * alpha, rot=-0.7)
    flat_ellipse(cv, cx + r * 0.42, cy + r * 0.36, r * 0.08, r * 0.08, (1, 1, 1), 0.6 * alpha)


def swirl(cv, cx, cy, r, c1, c2, arms=3):
    """A lollipop's flat-ish candy disc with spiral bands, shaded as a low dome."""
    u, v = cv.ellipse_uv(cx, cy, r, r)
    d2 = u * u + v * v
    cover = _edge(d2)
    d = np.sqrt(d2)
    ang = np.arctan2(v, u)
    band = np.sin(ang * arms + d * 9.0) > 0
    base = np.where(band[..., None], _col(c1)[None, None, :], _col(c2)[None, None, :])
    nz = np.sqrt(np.clip(1 - d2, 0, 1))
    n = np.stack([u * 0.6, v * 0.6, nz + 0.4], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    lam = np.clip(n @ KEY, -1, 1)
    rgb = base * (0.74 + 0.32 * np.clip((lam + 0.4) / 1.4, 0, 1))[..., None]
    h = KEY + np.array([0, 0, 1.0])
    h /= np.linalg.norm(h)
    sp = np.clip(n @ h, 0, 1) ** 40
    rgb = rgb + (1 - rgb) * (0.8 * sp)[..., None]
    rim = np.clip((d2 - 0.8) / 0.2, 0, 1)
    rgb = rgb * (1 - 0.12 * rim[..., None])
    cv.over(np.clip(rgb, 0, 1), cover)


def eye(cv, x, y, r, look=(0.0, 0.0), blink=0.0):
    """A big glossy eye: plum disc, a big sparkle and a small one. `blink` 0..1 closes it to a smile-line."""
    if blink >= 0.85:
        capsule(cv, x - r * 0.9, y + r * 0.1, x + r * 0.9, y + r * 0.1, r * 0.28, INK, gloss=0)
        return
    ry = r * (1.0 - blink)
    flat_ellipse(cv, x + look[0] * r * 0.3, y + look[1] * r * 0.3, r * 0.85, ry, INK)
    flat_ellipse(cv, x + look[0] * r * 0.3 - r * 0.28, y + look[1] * r * 0.3 - ry * 0.32, r * 0.34, r * 0.34 * (1 - blink), (1, 1, 1))
    flat_ellipse(cv, x + look[0] * r * 0.3 + r * 0.28, y + look[1] * r * 0.3 + ry * 0.34, r * 0.14, r * 0.14 * (1 - blink), (1, 1, 1), 0.9)


def cheek(cv, x, y, r):
    flat_ellipse(cv, x, y, r, r * 0.62, BLUSH, 0.55, soft=0.6)


def smile(cv, x, y, w):
    """A tiny curved smile, as a row of overlapping dots (anti-aliased by supersampling)."""
    for k in range(9):
        t = k / 8.0
        a = math.pi * (0.15 + 0.7 * t)
        capsule(cv, x + math.cos(a) * w, y + math.sin(a) * w * 0.7, x + math.cos(a) * w, y + math.sin(a) * w * 0.7, w * 0.16, INK, gloss=0)


def sparkles(cv, pts, r=1.3, alpha=0.9):
    for (x, y) in pts:
        flat_ellipse(cv, x, y, r, r, (1, 1, 1), alpha)


# ============================================================================================== trees
# Every sprite is @2x: a tree is 104 x 120 px (52 x 60 world), its feet at row 108; a great tree is
# 208 x 244 (104 x 122 world), its feet at row 228; a prop's feet sit 16 px above its bottom edge.
PUFF_VARIANTS = {
    "strawberry": (STRAWBERRY, (1.00, 0.80, 0.86)),
    "mint": (MINT, (0.82, 1.00, 0.92)),
    "lilac": (LILAC, (0.90, 0.85, 1.00)),
    "lemon": (LEMON, (1.00, 0.97, 0.78)),
}
GREAT_VARIANTS = {"bubblegum": (BUBBLEGUM, (1.0, 0.86, 0.95)), "sky": (SKY, (0.86, 0.95, 1.0))}


def _puff_clusters(scale, cx, top):
    """The lobes of a cotton-candy canopy: a back row, a middle mass, a lit crown."""
    s = scale
    return [
        (cx - 26 * s, top + 42 * s, 20 * s), (cx + 26 * s, top + 42 * s, 20 * s),
        (cx - 14 * s, top + 26 * s, 22 * s), (cx + 16 * s, top + 26 * s, 21 * s),
        (cx, top + 44 * s, 24 * s), (cx + 2 * s, top + 16 * s, 22 * s),
    ]


def puff_tree(variant, great=False):
    color, light = (GREAT_VARIANTS if great else PUFF_VARIANTS)[variant]
    if great:
        w, h, feet, s = 208, 244, 228, 2.0
    else:
        w, h, feet, s = 104, 120, 108, 1.0
    cx = w / 2
    trunk = Canvas(w, h)
    shadow(trunk, cx + 2 * s, feet, 26 * s, 8 * s, 0.26)
    # a soft, bendy caramel trunk with a rounded foot
    capsule(trunk, cx, feet - 4 * s, cx + 2 * s, feet - 48 * s, 7 * s, CARAMEL, gloss=0.5,
            stripes=((0.95, 0.80, 0.66), 7 * s, 0.4))
    sphere(trunk, cx, feet - 4 * s, 11 * s, 6 * s, CARAMEL, gloss=0.4)
    canopy = Canvas(w, h)
    top = feet - 104 * s
    for (x, y, r) in _puff_clusters(s, cx, top):
        sphere(canopy, x, y, r, r * 0.94, color, gloss=0.35, spec_size=2.2, flat=0.15)
    # the lit crown puffs, lighter, a touch glossier
    sphere(canopy, cx - 6 * s, top + 18 * s, 13 * s, 12 * s, light, gloss=0.6, spec_size=1.6, flat=0.1)
    sphere(canopy, cx + 16 * s, top + 30 * s, 9 * s, 8.5 * s, light, gloss=0.5, spec_size=1.6, flat=0.1)
    sparkles(canopy, [(cx - 20 * s, top + 30 * s), (cx + 24 * s, top + 18 * s), (cx + 4 * s, top + 46 * s)], 1.2 * s, 0.7)
    return trunk.finish(), canopy.finish()


GUMDROP_VARIANTS = {"cherry": (1.0, 0.46, 0.56), "lime": (0.62, 0.92, 0.48), "grape": (0.70, 0.52, 0.96), "orange": (1.0, 0.70, 0.38)}


def gumdrop(variant):
    """A gumdrop hillock as tall as a tree: a sugared dome you can walk behind."""
    color = GUMDROP_VARIANTS[variant]
    w, h, feet = 104, 120, 108
    cv = Canvas(w, h)
    cx = w / 2
    shadow(cv, cx + 3, feet, 40, 10, 0.26)
    # a dome: the top of a tall ellipsoid, cut flat at its feet
    u, v = cv.ellipse_uv(cx, feet, 38, 64)
    keep = (cv.Y <= feet + 2)
    tmp = Canvas(w, h)
    sphere(tmp, cx, feet, 38, 64, color, gloss=0.9, spec_size=2.6)
    cv.over(tmp.rgb / np.maximum(tmp.a, 1e-6)[..., None], tmp.a * keep)
    # a rounded foot so it sits ON the ground
    sphere(cv, cx, feet - 1, 38, 6, tuple(c * 0.86 for c in color), gloss=0.2, flat=0.6)
    # sugar crystals glinting over it
    rng = np.random.default_rng(len(variant) * 31 + 7)
    pts = []
    for _ in range(26):
        a = rng.uniform(math.pi * 1.05, math.pi * 1.95)
        rr = rng.uniform(0.25, 0.92)
        pts.append((cx + math.cos(a) * 38 * rr, feet + math.sin(a) * 64 * rr))
    sparkles(cv, pts, 1.05, 0.75)
    return cv.finish()


LOLLI_VARIANTS = {"rose": (STRAWBERRY, CREAM), "sky": (SKY, CREAM), "lemon": (LEMON, PEACH), "mint": (MINT, LILAC)}


def lolli_tree(variant):
    c1, c2 = LOLLI_VARIANTS[variant]
    w, h, feet = 104, 120, 108
    cv = Canvas(w, h)
    cx = w / 2
    shadow(cv, cx, feet, 16, 5, 0.24)
    capsule(cv, cx, feet - 2, cx, feet - 62, 3.4, CREAM, gloss=0.6)
    swirl(cv, cx, feet - 76, 28, c1, c2)
    # a ribbon bow where the candy meets the stick
    sphere(cv, cx - 6, feet - 48, 5, 3.5, c1, gloss=0.6, rot=0.4)
    sphere(cv, cx + 6, feet - 48, 5, 3.5, c1, gloss=0.6, rot=-0.4)
    sphere(cv, cx, feet - 48, 2.6, 2.6, c1, gloss=0.6)
    return cv.finish()


STALK_VARIANTS = {"pink": BUBBLEGUM, "sky": SKY, "mint": MINT}


def bubble_stalk(variant):
    """A curly stalk that grows soap bubbles instead of flowers."""
    color = STALK_VARIANTS[variant]
    w, h, feet = 104, 120, 108
    cv = Canvas(w, h)
    cx = w / 2
    shadow(cv, cx, feet, 14, 4, 0.22)
    # the stalk as a chain of capsules swaying into a curl
    pts = [(cx + 6 * math.sin(t * 2.6), feet - 2 - t * 70) for t in np.linspace(0, 1, 12)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        capsule(cv, x0, y0, x1, y1, 3.2, (0.56, 0.84, 0.66), gloss=0.4)
    for k in range(3):
        sphere(cv, cx + (-1) ** k * 10, feet - 12 - k * 18, 7, 3.2, (0.62, 0.90, 0.70), gloss=0.4, rot=(-1) ** k * 0.5)
    tip = pts[-1]
    sphere(cv, tip[0], tip[1], 5, 5, color, gloss=0.7)
    bubble(cv, tip[0] - 2, tip[1] - 20, 17, tint=color)
    bubble(cv, tip[0] + 22, tip[1] - 2, 10, tint=color)
    bubble(cv, tip[0] - 20, tip[1] + 8, 8, tint=color)
    bubble(cv, tip[0] + 12, tip[1] - 34, 6, tint=color)
    return cv.finish()


# ============================================================================================== props
# Each prop: (w, h) at @2x, and a builder(base, tint, gloss, cx, feet). TINT is drawn in white/gray and
# multiplied by the prop's colour; GLOSS is drawn untinted on top (white shines, sparkles, faces).
def _prop_canvases(w, h):
    return Canvas(w, h), Canvas(w, h), Canvas(w, h)


def p_marsh_stone(b, t, g, cx, feet):
    shadow(b, cx + 2, feet, 18, 5, 0.24)
    sphere(t, cx, feet - 12, 16, 15, (1, 1, 1), gloss=0, flat=0.45)
    sphere(t, cx, feet - 24, 15, 6, (1, 1, 1), gloss=0, flat=0.7)
    flat_ellipse(g, cx - 6, feet - 26, 6, 2.2, (1, 1, 1), 0.7, rot=-0.15)


def p_bubble_bloom(b, t, g, cx, feet):
    shadow(b, cx, feet, 10, 3, 0.2)
    capsule(b, cx, feet - 1, cx + 1, feet - 22, 1.8, (0.56, 0.84, 0.66), gloss=0.3)
    sphere(b, cx - 6, feet - 6, 6, 2.6, (0.62, 0.90, 0.70), gloss=0.3, rot=0.5)
    sphere(b, cx + 6, feet - 9, 6, 2.6, (0.62, 0.90, 0.70), gloss=0.3, rot=-0.5)
    for k in range(5):
        a = k / 5 * math.tau - math.pi / 2
        sphere(t, cx + 1 + math.cos(a) * 6, feet - 28 + math.sin(a) * 6, 5, 5, (1, 1, 1), gloss=0)
    bubble(g, cx + 1, feet - 28, 6, tint=(1, 1, 1))


def p_jellybeans(b, t, g, cx, feet):
    shadow(b, cx, feet, 16, 4, 0.2)
    for (x, y, r, rot) in [(-8, -5, 6, 0.5), (6, -4, 6.5, -0.4), (-1, -11, 6, 0.1), (11, -12, 5, 0.9)]:
        sphere(t, cx + x, feet + y, r * 1.5, r, (1, 1, 1), gloss=0, rot=rot)
        flat_ellipse(g, cx + x - r * 0.5, feet + y - r * 0.45, r * 0.5, r * 0.2, (1, 1, 1), 0.75, rot=rot)


def p_puff_bush(b, t, g, cx, feet):
    shadow(b, cx, feet, 22, 5, 0.22)
    for (x, y, r) in [(-12, -9, 11), (12, -9, 11), (0, -12, 13), (-5, -21, 9), (7, -19, 9)]:
        sphere(t, cx + x, feet + y, r, r * 0.92, (1, 1, 1), gloss=0, flat=0.15)
    sparkles(g, [(cx - 8, feet - 22), (cx + 9, feet - 14)], 1.1, 0.7)


def p_fizz_spring(b, t, g, cx, feet):
    shadow(b, cx, feet, 16, 4, 0.2)
    sphere(b, cx, feet - 4, 15, 6, (0.96, 0.92, 0.98), gloss=0.5, flat=0.5)
    flat_ellipse(t, cx, feet - 6, 10, 3.6, (1, 1, 1))
    for (x, y, r) in [(-3, -14, 3.5), (4, -22, 2.6), (-1, -30, 2.0)]:
        bubble(g, cx + x, feet + y, r)


def p_candy_bench(b, t, g, cx, feet):
    shadow(b, cx, feet, 28, 5, 0.24)
    for x in (-18, 18):
        capsule(b, cx + x, feet - 2, cx + x, feet - 10, 3.2, CREAM, gloss=0.4)
    capsule(t, cx - 22, feet - 13, cx + 22, feet - 13, 6, (1, 1, 1), gloss=0)
    capsule(t, cx - 22, feet - 25, cx + 22, feet - 25, 5, (1, 1, 1), gloss=0)
    capsule(g, cx - 16, feet - 15, cx + 12, feet - 15, 1.2, (1, 1, 1), gloss=0, alpha=0.6)


def p_chime_bubble(b, t, g, cx, feet):
    """The seven chime-bubbles (Bobbledown's secret): a great bubble held on a curled stand, a note
    curled up inside it."""
    shadow(b, cx, feet, 14, 4, 0.24)
    sphere(b, cx, feet - 3, 11, 4.5, CREAM, gloss=0.4, flat=0.5)
    pts = [(cx + 4 * math.sin(s * 5.0), feet - 4 - s * 26) for s in np.linspace(0, 1, 10)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        capsule(b, x0, y0, x1, y1, 2.0, CREAM, gloss=0.5)
    # a curled note inside, tinted
    sphere(t, cx - 2, feet - 44, 4.0, 3.2, (1, 1, 1), gloss=0, rot=-0.4)
    capsule(t, cx + 1.6, feet - 45, cx + 2.4, feet - 58, 1.1, (1, 1, 1), gloss=0)
    capsule(t, cx + 2.4, feet - 58, cx + 7, feet - 54, 1.1, (1, 1, 1), gloss=0)
    sphere(t, cx, feet - 48, 17, 17, (1, 1, 1), gloss=0, alpha=0.16)
    bubble(g, cx, feet - 48, 17)


def p_bubble_lamp(b, t, g, cx, feet):
    shadow(b, cx, feet, 10, 3, 0.22)
    capsule(b, cx, feet - 2, cx, feet - 40, 2.4, CREAM, gloss=0.5, stripes=(STRAWBERRY, 4.0, 0.6))
    sphere(t, cx, feet - 50, 9, 9, (1, 1, 1), gloss=0, flat=0.2)
    bubble(g, cx, feet - 50, 10)


def p_pebble_pops(b, t, g, cx, feet):
    shadow(b, cx, feet, 13, 3.5, 0.18)
    for (x, y, r) in [(-6, -4, 5), (5, -3, 4), (1, -8, 3.6)]:
        sphere(t, cx + x, feet + y, r, r * 0.85, (1, 1, 1), gloss=0, flat=0.3)
        flat_ellipse(g, cx + x - r * 0.35, feet + y - r * 0.4, r * 0.35, r * 0.18, (1, 1, 1), 0.8)


def p_cloud_cushion(b, t, g, cx, feet):
    shadow(b, cx, feet, 22, 5, 0.2)
    for (x, y, r) in [(-10, -6, 9), (10, -6, 9), (0, -8, 11)]:
        sphere(t, cx + x, feet + y, r, r * 0.6, (1, 1, 1), gloss=0, flat=0.4)


def p_sign_bubble(b, t, g, cx, feet):
    """A round signboard on a little candy post."""
    shadow(b, cx, feet, 10, 3, 0.2)
    capsule(b, cx, feet - 2, cx, feet - 22, 2.2, CREAM, gloss=0.4)
    sphere(t, cx, feet - 30, 12, 10, (1, 1, 1), gloss=0, flat=0.6)
    for k in range(3):
        capsule(g, cx - 6, feet - 33 + k * 3.2, cx + 6 - (k == 2) * 4, feet - 33 + k * 3.2, 0.9, INK, gloss=0, alpha=0.5)


PROP_BUILDERS = {
    "marsh_stone": ((44, 52), p_marsh_stone),
    "bubble_bloom": ((36, 56), p_bubble_bloom),
    "jellybeans": ((44, 40), p_jellybeans),
    "puff_bush": ((60, 52), p_puff_bush),
    "fizz_spring": ((44, 56), p_fizz_spring),
    "candy_bench": ((64, 48), p_candy_bench),
    "chime_bubble": ((48, 92), p_chime_bubble),
    "bubble_lamp": ((32, 80), p_bubble_lamp),
    "pebble_pops": ((36, 32), p_pebble_pops),
    "cloud_cushion": ((56, 36), p_cloud_cushion),
    "sign_bubble": ((36, 60), p_sign_bubble),
}


def make_prop(name):
    """(base, tint, gloss) images for a prop; tint/gloss are None when empty."""
    (w, h), fn = PROP_BUILDERS[name]
    b, t, g = _prop_canvases(w, h)
    fn(b, t, g, w / 2, h - 16)

    def maybe(cv):
        return cv.finish() if cv.a.max() > 0.002 else None

    return b.finish(), maybe(t), maybe(g)


# ========================================================================================== creatures
CELL = 64        # @2x: 32 world px
FEET = 48        # the ground line inside a cell (8 world px above its bottom, like every pal sheet)
COLS = 8
IDLE = 16
VIEWS = ["down", "down_right", "right", "up_right", "up"]
_FACE = {"down": (0.0, 1.0), "down_right": (0.7, 0.7), "right": (1.0, 0.0), "up_right": (0.7, -0.7), "up": (0.0, -1.0)}

CREATURE_VARIANTS = {
    "bobbling": [STRAWBERRY, MINT, LEMON],
    "puffkin": [(1.0, 0.94, 0.98), (0.88, 0.92, 1.0), (1.0, 0.90, 0.84)],
    "wobbler": [SKY, BUBBLEGUM, MINT],
    "rollypoll": [LILAC, PEACH, SKY],
    "bubblefin": [PEACH, LILAC, LEMON],
}
TEMPERAMENT = {"bobbling": "friendly", "puffkin": "shy", "wobbler": "friendly", "rollypoll": "shy", "bubblefin": "friendly"}
FLOATERS = {"puffkin", "bubblefin"}


def _face(cv, view, cx, cy, r, blink=0.0, eye_r=None):
    """Eyes, cheeks and a smile on the front of a round body, slid round toward the facing."""
    fx, fy = _FACE[view]
    if fy < -0.5:
        return  # facing away: just the back of a round head
    er = eye_r or r * 0.2
    shift = fx * r * 0.42
    lift = -r * 0.08 + (-fy * r * 0.12 if fy < 0 else 0)
    spread = r * 0.34 * (1 - 0.45 * abs(fx))
    eyes = [cx + shift - spread, cx + shift + spread] if abs(fx) < 0.9 else [cx + shift + r * 0.08]
    for ex in eyes:
        eye(cv, ex, cy + lift, er, look=(fx, max(fy, 0) * 0.5), blink=blink)
    if abs(fx) < 0.9:
        cheek(cv, cx + shift - spread - er * 0.9, cy + lift + er * 1.4, er * 0.75)
        cheek(cv, cx + shift + spread + er * 0.9, cy + lift + er * 1.4, er * 0.75)
        smile(cv, cx + shift, cy + lift + er * 1.1, er * 0.7)
    else:
        cheek(cv, cx + shift - r * 0.05, cy + lift + er * 1.5, er * 0.75)


def _hop(f):
    """A hop cycle over 8 frames: (lift px, squash) -- squat, spring, hang, land."""
    ph = f / COLS
    lift = max(0.0, math.sin(ph * math.tau * 1.0 - 0.6)) * 9.0
    squash = 0.0
    if lift < 0.5:
        squash = -0.16 * abs(math.sin(ph * math.tau * 1.0 - 0.6))
    else:
        squash = 0.08 * (lift / 9.0)
    return lift, squash


def creature_frame(species, view, f, variant, idle=False):
    """One cell. f indexes the motion cycle (0..7), or with idle=True the 16-frame resting loop."""
    color = CREATURE_VARIANTS[species][variant]
    cv = Canvas(CELL, CELL)
    cx = CELL / 2
    fx, fy = _FACE[view]
    # motion: a hop (bobbling, wobbler), a roll (rollypoll), a hover (floaters)
    if idle:
        ph = f / IDLE
        breathe = math.sin(ph * math.tau)
        lift, squash = 0.0, 0.035 * breathe
        blink = 1.0 if f in (9, 10) else (0.5 if f in (8, 11) else 0.0)
    else:
        ph = f / COLS
        lift, squash = _hop(f)
        blink = 0.0
    if species in FLOATERS:
        lift = 10.0 + 2.5 * math.sin(ph * math.tau)
        squash = 0.03 * math.sin(ph * math.tau)
    if species == "rollypoll":
        lift, squash = 0.0, (0.0 if idle else 0.02 * math.sin(ph * math.tau * 2))
    if species == "wobbler" and not idle:
        lift *= 0.4
    sh_scale = 1.0 - min(lift, 12.0) / 30.0
    if species == "bobbling":
        r = 13.0
        shadow(cv, cx, FEET, 13 * sh_scale, 4 * sh_scale, 0.28)
        rx, ry = r * (1 - squash * 0.7), r * (1 + squash)
        by = FEET - ry - lift
        # little round feet, then the ball body, an antenna with a bobble
        for side in (-1, 1):
            sphere(cv, cx + side * 6 + fx * 2, FEET - 2.5 - lift * 0.7, 4.2, 2.8, tuple(c * 0.85 for c in color), gloss=0.3)
        sway = math.sin(ph * math.tau + 1) * 2.0
        capsule(cv, cx - fx * 2, by - ry + 2, cx - fx * 2 + sway, by - ry - 7, 0.9, tuple(c * 0.85 for c in color), gloss=0)
        sphere(cv, cx - fx * 2 + sway, by - ry - 8, 2.6, 2.6, LEMON if variant != 2 else STRAWBERRY, gloss=0.8)
        sphere(cv, cx, by, rx, ry, color, gloss=0.9, spec_size=1.4)
        _face(cv, view, cx, by + 1, r, blink)
    elif species == "puffkin":
        shadow(cv, cx, FEET, 12 * sh_scale, 3.5 * sh_scale, 0.18)
        by = FEET - 12 - lift
        lobes = [(-8, 2, 7), (8, 2, 7), (0, 3, 8), (-5, -5, 7.5), (5, -6, 7.5), (0, -9, 6.5)]
        for (x, y, r) in lobes:
            sphere(cv, cx + x, by + y * (1 + squash), r, r * 0.95, color, gloss=0.25, spec_size=2.5, flat=0.1, bounce=LILAC)
        _face(cv, view, cx, by, 10.0, blink, eye_r=2.2)
    elif species == "wobbler":
        shadow(cv, cx, FEET, 15, 4.5, 0.2)
        wob = math.sin(ph * math.tau * (1 if idle else 2)) * (0.05 if idle else 0.12)
        rx, ry = 14 * (1 + wob), 12 * (1 - wob)
        by = FEET - lift
        tmp = Canvas(CELL, CELL)
        sphere(tmp, cx, by, rx, ry * 1.6, color, gloss=1.0, spec_size=1.2)
        keep = cv.Y <= by + 0.5
        cv.over(tmp.rgb / np.maximum(tmp.a, 1e-6)[..., None], tmp.a * keep * 0.78)
        # a little bubble floating inside the jelly, and a jelly foot-rim
        bubble(cv, cx - 5 + 2 * math.sin(ph * math.tau), by - 8, 2.6)
        flat_ellipse(cv, cx, by - 0.5, rx * 0.95, 2.0, tuple(min(1, c * 1.1) for c in color), 0.6)
        _face(cv, view, cx, by - ry * 0.75, 12.0, blink, eye_r=2.4)
    elif species == "rollypoll":
        shadow(cv, cx, FEET, 13, 4, 0.26)
        r = 12.5
        by = FEET - r - lift
        sphere(cv, cx, by, r, r * (1 + squash), color, gloss=0.7, spec_size=1.6)
        # banded shell: soft stripes that roll round as it moves
        roll = 0 if idle else ph * math.tau
        u, v = cv.ellipse_uv(cx, by, r, r)
        d2 = u * u + v * v
        if abs(fx) > 0.5:
            stripes = np.sin(u * 5.5 * (1 if fx > 0 else -1) + roll * 2) > 0.6
        else:
            stripes = np.sin(v * 5.5 + roll * 2 * (1 if fy > 0 else -1)) > 0.6
        cv.over(np.broadcast_to(np.array([1, 1, 1.0]), cv.rgb.shape), (stripes & (d2 < 0.92)) * 0.28)
        if fy > -0.5:
            # a little face peeking from under the shell
            hx = cx + fx * r * 0.7
            hy = by + r * 0.45 + max(fy, 0) * 1.5
            sphere(cv, hx, hy, 6.5, 5.2, (1.0, 0.92, 0.86), gloss=0.5)
            for side in ((-1, 1) if abs(fx) < 0.9 else (1,)):
                eye(cv, hx + side * 2.4 * (1 - abs(fx) * 0.6) + fx * 1.2, hy - 0.6, 1.4, blink=blink)
            cheek(cv, hx + fx * 2.5, hy + 2.0, 1.4)
    elif species == "bubblefin":
        shadow(cv, cx, FEET, 11 * sh_scale, 3 * sh_scale, 0.16)
        by = FEET - 12 - lift
        flap = math.sin(ph * math.tau * 2) * 0.5
        side = 1 if fx >= 0 else -1
        # tail behind, fins either side, a round puffy body, a bubble trailing up from its mouth
        if abs(fx) > 0.3:
            sphere(cv, cx - side * 13, by, 5, 6 + flap * 2, tuple(c * 0.92 for c in color), gloss=0.3, rot=side * 0.3)
        sphere(cv, cx - 9, by + 2, 4.5, 2.2 + flap * 1.5, tuple(c * 0.92 for c in color), gloss=0.3, rot=0.6)
        sphere(cv, cx + 9, by + 2, 4.5, 2.2 - flap * 1.5, tuple(c * 0.92 for c in color), gloss=0.3, rot=-0.6)
        sphere(cv, cx, by, 11.5, 11 * (1 + squash), color, gloss=0.9, spec_size=1.4)
        sphere(cv, cx, by - 11, 3, 2.2, tuple(c * 0.9 for c in color), gloss=0.4)
        _face(cv, view, cx, by, 11.0, blink, eye_r=2.3)
        bubble(cv, cx + fx * 13 + 2, by - 10 - (ph * 10 % 10), 2.6)
    return cv.finish()


def creature_sheet(species, variant):
    cols = COLS + IDLE
    sheet = Image.new("RGBA", (cols * CELL, len(VIEWS) * CELL), (0, 0, 0, 0))
    for r, view in enumerate(VIEWS):
        for f in range(COLS):
            sheet.paste(creature_frame(species, view, f, variant), (f * CELL, r * CELL))
        for f in range(IDLE):
            sheet.paste(creature_frame(species, view, f, variant, idle=True), ((COLS + f) * CELL, r * CELL))
    return sheet


def creature_glow(species, variant):
    return [round(min(1.0, c * 1.05 + 0.08), 2) for c in CREATURE_VARIANTS[species][variant]]


# ============================================================================================ preview
def preview(path="bobbledown.png"):
    bg = (250, 238, 240, 255)
    items = []
    for v in PUFF_VARIANTS:
        t, c = puff_tree(v)
        t.alpha_composite(c)
        items.append(t)
    for v in GUMDROP_VARIANTS:
        items.append(gumdrop(v))
    for v in LOLLI_VARIANTS:
        items.append(lolli_tree(v))
    for v in STALK_VARIANTS:
        items.append(bubble_stalk(v))
    demo = [STRAWBERRY, MINT, LILAC, LEMON, SKY]
    props = []
    for i, name in enumerate(PROP_BUILDERS):
        base, tint, gloss = make_prop(name)
        im = base.copy()
        if tint is not None:
            arr = np.asarray(tint).astype(float) / 255
            arr[..., :3] *= np.array(demo[i % len(demo)])
            im.alpha_composite(Image.fromarray((arr * 255).astype(np.uint8), "RGBA"))
        if gloss is not None:
            im.alpha_composite(gloss)
        props.append(im)
    great_t, great_c = puff_tree("bubblegum", great=True)
    great_t.alpha_composite(great_c)
    sheets = [creature_sheet(sp, 0).crop((0, 0, 24 * CELL, 5 * CELL)) for sp in CREATURE_VARIANTS]
    pad = 10
    w = max(sum(i.width + pad for i in items), sum(i.width + pad for i in props) + great_t.width, max(s.width for s in sheets)) + pad
    h = 130 + 250 + sum(s.height for s in sheets) + pad * 8
    canvas = Image.new("RGBA", (w, h), bg)
    x = pad
    for im in items:
        canvas.alpha_composite(im, (x, pad))
        x += im.width + pad
    x = pad
    y = 140
    for im in props:
        canvas.alpha_composite(im, (x, y + 160 - im.height))
        x += im.width + pad
    canvas.alpha_composite(great_t, (x, y))
    y = 400
    for s in sheets:
        canvas.alpha_composite(s, (pad, y))
        y += s.height + pad
    canvas.save(path)
    print("wrote", path)


if __name__ == "__main__":
    preview()
