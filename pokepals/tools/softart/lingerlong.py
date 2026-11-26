"""
Lingerlong -- the marble plaza's art. Smooth like Bobbledown (supersampled, no outline, baked at twice
the world resolution as "@2x" files), but where Bobbledown is candy, Lingerlong is STONE:

  * polished white marble with soft veining and a glossy highlight, whose shadows are LILAC (never grey,
    never black), and brass accents that catch a warm specular;
  * a warm key light from the upper left and a PINK bounce light from below (the floor glows pink);
  * teal palm fronds with a pink rim light along their lower edges;
  * the floor is polished, so every sprite that stands on it carries a short, soft, faded mirror copy of
    its lowest part baked BELOW its foot line (see `bake_floor`). The distance from the image's bottom
    edge to that foot line is the sprite's `foot`, recorded in data/ll_details.json.

How it is drawn: each sprite is built in a G-BUFFER (per supersampled pixel: coverage, a surface normal,
an albedo and a material), painter's order, from a few primitives -- lathes (anything round: planters,
columns, urns, bowls), bevelled slabs (anything flat-faced: arches, plinths, benches: a blurred mask's
gradient rounds every edge), tubes (brass and chrome rails) and emissive paint (foliage, pictures, lit
glass). One shading pass then lights the whole sprite consistently, which is what makes every piece look
like the same stone in the same afternoon. Soft extras (glows, halos) go on top.

The oblique view: round things are seen from above at about 25 degrees, so a horizontal circle is drawn
as an ellipse K = 0.42 times as tall as it is wide.

No unseeded randomness: every image is reproducible. Needs Pillow + numpy (tools-only).
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bobbledown as bd  # noqa: E402  (Canvas, SS, KEY: the shared soft-art core)

SS = bd.SS
K = 0.42                                   # ellipse squash of a horizontal circle
UP = np.array([0.0, -0.91, 0.42])          # a floor-facing-up surface, in screen space (y down, z at us)
FRONT = np.array([0.0, 0.42, 0.91])        # an upright face looking at the viewer
KEY = bd.KEY                               # warm key light from the upper left
HALF = KEY + np.array([0.0, 0.0, 1.0])
HALF = HALF / np.linalg.norm(HALF)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


# ------------------------------------------------------------------------------------------ palette
MARBLE = hexc("f6efe6")
LILAC_SH = hexc("b9a7d6")
BRASS = hexc("e9c46a")
PINK = hexc("f7b7d2")
PEACH = hexc("ffd3a8")
GOLD_SKY = hexc("fff0c9")
PERI = hexc("8fb8e8")
LILAC = hexc("c9b6f0")
FROND_D = hexc("3fae9a")
FROND_L = hexc("7fd8b4")
TRUNK = hexc("c98f7a")
CUSHION = hexc("f29bb5")
GLOBE = hexc("fff6e6")
GLOBE_LIT = hexc("ffe2a0")
AQUA = hexc("7fd6d8")
AQUA_L = hexc("a9e6ef")
INDIGO = hexc("2b2a5c")
VIOLET = hexc("6a4c93")
ROSE = hexc("e07a9a")
EMBER = hexc("ffb482")
TILE_A = hexc("fbf4ec")
TILE_ROSE = hexc("f3c9d3")
TILE_MINT = hexc("bfe6d8")
TILE_LILAC = hexc("d9cdf5")
TILE_PEACH = hexc("fbd9bf")
TILE_DUSK = hexc("8f86c9")
GROUT = hexc("e3cfd2")
CHROME = (0.93, 0.93, 0.97)
ROSE_MARBLE = (0.97, 0.85, 0.87)
SHADOW_COL = (0.50, 0.40, 0.68)            # contact shadows on the floor: deep lilac, never grey

# Marble's shadow is lilac: the darkest side of white marble is exactly LILAC_SH.
SH_MUL = np.array(LILAC_SH) / np.array(MARBLE)
WARM = np.array([1.035, 1.0, 0.955])
VEIN_MUL = np.array([0.90, 0.87, 0.94])     # what a vein does to the stone: a soft lilac-grey-warm
METAL_DARK = np.array([0.55, 0.40, 0.42])   # brass in shade, a warm plum

MAT_MARBLE, MAT_METAL, MAT_MATTE, MAT_WATER, MAT_EMIT = 0, 1, 2, 3, 4


def _v(c):
    return np.array(c[:3], dtype=float)


def _norm(n):
    return n / (np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# --------------------------------------------------------------------------------------------- noise
def _hash2(ix, iy, seed):
    h = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + (seed * 2246822519 & 0xFFFFFFFF)) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFF) / 65535.0


def vnoise(x, y, seed, px=None, py=None):
    """Smooth value noise; periodic with integer periods px / py when given."""
    x0 = np.floor(x)
    y0 = np.floor(y)
    fx, fy = x - x0, y - y0
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    ix0, iy0 = x0.astype(np.int64), y0.astype(np.int64)
    ix1, iy1 = ix0 + 1, iy0 + 1
    if px:
        ix0, ix1 = ix0 % px, ix1 % px
    if py:
        iy0, iy1 = iy0 % py, iy1 % py
    a = _hash2(ix0, iy0, seed)
    b = _hash2(ix1, iy0, seed)
    c = _hash2(ix0, iy1, seed)
    d = _hash2(ix1, iy1, seed)
    return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy


def fbm(x, y, seed, octaves=4, px=None, py=None):
    tot, amp, norm, f = 0.0, 1.0, 0.0, 1
    for o in range(octaves):
        tot = tot + amp * vnoise(x * f, y * f, seed + o * 101, px * f if px else None, py * f if py else None)
        norm += amp
        amp *= 0.5
        f *= 2
    return tot / norm


def vein_field(X, Y, seed=0):
    """0..1: where marble veins run (1 at a vein's core). In @2x pixel space."""
    warp = fbm(X / 30.0, Y / 30.0, seed + 7, 4)
    t = (X * 0.55 + Y * 0.85) / 52.0 + 1.7 * warp
    r = 1.0 - np.abs(np.sin(math.pi * t))
    strength = np.clip(fbm(X / 46.0, Y / 46.0, seed + 13, 2) * 1.6 - 0.35, 0, 1)
    v = r ** 14 * strength * 0.75 + 0.22 * r ** 4 * strength
    cloud = fbm(X / 16.0, Y / 16.0, seed + 29, 3) - 0.5
    return np.clip(v + 0.16 * cloud, 0.0, 1.0)


# ---------------------------------------------------------------------------------------------- blur
def _box1(a, r, axis):
    if r < 1:
        return a
    r = int(r)
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    p = np.pad(a, pad, mode="constant")
    c = np.cumsum(p, axis=axis)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return (hi - lo) / (2 * r + 1)


def blur(a, r):
    """An approximately gaussian blur of radius ~r (three box passes per axis)."""
    rr = max(1, int(round(r / 1.7)))
    for _ in range(3):
        a = _box1(a, rr, 0)
        a = _box1(a, rr, 1)
    return a


# ======================================================================================= the G-buffer
class GB:
    """Geometry first, light second. Coordinates are OUTPUT (@2x) pixels; storage is SS x that."""

    def __init__(self, w, h, seed=0):
        self.w, self.h = w, h
        self.W, self.H = w * SS, h * SS
        ys, xs = np.mgrid[0:self.H, 0:self.W]
        self.X = (xs + 0.5) / SS
        self.Y = (ys + 0.5) / SS
        self.cov = np.zeros((self.H, self.W))
        self.N = np.zeros((self.H, self.W, 3))
        self.N[..., 2] = 1.0
        self.alb = np.zeros((self.H, self.W, 3))
        self.gloss = np.zeros((self.H, self.W))
        self.vein = np.zeros((self.H, self.W))
        self.mat = np.zeros((self.H, self.W), dtype=np.int8)
        self.seed = seed

    def box(self, x0, y0, x1, y1):
        i0 = max(0, int(math.floor(y0 * SS)))
        i1 = min(self.H, int(math.ceil(y1 * SS)))
        j0 = max(0, int(math.floor(x0 * SS)))
        j1 = min(self.W, int(math.ceil(x1 * SS)))
        return (slice(i0, max(i0, i1)), slice(j0, max(j0, j1)))

    def put(self, sl, m, n, alb, mat=MAT_MARBLE, gloss=0.5, vein=1.0):
        """Overwrite the pixels `m` (a bool mask over the window `sl`) with a surface."""
        if not np.any(m):
            return
        self.cov[sl][m] = 1.0
        n = np.asarray(n, float)
        self.N[sl][m] = n[m] if n.ndim == 3 else n
        alb = np.asarray(alb, float)
        self.alb[sl][m] = alb[m] if alb.ndim == 3 else alb
        for arr, val in ((self.gloss, gloss), (self.vein, vein)):
            val = np.asarray(val, float)
            arr[sl][m] = val[m] if val.ndim == 2 else val
        self.mat[sl][m] = mat

    def put_full(self, m, n, alb, **kw):
        self.put((slice(None), slice(None)), m, n, alb, **kw)

    def erase(self, m):
        self.cov[m] = 0.0

    def mask_poly(self, pts):
        im = Image.new("L", (self.W, self.H), 0)
        ImageDraw.Draw(im).polygon([(x * SS - 0.5, y * SS - 0.5) for x, y in pts], fill=255)
        return np.asarray(im) > 127

    def mask_ellipse(self, cx, cy, rx, ry):
        return ((self.X - cx) / rx) ** 2 + ((self.Y - cy) / ry) ** 2 <= 1.0

    def mask_rrect(self, x0, y0, x1, y1, r):
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
        dx = np.maximum(np.abs(self.X - cx) - hx, 0)
        dy = np.maximum(np.abs(self.Y - cy) - hy, 0)
        return dx * dx + dy * dy <= r * r

    # ------------------------------------------------------------------------------- the shading pass
    def render(self, neutral=False):
        """Light every covered pixel; returns a bd.Canvas (premultiplied) ready for overlays."""
        cv = bd.Canvas(self.w, self.h)
        idx = self.cov > 0
        if not idx.any():
            return cv
        n = _norm(self.N[idx])
        alb = self.alb[idx]
        mat = self.mat[idx]
        gloss = self.gloss[idx]
        vein = self.vein[idx]
        X, Y = self.X[idx], self.Y[idx]
        out = np.zeros_like(alb)
        lam = n @ KEY
        wrap = smooth(-0.62, 0.62, lam)
        down = np.clip(n[:, 1], 0, 1)
        nz = np.clip(n[:, 2], 0, 1)
        ndh = np.clip(n @ HALF, 0, 1)
        rim = np.clip(1 - nz, 0, 1) ** 2.2
        env = np.where((n[:, 1] < 0)[:, None], _v(LILAC) * 0.6 + _v(PERI) * 0.4, _v(PINK))
        # ---- marble (and the tint layers' neutral matte)
        for code in (MAT_MARBLE, MAT_MATTE):
            s = mat == code
            if not s.any():
                continue
            b = alb[s]
            if neutral:
                shadow = b * 0.70
                bounce = b * 0.92
            else:
                shadow = b * SH_MUL
                bounce = _v(PINK) * (0.55 + 0.45 * b)
            lit = np.clip(b * WARM, 0, 1)
            w = wrap[s][:, None]
            rgb = shadow + (lit - shadow) * w
            rgb = rgb + (bounce - rgb) * (0.36 * smooth(0.25, 1.0, down[s]))[:, None]
            if code == MAT_MARBLE and not neutral:
                vf = vein_field(X[s], Y[s], self.seed) * vein[s]
                rgb = rgb * (1 - vf[:, None] * (1 - VEIN_MUL))
                rgb = rgb + (env[s] - rgb) * (0.22 * rim[s])[:, None]
                sp = gloss[s] * (ndh[s] ** 70 * 0.95 + ndh[s] ** 9 * 0.10)
                # polish: one broad, soft diagonal sheen across flat faces (a window of sky in the stone)
                c0 = 0.30 * (self.w + 0.8 * self.h)
                band = np.exp(-((X[s] + 0.8 * Y[s] - c0) / (0.16 * (self.w + 0.8 * self.h))) ** 2)
                sp = sp + gloss[s] * 0.30 * band * smooth(0.75, 0.95, nz[s])
            else:
                sp = gloss[s] * (ndh[s] ** 14 * 0.35 + ndh[s] ** 4 * 0.06)
            rgb = rgb + (1 - rgb) * sp[:, None]
            out[s] = rgb
        # ---- brass and chrome: mostly reflection, a dark warm core, a hot highlight
        s = mat == MAT_METAL
        if s.any():
            b = alb[s]
            w = wrap[s][:, None]
            dark = METAL_DARK * b / np.maximum(_v(BRASS), 0.3) if not neutral else b * 0.5
            dark = np.clip(dark, 0, 1)
            light = np.clip(b * 1.08 + 0.05, 0, 1)
            rgb = dark + (light - dark) * w ** 0.8
            envm = env[s] * (0.55 + 0.45 * b)
            rgb = rgb + (envm - rgb) * (0.45 * rim[s] + 0.25 * down[s] ** 1.5)[:, None]
            sp = gloss[s] * (ndh[s] ** 40 * 1.0 + ndh[s] ** 8 * 0.18)
            rgb = rgb + (1 - rgb) * sp[:, None]
            out[s] = rgb
        # ---- water: a still, glossy, shallow aqua
        s = mat == MAT_WATER
        if s.any():
            b = alb[s]
            rgb = b * (0.92 + 0.12 * wrap[s])[:, None]
            out[s] = rgb
        # ---- emissive: the albedo IS the colour (foliage pre-lit, pictures, lit glass)
        s = mat == MAT_EMIT
        if s.any():
            out[s] = alb[s]
        full = np.zeros((self.H, self.W, 3))
        full[idx] = np.clip(out, 0, 1)
        cv.over(full, self.cov)
        return cv


# ============================================================================================ primitives
def radial_normal(u, w, beta=0.0):
    """The normal of a round surface at horizontal parameter u (-1..1 across), front-ness w, tilted
    `beta` radians toward up (a surface narrowing as it rises faces upward)."""
    radial = np.stack([u, K * w, 0.91 * w], axis=-1)
    if np.ndim(beta) == 0:
        cb, sb = math.cos(beta), math.sin(beta)
        return radial * cb + UP * sb
    return radial * np.cos(beta)[..., None] + UP * np.sin(beta)[..., None]


def lathe(gb, cx, cy, prof, alb=MARBLE, mat=MAT_MARBLE, gloss=0.55, vein=1.0, cap=True, k=K, flutes=0,
          flute_depth=0.25, bands=None):
    """A round thing standing on the floor: `prof` lists (height, radius) pairs in @2x px, height measured
    up from cy (the centre of its lowest ellipse). Drawn as a stack of shaded ellipses, bottom to top.
    `bands` = [(h0, h1, alb, mat, gloss)] repaints a height range (a brass band)."""
    hs = np.array([p[0] for p in prof], float)
    rs = np.array([p[1] for p in prof], float)
    zs = np.arange(hs[0], hs[-1] + 1e-6, 1.0 / SS)
    rr = np.interp(zs, hs, rs)
    dr = np.gradient(rr, zs) if len(zs) > 1 else np.zeros_like(zs)
    for z, r, d in zip(zs, rr, dr):
        if r <= 0.08:
            continue
        yc = cy - z
        sl = gb.box(cx - r - 1, yc - r * k - 1, cx + r + 1, yc + r * k + 1)
        X, Y = gb.X[sl], gb.Y[sl]
        u = (X - cx) / r
        v = (Y - yc) / (r * k)
        d2 = u * u + v * v
        m = d2 <= 1.0
        if not m.any():
            continue
        uu = np.clip(u, -1, 1)
        w = np.sqrt(np.clip(1 - uu * uu, 0, 1))
        beta = math.atan(-d * 0.9)
        n = radial_normal(uu, w, beta)
        if flutes:
            phi = np.arcsin(uu)
            n = n + np.stack([np.sin(phi * flutes) * flute_depth, np.zeros_like(u), np.zeros_like(u)], -1)
        t = smooth(0.70, 0.97, np.sqrt(d2))
        n = n * t[..., None] + UP * (1 - t[..., None])
        a, mt, gl = alb, mat, gloss
        if bands:
            for (h0, h1, ba, bm, bg) in bands:
                if h0 <= z <= h1:
                    a, mt, gl = ba, bm, bg
        gb.put(sl, m, n, a, mat=mt, gloss=gl, vein=vein if mt == MAT_MARBLE else 0.0)
    if cap and rr[-1] > 0.5:
        r = rr[-1]
        yc = cy - zs[-1]
        sl = gb.box(cx - r - 1, yc - r * k - 1, cx + r + 1, yc + r * k + 1)
        u = (gb.X[sl] - cx) / r
        v = (gb.Y[sl] - yc) / (r * k)
        d = np.sqrt(u * u + v * v)
        m = d <= 1.0
        # a softly rounded top edge
        e = smooth(0.78, 1.0, d)
        n = UP[None, None, :] * (1 - e[..., None]) + radial_normal(np.clip(u, -1, 1), np.clip(v, -1, 1)) * e[..., None]
        gb.put(sl, m, n, alb, mat=mat, gloss=gloss, vein=vein)


def bevel_normals(mask, face, radius, edge=1.0):
    """Normals for a flat face (`face` normal) whose edges round off over ~radius @2x px."""
    rs = radius * SS
    B = blur(mask.astype(float), rs)
    gy, gx = np.gradient(B)
    s = edge * 2.6 * rs
    n = np.zeros(mask.shape + (3,))
    n[...] = face
    n[..., 0] -= gx * s
    n[..., 1] -= gy * s
    return _norm(n)


def slab(gb, mask, face=FRONT, radius=2.0, edge=1.0, alb=MARBLE, mat=MAT_MARBLE, gloss=0.5, vein=1.0):
    n = bevel_normals(mask, face, radius, edge)
    gb.put_full(mask, n, alb, mat=mat, gloss=gloss, vein=vein)


def puffy(gb, mask, radius, face=FRONT, alb=(1, 1, 1), mat=MAT_MATTE, gloss=0.4, edge=1.6):
    """A cushion: a slab whose rounding reaches well into the middle."""
    slab(gb, mask, face=face, radius=radius, edge=edge, alb=alb, mat=mat, gloss=gloss, vein=0.0)


def tube(gb, pts, r, alb=BRASS, mat=MAT_METAL, gloss=0.8):
    """A round rod along a polyline (each segment a capsule, painter's order)."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        sl = gb.box(min(x0, x1) - r - 1, min(y0, y1) - r - 1, max(x0, x1) + r + 1, max(y0, y1) + r + 1)
        X, Y = gb.X[sl], gb.Y[sl]
        ax, ay = x1 - x0, y1 - y0
        L2 = max(ax * ax + ay * ay, 1e-9)
        t = np.clip(((X - x0) * ax + (Y - y0) * ay) / L2, 0, 1)
        dx, dy = (X - x0 - ax * t) / r, (Y - y0 - ay * t) / r
        d2 = dx * dx + dy * dy
        m = d2 <= 1.0
        n = np.stack([dx, dy, np.sqrt(np.clip(1 - d2, 0, 1))], -1)
        gb.put(sl, m, n, alb, mat=mat, gloss=gloss, vein=0.0)


def sphere(gb, cx, cy, rx, ry, alb=MARBLE, mat=MAT_MARBLE, gloss=0.6, vein=1.0, clip=None, rot=0.0):
    r = max(rx, ry)
    sl = gb.box(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1)
    dx, dy = gb.X[sl] - cx, gb.Y[sl] - cy
    c, s_ = math.cos(rot), math.sin(rot)
    u = (dx * c + dy * s_) / rx
    v = (-dx * s_ + dy * c) / ry
    d2 = u * u + v * v
    m = d2 <= 1.0
    if clip is not None:
        m = m & clip[sl]
    # back into screen space
    nx, ny = u * c - v * s_, u * s_ + v * c
    n = np.stack([nx, ny, np.sqrt(np.clip(1 - d2, 0, 1))], -1)
    gb.put(sl, m, n, alb, mat=mat, gloss=gloss, vein=vein)


def paint_rgba(gb, rgba, mat=MAT_EMIT):
    """Write an SS-resolution straight RGBA float array (pre-lit colour) into the G-buffer."""
    m = rgba[..., 3] > 0.5
    gb.put_full(m, FRONT, rgba[..., :3], mat=mat, gloss=0.0, vein=0.0)


def emit(gb, mask, color):
    gb.put_full(mask, FRONT, np.broadcast_to(_v(color), gb.N.shape) if np.ndim(color) == 1 else color,
                mat=MAT_EMIT, gloss=0.0, vein=0.0)


# --------------------------------------------------------------------------------------- soft overlays
def glow(cv, cx, cy, r, color, alpha):
    """A soft additive-looking halo (composited over)."""
    d = np.sqrt((cv.X - cx) ** 2 + (cv.Y - cy) ** 2) / r
    a = np.clip(1 - d, 0, 1) ** 2.2 * alpha
    cv.over(np.broadcast_to(_v(color), cv.rgb.shape), a)


def soft_shadow(cv, cx, cy, rx, ry, alpha=0.20, color=SHADOW_COL):
    u = (cv.X - cx) / rx
    v = (cv.Y - cy) / ry
    d2 = u * u + v * v
    cv.over(np.broadcast_to(_v(color), cv.rgb.shape), np.exp(-d2 * 2.4) * (d2 < 2.4) * alpha)


# =================================================================================== the polished floor
def _arr(img):
    return np.asarray(img).astype(float) / 255.0


def _img(arr):
    return Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def _over(top, bottom):
    """Straight-alpha 'over' of two float RGBA arrays."""
    ta, ba = top[..., 3:4], bottom[..., 3:4]
    oa = ta + ba * (1 - ta)
    rgb = (top[..., :3] * ta + bottom[..., :3] * ba * (1 - ta)) / np.maximum(oa, 1e-6)
    return np.concatenate([rgb, oa], -1)


def reflection(img, foot_px, length_px, strength=0.30):
    """The mirror copy of an image's lowest `length_px` rows above its foot, hung below the foot and faded
    out: a soft, short reflection in polished stone. Returns a float RGBA array the size of `img`."""
    a = _arr(img)
    H = a.shape[0]
    out = np.zeros_like(a)
    L = int(min(length_px, foot_px, H - foot_px))
    if L <= 0:
        return out
    src = a[foot_px - L:foot_px][::-1].copy()
    t = (np.arange(L) + 0.5) / L
    fade = strength * (1 - t) ** 1.7
    src[..., 3] *= fade[:, None]
    # the stone's own colour seeps in, and the copy is softened a touch (premultiplied blur)
    src[..., :3] = src[..., :3] * 0.82 + np.array([0.98, 0.93, 0.97]) * 0.18
    pm = src[..., :3] * src[..., 3:4]
    al = src[..., 3]
    pm = np.stack([_box1(_box1(pm[..., c], 1, 0), 1, 1) for c in range(3)], -1)
    al = _box1(_box1(al, 1, 0), 1, 1)
    src = np.concatenate([pm / np.maximum(al[..., None], 1e-6), al[..., None]], -1)
    out[foot_px:foot_px + L] = src
    return out


def bake_floor(img, foot_px, length_px, shadow=None, strength=0.30):
    """Reflection, then the soft contact shadow, then the thing itself."""
    refl = reflection(img, foot_px, length_px, strength)
    base = refl
    if shadow is not None:
        w, h = img.size
        cv = bd.Canvas(w, h)
        cx, cy, rx, ry, al = shadow
        soft_shadow(cv, cx, cy, rx, ry, al)
        base = _over(_arr(cv.finish()), base)
    return _img(_over(_arr(img), base))


# ==================================================================================== world sizes (px)
# Every size below is @2x pixels (twice world px). FOOT_TALL / FOOT_PROP are the reflection margins.
FOOT_TALL = 24   # 12 world px
FOOT_PROP = 16   # 8 world px (the margin every smooth @2x prop already uses, see WorldArt._blit_soft_prop)
REFLECT_TALL = 22
REFLECT_PROP = 15


# =========================================================================================== palms
def _proj(cx, cy, horiz, fwd, height):
    """A 3D point (x right, fwd toward the viewer, height up) relative to (cx, cy) on screen."""
    return cx + horiz, cy + fwd * K - height * 0.91


def _bbox(A, pad):
    rows = np.where(A.any(axis=1))[0]
    cols = np.where(A.any(axis=0))[0]
    if len(rows) == 0:
        return None
    return (slice(max(0, rows[0] - pad), min(A.shape[0], rows[-1] + pad + 1)),
            slice(max(0, cols[0] - pad), min(A.shape[1], cols[-1] + pad + 1)))


def _shift(A, dy, dx):
    out = np.zeros_like(A)
    H, W = A.shape
    out[max(0, dy):H + min(0, dy), max(0, dx):W + min(0, dx)] = A[max(0, -dy):H - max(0, dy), max(0, -dx):W - max(0, dx)]
    return out


def frond_layer(W, H, crown, fronds, seed, scale=1.0):
    """Draw a palm's fronds into an SS-res straight RGBA float array, far fronds first. Each frond is its own
    layer: drawn with PIL as leaflet polygons, smoothed, lit (a teal gradient toward the tip, a warm top edge,
    a PINK rim along its lower edge) and laid over the ones behind it with a soft shadow, so every frond
    separates from the next by light alone. `fronds` lists (phi, length, rise, droop); phi is the frond's
    bearing (0 = toward the viewer); lengths in @2x px."""
    cx, cy = crown
    rng = np.random.default_rng(seed)
    acc = np.zeros((H * SS, W * SS, 3))
    acc_a = np.zeros((H * SS, W * SS))
    deep = np.array([0.24, 0.42, 0.56])
    pad = int(4 * SS)

    def P(h, f, z):
        x, y = _proj(cx, cy, h, f, z)
        return (x * SS - 0.5, y * SS - 0.5)

    order = sorted(fronds, key=lambda fr: math.cos(fr[0]))
    for k, (phi, L, rise, droop) in enumerate(order):
        im = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        sx, sf = math.sin(phi), math.cos(phi)
        px_, pf_ = math.cos(phi), -math.sin(phi)          # across the frond, in the floor plane
        n_seg = 22
        spine = []
        for i in range(n_seg + 1):
            s = i / n_seg
            spine.append((sx * L * s, sf * L * s, L * (rise * s - droop * s * s)))
        # fronds toward the light and toward the viewer are lighter; the far ones sit in the crown's shade
        facing = 0.5 + 0.5 * (-sx * 0.55 + sf * 0.45)
        for i in range(2, n_seg + 1):
            s = i / n_seg
            hx, hf, hz = spine[i]
            ll = L * 0.38 * (math.sin(math.pi * min(1.0, 0.10 + 0.95 * s)) ** 0.7) * (1.05 - 0.3 * s)
            ll *= 0.9 + 0.2 * rng.random()
            for side in (-1, 1):
                ang = 0.80 + 0.18 * rng.random()             # leaflets sweep toward the tip
                dh = side * px_ * math.cos(ang) + sx * math.sin(ang)
                df = side * pf_ * math.cos(ang) + sf * math.sin(ang)
                dz = -0.42 - 0.3 * s                         # and hang a little
                ln = math.sqrt(dh * dh + df * df + dz * dz)
                dh, df, dz = dh / ln, df / ln, dz / ln
                b = P(hx, hf, hz)
                t = P(hx + dh * ll, hf + df * ll, hz + dz * ll)
                mpt = P(hx + dh * ll * 0.35, hf + df * ll * 0.35, hz + dz * ll * 0.35)
                ex, ey = t[0] - b[0], t[1] - b[1]
                el = math.hypot(ex, ey) + 1e-6
                nx, ny = -ey / el, ex / el
                wd = (1.5 + 0.8 * (1 - s)) * SS * scale
                lit = -dh * 0.5 + 0.5 * side * (-px_ * 0.5)
                kl = float(np.clip(0.18 + 0.45 * s + 0.45 * facing + 0.2 * lit, 0, 1))
                col = _v(FROND_D) * (1 - kl) + _v(FROND_L) * kl
                c1 = tuple(int(255 * c) for c in col * 0.96)
                c2 = tuple(int(255 * min(1, c * 1.04 + 0.03)) for c in col)
                q1 = (mpt[0] + nx * wd, mpt[1] + ny * wd)
                q2 = (mpt[0] - nx * wd, mpt[1] - ny * wd)
                dr.polygon([b, q1, q2], fill=c1 + (255,))
                dr.polygon([q1, t, q2], fill=c2 + (255,))
        pts = [P(*q) for q in spine[:-2]]
        for i, (a0, a1) in enumerate(zip(pts, pts[1:])):
            wdt = max(1, int((1.5 - 0.9 * i / n_seg) * SS * scale))
            dr.line([a0, a1], fill=(int(255 * 0.66), int(255 * 0.88), int(255 * 0.72), 255), width=wdt)
        arr = np.asarray(im).astype(float) / 255.0
        A = (arr[..., 3] > 0.5).astype(float)
        bb = _bbox(A, pad)
        if bb is None:
            continue
        a = A[bb]
        rgb = arr[bb][..., :3]
        pm = rgb * a[..., None]
        bl = blur(a, 1.0 * SS)
        rgb = np.stack([blur(pm[..., c], 1.0 * SS) for c in range(3)], -1) / np.maximum(bl[..., None], 1e-4)
        d = int(1.8 * SS)
        below = _shift(a, -d, 0)          # below[y] = a[y + d]
        above = _shift(a, d, d)
        rim_low = blur(a * (1 - below), 0.8 * SS) * a
        rim_top = blur(a * (1 - above), 0.8 * SS) * a
        rgb = rgb + (_v(PINK) - rgb) * np.clip(rim_low * 1.3, 0, 0.8)[..., None]
        rgb = rgb + (_v((1.0, 0.97, 0.86)) - rgb) * np.clip(rim_top * 0.6, 0, 0.5)[..., None]
        # this frond's soft shadow on the fronds already drawn behind it (the sun is upper left)
        sh = blur(_shift(a, int(2.5 * SS), int(1.5 * SS)), 1.6 * SS) * acc_a[bb] * (1 - a)
        acc[bb] = acc[bb] + (deep - acc[bb]) * (0.35 * sh)[..., None]
        acc[bb] = np.where(a[..., None] > 0, rgb, acc[bb])
        acc_a[bb] = np.maximum(acc_a[bb], a)
    # a lilac-teal hush in the heart of the crown (ambient occlusion)
    Ys, Xs = np.mgrid[0:acc_a.shape[0], 0:acc_a.shape[1]]
    dc = np.hypot(Xs / SS - cx, (Ys / SS - cy) * 1.6) / (fronds[0][1] * 0.45)
    occ = np.clip(1 - dc, 0, 1) ** 1.5 * 0.40
    acc = acc + (deep - acc) * occ[..., None]
    return np.concatenate([np.clip(acc, 0, 1), acc_a[..., None]], -1)


def palm_trunk(gb, base_x, base_y, top_x, top_y, r0, r1, seed=0):
    """A ringed, gently curving trunk from (base) to (top), as horizontal rows of a cylinder."""
    y0, y1 = top_y, base_y
    sl = gb.box(min(base_x, top_x) - r0 - 4, y0 - 2, max(base_x, top_x) + r0 + 4, y1 + 1)
    X, Y = gb.X[sl], gb.Y[sl]
    t = np.clip((base_y - Y) / (base_y - top_y), 0, 1)            # 0 at base, 1 at the crown
    xc = base_x + (top_x - base_x) * (t ** 1.6)
    slope = (top_x - base_x) * 1.6 * np.maximum(t, 1e-3) ** 0.6 / (base_y - top_y)
    r = r0 + (r1 - r0) * t ** 0.8
    u = (X - xc) / r
    m = (np.abs(u) <= 1.0) & (Y >= y0) & (Y <= y1)
    w = np.sqrt(np.clip(1 - u * u, 0, 1))
    n = np.stack([u - slope * w * 0.3, np.zeros_like(u) + 0.10, w * 0.95], -1)
    # leaf-scar rings: each ring is a little shelf, dark under, lit on top
    period = 5.2
    ph = ((base_y - Y) + 1.6 * u * u + 0.8 * u) / period
    fr = ph - np.floor(ph)
    n[..., 1] += 0.32 * np.sin(fr * math.tau)
    alb = np.broadcast_to(_v(TRUNK), X.shape + (3,)).copy()
    alb *= (0.95 + 0.06 * np.cos(fr * math.tau))[..., None]
    gb.put(sl, m, n, alb, mat=MAT_MARBLE, gloss=0.12, vein=0.0)


def round_planter(gb, cx, foot_y, r, h, band=0.78, soil=True):
    """A white marble planter with a brass band near its lip. foot_y is its front-bottom edge."""
    cy = foot_y - r * K
    prof = [(0, r * 0.80), (h * 0.12, r * 0.86), (h * 0.55, r * 0.97), (h * 0.82, r * 1.0),
            (h * 0.86, r * 1.07), (h * 1.0, r * 1.07)]
    lathe(gb, cx, cy, prof, gloss=0.6, cap=False,
          bands=[(h * band - h * 0.07, h * band, BRASS, MAT_METAL, 0.9)])
    # the lip: an inner ring and soil inside it
    top = cy - h
    ri = r * 0.90
    m_out = gb.mask_ellipse(cx, top, r * 1.07, r * 1.07 * K)
    m_in = gb.mask_ellipse(cx, top, ri, ri * K)
    lip = m_out & ~m_in
    slab(gb, lip, face=UP, radius=1.2, edge=0.8, gloss=0.6)
    if soil:
        sl = (slice(None), slice(None))
        n = np.broadcast_to(UP, gb.N.shape)
        # moss: soft mint with a darker ring at the back wall
        d = np.sqrt(((gb.X - cx) / ri) ** 2 + ((gb.Y - top) / (ri * K)) ** 2)
        moss = _v((0.62, 0.80, 0.70)) * (0.85 + 0.15 * (1 - d))[..., None]
        moss = moss * (1 - 0.25 * smooth(0.6, 1.0, d) * (gb.Y < top))[..., None]
        gb.put(sl, m_in, n, moss, mat=MAT_MATTE, gloss=0.05, vein=0.0)
    return top


PALM_VARIANTS = {
    # lean (px at the crown), trunk height (px), frond count, frond length (px), seed, frond phase
    "a": (6, 140, 10, 56, 11, 0.10),
    "b": (-7, 150, 9, 56, 23, 0.45),
    "c": (1, 124, 11, 54, 37, 0.80),
}


def _fronds(n, L, phase, seed):
    rng = np.random.default_rng(seed)
    out = []
    for i in range(n):
        phi = phase + i * math.tau / n + rng.uniform(-0.18, 0.18)
        front = math.cos(phi)
        Lk = L * rng.uniform(0.88, 1.08) * (0.92 if front < -0.3 else 1.0)
        rise = rng.uniform(0.70, 1.0) + (0.25 if front < -0.3 else 0.0)
        droop = rng.uniform(1.25, 1.6)
        out.append((phi, Lk, rise, droop))
    return out


def palm(variant, great=False):
    if great:
        w, h = 224, 384
        lean, th, nf, L, seed, phase = (8, 236, 13, 96, 101, 0.3)
        pr, ph, r0, r1 = 46, 44, 13, 9
    else:
        w, h = 128, 248
        lean, th, nf, L, seed, phase = PALM_VARIANTS[variant]
        pr, ph, r0, r1 = 26, 32, 8.5, 5.6
    foot = h - FOOT_TALL
    cx = w / 2
    gb = GB(w, h, seed=seed)
    top = round_planter(gb, cx, foot, pr, ph)
    crown = (cx + lean, top - th)
    palm_trunk(gb, cx, top + 2, crown[0], crown[1], r0, r1, seed)
    # a ruff of old frond bases at the crown, on the trunk layer
    for k in range(5):
        a = -0.9 + k * 0.45
        sphere(gb, crown[0] + math.sin(a) * r1 * 1.3, crown[1] + 3 + abs(math.cos(a)) * 1.5, r1 * 0.9, r1 * 0.75,
               alb=(0.74, 0.55, 0.50), mat=MAT_MARBLE, gloss=0.1, vein=0.0)
    trunk_cv = gb.render()
    trunk = bake_floor(trunk_cv.finish(), foot, REFLECT_TALL, shadow=(cx + 3, foot - 3, pr * 1.05, pr * 0.34, 0.20))
    fr = _fronds(nf, L, phase, seed)
    layer = frond_layer(w, h, crown, fr, seed, scale=1.5 if great else 1.0)
    cgb = GB(w, h, seed=seed)
    paint_rgba(cgb, layer)
    canopy = cgb.render().finish()
    return trunk, canopy


# =========================================================================================== columns
def column(broken=False):
    w = 56
    h = (44 + 12) * 2 if broken else (92 + 12) * 2
    foot = h - FOOT_TALL
    cx = w / 2
    gb = GB(w, h, seed=5 if broken else 3)
    # a square-ish plinth (drawn as a slab with a top face), then a round torus base
    pw = 26
    front = gb.mask_rrect(cx - pw, foot - 12, cx + pw, foot, 1.5)
    topf = gb.mask_rrect(cx - pw, foot - 12 - 9, cx + pw, foot - 12 + 0.5, 1.5)
    slab(gb, topf, face=UP, radius=1.4)
    slab(gb, front, face=FRONT, radius=1.6)
    cy = foot - 12 - 4.5
    shaft_r = 15.5
    total = h - FOOT_TALL - 12 - 6
    if broken:
        shaft_top = total - 6
        lathe(gb, cx, cy, [(0, 22), (3, 22.5), (6, 19), (8, 17), (10, shaft_r + 0.5), (shaft_top, shaft_r)],
              flutes=9, cap=True, gloss=0.5)
        # the break: a jagged top, cut away with a polygon, then a rough lilac-shadowed face
        # the break: a tilted, jagged plane. Above its far edge the stone is gone; between its far and near
        # edges the rough fracture face shows, a warmer, matte stone.
        ty = cy - shaft_top + 12
        u = np.clip((gb.X - cx) / (shaft_r + 0.5), -1, 1)
        wv = np.sqrt(np.clip(1 - u * u, 0, 1))
        jag = (fbm(gb.X / 2.2, np.zeros_like(gb.X), 9, 3) - 0.5) * 7 + np.abs(np.sin(gb.X * 0.9)) * 2.0
        centre = ty + (gb.X - cx) * 0.45
        y_far = centre - shaft_r * K * wv + jag * 0.5
        y_near = centre + shaft_r * K * wv + jag
        gb.erase(gb.Y < y_far)
        face_m = (gb.Y >= y_far) & (gb.Y < y_near) & (gb.cov > 0)
        rough = 0.35 * (fbm(gb.X / 2.0, gb.Y / 2.0, 4, 3) - 0.5)
        n = _norm(np.broadcast_to(_norm(UP + np.array([0.35, 0, 0])), gb.N.shape)
                  + np.stack([rough, rough * 0.6, np.zeros_like(rough)], -1))
        gb.put_full(face_m, n, ROSE_MARBLE, gloss=0.05, vein=0.4)
        # a fallen chip at the foot
        sphere(gb, cx + 20, foot - 4, 4.5, 3, alb=MARBLE, gloss=0.4)
    else:
        neck = total - 34
        lathe(gb, cx, cy, [(0, 22), (3, 22.5), (6, 19), (8, 17), (10, shaft_r + 0.5), (neck * 0.35, shaft_r),
                           (neck, shaft_r - 2.0), (neck + 0.01, shaft_r - 1.0), (neck + 4, shaft_r - 1.0),
                           (neck + 4.01, shaft_r - 2.0), (neck + 6, shaft_r - 2.0)],
              flutes=9, cap=False, gloss=0.5,
              bands=[(neck, neck + 4, BRASS, MAT_METAL, 0.9)])
        # the capital: a cushion (echinus) and a square slab (abacus) with a lit top face
        lathe(gb, cx, cy - neck - 6, [(0, shaft_r - 1), (4, shaft_r + 3), (7, shaft_r + 6), (8.5, shaft_r + 6.5)],
              cap=True, gloss=0.6)
        ay = cy - neck - 6 - 8.5
        aw = 25
        front = gb.mask_rrect(cx - aw, ay - 4, cx + aw, ay + 5, 1.2)
        topf = gb.mask_rrect(cx - aw, ay - 4 - 9, cx + aw, ay - 3.5, 1.2)
        slab(gb, topf, face=UP, radius=1.2)
        slab(gb, front, face=FRONT, radius=1.4)
    img = gb.render().finish()
    return bake_floor(img, foot, REFLECT_TALL, shadow=(cx + 2, foot - 2, 28, 7, 0.18))


# ============================================================================================== arch
ARCH_W, ARCH_H = 192, 264      # 96 x 132 world
ARCH_FOOT = ARCH_H - FOOT_TALL
DOOR_X0, DOOR_X1 = 44, 148     # the doorway: 52 world wide ...
DOOR_TOP = ARCH_FOOT - 168     # ... 84 world tall
DOOR_R = (DOOR_X1 - DOOR_X0) / 2
DOOR_SPRING = DOOR_TOP + DOOR_R
ARCH_DOOR_W, ARCH_DOOR_H = (DOOR_X1 - DOOR_X0) // 2, (ARCH_FOOT - DOOR_TOP) // 2


def doorway_mask(gb, grow=0.0):
    cx = ARCH_W / 2
    rect = (gb.X >= DOOR_X0 - grow) & (gb.X <= DOOR_X1 + grow) & (gb.Y >= DOOR_SPRING) & (gb.Y <= ARCH_FOOT + grow)
    circ = (gb.X - cx) ** 2 + (gb.Y - DOOR_SPRING) ** 2 <= (DOOR_R + grow) ** 2
    return rect | circ


def arch():
    w, h, foot = ARCH_W, ARCH_H, ARCH_FOOT
    cx = w / 2
    gb = GB(w, h, seed=17)
    door = doorway_mask(gb)
    # the body: piers + spandrels + frieze, one face
    body = gb.mask_rrect(8, 34, w - 8, foot, 2.0) & ~door
    slab(gb, body, radius=2.6, edge=0.9, gloss=0.45)
    # the archivolt: a raised band round the opening, carrying down the piers as pilasters
    band_out = doorway_mask(gb, 11)
    band = band_out & ~door & (gb.Y <= foot - 22)
    slab(gb, band, radius=2.4, edge=1.1, gloss=0.65)
    # impost bands where the arch springs (a brass line on a marble moulding)
    for x0, x1 in ((6, DOOR_X0 + 1), (DOOR_X1 - 1, w - 6)):
        mould = gb.mask_rrect(x0, DOOR_SPRING - 4, x1, DOOR_SPRING + 5, 1.6)
        slab(gb, mould, radius=1.6, edge=1.0, gloss=0.7)
        line = gb.mask_rrect(x0 + 1, DOOR_SPRING + 1.5, x1 - 1, DOOR_SPRING + 3.5, 0.8)
        slab(gb, line, radius=0.9, alb=BRASS, mat=MAT_METAL, gloss=0.95)
    # pier bases: wider blocks with a lit top
    for x0, x1 in ((3, DOOR_X0 + 4), (DOOR_X1 - 4, w - 3)):
        topf = gb.mask_rrect(x0, foot - 30, x1, foot - 21, 1.4)
        slab(gb, topf, face=UP, radius=1.2, gloss=0.6)
        front = gb.mask_rrect(x0, foot - 22, x1, foot, 1.8)
        slab(gb, front, radius=1.8, gloss=0.5)
    # keystone
    kx = cx
    key = gb.mask_poly([(kx - 9, DOOR_TOP - 14), (kx + 9, DOOR_TOP - 14), (kx + 6.5, DOOR_TOP + 6), (kx - 6.5, DOOR_TOP + 6)])
    slab(gb, key, radius=1.8, edge=1.2, gloss=0.7)
    sphere(gb, kx, DOOR_TOP - 4, 3.0, 3.0, alb=BRASS, mat=MAT_METAL, gloss=1.0)
    # frieze with a brass line, then the cornice: a lit top strip over a moulded front
    fr_line = gb.mask_rrect(10, 46, w - 10, 48.5, 0.8)
    slab(gb, fr_line, radius=0.9, alb=BRASS, mat=MAT_METAL, gloss=0.95)
    corn_f = gb.mask_rrect(2, 24, w - 2, 37, 2.0)
    slab(gb, corn_f, radius=2.2, edge=1.0, gloss=0.6)
    corn_t = gb.mask_rrect(2, 12, w - 2, 25, 2.0)
    slab(gb, corn_t, face=UP, radius=1.6, gloss=0.6)
    # small brass rosettes on the spandrels
    for x in (24, w - 24):
        sphere(gb, x, 66, 3.6, 3.6, alb=BRASS, mat=MAT_METAL, gloss=1.0)
    img = gb.render().finish()
    return bake_floor(img, foot, REFLECT_TALL, shadow=(cx + 3, foot - 2, 100, 10, 0.16))


def _sky(Y, y0, y1, stops):
    """A vertical gradient through colour stops [(t, rgb)] between rows y0..y1."""
    t = np.clip((Y - y0) / (y1 - y0), 0, 1)
    ts = [s[0] for s in stops]
    out = np.zeros(Y.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(t, ts, [s[1][c] for s in stops])
    return out


def _checker_floor(X, Y, cx, horizon, ta, tb, tile=26.0, cam=26.0, grout=None):
    """A perspective marble checker below `horizon`: returns (rgb, depth)."""
    dy = np.maximum(Y - horizon, 0.35)
    z = cam * 60.0 / dy                    # depth
    xf = (X - cx) * z / 60.0
    u, v = xf / tile, z / tile
    check = ((np.floor(u) + np.floor(v)) % 2) == 0
    rgb = np.where(check[..., None], _v(ta), _v(tb))
    if grout is not None:
        fu, fv = u - np.floor(u), v - np.floor(v)
        g = ((np.minimum(fu, 1 - fu) < 0.025 * (1 + z / 80)) | (np.minimum(fv, 1 - fv) < 0.025 * (1 + z / 80)))
        rgb = np.where(g[..., None], rgb * 0.92 + _v(grout) * 0.08, rgb)
    return rgb, z


def arch_view(kind):
    """The picture seen through the arch's doorway (drawn under the arch frame)."""
    w, h = ARCH_W, ARCH_H
    gb = GB(w, h, seed=3)
    m = doorway_mask(gb, 2.0)
    cx = w / 2
    X, Y = gb.X, gb.Y
    horizon = DOOR_TOP + 98
    if kind == "dusk":
        sky = _sky(Y, DOOR_TOP - 2, horizon, [(0, INDIGO), (0.42, VIOLET), (0.78, ROSE), (1.0, EMBER)])
        ta, tb = (0.82, 0.74, 0.86), TILE_DUSK
    else:
        sky = _sky(Y, DOOR_TOP - 2, horizon, [(0, PINK), (0.45, PEACH), (1.0, GOLD_SKY)])
        ta, tb = TILE_A, TILE_ROSE
    floor, z = _checker_floor(X, Y, cx, horizon, ta, tb, grout=GROUT if kind == "noon" else None)
    haze = np.clip(1 - (Y - horizon) / 26.0, 0, 1) ** 2
    horizon_col = _v(EMBER) if kind == "dusk" else _v(GOLD_SKY)
    floor = floor + (horizon_col - floor) * (haze * 0.75)[..., None]
    if kind == "dusk":
        floor = floor * (0.78 + 0.22 * np.clip((Y - horizon) / 70.0, 0, 1))[..., None]
    pic = np.where((Y < horizon)[..., None], sky, floor)
    # a soft sun-glow on the horizon (noon), a last ember line (dusk)
    gl = np.exp(-((Y - horizon) / 6.0) ** 2) * np.exp(-((X - (cx + 18)) / 50.0) ** 2)
    pic = pic + (_v((1.0, 0.98, 0.90)) - pic) * (gl * (0.5 if kind == "noon" else 0.35))[..., None]
    emit(gb, m, pic)
    cv = None
    if kind == "dusk":
        # stars
        rng = np.random.default_rng(42)
        stars = []
        for _ in range(9):
            sx = rng.uniform(DOOR_X0 + 8, DOOR_X1 - 8)
            sy = rng.uniform(DOOR_TOP + 6, horizon - 40)
            if (sx - cx) ** 2 + (sy - DOOR_SPRING) ** 2 > (DOOR_R - 6) ** 2 and sy < DOOR_SPRING:
                continue
            stars.append((sx, sy, rng.uniform(0.7, 1.3)))
        # two lamp posts with lit globes, and a small round table between them
        for lx, ly in ((cx - 30, horizon + 26), (cx + 30, horizon + 26)):
            tube(gb, [(lx, ly), (lx, ly - 34)], 1.3, alb=BRASS, gloss=0.6)
            sphere(gb, lx, ly - 38, 4.6, 4.6, alb=GLOBE_LIT, mat=MAT_EMIT)
        tx, ty = cx, horizon + 36
        tube(gb, [(tx, ty), (tx, ty - 10)], 1.4, alb=BRASS, gloss=0.6)
        tm = gb.mask_ellipse(tx, ty - 11, 10, 3.4)
        slab(gb, tm, face=UP, radius=0.8, alb=(0.88, 0.80, 0.90), gloss=0.5, vein=0)
        sphere(gb, tx - 9, ty - 4, 3.0, 5.0, alb=(0.62, 0.52, 0.72), mat=MAT_MATTE, gloss=0.2)  # chairs
        sphere(gb, tx + 9, ty - 4, 3.0, 5.0, alb=(0.62, 0.52, 0.72), mat=MAT_MATTE, gloss=0.2)
        # keep everything inside the doorway
        outside = ~m
        gb.erase(outside)
        cv = gb.render()
        for sx, sy, r in stars:
            glow(cv, sx, sy, 3.2 * r, (1, 0.97, 0.9), 0.55)
            bd.flat_ellipse(cv, sx, sy, 0.8 * r, 0.8 * r, (1, 1, 1), 0.95)
        for lx, ly in ((cx - 30, horizon + 26), (cx + 30, horizon + 26)):
            glow(cv, lx, ly - 38, 16, GLOBE_LIT, 0.55)
            # the lamp's glow reflected in the polished floor
            bd.flat_ellipse(cv, lx, ly + 10, 2.2, 9, GLOBE_LIT, 0.35, soft=1.0)
        glow(cv, tx, ty - 13, 7, GLOBE_LIT, 0.6)    # a candle on the table
    else:
        # one palm, mid-distance on the right, in its planter
        px_, py_ = cx + 26, horizon + 30
        lathe(gb, px_, py_ - 2.2, [(0, 5), (7, 6), (8, 6.3)], gloss=0.5)
        tube(gb, [(px_, py_ - 9), (px_ + 3, py_ - 52)], 1.6, alb=TRUNK, mat=MAT_MARBLE, gloss=0.1)
        fr = _fronds(8, 20, 0.2, 5)
        layer = frond_layer(w, h, (px_ + 3, py_ - 52), fr, 5, scale=0.6)
        layer[..., 3] *= m
        paint_rgba(gb, layer)
        gb.erase(~m)
        cv = gb.render()
        # a pale sun low on the right
        glow(cv, cx - 24, horizon - 14, 22, (1.0, 0.98, 0.88), 0.55)
        bd.flat_ellipse(cv, cx - 24, horizon - 14, 6, 6, (1.0, 0.98, 0.90), 0.9)
    a = _arr(cv.finish())
    a[..., 3] *= _down(m.astype(float))
    return _img(a)


def _down(m):
    H, W = m.shape
    return m.reshape(H // SS, SS, W // SS, SS).mean(axis=(1, 3))


# ============================================================================================== busts
BUST_W, BUST_H = 80, 112


def _arc(cv, cx, cy, rx, ry, a0, a1, width, color, alpha):
    """A soft stroked elliptical arc (angles in radians, 0 = right, y down)."""
    pts = [(cx + math.cos(t) * rx, cy + math.sin(t) * ry) for t in np.linspace(a0, a1, 10)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        bd.capsule(cv, x0, y0, x1, y1, width, color, gloss=0, alpha=alpha)


INK = (0.52, 0.42, 0.68)        # carved lines (closed eyes, a mouth): lilac, never black


def bust(variant):
    """A serene, abstract head and shoulders, eyes closed, of nobody in particular. One small trait each:
    a: a brass laurel, b: a sun hat, c: a scarf, d: a fox-like companion creature. No reflection (it floats)."""
    w, h = BUST_W, BUST_H
    cx = w / 2
    gb = GB(w, h, seed={"a": 41, "b": 43, "c": 47, "d": 53}[variant])
    # the socle: a small round foot it floats on
    lathe(gb, cx, h - 2 - 9 * K, [(0, 9.5), (2, 10), (3.5, 7.5), (6, 6.5), (8, 8), (10, 8.5)], gloss=0.6)
    if variant == "d":
        hy = 50
        ruff = gb.mask_poly([(cx - 11, 60), (cx + 11, 60), (cx + 23, 70), (cx + 28, 84), (cx + 25, 97),
                             (cx - 25, 97), (cx - 28, 84), (cx - 23, 70)])
        n = bevel_normals(ruff, FRONT, 9, 1.4)
        ang = np.arctan2(gb.Y - 70, gb.X - cx)
        n[..., 0] += 0.14 * np.sin(ang * 11)
        n[..., 1] += 0.10 * np.cos(ang * 11)
        gb.put_full(ruff, _norm(n), MARBLE, gloss=0.4)
        for side in (-1, 1):
            ear = gb.mask_poly([(cx + side * 5, hy - 9), (cx + side * 17, hy - 33), (cx + side * 18, hy - 5)])
            slab(gb, ear, radius=3, edge=1.3, gloss=0.5)
            inner = gb.mask_poly([(cx + side * 8, hy - 11), (cx + side * 16, hy - 27), (cx + side * 15.5, hy - 9)])
            slab(gb, inner, radius=2, edge=-0.8, alb=ROSE_MARBLE, gloss=0.3)
        for side in (-1, 1):                                       # cheek tufts
            tuft = gb.mask_poly([(cx + side * 10, hy - 2), (cx + side * 21, hy + 7), (cx + side * 9, hy + 10)])
            slab(gb, tuft, radius=2.5, edge=1.2, gloss=0.4)
        sphere(gb, cx, hy, 16, 14.5, gloss=0.6)
        sphere(gb, cx, hy + 7.5, 8.5, 6.0, gloss=0.6)              # muzzle
        sphere(gb, cx, hy + 3.6, 2.6, 1.9, alb=(0.80, 0.70, 0.88), mat=MAT_MARBLE, gloss=0.9, vein=0)
        cv = gb.render()
        for side in (-1, 1):
            _arc(cv, cx + side * 6.5, hy - 2.5, 3.6, 2.0, 0.3, math.pi - 0.3, 0.7, INK, 0.85)
        _arc(cv, cx - 2.4, hy + 9.5, 2.4, 1.4, 0.2, math.pi - 0.6, 0.45, INK, 0.5)
        _arc(cv, cx + 2.4, hy + 9.5, 2.4, 1.4, 0.6, math.pi - 0.2, 0.45, INK, 0.5)
        return cv.finish()
    hy = 36                      # the head's centre
    # the neck, then shoulders sloping from it and a chest with a curved cut at the bottom
    lathe(gb, cx, 66, [(0, 8), (8, 7), (16, 6.8)], cap=False, gloss=0.4)
    chest = gb.mask_poly([(cx - 8, 59), (cx + 8, 59), (cx + 20, 64), (cx + 29, 71), (cx + 31, 81), (cx + 29, 93),
                          (cx + 20, 97), (cx - 20, 97), (cx - 29, 93), (cx - 31, 81), (cx - 29, 71), (cx - 20, 64)])
    chest = chest | gb.mask_poly([(cx - 12, 94), (cx + 12, 94), (cx + 7, 101), (cx - 7, 101)])
    # a rounded torso: curving away left and right, the shoulders' tops turned up to the light
    n = bevel_normals(chest, FRONT, 7, 1.5)
    n[..., 0] += np.clip((gb.X - cx) / 31.0, -1, 1) * 0.55
    n[..., 1] -= np.clip((74 - gb.Y) / 14.0, 0, 1) * 0.45 * np.clip(np.abs(gb.X - cx) / 14.0, 0, 1)
    gb.put_full(chest, _norm(n), MARBLE, gloss=0.5, vein=1.0)
    if variant == "c":
        # a scarf: a soft roll around the neck and one end falling over the chest
        sphere(gb, cx, 71, 13.5, 5.5, alb=ROSE_MARBLE, gloss=0.35, vein=0.5)
        sphere(gb, cx, 66, 11, 4.8, alb=ROSE_MARBLE, gloss=0.35, vein=0.5)
        tail = gb.mask_poly([(cx + 3, 70), (cx + 12, 71), (cx + 15, 92), (cx + 8, 94), (cx + 5, 81)])
        n = bevel_normals(tail, FRONT, 3, 1.2)
        n[..., 0] += 0.25 * np.sin((gb.Y - 68) * 0.7)
        gb.put_full(tail, _norm(n), ROSE_MARBLE, gloss=0.35, vein=0.5)
        fringe = gb.mask_rrect(cx + 7.5, 92, cx + 16, 95.5, 1.2)
        slab(gb, fringe, radius=1.2, alb=BRASS, mat=MAT_METAL, gloss=0.9)
    if variant != "b":
        sphere(gb, cx + 1.5, hy - 3, 16, 17, gloss=0.5)           # hair, swept back
    sphere(gb, cx, hy, 14, 17, gloss=0.65)                        # the head: an egg
    sphere(gb, cx, hy + 6, 11.5, 11.5, gloss=0.55)                # cheeks and chin
    sphere(gb, cx + 0.4, hy + 3, 2.1, 4.6, gloss=0.6)             # a nose: a small soft ridge
    if variant != "b":
        hair = gb.mask_poly([(cx - 15, hy - 1), (cx - 12, hy - 13), (cx, hy - 18), (cx + 12, hy - 14), (cx + 15, hy - 2),
                             (cx + 11, hy - 8), (cx + 3, hy - 10.5), (cx - 8, hy - 8.5)])
        n = bevel_normals(hair, np.array([0, -0.3, 0.95]), 3, 1.0)
        n[..., 0] += 0.18 * np.sin((gb.X - cx) * 0.9)
        gb.put_full(hair, _norm(n), MARBLE, gloss=0.5)
    if variant == "a":
        # a brass laurel round the brow: pairs of small leaves along the band, pointing back from the front
        for i in range(9):
            t = math.pi * (0.06 + 0.88 * i / 8)
            lx = cx - math.cos(t) * 15.5
            ly = hy - 9 + math.sin(t) * 4.0
            back = -1 if lx < cx else 1
            sphere(gb, lx, ly - 1.7, 3.6, 1.5, alb=BRASS, mat=MAT_METAL, gloss=1.0, vein=0, rot=-0.6 * back)
            sphere(gb, lx, ly + 1.7, 3.6, 1.5, alb=BRASS, mat=MAT_METAL, gloss=1.0, vein=0, rot=0.6 * back)
        sphere(gb, cx, hy - 5, 1.8, 1.8, alb=BRASS, mat=MAT_METAL, gloss=1.0, vein=0)
    if variant == "b":
        # a sun hat: a broad brim, a round crown, a brass band
        brim = gb.mask_ellipse(cx, hy - 10, 31, 9)
        n = bevel_normals(brim, UP, 3, 1.0)
        gb.put_full(brim, n, MARBLE, gloss=0.5)
        lathe(gb, cx, hy - 11, [(0, 15), (5, 14.5), (9, 13), (12, 10), (14, 6), (15, 0.5)], cap=False, gloss=0.6,
              bands=[(0.5, 4, BRASS, MAT_METAL, 0.95)])
    cv = gb.render()
    if variant == "b":
        soft_shadow(cv, cx + 3, hy - 3, 16, 4, 0.22, (0.55, 0.45, 0.72))   # the brim's shade on the brow
    # closed eyes, a quiet mouth: soft lilac strokes
    ey = hy + (2.5 if variant == "b" else 1.5)
    for side in (-1, 1):
        _arc(cv, cx + side * 5.8, ey, 3.4, 1.8, 0.25, math.pi - 0.25, 0.6, INK, 0.85)
    _arc(cv, cx, hy + 10.5, 2.4, 0.8, 0.35, math.pi - 0.35, 0.45, INK, 0.55)
    return cv.finish()


def plinth():
    w, h = 72, 80
    foot = h - FOOT_TALL
    cx = w / 2
    gb = GB(w, h, seed=61)
    topf = gb.mask_rrect(cx - 31, foot - 54, cx + 31, foot - 44, 2.0)
    slab(gb, topf, face=UP, radius=1.6, gloss=0.65)
    cap = gb.mask_rrect(cx - 32, foot - 45, cx + 32, foot - 38, 1.8)
    slab(gb, cap, radius=1.6, gloss=0.6)
    body = gb.mask_rrect(cx - 27, foot - 39, cx + 27, foot - 7, 1.5)
    slab(gb, body, radius=2.0, gloss=0.5)
    base = gb.mask_rrect(cx - 32, foot - 8, cx + 32, foot, 1.8)
    slab(gb, base, radius=1.6, gloss=0.55)
    plate = gb.mask_rrect(cx - 15, foot - 28, cx + 15, foot - 19, 1.2)
    slab(gb, plate, radius=1.0, alb=BRASS, mat=MAT_METAL, gloss=0.95)
    cv = gb.render()
    for k in range(2):
        y = foot - 25.5 + k * 3
        bd.capsule(cv, cx - 10 + k * 3, y, cx + 10 - k * 5, y, 0.55, (0.55, 0.40, 0.38), gloss=0, alpha=0.55)
    return bake_floor(cv.finish(), foot, REFLECT_TALL, shadow=(cx + 2, foot - 2, 34, 6, 0.18))


# ============================================================================================= lamps
LAMP_GLOBE = 121         # the globe's centre, @2x px above the post's base ellipse
LAMP_LIGHT_Y = int(round((LAMP_GLOBE + 9 * K) / 2))   # ... and in world px above the foot line
def lamp(lit=False):
    w, h = 40, 168
    foot = h - FOOT_TALL
    cx = w / 2
    gb = GB(w, h, seed=71)
    cy = foot - 9 * K
    lathe(gb, cx, cy, [(0, 9), (2, 9.2), (4, 7.5), (7, 5), (10, 3.6), (14, 2.6), (92, 2.2), (96, 2.2),
                       (97, 3.6), (100, 3.8), (102, 2.4), (106, 3.2), (108, 4.4), (110, 4.8)],
          alb=BRASS, mat=MAT_METAL, gloss=0.85, cap=True, vein=0)
    gy = cy - LAMP_GLOBE
    if lit:
        sphere(gb, cx, gy, 11, 11.5, alb=GLOBE_LIT, mat=MAT_EMIT)
    else:
        sphere(gb, cx, gy, 11, 11.5, alb=GLOBE, mat=MAT_MARBLE, gloss=0.9, vein=0)
    sphere(gb, cx, gy - 11.5, 2.4, 2.0, alb=BRASS, mat=MAT_METAL, gloss=1.0)
    cv = gb.render()
    if lit:
        # an inner warm core, a glossy window, and a halo that stays inside the image
        glow(cv, cx, gy + 1, 11, (1.0, 0.97, 0.86), 0.9)
        glow(cv, cx, gy, 19.5, GLOBE_LIT, 0.6)
        # light falling on the brass below the globe
        glow(cv, cx, gy + 18, 7, GLOBE_LIT, 0.25)
    bd.flat_ellipse(cv, cx - 4, gy - 5, 3.2, 2.2, (1, 1, 1), 0.85, rot=-0.6)
    img = cv.finish()
    out = bake_floor(img, foot, REFLECT_TALL, shadow=(cx + 2, foot - 2, 11, 4, 0.20))
    if lit:
        # a warm pool on the polished floor under it
        a = _arr(out)
        cv2 = bd.Canvas(w, h)
        soft_shadow(cv2, cx, foot + 2, 19, 6, 0.22, GLOBE_LIT)
        out = _img(_over(a, _arr(cv2.finish())))
    return out


# ========================================================================================= umbrella
def umbrella():
    w, h = 120, 168
    foot = h - FOOT_TALL
    cx = w / 2
    gb = GB(w, h, seed=81)
    # a round weighted base and the pole
    lathe(gb, cx, foot - 10 * K, [(0, 10), (3, 10.5), (5, 9), (7, 4), (8, 2.2)], gloss=0.6)
    tube(gb, [(cx, foot - 7), (cx, 30)], 2.0, alb=BRASS, gloss=0.85)
    # the canopy: a shallow cone of 8 gores with scalloped hems
    apex = (cx, 20.0)
    rim_cy, R, ry = 54.0, 57.0, 17.0
    hc = 34.0                                       # apex height over the rim plane (for the normals)
    n_g = 8
    gores = []
    for i in range(n_g):
        a0 = (i + 0.5) / n_g * math.tau
        a1 = (i + 1.5) / n_g * math.tau
        am = (a0 + a1) / 2
        gores.append((math.cos(am), i, a0, a1, am))
    gores.sort()
    # draw into a G-buffer per gore, using a facet normal that bends toward up near the apex
    for (_, i, a0, a1, am) in gores:
        pts = [apex]
        for j in range(13):
            a = a0 + (a1 - a0) * j / 12
            sag = 3.2 * math.sin(math.pi * j / 12)
            pts.append((cx + R * math.sin(a) * (1 + 0.02 * math.sin(math.pi * j / 12)),
                        rim_cy + ry * math.cos(a) + sag))
        m = gb.mask_poly(pts)
        # the facet normal in 3D: outward radial * hc + up * R; then into screen space
        nx, nf = math.sin(am), math.cos(am)
        radial = np.array([nx, K * nf, 0.91 * nf])
        s = np.clip((gb.Y - apex[1]) / (rim_cy - apex[1] + ry * nf), 0, 1)
        tilt = (0.55 - 0.25 * s)[..., None]          # flatter near the top
        nrm = radial * (1 - tilt) + UP * tilt
        # the gore bulges a little between its ribs
        ang = np.arctan2(gb.X - cx, (gb.Y - rim_cy) / ry * R + 1e-6)
        rel = np.sin((ang - a0) / (a1 - a0) * math.pi)
        nrm = nrm + np.stack([np.zeros_like(rel), np.zeros_like(rel), rel * 0.15], -1)
        col = PINK if i % 2 == 0 else MARBLE
        gb.put_full(m, _norm(nrm), col, mat=MAT_MATTE, gloss=0.35, vein=0.0)
    sphere(gb, apex[0], apex[1] - 1, 3.0, 3.6, alb=BRASS, mat=MAT_METAL, gloss=1.0)
    cv = gb.render()
    out = bake_floor(cv.finish(), foot, REFLECT_TALL, shadow=(cx + 4, foot - 2, 13, 4, 0.18))
    # the canopy's soft shade falls on the floor a little to the right (the sun is upper left)
    a = _arr(out)
    cv2 = bd.Canvas(w, h)
    soft_shadow(cv2, cx + 8, foot - 3, 40, 9, 0.10)
    return _img(_over(a, _arr(cv2.finish())))


# ========================================================================================= fountain
FOUNT_W = 352
FOUNT_FOOT = 88                  # the fountain's CENTRE line sits 44 world px above each image's bottom
BASIN_RX, BASIN_RY = 152, 64
BASIN_WALL = 28
WATER_DROP = 6


def _water(gb, cx, cy, rx, ry, seed=0):
    m = gb.mask_ellipse(cx, cy, rx, ry)
    u = (gb.X - cx) / rx
    v = (gb.Y - cy) / ry
    # far water reflects the sky (lighter, a touch pink at the very back), near water is deeper aqua
    t = np.clip((v + 1) / 2, 0, 1)
    col = _v(AQUA_L)[None, None, :] * (1 - t[..., None]) + _v(AQUA)[None, None, :] * t[..., None]
    col = col + (_v(PINK) - col) * (0.25 * np.clip(-v - 0.55, 0, 1))[..., None]
    # gentle caustic network on the floor of the basin
    cx_ = _caustic_field(gb.X / 26.0 + seed, gb.Y / 13.0, 4)
    col = col + (1 - col) * (0.09 * cx_)[..., None]
    # the far wall's shade lies across the back of the water, deepest on the left (the sun is upper left)
    col = col * (1 - 0.14 * np.clip(-v, 0, 1) ** 3 * smooth(0.6, -0.6, u))[..., None]
    gb.put_full(m, UP, col, mat=MAT_WATER, gloss=0.0, vein=0.0)
    return m


def _glints(cv, cx, cy, rx, ry, n, seed):
    rng = np.random.default_rng(seed)
    for _ in range(n):
        a = rng.uniform(0, math.tau)
        d = math.sqrt(rng.uniform(0.05, 0.85))
        x, y = cx + math.cos(a) * rx * d, cy + math.sin(a) * ry * d
        L = rng.uniform(2.0, 5.0) * (rx / 100 + 0.5)
        bd.flat_ellipse(cv, x, y, L, 0.55, (1, 1, 1), rng.uniform(0.5, 0.9))


def _ring(gb, cx, cy, ro, ri, ky, gloss=0.6, alb=MARBLE, mat=MAT_MARBLE):
    """A rounded rim (a half torus) between two ellipses at the same height, lit as stone."""
    uo = (gb.X - cx) / ro
    vo = (gb.Y - cy) / (ro * ky)
    do = np.sqrt(uo * uo + vo * vo)
    ui = (gb.X - cx) / ri
    vi = (gb.Y - cy) / (ri * ky)
    di = np.sqrt(ui * ui + vi * vi)
    m = (do <= 1.0) & (di > 1.0)
    # across the ring: 0 on the inner edge, 1 on the outer
    rr = np.sqrt((gb.X - cx) ** 2 + ((gb.Y - cy) / ky) ** 2)
    t = np.clip((rr - ri) / (ro - ri), 0, 1)
    phi = np.arctan2(gb.X - cx, (gb.Y - cy) / ky)      # 0 toward the viewer
    radial = np.stack([np.sin(phi), K * np.cos(phi), 0.91 * np.cos(phi)], -1)
    psi = (t - 0.5) * math.pi * 0.85
    n = UP[None, None, :] * np.cos(psi)[..., None] + radial * np.sin(psi)[..., None]
    gb.put_full(m, n, alb, mat=mat, gloss=gloss, vein=1.0 if mat == MAT_MARBLE else 0.0)
    return m


def _inner_wall(gb, cx, cy_rim, cy_water, ri, rw, ky):
    """The far inside of a bowl, seen above the water: everything inside the rim, above the water."""
    in_rim = ((gb.X - cx) / ri) ** 2 + ((gb.Y - cy_rim) / (ri * ky)) ** 2 <= 1
    in_water = ((gb.X - cx) / rw) ** 2 + ((gb.Y - cy_water) / (rw * ky)) ** 2 <= 1
    m = in_rim & ~in_water
    u = np.clip((gb.X - cx) / ri, -1, 1)
    w = -np.sqrt(np.clip(1 - u * u, 0, 1))              # the far side
    n = -radial_normal(u, w)                            # facing inward, toward us
    gb.put_full(m, n, MARBLE, gloss=0.4, vein=1.0)


def _caustic_field(x, y, seed, period=None):
    """Bright wavy lines where cells meet (a worley F2 - F1 network), 0..1. Periodic with an integer
    `period` (in cells) when given, so a texture made from it tiles."""
    if period:
        wx = x + 0.7 * (fbm(x, y, seed + 3, 3, period, period) - 0.5)
        wy = y + 0.7 * (fbm(x + 5.0, y, seed + 9, 3, period, period) - 0.5)
    else:
        wx = x + 0.7 * (fbm(x * 0.7, y * 0.7, seed + 3, 3) - 0.5)
        wy = y + 0.7 * (fbm(x * 0.7 + 5.2, y * 0.7, seed + 9, 3) - 0.5)
    ix, iy = np.floor(wx).astype(np.int64), np.floor(wy).astype(np.int64)
    f1 = np.full(x.shape, 9.0)
    f2 = np.full(x.shape, 9.0)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cx_, cy_ = ix + ox, iy + oy
            hx, hy = (cx_ % period, cy_ % period) if period else (cx_, cy_)
            px = cx_ + 0.15 + 0.7 * _hash2(hx, hy, seed)
            py = cy_ + 0.15 + 0.7 * _hash2(hx, hy, seed + 1)
            d = np.hypot(wx - px, wy - py)
            f2 = np.where(d < f1, f1, np.minimum(f2, d))
            f1 = np.minimum(f1, d)
    e = f2 - f1
    return np.clip(1 - e / 0.16, 0, 1) ** 2


def fountain_base():
    w, h = FOUNT_W, 192
    cy = h - FOUNT_FOOT              # the fountain's centre on the floor
    cx = w / 2
    gb = GB(w, h, seed=91)
    # a low step all round, then the basin wall
    lathe(gb, cx, cy, [(0, BASIN_RX + 8), (4, BASIN_RX + 8), (4.01, BASIN_RX + 1)], k=BASIN_RY / BASIN_RX,
          cap=True, gloss=0.5)
    ky = BASIN_RY / BASIN_RX
    lathe(gb, cx, cy - 4, [(0, BASIN_RX), (BASIN_WALL - 4, BASIN_RX)], k=ky, cap=False, gloss=0.55, flutes=0,
          bands=[(BASIN_WALL - 14, BASIN_WALL - 11, BRASS, MAT_METAL, 0.95)])
    rim_y = cy - BASIN_WALL
    ri = BASIN_RX - 14
    _inner_wall(gb, cx, rim_y, rim_y + WATER_DROP, ri, ri - 2, ky)
    _water(gb, cx, rim_y + WATER_DROP, ri - 2, (ri - 2) * ky, seed=1)
    _ring(gb, cx, rim_y, BASIN_RX + 2, ri, ky, gloss=0.75)
    # small brass studs along the front of the wall
    for k in range(-4, 5):
        a = k / 4.6 * (math.pi / 2)
        x = cx + math.sin(a) * BASIN_RX
        y = cy - 4 - (BASIN_WALL - 4) * 0.4 + math.cos(a) * BASIN_RY
        sphere(gb, x, y, 2.4 * (0.6 + 0.4 * math.cos(a)) + 0.6, 2.4, alb=BRASS, mat=MAT_METAL, gloss=1.0)
    cv = gb.render()
    _glints(cv, cx, rim_y + WATER_DROP, ri - 10, (ri - 10) * ky, 18, 3)
    front = cy + BASIN_RY + 4      # the front-bottom of the step
    img = cv.finish()
    out = bake_floor(img, int(round(front)), 20, shadow=None)
    return out


def fountain_top():
    w, h = FOUNT_W, 300
    cy = h - FOUNT_FOOT
    cx = w / 2
    gb = GB(w, h, seed=93)
    water_y = cy - BASIN_WALL + WATER_DROP
    # the lower stem: a baluster rising from the basin water
    lathe(gb, cx, water_y, [(0, 13), (6, 12), (14, 9), (26, 10), (38, 15), (48, 13), (56, 9), (64, 8), (70, 9)],
          cap=False, gloss=0.6, bands=[(26, 29, BRASS, MAT_METAL, 0.95)])
    # the lower bowl
    b1_y = cy - 100
    R1 = 76
    lathe(gb, cx, b1_y + 22, [(0, 9), (4, 30), (10, 52), (16, 67), (21, R1), (22, R1)], cap=False, gloss=0.65,
          k=K)
    ri1 = R1 - 7
    _inner_wall(gb, cx, b1_y, b1_y + 3, ri1, ri1 - 1, K)
    _water(gb, cx, b1_y + 3, ri1 - 1, (ri1 - 1) * K, seed=2)
    _ring(gb, cx, b1_y, R1 + 1.5, ri1, K, gloss=0.8)
    # the upper stem
    lathe(gb, cx, b1_y + 3, [(0, 8), (5, 6.5), (16, 5.5), (28, 7), (36, 6), (44, 5)], cap=False, gloss=0.6,
          bands=[(16, 19, BRASS, MAT_METAL, 0.95)])
    # the upper bowl
    b2_y = cy - 164
    R2 = 40
    lathe(gb, cx, b2_y + 12, [(0, 5), (3, 18), (7, 31), (11, R2), (12, R2)], cap=False, gloss=0.7)
    ri2 = R2 - 5
    _inner_wall(gb, cx, b2_y, b2_y + 2, ri2, ri2 - 1, K)
    _water(gb, cx, b2_y + 2, ri2 - 1, (ri2 - 1) * K, seed=3)
    _ring(gb, cx, b2_y, R2 + 1, ri2, K, gloss=0.8)
    # the finial: a short stem and a brass bud
    lathe(gb, cx, b2_y + 2, [(0, 5), (8, 3.6), (16, 3.2), (20, 4.2)], cap=True, gloss=0.6,
          alb=MARBLE, bands=[(15, 20, BRASS, MAT_METAL, 0.95)])
    sphere(gb, cx, b2_y - 26, 6.5, 7.5, alb=BRASS, mat=MAT_METAL, gloss=1.0)
    sphere(gb, cx, b2_y - 34, 2.4, 3.4, alb=BRASS, mat=MAT_METAL, gloss=1.0)
    cv = gb.render()
    _glints(cv, cx, b1_y + 3, ri1 - 6, (ri1 - 6) * K, 10, 5)
    _glints(cv, cx, b2_y + 2, ri2 - 4, (ri2 - 4) * K, 5, 6)
    # soft rings where the stems enter the water
    for (yy, rr) in ((water_y, 15), (b1_y + 3, 9.5), (b2_y + 2, 6.5)):
        _arc(cv, cx, yy + 0.5, rr + 2.5, (rr + 2.5) * K, 0.15, math.pi - 0.15, 0.7, (1, 1, 1), 0.7)
    return cv.finish()


# =============================================================================================== props
# Each prop: (world w, world h of the thing) -> image of (w, h + 8) world, @2x, its foot 8 world px above
# the bottom edge (FOOT_PROP). A builder(base, tint, gloss, cx, foot) draws into three G-buffers.
def _prop_canvases(w, h, seed):
    return GB(w, h, seed), GB(w, h, seed + 1), bd.Canvas(w, h)


def p_bench(b, t, g, cx, foot, ov):
    # two scrolled marble legs, a slab seat, a low back with a brass rail; a cushion on the seat (tint)
    for x in (cx - 36, cx + 36):
        leg = b.mask_rrect(x - 9, foot - 16, x + 9, foot, 3.0)
        slab(b, leg, radius=3.0, edge=1.2)
    back_t = b.mask_rrect(cx - 50, foot - 44, cx + 50, foot - 39, 1.5)
    slab(b, back_t, face=UP, radius=1.2, gloss=0.6)
    back = b.mask_rrect(cx - 50, foot - 40, cx + 50, foot - 27, 2.0)
    slab(b, back, radius=2.0)
    tube(b, [(cx - 48, foot - 42), (cx + 48, foot - 42)], 1.6, alb=BRASS, gloss=0.9)
    seat_t = b.mask_rrect(cx - 54, foot - 30, cx + 54, foot - 20, 2.0)
    slab(b, seat_t, face=UP, radius=1.6, gloss=0.6)
    seat_f = b.mask_rrect(cx - 54, foot - 21, cx + 54, foot - 14, 2.0)
    slab(b, seat_f, radius=1.8)
    cush = t.mask_rrect(cx - 48, foot - 33, cx + 48, foot - 21, 5.5)
    puffy(t, cush, 5.0, face=_norm(UP * 0.6 + FRONT * 0.4), gloss=0.5)
    # gloss: a sheen streak on the cushion
    bd.capsule(ov, cx - 34, foot - 30, cx + 18, foot - 30, 1.1, (1, 1, 1), gloss=0, alpha=0.45)


def p_lounger(b, t, g, cx, foot, ov):
    # a long low frame running north, its head raised; legs in brass
    fr_t = b.mask_rrect(cx - 25, foot - 98, cx + 25, foot - 10, 4)
    slab(b, fr_t, face=UP, radius=2.0, gloss=0.6)
    fr_f = b.mask_rrect(cx - 25, foot - 12, cx + 25, foot - 5, 2.0)
    slab(b, fr_f, radius=1.6)
    for x in (cx - 21, cx + 21):
        tube(b, [(x, foot - 5), (x, foot - 1)], 1.8, alb=BRASS)
    # the pad: a raised back panel (facing us) and a flat seat
    back = t.mask_rrect(cx - 21, foot - 100, cx + 21, foot - 64, 5)
    puffy(t, back, 5, face=_norm(FRONT * 0.7 + UP * 0.3), gloss=0.4)
    seat = t.mask_rrect(cx - 21, foot - 66, cx + 21, foot - 14, 5)
    puffy(t, seat, 5, face=UP, gloss=0.4)
    # tufting seams across the pad
    for y in (foot - 82, foot - 50, foot - 32):
        bd.capsule(ov, cx - 17, y, cx + 17, y, 0.5, (0.55, 0.45, 0.6), gloss=0, alpha=0.18)
    bd.capsule(ov, cx - 12, foot - 92, cx + 6, foot - 92, 1.0, (1, 1, 1), gloss=0, alpha=0.4)


def _fern(W, H, base, n, L, seed, scale=0.6, spread=1.0):
    fr = []
    rng = np.random.default_rng(seed)
    for i in range(n):
        phi = i * math.tau / n + rng.uniform(-0.25, 0.25)
        fr.append((phi, L * rng.uniform(0.8, 1.1), rng.uniform(1.6, 2.0), rng.uniform(1.7, 2.2) * spread))
    return frond_layer(W, H, base, fr, seed, scale=scale)


def p_planter(b, t, g, cx, foot, ov):
    topf = b.mask_rrect(cx - 32, foot - 52, cx + 32, foot - 36, 2.0)
    inner = b.mask_rrect(cx - 27, foot - 50, cx + 27, foot - 39, 1.5)
    slab(b, topf & ~inner, face=UP, radius=1.4, gloss=0.65)
    b.put_full(inner, UP, (0.62, 0.80, 0.70), mat=MAT_MATTE, gloss=0.05, vein=0)
    layer = _fern(b.w, b.h, (cx, foot - 46), 13, 30, 5, scale=0.75)
    paint_rgba(b, layer)
    front = b.mask_rrect(cx - 32, foot - 37, cx + 32, foot, 2.2)
    slab(b, front, radius=2.2)
    band = b.mask_rrect(cx - 32, foot - 31, cx + 32, foot - 28, 0.8)
    slab(b, band, radius=0.9, alb=BRASS, mat=MAT_METAL, gloss=0.95)


def p_fern_pot(b, t, g, cx, foot, ov):
    top = round_planter(b, cx, foot, 13, 22, band=0.75)
    layer = _fern(b.w, b.h, (cx, top - 2), 10, 23, 7, scale=0.6)
    paint_rgba(b, layer)


def p_plaque(b, t, g, cx, foot, ov):
    lathe(b, cx, foot - 9 * K, [(0, 9), (3, 9.2), (5, 6), (8, 4.5), (26, 3.8), (29, 5.5), (32, 7)], cap=True, gloss=0.6)
    top = foot - 9 * K - 32
    # the plaque: a brass tablet tilted toward us on the stand
    pl = b.mask_poly([(cx - 17.5, top - 14), (cx + 17.5, top - 14), (cx + 19.5, top + 6), (cx - 19.5, top + 6)])
    n = bevel_normals(pl, _norm(UP * 0.45 + FRONT * 0.75), 1.2, 1.0)
    b.put_full(pl, n, BRASS, mat=MAT_METAL, gloss=0.95, vein=0)
    for k in range(3):
        y = top - 8 + k * 4.5
        bd.capsule(ov, cx - 12, y, cx + 12 - (k == 2) * 8, y, 0.55, (0.50, 0.34, 0.30), gloss=0, alpha=0.6)


def p_urn(b, t, g, cx, foot, ov):
    cy = foot - 9 * K
    lathe(b, cx, cy, [(0, 9), (3, 9.5), (5, 6), (8, 7), (14, 14), (24, 16.5), (34, 13), (40, 8), (44, 7),
                      (46, 9.5), (49, 10)], cap=False, gloss=0.7,
          bands=[(5, 8, BRASS, MAT_METAL, 0.95), (40, 43, BRASS, MAT_METAL, 0.95)])
    ty = cy - 49
    _ring(b, cx, ty, 10.5, 7.5, K, gloss=0.7)
    inside = b.mask_ellipse(cx, ty, 7.5, 7.5 * K)
    b.put_full(inside, FRONT, (0.62, 0.52, 0.74), mat=MAT_MATTE, gloss=0.0, vein=0)
    for side in (-1, 1):
        pts = [(cx + side * (8 + 6 * math.sin(a)), cy - 44 + 14 * (1 - math.cos(a)) * 0.5 - 4 * math.sin(a))
               for a in np.linspace(0, math.pi, 9)]
        pts = [(cx + side * 8, cy - 43)] + [(cx + side * (9 + 7 * math.sin(a)), cy - 43 + 12 * a / math.pi)
                                            for a in np.linspace(0, math.pi, 9)]
        tube(b, pts, 1.4, alb=BRASS, gloss=0.95)


def p_pool_rail(b, t, g, cx, foot, ov):
    # two chrome rails: up from the deck, over the edge, and down toward the water behind
    # (seen a little from the side, so the far legs, going down into the water, show beside the near ones)
    for x in (cx - 11, cx + 7):
        arc = [(x + 6 * (1 - math.cos(a)) / 2, foot - 34 - 13 * math.sin(a) + 6 * (1 - math.cos(a)) / 2)
               for a in np.linspace(0, math.pi, 14)]
        pts = [(x + 6, foot - 18)] + list(reversed(arc)) + [(x, foot - 1)]
        tube(b, pts, 2.5, alb=CHROME, gloss=1.0)
        # the flange where it meets the deck
        lathe(b, x, foot - 4.5 * K, [(0, 4.5), (1.5, 4.5), (2.5, 3.0)], alb=CHROME, mat=MAT_METAL, gloss=1.0, vein=0)


def p_ball(b, t, g, cx, foot, ov):
    r = 18.0
    cy = foot - r + 0.5
    sl = b.box(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1)
    u = (b.X[sl] - cx) / r
    v = (b.Y[sl] - cy) / r
    d2 = u * u + v * v
    m = d2 <= 1
    wv = np.sqrt(np.clip(1 - d2, 0, 1))
    n = np.stack([u, v, wv], -1)
    # the ball's pole tilts toward the upper left and the viewer
    pole = _norm(np.array([-0.45, -0.55, 0.70]))
    e1 = _norm(np.cross(pole, np.array([0, 0, 1.0])))
    e2 = np.cross(pole, e1)
    lon = np.arctan2(n @ e2, n @ e1)
    lat = n @ pole
    seg = (np.floor((lon + math.pi) / (math.tau / 6)) % 2 == 0) & (np.abs(lat) < 0.93)
    cap_m = np.abs(lat) >= 0.93
    b.put(sl, m & ~seg, n, MARBLE, mat=MAT_MATTE, gloss=0.6, vein=0)
    t.put(sl, m & seg, n, (1, 1, 1), mat=MAT_MATTE, gloss=0.0, vein=0)
    b.put(sl, m & cap_m & (lat > 0), n, BRASS, mat=MAT_METAL, gloss=0.9, vein=0)
    bd.flat_ellipse(ov, cx - 6.5, cy - 7.5, 4.5, 2.6, (1, 1, 1), 0.75, rot=-0.7)
    bd.flat_ellipse(ov, cx - 1.5, cy - 10.5, 1.3, 1.0, (1, 1, 1), 0.6)


def p_table_set(b, t, g, cx, foot, ov):
    # a brass pedestal on a round foot, a marble top laid for two, a candle in the middle
    lathe(b, cx, foot - 14 * K, [(0, 14), (2, 14.5), (4, 10), (6, 4), (8, 3)], alb=BRASS, mat=MAT_METAL,
          gloss=0.9, cap=False, vein=0)
    tube(b, [(cx, foot - 8), (cx, foot - 40)], 3.0, alb=BRASS, gloss=0.9)
    ty = foot - 48
    edge = b.mask_ellipse(cx, ty + 3, 40, 40 * K) & ~b.mask_ellipse(cx, ty, 40, 40 * K)
    edge = edge | (b.mask_ellipse(cx, ty + 3, 40, 40 * K) & (b.Y > ty))
    slab(b, edge, radius=1.0, gloss=0.6)
    top = b.mask_ellipse(cx, ty, 40, 40 * K)
    slab(b, top, face=UP, radius=1.5, edge=0.8, gloss=0.75)
    for side in (-1, 1):
        px = cx + side * 22
        plate = b.mask_ellipse(px, ty + 2, 10, 10 * K)
        slab(b, plate, face=UP, radius=1.6, edge=-1.0, alb=(1, 1, 1), gloss=0.9, vein=0)
        ring = plate & ~b.mask_ellipse(px, ty + 2, 6.5, 6.5 * K)
        slab(b, ring, face=UP, radius=0.8, alb=(1, 0.99, 0.97), gloss=0.9, vein=0)
        # a glass: a slim stem and a bowl (mostly gloss)
        gx = cx + side * 9
        tube(b, [(gx, ty - 2), (gx, ty - 7)], 0.6, alb=CHROME, gloss=1.0)
        sphere(b, gx, ty - 10.5, 3.2, 3.8, alb=(0.95, 0.88, 0.94), mat=MAT_METAL, gloss=1.0)
    # the candle in a brass cup
    lathe(b, cx, ty + 1, [(0, 4), (2, 4), (2.5, 2.4)], alb=BRASS, mat=MAT_METAL, gloss=0.9, vein=0)
    lathe(b, cx, ty - 1.5, [(0, 2.2), (11, 2.2)], alb=(1, 0.97, 0.92), mat=MAT_MATTE, gloss=0.3, vein=0)
    flame = b.mask_poly([(cx, ty - 21), (cx + 2.0, ty - 16), (cx + 1.6, ty - 13.5), (cx - 1.6, ty - 13.5),
                         (cx - 2.0, ty - 16)])
    emit(b, flame, (1.0, 0.86, 0.50))


TABLE_LIGHT_Y = 32       # the candle flame, world px above the foot line


def _table_glow(ov, cx, foot):
    ty = foot - 48
    glow(ov, cx, ty - 16, 16, GLOBE_LIT, 0.55)
    glow(ov, cx, ty - 15, 3.5, (1, 1, 0.9), 0.9)


def p_chair(b, t, g, cx, foot, ov):
    # a bistro chair seen from the front: a brass hoop back, a round seat with a pad, four thin legs
    for x, y0 in ((cx - 11, foot - 30), (cx + 11, foot - 30)):
        tube(b, [(x * 0.9 + cx * 0.1, y0), (x * 0.9 + cx * 0.1, foot - 6)], 1.1, alb=BRASS, gloss=0.8)
    pts = [(cx + 13 * math.cos(a), foot - 40 - 16.5 * math.sin(a)) for a in np.linspace(0, math.pi, 16)]
    tube(b, [(cx + 13, foot - 38)] + pts + [(cx - 13, foot - 38)], 1.4, alb=BRASS, gloss=0.9)
    for k in range(3):
        y = foot - 46 - k * 5
        x_ = math.sqrt(max(1, 13 ** 2 * (1 - ((foot - 40 - y) / 16.5) ** 2)))
        tube(b, [(cx - x_, y), (cx + x_, y)], 0.9, alb=BRASS, gloss=0.8)
    seat = b.mask_ellipse(cx, foot - 37, 16, 16 * K + 1)
    seat_f = b.mask_rrect(cx - 16, foot - 37, cx + 16, foot - 32, 2.0)
    slab(b, seat_f, radius=1.2, alb=BRASS, mat=MAT_METAL, gloss=0.9)
    slab(b, seat, face=UP, radius=1.2, alb=BRASS, mat=MAT_METAL, gloss=0.9)
    pad = t.mask_ellipse(cx, foot - 39, 13.5, 13.5 * K)
    puffy(t, pad, 3.0, face=UP, gloss=0.4)
    for x in (cx - 14, cx + 14):
        tube(b, [(x, foot - 33), (x * 1.0 + (x - cx) * 0.05, foot - 1)], 1.3, alb=BRASS, gloss=0.85)


def p_cushion(b, t, g, cx, foot, ov):
    m = t.mask_rrect(cx - 21, foot - 22, cx + 21, foot - 1, 7)
    n = bevel_normals(m, _norm(UP * 0.75 + FRONT * 0.35), 7, 1.7)
    # a tufted button pulls the middle down
    d = np.hypot(t.X - cx, (t.Y - (foot - 12)) * 1.6)
    pull = np.exp(-(d / 6.0) ** 2)
    n[..., 0] += (t.X - cx) / 6.0 * pull * -0.25
    n[..., 1] += (t.Y - (foot - 12)) / 6.0 * pull * -0.25
    t.put_full(m, _norm(n), (1, 1, 1), mat=MAT_MATTE, gloss=0.5, vein=0)
    sphere(t, cx, foot - 12.5, 2.0, 1.5, alb=(0.86, 0.86, 0.86), mat=MAT_MATTE, gloss=0.6, vein=0)
    bd.capsule(ov, cx - 12, foot - 19, cx + 4, foot - 19.5, 1.0, (1, 1, 1), gloss=0, alpha=0.35)


def p_place_card(b, t, g, cx, foot, ov):
    # a little folded card: we see its front face sloping down from the ridge
    face = b.mask_poly([(cx - 9, foot - 14), (cx + 9, foot - 14), (cx + 10, foot - 1), (cx - 10, foot - 1)])
    n = bevel_normals(face, _norm(FRONT * 0.85 + UP * 0.35), 0.8, 0.6)
    b.put_full(face, n, (1.0, 0.98, 0.95), mat=MAT_MATTE, gloss=0.2, vein=0)
    back = b.mask_poly([(cx - 9, foot - 14), (cx + 9, foot - 14), (cx + 8, foot - 16.5), (cx - 8, foot - 16.5)])
    b.put_full(back & ~face, UP, (0.97, 0.94, 0.92), mat=MAT_MATTE, gloss=0.2, vein=0)
    edge = b.mask_poly([(cx - 10, foot - 2.6), (cx + 10, foot - 2.6), (cx + 10, foot - 1), (cx - 10, foot - 1)])
    slab(b, edge, radius=0.4, alb=BRASS, mat=MAT_METAL, gloss=0.9)
    ridge = b.mask_poly([(cx - 9, foot - 14.6), (cx + 9, foot - 14.6), (cx + 9, foot - 13.4), (cx - 9, foot - 13.4)])
    slab(b, ridge, radius=0.4, alb=BRASS, mat=MAT_METAL, gloss=0.9)
    # a line of handwriting and a tiny heart
    pts = [(cx - 6 + i * 0.8, foot - 8.5 + 1.0 * math.sin(i * 1.3)) for i in range(13)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        bd.capsule(ov, x0, y0, x1, y1, 0.42, (0.50, 0.40, 0.66), gloss=0, alpha=0.85)
    bd.flat_ellipse(ov, cx + 6.2, foot - 9, 0.9, 0.9, ROSE, 0.9)
    bd.flat_ellipse(ov, cx + 7.6, foot - 9, 0.9, 0.9, ROSE, 0.9)
    bd.capsule(ov, cx + 6.9, foot - 7.0, cx + 6.9, foot - 7.0, 0.9, ROSE, gloss=0, alpha=0.9)


# name: ((world w, world h of the thing), builder, has_tint, has_gloss_overlay, shadow (rx, ry, alpha) @2x)
PROPS = {
    "bench": ((56, 28), p_bench, True, (54, 6, 0.16)),
    "lounger": ((28, 52), p_lounger, True, (26, 6, 0.14)),
    "planter": ((36, 36), p_planter, False, (34, 6, 0.16)),
    "fern_pot": ((24, 30), p_fern_pot, False, (14, 4, 0.16)),
    "plaque": ((22, 26), p_plaque, False, (11, 4, 0.16)),
    "urn": ((22, 30), p_urn, False, (11, 4, 0.18)),
    "pool_rail": ((20, 26), p_pool_rail, False, (16, 3, 0.12)),
    "ball": ((20, 20), p_ball, True, (15, 4, 0.20)),
    "table_set": ((48, 40), p_table_set, False, (20, 6, 0.16)),
    "chair": ((20, 30), p_chair, True, (16, 4, 0.14)),
    "cushion": ((22, 12), p_cushion, True, (22, 4, 0.14)),
    "place_card": ((12, 10), p_place_card, False, (10, 2.5, 0.16)),
}


def make_prop(name):
    """(base, tint, gloss) PIL images (tint / gloss None when empty), and the layer names."""
    (ww, wh), fn, tinted, sh = PROPS[name]
    w, h = ww * 2, (wh + 8) * 2
    foot = h - FOOT_PROP
    cx = w / 2
    seed = sum(ord(c) for c in name)
    b, t, ov = _prop_canvases(w, h, seed)
    fn(b, t, None, cx, foot, ov)
    base_img = b.render().finish()
    if name == "table_set":
        cvb = bd.Canvas(w, h)
        _table_glow(cvb, cx, foot)
        base_img = _img(_over(_arr(cvb.finish()), _arr(base_img)))
    base = bake_floor(base_img, foot, REFLECT_PROP, shadow=(cx + 2, foot - 1.5, sh[0], sh[1], sh[2]))
    tint = None
    if tinted and t.cov.any():
        timg = t.render(neutral=True).finish()
        refl = reflection(timg, foot, REFLECT_PROP, 0.30)
        tint = _img(_over(_arr(timg), refl))
    gloss = ov.finish() if ov.a.max() > 0.002 else None
    layers = ["base"] + (["tint"] if tint is not None else []) + (["gloss"] if gloss is not None else [])
    return base, tint, gloss, layers


# ===================================================================================== shader textures
def tex_marble(size=256):
    """Seamless grayscale marble veining (white = clear stone, darker = veins)."""
    ys, xs = np.mgrid[0:size, 0:size].astype(float)
    val = marble_value(xs / size, ys / size)
    return Image.fromarray((val * 255 + 0.5).astype(np.uint8), "L")


def marble_value(u, v):
    """The marble texture at (u, v), periodic with period 1 in both."""
    P = 4
    # one main vein family running diagonally, strongly warped so it never reads as stripes, fading in
    # and out along its length; a finer, fainter family crossing it; and a soft cloudiness
    warp = fbm(u * P, v * P, 201, 5, P, P)
    warp2 = fbm(u * P * 2 + 3.1, v * P * 2, 207, 4, P * 2, P * 2)
    t = 1 * u + 2 * v + 1.9 * (warp - 0.5) + 0.4 * (warp2 - 0.5)
    r = 1 - np.abs(np.sin(math.pi * t))
    t2 = -2 * u + 1 * v + 2.2 * (fbm(u * P + 9.0, v * P, 211, 5, P, P) - 0.5)
    r2 = 1 - np.abs(np.sin(math.pi * t2))
    strength = smooth(0.30, 0.70, fbm(u * 3, v * 3, 221, 3, 3, 3))
    strength2 = smooth(0.40, 0.75, fbm(u * 4 + 2.0, v * 4, 227, 3, 4, 4))
    vein = (r ** 30 * 0.9 + r ** 6 * 0.20) * strength + r2 ** 40 * 0.45 * strength2
    cloud = fbm(u * 8, v * 8, 231, 4, 8, 8)
    val = 1.0 - 0.50 * np.clip(vein, 0, 1) - 0.12 * (cloud - 0.5)
    return np.clip(val, 0, 1)


def tex_caustics(size=256):
    """Seamless grayscale water caustics: a soft bright cell network."""
    ys, xs = np.mgrid[0:size, 0:size].astype(float)
    n = 6
    x, y = xs / size * n, ys / size * n
    a = _caustic_field(x, y, 301, period=n)
    b = _caustic_field(x * 1.0 + 0.5, y * 1.0 + 0.37, 307, period=n)
    val = np.clip(0.8 * a + 0.35 * b * a + 0.15 * b, 0, 1)
    pad = 8
    val = blur(np.pad(val, pad, mode="wrap"), 1.8)[pad:-pad, pad:-pad]     # a wrapped blur keeps it seamless
    val = np.clip(val / max(val.max(), 1e-6), 0, 1) ** 0.9
    return Image.fromarray((val * 255 + 0.5).astype(np.uint8), "L")


def tex_clouds(w=512, h=256):
    """Soft cream clouds with lilac-pink undersides, alpha seamless left to right, fading top and bottom."""
    ys, xs = np.mgrid[0:h, 0:w].astype(float)
    P = 4
    u, v = xs / w * P, ys / h * 2
    base = fbm(u, v, 401, 4, P, None)
    billow = fbm(u * 2 + 1.7, v * 2, 409, 3, P * 2, None)
    f = base * 0.75 + billow * 0.25
    pad = 12
    f = blur(np.pad(f, ((pad, pad), (pad, pad)), mode="wrap"), 3.0)[pad:-pad, pad:-pad]   # wraps left-right
    f = (f - f.mean()) / (f.std() + 1e-6)
    env = np.sin(math.pi * np.clip(ys / (h - 1), 0, 1)) ** 1.2
    a = smooth(-0.2, 1.3, f + 1.4 * (env - 0.6)) * env ** 0.6
    # light from above: the top of each puff is cream, the underside blushes
    fs = blur(np.pad(f, ((24, 24), (24, 24)), mode="wrap"), 8.0)[24:-24, 24:-24]
    shade = np.clip((fs - np.roll(fs, 10, axis=0)) * 1.4 + 0.65, 0, 1)
    top = np.array([1.0, 0.98, 0.94])
    under = np.array([0.95, 0.82, 0.90])
    rgb = under[None, None, :] * (1 - shade[..., None]) + top[None, None, :] * shade[..., None]
    arr = np.concatenate([rgb, a[..., None]], -1)
    return Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


# ================================================================================ every sprite, by file
def tall_sprites():
    """{file stem: (image, foot world px)} for every standing (non-prop) sprite."""
    out = {}
    for v in PALM_VARIANTS:
        trunk, canopy = palm(v)
        out["ll_palm_%s_trunk" % v] = (trunk, FOOT_TALL // 2)
        out["ll_palm_%s_canopy" % v] = (canopy, FOOT_TALL // 2)
    trunk, canopy = palm("a", great=True)
    out["ll_great_palm_trunk"] = (trunk, FOOT_TALL // 2)
    out["ll_great_palm_canopy"] = (canopy, FOOT_TALL // 2)
    out["ll_column"] = (column(), FOOT_TALL // 2)
    out["ll_column_broken"] = (column(broken=True), FOOT_TALL // 2)
    out["ll_arch"] = (arch(), FOOT_TALL // 2)
    out["ll_arch_view_dusk"] = (arch_view("dusk"), FOOT_TALL // 2)
    out["ll_arch_view_noon"] = (arch_view("noon"), FOOT_TALL // 2)
    for v in "abcd":
        out["ll_bust_%s" % v] = (bust(v), 0)
    out["ll_plinth"] = (plinth(), FOOT_TALL // 2)
    out["ll_lamp"] = (lamp(False), FOOT_TALL // 2)
    out["ll_lamp_lit"] = (lamp(True), FOOT_TALL // 2)
    out["ll_umbrella"] = (umbrella(), FOOT_TALL // 2)
    out["ll_fountain_base"] = (fountain_base(), FOUNT_FOOT // 2)
    out["ll_fountain_top"] = (fountain_top(), FOUNT_FOOT // 2)
    return out
