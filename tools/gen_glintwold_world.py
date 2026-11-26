#!/usr/bin/env python3
"""Generate GLINTWOLD, the faceted world, as a world spec (issue #160).

A walk-and-wonder world (3400 x 2600) that looks like a stylised low-poly scene seen from above:
everything is flat triangles, each one a single clean colour chosen by how it faces the light. Late
golden afternoon, clean and airy.

Glintwold was CUT, not grown. The whole wold was once one dull stone lying in the dark. Then a light
found it and began, very slowly, to turn round it, and wherever the light touched, a face was cut: a
hill, a pine, a deer. The light is still turning, so nothing here looks quite the same twice. Folk
who live here call each flat face a GLINT. The cutting stopped one face short: in the middle of the
wold hangs THE UNFINISHED, a great stone in loose pieces, on a low round dais called the TURNING
FLOOR. A carved line there says: "It only looks whole from two places at once."

Its one SECRET (the 'heartstone' and 'secret' blocks, reveal type "facets"): half the Unfinished's
pieces answer to where you stand, half to where your companion stands. Each half slides home only when
its viewer is on its own unmarked mark on the Turning Floor. Both home and held: the stone closes, and
the offcut, the last face that had to be cut away, falls at its foot.

Nine regions: the Landing (south, where you arrive), the Heart (the Turning Floor and the Unfinished),
the Tines (crystal spires behind it), the Pinefold, Goldhanger, the Low Tarns, the Brokeback (angular
hills), Cutwater (the big lake) and the Shardfield. Meandering sand paths join them, and a ring of
path marks the Turning Floor's rim.

Hand-authored: regions, the lake and tarns, paths, landmarks, the heartstone, every line of lore.
Procedural (seeded, so re-running reproduces it): the scatter of trees, props and creatures, kept
clear of the paths, the landing, the portal and the Turning Floor.

The art block is two fragments merged over a small fallback: pokepals/tools/lowpoly/glintwold_art.json
(palette, trees, props) and pokepals/tools/lowpoly/glintwold_look.json (ground, water, actor look, day
cycle). Writes the server seed and the client test fixture. Run from the repo root:
python3 tools/gen_glintwold_world.py
"""
import copy
import json
import math
import os
import random

random.seed(0x611E7)

BOUNDS_MIN = (-1700, -1300)
BOUNDS_MAX = (1700, 1300)
PLAYER_SPAWN = [0, 1030]
COMPANION_SPAWN = [-34, 1060]
PORTALS = [
    {"id": "glintwold_way_home", "type": "portal", "position": [0, 1130], "color": [0.98, 0.86, 0.52], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]


def hexc(h):
    h = h.lstrip("#")
    return tuple(round(int(h[i:i + 2], 16) / 255.0, 2) for i in (0, 2, 4))


SAND = hexc("#EAD9A6")
STONE = hexc("#B9B4C7")
GOLD = hexc("#F2C14E")
ROSE = hexc("#EE8FA0")
TEAL = hexc("#49B8B0")
SPIRE = hexc("#B8A6F0")
AQUA = hexc("#8EE0E6")
QUARTZ = hexc("#FAD0DC")
WHITE = (1.0, 1.0, 1.0)

# ── regions: (id, min, max, tint): a clean partition of the bounds ───────────────────────────────────
REGIONS = [
    ("the_landing",    (-500, 700),    (500, 1300),   (1.00, 0.94, 0.78)),
    ("the_heart",      (-500, -700),   (500, 700),    (1.00, 0.90, 0.92)),
    ("the_tines",      (-500, -1300),  (500, -700),   (0.86, 0.82, 1.00)),
    ("the_pinefold",   (-1700, -1300), (-500, -400),  (0.74, 0.92, 0.84)),
    ("goldhanger",     (-1700, -400),  (-500, 700),   (1.00, 0.88, 0.70)),
    ("the_low_tarns",  (-1700, 700),   (-500, 1300),  (0.78, 0.94, 0.94)),
    ("the_brokeback",  (500, -1300),   (1700, -400),  (0.86, 0.86, 0.94)),
    ("cutwater",       (500, -400),    (1700, 700),   (0.76, 0.92, 1.00)),
    ("the_shardfield", (500, 700),     (1700, 1300),  (0.94, 0.86, 1.00)),
]

# ── the water: overlapping ponds make Cutwater; two small tarns in the south-west ───────────────────
WATER = list(hexc("#7FD3E0"))
PONDS = [
    {"center": [1080, 150], "radius": 260, "color": WATER},
    {"center": [880, 300], "radius": 170, "color": WATER},
    {"center": [1290, 30], "radius": 180, "color": WATER},
    {"center": [1170, 390], "radius": 150, "color": WATER},
    {"center": [-1250, 1000], "radius": 110, "color": WATER},
    {"center": [-900, 1110], "radius": 80, "color": WATER},
]

# ── THE UNFINISHED on the Turning Floor (the 'heartstone' block; see the docstring) ───────────────────
HEART = (0, -260)
FLOOR_R = 230
MARK_YOU = (-140, -155)        # south-west of the stone, the side you come up the path on
MARK_COMPANION = (150, -355)   # north-east, round the far side
SECRET_POS = (0, -205)         # just south of the stone's foot
HEARTSTONE = {
    "position": list(HEART),
    "marks": {"you": list(MARK_YOU), "companion": list(MARK_COMPANION)},
    "reach": 320,
    "tolerance": 16, "hold_s": 2.0,
    "floor_radius": FLOOR_R,
}

# ── paths: sand trails from the Landing out to every region, and a ring round the Turning Floor ──────
RING_N = 24


def ring_pt(k, r=FLOOR_R):
    a = math.radians(k * 360.0 / RING_N)
    return [round(HEART[0] + math.cos(a) * r), round(HEART[1] + math.sin(a) * r)]


RING_S = ring_pt(6)     # (0, -30): where the spine meets the rim
RING_E = ring_pt(0)
RING_N_PT = ring_pt(18)
RING_W = ring_pt(12)
PATHS = [
    ([0, 1080], [0, 820]),          # the spine, from the Landing up to the Turning Floor
    ([0, 820], [0, 600]),
    ([0, 600], [0, 250]),
    ([0, 250], RING_S),
    ([0, 600], [450, 520]),         # east to Cutwater's south shore
    ([450, 520], [720, 600]),
    ([720, 600], [1060, 610]),
    ([1060, 610], [1420, 560]),
    (RING_E, [500, -200]),          # from the rim east, round Cutwater's west shore
    ([500, -200], [690, -120]),
    ([500, -200], [800, -560]),     # up into the Brokeback
    ([800, -560], [1150, -850]),
    (RING_N_PT, [-40, -760]),       # north into the Tines
    ([-40, -760], [60, -1050]),
    (RING_W, [-600, -350]),         # west, then forking to the Pinefold and Goldhanger
    ([-600, -350], [-950, -700]),
    ([-950, -700], [-1150, -950]),
    ([-600, -350], [-900, 100]),
    ([-900, 100], [-1150, 260]),
    ([0, 820], [-450, 900]),        # south-west to the Low Tarns
    ([-450, 900], [-780, 980]),
    ([-780, 980], [-1060, 960]),
    ([0, 820], [450, 900]),         # south-east to the Shardfield
    ([450, 900], [850, 1000]),
    ([850, 1000], [1200, 950]),
]
PATHS += [(ring_pt(k), ring_pt(k + 1)) for k in range(RING_N)]

# ── landmarks: great faceted pines, seen (and walked behind) from afar ───────────────────────────────
LANDMARKS = [
    {"type": "great_tree", "position": [-1250, -760]},
    {"type": "great_tree", "position": [-700, 560]},
    {"type": "great_tree", "position": [1450, -200]},
]


def _seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
    return math.hypot(p[0] - (ax + dx * t), p[1] - (ay + dy * t))


def path_dist(p):
    return min(_seg_dist(p, a, b) for a, b in PATHS)


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


def cairn(id, pos, label, lore=None):
    return prop(id, "gw_cairn", pos, STONE, label, lore, solid=True, radius=7)


def bench(id, pos, label, lore=None):
    return prop(id, "gw_bench", pos, SAND, label, lore, solid=True, radius=10)


def sign(id, pos, label, lore=None):
    return prop(id, "gw_sign", pos, SAND, label, lore, solid=True, radius=6)


# ── hand-placed props: the story, told in pieces ─────────────────────────────────────────────────────
SPECIAL = [
    # the Landing
    sign("landing_sign", (110, 960), "a cut-stone sign",
         "GLINTWOLD, says the sign, cut into one clean face of stone. Underneath, smaller: \"Mind the light. It's still working.\""),
    bench("landing_bench", (-140, 900), "a bench looking north",
          "From this bench you can just see the Unfinished, far up the path, catching the light in pieces."),
    cairn("landing_cairn", (150, 1150), "a cairn of flat stones",
          "Flat stones stacked by someone who liked flat stones. Here, that's everyone."),
    cairn("story_cairn", (64, 420), "an old story-cairn",
          "Scratched on the top stone: \"Once the whole wold was one dull stone, lying in the dark. Then a light found it, and began, very slowly, to turn round it. Wherever it touched, a face was cut.\""),
    # the Heart: the Turning Floor and the Unfinished
    prop("heart_plinth", "gw_plinth", (-64, 14), QUARTZ, "a carved plinth",
         "Carved into the plinth in small, careful letters: \"It only looks whole from two places at once.\"", solid=True, radius=8),
    sign("heart_sign", (70, -540), "a sign at the floor's edge",
         "THE UNFINISHED. The cutting stopped one face short, and here it hangs, in pieces that won't sit still. They drift apart when nobody's looking, and a little when somebody is."),
    bench("heart_bench", (270, 30), "a bench facing the stone",
          "Folk sit here to watch the Unfinished turn its pieces in the light. It never quite closes. Not on its own."),
    # Cutwater
    bench("cutwater_bench", (740, 655), "a bench by the water",
          "The lake holds the sky in bands, like a stack of coloured glass. Every so often one face of it flashes white, and then a different one."),
    sign("cutwater_sign", (640, -60), "a sign by the shore",
         "CUTWATER. The water was cut too, they say, the same as everything. That's why the little waves come in dead straight."),
    # the Tines
    cairn("tines_cairn", (130, -900), "a cairn among the spires",
          "Up among the spires the air rings, very faintly, as the light turns. Folk came up here to listen, and left a stone each."),
    prop("tines_gem", "gw_gem", (-120, -1000), AQUA, "a gem cluster",
         "A cluster of gems no bigger than your fist. Each flat face is a glint. This one has more glints than anyone has ever bothered to count."),
    # the Pinefold
    sign("pinefold_sign", (-900, -720), "a sign under the pines",
         "THE PINEFOLD. Every pine here was cut in one go, top to toe, in the time it takes the light to cross a hand."),
    cairn("pinefold_cairn", (-1160, -700), "a cairn by the great pine",
          "The great pine was one of the first things the light cut, after the hills. It took longer than the rest. You can tell: it has more faces."),
    # Goldhanger
    bench("goldhanger_bench", (-1140, 330), "a bench under round trees",
          "The round trees here catch the light low and hold on to it. Gold on one side, rose on the other, and both change while you watch."),
    # the Brokeback
    sign("brokeback_sign", (1100, -880), "a sign between the hills",
         "THE BROKEBACK. Hills with their corners left on. Walk round behind one and the whole wold goes quiet for a step or two."),
    # the Shardfield
    cairn("shardfield_cairn", (1230, 1010), "a cairn in the shards",
          "Loose shards everywhere, the bits the light trimmed off. Nobody sweeps them up. They're good luck, and they catch the evening."),
    # the Low Tarns
    bench("tarns_bench", (-1080, 900), "a bench between the tarns",
          "Two small tarns, so still they keep whole faces of the sky. Lean over and you're cut into faces too, a little."),
    cairn("tarns_cairn", (-620, 1080), "a cairn of round-ish stones"),
    # landmarks: arches you walk through on the way north and east
    prop("tines_arch", "gw_arch", (-30, -800), STONE, "a low stone arch",
         "A stone arch cut from three blocks. Step through it and the light on your shoulders changes colour, just slightly.", solid=False),
    prop("brokeback_arch", "gw_arch", (810, -575), STONE, "a low stone arch", solid=False),
]

# Lamps along the paths: a lit faceted lantern every so often, set off to one side.
LAMPS = []
for i, (a, b) in enumerate([([0, 1080], [0, 250]), ([0, 600], [720, 600]), (RING_E, [800, -560]),
                            (RING_W, [-950, -700]), ([-600, -350], [-1150, 260]), ([0, 820], [-780, 980]),
                            ([0, 820], [850, 1000]), (RING_N_PT, [60, -1050])]):
    d = math.hypot(b[0] - a[0], b[1] - a[1])
    n = max(1, int(d // 260))
    nx, ny = -(b[1] - a[1]) / d, (b[0] - a[0]) / d
    for k in range(1, n + 1):
        t = (k - 0.5) / n
        side = 1 if (k + i) % 2 else -1
        LAMPS.append((a[0] + (b[0] - a[0]) * t + nx * 40 * side, a[1] + (b[1] - a[1]) * t + ny * 40 * side))
LAMP_PROPS = []
for i, (x, y) in enumerate(LAMPS):
    if math.hypot(x - HEART[0], y - HEART[1]) < FLOOR_R + 40 or math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 70:
        continue
    if path_dist((x, y)) < 26 or any(math.hypot(x - p["position"][0], y - p["position"][1]) < 40 for p in SPECIAL):
        continue
    LAMP_PROPS.append(prop("lamp_%d" % i, "gw_lamp", (x, y), GOLD, "a faceted lantern", solid=True, radius=5))
SPECIAL += LAMP_PROPS

# ── procedural scatter ──────────────────────────────────────────────────────────────────────────────
placed = [(p["position"][0], p["position"][1], 24) for p in SPECIAL]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 70))


def clear(x, y, r):
    if not (BOUNDS_MIN[0] + 140 <= x <= BOUNDS_MAX[0] - 140 and BOUNDS_MIN[1] + 140 <= y <= BOUNDS_MAX[1] - 140):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 220:
        return False
    # the Turning Floor stays completely clear, with a margin so its rim reads as a clearing
    if math.hypot(x - HEART[0], y - HEART[1]) < FLOOR_R + 70 + r:
        return False
    if any(math.hypot(x - pd["center"][0], y - pd["center"][1]) < pd["radius"] * 1.15 + r for pd in PONDS):
        return False
    if path_dist((x, y)) < 30 + r:
        return False
    return all(math.hypot(x - px, y - py) >= r + pr for px, py, pr in placed)


def scatter(region_id, n, r, tries=5000):
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


def props(region, n, type, colors, label, r=16, solid=None, radius=None):
    for i, (x, y) in enumerate(scatter(region, n, r)):
        PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), random.choice(colors), label, solid=solid, radius=radius))


# The hills go first: they're the biggest things and want the most room.
trees("the_brokeback", 14, "gw_hill", r=95)
trees("the_heart", 2, "gw_hill", r=95)
trees("goldhanger", 2, "gw_hill", r=95)
trees("the_shardfield", 2, "gw_hill", r=95)
# The Pinefold: dense pines, a few boulders.
trees("the_pinefold", 130, "tree", 24)
trees("the_pinefold", 6, "gw_boulder", 22)
props("the_pinefold", 10, "gw_gem", [AQUA, SPIRE], "a gem cluster", r=14)
# Goldhanger: round trees in gold and rose and teal.
trees("goldhanger", 80, "gw_round", 26)
trees("goldhanger", 10, "tree", 24)
props("goldhanger", 6, "gw_gem", [GOLD, ROSE], "a gem cluster", r=14)
# The Tines: a forest of crystal spires behind the Unfinished.
trees("the_tines", 70, "gw_spire", 24)
trees("the_tines", 6, "gw_boulder", 22)
props("the_tines", 12, "gw_gem", [SPIRE, AQUA], "a gem cluster", r=14)
props("the_tines", 8, "gw_shardbed", [SPIRE, AQUA], "a bed of loose shards", r=18)
# The Brokeback: between and behind the hills, a few pines and boulders.
trees("the_brokeback", 14, "tree", 24)
trees("the_brokeback", 10, "gw_boulder", 22)
props("the_brokeback", 6, "gw_cairn", [STONE], "a cairn", r=16, solid=True, radius=7)
# Cutwater's shores: kept open so the lake reads.
trees("cutwater", 16, "tree", 26)
trees("cutwater", 10, "gw_round", 26)
trees("cutwater", 6, "gw_spire", 24)
props("cutwater", 6, "gw_gem", [AQUA, TEAL], "a gem cluster", r=14)
# The Shardfield: loose shards and gem clusters, a few spires and boulders.
trees("the_shardfield", 14, "gw_spire", 24)
trees("the_shardfield", 12, "gw_boulder", 22)
props("the_shardfield", 40, "gw_shardbed", [SPIRE, QUARTZ, AQUA], "a bed of loose shards", r=18)
props("the_shardfield", 18, "gw_gem", [SPIRE, AQUA, QUARTZ, GOLD], "a gem cluster", r=14)
# The Heart: a light mix round the Turning Floor, never on it.
trees("the_heart", 14, "gw_round", 28)
trees("the_heart", 10, "tree", 26)
trees("the_heart", 4, "gw_spire", 26)
props("the_heart", 6, "gw_gem", [QUARTZ, GOLD], "a gem cluster", r=14)
# The Landing: a gentle welcome.
trees("the_landing", 14, "tree", 26)
trees("the_landing", 10, "gw_round", 26)
props("the_landing", 4, "gw_gem", [GOLD, ROSE], "a gem cluster", r=14)
# The Low Tarns: pines and round trees round the still water.
trees("the_low_tarns", 30, "tree", 24)
trees("the_low_tarns", 18, "gw_round", 26)
trees("the_low_tarns", 6, "gw_boulder", 22)

# ── native creatures: ambient pals, server-simulated, examinable (lore in data/pals.json) ────────────
CREATURES = []


def creatures(region, species, n, roam):
    for i, (x, y) in enumerate(scatter(region, n, 40)):
        CREATURES.append({"id": "%s_%s_%d" % (region, species, i), "home": [x, y], "roam_radius": roam,
                          "region": region, "species": species, "variant": random.randrange(3)})


creatures("the_landing", "cobblet", 3, 180)
creatures("the_heart", "cobblet", 2, 160)
creatures("the_heart", "foldwing", 2, 200)
creatures("the_tines", "foldwing", 4, 220)
creatures("the_pinefold", "glintbuck", 4, 220)
creatures("goldhanger", "glintbuck", 3, 220)
creatures("goldhanger", "foldwing", 3, 200)
creatures("the_low_tarns", "glintbuck", 3, 200)
creatures("the_low_tarns", "cobblet", 2, 160)
creatures("the_brokeback", "glintbuck", 2, 240)
creatures("the_brokeback", "cobblet", 4, 200)
creatures("cutwater", "foldwing", 4, 240)
creatures("the_shardfield", "cobblet", 4, 200)
creatures("the_shardfield", "foldwing", 2, 200)

ALL_PROPS = SPECIAL + PROPS

# ── the world's own ART OVERRIDE: a small fallback, with the two fragments deep-merged over it ───────
HERE = os.path.dirname(os.path.abspath(__file__))
LOWPOLY = os.path.join(HERE, "..", "pokepals", "tools", "lowpoly")
PROP_TYPES = ["gw_gem", "gw_lamp", "gw_bench", "gw_sign", "gw_cairn", "gw_plinth", "gw_arch", "gw_shardbed", "offcut"]
FALLBACK_ART = {
    "palette": {
        "ground_top": list(hexc("#A6DB93")), "ground_bottom": list(hexc("#7DC27E")),
        "foliage_dark": list(hexc("#235E58")), "foliage_mid": list(hexc("#3E9A78")), "foliage_light": list(hexc("#8BD49A")),
        "bark": list(hexc("#7A5A48")), "water": WATER, "rim": [1.0, 0.98, 0.92],
        "shadow": list(hexc("#3A4A6B")), "grass": list(hexc("#8FCF8A")), "water_rim": [0.95, 0.89, 0.70, 0.9],
    },
    "light": {"shadow_alpha": 0.18, "rim_strength": 0.2},
    "entities": {
        "props": {"extra_types": PROP_TYPES},
        "prop_lights": {
            "gw_lamp": {"radius": 26, "y": -26, "alpha": 0.22},
            "gw_gem": {"radius": 14, "y": -6, "alpha": 0.14},
        },
    },
}


def deep_merge(base, over):
    out = copy.deepcopy(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


ART = FALLBACK_ART
MERGED = []
for name in ("glintwold_art.json", "glintwold_look.json"):
    path = os.path.join(LOWPOLY, name)
    if os.path.exists(path):
        frag = json.load(open(path))
        frag = {k: v for k, v in frag.items() if not k.startswith("_")}
        ART = deep_merge(ART, frag)
        MERGED.append(name)

ATMOSPHERE = {
    "day_tint": [1.0, 0.98, 0.94],
    "vignette": {"strength": 0.22, "color": list(hexc("#3A4A6B"))},
    "wind": {"strength": 0.9, "speed": 0.5},
    "pollen": {"amount": 40, "color": [1.0, 0.95, 0.78]},
    "region_tint_alpha": 0.06,
    "grass": {"max": 0},
}

HEADER = ("GLINTWOLD - the faceted world. A walk-and-wonder world that looks like a low-poly scene seen from above: "
          "everything is flat triangles, each a single clean colour by how it faces a light that is still slowly turning. "
          "It was CUT, not grown. Nine regions: the Landing (where you arrive), the Heart (the Turning Floor and the "
          "Unfinished), the Tines, the Pinefold, Goldhanger, the Low Tarns, the Brokeback, Cutwater (the lake) and the "
          "Shardfield. Its 'art' block is pokepals/tools/lowpoly/glintwold_art.json and glintwold_look.json deep-merged "
          "over a small fallback (ground.render 'facet', actor_look.facet). Tree kinds: tree, great_tree, gw_round, "
          "gw_spire, gw_hill, gw_boulder. The 'heartstone' block places the Unfinished, its two marks and the Turning "
          "Floor; the secret (reveal type 'facets') is the offcut. Generated by tools/gen_glintwold_world.py - edit that "
          "and re-run, don't hand-tune positions.")

SECRET_COMMENT = ("This world's one SECRET (issue #160). reveal.type 'facets': the Unfinished (the 'heartstone' block) hangs in "
                  "pieces; half answer to where the player stands, half to where the companion stands, and each half slides "
                  "home only when its viewer stands on its own mark ('heartstone.marks', within 'tolerance'). Both home and "
                  "held 'hold_s': the stone closes and the offcut falls at 'position'. Any actor on a mark counts, so two "
                  "friends can close it too. It all happens on the players' screens, so the server honours a claim only "
                  "here, within 'radius' of 'position'.")
SECRET = {
    "id": "offcut",
    "position": list(SECRET_POS),
    "radius": 70.0,
    "prop": {"type": "offcut", "color": list(QUARTZ), "label": "the offcut", "tags": ["small", "bright", "old", "odd"]},
    "lore": "A chip of stone no bigger than your thumb, with one face cut perfectly flat. It's the last face, the one that had to come away so the rest could close. It catches the light from every side at once.",
    "reveal": {
        "type": "facets",
        "lines": {
            "notice": "Your companion stops and looks across the Turning Floor, at one particular spot, as if it can see the stone from there.",
            "stand": "Your companion stands where you showed it, and looks up at the stone.",
            "go_look": "Your companion trots round the Turning Floor, looking up at the stone, and settles somewhere on the far side.",
            "closing": "The pieces slide together. Hold still.",
        },
        "reveal_line": "The pieces close with a flash, and for a moment the Unfinished is whole. Light runs over every face. Something small and bright drops at its foot.",
    },
    "found_line": "The stone was always one face short. Now you have the face, and it looks whole from wherever it likes.",
    "home_line": "Something has changed at home.",
    "qualities": ["glowing", "crafted", "old"],
    "keepsake": {
        "id": "offcut_kept", "type": "kept_offcut", "color": list(QUARTZ), "label": "the offcut, on a little stand",
        "line": "A small faceted chip that catches the light. Your companion walks round it slowly, as if it might close up if seen from the right place.",
        "temperament": {"curiosity": 0.8, "energy": 0.5, "clinginess": 0.45},
    },
}


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
path_objs = [{"from": list(a), "to": list(b), "color": list(SAND)} for a, b in PATHS]

out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "glintwold",')
out.append('\t"intro": %s,' % json.dumps("Everything here was cut, not grown, and the light that cut it is still turning. Watch the faces change. In the middle, something was left unfinished."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"music": { "track": "res://assets/music/glintwold.ogg", "volume_db": -22 },')  # tools/music/scores/glintwold.score
out.append('\t"border": { "ring": true, "spacing": 120, "inset": 24, "jitter": 34, "rows": 2, "row_gap": 60 },')
out.append('\t"collision": { "tree_radius": 8, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": %s,' % json.dumps(list(hexc("#8FCF8A"))))
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [\n%s\n\t],' % block(PONDS))
out.append('\t"paths": [\n%s\n\t],' % block(path_objs))
out.append('\t"landmarks": [\n%s\n\t],' % block(LANDMARKS))
out.append('\t"trees": [\n%s\n\t],' % block(TREES))
out.append('\t"props": [\n%s\n\t],' % block(ALL_PROPS))
out.append('\t"heartstone": %s,' % json.dumps(HEARTSTONE, separators=(", ", ": ")))
out.append('\t"_secret_comment": %s,' % json.dumps(SECRET_COMMENT))
out.append('\t"secret": %s,' % json.dumps(SECRET, indent="\t", ensure_ascii=False).replace("\n", "\n\t"))
out.append('\t"ambient_pals": [\n%s\n\t],' % block(CREATURES))
# The way home: a small portal just behind where you arrive. Like every way home it sets you down at the
# Vale's Gateway (its id is WorldRouter.HUB_GATEWAY_ID on the client).
out.append('\t"portals": [\n%s\n\t]' % block(PORTALS))
out.append("}")
text = "\n".join(out) + "\n"

# ── validate ─────────────────────────────────────────────────────────────────────────────────────────
d = json.loads(text)
ids = [p["id"] for p in d["props"]] + [c["id"] for c in d["ambient_pals"]]
assert len(ids) == len(set(ids)), "duplicate ids"
for p in d["props"]:
    assert bool(p.get("interactive")) == bool(p.get("lore")), "interactive iff lore: %s" % p["id"]
    x, y = p["position"]
    assert BOUNDS_MIN[0] < x < BOUNDS_MAX[0] and BOUNDS_MIN[1] < y < BOUNDS_MAX[1], p["id"]
    # nothing solid on a path (arches are walked through), the spawn, the portal or the Turning Floor
    solid = p.get("solid", False)
    if solid:
        assert path_dist(p["position"]) >= 20, "a solid prop stands on a path: %s" % p["id"]
    assert math.hypot(x - HEART[0], y - HEART[1]) > FLOOR_R + 20, "a prop stands on the Turning Floor: %s" % p["id"]
    assert math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) > 60 and math.hypot(x - PORTALS[0]["position"][0], y - PORTALS[0]["position"][1]) > 60, p["id"]
for t in d["trees"]:
    assert math.hypot(t[0] - HEART[0], t[1] - HEART[1]) > FLOOR_R + 60, "a tree stands on the Turning Floor"
    assert path_dist(t) > 30, "a tree stands on a path"
for lm in d["landmarks"]:
    assert path_dist(lm["position"]) > 60 and math.hypot(lm["position"][0] - HEART[0], lm["position"][1] - HEART[1]) > FLOOR_R + 80
for name, m in HEARTSTONE["marks"].items():
    r = math.hypot(m[0] - HEART[0], m[1] - HEART[1])
    assert 150 <= r <= 190 and r < FLOOR_R - 30, "mark %s is %d from the stone" % (name, r)
mu, mc = MARK_YOU, MARK_COMPANION
cosang = ((mu[0] - HEART[0]) * (mc[0] - HEART[0]) + (mu[1] - HEART[1]) * (mc[1] - HEART[1])) / (
    math.hypot(mu[0] - HEART[0], mu[1] - HEART[1]) * math.hypot(mc[0] - HEART[0], mc[1] - HEART[1]))
assert cosang < -0.5, "the two marks are on different sides of the stone"
assert math.hypot(SECRET_POS[0] - HEART[0], SECRET_POS[1] - HEART[1]) < 80
for pd in PONDS:
    for s in (PLAYER_SPAWN, PORTALS[0]["position"], SECRET_POS, HEART):
        assert math.hypot(s[0] - pd["center"][0], s[1] - pd["center"][1]) > pd["radius"] + 60
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("props:", len(d["props"]), "| interactive:", sum(1 for p in d["props"] if p.get("interactive")),
      "| trees:", kinds, "| creatures:", len(d["ambient_pals"]), "| art fragments merged:", MERGED or "none (fallback only)")
ROOT = os.path.join(HERE, "..")
for path in ["server/priv/world_seeds/glintwold.json", "pokepals/tests/world_fixtures/glintwold.json"]:
    open(os.path.join(ROOT, path), "w").write(text)
print("wrote both files")
