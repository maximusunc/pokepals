"""
Glintwold -- the faceted world's art, built as real little low-poly meshes and drawn by lowpoly.py.

The wold was CUT, not grown: every hill, pine and deer is a handful of flat faces, each one a single
clean colour picked by how it faces the light (upper left). No outlines, no gradients, no dither.
The palette is late golden afternoon: sea-green pines, gold / rose / teal round trees, pale violet and
aqua crystal spires, lilac-grey stone, and the Unfinished in rose quartz.

Everything is reproducible: the only randomness is seeded jitter on vertices.

Outputs (baked by tools/gen_glintwold.py), all @2x:
  * trees      -- pines (trunk + canopy), the great pine, round trees (trunk + canopy), crystal
                  spires, hill-mounds and boulders (one sprite each);
  * props      -- prop_<type>_base@2x.png (and a grayscale _tint for the gem, coloured by the prop);
  * creatures  -- glintbuck, cobblet and foldwing sheets in the PalView layout (8 motion + 16 idle
                  columns x five right-handed facings, 64 px cells, feet on row 48);
  * the Unfinished -- one whole stone cut into nine shards that fit back together exactly.
"""

import math

import numpy as np
from PIL import Image

from lowpoly import (Mesh, Raster, Split, box, cone, crystal, frustum, icosphere, join, lathe, panel,
                     ramp, render, hexc, SS, PX)

# ------------------------------------------------------------------------------------------- palette
PINE = ramp("#235E58", "#2F7F6B", "#3E9A78", "#58B587", "#8BD49A")
PINE_TEAL = ramp("#1F5A5E", "#2A7A78", "#3A9690", "#5DB8A4", "#93DCC0")
TRUNK = ramp("#4B362E", "#5E4338", "#7A5A48", "#97735C")
GOLD = ramp("#C47A34", "#E39A3B", "#F2C14E", "#FBDD7A", "#FDEDB4")
ROSE = ramp("#B5546F", "#D96C86", "#EE8FA0", "#F9B9C0", "#FDDDE0")
TEAL = ramp("#226F73", "#2F8F91", "#49B8B0", "#8FDCCB", "#C6F0E2")
SPIRE = ramp("#5B4FA3", "#8F7FD8", "#B8A6F0", "#DCD2FF", "#F2EEFF")
AQUA = ramp("#3D8FA6", "#5BBCCB", "#8EE0E6", "#C2F2F2", "#EFFFFD")
STONE = ramp("#6E6889", "#9993AD", "#B9B4C7", "#D8D4E2", "#ECEAF2")
GRASS = ramp("#5A9E6E", "#6FB57A", "#7DC27E", "#8FCF8A", "#A6DB93", "#C9DE8E")
SAND = ramp("#BFA56E", "#DCC68E", "#EAD9A6", "#F3E6BC")
HEART = ramp("#B77A9E", "#E9A9C0", "#FAD0DC", "#FFE9EE", "#FFF8FA")
INK = (0.17, 0.18, 0.29)          # eyes: a deep blue-violet, never black
WOOD = ramp("#6B4A3B", "#8A634E", "#A87F62", "#C49C7A")
GLASS = ramp("#E0A24A", "#F2C14E", "#FBDD7A", "#FFF1C4", "#FFFBEA")
GREY = ramp("#8C8C8C", "#A8A8A8", "#C4C4C4", "#DEDEDE", "#F6F6F6")   # tinted by a prop's colour

HILL_GRASS = ramp("#4F9168", "#62A774", "#78BD7E", "#97D08C", "#B8DC92", "#D3E49A")
HILL = Split(HILL_GRASS, STONE, cut=0.26)
MOSSY = Split(GRASS, STONE, cut=0.80)

TREE_W, TREE_H, TREE_FEET = 104, 150, 138          # @2x; base 12 px below the feet (TreeView base_y 6)


# ============================================================================================== trees
def pine_meshes(seed, tiers, trunk_h=14.0, trunk_r=3.0, mat=PINE, lean=0.0):
    """A low-poly pine: a short trunk and stacked cone tiers (r, z0, z1), each turned and jittered."""
    trunk = frustum(5, trunk_r, trunk_r * 0.7, 0, trunk_h, TRUNK, rot=0.4).jitter(0.4, seed, keep_z_below=0)
    canopy = Mesh()
    rng = np.random.default_rng(seed)
    for i, (r, z0, z1) in enumerate(tiers):
        n = 7 if r > 9 else 6
        c = cone(n, r, z0, z1, mat, rot=rng.uniform(0, math.tau), cap=True,
                 apex=(lean * z1 / 60 + rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8)))
        c.jitter((1.4, 1.4, 1.2), seed * 7 + i)
        canopy.add(c)
    return trunk, canopy


PINE_VARIANTS = {
    # name: (seed, tiers, trunk_h, material)
    "a": (3, [(17, 9, 34), (13.5, 22, 46), (10, 34, 57), (6.5, 45, 66)], 14, PINE),
    "b": (8, [(15, 8, 36), (11.5, 24, 50), (7.5, 38, 64)], 13, PINE),
    "c": (21, [(13, 10, 34), (10.5, 22, 46), (8, 33, 57), (5.5, 43, 68), (3.6, 54, 74)], 15, PINE),
    "d": (34, [(18, 8, 32), (14, 19, 42), (9.5, 31, 54)], 12, PINE_TEAL),
}


def pine(variant):
    seed, tiers, th, mat = PINE_VARIANTS[variant]
    trunk, canopy = pine_meshes(seed, tiers, th, mat=mat)
    foot = (TREE_W / 2, TREE_FEET)
    t = render(TREE_W, TREE_H, [trunk], foot, shadow_of=[trunk, canopy])
    c = render(TREE_W, TREE_H, [canopy], foot, shadow=False)
    return t, c


GREAT_W, GREAT_H, GREAT_FEET = 232, 380, 364        # base 16 px below the feet (TreeView base_y 8)


def great_pine(variant):
    seed = {"a": 5, "b": 17}[variant]
    tiers = [(44, 18, 74), (36, 46, 104), (28, 76, 132), (20, 104, 156), (12.5, 130, 176), (6.5, 152, 188)]
    if variant == "b":
        tiers = [(40, 16, 70), (34, 42, 98), (27, 70, 126), (19, 98, 150), (11, 124, 172)]
    trunk = frustum(6, 8.0, 5.0, 0, 30, TRUNK, rot=0.2).jitter(0.8, seed, keep_z_below=0)
    # a few roots flaring out at its foot
    for k in range(4):
        a = 0.5 + k * math.tau / 4
        root = cone(4, 3.0, 0, 6, TRUNK, rot=a).scale(1.0, 1.0, 1.0)
        root.rot_y(math.pi / 2.6).rot_z(a).move(math.cos(a) * 7, math.sin(a) * 5, 0)
        trunk.add(root)
    canopy = Mesh()
    rng = np.random.default_rng(seed)
    for i, (r, z0, z1) in enumerate(tiers):
        c = cone(9 if r > 20 else 8, r, z0, z1, PINE, rot=rng.uniform(0, math.tau), cap=True,
                 apex=(rng.uniform(-1.5, 1.5), rng.uniform(-1.5, 1.5)))
        c.jitter((2.6, 2.6, 2.0), seed * 11 + i)
        canopy.add(c)
    foot = (GREAT_W / 2, GREAT_FEET)
    t = render(GREAT_W, GREAT_H, [trunk], foot, shadow_of=[trunk, canopy])
    c = render(GREAT_W, GREAT_H, [canopy], foot, shadow=False)
    return t, c


ROUND_VARIANTS = {
    # name: (material, seed, [(x, y, z, r)] canopy lumps, trunk height)
    "gold_a": (GOLD, 2, [(0, 0, 34, 16)], 20),
    "gold_b": (GOLD, 9, [(-6, 1, 30, 12), (6, -1, 36, 13)], 18),
    "rose_a": (ROSE, 4, [(0, 0, 33, 15.5)], 19),
    "rose_b": (ROSE, 13, [(-5, 0, 29, 11.5), (5, 1, 33, 12), (0, -2, 42, 9)], 17),
    "teal_a": (TEAL, 6, [(0, 0, 35, 16.5)], 21),
    "teal_b": (TEAL, 15, [(-7, 0, 31, 11), (6, 0, 31, 11.5), (0, -1, 41, 10)], 19),
}


def round_tree(variant):
    mat, seed, lumps, th = ROUND_VARIANTS[variant]
    trunk = frustum(5, 2.8, 1.9, 0, th, TRUNK, rot=0.3).jitter(0.35, seed, keep_z_below=0)
    # a forked branch or two into the crown
    for k, (x, y, z, r) in enumerate(lumps):
        if abs(x) > 0.5:
            br = frustum(4, 1.5, 1.0, 0, 10, TRUNK, rot=0.2)
            br.rot_y(math.copysign(0.7, x)).move(0, 0, th - 6)
            trunk.add(br)
    canopy = Mesh()
    for k, (x, y, z, r) in enumerate(lumps):
        s = icosphere(1, mat, r, r * 0.92, r * 0.86, jitter=0.10, seed=seed * 5 + k)
        canopy.add(s.move(x, y, z))
    foot = (TREE_W / 2, TREE_FEET)
    t = render(TREE_W, TREE_H, [trunk], foot, shadow_of=[trunk, canopy])
    c = render(TREE_W, TREE_H, [canopy], foot, shadow=False)
    return t, c


SPIRE_W, SPIRE_H, SPIRE_FEET = 120, 230, 218
SPIRE_VARIANTS = {
    # name: (seed, [(x, y, r, h, tilt_x, tilt_y, material)])
    "violet": (3, [(0, 0, 7.5, 64, 0.0, 0.0, SPIRE), (-9, 3, 5, 36, -0.32, 0.12, SPIRE), (9, 2, 4.5, 30, 0.36, 0.1, SPIRE),
                   (3, 7, 3.6, 16, 0.2, 0.4, AQUA)]),
    "aqua": (7, [(0, 0, 7, 58, 0.05, 0.0, AQUA), (-8, 2, 5, 40, -0.28, 0.08, AQUA), (8, 4, 4, 24, 0.4, 0.2, SPIRE),
                 (-3, 8, 3.2, 14, -0.15, 0.45, AQUA)]),
    "twin": (11, [(-5, 0, 6.5, 56, -0.08, 0.0, SPIRE), (6, 1, 6, 46, 0.12, 0.05, AQUA), (0, 6, 4, 22, 0.0, 0.42, SPIRE),
                  (12, 6, 3, 14, 0.5, 0.3, AQUA)]),
}


def spire(variant):
    seed, parts = SPIRE_VARIANTS[variant]
    rng = np.random.default_rng(seed)
    meshes = []
    for i, (x, y, r, h, tx, ty, mat) in enumerate(parts):
        c = crystal(6, r, h, mat, tip=r * 2.4, rot=rng.uniform(0, 1), waist=0.86)
        c.jitter((0.5, 0.5, 0.8), seed * 3 + i, keep_z_below=0)
        c.rot_y(tx).rot_x(-ty).move(x, y, -1.0)
        meshes.append(c)
    # a few stone chips at its foot
    for k in range(3):
        a = 1.0 + k * 2.1
        s = icosphere(0, STONE, 3.2, 2.8, 1.8, jitter=0.12, seed=seed + k).move(math.cos(a) * 11, math.sin(a) * 6 + 3, 0.8)
        meshes.append(s)
    return render(SPIRE_W, SPIRE_H, meshes, (SPIRE_W / 2, SPIRE_FEET))


HILL_W, HILL_H, HILL_FEET = 380, 250, 238
HILL_VARIANTS = {
    # name: (seed, [(x, y, rx, ry, h)] mounds, outcrops [(x, y, r, h)])
    "long": (4, [(-10, -26, 80, 27, 70), (44, -20, 40, 18, 40)], [(60, -8, 7, 18), (-62, -10, 5, 11)]),
    "peak": (9, [(0, -26, 66, 27, 90), (-44, -16, 32, 15, 30)], [(40, -8, 8, 20), (49, -4, 5, 11)]),
}


def _mound(rx, ry, h, mat, seed, n=None):
    """An angular hill-mound: a few jittered rings stepping in to a broad grassy crown, flat on the ground."""
    n = n or (12 if rx > 50 else 9)
    prof = [(1.0, 0.0), (0.93, 0.22), (0.78, 0.50), (0.55, 0.76), (0.28, 0.94)]
    m = lathe(n, [(r, z * h) for (r, z) in prof], mat, rot=0.2, twist=math.pi / n, tip_top=(rx * 0.0, 0.0, h))
    m.scale(rx, ry, 1.0)
    m.jitter((rx * 0.035, ry * 0.05, h * 0.05), seed, keep_z_below=0)
    return m


def hill(variant):
    seed, lumps, outcrops = HILL_VARIANTS[variant]
    meshes = []
    for i, (x, y, rx, ry, h) in enumerate(lumps):
        meshes.append(_mound(rx, ry, h, HILL, seed * 13 + i).move(x, y, 0))
    for i, (x, y, r, h) in enumerate(outcrops):
        c = crystal(5, r, h * 0.45, STONE, tip=h * 0.55, rot=0.3 * i).jitter((0.8, 0.8, 1.0), seed + i, keep_z_below=0)
        meshes.append(c.rot_y(0.12 * (-1) ** i).move(x, y, 0))
    return render(HILL_W, HILL_H, meshes, (HILL_W / 2, HILL_FEET))


BOULDER_W, BOULDER_H, BOULDER_FEET = 72, 64, 52
BOULDER_VARIANTS = {"a": (3, 12, 9, 9), "b": (8, 10, 8, 11), "c": (14, 14, 10, 7)}


def boulder(variant):
    seed, rx, ry, rz = BOULDER_VARIANTS[variant]
    b = icosphere(1, MOSSY, rx, ry, rz, jitter=0.16, seed=seed).move(0, -2, rz * 0.62)
    meshes = [b]
    meshes.append(icosphere(0, STONE, 3.4, 3, 2.2, jitter=0.15, seed=seed + 1).move(rx * 0.9, 4, 1.4))
    return render(BOULDER_W, BOULDER_H, meshes, (BOULDER_W / 2, BOULDER_FEET))


# ============================================================================================== props
# Each prop: (w, h) at @2x, feet 16 px above the bottom edge (WorldArt._blit_soft_prop), and a builder
# returning (base meshes, tint meshes). Tint meshes are drawn in GREY and coloured by the prop's own
# colour in the game (only the gem uses that).
def p_gem():
    rng = np.random.default_rng(5)
    tint = []
    for i, (x, y, r, h, tx, ty) in enumerate([(0, 0, 3.0, 9, 0.0, 0.0), (-4, 2, 2.2, 5, -0.5, 0.2),
                                                 (4, 1.5, 2.0, 6, 0.45, 0.1), (1, 4, 1.6, 3, 0.1, 0.5)]):
        c = crystal(5, r, h, GREY, tip=r * 1.8, rot=rng.uniform(0, 1)).jitter(0.2, i, keep_z_below=0)
        tint.append(c.rot_y(tx).rot_x(-ty).move(x, y, -0.5))
    base = [icosphere(0, STONE, 4.2, 3.4, 1.8, jitter=0.1, seed=2).move(-1, 2, 0.6)]
    return [m.scale(1.45) for m in base], [m.scale(1.45) for m in tint]


def p_lamp():
    post = frustum(5, 1.6, 1.2, 0, 21, WOOD, rot=0.3).jitter(0.15, 1, keep_z_below=0)
    foot = frustum(6, 3.8, 2.8, 0, 2.6, STONE, rot=0.1).jitter(0.25, 2, keep_z_below=0)
    lantern = lathe(5, [(3.4, 23.5), (4.6, 27.5), (3.6, 32)], GLASS, rot=0.2,
                    tip_bottom=(0, 0, 21.0), tip_top=(0, 0, 33))
    cap = cone(5, 5.2, 32.2, 37.0, STONE, rot=0.2 + math.pi / 5)
    finial = icosphere(0, STONE, 1.1).move(0, 0, 37.8)
    return [foot, post, lantern, cap, finial], []


def p_bench():
    seat = box(30, 7, 2.2, WOOD, z0=6.5).jitter(0.45, 1)
    back = box(30, 1.8, 6, WOOD, z0=9.5).rot_x(-0.2, about=(0, 0, 9.5)).move(0, -3.2, 0).jitter(0.45, 2)
    legs = [frustum(5, 3.0, 2.2, 0, 6.6, STONE, rot=0.3 * i).jitter(0.3, 5 + i, keep_z_below=0).move(x, 0, 0)
            for i, x in enumerate((-11, 11))]
    return legs + [seat, back], []


def p_sign():
    post = frustum(4, 1.4, 1.2, 0, 18, WOOD, rot=math.pi / 4)
    board = box(16, 1.6, 8, WOOD, z0=11).rot_z(-0.18).rot_y(0.06).jitter(0.3, 3)
    point = cone(3, 4.0, 0, 3.5, WOOD, rot=0).rot_y(math.pi / 2).move(8, 0, 15).rot_z(-0.18)
    stone = icosphere(0, STONE, 3.4, 2.8, 1.6, jitter=0.12, seed=4).move(-2.5, 1.5, 0.5)
    return [stone, post, board, point], []


def p_cairn():
    meshes = []
    z = 0.0
    for i, (r, h, dx, rot) in enumerate([(8, 4.4, 0.0, 0.0), (6.4, 3.8, 0.8, 0.5), (5.0, 3.4, -0.5, 1.2),
                                          (3.4, 3.0, 0.4, 0.4), (2.0, 2.6, 0.0, 0.9)]):
        s = frustum(6, r, r * 0.86, 0, h, STONE, rot=rot).jitter((0.4, 0.4, 0.35), 20 + i)
        s.rot_y(0.06 * (-1) ** i)
        meshes.append(s.move(dx, 0, z))
        z += h - 0.3
    return meshes, []


def p_plinth():
    """The carved line by the dais: a low slanted slab, its top a lighter face with a groove cut in."""
    slab = box(30, 12, 9, STONE).jitter((0.3, 0.3, 0.2), 6, keep_z_below=0)
    top = box(26, 9, 1.6, ramp("#B9B4C7", "#CFCADB", "#E3DFEB", "#F3F1F7"), z0=9).jitter(0.15, 7)
    top.rot_x(0.16, about=(0, 0, 9))
    groove = box(19, 1.4, 0.4, ramp("#6E6889", "#7E7898"), z0=10.65).rot_x(0.16, about=(0, 0, 9))
    step = box(34, 15, 2, STONE).move(0, 1, 0)
    return [step, slab, top, groove], []


def p_arch():
    meshes = []
    for x in (-19, 19):
        meshes.append(box(9, 9, 30, STONE).move(x, 0, 0).jitter((0.6, 0.6, 0.4), int(x + 40), keep_z_below=0))
    # a lintel of five wedge stones in a shallow arc
    for k in range(5):
        a = math.pi * (0.15 + 0.7 * k / 4)
        cx, cz = math.cos(a) * -21, 29 + math.sin(a) * 9
        st = box(10.5, 9, 6.5, STONE).move(0, 0, -3.25).rot_y(a - math.pi / 2).move(cx, 0, cz)
        meshes.append(st.jitter(0.35, 50 + k))
    meshes.append(cone(4, 2.6, 0, 4, GRASS, rot=0.3).move(-24, 5, 0))
    return meshes, []


def p_shardbed():
    rng = np.random.default_rng(9)
    meshes = []
    for i, (x, y, r, h, mat) in enumerate([(-10, 1, 3.6, 6, SPIRE), (-1, -3, 3.2, 8, HEART), (8, 2, 3.4, 5.5, AQUA),
                                            (15, -2, 2.6, 4.5, SPIRE), (2, 5, 2.6, 4, HEART), (-17, -2, 2.4, 3.5, AQUA)]):
        c = crystal(4, r, h * 0.4, mat, tip=h * 0.6, rot=rng.uniform(0, 1)).jitter(0.2, i, keep_z_below=0)
        c.rot_y(rng.uniform(-1.0, 1.0)).rot_x(rng.uniform(-0.6, 0.6)).move(x, y, 0.2)
        meshes.append(c)
    return meshes, []


def p_offcut():
    """The offcut: the last face that had to be cut away. A small, bright chip of the Unfinished."""
    chip = lathe(5, [(3.6, 1.6), (3.2, 4.2)], HEART, rot=0.4, tip_top=(0.6, -0.4, 9.0), tip_bottom=(0, 0, 0))
    chip.jitter((0.4, 0.4, 0.3), 77)
    chip.rot_y(0.22)
    return [chip], []


PROP_BUILDERS = {
    "gw_gem": ((56, 68), p_gem),
    "gw_lamp": ((44, 112), p_lamp),
    "gw_bench": ((80, 56), p_bench),
    "gw_sign": ((56, 72), p_sign),
    "gw_cairn": ((44, 72), p_cairn),
    "gw_plinth": ((84, 64), p_plinth),
    "gw_arch": ((112, 116), p_arch),
    "gw_shardbed": ((96, 48), p_shardbed),
    "offcut": ((32, 48), p_offcut),
}


def make_prop(name):
    """(base, tint) images for a prop; tint is None when it has none."""
    (w, h), fn = PROP_BUILDERS[name]
    base_m, tint_m = fn()
    foot = (w / 2, h - 16)
    r = Raster(w, h, foot)
    for m in base_m + tint_m:
        r.cast(m)
    for m in base_m:
        r.draw(m, group=0)
    for m in tint_m:
        r.draw(m, group=1)
    if not tint_m:
        return r.finish(), None
    groups = np.array([g for (g, _c, _n, _col) in r.faces] + [-1])
    owner = groups[r.fid]           # fid -1 indexes the trailing -1
    base = r.finish(mask=(owner == 0))
    tint = r.finish(mask=(owner == 1), shadow=False)
    return base, tint


# ========================================================================================== creatures
CELL = 64
FEET = 48
COLS = 8
IDLE = 16
VIEWS = ["down", "down_right", "right", "up_right", "up"]
YAW = {"right": 0.0, "down_right": math.pi / 4, "down": math.pi / 2, "up_right": -math.pi / 4, "up": -math.pi / 2}

CREATURE_VARIANTS = {
    "glintbuck": [(GOLD, AQUA), (ROSE, AQUA), (SPIRE, ramp("#E39A3B", "#F2C14E", "#FBDD7A", "#FDEDB4"))],
    "cobblet": [(STONE, GRASS), (SAND, GRASS), (ramp("#4E7F86", "#6E9CA0", "#8DB8B6", "#B4D6CF"), GRASS)],
    "foldwing": [(GOLD, ROSE), (ROSE, SPIRE), (AQUA, GOLD)],
}
TEMPERAMENT = {"glintbuck": "shy", "cobblet": "friendly", "foldwing": "shy"}
FLOATERS = {"foldwing"}
LORE = {
    "glintbuck": "A glintbuck, cut from a few bright faces. It holds very still when you look at it, and its crystal antlers catch the light as it turns its head.",
    "cobblet": "A cobblet: a round stone that decided to go for a walk. It waddles everywhere, a little moss on its head, and it is always glad of company.",
    "foldwing": "A foldwing, folded from a single flat face like a paper moth. It flutters low over the grass and settles on anything warm.",
}


def _eye(x, y, z, r=0.9):
    return icosphere(0, INK, r, r * 0.7, r).move(x, y, z)


def glintbuck(f, idle, variant):
    coat, horn = CREATURE_VARIANTS["glintbuck"][variant]
    belly = ramp("#D8C7B5", "#EADCCB", "#F5EDE2", "#FFF8EE")
    ph = f / (IDLE if idle else COLS)
    swing = 0.0 if idle else math.sin(ph * math.tau) * 0.5
    bob = 0.0 if idle else abs(math.sin(ph * math.tau)) * 0.6
    breathe = math.sin(ph * math.tau) * 0.03 if idle else 0.0
    look = 0.0
    lift_head = 0.0
    if idle:
        # it lifts its head and glances round, then settles
        look = 0.5 * math.sin(ph * math.tau) if 3 <= f <= 12 else 0.0
        lift_head = 1.0 if 4 <= f <= 11 else 0.0
    blink = idle and f in (13, 14)
    parts = []
    body = icosphere(0, coat, 7.6, 4.0, 4.6, jitter=0.08, seed=11).rot_y(0.06).move(0, 0, 11.5 + bob)
    body.scale(1, 1, 1 + breathe)
    parts.append(body)
    parts.append(icosphere(0, belly, 5.0, 3.0, 2.0, jitter=0.05, seed=12).move(0.5, 0, 9.0 + bob))
    # legs: thin prisms swinging from the hip, diagonal pairs together
    for (lx, ly, sgn) in [(5.0, 2.0, 1), (5.0, -2.0, -1), (-5.0, 2.0, -1), (-5.0, -2.0, 1)]:
        leg = frustum(4, 1.15, 0.8, 0, 9.5, coat, rot=math.pi / 4, top=False)
        leg.rot_y(math.pi, about=(0, 0, 0)).move(0, 0, 9.5)    # hang from the hip
        leg.rot_y(swing * sgn, about=(0, 0, 9.5))
        parts.append(leg.move(lx, ly, bob * 0.6))
        parts.append(frustum(4, 0.95, 0.85, 0, 1.0, ramp("#4B362E", "#5E4338"), rot=math.pi / 4).move(lx, ly, 0))
    # neck and head, turning on the neck's foot when it looks round
    pivot = (5.5, 0, 13 + bob)
    head = Mesh()
    neck = frustum(4, 2.0, 1.4, 0, 8 + lift_head, coat, rot=math.pi / 4).rot_y(0.45).move(5.5, 0, 12.5 + bob)
    head.add(neck)
    hz = 21.5 + bob + lift_head
    hx = 9.5 - lift_head * 0.4
    head.add(icosphere(0, coat, 3.4, 2.4, 2.5, jitter=0.06, seed=13).move(hx, 0, hz))
    head.add(cone(4, 1.6, 0, 3.6, belly, rot=math.pi / 4).rot_y(math.pi / 2).move(hx + 2.2, 0, hz - 0.8))
    for side in (-1, 1):
        ear = panel([(hx - 1.0, side * 1.6, hz + 1.4), (hx - 2.6, side * 4.6, hz + 3.2), (hx - 0.2, side * 2.4, hz + 2.6)], coat)
        head.add(ear)
        # crystal antlers: a prong and a branch
        a = crystal(4, 0.7, 4.0, horn, tip=2.2, rot=0.3).rot_x(side * -0.35).rot_y(-0.25).move(hx - 0.6, side * 1.1, hz + 1.6)
        b = crystal(4, 0.5, 2.0, horn, tip=1.6, rot=0.8).rot_x(side * -0.9).rot_y(0.5).move(hx - 0.2, side * 1.9, hz + 3.6)
        head.add(a)
        head.add(b)
        if not blink:
            head.add(_eye(hx + 1.6, side * 1.95, hz + 0.5, 0.75))
    head.rot_z(look, about=pivot)
    parts.append(head)
    tail = cone(3, 1.4, 0, 3.2, belly, rot=0.2).rot_y(-2.2).move(-7.4, 0, 14 + bob)
    parts.append(tail)
    return parts


def cobblet(f, idle, variant):
    stone, moss = CREATURE_VARIANTS["cobblet"][variant]
    ph = f / (IDLE if idle else COLS)
    if idle:
        roll, step, bob = 0.0, 0.0, 0.0
        squash = 0.03 * math.sin(ph * math.tau)
        turn = 0.35 * math.sin(ph * math.tau) if 2 <= f <= 7 else 0.0
    else:
        roll = math.sin(ph * math.tau) * 0.20
        step = math.sin(ph * math.tau)
        bob = abs(math.cos(ph * math.tau)) * 0.9
        squash, turn = 0.0, 0.0
    blink = idle and f in (10, 11)
    body = icosphere(1, Split(moss, stone, cut=0.78), 8.6, 8.0, 7.2 * (1 + squash), jitter=0.11, seed=31 + variant)
    body.move(0, 0, 8.2 + bob)
    face = Mesh()
    if not blink:
        for side in (-1, 1):
            face.add(_eye(7.4, side * 2.7, 10.0 + bob, 1.0))
    else:
        for side in (-1, 1):
            face.add(box(0.6, 1.8, 0.5, INK).move(7.9, side * 2.7, 9.8 + bob))
    upper = join(body, face).rot_x(roll, about=(0, 0, 1)).rot_z(turn)
    feet = []
    for side in (-1, 1):
        fx = 1.0 + side * step * 2.0
        feet.append(icosphere(0, stone, 2.8, 2.2, 1.5, jitter=0.08, seed=40 + side).move(fx, side * 4.2, 1.2 + max(0, side * step) * 1.0))
    return feet + [upper]


def foldwing(f, idle, variant):
    wing, body_c = CREATURE_VARIANTS["foldwing"][variant]
    ph = f / (IDLE if idle else COLS)
    lift = 11.0 + 2.2 * math.sin(ph * math.tau)
    beats = 1 if idle else 2
    flap = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(ph * math.tau * beats))
    if idle:
        flap = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(ph * math.tau * 2))
    body = crystal(4, 1.0, 6.5, body_c, tip=1.6, rot=math.pi / 4, base_tip=1.2).rot_y(math.pi / 2).move(-3.0, 0, lift)
    parts = [body]
    for side in (-1, 1):
        # a forewing folded along one crease (two flat faces), and a smaller hind wing
        fore = Mesh().add(panel([(2.4, 0, 0), (-0.5, 0, 0), (1.0, side * 8.0, 0.0)], wing))
        fore.add(panel([(-0.5, 0, 0), (1.0, side * 8.0, 0.0), (-3.6, side * 6.2, 0.9)], wing))
        hind = Mesh().add(panel([(-0.8, 0, 0), (-4.2, 0, 0), (-4.6, side * 5.0, 0.4)], body_c))
        hind.add(panel([(-0.8, 0, 0), (-4.6, side * 5.0, 0.4), (-1.8, side * 4.4, 0.2)], wing))
        w = join(fore, hind).rot_x(side * flap * 1.05).move(0, 0, lift)
        parts.append(w)
        parts.append(panel([(2.2, side * 0.3, lift + 0.4), (5.0, side * 2.2, lift + 2.6), (2.6, side * 0.5, lift + 0.6)], body_c))
    parts.append(_eye(2.6, 0.6, lift + 0.3, 0.55))
    parts.append(_eye(2.6, -0.6, lift + 0.3, 0.55))
    return parts


BUILD = {"glintbuck": glintbuck, "cobblet": cobblet, "foldwing": foldwing}
SIZE = {"glintbuck": 1.12, "cobblet": 1.25, "foldwing": 1.15}


def creature_frame(species, view, f, variant, idle=False):
    parts = BUILD[species](f, idle, variant)
    s = SIZE[species]
    meshes = [m.scale(s).rot_z(YAW[view]) for m in parts]
    r = Raster(CELL, CELL, (CELL / 2, FEET))
    for m in meshes:
        r.cast(m)
    for m in meshes:
        r.draw(m)
    return r.finish()


def creature_sheet(species, variant):
    cols = COLS + IDLE
    sheet = Image.new("RGBA", (cols * CELL, len(VIEWS) * CELL), (0, 0, 0, 0))
    for row, view in enumerate(VIEWS):
        for f in range(COLS):
            sheet.paste(creature_frame(species, view, f, variant), (f * CELL, row * CELL))
        for f in range(IDLE):
            sheet.paste(creature_frame(species, view, f, variant, idle=True), ((COLS + f) * CELL, row * CELL))
    return sheet


# ===================================================================================== the Unfinished
# One great rose-quartz stone hanging over the Turning Floor, built as ONE mesh, then cut into nine
# shards along its own facet edges: every visible face belongs to exactly one shard, so drawing all
# nine at their homes rebuilds the stone exactly.
HEART_W, HEART_H, HEART_FEET = 220, 380, 364     # foot 16 px above the bottom (props convention)
HEART_HOVER = 14.0                               # world px between the dais and the stone's point
HEART_SCALE = 1.1
YOU_TINT = hexc("#BFEFF2")
COMPANION_TINT = hexc("#FFE3A6")
TINT_AMOUNT = 0.24


def heart_mesh():
    prof = [(13, 14), (26, 38), (33, 70), (31, 104), (23, 132), (12, 152)]
    m = lathe(7, [(r, z + HEART_HOVER) for (r, z) in prof], HEART, rot=0.35, twist=0.22,
              tip_top=(1.5, -1.0, 168 + HEART_HOVER), tip_bottom=(0, 0, HEART_HOVER))
    m.jitter((1.8, 1.8, 2.2), 1717)
    m.scale(HEART_SCALE)
    return m


def heart_raster():
    r = Raster(HEART_W, HEART_H, (HEART_W / 2, HEART_FEET))
    r.draw(heart_mesh(), lo=-0.45, hi=0.95)
    return r


def heart_shadow():
    r = Raster(HEART_W, 80, (HEART_W / 2, 40))
    r.blob_shadow(30, 16, 3, 2, sides=9)
    return r.finish()


HEART_ROWS = [(0.15, 2), (0.39, 3), (0.63, 2), (0.85, 2)]      # (height down the stone, shards across)


def heart_layout():
    """[(row, col)] for each shard, in order, and whose half it is: neighbours alternate."""
    out = []
    for row, (_fy, k) in enumerate(HEART_ROWS):
        for col in range(k):
            out.append((row, col, "you" if (row + col) % 2 == 0 else "companion"))
    return out


def heart_groups(r):
    """Assign every visible face to one of nine shards: Voronoi cells of nine seeds laid in rows over
    the stone's screen silhouette (2, 3, 2, 2 across, top to bottom), so the pieces are similar sizes."""
    ys, xs = np.nonzero(r.cov)
    y0, y1 = ys.min(), ys.max()
    seeds = []
    for (fy, k) in HEART_ROWS:
        sy = int(y0 + (y1 - y0) * fy)
        row = np.nonzero(r.cov[sy])[0]
        xl, xr = row.min(), row.max()
        for j in range(k):
            seeds.append((xl + (xr - xl) * (j + 0.5) / k, sy))
    seeds = np.array(seeds)
    # the screen centroid of each visible face
    n_faces = len(r.faces)
    cx = np.zeros(n_faces)
    cy = np.zeros(n_faces)
    cnt = np.zeros(n_faces)
    fid = r.fid
    m = fid >= 0
    np.add.at(cx, fid[m], np.nonzero(m)[1])
    np.add.at(cy, fid[m], np.nonzero(m)[0])
    np.add.at(cnt, fid[m], 1)
    vis = cnt > 0
    cx = np.where(vis, cx / np.maximum(cnt, 1), 0)
    cy = np.where(vis, cy / np.maximum(cnt, 1), 0)
    d = (cx[:, None] - seeds[None, :, 0]) ** 2 + ((cy[:, None] - seeds[None, :, 1]) * 0.8) ** 2
    group = np.argmin(d, axis=1)
    group[~vis] = -1
    # no empty shard: give an empty seed the nearest face still in a crowded shard
    for g in range(9):
        if not (group == g).any():
            order = np.argsort(d[:, g])
            for fi in order:
                if vis[fi] and (group == group[fi]).sum() > 2:
                    group[fi] = g
                    break
    return group


def heart_shards():
    """(whole image, [(shard image, info)], shadow image). Shard info offsets are world px from the
    stone's foot (the ground point under it) to the shard image's top-left."""
    r = heart_raster()
    whole = r.finish(shadow=False)
    group = heart_groups(r)
    owner = np.append(group, -1)[r.fid]
    shards = []
    for g in range(9):
        _row, _col, half = heart_layout()[g]
        tint = YOU_TINT if half == "you" else COMPANION_TINT
        img = r.finish(mask=(owner == g), shadow=False, tint=tint, tint_amt=TINT_AMOUNT)
        bb = img.getbbox()
        img = img.crop(bb)
        # keep an even size so the half-size draw lands on whole world px
        w2, h2 = img.size[0] + (img.size[0] % 2), img.size[1] + (img.size[1] % 2)
        pad = Image.new("RGBA", (w2, h2), (0, 0, 0, 0))
        pad.paste(img, (0, 0))
        left, top = bb[0], bb[1]
        if left % 2:
            pad = Image.new("RGBA", (w2 + 2, h2), (0, 0, 0, 0))
            pad.paste(img, (1, 0))
            left -= 1
        if top % 2:
            p2 = Image.new("RGBA", (pad.size[0], pad.size[1] + 2), (0, 0, 0, 0))
            p2.paste(pad, (0, 1))
            pad = p2
            top -= 1
        fx, fy = HEART_W / 2, HEART_FEET
        ox, oy = (left - fx) / PX, (top - fy) / PX
        sw, sh = pad.size[0] / PX, pad.size[1] / PX
        mask = owner == g
        ys, xs = np.nonzero(mask)
        faces = np.nonzero(group == g)[0]
        depth = float(np.mean([r.faces[i][1][1] * 0.77 + r.faces[i][1][2] * 0.64 for i in faces]))
        shards.append((pad, {
            "offset": [ox, oy],
            "size": [sw, sh],
            "center": [round((xs.mean() / SS - fx) / PX, 2), round((ys.mean() / SS - fy) / PX, 2)],
            "half": half,
            "depth": round(depth, 2),
        }))
    return whole, shards, heart_shadow()


# ============================================================================================ preview
def all_trees():
    out = []
    for v in PINE_VARIANTS:
        out.append(("pine_" + v, pine(v)))
    for v in ROUND_VARIANTS:
        out.append(("round_" + v, round_tree(v)))
    for v in SPIRE_VARIANTS:
        out.append(("spire_" + v, (spire(v), None)))
    for v in BOULDER_VARIANTS:
        out.append(("boulder_" + v, (boulder(v), None)))
    return out


def preview(path="glintwold.png"):
    bg = (0x8F, 0xCF, 0x8A, 255)
    def flat(pair):
        a, b = pair
        a = a.copy()
        if b is not None:
            a.alpha_composite(b)
        return a
    rows = []
    rows.append([flat(p) for _n, p in all_trees()])
    rows.append([flat(great_pine(v)) for v in ("a", "b")] + [hill(v) for v in HILL_VARIANTS])
    props = []
    demo = [hexc("#B8A6F0"), hexc("#8EE0E6"), hexc("#F9B9C0")]
    for i, name in enumerate(PROP_BUILDERS):
        base, tint = make_prop(name)
        im = base.copy()
        if tint is not None:
            arr = np.asarray(tint).astype(float) / 255
            arr[..., :3] *= np.array(demo[i % 3])
            im.alpha_composite(Image.fromarray((arr * 255).astype(np.uint8), "RGBA"))
        props.append(im)
    whole, shards, shadow = heart_shards()
    # the shards drawn back at their homes, then pulled apart a little
    fx, fy = HEART_W / 2, HEART_FEET
    rebuilt = Image.new("RGBA", (HEART_W, HEART_H), (0, 0, 0, 0))
    apart = Image.new("RGBA", (HEART_W + 80, HEART_H + 40), (0, 0, 0, 0))
    for img, info in shards:
        ox, oy = info["offset"]
        rebuilt.alpha_composite(img, (int(fx + ox * PX), int(fy + oy * PX)))
        cx, cy = info["center"]
        apart.alpha_composite(img, (int(40 + fx + ox * PX + cx * 0.5), int(20 + fy + oy * PX + (cy + 90) * 0.25)))
    props += [whole, rebuilt, apart, shadow]
    rows.append(props)
    sheets = [creature_sheet(sp, v) for sp in BUILD for v in range(3)]
    pad = 10
    w = max(max(sum(i.width + pad for i in row) for row in rows), max(s.width for s in sheets)) + pad
    h = sum(max(i.height for i in row) + pad for row in rows) + sum(s.height + pad for s in sheets) + pad
    canvas = Image.new("RGBA", (w, h), bg)
    y = pad
    for row in rows:
        rh = max(i.height for i in row)
        x = pad
        for im in row:
            canvas.alpha_composite(im, (x, y + rh - im.height))
            x += im.width + pad
        y += rh + pad
    for s in sheets:
        canvas.alpha_composite(s, (pad, y))
        y += s.height + pad
    canvas.save(path)
    print("wrote", path)


if __name__ == "__main__":
    import sys
    preview(sys.argv[1] if len(sys.argv) > 1 else "glintwold.png")
