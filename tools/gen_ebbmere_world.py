#!/usr/bin/env python3
"""Generate EBBMERE, the tidal flats, as a world spec.

A wide (3600 x 2600), calm, salty walk-and-wonder world: wet sand that holds the sky, tide pools, creeks,
shell ridges, a stranded rowboat and a lighthouse on a rocky point. The TIDE slowly goes out and comes back on
a shared clock (a pure function of UTC time: tide.period_s, so everyone sees the same water). The drawn
waterline, the sand you can wade and where things are buried all follow it.

How the tide is drawn and read: the world carries a baked SEABED, one 16-bit value per 16 px cell (`tide.field`),
elevation 0..1. The water covers a point whenever the tide level is above its elevation, so one grid says
where the waterline is at every moment. Elevation under `deep_elev` is open sea, too deep to wade; it is
walled with invisible posts (the Stillglass lesson: a drawn shore and a collision shape must agree, so the
posts are placed from the very grid the shader samples). Everything else, however far the tide covers it, is
wadeable.

Its one SECRET (docs/home-world-and-secrets-design.md, "Ebbmere"): a sand-dollar that rises only at the
lowest tide, buried on the far bar (reveal type "tide"). While the tide is out the companion sniffs out the
buried spots; tap one and a form that can dig (fox, rabbit, wolf) digs it. Most give up shells, or a crab that
scuttles off; the one on the far bar gives up the sand-dollar, but only in this tide's lowest window.

Hand-authored: regions, the creeks, bars, pools' rules, the lighthouse point, every lore line, the art
override. Procedural (seeded): pools, dig spots, the scatter of props and dune trees. Writes the server seed
and the client test fixture. Run from the repo root:  python3 tools/gen_ebbmere_world.py
"""
import base64
import json
import math
import random

random.seed(0xEBB)

BOUNDS_MIN = (-1800, -1300)
BOUNDS_MAX = (1800, 1300)
PLAYER_SPAWN = [-1250, 860]
COMPANION_SPAWN = [-1280, 890]
PORTALS = [
    {"id": "ebbmere_way_home", "type": "portal", "position": [-1322, 860], "color": [0.80, 0.90, 0.92], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

REGIONS = [
    ("dune_landing",  (-1800, 500),   (-600, 1300),  (0.96, 0.92, 0.84)),
    ("wrack_line",    (-600, 500),    (1800, 1300),  (0.96, 0.93, 0.86)),
    ("cockle_ridge",  (-1800, -200),  (-600, 500),   (0.94, 0.90, 0.84)),
    ("pool_terrace",  (-600, -200),   (700, 500),    (0.92, 0.92, 0.88)),
    ("the_creeks",    (700, -200),    (1800, 500),   (0.90, 0.92, 0.90)),
    ("far_bars",      (-1800, -700),  (1000, -200),  (0.88, 0.92, 0.94)),
    ("lantern_point", (1000, -700),   (1800, -200),  (0.94, 0.92, 0.88)),
    ("greywater",     (-1800, -1300), (1800, -700),  (0.84, 0.90, 0.94)),
]

# ── THE TIDE: one cosine per period, a pure function of UTC time (TideClock / Server.Tide) ──────────
TIDE = {"period_s": 360.0, "epoch_s": 0.0, "level_low": 0.30, "level_high": 0.78, "yield_level": 0.345}
DEEP_ELEV = 0.26
EXPOSE_MARGIN = 0.012
DOLLAR_ELEV = TIDE["yield_level"] + EXPOSE_MARGIN     # the bar shows exactly while the level is under yield_level
CELL = 16
GW = int((BOUNDS_MAX[0] - BOUNDS_MIN[0]) / CELL)      # 225
GH = int(math.ceil((BOUNDS_MAX[1] - BOUNDS_MIN[1]) / CELL))   # 163


def sm(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def shelf_y(x):
    return -880 + 70 * math.sin(x / 310.0) + 40 * math.sin(x / 130.0 + 1.0)


CREEKS = [
    [(-900, 330), (-950, 40), (-800, -240), (-860, -520), (-790, -820)],
    [(300, 520), (240, 220), (420, -90), (380, -420), (450, -760)],
    [(900, 450), (960, 150), (1060, -150), (1110, -420), (1060, -780)],
]
CREEK_FLOOR = 0.285
CREEK_HALF = 24.0
BARS = [   # shell ridges: a long low rise
    ((-1560, -60), (-1240, 40), (-980, 190)),
    ((-420, 120), (-120, 60), (200, 110), (520, 40)),
    ((-300, -380), (0, -430), (330, -360)),
    ((1150, 330), (1400, 270), (1650, 330)),
    ((-1450, 330), (-1250, 280)),
]
LIGHT_BASE = (1400, -160)
LIGHT_ELEV = 0.99
DOLLAR_X = -430.0
DOLLAR = (DOLLAR_X, round(shelf_y(DOLLAR_X) + 150.0))


def seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
    return math.hypot(p[0] - (ax + dx * t), p[1] - (ay + dy * t))


def poly_dist(p, pts):
    return min(seg_dist(p, a, b) for a, b in zip(pts[:-1], pts[1:]))


POOLS = []     # (x, y, radius); filled below from the base field


def base_elev(x, y):
    d = y - shelf_y(x)
    if d <= 0:
        return 0.28 - 0.23 * sm(0, 90, -d)
    t = d / 1500.0
    if t <= 1.0:
        e = 0.28 + 0.52 * (0.85 * t + 0.15 * t * t)
    else:
        e = 0.80 + 0.17 * sm(0.0, 1.0, (t - 1.0) / 0.25)
    e += 0.018 * math.sin(x / 170.0 + 1.3 * math.sin(y / 230.0)) + 0.014 * math.sin(y / 97.0 + x / 310.0) + 0.010 * math.sin((x + y) / 61.0)
    for bar in BARS:
        dist = poly_dist((x, y), list(bar))
        e += 0.07 * math.exp(-(dist / 55.0) ** 2)
    return e


def elev(x, y):
    e = base_elev(x, y)
    d = y - shelf_y(x)
    if d > 0:
        e = max(e, 0.275)
    # the rocky point the lighthouse stands on: always dry
    r = math.hypot(x - LIGHT_BASE[0], y - LIGHT_BASE[1])
    w = 1.0 - sm(95, 210, r)
    e = e + (max(e, LIGHT_ELEV) - e) * w
    # creeks and pools carry water through every tide (their floor is under the lowest water, over the sea's depth)
    for creek in CREEKS:
        dist = poly_dist((x, y), creek)
        if dist < CREEK_HALF * 3:
            e = min(e, CREEK_FLOOR + 0.22 * (dist / (CREEK_HALF * 3)) ** 2 * 3.0 if dist > CREEK_HALF else CREEK_FLOOR)
    for (px, py, pr) in POOLS:
        dist = math.hypot(x - px, y - py)
        if dist < pr * 1.6:
            e = min(e, CREEK_FLOOR + 0.3 * sm(pr * 0.7, pr * 1.6, dist))
    # the far bar: a low sandbar whose top shows exactly while the tide is at its lowest
    dd = math.hypot(x - DOLLAR[0], y - DOLLAR[1])
    wb = 1.0 - sm(45, 100, dd)
    e = e + (DOLLAR_ELEV - e) * wb
    return max(0.0, min(1.0, e))


def pick_pools():
    rng = random.Random(0xB00)
    out = []
    tries = 0
    while len(out) < 15 and tries < 4000:
        tries += 1
        x = rng.uniform(-1650, 1650)
        y = rng.uniform(-560, 460)
        b = base_elev(x, y)
        if not (0.42 <= b <= 0.66):
            continue
        if math.hypot(x - LIGHT_BASE[0], y - LIGHT_BASE[1]) < 330 or math.hypot(x - DOLLAR[0], y - DOLLAR[1]) < 200:
            continue
        if any(poly_dist((x, y), c) < 110 for c in CREEKS):
            continue
        r = rng.uniform(34, 72)
        if any(math.hypot(x - ox, y - oy) < r + orr + 150 for ox, oy, orr in out):
            continue
        out.append((round(x), round(y), round(r)))
    return out


POOLS = pick_pools()

# ── bake the seabed ─────────────────────────────────────────────────────────────────────────────────
FIELD = [0] * (GW * GH)     # 16-bit elevations (a single byte stair-stepped the gentle flats into squares)
for j in range(GH):
    for i in range(GW):
        FIELD[j * GW + i] = int(round(elev(BOUNDS_MIN[0] + (i + 0.5) * CELL, BOUNDS_MIN[1] + (j + 0.5) * CELL) * 65535.0))


def _at(i, j):
    return FIELD[max(0, min(GH - 1, j)) * GW + max(0, min(GW - 1, i))] / 65535.0


def field_elev(x, y):
    """The same bilinear read TideField.elev_at does (cell centres), so posts and spots agree with the client."""
    fx = (x - BOUNDS_MIN[0]) / CELL - 0.5
    fy = (y - BOUNDS_MIN[1]) / CELL - 0.5
    x0, y0 = math.floor(fx), math.floor(fy)
    tx, ty = fx - x0, fy - y0
    top = _at(x0, y0) * (1 - tx) + _at(x0 + 1, y0) * tx
    bot = _at(x0, y0 + 1) * (1 - tx) + _at(x0 + 1, y0 + 1) * tx
    return top * (1 - ty) + bot * ty


def is_deep(x, y):
    return field_elev(x, y) < DEEP_ELEV


# the deep sea's edge, walled with invisible posts so you stop at the drop-off you can see
POSTS = []
STEP = 12
for gy in range(int(BOUNDS_MIN[1]) + 6, int(BOUNDS_MAX[1]), STEP):
    for gx in range(int(BOUNDS_MIN[0]) + 6, int(BOUNDS_MAX[0]), STEP):
        if is_deep(gx, gy):
            continue
        if any(is_deep(gx + dx, gy + dy) for dx, dy in ((STEP, 0), (-STEP, 0), (0, STEP), (0, -STEP), (STEP, STEP), (-STEP, -STEP))):
            POSTS.append((gx, gy))
SHORE = [{"id": "shore_%d" % i, "type": "eb_shore", "position": [x, y], "color": [1.0, 1.0, 1.0], "label": "", "solid": True, "collision_radius": 8}
         for i, (x, y) in enumerate(POSTS)]
print("seabed %dx%d cells, %d pools, %d shore posts" % (GW, GH, len(POOLS), len(POSTS)))


def near_posts(p, r):
    return any(math.hypot(p[0] - x, p[1] - y) < r for x, y in POSTS)


# ── dig spots ───────────────────────────────────────────────────────────────────────────────────────
def find_spots():
    rng = random.Random(0xD16)
    out = []
    tries = 0
    while len(out) < 26 and tries < 20000:
        tries += 1
        x = rng.uniform(-1700, 1700)
        y = rng.uniform(-720, 560)
        e = field_elev(x, y)
        if not (0.37 <= e <= 0.74):
            continue
        if any(math.hypot(x - px, y - py) < pr * 1.8 + 30 for px, py, pr in POOLS):
            continue
        if any(poly_dist((x, y), c) < CREEK_HALF * 2.4 for c in CREEKS):
            continue
        if math.hypot(x - LIGHT_BASE[0], y - LIGHT_BASE[1]) < 260 or math.hypot(x - DOLLAR[0], y - DOLLAR[1]) < 150:
            continue
        if near_posts((x, y), 60):
            continue
        if any(math.hypot(x - ox, y - oy) < 150 for ox, oy, _ in out):
            continue
        out.append((round(x), round(y), round(e, 3)))
    return out


SPOT_POS = find_spots()
DIG_SPOTS = [{"id": "bar_dollar", "position": [DOLLAR[0], DOLLAR[1]]}]
DIG_SPOTS += [{"id": "spot_%02d" % i, "position": [x, y]} for i, (x, y, _) in enumerate(SPOT_POS)]
assert len(DIG_SPOTS) >= 20, "too few dig spots: %d" % len(DIG_SPOTS)
dollar_e = field_elev(*DOLLAR)
assert abs(dollar_e - DOLLAR_ELEV) < 0.006, "the far bar must stand at the yield level + margin (%.4f vs %.4f)" % (dollar_e, DOLLAR_ELEV)
assert not is_deep(*DOLLAR)
print("dollar spot", DOLLAR, "elev %.4f" % dollar_e, "| %d spots" % len(DIG_SPOTS))


# ── props and trees ─────────────────────────────────────────────────────────────────────────────────
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
GAUGE = (-1160, 770)
SPECIAL = [
    prop("landing_stone", "eb_tide_stone", (-1170, 810), WHITE, "a stone with waves cut in it",
         "Wavy lines are cut into the face of the stone, row on row, and under them a few words in a careful hand: 'It goes out, it comes back. "
         "Go down to the flats while the water is away. Your companion has a nose for what it leaves behind. Lowest of all, the far bars show, "
         "and what is under them rises.'", solid=True, radius=8),
    prop("landing_cairn", "eb_cairn", (-1370, 920), WHITE, "a little cairn",
         "Three stones, stacked above the high-water line by someone who trusted the tide to leave them alone. It has.", solid=True, radius=7),
    prop("old_rowboat", "eb_rowboat", (-1180, 120), WHITE, "a stranded rowboat",
         "A rowboat, left on its keel on the ridge by a tide that never came back for it. The paint has gone to chalk. In the bottom, "
         "a good many shells, collected by something that was not you.", solid=True, radius=14),
    prop("far_buoy", "eb_buoy", (-120, -610), WHITE, "a red buoy",
         "A buoy, left high and dry. Whoever it was marking is long gone, but the far bars are out this way. They are only bare at the very lowest water."),
    prop("groyne_a", "eb_groyne", (-560, 380), WHITE, "an old groyne post",
         "One of a row of posts that once held the sand in place. The sand left anyway, and came back, and left.", solid=True, radius=5),
    prop("groyne_b", "eb_groyne", (-480, 400), WHITE, "an old groyne post",
         "Barnacles all the way up to where the highest tide reaches, and none above it.", solid=True, radius=5),
    prop("groyne_c", "eb_groyne", (-400, 424), WHITE, "an old groyne post",
         "The third post, a little shorter, as if the sea had been nibbling at it for years. It has."),
    prop("point_rock", "eb_rock_big", (1310, -100), WHITE, "a barnacled rock",
         "The rock the lighthouse stands on, here at the point's foot. Under the barnacles, a smooth patch where hands have rested.", solid=True, radius=14),
    prop("point_cairn", "eb_cairn", (1500, -80), WHITE, "a cairn on the point",
         "Built by lamplighters, one stone a night. Nobody ever knocks it down. Nobody ever finishes it either.", solid=True, radius=7),
    prop("old_log", "eb_driftwood", (-1500, 380), WHITE, "a bleached log",
         "A log from somewhere much further away than this. You wonder what it saw. It would say 'water', mostly."),
    prop("shell_heap_big", "eb_shellheap", (-1060, 150), WHITE, "a heap of shells",
         "Cockles, whelks and razor shells, heaped by wind and waves along the ridge. A scallop on top is the pink of the inside of a lip."),
    prop("first_wrack", "eb_wrack", (-300, 330), WHITE, "a heap of wrack",
         "Seaweed, left in a line where the last tide turned. It smells exactly like the word 'sea'."),
]

placed = [(p["position"][0], p["position"][1], 26) for p in SPECIAL]
placed += [(x, y, 56) for x, y, _ in SPOT_POS] + [(DOLLAR[0], DOLLAR[1], 80)]
placed.append((GAUGE[0], GAUGE[1], 40))
placed.append((LIGHT_BASE[0], LIGHT_BASE[1], 60))
LANDMARKS = [{"type": "lighthouse", "position": [LIGHT_BASE[0], LIGHT_BASE[1]]}]


def clear(x, y, r, min_e=0.30, max_e=1.0):
    if not (BOUNDS_MIN[0] + 90 <= x <= BOUNDS_MAX[0] - 90 and BOUNDS_MIN[1] + 90 <= y <= BOUNDS_MAX[1] - 90):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 190:
        return False
    e = field_elev(x, y)
    if not (min_e <= e <= max_e) or is_deep(x, y):
        return False
    if near_posts((x, y), 22 + r):
        return False
    return all(math.hypot(x - px, y - py) >= r + pr for px, py, pr in placed)


def scatter(region_id, n, r, tries=6000, min_e=0.30, max_e=1.0):
    rmin, rmax = next((a, b) for rid, a, b, _ in REGIONS if rid == region_id)
    out = []
    for _ in range(tries):
        if len(out) >= n:
            break
        x = random.uniform(rmin[0], rmax[0])
        y = random.uniform(rmin[1], rmax[1])
        if clear(x, y, r, min_e, max_e):
            placed.append((x, y, r))
            out.append((round(x), round(y)))
    return out


TREES = []
PROPS = []


def trees(region, n, kind, r=24, min_e=0.88):
    for x, y in scatter(region, n, r, min_e=min_e):
        TREES.append([x, y, kind])


def props(region, n, type, label, r=16, solid=None, radius=None, min_e=0.30, max_e=1.0):
    for i, (x, y) in enumerate(scatter(region, n, r, min_e=min_e, max_e=max_e)):
        PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), WHITE, label, solid=solid, radius=radius))


# the dunes at the back of the beach: wind-bent pines, thorn scrub, tamarisk, marram grass
trees("dune_landing", 14, "dune_pine", 24)
trees("dune_landing", 16, "thorn", 22)
trees("dune_landing", 8, "tamarisk", 22)
trees("wrack_line", 26, "dune_pine", 24)
trees("wrack_line", 34, "thorn", 22)
trees("wrack_line", 16, "tamarisk", 22)
trees("lantern_point", 5, "thorn", 22, min_e=0.9)
props("dune_landing", 26, "eb_marram", "a tuft of marram grass", r=16, min_e=0.88)
props("wrack_line", 50, "eb_marram", "a tuft of marram grass", r=16, min_e=0.88)
props("dune_landing", 6, "eb_driftwood", "a bleached log", r=22, min_e=0.88)
props("wrack_line", 10, "eb_driftwood", "a bleached log", r=22, min_e=0.88)
props("wrack_line", 8, "eb_rock", "a barnacled rock", r=18, solid=True, radius=8, min_e=0.84)
props("wrack_line", 8, "eb_wrack", "a heap of wrack", r=18, min_e=0.80)
# the flats: wrack, shells and rocks the tide leaves, kept off the dig spots
for reg, nw, ns, nr in (("cockle_ridge", 8, 8, 5), ("pool_terrace", 12, 9, 4), ("the_creeks", 10, 6, 5), ("far_bars", 10, 8, 3), ("lantern_point", 4, 3, 6)):
    props(reg, nw, "eb_wrack", "a heap of wrack", r=18, min_e=0.34)
    props(reg, ns, "eb_shellheap", "a heap of shells", r=18, min_e=0.34)
    props(reg, nr, "eb_rock", "a barnacled rock", r=18, solid=True, radius=8, min_e=0.36)
props("cockle_ridge", 5, "eb_driftwood", "a bleached log", r=22, min_e=0.4)
props("far_bars", 3, "eb_buoy", "a stranded buoy", r=16, min_e=0.4)
ALL_PROPS = SPECIAL + PROPS + SHORE

# ── the world's own ART OVERRIDE (deep-merged over data/art.json by ArtStyle.load_style) ─────────────
S = "res://assets/sprites/"


def ramp(*rows):
    return [list(r) for r in rows]


def tree_variants(names):
    return [{"trunk": S + "eb_%s_trunk.png" % n, "canopy": S + "eb_%s_canopy.png" % n} for n in names]


PINES = ["dune_pine_a", "dune_pine_b"]
THORNS = ["thorn_a", "thorn_b", "thorn_c"]
TAMS = ["tamarisk_a", "tamarisk_b"]
ART = {
    "palette": {
        "ground_top": [0.86, 0.80, 0.68], "ground_bottom": [0.76, 0.70, 0.58],
        "foliage_dark": [0.26, 0.36, 0.34], "foliage_mid": [0.46, 0.56, 0.48], "foliage_light": [0.72, 0.80, 0.64],
        "bark": [0.52, 0.46, 0.38], "water": [0.30, 0.52, 0.62], "rim": [1.0, 0.96, 0.86],
        "shadow": [0.30, 0.26, 0.22], "grass": [0.86, 0.80, 0.68], "water_rim": [0.96, 0.98, 0.96, 0.7],
    },
    "light": {"shadow_alpha": 0.18, "rim_strength": 0.14},
    "entities": {
        "portal": {"frame_tint": [0.80, 0.92, 0.94]},
        "ground": {
            "render": "pixel", "terrain": S + "eb_terrain.png", "tile": 128,
            "details": S + "eb_details.png", "details_index": "res://data/eb_details.json",
            "shade": 0.1,
            "ramps": {
                "grass": ramp((0.76, 0.69, 0.55), (0.82, 0.75, 0.60), (0.87, 0.80, 0.65), (0.95, 0.91, 0.80)),
                "lush": ramp((0.64, 0.57, 0.46), (0.70, 0.62, 0.50), (0.75, 0.67, 0.55), (0.88, 0.82, 0.70)),
                "meadow": ramp((0.60, 0.60, 0.40), (0.66, 0.66, 0.44), (0.73, 0.73, 0.50), (0.86, 0.86, 0.66)),
                "dirt": ramp((0.50, 0.45, 0.38), (0.56, 0.50, 0.42), (0.62, 0.56, 0.47), (0.76, 0.72, 0.64)),
                "sand": ramp((0.84, 0.80, 0.72), (0.89, 0.85, 0.77), (0.94, 0.91, 0.84), (1.0, 0.98, 0.94)),
                "path": ramp((0.60, 0.54, 0.44), (0.68, 0.62, 0.50), (0.76, 0.70, 0.58), (0.88, 0.84, 0.74)),
                "worn": ramp((0.66, 0.60, 0.48), (0.74, 0.67, 0.54), (0.82, 0.75, 0.62), (0.92, 0.88, 0.78)),
            },
            "accents": [[1.0, 0.92, 0.84]],
            "patches": {"lush": {"scale": 0.0026, "threshold": 0.45}, "meadow": {"scale": 0.004, "threshold": 0.66},
                        "dirt": {"scale": 0.003, "threshold": 0.62}},
            "clump": {"scale": 0.007, "dark": 0.38, "light": 0.62},
            "scatter": {
                "density": 0.55,
                "open": [
                    {"names": ["cockle", "cockle_pink"], "weight": 11, "count": [1, 3]},
                    {"names": ["whelk", "razor"], "weight": 6, "count": [1, 2]},
                    {"names": ["scallop"], "weight": 3},
                    {"names": ["starfish"], "weight": 1},
                    {"names": ["wrack", "wrack_small"], "weight": 9, "count": [1, 2]},
                    {"names": ["pebbles"], "weight": 8, "count": [1, 3]},
                    {"names": ["lugworm", "pinholes"], "weight": 8, "count": [1, 3]},
                    {"names": ["driftchip"], "weight": 4},
                    {"names": ["marram"], "weight": 3, "sway": 0.3},
                    {"names": ["thrift"], "weight": 2, "count": [1, 2]},
                ],
                "under_trees": {"names": ["marram", "driftchip"], "ring": ["thrift"]},
                "path_edge": [],
                "reeds": [],
                "lilies": [],
            },
        },
        "understory": {"render": "sprite", "prefix": S + "eb_understory_", "types": ["bush_a", "bush_b", "stump"], "density": 0.3},
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 0}, "clouds": {"count": 3, "alpha": 0.06, "speed": 6},
                         "leaves": {"rate": 0.0, "colors": [[0.9, 0.9, 0.8]]}},
        "tree": {"render": "sprite", "sway": 0.4, "variants": tree_variants(PINES + THORNS + TAMS)},
        "dune_pine": {"render": "sprite", "sway": 0.35, "variants": tree_variants(PINES)},
        "thorn": {"render": "sprite", "sway": 0.3, "variants": tree_variants(THORNS)},
        "tamarisk": {"render": "sprite", "sway": 0.5, "variants": tree_variants(TAMS)},
        "great_tree": {"render": "sprite", "sway": 0.2, "variants": tree_variants(THORNS[:1])},
        "lighthouse": {"render": "sprite", "sway": 0.0, "variants": [{"trunk": S + "eb_lighthouse_trunk.png", "canopy": S + "eb_lighthouse_canopy.png"}]},
        "props": {"unseen": ["eb_shore"], "extra_types": ["eb_rock", "eb_rock_big", "eb_shellheap", "eb_driftwood", "eb_wrack", "eb_rowboat",
                                                           "eb_groyne", "eb_tide_stone", "eb_cairn", "eb_marram", "eb_buoy", "eb_sand_dollar"]},
    },
    "daycycle": {"enabled": True, "period_sec": 720, "loop": True, "stops": [
        {"t": 0.0, "tint": [1.0, 0.97, 0.92], "vignette": [0.52, 0.46, 0.40], "vstrength": 0.22},
        {"t": 0.5, "tint": [1.0, 0.92, 0.88], "vignette": [0.56, 0.44, 0.40], "vstrength": 0.26},
        {"t": 1.0, "tint": [1.0, 0.97, 0.92], "vignette": [0.52, 0.46, 0.40], "vstrength": 0.22},
    ]},
}

LIGHT_LAMP = [LIGHT_BASE[0], LIGHT_BASE[1] - 121]
TIDE_BLOCK = dict(TIDE)
TIDE_BLOCK.update({
    "deep_elev": DEEP_ELEV,
    "expose_margin": EXPOSE_MARGIN,
    "field": {"origin": list(BOUNDS_MIN), "cell": CELL, "w": GW, "h": GH, "bits": 16,
              "data": base64.b64encode(b"".join(v.to_bytes(2, "big") for v in FIELD)).decode("ascii")},
    # how the water looks (colours 0..1); the shader and TideLayer read these
    "look": {
        "deep": [0.14, 0.30, 0.40], "shallow": [0.52, 0.76, 0.80], "foam": [0.97, 0.99, 0.97], "wet": [0.36, 0.32, 0.27],
        "sheen": [0.88, 0.93, 0.96], "wet_band": 0.10, "foam_band": 0.012, "shallow_alpha": 0.46, "deep_alpha": 0.9,
    },
    "gauge": list(GAUGE),
    "lamp": LIGHT_LAMP,
    # the first-time hints, one for each state of the tide
    "hints": {
        "ebbing": "The tide is going out. The flats are opening up, a little further every minute.",
        "low_soon": "The water is drawing right back from the far bars. Lowest tide is close.",
        "low": "Lowest tide. The far bars are bare, and whatever the sea keeps there is within reach. Be quick: it will not stay.",
        "low_soon_short": "Lowest tide is coming.",
        "low_short": "Lowest tide. The far bars are bare.",
        "flooding": "The tide has turned. The sea is coming back, slowly, over the sand.",
        "high": "High water. Everything on the flats is under a hand's depth of sea. Wait for it to go out again.",
    },
})

DIG = {
    "spots": DIG_SPOTS,
    "dollar_spot": "bar_dollar",
    "active_fraction": 0.62,
    "affordances": {"fox": "dig", "rabbit": "dig", "wolf": "dig", "_default": "dig"},
    "tap_radius": 54.0, "dig_seconds": 1.8, "arrive_distance": 40.0, "sniff_range_low": 240.0, "sniff_range_high": 560.0,
    "sniff_cooldown_low": 9.0, "sniff_cooldown_high": 3.5, "sniff_hold": 2.4, "see_radius": 64.0,
    "outcomes": [
        {"kind": "shell", "weight": 7, "names": ["cockle", "whelk", "razor shell", "scallop", "periwinkle"]},
        {"kind": "crab", "weight": 2},
        {"kind": "glass", "weight": 1},
    ],
    "lines": {
        "sniff": "Your companion stops, nose to the sand. Something is buried there.",
        "sign": "A little ring of bubbles in the wet sand: something is under there. Tap it to send your companion to dig.",
        "cant_dig": "Your companion pats at the sand, but this shape cannot dig. A fox, a rabbit or a wolf could.",
        "dug": "Already dug. The sea will have the hole filled in by the next tide.",
        "dig_shell": "Your companion digs up a %s and drops it at your feet.",
        "dig_crab": "A crab! It had been asleep under there, and is now very much awake. It scuttles for the sea.",
        "dig_glass": "A piece of sea-glass, worn soft as a sweet. Your companion looks very pleased with itself.",
        "dig_dollar": "Under the sand, pale and perfectly round: a sand-dollar, with a flower pressed into its back.",
    },
}

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Ebbmere'). reveal.type 'tide': at the lowest tide "
                  "the far bar at 'position' is bare; a companion in a form that can dig (dig.affordances) sent to the dig spot "
                  "'bar_dollar' brings up the sand-dollar, but only while the shared tide (TideClock; the same clock Server.Tide checks) "
                  "is in its low window. The server honours the claim only inside that window plus 'grace_s', within 'radius' of 'position'.")
SECRET = {
    "id": "sand_dollar",
    "position": [DOLLAR[0], DOLLAR[1] + 10],
    "radius": 130.0,
    "prop": {"type": "eb_sand_dollar", "color": [1.0, 1.0, 1.0], "label": "a sand-dollar", "tags": ["pale", "round", "salt", "quiet"]},
    "lore": "A sand-dollar, whole and unbroken, pale as the moon, with a five-petalled flower pressed into its back by a sea that was fond of it. It is the weight of nothing at all.",
    "reveal": {
        "type": "tide",
        "tide": dict(TIDE),
        "grace_s": 30.0,
        "spot": "bar_dollar",
        "reveal_line": DIG["lines"]["dig_dollar"],
        "refused_line": "The tide has turned, and the sea has slipped back over the bar. The sand-dollar is still there. It will rise again at the next lowest tide.",
    },
    "found_line": "The sand-dollar was only ever under the lowest water. You and your companion found the one hour of the tide that lets it be seen.",
    "home_line": "Something has changed at home.",
    "qualities": ["quiet", "watery", "old"],
    "keepsake": {
        "id": "dollar_dish", "type": "kept_sand_dollar", "color": [1.0, 1.0, 1.0], "label": "a sand-dollar in a dish of sand",
        "line": "A sand-dollar in a shallow dish of sand. If you hold your ear to it, there is nothing at all, and the nothing is the sea.",
        "temperament": {"curiosity": 0.6, "energy": 0.4, "clinginess": 0.5},
    },
}

HEADER = ("EBBMERE - the tidal flats. A walk-and-wonder world: wet sand that holds the sky, tide pools, creeks, shell ridges and a "
          "lighthouse. The TIDE goes out and comes back on a shared clock (tide: a pure function of UTC time, TideClock / Server.Tide); "
          "tide.field is the baked seabed (one 16-bit value per 16 px cell) the water covers whenever the level is above it; elevation under "
          "tide.deep_elev is open sea, walled with invisible 'eb_shore' posts. Eight regions: Dune Landing (where you arrive), Wrack Line, "
          "Cockle Ridge, Pool Terrace, The Creeks, Far Bars, Lantern Point and Greywater. It RE-SKINS ITSELF through its 'art' block: its own "
          "sand + shore-litter atlas, windswept dune trees, a lighthouse landmark. 'dig' holds the buried spots; its secret is a sand-dollar "
          "that only the lowest tide gives up: see the 'secret' block (reveal type 'tide'). Generated by tools/gen_ebbmere_world.py "
          "(art: pokepals/tools/gen_ebbmere.py) - edit that and re-run, don't hand-tune positions.")


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "ebbmere",')
out.append('\t"intro": %s,' % json.dumps("The sea has gone out and left its floor lying about. Walk on it while it lasts."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": false },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 18, "pond_blocks": false, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.84, 0.78, 0.66],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps({
    "day_tint": [1.0, 0.97, 0.92], "vignette": {"strength": 0.22, "color": [0.52, 0.46, 0.40]},
    "wind": {"strength": 0.8, "speed": 0.6}, "pollen": {"amount": 0, "color": [1, 1, 1]}, "region_tint_alpha": 0.04,
    "grass": {"max": 0}, "sparkles": {"count": 160, "colors": [[1.0, 0.98, 0.92], [0.86, 0.94, 1.0]]},
}, separators=(", ", ": ")))
out.append('\t"tide": %s,' % json.dumps(TIDE_BLOCK, separators=(", ", ": "), ensure_ascii=False))
out.append('\t"dig": %s,' % json.dumps(DIG, separators=(", ", ": "), ensure_ascii=False))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [],')
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
    if not p["id"].startswith("shore_"):
        assert not is_deep(x, y), "prop in the deep sea: %s" % p["id"]
for t in d["trees"]:
    assert field_elev(t[0], t[1]) >= 0.86, "a tree stands where the tide reaches: %s" % t
for s in DIG_SPOTS:
    e = field_elev(*s["position"])
    assert not is_deep(*s["position"]) and e >= 0.33, "dig spot too wet: %s" % s
# the arrival must stay dry at the highest tide
assert field_elev(*PLAYER_SPAWN) > TIDE["level_high"] + 0.05, "the landing floods"
assert field_elev(*GAUGE) > TIDE["level_high"] + 0.05
assert field_elev(*LIGHT_BASE) > TIDE["level_high"] + 0.05
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("props:", len(d["props"]) - len(SHORE), "+", len(SHORE), "posts | trees:", kinds, "| spec bytes:", len(text))
for path in ["server/priv/world_seeds/ebbmere.json", "pokepals/tests/world_fixtures/ebbmere.json"]:
    open(path, "w").write(text)
print("wrote both files")
