#!/usr/bin/env python3
"""Generate STEAMHOLLOW, the bathhouse village lost in fog, as a world spec.

A walk-and-soak world (3200 x 2400): wooden boardwalks, hot-spring pools breathing steam, paper lanterns
and timber bathhouses, all half-hidden in a drifting mist that shows you only a few steps around you
(MistVeil, tuned by `atmosphere.fog` below). No goal, no puzzle. Lanterns, lit doorways, your companion
and any friends near you each thin the mist into a small pocket, so it is cozy and navigable, not spooky.

Its one SECRET (docs/home-world-and-secrets-design.md, "Steamhollow"): a little bronze bell hung from a
leaning post by a cold spring in the far north-west, ringing too faintly for you to hear. Your companion
hears it, but only when it is calm and settled beside you (reveal type "listen": the pure ListenGuide
and ListenDirector on the client). Its gaze turns toward the sound, its ears prick; that body language
is the only compass. Near the bell the tell sharpens and the bell shows through the mist. Examining it
claims the secret as usual. Every number (hearing range by bond, how long to settle, aim error, ...) lives
in this file's data, not in code.

Hand-authored: regions, boardwalks, bathhouses, ponds, the bell's place, every lore line, the art
override, the secret. Procedural (seeded, so re-running reproduces it): the scatter of trees and props,
kept clear of the boardwalks, buildings, ponds, the landing and the bell. The generator also flood-fills
the walkable ground and asserts that the spawn reaches the bell and every region.

Art assets come from pokepals/tools/gen_steamhollow.py. Writes the server seed and the client test
fixture. Run from the repo root:  python3 tools/gen_steamhollow_world.py
"""
import json
import math
import random

random.seed(0x57EA3)

BOUNDS_MIN = (-1600, -1200)
BOUNDS_MAX = (1600, 1200)
PLAYER_SPAWN = [0, 900]
COMPANION_SPAWN = [-30, 930]
PORTALS = [
    {"id": "steamhollow_way_home", "type": "portal", "position": [-72, 900], "color": [1.0, 0.82, 0.58], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

# ── regions: a 3 x 3 grid with the south-east folded into the landing (8 regions, a clean partition) ──
REGIONS = [
    ("stillwater_nook", (-1600, -1200), (-600, -300), (0.74, 0.84, 0.90)),
    ("old_springs",     (-600, -1200),  (600, -300),  (0.78, 0.86, 0.88)),
    ("maple_bank",      (600, -1200),   (1600, -300), (0.96, 0.84, 0.78)),
    ("cedar_walk",      (-1600, -300),  (-600, 500),  (0.70, 0.82, 0.80)),
    ("kettle_row",      (-600, -300),   (600, 500),   (1.00, 0.90, 0.78)),
    ("soak_terraces",   (600, -300),    (1600, 500),  (0.86, 0.92, 0.94)),
    ("drying_green",    (-1600, 500),   (-600, 1200), (0.82, 0.90, 0.80)),
    ("lantern_landing", (-600, 500),    (1600, 1200), (1.00, 0.88, 0.72)),
]

# ── the springs: milky hot water ─────────────────────────────────────────────────────────────────────
WATER = [0.36, 0.70, 0.68]
PONDS = [
    {"center": [0, -190], "radius": 120, "color": WATER},            # the Grand Soak, behind Kettle Row
    {"center": [-300, 400], "radius": 46, "color": WATER},           # foot baths south of the street
    {"center": [300, 400], "radius": 46, "color": WATER},
    {"center": [880, 170], "radius": 90, "color": WATER},            # Soak Terraces
    {"center": [880, -40], "radius": 80, "color": WATER},
    {"center": [1190, 100], "radius": 72, "color": WATER},
    {"center": [1190, -130], "radius": 82, "color": WATER},
    {"center": [-300, -700], "radius": 80, "color": WATER},          # Old Springs, wild
    {"center": [150, -650], "radius": 90, "color": WATER},
    {"center": [420, -900], "radius": 70, "color": WATER},
    {"center": [-100, -960], "radius": 60, "color": WATER},
    {"center": [1000, -800], "radius": 80, "color": WATER},          # Maple Bank's long pool
    {"center": [1110, -760], "radius": 90, "color": WATER},
    {"center": [1220, -800], "radius": 70, "color": WATER},
    {"center": [-1230, -740], "radius": 38, "color": [0.46, 0.70, 0.78]},   # the cold spring by the bell
    {"center": [-1100, 800], "radius": 70, "color": WATER},          # Drying Green
    {"center": [700, 850], "radius": 90, "color": WATER},            # by the landing
    {"center": [1150, 700], "radius": 70, "color": WATER},
]

LANDMARKS = [
    {"type": "great_tree", "position": [-1350, 640]},
    {"type": "great_tree", "position": [1350, -1000]},
    {"type": "great_tree", "position": [0, -1050]},
]

# ── boardwalks: plates laid flat on the ground. "flat" planks run east-west, "road" north-south ──────
W = 36
PLATES = []


def walk_h(x0, x1, y):
    PLATES.append({"rect": [x0, y - W // 2, x1 - x0, W], "kind": "flat", "color": [1.0, 1.0, 1.0]})


def walk_v(x, y0, y1):
    PLATES.append({"rect": [x - W // 2, y0, W, y1 - y0], "kind": "road", "color": [1.0, 1.0, 1.0]})


walk_v(0, 294, 940)            # the spine from the landing up to Kettle Row
walk_h(-1000, 1100, 294)       # Kettle Row itself
walk_v(0, -42, 294)            # the spine on, between two bathhouses, to the Grand Soak
walk_h(-262, 262, -42)         # round the south shore of the Grand Soak
walk_v(-262, -520, -42)        # up the west side toward Old Springs
walk_v(262, -520, -42)         # ...and the east
walk_v(-1000, -280, 294)       # the cedar walk, north to its end
walk_v(1020, -300, 294)        # the terraces' walk
walk_h(1020, 1100, 20)         # a stub out to the east pools
walk_h(-900, 0, 800)           # west across the landing to the Drying Green
walk_h(1020, 1090, -200)

# ── bathhouses: timber buildings along the north side of Kettle Row, doors facing the street ─────────
STREET_Y = 276   # south edge of every bathhouse; the boardwalk starts just below
WOODS = [(0.80, 0.58, 0.40), (0.72, 0.52, 0.38), (0.86, 0.66, 0.46), (0.68, 0.50, 0.40), (0.78, 0.60, 0.44), (0.74, 0.56, 0.36)]
ROOFS = [(0.32, 0.46, 0.50), (0.40, 0.34, 0.34), (0.30, 0.40, 0.46), (0.46, 0.38, 0.32), (0.34, 0.44, 0.44), (0.38, 0.40, 0.50)]
CURTAINS = [(0.20, 0.26, 0.46), (0.52, 0.20, 0.22), (0.18, 0.34, 0.36), (0.30, 0.22, 0.42), (0.20, 0.26, 0.46), (0.46, 0.30, 0.18)]
BUILDING_DEFS = [   # (x, width, depth, wall height, name)
    (-560, 120, 70, 54, "the Pine Bath"),
    (-420, 150, 80, 64, "the Kettle House"),
    (-250, 180, 90, 66, "the Long Soak"),
    (70, 180, 90, 66, "the Cloud Bath"),
    (270, 140, 70, 54, "the Little Steam"),
    (430, 130, 70, 54, "the Cedar Tub"),
]
BUILDINGS = []
for i, (bx, bw, bd, bh, bname) in enumerate(BUILDING_DEFS):
    BUILDINGS.append({
        "id": "bathhouse_%d" % i, "view": "bathhouse", "label": bname,
        "rect": [bx, STREET_Y - bd, bw, bd], "h": bh,
        "wall": list(WOODS[i]), "roof": list(ROOFS[i]), "trim": [0.88, 0.80, 0.66],
        "door": True, "door_color": [0.30, 0.20, 0.14], "roof_style": "gable",
        "chimney": i % 2 == 0, "windows": True,
        "glow": [1.0, 0.86, 0.56], "curtain": list(CURTAINS[i]),
    })

# ── the secret's place ───────────────────────────────────────────────────────────────────────────────
BELL = (-1180, -790)
BELL_CLEAR = 72
BOARDWALK_END = (-1000, -280)


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

# ── hand-placed props: the landing, things to look at, the notices that hint at the bell ─────────────
SPECIAL = [
    prop("landing_lantern", "sh_lantern", (44, 880), WHITE, "a paper lantern",
         "A paper lantern on a post, lit from inside. Its light makes a small warm room in the mist, just big enough for you and your companion.", solid=True, radius=4),
    prop("landing_notice", "sh_board", (-44, 850), WHITE, "a notice board",
         "A weathered notice board. 'WELCOME TO STEAMHOLLOW. Baths are hot, the mist is thick, and nobody here minds if you are late. Please do not hurry the water.'", solid=True, radius=5),
    prop("row_notice", "sh_board", (-640, 330), WHITE, "the bellkeeper's board",
         "The bellkeeper's board: 'The little bell by the cold spring has gone too quiet for people to hear again. It never stops ringing; we only stop listening. If you've a companion, stand still together and let it listen. Mind you, it hears best when it is calm, and it hears nothing at all if you hurry.'", solid=True, radius=5),
    prop("cedar_end_notice", "sh_board", (BOARDWALK_END[0] + 34, BOARDWALK_END[1] - 6), WHITE, "a notice board",
         "The boardwalk ends here, and the cedars begin. Someone has chalked below the old notice: 'Past this point the mist is all there is. Stand still. Let the little one listen.'", solid=True, radius=5),
    prop("cedar_end_jizo", "sh_jizo", (BOARDWALK_END[0] - 30, BOARDWALK_END[1] - 8), WHITE, "a little stone guardian",
         "A small stone guardian in a faded red bib, mossy at the feet. Travellers leave it a pebble for company. You do, too.", solid=True, radius=5),
    prop("row_stool_a", "sh_stool", (-120, 336), WHITE, "a bath stool",
         "A low wooden stool, still damp. Whoever sat here has only just gone in. Their sandals are lined up very neatly beside it."),
    prop("row_bucket_a", "sh_bucket", (-95, 338), WHITE, "a wooden bucket",
         "A bucket of water, still warm. A ladle floats in it, turning slowly, like it's thinking."),
    prop("row_bench", "sh_bench", (150, 350), WHITE, "a bench by the foot bath",
         "A bench beside a small hot pool. The boards under it are worn smooth in exactly two places."),
    prop("row_bench_b", "sh_bench", (-380, 350), WHITE, "a bench by the foot bath",
         "A bench with a view of nothing: just steam, and the shape of the next lantern."),
    prop("terrace_rack", "sh_towel_rack", (1060, 220), WHITE, "a rack of towels",
         "Towels hang from the rack and never seem to dry. They drip, quietly, in a rhythm. You find yourself counting it.", solid=True, radius=9),
    prop("green_rack_a", "sh_towel_rack", (-760, 700), WHITE, "a rack of towels",
         "A long rack of towels, cream and indigo, all hanging a little crooked. A very small footprint leads out from under it and back in again."),
    prop("green_rack_b", "sh_towel_rack", (-840, 880), WHITE, "a rack of towels",
         "Someone hung their towel here to dry a long time ago, and it's cheerfully refused.", solid=True, radius=9),
    prop("springs_basin", "sh_mossrock", (-60, -520), WHITE, "an old stone basin",
         "A stone basin, older than the boardwalks. It still holds hot water, and a single yellow leaf that has been going round and round for who knows how long.", solid=True, radius=8),
    prop("springs_vent", "sh_steam_vent", (310, -560), WHITE, "a steam vent",
         "A breath of steam rises from a crack in the stone, in no hurry, every few seconds, like the ground sighing in its sleep."),
    prop("maple_bench", "sh_bench", (1040, -660), WHITE, "a bench under the maples",
         "A bench under a maple, red leaves collected on it. You sit down, and the leaves rearrange themselves around you."),
    prop("nook_stool", "sh_stool", (-1118, -770), WHITE, "a bellkeeper's stool",
         "A small stool, set down on purpose. Whoever sat here sat very still for a very long time, listening."),
]

placed = [(p["position"][0], p["position"][1], 24) for p in SPECIAL]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 70))

# lanterns beside the spine and along the street: the cozy backbone of the village
LANTERNS = []
for k, y in enumerate(range(340, 900, 90)):
    for sx in (-1, 1):
        LANTERNS.append(prop("spine_lantern_%d_%d" % (k, sx), "sh_lantern", (sx * 46, y), WHITE, "a paper lantern", solid=True, radius=4))
for k, x in enumerate(range(-900, 1100, 110)):
    if abs(x) < 70:
        continue
    LANTERNS.append(prop("row_lantern_%d" % k, "sh_lantern", (x, 326), WHITE, "a paper lantern", solid=True, radius=4))
for k, y in enumerate(range(-240, 300, 110)):
    LANTERNS.append(prop("cedar_toro_%d" % k, "sh_stone_lantern", (-964, y), WHITE, "a stone lantern", solid=True, radius=6))
for k, y in enumerate(range(-240, 300, 120)):
    LANTERNS.append(prop("terrace_lantern_%d" % k, "sh_lantern", (1056, y), WHITE, "a paper lantern", solid=True, radius=4))
for k, x in enumerate(range(-820, -40, 140)):
    LANTERNS.append(prop("green_lantern_%d" % k, "sh_lantern", (x, 838), WHITE, "a paper lantern", solid=True, radius=4))
for p_ in LANTERNS:
    placed.append((p_["position"][0], p_["position"][1], 18))


def _seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
    return math.hypot(p[0] - (ax + dx * t), p[1] - (ay + dy * t))


def _rect_dist(x, y, r):
    """distance from (x, y) to the rectangle [rx, ry, rw, rh] (0 inside)"""
    rx, ry, rw, rh = r
    dx = max(rx - x, 0, x - (rx + rw))
    dy = max(ry - y, 0, y - (ry + rh))
    return math.hypot(dx, dy)


def clear(x, y, r):
    if not (BOUNDS_MIN[0] + 140 <= x <= BOUNDS_MAX[0] - 140 and BOUNDS_MIN[1] + 140 <= y <= BOUNDS_MAX[1] - 140):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 180:
        return False
    if any(math.hypot(x - pd["center"][0], y - pd["center"][1]) < pd["radius"] * 1.2 + r + 6 for pd in PONDS):
        return False
    if any(_rect_dist(x, y, pl["rect"]) < 22 + r for pl in PLATES):
        return False
    # buildings: keep their footprints and the tall roofs clear, and the strip behind them lightly
    if any(_rect_dist(x, y, b["rect"]) < 30 + r or (b["rect"][0] - 20 < x < b["rect"][0] + b["rect"][2] + 20 and b["rect"][1] - 70 < y < b["rect"][1]) for b in BUILDINGS):
        return False
    if math.hypot(x - BELL[0], y - BELL[1]) < BELL_CLEAR + r:
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


def trees(region, n, kind, r=26):
    for x, y in scatter(region, n, r):
        TREES.append([x, y, kind])


def props(region, n, type, label, r=16, solid=None, radius=None):
    for i, (x, y) in enumerate(scatter(region, n, r)):
        PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), WHITE, label, solid=solid, radius=radius))


# The Stillwater Nook: thick cedars round a cold spring (the bell's clearing is kept bare above)
trees("stillwater_nook", 70, "cedar", 24)
trees("stillwater_nook", 14, "willow", 28)
props("stillwater_nook", 10, "sh_mossrock", "a mossy rock", r=18, solid=True, radius=8)
# Old Springs: wild, open, rocky pools
trees("old_springs", 22, "willow", 28)
trees("old_springs", 24, "cedar", 24)
props("old_springs", 14, "sh_mossrock", "a mossy rock", r=18, solid=True, radius=8)
props("old_springs", 8, "sh_steam_vent", "a steam vent", r=14)
# Maple Bank: red and gold
trees("maple_bank", 60, "maple", 28)
trees("maple_bank", 14, "cedar", 24)
props("maple_bank", 10, "sh_mossrock", "a mossy rock", r=18, solid=True, radius=8)
# Cedar Walk
trees("cedar_walk", 90, "cedar", 24)
trees("cedar_walk", 10, "mist", 28)
props("cedar_walk", 8, "sh_mossrock", "a mossy rock", r=18, solid=True, radius=8)
# Kettle Row: only a few trees, the street is for walking
trees("kettle_row", 12, "maple", 28)
trees("kettle_row", 8, "mist", 28)
props("kettle_row", 10, "sh_bucket", "a bucket", r=12)
props("kettle_row", 8, "sh_stool", "a bath stool", r=12)
# Soak Terraces
trees("soak_terraces", 22, "maple", 28)
trees("soak_terraces", 16, "mist", 28)
props("soak_terraces", 8, "sh_steam_vent", "a steam vent", r=14)
props("soak_terraces", 6, "sh_bench", "a bench", r=18)
props("soak_terraces", 8, "sh_bucket", "a bucket", r=12)
# Drying Green
trees("drying_green", 18, "mist", 28)
trees("drying_green", 12, "willow", 28)
props("drying_green", 6, "sh_towel_rack", "a rack of towels", r=22, solid=True, radius=9)
props("drying_green", 6, "sh_bench", "a bench", r=18)
props("drying_green", 4, "sh_jizo", "a little stone guardian", r=14, solid=True, radius=5)
# Lantern Landing
trees("lantern_landing", 36, "cedar", 26)
trees("lantern_landing", 22, "maple", 28)
trees("lantern_landing", 16, "mist", 28)
props("lantern_landing", 12, "sh_mossrock", "a mossy rock", r=18, solid=True, radius=8)
props("lantern_landing", 8, "sh_stool", "a bath stool", r=12)
props("lantern_landing", 6, "sh_steam_vent", "a steam vent", r=14)

ALL_PROPS = SPECIAL + LANTERNS + PROPS

# ── walkability: flood-fill the ground from the spawn and prove it reaches everything that matters ───
CELL = 12
BODY = 15   # the avatars' body radius plus margin, generously


def _blocked_fn():
    circles = [(t[0], t[1], 7 + BODY) for t in TREES]
    for lm in LANDMARKS:
        circles.append((lm["position"][0], lm["position"][1], 16 + BODY))
    for p in ALL_PROPS:
        if p.get("solid"):
            circles.append((p["position"][0], p["position"][1], p.get("collision_radius", 8) + BODY))
    for pd in PONDS:
        circles.append((pd["center"][0], pd["center"][1], pd["radius"] + 6))
    rects = [b["rect"] for b in BUILDINGS]

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
    return [{"trunk": S + "sh_%s_trunk.png" % n, "canopy": S + "sh_%s_canopy.png" % n} for n in names]


CEDARS = ["cedar_a", "cedar_b", "cedar_c", "cedar_d"]
MAPLES = ["maple_a", "maple_b", "maple_c"]
MISTS = ["mist_a", "mist_b"]
WILLOWS = ["willow_a", "willow_b"]
ART = {
    # damp green-grey ground under a warm, dim evening
    "palette": {
        "ground_top": [0.40, 0.52, 0.44], "ground_bottom": [0.32, 0.44, 0.38],
        "foliage_dark": [0.12, 0.26, 0.24], "foliage_mid": [0.30, 0.46, 0.42], "foliage_light": [0.60, 0.74, 0.64],
        "bark": [0.30, 0.24, 0.20], "water": [0.36, 0.70, 0.68], "rim": [1.0, 0.90, 0.72],
        "shadow": [0.08, 0.10, 0.16], "grass": [0.40, 0.52, 0.44], "water_rim": [0.92, 0.99, 0.96, 0.7],
    },
    "light": {"shadow_alpha": 0.22, "rim_strength": 0.16},
    "entities": {
        "portal": {"frame_tint": [0.92, 0.84, 0.74]},
        "ground": {
            "render": "pixel", "terrain": S + "sh_terrain.png", "tile": 128,
            "details": S + "sh_details.png", "details_index": "res://data/sh_details.json",
            "shade": 0.2,
            "ramps": {
                "grass": ramp((0.26, 0.38, 0.32), (0.32, 0.46, 0.38), (0.38, 0.53, 0.43), (0.52, 0.68, 0.54)),
                "lush": ramp((0.20, 0.32, 0.28), (0.25, 0.40, 0.33), (0.31, 0.47, 0.38), (0.44, 0.62, 0.48)),
                "meadow": ramp((0.34, 0.46, 0.38), (0.41, 0.54, 0.44), (0.48, 0.61, 0.50), (0.62, 0.74, 0.60)),
                "dirt": ramp((0.22, 0.20, 0.22), (0.29, 0.26, 0.27), (0.35, 0.31, 0.31), (0.46, 0.42, 0.40)),
                "sand": ramp((0.46, 0.50, 0.48), (0.55, 0.60, 0.57), (0.63, 0.68, 0.64), (0.78, 0.82, 0.76)),
                "path": ramp((0.30, 0.26, 0.24), (0.38, 0.33, 0.30), (0.45, 0.39, 0.34), (0.58, 0.52, 0.45)),
                "worn": ramp((0.28, 0.38, 0.31), (0.35, 0.46, 0.37), (0.42, 0.53, 0.42), (0.55, 0.66, 0.52)),
            },
            "accents": [[1.0, 0.86, 0.60]],
            "patches": {"lush": {"scale": 0.004, "threshold": 0.50}, "meadow": {"scale": 0.005, "threshold": 0.62},
                        "dirt": {"scale": 0.006, "threshold": 0.90}},
            "clump": {"scale": 0.009, "dark": 0.34, "light": 0.66},
            "scatter": {
                "density": 0.8,
                "open": [
                    {"names": ["mosstuft_a", "mosstuft_b"], "weight": 24, "count": [1, 4], "sway": 0.2},
                    {"names": ["fern", "sprout"], "weight": 20, "count": [1, 3], "sway": 0.3},
                    {"names": ["pebbles"], "weight": 8, "count": [1, 2]},
                    {"names": ["wetstone"], "weight": 5},
                    {"names": ["mapleleaf", "ginkgo"], "weight": 6},
                    {"names": ["twig"], "weight": 4},
                ],
                "under_trees": {"names": ["twig", "mapleleaf"], "ring": ["mosstuft_a"]},
                "path_edge": [],
                "reeds": ["reed"],
                "lilies": [],
            },
        },
        "understory": {"render": "sprite", "prefix": S + "sh_understory_", "types": ["bush_a", "bush_b", "stump"], "density": 0.6},
        # a few warm fireflies in the mist; falling maple leaves; no butterflies and no cloud shadows (the mist is the weather)
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 12, "color": [1.0, 0.88, 0.56], "always": True},
                         "clouds": {"count": 0},
                         "leaves": {"rate": 0.5, "colors": [[0.84, 0.30, 0.20], [0.92, 0.62, 0.22], [0.70, 0.40, 0.18]]}},
        "tree": {"render": "sprite", "sway": 0.25, "variants": tree_variants(CEDARS * 2 + MAPLES + MISTS)},
        "cedar": {"render": "sprite", "sway": 0.2, "variants": tree_variants(CEDARS)},
        "maple": {"render": "sprite", "sway": 0.3, "variants": tree_variants(MAPLES)},
        "mist": {"render": "sprite", "sway": 0.3, "variants": tree_variants(MISTS)},
        "willow": {"render": "sprite", "sway": 0.4, "variants": tree_variants(WILLOWS)},
        "great_tree": {"render": "sprite", "sway": 0.15, "variants": tree_variants(["great_maple", "great_willow"])},
        "water": {"render": "sprite", "tile": S + "sh_onsen.png", "world_tile": 64},
        "pool": {"render": "sprite", "tile": S + "sh_onsen.png", "world_tile": 64},
        "river": {"render": "sprite", "tile": S + "sh_onsen.png", "world_tile": 64},
        # a bathhouse is a BuildingView in timber and tile (BathhouseView); boardwalks are plates
        "building": {"render": "sprite", "wall": S + "sh_wall.png", "roof": S + "sh_roof.png", "slope": S + "sh_slope.png"},
        "plate": {"render": "sprite", "flat": S + "sh_boards.png", "road": S + "sh_boards_v.png", "stud": S + "sh_boards.png"},
        "props": {"extra_types": ["sh_lantern", "sh_stone_lantern", "sh_bucket", "sh_stool", "sh_mossrock", "sh_bench",
                                  "sh_towel_rack", "sh_steam_vent", "sh_jizo", "sh_board"]},
        "prop_lights": {
            "sh_lantern": {"radius": 40, "y": -22, "alpha": 0.46},
            "sh_stone_lantern": {"radius": 30, "y": -14, "alpha": 0.38},
        },
    },
    # held at lamplit dusk: the lanterns are always lit
    "daycycle": {"enabled": True, "period_sec": 600, "loop": True, "hold": 0.8, "stops": [
        {"t": 0.0, "tint": [1.0, 0.98, 0.95], "vignette": [0.08, 0.10, 0.16], "vstrength": 0.30},
        {"t": 1.0, "tint": [0.80, 0.78, 0.92], "vignette": [0.10, 0.08, 0.20], "vstrength": 0.46}]},
}

ATMOSPHERE = {
    "day_tint": [0.88, 0.86, 0.95],
    "vignette": {"strength": 0.36, "color": [0.08, 0.09, 0.16]},
    "wind": {"strength": 0.7, "speed": 0.5},
    "pollen": {"amount": 14, "color": [1.0, 0.94, 0.80]},
    "region_tint_alpha": 0.06,
    "grass": {"max": 0},
    # the defining feature: a drifting mist that leaves you about two steps of clear view (MistVeil)
    "fog": {
        "clear_radius": 40, "fade_radius": 150, "color": [0.80, 0.82, 0.90], "warm": [1.0, 0.80, 0.52],
        "density": 0.93, "swirl": 0.35, "noise_scale": 0.011, "drift": [7, 3], "fade_in": 2.5,
        "light_clear": 0.9, "max_lights": 12, "companion_radius": 56, "friend_radius": 46,
        "lit": {
            "prop_types": {"sh_lantern": {"radius": 36, "warm": 1.0, "y": -22}, "sh_stone_lantern": {"radius": 28, "warm": 0.9, "y": -14}},
            "buildings": {"radius": 150, "warm": 0.85, "y": -20},
        },
    },
    # steam breathing off every spring, and off the vents
    "steam": {"color": [1.0, 0.98, 0.96], "alpha": 0.32, "rise": 38, "life": 4.5, "size": 16, "per_radius": 22,
              "vent_types": ["sh_steam_vent"], "vent_puffs": 3},
}

HEADER = ("STEAMHOLLOW - a bathhouse village lost in fog. A walk-and-soak world (no goal, no puzzle): wooden boardwalks, "
          "hot-spring pools breathing steam, paper lanterns and timber bathhouses, all half-hidden in drifting mist that "
          "leaves you about two steps of clear view (atmosphere.fog, MistVeil; atmosphere.steam, SteamPuffs). Eight regions: "
          "Lantern Landing (where you arrive), Kettle Row (the bathhouse street), Soak Terraces, Cedar Walk, Drying Green, "
          "Old Springs, Maple Bank and the Stillwater Nook. It RE-SKINS ITSELF through its 'art' block (deep-merged over "
          "data/art.json): its own damp ground + litter atlas, cedars/maples/willows (tree entries [x, y, kind]), milky "
          "hot-spring water, plate boardwalks, timber bathhouses (buildings with view 'bathhouse'), lantern light. Its secret "
          "is a faint bronze bell: see the 'secret' block (reveal type 'listen'). Generated by tools/gen_steamhollow_world.py "
          "(art: pokepals/tools/gen_steamhollow.py) - edit that and re-run, don't hand-tune positions.")

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Steamhollow'). reveal.type 'listen': a bronze "
                  "bell hangs in the fog, ringing too faintly to hear. When the companion is calm and settled beside the player "
                  "(player still or slow, companion close and standing easy) and within hearing (range by bond), its gaze turns "
                  "toward the bell and its ears prick (ListenGuide / ListenDirector); near the bell the tell sharpens and the "
                  "bell shows in the mist. The server honours a claim only here, within 'radius' of 'position'.")
SECRET = {
    "id": "faint_bell",
    "position": list(BELL),
    "radius": 120.0,
    "prop": {"type": "bronze_bell", "color": [0.86, 0.62, 0.30], "label": "a little bronze bell", "tags": ["small", "old", "quiet", "metal"]},
    "lore": "A little bronze bell on a leaning post, no bigger than a fist. You hold still and hear nothing at all. Your companion is looking at it as if it had said its name.",
    "reveal": {
        "type": "listen",
        "hear_range_low": 420.0, "hear_range_high": 900.0,
        "still_speed": 30.0, "companion_still_speed": 26.0, "companion_radius": 95.0,
        "settle_low": 2.4, "settle_high": 1.0, "lose_seconds": 2.2,
        "tell_cap_low": 0.7, "tell_cap_high": 1.0,
        "aim_error_low": 0.62, "aim_error_high": 0.22, "aim_residual": 0.10, "wobble_rate": 0.7,
        "near_radius": 240.0, "near_settle_factor": 0.45,
        "visible_radius": 130.0, "found_radius": 62.0, "aim_distance": 120.0, "pocket_radius": 46.0,
        "lines": {
            "hear": "Your companion goes still. Its ears prick, and it turns its head, listening to something you can't hear.",
            "lost": "It lowers its ears. Whatever it was hearing has slipped away. Stand still together, and it may hear it again.",
            "near": "Your companion's whole body is leaning toward the mist now, tail still, ears forward. You must be getting closer.",
            "close": "A small glint, in the mist ahead: bronze, hanging very still.",
        },
    },
    "found_line": "It had been ringing all along, too softly for anyone but the little one beside you. Now you know the sound is there.",
    "home_line": "Something has changed at home.",
    "qualities": ["quiet", "old", "crafted"],
    "keepsake": {
        "id": "faint_bell_kept", "type": "kept_bronze_bell", "color": [0.86, 0.62, 0.30], "label": "a little bronze bell on a stand",
        "line": "A bell too quiet for you to hear. Your companion tilts its head toward it now and then, and listens.",
        "temperament": {"curiosity": 0.6, "energy": 0.25, "clinginess": 0.6},
    },
}


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "steamhollow",')
out.append('\t"intro": %s,' % json.dumps("Mist, and lamplight, and the sound of water. You can see about two steps ahead, and that is plenty. Somewhere out here a very small bell is ringing, too softly for you."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": true, "spacing": 120, "inset": 24, "jitter": 34, "rows": 2, "row_gap": 60 },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.36, 0.48, 0.41],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [\n%s\n\t],' % block(PONDS))
out.append('\t"paths": [],')
out.append('\t"plates": [\n%s\n\t],' % block(PLATES))
out.append('\t"buildings": [\n%s\n\t],' % block(BUILDINGS))
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
for label, (x, y) in [("the bell", BELL), ("the end of the cedar walk", BOARDWALK_END), ("the Grand Soak shore", (0, -60)),
                      ("the terraces", (1020, -250)), ("the drying green", (-800, 800)), ("old springs", (-262, -500))] + \
        [("region " + rid, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)) for rid, a, b, _ in REGIONS]:
    ok = can_reach(seen, x, y, slack=6)
    assert ok, "%s is not reachable from the spawn" % label
for p in d["props"]:
    if p.get("interactive") and p["id"] != "":
        assert can_reach(seen, p["position"][0], p["position"][1], slack=8), "unreachable lore prop " + p["id"]
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("props:", len(d["props"]), "| trees:", kinds, "| plates:", len(PLATES), "| buildings:", len(BUILDINGS), "| walkable cells:", len(seen))
for path in ["server/priv/world_seeds/steamhollow.json", "pokepals/tests/world_fixtures/steamhollow.json"]:
    open(path, "w").write(text)
print("wrote both files")
