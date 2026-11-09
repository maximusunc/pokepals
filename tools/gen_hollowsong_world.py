#!/usr/bin/env python3
"""Generate HOLLOWSONG, the echo canyon, as a world spec.

A walk-and-call world (3600 x 2600): banded red cliffs, wind-carved arches and a dry riverbed at sunset.
Every sound comes back, and the echoes show as soft visible ripples. No goal, no puzzle: a warm, wide, golden
place to wander and call out in.

Its one SECRET (docs/home-world-and-secrets-design.md, "Hollowsong"): a hidden cave, the only place in the
canyon that answers WRONG. In wolf form your companion howls on command (the radial's "Howl"); the canyon
howls back, and the ripples are computed from the authored wall geometry below (the pure EchoField on the
client). One answer comes late and violet from a spot with no wall at all: the cave. Howl again from
somewhere else and the two bearings cross near it; walk up and a crack in the cliff opens (reveal type
"echo"), and the answering stone inside is claimed through the usual flow. Every number (speed, reach, error
by bond, cooldown, the notice and reveal radii) lives in this file's data, not in code.

Hand-authored: regions, the cliffs (rect footprints; their edges ARE the echoing walls), the arches, ponds,
the cave's place, every lore line, the art override and the secret. Procedural (seeded, so re-running
reproduces it): the scatter of trees and props, kept clear of cliffs, ponds, the landing, the slot and the
stone. The generator also flood-fills the walkable ground and asserts that the spawn reaches the stone, the
slot and every region.

Art assets come from pokepals/tools/gen_hollowsong.py. Writes the server seed and the client test fixture.
Run from the repo root:  python3 tools/gen_hollowsong_world.py
"""
import json
import math
import random

random.seed(0x4011A)

BOUNDS_MIN = (-1800, -1300)
BOUNDS_MAX = (1800, 1300)
PLAYER_SPAWN = [-1500, 420]
COMPANION_SPAWN = [-1530, 450]
PORTALS = [
    {"id": "hollowsong_way_home", "type": "portal", "position": [-1572, 420], "color": [1.0, 0.78, 0.54], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

# ── regions: a 4-column partition (8 regions) ─────────────────────────────────────────────────────────
REGIONS = [
    ("red_stair",        (-1800, -1300), (-1100, -300), (0.98, 0.80, 0.70)),
    ("sundown_landing",  (-1800, -300),  (-1100, 1300), (1.00, 0.88, 0.72)),
    ("whisper_walls",    (-1100, -1300), (-100, -400),  (0.94, 0.78, 0.72)),
    ("dry_run",          (-1100, -400),  (-100, 1300),  (1.00, 0.90, 0.74)),
    ("the_choir",        (-100, -1300),  (900, 500),    (1.00, 0.84, 0.70)),
    ("hoodoo_flats",     (-100, 500),    (900, 1300),   (0.96, 0.80, 0.70)),
    ("the_hush",         (900, -1300),   (1800, -300),  (0.86, 0.78, 0.92)),
    ("cottonwood_bend",  (900, -300),    (1800, 1300),  (1.00, 0.88, 0.66)),
]

POOL = [0.34, 0.46, 0.54]
PONDS = [
    {"center": [-1000, 340], "radius": 46, "color": POOL},     # a seep by the landing
    {"center": [200, 330], "radius": 40, "color": POOL},
    {"center": [-100, -330], "radius": 38, "color": POOL},     # tucked under the Great Arch
    {"center": [1000, 620], "radius": 52, "color": POOL},
    {"center": [1550, 430], "radius": 64, "color": POOL},      # the bend's long pool
    {"center": [1470, 520], "radius": 50, "color": POOL},
    {"center": [-600, 900], "radius": 44, "color": POOL},
]

LANDMARKS = [
    {"type": "great_tree", "position": [1380, 640]},
    {"type": "great_tree", "position": [-1000, 720]},
    {"type": "great_tree", "position": [720, -300]},
]

VEIN = {"rect": [-1700, 20, 3400, 110], "color": [0.92, 0.78, 0.60], "rim": [0.98, 0.90, 0.74]}

# ── the cliffs. Every cliff is a footprint rect [x, y, w, depth] whose SOUTH edge is its foot (the drawn
# face). The edges of the footprints that collide are the canyon's echoing WALLS (see walls_of). ───────────
BANDS_RED = [[0.60, 0.26, 0.20], [0.74, 0.38, 0.26], [0.84, 0.54, 0.38], [0.52, 0.22, 0.20], [0.90, 0.68, 0.48]]
BANDS_ROSE = [[0.66, 0.34, 0.30], [0.78, 0.46, 0.38], [0.86, 0.60, 0.48], [0.58, 0.28, 0.28]]
BANDS_OCHRE = [[0.72, 0.46, 0.24], [0.84, 0.60, 0.32], [0.92, 0.74, 0.46], [0.64, 0.38, 0.22]]
BANDS_VIOLET = [[0.50, 0.28, 0.34], [0.64, 0.38, 0.42], [0.76, 0.52, 0.50], [0.44, 0.24, 0.32]]
TOP = [0.90, 0.74, 0.54]

CLIFFS = []
WALLS = []     # [x1, y1, x2, y2] edges of every colliding footprint


def _edges(rect):
    x, y, w, h = rect
    return [[x, y, x + w, y], [x + w, y, x + w, y + h], [x + w, y + h, x, y + h], [x, y + h, x, y]]


def cliff(cid, x, feet, w, depth, h, tiers=(), bands=None, arch=None, cave=None, solid_rects=None):
    rect = [round(x), round(feet - depth), round(w), round(depth)]
    b = {"id": cid, "view": "cliff", "rect": rect, "h": h, "roof": list(TOP), "bands": bands or BANDS_RED}
    if tiers:
        b["tiers"] = [{"inset": i, "h": th} for i, th in tiers]
    if arch:
        b["arch"] = arch
    if cave:
        b["cave"] = cave
    rects = [rect]
    if solid_rects:
        rects = [[round(a) for a in r] for r in solid_rects]
        b["solid_rects"] = rects
    CLIFFS.append(b)
    for r in rects:
        WALLS.extend([[round(v) for v in e] for e in _edges(r)])
    return b


SLOT_X0, SLOT_X1 = 900, 1500       # the slot's footprint along the north rim
SLOT_MOUTH_Y = -760                # where the flanks end (their feet)
CAVE_FEET = -1080                  # the back wall's foot: the cave is in its face
CAVE_X = 1200

# the north rim: tall faces along the whole top of the canyon (nothing walkable is north of them)
rng = random.Random(77)
x = -1800
k = 0
while x < 1800:
    w = rng.randint(260, 400)
    if x + w > SLOT_X0 and x < SLOT_X1:
        x = SLOT_X1
        continue
    feet = -1010 - rng.randint(0, 40)
    h = rng.randint(130, 190)
    tiers = [(rng.randint(24, 40), rng.randint(40, 70))] + ([(rng.randint(24, 36), rng.randint(30, 50))] if rng.random() < 0.5 else [])
    cliff("rim_n_%d" % k, x, feet, min(w, 1800 - x) + 12, 220, h, tiers, bands=rng.choice([BANDS_RED, BANDS_ROSE, BANDS_OCHRE]))
    x += w
    k += 1

# the slot: two deep flanks and a back wall with the cave in its face
cliff("slot_west", SLOT_X0, SLOT_MOUTH_Y, 200, 470, 150, [(26, 50)], bands=BANDS_VIOLET)
cliff("slot_east", SLOT_X1 - 200, SLOT_MOUTH_Y, 200, 470, 150, [(26, 50)], bands=BANDS_VIOLET)
cliff("slot_back", 1100, CAVE_FEET, 200, 150, 170, [(20, 60)], bands=BANDS_VIOLET, cave={"x": CAVE_X - 1200, "w": 60, "h": 84})

# the south rim: lower, so it never hides the canyon floor
x = -1800
k = 0
while x < 1800:
    w = rng.randint(280, 420)
    cliff("rim_s_%d" % k, x, 1235 + rng.randint(0, 20), min(w, 1800 - x) + 12, 130, rng.randint(60, 100), [(rng.randint(22, 34), rng.randint(24, 40))],
          bands=rng.choice([BANDS_RED, BANDS_ROSE, BANDS_OCHRE]))
    x += w
    k += 1

# buttes and mesas standing in the canyon: (id, centre x, foot y, width, depth, height, tiers, bands)
BUTTES = [
    ("butte_stair",   -1300, -450, 320, 120, 140, [(36, 46)], BANDS_ROSE),
    ("butte_gate",     -800, -150, 260, 110, 110, [(30, 40)], BANDS_RED),
    ("butte_south",    -450,  250, 200,  90,  90, [(26, 40)], BANDS_OCHRE),
    ("butte_whisper",  -350, -700, 280, 120, 150, [(34, 50)], BANDS_RED),
    ("butte_choir",     400, -600, 300, 110, 130, [(36, 44)], BANDS_ROSE),
    ("butte_low",       500,  330, 240, 100, 110, [(30, 40)], BANDS_OCHRE),
    ("butte_hush",      900, -250, 220,  90, 100, [], BANDS_RED),
    ("butte_flats",    -200,  850, 260, 110, 120, [(30, 50)], BANDS_RED),
    ("butte_flats_b",   350,  920, 200,  90,  90, [], BANDS_OCHRE),
    ("butte_bend",     1100,  300, 280, 110, 120, [(34, 44)], BANDS_ROSE),
    ("butte_bend_b",   1300,  980, 320, 120, 140, [(36, 50)], BANDS_RED),
    ("butte_hush_b",   1450, -430, 240, 100, 110, [], BANDS_VIOLET),
]
for cid, cx, feet, w, d, h, tiers, bands in BUTTES:
    cliff(cid, cx - w / 2, feet, w, d, h, tiers, bands)

# arches: the opening is walkable (only the two legs collide)
ARCHES = [
    # (id, centre x, foot y, width, depth, height, gap half-width, gap height, bands)
    ("great_arch",  0,    -80, 380, 90, 170, 70, 92, BANDS_RED),
    ("wren_arch",  -700, -560, 260, 80, 130, 50, 70, BANDS_ROSE),
    ("needle_eye",  700,  640, 240, 80, 120, 46, 66, BANDS_OCHRE),
]
for cid, cx, feet, w, d, h, gh, gv, bands in ARCHES:
    x0 = cx - w / 2
    leg = w / 2 - gh
    cliff(cid, x0, feet, w, d, h, [(30, 36)], bands, arch={"x0": -gh, "x1": gh, "h": gv},
          solid_rects=[[x0, feet - d, leg, d], [cx + gh, feet - d, leg, d]])

# ── the secret's place ───────────────────────────────────────────────────────────────────────────────
STONE = (CAVE_X, CAVE_FEET + 22)         # the answering stone, on the cave's threshold (clear of the face's paint)
CAVE_MOUTH = (CAVE_X, CAVE_FEET + 10)    # what you walk up to
CAVE_ORIGIN = (CAVE_X, CAVE_FEET - 60)   # where the wrong answer truly comes from: inside the rock
SLOT_CLEAR = (SLOT_X0 + 200, SLOT_MOUTH_Y - 360, 200, 520)   # the slot's floor and its mouth, kept bare


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

SPECIAL = [
    prop("landing_ring", "hs_ring", (-1440, 470), WHITE, "an old fire ring",
         "A ring of stones round old ashes, one ember still red. Whoever sat here talked to the canyon for a long while; the ash is all in a neat line, as if it had been listening too."),
    prop("landing_board", "hs_board", (-1540, 380), WHITE, "a notice board",
         "A sun-bleached notice board. 'WELCOME TO HOLLOWSONG. This canyon keeps everything you say to it, and gives it back a little late. Call out and see. A companion in a wolf's shape has the voice for it: tap the little chip at the bottom right, choose Wolf, then Howl.'", solid=True, radius=5),
    prop("choir_board", "hs_board", (-70, 150), WHITE, "the echo-keeper's board",
         "The echo-keeper's notes, in pencil: 'The walls answer from where they stand. Watch the ripples come home. But one voice comes back from where there is NO wall, violet and late, and it has a place of its own. Stand somewhere else and call again; where the two lines cross is where it lives.'", solid=True, radius=5),
    prop("hush_board", "hs_board", (1330, -470), WHITE, "a weathered board",
         "THE HUSH. 'Past here the cliffs lean close. Voices go in. Something answers more slowly than it should, and from the wrong side of the rock.'", solid=True, radius=5),
    prop("landing_cairn", "hs_cairn", (-1380, 330), WHITE, "a little cairn",
         "Seven stones, each smaller than the last. Travellers leave one for every echo they were sure they heard.", solid=True, radius=5),
    prop("stair_cairn", "hs_cairn", (-1250, -250), WHITE, "a cairn",
         "A cairn with a feather pushed in the top. The wind turns the feather, and the feather seems to turn the wind."),
    prop("run_log", "hs_log", (-560, 420), WHITE, "a dry log",
         "A silver-grey log, bleached smooth. It is hollow, and if you put your ear to one end you hear the canyon's own low note, like blowing across a bottle."),
    prop("run_boulder", "hs_boulder", (-300, 120), WHITE, "a round red boulder",
         "A red boulder with a cream stripe through it, warm all the way through. A lizard has been sunning on it, and has left, offended.", solid=True, radius=9),
    prop("whisper_hoodoo", "hs_hoodoo", (-480, -420), WHITE, "a hoodoo",
         "A tall stone column with a cap like a hat. It leans a little toward the wall behind it, the way you lean toward someone telling a secret.", solid=True, radius=9),
    prop("choir_cairn", "hs_cairn", (240, -200), WHITE, "a cairn in the Choir",
         "A cairn at the exact spot where, the keeper's board says, every wall in the Choir answers at once. You say 'hello' very quietly. The canyon says it back, from four sides.", solid=True, radius=5),
    prop("flats_hoodoo_a", "hs_hoodoo", (100, 760), WHITE, "a hoodoo",
         "A banded pillar, red and cream and red again. It is a hundred thousand years of rivers, stacked, and it is currently being used as a perch by a very small bird.", solid=True, radius=9),
    prop("flats_hoodoo_b", "hs_hoodoo", (560, 800), WHITE, "a hoodoo",
         "One of the tall ones. The wind has worn a hole through its middle, and it hums when the breeze is right. Right now it is.", solid=True, radius=9),
    prop("bend_log", "hs_log", (1260, 760), WHITE, "a driftwood log",
         "The river left this here, the last time there was one. It is carried further than any tree grows: stripped, and polished, and entirely at peace with having been so far."),
    prop("bend_yucca", "hs_yucca", (1150, 460), WHITE, "a flowering yucca",
         "A yucca in bloom, a tall white stalk of bells. Moths come for it at night. By day it just stands there looking proud of itself."),
    prop("hush_cairn", "hs_cairn", (1150, -560), WHITE, "a cairn by the slot",
         "A cairn at the slot's mouth. The stones are all slightly warm, and slightly out of tune with each other, and you decide not to ask.", solid=True, radius=5),
]

placed = [(p["position"][0], p["position"][1], 24) for p in SPECIAL]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 70))


def _rect_dist(x, y, r):
    rx, ry, rw, rh = r
    dx = max(rx - x, 0, x - (rx + rw))
    dy = max(ry - y, 0, y - (ry + rh))
    return math.hypot(dx, dy)


def clear(x, y, r):
    if not (BOUNDS_MIN[0] + 140 <= x <= BOUNDS_MAX[0] - 140 and BOUNDS_MIN[1] + 140 <= y <= BOUNDS_MAX[1] - 140):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 190:
        return False
    if any(math.hypot(x - pd["center"][0], y - pd["center"][1]) < pd["radius"] * 1.2 + r + 6 for pd in PONDS):
        return False
    # cliffs: keep their footprints, and the strip they paint over to the north, clear
    for b in CLIFFS:
        rx, ry, rw, rh = b["rect"]
        if _rect_dist(x, y, b["rect"]) < 34 + r:
            return False
        if rx - 16 < x < rx + rw + 16 and ry - 90 < y < ry:
            return False
    if _rect_dist(x, y, SLOT_CLEAR) < 36 + r:
        return False
    vx, vy, vw, vh = VEIN["rect"]
    if _rect_dist(x, y, VEIN["rect"]) < r:
        return False
    if math.hypot(x - STONE[0], y - STONE[1]) < 140 + r:
        return False
    return all(math.hypot(x - px, y - py) >= r + pr for px, py, pr in placed)


def scatter(region_id, n, r, tries=4000):
    rmin, rmax = next((a, b) for rid, a, b, _ in REGIONS if rid == region_id)
    out = []
    for _ in range(tries):
        if len(out) >= n:
            break
        x = random.uniform(rmin[0], rmax[0])
        y = random.uniform(rmin[1], rmax[1])
        if clear(x, y, r):
            placed.append((x, y, r))
            out.append((round(x), round(y)))
    return out


TREES = []
PROPS = []


def trees(region, n, kind, r=24):
    for x, y in scatter(region, n, r):
        TREES.append([x, y, kind])


def props(region, n, type, label, r=16, solid=None, radius=None):
    for i, (x, y) in enumerate(scatter(region, n, r)):
        PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), WHITE, label, solid=solid, radius=radius))


for region, jun, sage, cot, boul, hood, agave in [
    ("red_stair", 26, 14, 0, 8, 2, 8),
    ("sundown_landing", 12, 16, 6, 6, 1, 8),
    ("whisper_walls", 22, 14, 2, 8, 3, 6),
    ("dry_run", 8, 16, 10, 10, 2, 8),
    ("the_choir", 10, 12, 2, 8, 2, 6),
    ("hoodoo_flats", 14, 14, 0, 12, 6, 10),
    ("the_hush", 16, 10, 0, 6, 3, 4),
    ("cottonwood_bend", 6, 8, 34, 6, 1, 8),
]:
    trees(region, jun, "juniper")
    trees(region, sage, "sage", 20)
    trees(region, cot, "cottonwood", 28)
    props(region, boul, "hs_boulder", "a red boulder", r=20, solid=True, radius=9)
    props(region, hood, "hs_hoodoo", "a hoodoo", r=22, solid=True, radius=9)
    props(region, agave, "hs_agave", "an agave", r=12)
trees("dry_run", 8, "dryw", 28)
trees("cottonwood_bend", 8, "dryw", 28)
props("dry_run", 4, "hs_log", "a dry log", r=18)
props("sundown_landing", 3, "hs_yucca", "a yucca", r=14)
props("cottonwood_bend", 3, "hs_yucca", "a yucca", r=14)

ALL_PROPS = SPECIAL + PROPS

# ── walkability: flood-fill the ground from the spawn and prove it reaches everything that matters ───
CELL = 12
BODY = 15


def _blocked_fn():
    circles = [(t[0], t[1], 7 + BODY) for t in TREES]
    for lm in LANDMARKS:
        circles.append((lm["position"][0], lm["position"][1], 16 + BODY))
    for p in ALL_PROPS:
        if p.get("solid"):
            circles.append((p["position"][0], p["position"][1], p.get("collision_radius", 8) + BODY))
    for pd in PONDS:
        circles.append((pd["center"][0], pd["center"][1], pd["radius"] + 6))
    rects = []
    for b in CLIFFS:
        rects.extend(b.get("solid_rects") or [b["rect"]])

    def blocked(x, y):
        if not (BOUNDS_MIN[0] + 60 < x < BOUNDS_MAX[0] - 60 and BOUNDS_MIN[1] + 60 < y < BOUNDS_MAX[1] - 60):
            return True
        for cx, cy, r in circles:
            if abs(x - cx) < r and abs(y - cy) < r and math.hypot(x - cx, y - cy) < r:
                return True
        return any(_rect_dist(x, y, rc) < 8 + 4 for rc in rects)
    return blocked


def reachable_from_spawn():
    blocked = _blocked_fn()
    sx, sy = PLAYER_SPAWN
    seen = {(round(sx / CELL), round(sy / CELL))}
    stack = list(seen)
    while stack:
        i, j = stack.pop()
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (i + di, j + dj)
            if n in seen:
                continue
            if blocked(n[0] * CELL, n[1] * CELL):
                continue
            seen.add(n)
            stack.append(n)
    return seen


def can_reach(seen, x, y, slack=1):
    i, j = round(x / CELL), round(y / CELL)
    return any((i + a, j + b) in seen for a in range(-slack, slack + 1) for b in range(-slack, slack + 1))


# ── the world's own ART OVERRIDE (deep-merged over data/art.json by ArtStyle.load_style) ─────────────
S = "res://assets/sprites/"


def ramp(*rows):
    return [list(r) for r in rows]


def tree_variants(names):
    return [{"trunk": S + "hs_%s_trunk.png" % n, "canopy": S + "hs_%s_canopy.png" % n} for n in names]


JUNIPERS = ["juniper_a", "juniper_b", "juniper_c", "juniper_d"]
SAGES = ["sage_a", "sage_b"]
COTTONS = ["cotton_a", "cotton_b", "cotton_c"]
DRYWS = ["dryw_a", "dryw_b"]
ART = {
    # sun-baked ground under a long gold evening
    "palette": {
        "ground_top": [0.80, 0.64, 0.46], "ground_bottom": [0.70, 0.54, 0.38],
        "foliage_dark": [0.18, 0.28, 0.22], "foliage_mid": [0.36, 0.46, 0.34], "foliage_light": [0.66, 0.74, 0.52],
        "bark": [0.40, 0.26, 0.20], "water": [0.34, 0.46, 0.54], "rim": [1.0, 0.82, 0.58],
        "shadow": [0.22, 0.08, 0.10], "grass": [0.78, 0.62, 0.42], "water_rim": [1.0, 0.86, 0.62, 0.7],
    },
    "light": {"shadow_alpha": 0.26, "rim_strength": 0.22},
    "entities": {
        "portal": {"frame_tint": [0.96, 0.78, 0.62]},
        "ground": {
            "render": "pixel", "terrain": S + "hs_terrain.png", "tile": 128,
            "details": S + "hs_details.png", "details_index": "res://data/hs_details.json",
            "shade": 0.22,
            "ramps": {
                "grass": ramp((0.58, 0.44, 0.30), (0.66, 0.52, 0.35), (0.73, 0.59, 0.40), (0.84, 0.71, 0.50)),
                "lush": ramp((0.46, 0.42, 0.28), (0.53, 0.50, 0.32), (0.60, 0.57, 0.36), (0.72, 0.70, 0.46)),
                "meadow": ramp((0.70, 0.58, 0.38), (0.78, 0.67, 0.44), (0.85, 0.75, 0.50), (0.94, 0.86, 0.62)),
                "dirt": ramp((0.50, 0.25, 0.18), (0.60, 0.32, 0.22), (0.69, 0.38, 0.26), (0.82, 0.52, 0.36)),
                "sand": ramp((0.80, 0.64, 0.50), (0.88, 0.73, 0.57), (0.94, 0.82, 0.65), (0.99, 0.92, 0.78)),
                "path": ramp((0.62, 0.42, 0.30), (0.70, 0.50, 0.36), (0.78, 0.58, 0.42), (0.88, 0.70, 0.52)),
                "worn": ramp((0.64, 0.50, 0.34), (0.72, 0.58, 0.40), (0.80, 0.66, 0.46), (0.90, 0.78, 0.56)),
            },
            "accents": [[1.0, 0.84, 0.58], [0.96, 0.56, 0.42]],
            "patches": {"lush": {"scale": 0.004, "threshold": 0.60}, "meadow": {"scale": 0.0045, "threshold": 0.50},
                        "dirt": {"scale": 0.0055, "threshold": 0.70}},
            "clump": {"scale": 0.008, "dark": 0.34, "light": 0.66},
            "scatter": {
                "density": 0.8,
                "open": [
                    {"names": ["strawtuft_a", "strawtuft_b"], "weight": 24, "count": [1, 4], "sway": 0.25},
                    {"names": ["sagebrush"], "weight": 10, "count": [1, 2], "sway": 0.1},
                    {"names": ["pebbles"], "weight": 10, "count": [1, 3]},
                    {"names": ["redstone", "palestone"], "weight": 6},
                    {"names": ["ripple"], "weight": 8},
                    {"names": ["yucca_spike", "pricklypear"], "weight": 4},
                    {"names": ["bone"], "weight": 1},
                    {"names": ["desertbloom"], "weight": 3},
                    {"names": ["twig"], "weight": 3},
                ],
                "under_trees": {"names": ["twig", "goldleaf"], "ring": ["strawtuft_a"]},
                "path_edge": [],
                "reeds": [],
                "lilies": [],
            },
        },
        "understory": {"render": "sprite", "prefix": S + "hs_understory_", "types": ["bush_a", "bush_b", "stump"], "density": 0.5},
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 0},
                         "clouds": {"count": 3, "alpha": 0.07, "speed": 7},
                         "leaves": {"rate": 0.4, "colors": [[0.90, 0.68, 0.22], [0.82, 0.50, 0.18], [0.96, 0.82, 0.40]]}},
        "tree": {"render": "sprite", "sway": 0.4, "variants": tree_variants(JUNIPERS * 2 + SAGES)},
        "juniper": {"render": "sprite", "sway": 0.25, "variants": tree_variants(JUNIPERS)},
        "sage": {"render": "sprite", "sway": 0.35, "variants": tree_variants(SAGES)},
        "cottonwood": {"render": "sprite", "sway": 0.5, "variants": tree_variants(COTTONS)},
        "dryw": {"render": "sprite", "sway": 0.5, "variants": tree_variants(DRYWS)},
        "great_tree": {"render": "sprite", "sway": 0.2, "variants": tree_variants(["great_cotton", "great_dryw"])},
        "water": {"render": "sprite", "tile": S + "hs_pool.png", "world_tile": 64},
        "pool": {"render": "sprite", "tile": S + "hs_pool.png", "world_tile": 64},
        "river": {"render": "sprite", "tile": S + "hs_pool.png", "world_tile": 64},
        # a cliff is a CliffView: rock grain tinted in strata bands, a sandy top
        "building": {"render": "sprite", "wall": S + "hs_rock.png", "roof": S + "hs_top.png", "slope": S + "hs_top.png"},
        "props": {"extra_types": ["hs_boulder", "hs_cairn", "hs_hoodoo", "hs_log", "hs_agave", "hs_yucca", "hs_ring", "hs_board"]},
        "prop_lights": {
            "hs_ring": {"radius": 34, "y": -5, "alpha": 0.34},
        },
    },
    # held at a long gold sunset
    "daycycle": {"enabled": True, "period_sec": 600, "loop": True, "hold": 0.7, "stops": [
        {"t": 0.0, "tint": [1.0, 0.95, 0.86], "vignette": [0.30, 0.12, 0.12], "vstrength": 0.26},
        {"t": 1.0, "tint": [1.0, 0.78, 0.60], "vignette": [0.30, 0.10, 0.16], "vstrength": 0.38}]},
}

ATMOSPHERE = {
    "day_tint": [1.0, 0.88, 0.72],
    "vignette": {"strength": 0.30, "color": [0.30, 0.12, 0.12]},
    "wind": {"strength": 0.6, "speed": 0.6},
    "pollen": {"amount": 18, "color": [1.0, 0.84, 0.56]},
    "region_tint_alpha": 0.06,
    "grass": {"max": 0},
}

REVEAL = {
    "type": "echo",
    # the canyon's echoing WALLS: the edges of every colliding cliff footprint, [x1, y1, x2, y2]
    "walls": WALLS,
    "cave": {"origin": list(CAVE_ORIGIN), "mouth": list(CAVE_MOUTH)},
    # the howl (EchoField / EchoGuide). speed: px/s the sound travels. Reach is the longest there-and-back path
    # still heard; a bonded companion's voice carries further, answers the cave from further off, shows its
    # wrong answer more clearly and points it out with less error, and howls again sooner.
    "speed": 600.0, "path_low": 1500.0, "path_high": 2300.0, "min_strength": 0.10, "falloff": 1.1,
    "max_candidates": 28, "min_gap": 8.0, "hollow": 0.35,
    "wrong_range_low": 1250.0, "wrong_range_high": 1900.0,
    "wrong_noise_low": 0.36, "wrong_noise_high": 0.09, "wrong_noise_floor": 0.2,
    "wrong_strength_low": 0.72, "wrong_strength_high": 1.0,
    "cooldown_low": 4.0, "cooldown_high": 2.4,
    # walking up to the cave opens it, in any form; the companion notices it as you come near (by bond)
    "reveal_radius": 210.0,
    "notice_range_low": 300.0, "notice_range_high": 640.0, "notice_cooldown_low": 16.0, "notice_cooldown_high": 6.0, "notice_hold": 2.5,
    # the ripples: how long the wrong answer's bearing line lingers, and how long friends' ripples show
    "streak_life": 16.0, "streak_length": 900.0,
    "lines": {
        "arrive": "Warm stone, long shadows, and a wind that remembers. This canyon gives back everything you say to it. A wolf's voice carries furthest.",
        "not_wolf": "Your companion tries, but only a thin little sound comes out. A wolf's voice would carry down this canyon.",
        "first_echo": "The canyon takes the call and gives it back, wall by wall. Watch the ripples come home.",
        "silence": "Nothing comes back. There is too much open air here. Try nearer the cliffs.",
        "wrong": "One of those came back violet, and late, from where there is no wall at all. Stand somewhere else and call again: where the two lines cross is where it lives.",
        "notice": "Your companion has stopped, staring at a shadow in the cliff.",
        "reveal": "The cliff has a crack in it, wider than you thought. A cool breath comes out, and something in there is answering your footsteps.",
        "cooldown": "The canyon is still giving the last one back.",
    },
    "reveal_line": "The cliff has a crack in it, wider than you thought. A cool breath comes out, and something in there is answering your footsteps.",
}

SECRET = {
    "id": "answering_stone",
    "position": [STONE[0], STONE[1]],
    "radius": 130.0,
    "prop": {"type": "echo_stone", "color": [0.66, 0.56, 1.0], "label": "a smooth stone bowl", "tags": ["old", "hollow", "stone", "quiet"]},
    "lore": "A bowl of smooth red stone, cool as a spring. When you lean close it says your own breath back to you a beat late, as though it were learning how. Your companion's ears go up.",
    "reveal": REVEAL,
    "found_line": "It had been answering you all along, a little late and from the wrong side of the rock. The canyon was never empty; it was only listening.",
    "home_line": "Something has changed at home.",
    "qualities": ["old", "glowing", "wild"],
    "keepsake": {
        "id": "answering_stone_kept", "type": "kept_echo_stone", "color": [0.66, 0.56, 1.0], "label": "a stone bowl that answers",
        "line": "A small red bowl. Speak into it and it answers a beat late, in a voice a little like yours. Your companion puts its head on one side.",
        "temperament": {"curiosity": 0.7, "energy": 0.5, "clinginess": 0.7},
    },
}

HEADER = ("HOLLOWSONG - an echo canyon. A walk-and-call world (no goal, no puzzle): banded red cliffs, wind-carved arches and a "
          "dry riverbed at sunset, where every sound comes back and the echoes show as soft ripples (HowlDirector / EchoRipples). "
          "Eight regions: Sundown Landing (where you arrive), Red Stair, Dry Run, Whisper Walls, the Choir, Hoodoo Flats, the Hush "
          "and Cottonwood Bend. It RE-SKINS ITSELF through its 'art' block (deep-merged over data/art.json): its own sun-baked "
          "ground + litter atlas, junipers/sage/cottonwoods, cliffs (buildings with view 'cliff': CliffView) and arches (a cliff "
          "with an 'arch' opening and 'solid_rects' for its legs). Its secret is a hidden cave that answers wrong: see the "
          "'secret' block (reveal type 'echo'). Generated by tools/gen_hollowsong_world.py (art: pokepals/tools/gen_hollowsong.py) "
          "- edit that and re-run, don't hand-tune positions.")

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Hollowsong'). reveal.type 'echo': in wolf form "
                  "the companion howls on command; EchoField bounces the howl off the authored 'walls' and draws the returning "
                  "ripples. One answer comes late and violet from reveal.cave.origin, where there is no wall. Walking within "
                  "reveal_radius of cave.mouth opens the crack in the cliff and shows the answering stone. The server honours a "
                  "claim only here, within 'radius' of 'position'.")


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "hollowsong",')
out.append('\t"intro": %s,' % json.dumps(REVEAL["lines"]["arrive"]))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": true, "spacing": 120, "inset": 24, "jitter": 34, "rows": 2, "row_gap": 60 },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.76, 0.60, 0.42],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"vein": %s,' % json.dumps(VEIN))
out.append('\t"ponds": [\n%s\n\t],' % block(PONDS))
out.append('\t"paths": [],')
out.append('\t"buildings": [\n%s\n\t],' % block(CLIFFS))
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
seen = reachable_from_spawn()
TARGETS = [("the answering stone", STONE), ("the slot's mouth", (CAVE_X, SLOT_MOUTH_Y + 30)), ("the cave mouth's approach", (CAVE_X, CAVE_FEET + 120)),
           ("the great arch's far side", (0, -150)), ("the wren arch's far side", (-700, -640)), ("the needle's eye far side", (700, 560)),
           ("red stair", (-1400, -250)), ("whisper walls", (-600, -500)), ("the choir", (300, -200)), ("hoodoo flats", (300, 700)),
           ("the hush", (1250, -450)), ("cottonwood bend", (1450, 700)), ("the landing", tuple(PLAYER_SPAWN))]
for label, (x, y) in TARGETS:
    assert can_reach(seen, x, y, slack=6), "%s is not reachable from the spawn" % label
for p in d["props"]:
    if p.get("interactive"):
        assert can_reach(seen, p["position"][0], p["position"][1], slack=8), "unreachable lore prop " + p["id"]
# the cave's mouth must stay out of the reveal radius of the slot's mouth: you walk IN to open it
assert math.hypot(CAVE_MOUTH[0] - CAVE_X, CAVE_MOUTH[1] - (SLOT_MOUTH_Y + 30)) > REVEAL["reveal_radius"] + 20
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("props:", len(d["props"]), "| trees:", kinds, "| cliffs:", len(CLIFFS), "| walls:", len(WALLS), "| walkable cells:", len(seen))
for path in ["server/priv/world_seeds/hollowsong.json", "pokepals/tests/world_fixtures/hollowsong.json"]:
    open(path, "w").write(text)
print("wrote both files")
