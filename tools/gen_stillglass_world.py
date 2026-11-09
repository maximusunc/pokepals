#!/usr/bin/env python3
"""Generate STILLGLASS, the mirror lake, as a world spec.

A quiet (3400 x 2600), walk-and-wonder world: a perfectly flat silver lake, pale reeds, grey-green willows
and birches, and a sky that matches the water exactly. The lake mirrors whatever stands at its edge (the
reflection layer, `atmosphere.reflections`), and its reflections are slightly wrong: tall silver pines and a
pale great oak stand in the water that stand nowhere on the shore.

Its one SECRET (docs/home-world-and-secrets-design.md, "Stillglass"): a stone that only exists in the
reflection. Stand your companion at the water's edge and, once it settles, its reflection becomes a different
animal, turns and walks off along the north shore; follow it on the bank, step for step, to where it stops
and the real stone surfaces (reveal type "reflection"; ReflectionWalker / ReflectionDirector). The player's
own reflection is ordinary. All the numbers live in this file's data, not in code.

Hand-authored: regions, the lake's circles, the shore path's route, every lore line, the art override.
Procedural (seeded): the scatter of trees and props, kept clear of the shore path, the lake and the landing.
The lake's outline is computed exactly as the client draws it (WorldArt._organic_ring), so the shore path
lies on the real waterline. The ponds' own collision is a plain circle, which would disagree with that wobbly
bank by up to ~50 px, so the world turns pond collision OFF and walls the real shoreline with a chain of
invisible solid props ("sg_shore", an `unseen` type), so you stop at the water you can see.

Art comes from pokepals/tools/gen_stillglass.py. Writes the server seed and the client test fixture.
Run from the repo root:  python3 tools/gen_stillglass_world.py
"""
import json
import math
import random

random.seed(0x57111)

BOUNDS_MIN = (-1700, -1300)
BOUNDS_MAX = (1700, 1300)
PLAYER_SPAWN = [-1250, 700]
COMPANION_SPAWN = [-1280, 730]
PORTALS = [
    {"id": "stillglass_way_home", "type": "portal", "position": [-1322, 700], "color": [0.78, 0.88, 1.0], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

REGIONS = [
    ("sedge_landing",  (-1700, 500),  (-600, 1300),  (0.80, 0.90, 0.88)),
    ("south_shore",    (-600, 750),   (1700, 1300),  (0.82, 0.90, 0.92)),
    ("west_marsh",     (-1700, -150), (-600, 500),   (0.78, 0.90, 0.86)),
    ("still_water",    (-600, -150),  (1100, 750),   (0.86, 0.92, 0.98)),
    ("east_shallows",  (1100, -150),  (1700, 750),   (0.82, 0.90, 0.96)),
    ("grey_orchard",   (-1700, -1300), (-600, -150), (0.76, 0.88, 0.84)),
    ("silverbank",     (-600, -1300), (700, -150),   (0.84, 0.92, 0.96)),
    ("quiet_end",      (700, -1300),  (1700, -150),  (0.88, 0.92, 1.00)),
]

# ── the lake: four overlapping circles; centres are nudged for round north banks ────────────────────
SILVER = [0.70, 0.77, 0.82]
NOMINAL = [((-640, 170), 430), ((-200, 200), 470), ((260, 180), 470), ((700, 230), 400)]


def phase_for(cx, cy):
    return (cx * 0.013 + cy * 0.021) % math.tau


def organic_radius(a, r, s):
    return r * (1.0 + 0.11 * math.sin(3 * a + s) + 0.06 * math.sin(5 * a - s * 1.7) + 0.035 * math.sin(8 * a + s * 2.3))


def ring(cx, cy, r, segments=56):
    s = phase_for(cx, cy)
    pts = []
    for i in range(segments):
        a = math.tau * i / segments
        k = organic_radius(a, r, s)
        pts.append((cx + math.cos(a) * k, cy + math.sin(a) * k))
    return pts


PONDS = [{"center": [c[0], c[1]], "radius": r, "color": SILVER} for c, r in NOMINAL]
RINGS = [ring(p["center"][0], p["center"][1], p["radius"]) for p in PONDS]


def in_poly(p, poly):
    x, y = p
    inside = False
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        if (a[1] > y) != (b[1] > y) and x < a[0] + (y - a[1]) / (b[1] - a[1]) * (b[0] - a[0]):
            inside = not inside
    return inside


BBOX = [(min(q[0] for q in rg), min(q[1] for q in rg), max(q[0] for q in rg), max(q[1] for q in rg)) for rg in RINGS]


def is_water(p):
    for rg, (x0, y0, x1, y1) in zip(RINGS, BBOX):
        if x0 <= p[0] <= x1 and y0 <= p[1] <= y1 and in_poly(p, rg):
            return True
    return False


_WL = {}


def waterline(x, y0=-450.0, y1=700.0):
    """The y of the north waterline at x: the first water going down from y0."""
    key = round(x)
    if key not in _WL:
        _WL[key] = _waterline(float(key), y0, y1)
    return _WL[key]


def _waterline(x, y0, y1):
    y = y0
    while y < y1:
        if is_water((x, y)):
            lo, hi = y - 2.0, y
            for _ in range(10):
                mid = (lo + hi) / 2
                if is_water((x, mid)):
                    hi = mid
                else:
                    lo = mid
            return hi
        y += 3.0
    return None


# ── THE SHORE PATH: waterline points along the north bank, west to east ─────────────────────────────
START_X, END_X, STEP = -760, 900, 85
PATH = [(START_X, round(waterline(START_X), 1))]
while PATH[-1][0] < END_X:
    x0, y0 = PATH[-1]
    step = float(STEP)
    while True:
        x = min(END_X, x0 + step)
        y = waterline(x)
        if math.hypot(x - x0, y - y0) <= 95 or step < 6:
            break
        step *= 0.8
    PATH.append((round(x), round(y, 1)))
for (x, y) in PATH:
    assert is_water((x, y + 14)) and not is_water((x, y - 22)), "the shore path must stand on a north bank: %s" % ((x, y),)
START = PATH[0]
TRAIL = PATH[1:]
END = PATH[-1]
STONE = (END[0], round(END[1] - 16, 1))    # the stone surfaces on the bank, just up from where the reflection stops
assert not is_water(STONE)
TRAIL_LINE = PATH
path_len = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(PATH[:-1], PATH[1:]))
print("shore path: %d waypoints, %d px, start %s, stone %s" % (len(PATH), path_len, START, STONE))


def dist_to_path(p):
    best = 1e9
    for a, b in zip(PATH[:-1], PATH[1:]):
        ax, ay = a
        bx, by = b
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
        best = min(best, math.hypot(p[0] - (ax + dx * t), p[1] - (ay + dy * t)))
    return best


def near_lake(p, margin):
    return any(math.hypot(p[0] - pd["center"][0], p[1] - pd["center"][1]) < pd["radius"] * 1.25 + margin for pd in PONDS)


def prop(id, type, pos, color, label, lore=None, tags=None, solid=None, radius=None):
    p = {"id": id, "type": type, "position": [round(pos[0]), round(pos[1])], "color": [round(c, 2) for c in color], "label": label}
    if tags:
        p["tags"] = tags
    if lore:
        p["interactive"] = True
        p["lore"] = lore
    if solid is not None:
        p["solid"] = solid
    if radius is not None:
        p["collision_radius"] = radius
    return p


WHITE = (1.0, 1.0, 1.0)


def bank(x, gap):
    """A point `gap` px up the north bank from the waterline at x."""
    return (x, waterline(x) - gap)


# ── hand-placed props ───────────────────────────────────────────────────────────────────────────────
SPECIAL = [
    prop("landing_stone", "sg_sign_stone", (-1180, 650), WHITE, "a scratched stone",
         "Lines cut into the face of a slab, in a careful hand: 'Whoever walks beside you can see what the water sees. Stand them at the edge, "
         "up on the north bank, and be still. Then watch the water, and follow.'", solid=True, radius=8),
    prop("landing_cairn", "sg_cairn", (-1360, 760), WHITE, "a little cairn",
         "Three stones, stacked by someone who wanted to be remembered by a pile of stones. You add nothing. It is already enough.", solid=True, radius=7),
    prop("start_cairn", "sg_cairn", (START[0] - 70, START[1] - 78), WHITE, "a cairn at the bank",
         "The stones at the top of this one are wet, though nothing has splashed them. The bank here drops straight to the water. "
         "Stand quietly at its edge with your companion beside you.", solid=True, radius=7),
    prop("end_cairn", "sg_cairn", (END[0] + 90, END[1] - 70), WHITE, "a leaning cairn",
         "A cairn that leans toward the water, as if it were trying to see something in it.", solid=True, radius=7),
    prop("old_post", "sg_post", bank(-420, 92), WHITE, "a mooring post",
         "A post to tie a boat to. The rope round it has frayed to nothing. There has never been a boat on this lake, and the post knows it.", solid=True, radius=5),
    prop("old_post_2", "sg_post", bank(560, 92), WHITE, "another post",
         "A second post, standing a long way from the first. Between them the lake does exactly what the sky does.", solid=True, radius=5),
    prop("flat_stone_a", "sg_flat_stone", (-980, 520), WHITE, "a flat stone",
         "A flat grey stone. Skip it and it will cross the whole lake without a sound. You do not, because the lake is so quiet."),
    prop("flat_stone_b", "sg_flat_stone", bank(300, 110), WHITE, "a skipping stone",
         "A good skipping stone. Whatever you throw in here, the water gives a second one back, a little too neat."),
    prop("drift_log", "sg_driftlog", (-200, 740), WHITE, "a bleached log",
         "A bleached log on the south shore. Across the water the north bank is exactly as far away as it looks, which is not what you expected."),
    prop("south_boulder", "sg_boulder", (700, 900), WHITE, "a grey boulder",
         "A boulder with a patient face. The lake has no reflection of this bank. From here, you notice that, and it feels like being left out of a game.", solid=True, radius=8),
    prop("west_boulder", "sg_boulder", (-1400, 120), WHITE, "a boulder at the marsh",
         "Silver-green lichen, and under it the faint print of a hand that rested here.", solid=True, radius=8),
]

placed = [(p["position"][0], p["position"][1], 26) for p in SPECIAL]
LANDMARKS = [
    {"type": "great_willow", "position": [-1250, -650]},
    {"type": "great_oak", "position": [1250, -720]},
    {"type": "great_willow", "position": [200, 1050]},
]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 70))

# the phantoms: reflections with nothing on the shore. Each stands at a spot on the north bank 10..30 px up
# from the waterline, well off the walked path and away from every real tree; only the image is ever drawn.
PHANTOM_X = [(-1000, 0), (-880, 1), (-520, 2), (-380, 4), (-120, 1), (20, 0), (150, 5), (330, 2), (470, 3), (600, 1), (760, 0), (1010, 3), (-700, 4)]
PHANTOMS = []
for x, v in PHANTOM_X:
    y = waterline(x)
    gap = random.uniform(10, 26)
    PHANTOMS.append([x, round(y - gap, 1), v])
phantom_src = [(p[0], p[1]) for p in PHANTOMS]


def clear(x, y, r):
    if not (BOUNDS_MIN[0] + 140 <= x <= BOUNDS_MAX[0] - 140 and BOUNDS_MIN[1] + 140 <= y <= BOUNDS_MAX[1] - 140):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 190:
        return False
    if near_lake((x, y), r) and (is_water((x, y)) or any(is_water((x + dx, y + dy)) for dx, dy in ((r, 0), (-r, 0), (0, r), (0, -r)))):
        return False
    if is_water((x, y + 18)):   # keep the very edge clear of trunks: a tree on the edge hides its own reflection's root
        return False
    # the whole walk stays open: you walk the bank, the companion beside you
    if dist_to_path((x, y)) < 74 + r:
        return False
    if any(math.hypot(x - px, y - py) < 56 + r for px, py in phantom_src):
        return False
    if math.hypot(x - STONE[0], y - STONE[1]) < 110 + r or math.hypot(x - START[0], y - START[1]) < 110 + r:
        return False
    return all(math.hypot(x - px, y - py) >= r + pr for px, py, pr in placed)


def scatter(region_id, n, r, tries=5000, band=None):
    rmin, rmax = next((a, b) for rid, a, b, _ in REGIONS if rid == region_id)
    out = []
    for _ in range(tries):
        if len(out) >= n:
            break
        x = random.uniform(rmin[0], rmax[0])
        y = random.uniform(rmin[1], rmax[1])
        if band is not None:
            # prefer the bank: within `band` px above the north waterline
            wl = waterline(x)
            if wl is None or not (wl - band[1] <= y <= wl - band[0]):
                continue
        if clear(x, y, r):
            placed.append((x, y, r))
            out.append((round(x), round(y)))
    return out


TREES = []
PROPS = []


def trees(region, n, kind, r=26, band=None):
    for x, y in scatter(region, n, r, band=band):
        TREES.append([x, y, kind])


def props(region, n, type, label, r=16, solid=None, radius=None, band=None):
    for i, (x, y) in enumerate(scatter(region, n, r, band=band)):
        PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), WHITE, label, solid=solid, radius=radius))


# The bank itself: willows and birches standing 76..170 px up from the waterline, so their images hang in the
# water (the reflection layer reaches 140 px) with room between for the walk.
for reg in ("grey_orchard", "silverbank", "quiet_end"):
    trees(reg, 14 if reg == "silverbank" else 10, "willow", 26, band=(76, 150))
    trees(reg, 14 if reg == "silverbank" else 10, "birch", 22, band=(76, 160))
    trees(reg, 5, "round", 26, band=(90, 170))
# the quiet northern woods, behind the bank
trees("grey_orchard", 45, "round", 26)
trees("grey_orchard", 20, "oak", 30)
trees("silverbank", 40, "round", 26)
trees("silverbank", 18, "oak", 30)
trees("quiet_end", 36, "round", 26)
trees("quiet_end", 16, "oak", 30)
props("silverbank", 12, "sg_reedclump", "a clump of reeds", r=18)
props("grey_orchard", 8, "sg_flat_stone", "a flat stone", r=18)
props("quiet_end", 8, "sg_boulder", "a grey boulder", r=18, solid=True, radius=8)
# the lake's other shores: reeds, a few trees, open turf
trees("sedge_landing", 22, "willow", 26)
trees("sedge_landing", 14, "birch", 22)
props("sedge_landing", 14, "sg_reedclump", "a clump of reeds", r=18)
trees("west_marsh", 20, "willow", 26)
trees("west_marsh", 10, "round", 26)
props("west_marsh", 18, "sg_reedclump", "a clump of reeds", r=18)
props("west_marsh", 6, "sg_boulder", "a grey boulder", r=18, solid=True, radius=8)
trees("south_shore", 30, "round", 26)
trees("south_shore", 20, "birch", 22)
trees("south_shore", 10, "oak", 30)
props("south_shore", 20, "sg_reedclump", "a clump of reeds", r=18)
props("south_shore", 8, "sg_flat_stone", "a flat stone", r=18)
trees("east_shallows", 24, "willow", 26)
trees("east_shallows", 12, "round", 26)
props("east_shallows", 16, "sg_reedclump", "a clump of reeds", r=18)
trees("still_water", 6, "willow", 26)



def shore_chain(spacing=14.0, inset=-2.0):
    """Centres along the union's outer boundary, a little inside the drawn waterline."""
    pts = []
    for pd, rg in zip(PONDS, RINGS):
        n = len(rg)
        for i in range(n):
            a, b = rg[i], rg[(i + 1) % n]
            seg = math.hypot(b[0] - a[0], b[1] - a[1])
            k = max(1, int(seg / spacing))
            for j in range(k):
                t = j / k
                x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                if any(o is not rg and in_poly((x, y), o) for o in RINGS):
                    continue
                dx, dy = pd["center"][0] - x, pd["center"][1] - y
                dl = math.hypot(dx, dy) or 1.0
                pts.append((x + dx / dl * inset, y + dy / dl * inset))
    return pts


SHORE = [{"id": "shore_%d" % i, "type": "sg_shore", "position": [round(x), round(y)], "color": [1.0, 1.0, 1.0], "label": "", "solid": True, "collision_radius": 8}
         for i, (x, y) in enumerate(shore_chain())]
print("shore wall:", len(SHORE), "solid posts")
ALL_PROPS = SPECIAL + PROPS + SHORE

# ── the world's own ART OVERRIDE (deep-merged over data/art.json by ArtStyle.load_style) ─────────────
S = "res://assets/sprites/"


def ramp(*rows):
    return [list(r) for r in rows]


def tree_variants(names):
    return [{"trunk": S + "sg_%s_trunk.png" % n, "canopy": S + "sg_%s_canopy.png" % n} for n in names]


WILLOWS = ["willow_a", "willow_b"]
BIRCHES = ["birch_a", "birch_b", "birch_c"]
ROUNDS = ["round_a", "round_b"]
OAKS = ["oak_a", "oak_b"]
ART = {
    # the sky matches the water: pale silver, a touch of blue
    "palette": {
        "ground_top": [0.62, 0.72, 0.68], "ground_bottom": [0.52, 0.62, 0.60],
        "foliage_dark": [0.24, 0.34, 0.32], "foliage_mid": [0.44, 0.56, 0.52], "foliage_light": [0.74, 0.84, 0.80],
        "bark": [0.40, 0.38, 0.34], "water": [0.70, 0.77, 0.82], "rim": [0.92, 0.96, 0.98],
        "shadow": [0.18, 0.24, 0.30], "grass": [0.62, 0.72, 0.68], "water_rim": [0.93, 0.97, 1.0, 0.7],
    },
    "light": {"shadow_alpha": 0.16, "rim_strength": 0.15},
    "entities": {
        "portal": {"frame_tint": [0.80, 0.90, 1.0]},
        "ground": {
            "render": "pixel", "terrain": S + "sg_terrain.png", "tile": 128,
            "details": S + "sg_details.png", "details_index": "res://data/sg_details.json",
            "shade": 0.1,
            "ramps": {
                "grass": ramp((0.54, 0.65, 0.61), (0.58, 0.69, 0.65), (0.62, 0.73, 0.68), (0.78, 0.88, 0.84)),
                "lush": ramp((0.51, 0.62, 0.58), (0.55, 0.66, 0.62), (0.59, 0.70, 0.65), (0.75, 0.85, 0.81)),
                "meadow": ramp((0.57, 0.68, 0.63), (0.61, 0.72, 0.67), (0.65, 0.76, 0.70), (0.82, 0.91, 0.86)),
                "dirt": ramp((0.52, 0.55, 0.54), (0.58, 0.61, 0.60), (0.64, 0.67, 0.65), (0.78, 0.80, 0.78)),
                "sand": ramp((0.66, 0.72, 0.72), (0.72, 0.78, 0.77), (0.78, 0.84, 0.82), (0.92, 0.96, 0.94)),
                "path": ramp((0.56, 0.60, 0.58), (0.64, 0.68, 0.65), (0.72, 0.76, 0.72), (0.84, 0.88, 0.84)),
                "worn": ramp((0.54, 0.64, 0.60), (0.62, 0.72, 0.66), (0.70, 0.79, 0.72), (0.84, 0.91, 0.86)),
            },
            "accents": [[0.94, 0.96, 1.0]],
            "patches": {"lush": {"scale": 0.0034, "threshold": 0.50}, "meadow": {"scale": 0.005, "threshold": 0.62},
                        "dirt": {"scale": 0.006, "threshold": 1.6}},
            "clump": {"scale": 0.008, "dark": 0.36, "light": 0.64},
            "scatter": {
                "density": 0.5,
                "open": [
                    {"names": ["sedge_a", "sedge_b"], "weight": 20, "count": [1, 3], "sway": 0.25},
                    {"names": ["clover"], "weight": 12, "count": [1, 3]},
                    {"names": ["moonwort"], "weight": 9, "count": [1, 2]},
                    {"names": ["pebbles"], "weight": 10, "count": [1, 2]},
                    {"names": ["flatstone"], "weight": 4},
                    {"names": ["twig", "feather"], "weight": 4},
                ],
                "under_trees": {"names": ["twig", "clover"], "ring": ["moonwort"]},
                "path_edge": [],
                "reeds": ["silverreed"],
                "lilies": [],
            },
        },
        "understory": {"render": "sprite", "prefix": S + "sg_understory_", "types": ["bush_a", "bush_b", "stump"], "density": 0.4},
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 0}, "clouds": {"count": 2, "alpha": 0.05, "speed": 4},
                         "leaves": {"rate": 0.25, "colors": [[0.84, 0.92, 0.88], [0.92, 0.96, 0.96]]}},
        "tree": {"render": "sprite", "sway": 0.3, "variants": tree_variants(WILLOWS * 2 + BIRCHES * 2 + ROUNDS * 2 + OAKS)},
        "willow": {"render": "sprite", "sway": 0.4, "variants": tree_variants(WILLOWS)},
        "birch": {"render": "sprite", "sway": 0.4, "variants": tree_variants(BIRCHES)},
        "round": {"render": "sprite", "sway": 0.3, "variants": tree_variants(ROUNDS)},
        "oak": {"render": "sprite", "sway": 0.25, "variants": tree_variants(OAKS)},
        "great_tree": {"render": "sprite", "sway": 0.2, "variants": tree_variants(["great_oak"])},
        "great_willow": {"render": "sprite", "sway": 0.25, "variants": tree_variants(["great_willow"])},
        "great_oak": {"render": "sprite", "sway": 0.2, "variants": tree_variants(["great_oak"])},
        "water": {"render": "sprite", "tile": S + "sg_water.png", "world_tile": 64},
        "pool": {"render": "sprite", "tile": S + "sg_water.png", "world_tile": 64},
        "river": {"render": "sprite", "tile": S + "sg_water.png", "world_tile": 64},
        "props": {"unseen": ["sg_shore"], "extra_types": ["sg_boulder", "sg_flat_stone", "sg_cairn", "sg_driftlog", "sg_reedclump", "sg_post", "sg_sign_stone"]},
    },
    "daycycle": {"enabled": True, "period_sec": 480, "loop": True, "stops": [
        {"t": 0.0, "tint": [0.95, 0.98, 1.02], "vignette": [0.50, 0.58, 0.66], "vstrength": 0.28},
        {"t": 1.0, "tint": [0.92, 0.95, 1.02], "vignette": [0.44, 0.52, 0.64], "vstrength": 0.34},
    ]},
}

PHANTOM_SPRITES = [{"trunk": S + "sg_ghost_%s_trunk.png" % n, "canopy": S + "sg_ghost_%s_canopy.png" % n}
                   for n in ["pine_a", "pine_b", "pine_c", "willow", "birch", "great"]]

ATMOSPHERE = {
    "day_tint": [0.95, 0.98, 1.02],
    "vignette": {"strength": 0.28, "color": [0.50, 0.58, 0.66]},
    "wind": {"strength": 0.5, "speed": 0.4},
    "pollen": {"amount": 18, "color": [0.92, 0.96, 1.0]},
    "region_tint_alpha": 0.04,
    "grass": {"max": 0},
    "sparkles": {"count": 260, "colors": [[0.96, 0.98, 1.0], [0.80, 0.90, 1.0]]},
    # THE REFLECTION LAYER (ReflectionLayer): every actor and tree near the lake's north bank is drawn
    # mirrored in the water, clipped to it; `phantoms` are trees in the water with nothing on the shore
    # ([x, base_y, sprite]: where the tree's base would stand, 10..26 px up from the waterline).
    "reflections": {
        "reach": 110.0, "tree_reach": 150.0, "strength": 0.8, "silver": [0.50, 0.60, 0.72], "silver_mix": 0.30,
        "wobble": 1.0, "fade_len": 96.0, "phantom_strength": 0.9, "phantom_tint": [0.84, 0.92, 1.0],
        "phantom_sprites": PHANTOM_SPRITES, "phantoms": PHANTOMS,
    },
}

HEADER = ("STILLGLASS - a mirror lake. A walk-and-wonder world (no goal, no puzzle): a perfectly flat silver lake, pale reeds, "
          "grey-green willows and birches, a sky that matches the water. The lake mirrors whatever stands at its north bank "
          "(atmosphere.reflections: the reflection layer), and its reflections are slightly wrong (the 'phantoms': tall silver "
          "pines and a great oak in the water with nothing on the shore). Eight regions: Sedge Landing (where you arrive), South "
          "Shore, West Marsh, Still Water, East Shallows, Grey Orchard, Silverbank and Quiet End. It RE-SKINS ITSELF through its "
          "'art' block (deep-merged over data/art.json): its own turf + litter atlas, silver-green trees (tree entries "
          "[x, y, kind]: willow/birch/round/oak), silver water. Its secret is a stone that only exists in the reflection: see the "
          "'secret' block (reveal type 'reflection'). Generated by tools/gen_stillglass_world.py (art: pokepals/tools/gen_stillglass.py) "
          "- edit that and re-run, don't hand-tune positions.")

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Stillglass'). reveal.type 'reflection': stand the "
                  "companion at the water's edge by 'start' and, once it settles, its reflection turns into a different animal "
                  "(picked from 'species_pool', never the one worn) and walks the shore along 'trail' (waterline waypoints, the last is "
                  "where the stone surfaces), waiting when the player falls behind (ReflectionWalker / ReflectionDirector); at the end the "
                  "prop rises. The server honours a claim only here, within 'radius' of 'position'.")
SECRET = {
    "id": "mirror_stone",
    "position": list(STONE),
    "radius": 120.0,
    "prop": {"type": "mirror_stone", "color": [0.80, 0.88, 0.96], "label": "a stone from the water", "tags": ["cold", "smooth", "odd", "quiet"]},
    "lore": "A smooth grey stone, cold as the lake, and so still it seems to be listening. It is dry. When you look at it, the water below holds its picture a moment longer than it should.",
    "reveal": {
        "type": "reflection",
        "species_pool": ["cat", "fox", "rabbit", "bird", "wolf"],
        "start": [START[0], START[1]],
        "trail": [list(p) for p in TRAIL],
        "edge_radius": 190.0, "player_radius": 280.0, "linger_seconds": 1.2, "linger_speed": 34.0, "approach_offset": [0.0, -26.0],
        "settle_seconds": 1.0, "settle_speed": 14.0, "turn_seconds": 1.8, "pace": 68.0,
        "wait_distance": 200.0, "resume_distance": 120.0, "companion_radius": 380.0, "give_up_distance": 760.0,
        "waypoint_reach": 8.0, "done_hold": 6.0, "stone_delay": 1.0, "drift_hold": 30.0, "gaze": 1.0,
        "notice_range_low": 280.0, "notice_range_high": 620.0, "notice_cooldown_low": 16.0, "notice_cooldown_high": 6.0, "notice_hold": 2.5,
        "lines": {
            "notice": "Your companion stops and gazes at the water, head tilted. Something down there has caught its eye.",
            "approach": "Your companion pads to the edge and looks down at itself.",
            "gather": "The water stirs round your companion's reflection. It is not quite keeping still.",
            "turn": "Your companion's reflection is someone else now. It turns its back on you.",
            "set_off": "It walks off along the water, and glances back, once, to see whether you will follow.",
            "wait": "The reflection stands and waits, up to its ankles in nothing, until you catch up.",
            "lost": "The reflection goes back to being only a reflection. It remembers where it got to.",
            "follow": "Your companion keeps its eyes on the reflection, and walks the bank beside it. You walk after them both.",
        },
        "reveal_line": "The reflection stops, and the water rings round its feet. On the bank, where it stands, a stone has come up out of the ground. It is dry.",
    },
    "found_line": "The stone was only ever in the lake. Your companion's other self showed you where, and then it went back to being a reflection.",
    "home_line": "Something has changed at home.",
    "qualities": ["quiet", "watery", "old"],
    "keepsake": {
        "id": "mirror_dish", "type": "kept_mirror_stone", "color": [0.80, 0.88, 0.96], "label": "a stone and its reflection, in a dish of water",
        "line": "A little stone in a dish of still water. The reflection is a touch too bright, and sometimes, if you look at the right moment, it is not quite facing the same way.",
        "temperament": {"curiosity": 0.7, "energy": 0.4, "clinginess": 0.5},
    },
}


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "stillglass",')
out.append('\t"intro": %s,' % json.dumps("A lake so still it keeps a second copy of everything, and does not always copy faithfully. Stand a while at its edge."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": true, "spacing": 120, "inset": 24, "jitter": 34, "rows": 2, "row_gap": 60 },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": false, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.60, 0.70, 0.66],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [\n%s\n\t],' % block(PONDS))
out.append('\t"paths": [],')
out.append('\t"landmarks": [\n%s\n\t],' % block(LANDMARKS))
out.append('\t"trees": [\n%s\n\t],' % block(TREES))
out.append('\t"props": [\n%s\n\t],' % block(ALL_PROPS))
out.append('\t"_secret_comment": %s,' % json.dumps(SECRET_COMMENT))
out.append('\t"secret": %s,' % json.dumps(SECRET, indent="\t", ensure_ascii=False).replace("\n", "\n\t"))
out.append('\t"portals": [\n%s\n\t]' % block(PORTALS))
out.append("}")
text = "\n".join(out) + "\n"

# ── validate ─────────────────────────────────────────────────────────────────────────────────────────
d = json.loads(text)
ids = [p["id"] for p in d["props"]]
assert len(ids) == len(set(ids)), "duplicate ids"
for p in d["props"]:
    assert bool(p.get("interactive")) == bool(p.get("lore")), "interactive iff lore: %s" % p["id"]
    x, y = p["position"]
    assert BOUNDS_MIN[0] < x < BOUNDS_MAX[0] and BOUNDS_MIN[1] < y < BOUNDS_MAX[1], p["id"]
    assert p["id"].startswith("shore_") or not is_water((x, y)), "prop in the water: %s" % p["id"]
for t in d["trees"]:
    assert not is_water((t[0], t[1])), "tree in the water: %s" % t
for a, b in zip(PATH[:-1], PATH[1:]):
    assert math.hypot(b[0] - a[0], b[1] - a[1]) < 120, "shore path leg too long"
for t in d["trees"]:
    assert dist_to_path((t[0], t[1])) > 70, "a tree stands on the walk: %s" % t
for p in d["props"]:
    if p["id"] in ("start_cairn", "end_cairn") or p["id"].startswith("shore_"):
        continue
    assert dist_to_path(p["position"]) > 40 or p["id"].startswith("sg_"), "a prop stands on the walk: %s" % p["id"]
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("props:", len(d["props"]), "| trees:", kinds, "| phantoms:", len(PHANTOMS))
for path in ["server/priv/world_seeds/stillglass.json", "pokepals/tests/world_fixtures/stillglass.json"]:
    open(path, "w").write(text)
print("wrote both files")
