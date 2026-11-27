"""
A small flat-shaded low-poly renderer (Pillow + numpy only), for Glintwold.

It builds real little 3D meshes (cones, stacked cone tiers, icospheres with jittered vertices, crystal
prisms, boxes, flat folded panels), looks at them through one fixed oblique camera that matches the
game's top-down 3/4 view, and paints every triangle ONE clean colour picked from a short ramp by how
the facet faces the light (upper left). No outlines, no gradients inside a facet, no dither.

Pictures are rasterised with a depth buffer at SS x the output size and box-filtered down, so the
edges are smooth, then saved at twice the world resolution (the "@2x" convention: the client draws
them at half size with linear filtering).

World units: 1 = one world px. x runs east, y runs south (toward the viewer), z runs up. Every mesh
stands with its feet at the origin.
"""

import math

import numpy as np
from PIL import Image

SS = 4                       # supersampling factor
PX = 2                       # output px per world px (@2x)

# The camera: orthographic, looking north and down, ELEV degrees above the horizon. A ground length
# shows SIN_E as tall on screen and an upright one COS_E as tall.
ELEV = math.radians(40.0)
SIN_E, COS_E = math.sin(ELEV), math.cos(ELEV)
VIEW = np.array([0.0, COS_E, SIN_E])          # from the scene toward the camera

# The key light, from the upper left (north-west) and above.
LIGHT = np.array([-0.62, -0.10, 0.78])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# Hard ground shadows fall toward the lower right: how far (world px, on the ground) per unit height.
SHADOW_K = (0.32, 0.24)
SHADOW_RGB = (0x3A / 255, 0x4A / 255, 0x6B / 255)
SHADOW_ALPHA = 0.18


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def ramp(*hexes):
    """A shading ramp, darkest first, as a tuple of rgb tuples."""
    return tuple(hexc(h) for h in hexes)


class Split:
    """A material that picks a ramp by the facet's normal: `top` for faces whose normal points up more
    than `cut` (a grassy cap on a hill, moss on a stone), `side` otherwise."""

    def __init__(self, top, side, cut=0.72):
        self.top, self.side, self.cut = top, side, cut

    def pick(self, n):
        return self.top if n[2] > self.cut else self.side


# ---------------------------------------------------------------------------------------------- meshes
class Mesh:
    """Vertices (N x 3) and faces. Each face is (i, j, k, material, hint): `hint` is a point the face
    must face AWAY from (its primitive's centre), so the outward normal survives jitter and any
    transform; a hint of None makes the face double-sided (a wing, a paper fold)."""

    def __init__(self, verts=None, faces=None):
        self.v = np.array(verts if verts is not None else np.zeros((0, 3)), dtype=float).reshape(-1, 3)
        self.f = list(faces or [])

    def copy(self):
        return Mesh(self.v.copy(), [(a, b, c, m, None if h is None else np.array(h, float)) for (a, b, c, m, h) in self.f])

    def add(self, other):
        off = len(self.v)
        self.v = np.vstack([self.v, other.v]) if len(self.v) else other.v.copy()
        self.f += [(a + off, b + off, c + off, m, h) for (a, b, c, m, h) in other.f]
        return self

    # ---- transforms (each returns self, so they chain) ----
    def _apply(self, fn):
        self.v = fn(self.v)
        self.f = [(a, b, c, m, None if h is None else fn(np.array(h, float)[None, :])[0]) for (a, b, c, m, h) in self.f]
        return self

    def move(self, dx=0.0, dy=0.0, dz=0.0):
        d = np.array([dx, dy, dz])
        return self._apply(lambda p: p + d)

    def scale(self, sx, sy=None, sz=None):
        s = np.array([sx, sx if sy is None else sy, sx if sz is None else sz])
        return self._apply(lambda p: p * s)

    def _rot(self, axis, a, about=(0, 0, 0)):
        c, s = math.cos(a), math.sin(a)
        if axis == "z":
            m = np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
        elif axis == "y":
            m = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
        else:
            m = np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
        o = np.array(about, float)
        return self._apply(lambda p: (p - o) @ m.T + o)

    def rot_z(self, a, about=(0, 0, 0)):
        return self._rot("z", a, about)

    def rot_y(self, a, about=(0, 0, 0)):
        return self._rot("y", a, about)

    def rot_x(self, a, about=(0, 0, 0)):
        return self._rot("x", a, about)

    def jitter(self, amount, seed, keep_z_below=None):
        """Nudge every vertex by up to `amount` (a scalar or (ax, ay, az)), deterministically. Vertices at
        or below `keep_z_below` keep their height, so a thing still sits flat on the ground."""
        rng = np.random.default_rng(seed)
        amt = np.broadcast_to(np.array(amount, float), (3,))
        d = rng.uniform(-1, 1, self.v.shape) * amt
        if keep_z_below is not None:
            d[self.v[:, 2] <= keep_z_below + 1e-6, 2] = 0.0
        self.v = self.v + d
        return self

    def paint(self, mat):
        self.f = [(a, b, c, mat, h) for (a, b, c, _m, h) in self.f]
        return self


def _hinted(verts, tris, mat, centre):
    c = np.array(centre, float)
    return Mesh(verts, [(a, b, cc, mat, c) for (a, b, cc) in tris])


def ring(n, r, z, rot=0.0, rx=None, ry=None):
    rx = r if rx is None else rx
    ry = r if ry is None else ry
    return [(math.cos(rot + k / n * math.tau) * rx, math.sin(rot + k / n * math.tau) * ry, z) for k in range(n)]


def cone(n, r, z0, z1, mat, rot=0.0, apex=(0.0, 0.0), cap=False, ry=None):
    """A cone of n sides: a ring of radius r at height z0 and an apex at z1 (offset by `apex`)."""
    v = ring(n, r, z0, rot, ry=ry) + [(apex[0], apex[1], z1)]
    tris = [(k, (k + 1) % n, n) for k in range(n)]
    if cap:
        v.append((0, 0, z0))
        tris += [(k, (k + 1) % n, n + 1) for k in range(n)]
    return _hinted(v, tris, mat, (0, 0, z0 + (z1 - z0) * 0.3))


def frustum(n, r0, r1, z0, z1, mat, rot=0.0, top=True, bottom=False, rot1=None):
    """A truncated cone (a prism when r0 == r1): ring r0 at z0, ring r1 at z1."""
    v = ring(n, r0, z0, rot) + ring(n, r1, z1, rot if rot1 is None else rot1)
    tris = []
    for k in range(n):
        a, b = k, (k + 1) % n
        tris += [(a, b, n + b), (a, n + b, n + a)]
    if top:
        v.append((0, 0, z1))
        tris += [(n + k, n + (k + 1) % n, 2 * n) for k in range(n)]
    if bottom:
        v.append((0, 0, z0))
        idx = len(v) - 1
        tris += [(k, (k + 1) % n, idx) for k in range(n)]
    return _hinted(v, tris, mat, (0, 0, (z0 + z1) / 2))


def lathe(n, profile, mat, rot=0.0, twist=0.0, tip_top=None, tip_bottom=None):
    """A closed solid of revolution with n sides: `profile` is [(radius, z), ...] bottom to top; optional
    points close it off below/above (a crystal's two ends). `twist` turns each ring a little more."""
    v, rings = [], []
    for i, (r, z) in enumerate(profile):
        rings.append(len(v))
        v += ring(n, r, z, rot + twist * i)
    tris = []
    for i in range(len(profile) - 1):
        a0, b0 = rings[i], rings[i + 1]
        for k in range(n):
            k1 = (k + 1) % n
            tris += [(a0 + k, a0 + k1, b0 + k1), (a0 + k, b0 + k1, b0 + k)]
    zs = [z for (_r, z) in profile]
    if tip_top is not None:
        v.append(tip_top)
        t = len(v) - 1
        tris += [(rings[-1] + k, rings[-1] + (k + 1) % n, t) for k in range(n)]
    else:
        v.append((0, 0, zs[-1]))
        t = len(v) - 1
        tris += [(rings[-1] + k, rings[-1] + (k + 1) % n, t) for k in range(n)]
    if tip_bottom is not None:
        v.append(tip_bottom)
    else:
        v.append((0, 0, zs[0]))
    t = len(v) - 1
    tris += [(rings[0] + k, rings[0] + (k + 1) % n, t) for k in range(n)]
    return _hinted(v, tris, mat, (0, 0, (zs[0] + zs[-1]) / 2))


def crystal(n, r, h, mat, tip=None, base_tip=0.0, rot=0.0, waist=1.0):
    """A crystal: an n-sided prism of radius r rising to h, then a pointed tip `tip` tall. `base_tip`
    points its bottom too (a floating gem)."""
    tip = r * 1.4 if tip is None else tip
    prof = [(r, 0.0), (r * waist, h)]
    return lathe(n, prof, mat, rot, tip_top=(0, 0, h + tip),
                 tip_bottom=(0, 0, -base_tip) if base_tip else None)


_ICO = None


def _icosahedron():
    t = (1 + 5 ** 0.5) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2),
         (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11),
         (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    v = [np.array(p, float) / np.linalg.norm(p) for p in v]
    return v, f


def icosphere(subdiv, mat, rx=1.0, ry=None, rz=None, jitter=0.0, seed=0):
    """A low-subdivision icosphere (20 or 80 faces), radii (rx, ry, rz), centred on the origin."""
    v, f = _icosahedron()
    for _ in range(subdiv):
        mid = {}
        nf = []

        def m(a, b):
            key = (min(a, b), max(a, b))
            if key not in mid:
                p = v[a] + v[b]
                v.append(p / np.linalg.norm(p))
                mid[key] = len(v) - 1
            return mid[key]

        for (a, b, c) in f:
            ab, bc, ca = m(a, b), m(b, c), m(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        f = nf
    mesh = _hinted(np.array(v), f, mat, (0, 0, 0))
    if jitter:
        mesh.jitter(jitter, seed)
    ry = rx if ry is None else ry
    rz = rx if rz is None else rz
    return mesh.scale(rx, ry, rz)


def box(w, d, h, mat, z0=0.0):
    """An axis-aligned box w (x) by d (y) by h (z), centred on x/y, standing on z0."""
    x, y = w / 2, d / 2
    v = [(-x, -y, z0), (x, -y, z0), (x, y, z0), (-x, y, z0),
         (-x, -y, z0 + h), (x, -y, z0 + h), (x, y, z0 + h), (-x, y, z0 + h)]
    q = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    tris = []
    for (a, b, c, d2) in q:
        tris += [(a, b, c), (a, c, d2)]
    return _hinted(v, tris, mat, (0, 0, z0 + h / 2))


def panel(points, mat):
    """A flat double-sided polygon (a wing, a paper fold), fanned from its first point."""
    v = [tuple(p) for p in points]
    tris = [(0, k, k + 1) for k in range(1, len(v) - 1)]
    return Mesh(v, [(a, b, c, mat, None) for (a, b, c) in tris])


def join(*meshes):
    out = Mesh()
    for m in meshes:
        out.add(m)
    return out


# ------------------------------------------------------------------------------------------- shading
def facet_colour(mat, n, lo=-0.60, hi=0.95):
    """ONE colour for a facet: its ramp (darkest first) indexed by how squarely it faces the light."""
    r = mat.pick(n) if isinstance(mat, Split) else mat
    if isinstance(r[0], (int, float)):
        return r          # a single fixed colour
    lam = float(n @ LIGHT)
    t = (lam - lo) / (hi - lo)
    i = int(np.clip(t * len(r), 0, len(r) - 1))
    return r[i]


# ------------------------------------------------------------------------------------------ rendering
def project(p, foot):
    """World point(s) -> supersampled screen x, y and depth (bigger = nearer the camera)."""
    p = np.atleast_2d(p)
    k = PX * SS
    sx = foot[0] * SS + p[:, 0] * k
    sy = foot[1] * SS + (p[:, 1] * SIN_E - p[:, 2] * COS_E) * k
    d = p[:, 1] * COS_E + p[:, 2] * SIN_E
    return sx, sy, d


def _tri_cover(xs, ys, W, H):
    """Pixel-centre grid of a triangle's bbox and its barycentric weights (None if off-canvas)."""
    x0 = max(int(math.floor(min(xs))), 0)
    x1 = min(int(math.ceil(max(xs))), W - 1)
    y0 = max(int(math.floor(min(ys))), 0)
    y1 = min(int(math.ceil(max(ys))), H - 1)
    if x1 < x0 or y1 < y0:
        return None
    gy, gx = np.mgrid[y0:y1 + 1, x0:x1 + 1]
    px, py = gx + 0.5, gy + 0.5
    (ax, bx, cx), (ay, by, cy) = xs, ys
    area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    if abs(area) < 1e-9:
        return None
    w0 = ((bx - px) * (cy - py) - (by - py) * (cx - px)) / area
    w1 = ((cx - px) * (ay - py) - (cy - py) * (ax - px)) / area
    w2 = 1.0 - w0 - w1
    eps = -1e-6
    inside = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
    return (y0, y1, x0, x1, w0, w1, w2, inside)


def face_normals(mesh):
    out = []
    for (a, b, c, m, h) in mesh.f:
        pa, pb, pc = mesh.v[a], mesh.v[b], mesh.v[c]
        n = np.cross(pb - pa, pc - pa)
        ln = np.linalg.norm(n)
        if ln < 1e-12:
            out.append(None)
            continue
        n = n / ln
        if h is None:
            if n @ VIEW < 0:
                n = -n
        elif n @ ((pa + pb + pc) / 3 - h) < 0:
            n = -n
        out.append(n)
    return out


class Raster:
    """One supersampled picture: a depth buffer, a colour buffer, a face-id buffer (which face of
    which group owns each sub-pixel) and a hard ground-shadow mask."""

    def __init__(self, w, h, foot):
        self.w, self.h = w, h
        self.W, self.H = w * SS, h * SS
        self.foot = foot
        self.z = np.full((self.H, self.W), -1e9)
        self.rgb = np.zeros((self.H, self.W, 3))
        self.cov = np.zeros((self.H, self.W), bool)
        self.fid = np.full((self.H, self.W), -1, int)
        self.shadow = np.zeros((self.H, self.W), bool)
        self.faces = []           # global face list: (group, centroid world, normal, colour)

    def draw(self, mesh, group=0, lo=-0.60, hi=0.95, cull=True):
        normals = face_normals(mesh)
        sx, sy, d = project(mesh.v, self.foot)
        for (a, b, c, m, h), n in zip(mesh.f, normals):
            if n is None:
                continue
            if cull and h is not None and n @ VIEW <= 1e-4:
                continue
            col = np.array(facet_colour(m, n, lo, hi), float)
            cov = _tri_cover((sx[a], sx[b], sx[c]), (sy[a], sy[b], sy[c]), self.W, self.H)
            if cov is None:
                continue
            y0, y1, x0, x1, w0, w1, w2, inside = cov
            dep = w0 * d[a] + w1 * d[b] + w2 * d[c]
            zb = self.z[y0:y1 + 1, x0:x1 + 1]
            win = inside & (dep > zb)
            if not win.any():
                continue
            fid = len(self.faces)
            self.faces.append((group, (mesh.v[a] + mesh.v[b] + mesh.v[c]) / 3, n, col))
            zb[win] = dep[win]
            self.rgb[y0:y1 + 1, x0:x1 + 1][win] = col
            self.cov[y0:y1 + 1, x0:x1 + 1][win] = True
            self.fid[y0:y1 + 1, x0:x1 + 1][win] = fid
        return self

    def cast(self, mesh, k=SHADOW_K):
        """Lay the mesh's hard shadow on the ground (z = 0), toward the lower right."""
        v = mesh.v.copy()
        z = np.maximum(v[:, 2], 0.0)
        v[:, 0] += z * k[0]
        v[:, 1] += z * k[1]
        v[:, 2] = 0.0
        sx, sy, _d = project(v, self.foot)
        for (a, b, c, _m, _h) in mesh.f:
            cov = _tri_cover((sx[a], sx[b], sx[c]), (sy[a], sy[b], sy[c]), self.W, self.H)
            if cov is None:
                continue
            y0, y1, x0, x1, _w0, _w1, _w2, inside = cov
            self.shadow[y0:y1 + 1, x0:x1 + 1] |= inside
        return self

    def blob_shadow(self, rx, ry, cx=0.0, cy=0.0, sides=9, rot=0.3):
        """A flat, hard-edged faceted shadow on the ground (a polygon), for things whose cast shadow
        would wander too far (a hovering stone)."""
        pts = [(cx + math.cos(rot + k / sides * math.tau) * rx, cy + math.sin(rot + k / sides * math.tau) * ry, 0)
               for k in range(sides)] + [(cx, cy, 0)]
        m = Mesh(pts, [(k, (k + 1) % sides, sides, None, None) for k in range(sides)])
        return self.cast(m)

    def finish(self, mask=None, shadow=True, tint=None, tint_amt=0.0):
        """Box-filter down to the output size. `mask` (sub-pixel bool) keeps only part of the picture
        (one shard); `tint` blends the kept colours toward a hue."""
        cov = self.cov if mask is None else (self.cov & mask)
        rgb = self.rgb
        if tint is not None and tint_amt > 0:
            rgb = rgb * (1 - tint_amt) + np.array(tint) * tint_amt
        a = cov.astype(float)
        col = rgb * a[..., None]
        if shadow:
            sh = self.shadow & ~self.cov
            a = a + sh * SHADOW_ALPHA
            col = col + sh[..., None] * (np.array(SHADOW_RGB) * SHADOW_ALPHA)
        k = SS
        a2 = a.reshape(self.h, k, self.w, k).mean(axis=(1, 3))
        c2 = col.reshape(self.h, k, self.w, k, 3).mean(axis=(1, 3))
        safe = np.where(a2 > 1e-6, a2, 1.0)
        out = np.zeros((self.h, self.w, 4))
        out[..., :3] = np.clip(c2 / safe[..., None], 0, 1)
        out[..., 3] = np.clip(a2, 0, 1)
        return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")


def render(w, h, meshes, foot=None, shadow_of=None, shadow=True, lo=-0.60, hi=0.95):
    """Draw `meshes` into a w x h (@2x px) image whose feet sit at `foot` (default: centred, 16 px
    above the bottom edge, the prop and pal convention). `shadow_of` casts other meshes' shadows (a
    trunk layer carrying the canopy's shadow)."""
    foot = foot or (w / 2, h - 16)
    r = Raster(w, h, foot)
    if shadow:
        for m in (shadow_of if shadow_of is not None else meshes):
            r.cast(m)
    for m in meshes:
        r.draw(m, lo=lo, hi=hi)
    return r.finish(shadow=shadow)


def trimmed_alpha(img):
    return img.getbbox()
