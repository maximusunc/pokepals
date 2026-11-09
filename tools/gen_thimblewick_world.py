#!/usr/bin/env python3
"""Generate THIMBLEWICK, the tiny cottage garden, as a world spec.

You are the size of a beetle. A clover leaf is an umbrella, a teacup is a pond, the garden fence is a castle
wall of whitewashed pickets, a dropped button is a landmark. 3200 x 2400, warm, buzzing, oversized; no goal.

Its one SECRET (docs/home-world-and-secrets-design.md, "Thimblewick"): a lost silver thimble behind a gap in
the great fence, a gap much too small for you. Fence gaps are simply MISSING PICKETS (the fence is a row of
tree-kind pickets 12 px apart; one missing leaves 10 px between its neighbours, narrower than any body). Only
something small and quick fits: in RABBIT form your companion, sent with "Go look", squeezes through, is gone a
few seconds and comes back carrying a find. WHAT it brings depends on the gap and on the bond: every gap has an
ordered list of finds, each with a `min_bond`. Four gaps hold ordinary small things; the fifth, marked by a trail
of red cotton, holds a pebble for a new companion, a button for a closer one and the THIMBLE for a deeply bonded
one. Each trip also warms the bond a little, so a fresh pair reaches the thimble in one visit. Examining the
dropped thimble claims the secret as usual (reveal type "fetch").

Hand-authored: regions, the teacup pond, the gaps and their finds, every lore line, the art override, the
secret. Procedural (seeded, so re-running reproduces it): the fence's pickets and the scatter of flowers,
clover and grass, kept clear of the gaps, the pond and the landing.

Art assets come from pokepals/tools/gen_thimblewick.py. Writes the server seed and the client test fixture.
Run from the repo root:  python3 tools/gen_thimblewick_world.py
"""
import json
import math
import random

random.seed(0x7417B1E)

BOUNDS_MIN = (-1600, -1200)
BOUNDS_MAX = (1600, 1200)
PLAYER_SPAWN = [0, 900]
COMPANION_SPAWN = [-30, 930]
PORTALS = [
    {"id": "thimblewick_way_home", "type": "portal", "position": [-72, 900], "color": [0.86, 0.92, 0.62], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

# ── regions: (id, min, max, tint): a clean partition of the bounds ───────────────────────────────────
FENCE_Y = -700
REGIONS = [
    ("far_side",        (-1600, -1200), (1600, FENCE_Y), (0.78, 0.80, 0.70)),
    ("clover_commons",  (-1600, FENCE_Y), (-550, 200),   (0.70, 0.90, 0.62)),
    ("dew_run",         (-550, FENCE_Y), (550, -100),    (0.86, 0.92, 0.60)),
    ("hose_works",      (550, FENCE_Y), (1600, 200),     (0.96, 0.88, 0.58)),
    ("teacup_green",    (-550, -100), (550, 500),        (0.94, 0.86, 0.66)),
    ("button_meadow",   (-1600, 200), (-550, 1200),      (0.80, 0.90, 0.60)),
    ("doorstep",        (-550, 500), (550, 1200),        (0.90, 0.88, 0.66)),
    ("peg_corner",      (550, 200), (1600, 1200),        (0.96, 0.84, 0.62)),
]

# ── the teacup pond ───────────────────────────────────────────────────────────────────────────────────
TEA = [0.52, 0.32, 0.14]
TEACUP = (0, 150)
PONDS = [{"center": list(TEACUP), "radius": 108, "color": TEA}]

LANDMARKS = [   # great sunflowers (the art block gives them two colours)
    {"type": "great_tree", "position": [-1230, -330]},
    {"type": "great_tree", "position": [1230, -470]},
    {"type": "great_tree", "position": [940, 780]},
    {"type": "great_tree", "position": [-870, 1000]},
]

# ── THE FENCE AND ITS GAPS ───────────────────────────────────────────────────────────────────────────
# Pickets stand 12 px apart (one "tree" each, collision radius 7, so the wall is continuous); a missing picket
# leaves 24 px between neighbours' centres, 10 px clear: no body fits (a body needs 2 x (6 + 2)).
PICKET_X0, PICKET_DX = -1596, 12
GAPS_SPEC = [
    # id, nominal x, cache offset, label for the mouth, the gap's finds (ordered by min_bond)
    ("gap_roots", -1180, -90, [("pebble", 0.0), ("acorn", 0.45)]),
    ("gap_hollow", -560, 70, [("pebble", 0.0), ("feather", 0.40)]),
    ("gap_stoop", 40, -40, [("pebble", 0.0), ("bead", 0.40)]),
    ("gap_thread", 640, 80, [("pebble", 0.0), ("button", 0.40), ("thimble", 0.65)]),   # THE thimble gap
    ("gap_corner", 1200, 60, [("pebble", 0.0), ("feather", 0.35), ("acorn", 0.65)]),
]
THIMBLE_GAP = "gap_thread"


def snap(x):
    k = round((x - PICKET_X0) / PICKET_DX)
    return PICKET_X0 + PICKET_DX * k


GAPS = []
for gid, gx, cdx, finds in GAPS_SPEC:
    x = snap(gx)
    GAPS.append({
        "id": gid,
        "mouth": [x, FENCE_Y + 34],     # on the open side, where the worn earth is
        "inside": [x, FENCE_Y - 36],    # just behind the pickets
        "cache": [x + cdx, -810],      # where the finds lie
        "finds": [{"item": i, "min_bond": b} for i, b in finds],
    })
THIMBLE = next(g for g in GAPS if g["id"] == THIMBLE_GAP)


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

GAP_LORE = {
    "gap_roots": "A gap in the fence where a picket has rotted clean away: ten fingers wide, if you had fingers that size. You couldn't get a shoulder through it. Something smaller and quicker might.",
    "gap_hollow": "A gap between two leaning pickets, worn smooth at the bottom by small feet. You'd stick fast. A rabbit would not.",
    "gap_stoop": "Here a picket has fallen and a bit of the dust has been scooped into a dip. It leads somewhere you cannot follow. Tap your companion and choose Go look, and in the right shape it might.",
    "gap_thread": "A thread of red cotton snagged on the picket runs through this gap, as if someone small once dragged something heavy through it. You cannot follow. Your companion, if it were small and quick, could.",
    "gap_corner": "A gap by the corner post, half-hidden in grass. On the far side you can see a little worn path, no wider than a rabbit.",
}

# ── hand-placed props: the landing, the gaps' mouths, things to look at ──────────────────────────────
SPECIAL = []
for g in GAPS:
    SPECIAL.append(prop("worn_" + g["id"], "gap_worn", g["mouth"], WHITE, "a gap in the fence", GAP_LORE[g["id"]], tags=["fence", "small", "odd"]))
# the clue at the thimble gap: red cotton from the mouth, and its reel a little way off
SPECIAL.append(prop("thread_trail", "red_thread", (THIMBLE["mouth"][0] + 4, FENCE_Y + 18), WHITE, "a trail of red cotton",
                    "Red cotton, snagged on a picket and trailing out across the dust. It is not quite the colour of anything else in the garden.", tags=["thread", "made"]))
SPECIAL.append(prop("cotton_reel", "cotton_reel", (THIMBLE["mouth"][0] - 74, FENCE_Y + 84), WHITE, "a cotton reel",
                    "A cotton reel, standing on end like a tower, wound with red. It has been unwinding for a long time, and the loose end leads off to the fence.",
                    tags=["thread", "made", "round"], solid=True, radius=11))
SPECIAL += [
    prop("landing_flag_1", "flagstone", (0, 1030), WHITE, "a flagstone"),
    prop("landing_flag_2", "flagstone", (24, 960), WHITE, "a flagstone"),
    prop("landing_flag_3", "flagstone", (-6, 860), WHITE, "a flagstone"),
    prop("landing_flag_4", "flagstone", (30, 770), WHITE, "a flagstone"),
    prop("landing_peg", "clothes_peg", (-250, 1010), WHITE, "a clothes-peg",
         "A wooden clothes-peg, dropped from a line you can't see for the height of the stalks. It would make a fine bench, if you could climb it.", tags=["made", "wood"]),
    prop("lost_button", "lost_button", (-980, 790), WHITE, "a button as big as a trampoline",
         "A button the size of a trampoline, four holes and a loop of red cotton still through two of them. Somebody's coat has been one button short since spring.",
         tags=["made", "round"]),
    prop("watering_can", "watering_can", (900, -90), WHITE, "a watering can",
         "A copper watering can, green at the seams. Its spout is a tunnel and its rose a cloud of tiny sunken stars. It still smells of rain.", tags=["made", "metal"], solid=True, radius=20),
    prop("coiled_hose", "coiled_hose", (1060, 200), WHITE, "a coiled garden hose",
         "A garden hose, coiled like a sleeping serpent. It is warm from the sun, and full of a faint, patient sound that is only water waiting.", tags=["made", "round"], solid=True, radius=26),
    prop("tipped_pot", "tipped_pot", (1250, 380), WHITE, "a tipped flowerpot",
         "A terracotta pot, lying on its side with its mouth full of shade: a cave, with a floor of spilled earth. Something has been living in it and has just gone out.", tags=["made", "earth"], solid=True, radius=22),
    prop("snail_shell", "snail_shell", (-1150, 120), WHITE, "an empty snail shell",
         "An empty snail shell, banded in tawny stripes and large as a boulder. Its owner has long since moved on to a bigger house.", tags=["round", "old"], solid=True, radius=14),
    prop("seed_packet", "seed_packet", (1180, 850), WHITE, "a seed packet",
         "A seed packet leaning on a stone, its painted flower faded to a rumour. The picture shows something far larger than you've ever seen grow here. Perhaps it is the sunflowers.", tags=["made", "paper"]),
    prop("bottle_cap", "bottle_cap", (-640, 640), WHITE, "a bottle top",
         "A bottle top, upside down and full of rain: a round pool a hundred beetles could bathe in. A leaf is going round on it, very slowly.", tags=["made", "watery"]),
    prop("dew_1", "dewdrop", (-720, -110), WHITE, "a bead of dew",
         "A bead of dew, big as a beehive, with the whole garden upside down in it. You are in there too, very small.", tags=["watery", "shiny"]),
    prop("dew_2", "dewdrop", (480, 320), WHITE, "a bead of dew",
         "Dew, held in a hollow of a leaf. It wobbles when you step near and the sky wobbles with it.", tags=["watery", "shiny"]),
    prop("dew_3", "dewdrop", (-300, -430), WHITE, "a bead of dew", "A cold, clear bead. Everything in it is the wrong way up and quite beautiful.", tags=["watery", "shiny"]),
    prop("saucer_dew", "dewdrop", (-150, 252), WHITE, "a drop on the saucer rim",
         "Cold tea, a lake of it, in a cup larger than a barn, and a saucer you could hold a feast on. It smells of bergamot and of someone who sat here once and forgot to finish.", tags=["watery", "made"]),
    prop("teacup", "teacup", TEACUP, WHITE, "a teacup"),
]

placed = [(p["position"][0], p["position"][1], 24) for p in SPECIAL if p["type"] != "teacup"]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 70))
for g in GAPS:
    placed.append((g["mouth"][0], g["mouth"][1], 70))
PATH_PTS = [(0, 960), (-30, 780), (-110, 560), (-230, 340), (-330, 100), (-380, -150), (-300, -420), (-150, -640)]


def _seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
    return math.hypot(p[0] - (ax + dx * t), p[1] - (ay + dy * t))


def clear(x, y, r, strip=False):
    if not (BOUNDS_MIN[0] + 140 <= x <= BOUNDS_MAX[0] - 140 and BOUNDS_MIN[1] + 140 <= y <= BOUNDS_MAX[1] - 140):
        return False
    if abs(y - FENCE_Y) < 60 + r:
        return False                                      # the fence line and a clear lane either side of it
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 200:
        return False
    if any(math.hypot(x - pd["center"][0], y - pd["center"][1]) < pd["radius"] * 1.3 + 16 + r for pd in PONDS):
        return False
    if any(_seg_dist((x, y), a, b) < 26 + r for a, b in zip(PATH_PTS[:-1], PATH_PTS[1:])):
        return False                                      # the garden path stays open
    # the strip behind the fence keeps a corridor from each gap's inside to its cache
    if y < FENCE_Y:
        for g in GAPS:
            if _seg_dist((x, y), g["inside"], g["cache"]) < 70 + r:
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


def props(region, n, type, label, r=18, solid=None, radius=None):
    for i, (x, y) in enumerate(scatter(region, n, r)):
        PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), WHITE, label, solid=solid, radius=radius))


# the fence itself: one picket per 12 px, a few missing (the gaps)
gap_xs = {g["mouth"][0] for g in GAPS}
x = PICKET_X0
FENCE = []
while x <= -PICKET_X0:
    if x not in gap_xs:
        FENCE.append([x, FENCE_Y, "picket"])
    x += PICKET_DX
TREES += FENCE

# Far Side: the lane behind the fence, sealed by it: long grass and a few flowers, a few things lying about
trees("far_side", 70, "grass", 22)
trees("far_side", 14, "daisy", 24)
trees("far_side", 8, "clover", 24)
trees("far_side", 6, "bluebell", 22)
props("far_side", 10, "flagstone", "a flagstone")
props("far_side", 4, "bottle_cap", "a bottle top")
props("far_side", 6, "dewdrop", "a bead of dew")
# Clover Commons: a village of umbrellas
trees("clover_commons", 40, "clover", 30)
trees("clover_commons", 22, "grass", 22)
trees("clover_commons", 9, "daisy", 24)
trees("clover_commons", 8, "bluebell", 22)
trees("clover_commons", 4, "foxglove", 22)
props("clover_commons", 8, "dewdrop", "a bead of dew")
props("clover_commons", 3, "snail_shell", "an empty snail shell", solid=True, radius=14)
# Dew Run: the tall flowers, a long avenue of them
trees("dew_run", 16, "daisy", 24)
trees("dew_run", 14, "poppy", 24)
trees("dew_run", 14, "cosmos", 24)
trees("dew_run", 9, "dandelion", 24)
trees("dew_run", 9, "foxglove", 22)
trees("dew_run", 14, "grass", 22)
trees("dew_run", 8, "clover", 28)
props("dew_run", 5, "dewdrop", "a bead of dew")
# Hose Works: sun on the east side, sunflowers (landmarks), the big made things
trees("hose_works", 14, "poppy", 24)
trees("hose_works", 12, "cosmos", 24)
trees("hose_works", 9, "dandelion", 24)
trees("hose_works", 9, "foxglove", 22)
trees("hose_works", 18, "grass", 22)
trees("hose_works", 8, "daisy", 24)
props("hose_works", 4, "clothes_peg", "a clothes-peg", r=22)
# Teacup Green: open lawn round the cup, with a few flowers and clover umbrellas
trees("teacup_green", 11, "grass", 22)
trees("teacup_green", 10, "clover", 28)
trees("teacup_green", 7, "daisy", 24)
trees("teacup_green", 7, "bluebell", 22)
props("teacup_green", 5, "dewdrop", "a bead of dew")
# Button Meadow, the Doorstep, Peg Corner
trees("button_meadow", 13, "dandelion", 24)
trees("button_meadow", 13, "daisy", 24)
trees("button_meadow", 16, "clover", 28)
trees("button_meadow", 20, "grass", 22)
trees("button_meadow", 8, "poppy", 24)
props("button_meadow", 4, "snail_shell", "an empty snail shell", solid=True, radius=14)
props("button_meadow", 4, "clothes_peg", "a clothes-peg", r=22)
trees("doorstep", 10, "grass", 22)
trees("doorstep", 9, "daisy", 24)
trees("doorstep", 7, "bluebell", 22)
trees("doorstep", 6, "clover", 28)
props("doorstep", 3, "dewdrop", "a bead of dew")
trees("peg_corner", 9, "foxglove", 22)
trees("peg_corner", 11, "bluebell", 22)
trees("peg_corner", 18, "grass", 22)
trees("peg_corner", 11, "cosmos", 24)
trees("peg_corner", 11, "clover", 28)
props("peg_corner", 4, "bottle_cap", "a bottle top")
props("peg_corner", 4, "dewdrop", "a bead of dew")

ALL_PROPS = SPECIAL + PROPS

# ── the world's own ART OVERRIDE (deep-merged over data/art.json by ArtStyle.load_style) ─────────────
S = "res://assets/sprites/"


def ramp(*rows):
    return [list(r) for r in rows]


def tree_variants(names):
    return [{"trunk": S + "tw_%s_trunk.png" % n, "canopy": S + "tw_%s_canopy.png" % n} for n in names]


def sprite_variants(names):
    return [{"sprite": S + "tw_%s.png" % n} for n in names]


PICKET_NAMES = ["picket_plain_0", "picket_plain_1", "picket_plain_0", "picket_plain_1", "picket_chip_2", "picket_knot_3", "picket_lean_4", "picket_moss_5"]
GRASS_NAMES = ["grass0", "grass1", "grass2"]
CLOVER_NAMES = ["clover0", "clover0", "clover1"]
PROP_TYPES = ["gap_worn", "red_thread", "cotton_reel", "flagstone", "clothes_peg", "lost_button", "watering_can", "coiled_hose",
              "tipped_pot", "snail_shell", "seed_packet", "bottle_cap", "dewdrop"]


def flower(name, sway=0.3):
    return {"render": "sprite", "sway": sway, "variants": tree_variants([name])}


ART = {
    # a late afternoon: saturated greens, honey light, long soft shadows
    "palette": {
        "ground_top": [0.52, 0.68, 0.30], "ground_bottom": [0.40, 0.56, 0.24],
        "foliage_dark": [0.12, 0.30, 0.14], "foliage_mid": [0.28, 0.56, 0.22], "foliage_light": [0.60, 0.80, 0.34],
        "bark": [0.40, 0.30, 0.20], "water": [0.52, 0.32, 0.14], "rim": [1.0, 0.92, 0.66],
        "shadow": [0.16, 0.10, 0.04], "grass": [0.34, 0.54, 0.20], "water_rim": [0.98, 0.84, 0.54, 0.8],
    },
    "light": {"shadow_alpha": 0.26, "rim_strength": 0.3},
    "entities": {
        "portal": {"frame_tint": [0.86, 0.92, 0.64]},
        "ground": {
            "render": "pixel", "terrain": S + "tw_terrain.png", "tile": 128,
            "details": S + "tw_details.png", "details_index": "res://data/tw_details.json",
            "shade": 0.20,
            "ramps": {
                "grass": ramp((0.22, 0.42, 0.16), (0.30, 0.54, 0.20), (0.38, 0.62, 0.24), (0.66, 0.80, 0.34)),
                "lush": ramp((0.14, 0.34, 0.16), (0.20, 0.46, 0.20), (0.27, 0.54, 0.24), (0.46, 0.74, 0.34)),
                "meadow": ramp((0.28, 0.46, 0.16), (0.38, 0.58, 0.20), (0.46, 0.66, 0.24), (0.74, 0.84, 0.36)),
                "dirt": ramp((0.24, 0.15, 0.09), (0.34, 0.22, 0.13), (0.42, 0.28, 0.17), (0.64, 0.48, 0.30)),
                "sand": ramp((0.52, 0.46, 0.38), (0.64, 0.58, 0.48), (0.72, 0.66, 0.56), (0.88, 0.82, 0.70)),
                "path": ramp((0.44, 0.38, 0.30), (0.56, 0.49, 0.38), (0.62, 0.55, 0.43), (0.78, 0.70, 0.56)),
                "worn": ramp((0.30, 0.42, 0.18), (0.38, 0.50, 0.22), (0.44, 0.56, 0.26), (0.62, 0.72, 0.34)),
            },
            "accents": [[1.0, 0.90, 0.30], [1.0, 1.0, 1.0], [0.96, 0.52, 0.62], [0.62, 0.62, 1.0]],
            "patches": {"lush": {"scale": 0.004, "threshold": 0.54}, "meadow": {"scale": 0.0055, "threshold": 0.60},
                        "dirt": {"scale": 0.006, "threshold": 0.84}},
            "clump": {"scale": 0.010, "dark": 0.34, "light": 0.66},
            "scatter": {
                "density": 0.9,
                "open": [
                    {"names": ["grassblade_a", "grassblade_b"], "weight": 26, "count": [1, 4], "sway": 0.4},
                    {"names": ["cloverleaf"], "weight": 18, "count": [1, 3]},
                    {"names": ["buttercup"], "weight": 8, "count": [1, 3]},
                    {"names": ["petal_white", "petal_pink"], "weight": 9, "count": [1, 3]},
                    {"names": ["seed", "crumb"], "weight": 8, "count": [1, 3]},
                    {"names": ["pebble_a", "acorncap"], "weight": 4},
                    {"names": ["twig"], "weight": 5},
                ],
                "under_trees": {"names": ["twig", "crumb"], "ring": ["petal_white", "petal_pink"]},
                "path_edge": ["pebble_a"],
                "reeds": ["grassblade_b"],
                "lilies": ["tealeaf"],
            },
        },
        "understory": {"render": "sprite", "prefix": S + "tw_understory_", "types": ["bush_a", "bush_b", "stump"], "density": 0.6},
        # a garden that hums: butterflies and petals on the breeze, a little pollen, no fireflies in daylight
        "ambient_life": {
            "butterflies": {"count": 12, "colors": [[1.0, 0.86, 0.3], [1.0, 1.0, 0.9], [0.96, 0.62, 0.3], [0.6, 0.8, 1.0], [0.98, 0.56, 0.70]]},
            "fireflies": {"count": 0}, "clouds": {"count": 4, "alpha": 0.07, "speed": 8},
            "leaves": {"rate": 0.7, "colors": [[1.0, 0.82, 0.88], [1.0, 1.0, 0.9], [1.0, 0.72, 0.5], [0.96, 0.9, 0.5]]},
        },
        # the border ring is long grass and clover; everything standing in the garden is a flower or a blade
        "tree": {"render": "sprite", "sway": 0.55, "variants": sprite_variants(GRASS_NAMES * 2) + tree_variants(CLOVER_NAMES)},
        "great_tree": {"render": "sprite", "sway": 0.2, "variants": tree_variants(["great_gold", "great_ember", "great_gold"])},
        "picket": {"render": "sprite", "sway": 0.0, "variants": sprite_variants(PICKET_NAMES)},
        "grass": {"render": "sprite", "sway": 0.6, "variants": sprite_variants(GRASS_NAMES)},
        "clover": {"render": "sprite", "sway": 0.25, "variants": tree_variants(CLOVER_NAMES)},
        "daisy": flower("daisy"), "poppy": flower("poppy"), "cosmos": flower("cosmos"), "dandelion": flower("dandelion"),
        "foxglove": flower("foxglove", 0.2), "bluebell": flower("bluebell", 0.25),
        "water": {"render": "sprite", "tile": S + "tw_tea.png", "world_tile": 64},
        "pool": {"render": "sprite", "tile": S + "tw_tea.png", "world_tile": 64},
        "river": {"render": "sprite", "tile": S + "tw_tea.png", "world_tile": 64},
        "props": {"extra_types": PROP_TYPES},
    },
    # a slow golden loop, honey to amber and back
    "daycycle": {"enabled": True, "period_sec": 420, "loop": True, "stops": [
        {"t": 0.0, "tint": [1.04, 0.99, 0.88], "vignette": [0.20, 0.10, 0.02], "vstrength": 0.30},
        {"t": 1.0, "tint": [1.07, 0.93, 0.78], "vignette": [0.24, 0.10, 0.02], "vstrength": 0.36},
    ]},
}

ATMOSPHERE = {
    "day_tint": [1.04, 0.99, 0.88],
    "vignette": {"strength": 0.30, "color": [0.20, 0.10, 0.02]},
    "wind": {"strength": 1.6, "speed": 0.8},
    "pollen": {"amount": 70, "color": [1.0, 0.92, 0.55]},
    "region_tint_alpha": 0.07,
    "grass": {"max": 0},
    "sparkles": {"count": 160, "colors": [[1.0, 0.96, 0.7], [1.0, 0.9, 0.55]]},
}

HEADER = ("THIMBLEWICK - a tiny cottage garden, seen at beetle size. A walk-and-wonder world: clover leaves for "
          "umbrellas, a teacup for a pond, tall flowers standing like trees, and a long whitewashed picket fence (one "
          "tree-kind picket every 12 px along y=-700) with a lane behind it that only something small can reach. Eight "
          "regions: Far Side (behind the fence), Clover Commons, Dew Run, Hose Works, Teacup Green, Button Meadow, the "
          "Doorstep (where you arrive) and Peg Corner. It RE-SKINS ITSELF through its 'art' block (deep-merged over "
          "data/art.json): its own garden terrain + litter atlas, flower stalks as tree kinds (daisy, poppy, cosmos, "
          "dandelion, foxglove, bluebell, clover, grass, picket), tea for water, a golden afternoon. The fence gaps are "
          "missing pickets; see the 'secret' block (reveal type 'fetch'). Generated by tools/gen_thimblewick_world.py "
          "(art: pokepals/tools/gen_thimblewick.py) - edit that and re-run, don't hand-tune positions.")

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Thimblewick'). reveal.type 'fetch': in a "
                  "shape from reveal.species (a rabbit) the companion, sent with Go look, squeezes through the nearest of "
                  "reveal.gaps (mouth: outside the fence; inside: behind it; cache: where the finds lie), is gone a few seconds "
                  "and brings back the best entry of that gap's 'finds' whose min_bond the bond has reached (FetchTrip / "
                  "FetchDirector). The thimble is dropped at the PLAYER's feet wherever they stand, so the server honours a "
                  "claim anywhere in this world (radius covers it); 'position' is only where it comes from.")

ITEMS = {
    "pebble": {
        "type": "find_pebble", "color": [0.66, 0.62, 0.58], "label": "a pebble",
        "lore": "A pebble, round and grey and warm from the sun on the other side of the fence. For you it is a boulder. Your companion is enormously proud of it.",
        "drop": "It sets a pebble at your feet and looks up at you, shining. A good pebble. It would bring something finer, perhaps, if it knew you better.",
    },
    "acorn": {
        "type": "find_acorn", "color": [0.72, 0.50, 0.24], "label": "an acorn cup",
        "lore": "An acorn's little hat, big as a bathtub, with the pattern of the nut still printed in it. Someone's lunch, a season ago.",
        "drop": "It trots out dragging an acorn cup, and lays it down with great ceremony.",
    },
    "feather": {
        "type": "find_feather", "color": [0.84, 0.84, 0.88], "label": "a feather",
        "lore": "A feather as long as a canoe, soft and grey with a pale stripe, from a bird you have never once seen in this garden. It is much too light for something so big.",
        "drop": "It comes back with a long grey feather held high, like a banner.",
    },
    "bead": {
        "type": "find_bead", "color": [0.36, 0.60, 0.92], "label": "a glass bead",
        "lore": "A glass bead, blue as a swimming pool, with a bubble caught in its middle and the whole sky in its curve. It must have rolled off a necklace years ago.",
        "drop": "It rolls a blue glass bead out through the gap and nudges it to you, pleased.",
    },
    "button": {
        "type": "find_button", "color": [0.94, 0.88, 0.82], "label": "a button",
        "lore": "A pearly button, four holes and a few threads of red still in them. It belongs to the same coat as the one in the meadow, you'd bet. Something deeper in there might be worth more.",
        "drop": "It comes back carrying a button, red thread trailing from its holes. Closer. There is something else back there, and it knows it.",
    },
    "thimble": {
        "type": "thimble", "color": [0.84, 0.88, 0.94], "label": "a silver thimble",
        "lore": "A thimble: a little silver cup, dimpled all over, with a rim worn smooth by a lifetime of pushing needles. For you it is a bell tower. Someone has been missing it for a very long time.",
        "drop": "It is carrying something that gleams, held so carefully that it does not blink. Your companion sets down a silver thimble at your feet.",
    },
}

SECRET = {
    "id": "silver_thimble",
    "position": list(THIMBLE["cache"]),
    "radius": 4000.0,
    "prop": {"type": "thimble", "color": [0.84, 0.88, 0.94], "label": "a silver thimble", "tags": ["small", "made", "shiny", "old"]},
    "lore": ITEMS["thimble"]["lore"],
    "reveal": {
        "type": "fetch",
        "species": ["rabbit"],
        "ask_range": 480.0, "mouth_reach": 10.0, "go_speed": 100.0, "go_patience": 10.0, "go_run_distance": 240.0, "poke_seconds": 1.8,
        "squeeze_seconds": 0.8, "away_low": 9.0, "away_high": 5.0, "hurry_seconds": 1.1, "emerge_seconds": 0.6,
        "bring_speed": 128.0, "drop_distance": 30.0, "bring_patience": 45.0, "cooldown": 2.0, "pet_pause": 3.0,
        "warm": 0.06, "warm_decay": 0.8, "warm_min": 0.008,
        "notice_range_low": 240.0, "notice_range_high": 560.0, "notice_cooldown_low": 18.0, "notice_cooldown_high": 7.0,
        "notice_hold": 2.4, "rustle_every": 1.1, "drift_hold": 30.0, "carry_lift": 26.0, "camera_lift": 120.0,
        "gaps": GAPS,
        "items": ITEMS,
        "lines": {
            "notice": "Your companion stops and stares at the fence. There is a gap there, a very small one.",
            "set_off": "Off it trots to the fence, to see what is on the other side.",
            "too_big": "It nudges at the gap and cannot fit. A gap this size wants something small and quick: a rabbit's shape, perhaps.",
            "gave_up_big": "It gives up with a sigh and a flop. Tap it and pick a smaller shape, then ask again.",
            "lost_way": "It couldn't find a way to the gap from here. Try again from nearer the fence.",
            "called_off": "You whistle, and it turns back from the fence.",
            "gone": "It squeezes through and is gone. The long grass behind the fence rustles.",
            "missing": "The garden is very big, and very quiet, without it.",
            "hurry": "It hears you, and scrabbles back out in a hurry.",
            "carrying": "There it is, slipping out of the gap with something almost as big as it is.",
            "set_down": "It sets its find down where it stands, and sits beside it, waiting.",
            "no_gap": "There's no gap in the fence near enough. Walk along the fence and look for one.",
            "busy": "Your companion is off on an errand. Wait for it, or whistle it back.",
            "more": "There is something more back there, it seems to say. It might fetch it once you know each other better.",
        },
        "reveal_line": "It trots out of the fence with something shining held high, and sets it down in front of you with a small, triumphant sneeze.",
    },
    "found_line": "A thimble, as big as a bell, silver and dented. Somebody sewed through a long winter with it and lost it on the wrong side of the fence. It has come home, carried by the only one who could fit through.",
    "home_line": "Something has changed at home.",
    "qualities": ["crafted", "warm", "old"],
    "keepsake": {
        "id": "silver_thimble_kept", "type": "kept_thimble", "color": [0.84, 0.88, 0.94], "label": "a silver thimble on a spool of red cotton",
        "line": "A thimble on a spool of red cotton. Your companion sits and looks at it sometimes, as if remembering a very tight squeeze.",
        "temperament": {"curiosity": 0.75, "energy": 0.65, "clinginess": 0.55},
    },
}


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "thimblewick",')
out.append('\t"intro": %s,' % json.dumps("A garden, and you are the size of a beetle. Clover is an umbrella, a teacup is a pond, and the fence is a castle wall. Nothing needs doing. Look up."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": true, "spacing": 120, "inset": 24, "jitter": 34, "rows": 2, "row_gap": 60 },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.46, 0.62, 0.28],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [\n%s\n\t],' % block(PONDS))
out.append('\t"paths": [\n%s\n\t],' % block([{"from": list(a), "to": list(b), "color": [0.62, 0.56, 0.42]} for a, b in zip(PATH_PTS[:-1], PATH_PTS[1:])]))
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
# every gap: a missing picket in an otherwise continuous run, mouth in the open, inside/cache behind the fence
pickets = sorted(t[0] for t in d["trees"] if t[2] == "picket")
for g in GAPS:
    gx = g["mouth"][0]
    assert gx not in pickets and (gx - PICKET_DX) in pickets and (gx + PICKET_DX) in pickets, "gap %s is not a single missing picket" % g["id"]
    assert g["mouth"][1] > FENCE_Y and g["inside"][1] < FENCE_Y and g["cache"][1] < FENCE_Y, "gap %s sides" % g["id"]
    assert g["finds"][0]["min_bond"] == 0 and all(a["min_bond"] < b["min_bond"] for a, b in zip(g["finds"][:-1], g["finds"][1:])), "finds ordered"
    for f in g["finds"]:
        assert f["item"] in ITEMS, f
assert len(pickets) == len(set(pickets))
# the fence seals the far side: it runs wall to wall
assert pickets[0] <= BOUNDS_MIN[0] + 14 and pickets[-1] >= BOUNDS_MAX[0] - 14, "the fence does not reach the walls"
# no pond or special prop lies on the fence line; nothing solid stands in a mouth
for t in d["trees"]:
    if t[2] != "picket":
        for g in GAPS:
            assert math.hypot(t[0] - g["mouth"][0], t[1] - g["mouth"][1]) > 50, "a tree stands at gap %s's mouth" % g["id"]
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("props:", len(d["props"]), "| trees:", kinds, "| gaps:", len(GAPS))
for path in ["server/priv/world_seeds/thimblewick.json", "pokepals/tests/world_fixtures/thimblewick.json"]:
    open(path, "w").write(text)
print("wrote both files")
