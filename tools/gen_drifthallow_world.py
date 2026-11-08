#!/usr/bin/env python3
"""Generate DRIFTHALLOW, the snowfield at blue hour, as a world spec (the pilot of the "template" worlds).

A modest (3200 x 2400), walk-and-wonder world: deep untouched snow under a cold blue sky, frozen
birches and snow-laden pines, a frozen lake, a few cairns. No goal, no puzzle. Every step you and your
companion take leaves a print in the snow that slowly fills back in (GlowTrail, "snow" style).

Its one SECRET (docs/home-world-and-secrets-design.md, "Drifthallow (pilot)"): a snow-hare's den
holding a frost-flower that never melts. The hare's tracks are invisible to you. Only your companion
can read them, and only wearing a FOX: near the scent spot a fox puts its nose down and LEADS you
along the trail (the `reveal` block below: reveal type "tracks"), leaving bright paw-prints for you to
follow and waiting if you fall behind. In any other shape it just plays in the snow. At the den the
frost-flower rises; examining it claims the secret as usual. All the numbers (radii, waits, print
fade) live in this file's data, not in code.

Hand-authored: regions, ponds, the trail (coarse waypoints; the generator adds the hare's meander),
every lore line, the world's art override, the secret. Procedural (seeded, so re-running reproduces it):
the scatter of trees and props, kept clear of the trail, the ponds and the landing.

Art assets come from pokepals/tools/gen_drifthallow.py. Writes the server seed and the client test
fixture. Run from the repo root:  python3 tools/gen_drifthallow_world.py
"""
import json
import math
import random

random.seed(0xD41F7)

BOUNDS_MIN = (-1600, -1200)
BOUNDS_MAX = (1600, 1200)
PLAYER_SPAWN = [0, 900]
COMPANION_SPAWN = [-30, 930]
PORTALS = [
    {"id": "drifthallow_way_home", "type": "portal", "position": [-72, 900], "color": [0.66, 0.80, 1.0], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

# ── regions: (id, min, max, tint): a clean partition of the bounds ───────────────────────────────────
REGIONS = [
    ("hush_landing",   (-500, 640),   (500, 1200),   (0.72, 0.80, 1.00)),
    ("south_drifts",   (500, 640),    (1600, 1200),  (0.80, 0.86, 1.00)),
    ("pine_hollow",    (-1600, -100), (-500, 1200),  (0.55, 0.78, 0.85)),
    ("glasswater",     (-500, -250),  (350, 640),    (0.62, 0.84, 1.00)),
    ("whitebole_wood", (350, -350),   (1600, 640),   (0.86, 0.88, 1.00)),
    ("rimestone_rise", (350, -1200),  (1600, -350),  (0.70, 0.74, 0.96)),
    ("hares_reach",    (-1600, -1200), (-500, -100), (0.76, 0.84, 1.00)),
    ("north_fields",   (-500, -1200), (350, -250),   (0.80, 0.84, 1.00)),
]

# ── the frozen water: overlapping ponds make Glasswater; two small ones elsewhere ───────────────────
ICE = [0.67, 0.79, 0.90]
PONDS = [
    {"center": [-100, 200], "radius": 220, "color": ICE},
    {"center": [-260, 120], "radius": 150, "color": ICE},
    {"center": [80, 270], "radius": 130, "color": ICE},
    {"center": [-100, -880], "radius": 110, "color": ICE},
    {"center": [950, -800], "radius": 90, "color": ICE},
]

LANDMARKS = [
    {"type": "great_tree", "position": [-1250, 400]},
    {"type": "great_tree", "position": [1180, 120]},
    {"type": "great_tree", "position": [-300, -1000]},
]

# ── THE HARE'S TRAIL ─────────────────────────────────────────────────────────────────────────────────
# START is the scent spot (a hare_hollow prop, examinable). The coarse waypoints wind north of
# Glasswater to the den in Hare's Reach. The generator subdivides each leg and bends it a little, the
# way a hare's line wanders; the last point is the den. The hare's tracks are NOT drawn by the world:
# they only exist as the paw-prints a fox lays while leading you.
START = (560, 330)
COARSE = [(470, 100), (420, -150), (300, -380), (80, -520), (-170, -580), (-420, -520), (-600, -470)]
DEN = (-720, -420)
FLOWER = (-712, -396)


def _meander(points, step=150.0, wobble=34.0):
    out = []
    for a, b in zip(points[:-1], points[1:]):
        d = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, round(d / step))
        nx, ny = -(b[1] - a[1]) / d, (b[0] - a[0]) / d
        for i in range(1, n):
            t = i / n
            w = random.uniform(-wobble, wobble)
            out.append((a[0] + (b[0] - a[0]) * t + nx * w, a[1] + (b[1] - a[1]) * t + ny * w))
        out.append(b)
    return out


TRAIL = [(round(x), round(y)) for x, y in _meander([START] + COARSE + [DEN])]
TRAIL_LINE = [START] + TRAIL


def _seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
    return math.hypot(p[0] - (ax + dx * t), p[1] - (ay + dy * t))


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

# ── hand-placed props: the landing, the scent spot, the den, a few things to look at ────────────────
SPECIAL = [
    prop("landing_cairn", "snow_cairn", (112, 930), WHITE, "a little cairn",
         "Someone stacked these stones to say: you can stop here. The snow around them has never been walked on.", solid=True, radius=7),
    prop("landing_drift", "snow_drift", (-150, 960), WHITE, "a soft drift",
         "Snow so deep and quiet you could lie down in it. Every footstep you leave will fill back in, given a while."),
    # the scent spot, and the den it leads to
    prop("hare_scent", "hare_hollow", START, WHITE, "a hollow in the snow",
         "A small hollow in the snow, the shape of something that lay here very still. The cold carries a smell your eyes can't follow. A fox's nose might."),
    prop("hare_den", "hare_den", DEN, WHITE, "a snow-drift with a doorway",
         "A round dark doorway under the drift, no wider than a loaf. It's empty and very tidy. Whoever lived here is out in the snow somewhere, and was never in a hurry."),
    # things to look at
    prop("glass_rock", "snow_rock", (-380, 420), WHITE, "a rock in a white hat",
         "A boulder wearing its snow like a hat pulled low. The ice on the lake beside it is too thick to hear anything under. You listen anyway.", solid=True, radius=8),
    prop("pine_stump", "frozen_stump", (-1000, 300), WHITE, "a stump with a roof of snow",
         "A stump with a little roof of snow on it. Somebody small might live under it. Somebody small is probably watching you check."),
    prop("birch_cairn", "snow_cairn", (900, 160), WHITE, "a tall cairn",
         "A taller cairn, and an older one. The top stone has a perfect round of bare rock where something warm once sat.", solid=True, radius=7),
    prop("rime_spikes", "ice_spikes", (800, -700), WHITE, "frozen drips",
         "Frozen drips, each one a note held very long. In the wind they chime, if you stand still and let them.", solid=True, radius=6),
    prop("field_rock", "snow_rock", (-100, -420), WHITE, "a lone rock",
         "A lone rock in the middle of all that white. Every direction you look from here looks exactly as good.", solid=True, radius=8),
    prop("south_cairn", "snow_cairn", (900, 920), WHITE, "a small cairn",
         "Three stones and a lot of snow. Whoever built it did a careful, unhurried job.", solid=True, radius=7),
]

placed = [(p["position"][0], p["position"][1], 24) for p in SPECIAL]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 70))


def clear(x, y, r):
    if not (BOUNDS_MIN[0] + 140 <= x <= BOUNDS_MAX[0] - 140 and BOUNDS_MIN[1] + 140 <= y <= BOUNDS_MAX[1] - 140):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 200:
        return False
    if any(math.hypot(x - pd["center"][0], y - pd["center"][1]) < pd["radius"] * 1.2 + r for pd in PONDS):
        return False
    # keep the hare's whole corridor open (the fox leads you through here), and a clearing at each end
    if any(_seg_dist((x, y), a, b) < 60 + r for a, b in zip(TRAIL_LINE[:-1], TRAIL_LINE[1:])):
        return False
    if math.hypot(x - DEN[0], y - DEN[1]) < 90 + r or math.hypot(x - START[0], y - START[1]) < 90 + r:
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


# Pine Hollow: dark, close pines.      Whitebole Wood: a stand of frozen birches (the scent spot's edge).
trees("pine_hollow", 95, "pine", 24)
trees("pine_hollow", 10, "oak", 30)
props("pine_hollow", 22, "snow_drift", "a drift")
props("pine_hollow", 8, "frozen_stump", "a snowy stump")
trees("whitebole_wood", 110, "birch", 22)
trees("whitebole_wood", 18, "pine", 24)
props("whitebole_wood", 18, "snow_drift", "a drift")
# Glasswater's shores, the landing, the open fields: few trees, lots of space
trees("glasswater", 14, "birch", 24)
trees("glasswater", 8, "pine", 24)
props("glasswater", 10, "snow_rock", "a rock under snow", r=18, solid=True, radius=8)
props("glasswater", 12, "snow_drift", "a drift")
trees("hush_landing", 18, "pine", 26)
trees("hush_landing", 12, "birch", 24)
props("hush_landing", 16, "snow_drift", "a drift")
trees("south_drifts", 26, "pine", 26)
trees("south_drifts", 12, "oak", 30)
props("south_drifts", 26, "snow_drift", "a drift")
props("south_drifts", 6, "snow_rock", "a rock under snow", r=18, solid=True, radius=8)
trees("north_fields", 12, "oak", 30)
trees("north_fields", 12, "birch", 24)
props("north_fields", 28, "snow_drift", "a drift")
props("north_fields", 6, "snow_rock", "a rock under snow", r=18, solid=True, radius=8)
trees("rimestone_rise", 30, "pine", 26)
props("rimestone_rise", 14, "ice_spikes", "frozen drips", r=18, solid=True, radius=6)
props("rimestone_rise", 14, "snow_rock", "a rock under snow", r=18, solid=True, radius=8)
props("rimestone_rise", 10, "snow_drift", "a drift")
trees("hares_reach", 40, "birch", 24)
trees("hares_reach", 20, "pine", 26)
props("hares_reach", 16, "snow_drift", "a drift")
props("hares_reach", 6, "frozen_stump", "a snowy stump")

ALL_PROPS = SPECIAL + PROPS

# ── the world's own ART OVERRIDE (deep-merged over data/art.json by ArtStyle.load_style) ─────────────
S = "res://assets/sprites/"


def ramp(*rows):
    return [list(r) for r in rows]


def tree_variants(names):
    return [{"trunk": S + "dh_%s_trunk.png" % n, "canopy": S + "dh_%s_canopy.png" % n} for n in names]


PINES = ["pine_a", "pine_b", "pine_c", "pine_d"]
BIRCHES = ["birch_a", "birch_b", "birch_c"]
OAKS = ["oak_a", "oak_b"]
ART = {
    # blue hour: snow in lilac-blue shade, the last of the sky on its highlights
    "palette": {
        "ground_top": [0.66, 0.74, 0.86], "ground_bottom": [0.55, 0.63, 0.78],
        "foliage_dark": [0.16, 0.30, 0.34], "foliage_mid": [0.50, 0.62, 0.72], "foliage_light": [0.90, 0.95, 1.0],
        "bark": [0.34, 0.32, 0.40], "water": [0.67, 0.79, 0.90], "rim": [0.9, 0.95, 1.0],
        "shadow": [0.10, 0.14, 0.34], "grass": [0.66, 0.74, 0.86], "water_rim": [0.93, 0.97, 1.0, 0.8],
    },
    "light": {"shadow_alpha": 0.22, "rim_strength": 0.2},
    "entities": {
        "portal": {"frame_tint": [0.78, 0.84, 1.0]},
        "ground": {
            "render": "pixel", "terrain": S + "dh_terrain.png", "tile": 128,
            "details": S + "dh_details.png", "details_index": "res://data/dh_details.json",
            "shade": 0.18,
            "ramps": {
                "grass": ramp((0.56, 0.65, 0.80), (0.63, 0.72, 0.85), (0.69, 0.78, 0.89), (0.86, 0.92, 0.98)),
                "lush": ramp((0.50, 0.58, 0.76), (0.57, 0.65, 0.82), (0.63, 0.71, 0.86), (0.78, 0.85, 0.95)),
                "meadow": ramp((0.62, 0.70, 0.84), (0.70, 0.78, 0.90), (0.77, 0.84, 0.94), (0.93, 0.96, 1.0)),
                "dirt": ramp((0.36, 0.38, 0.48), (0.46, 0.48, 0.58), (0.54, 0.56, 0.66), (0.70, 0.72, 0.82)),
                "sand": ramp((0.60, 0.70, 0.82), (0.68, 0.78, 0.88), (0.75, 0.85, 0.93), (0.90, 0.96, 1.0)),
                "path": ramp((0.50, 0.56, 0.70), (0.57, 0.63, 0.77), (0.63, 0.69, 0.82), (0.78, 0.83, 0.92)),
                "worn": ramp((0.54, 0.62, 0.78), (0.61, 0.69, 0.83), (0.67, 0.75, 0.87), (0.82, 0.88, 0.96)),
            },
            "accents": [[0.96, 0.98, 1.0]],
            "patches": {"lush": {"scale": 0.0032, "threshold": 0.50}, "meadow": {"scale": 0.005, "threshold": 0.60},
                        "dirt": {"scale": 0.006, "threshold": 1.6}},
            "clump": {"scale": 0.009, "dark": 0.34, "light": 0.66},
            "scatter": {
                "density": 0.55,
                "open": [
                    {"names": ["snowtuft_a", "snowtuft_b"], "weight": 22, "count": [1, 4], "sway": 0.25},
                    {"names": ["snowcrest"], "weight": 24, "count": [1, 3]},
                    {"names": ["rime", "iceshard"], "weight": 14, "count": [1, 3]},
                    {"names": ["snowpebbles"], "weight": 8, "count": [1, 2]},
                    {"names": ["snowstone"], "weight": 4},
                    {"names": ["snowtwig"], "weight": 5},
                ],
                "under_trees": {"names": ["snowtwig", "pinecone"], "ring": ["rime"]},
                "path_edge": [],
                "reeds": ["frostreed"],
                "lilies": [],
            },
        },
        "understory": {"render": "sprite", "prefix": S + "dh_understory_", "types": ["bush_a", "bush_b", "stump"], "density": 0.5},
        # no butterflies or fireflies in the cold; a little snow shaken off the branches now and then
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 0}, "clouds": {"count": 3, "alpha": 0.06, "speed": 5},
                         "leaves": {"rate": 0.8, "colors": [[0.95, 0.97, 1.0], [0.85, 0.92, 1.0]]}},
        "tree": {"render": "sprite", "sway": 0.25, "variants": tree_variants(PINES * 2 + BIRCHES * 2 + OAKS)},
        "pine": {"render": "sprite", "sway": 0.2, "variants": tree_variants(PINES)},
        "birch": {"render": "sprite", "sway": 0.35, "variants": tree_variants(BIRCHES)},
        "oak": {"render": "sprite", "sway": 0.2, "variants": tree_variants(OAKS)},
        "great_tree": {"render": "sprite", "sway": 0.15, "variants": tree_variants(["great_oak", "great_oak2"])},
        "water": {"render": "sprite", "tile": S + "dh_ice.png", "world_tile": 64},
        "pool": {"render": "sprite", "tile": S + "dh_ice.png", "world_tile": 64},
        "river": {"render": "sprite", "tile": S + "dh_ice.png", "world_tile": 64},
        "props": {"extra_types": ["snow_drift", "snow_rock", "frozen_stump", "ice_spikes", "snow_cairn", "hare_hollow", "hare_den"]},
    },
    # blue hour, held and slowly breathing between a blue and a violet-blue
    "daycycle": {"enabled": True, "period_sec": 420, "loop": True, "stops": [
        {"t": 0.0, "tint": [0.90, 0.94, 1.06], "vignette": [0.05, 0.07, 0.20], "vstrength": 0.42},
        {"t": 1.0, "tint": [0.86, 0.88, 1.06], "vignette": [0.10, 0.07, 0.24], "vstrength": 0.5},
    ]},
}

ATMOSPHERE = {
    "day_tint": [0.90, 0.94, 1.06],
    "vignette": {"strength": 0.42, "color": [0.05, 0.07, 0.20]},
    "wind": {"strength": 0.8, "speed": 0.5},
    "pollen": {"amount": 40, "color": [0.95, 0.97, 1.0]},
    "region_tint_alpha": 0.05,
    "grass": {"max": 0},
    "sparkles": {"count": 650, "colors": [[0.96, 0.98, 1.0], [0.78, 0.90, 1.0], [1.0, 0.93, 0.85]]},
    # Everyone's footsteps are soft dents in the snow that fill back in (style "snow"); `scent` is the
    # bright paw-print a fox lays along the hare's trail, which lingers far longer.
    "footprints": {"style": "snow", "color": [0.30, 0.38, 0.58], "rim": [0.97, 0.99, 1.0], "life": 28, "spacing": 13, "max_prints": 700,
                   "scent": {"color": [0.62, 0.92, 1.0], "life": 90, "size": 2.2}},
}

HEADER = ("DRIFTHALLOW - a snowfield at blue hour. A walk-and-wonder world (no goal, no puzzle): deep untouched snow, "
          "frozen birches and snow-laden pines, a frozen lake, a cold quiet sky. Eight regions: Hush Landing (where you "
          "arrive), South Drifts, Pine Hollow, Glasswater (the frozen lake), Whitebole Wood, Rimestone Rise, North "
          "Fields and Hare's Reach. It RE-SKINS ITSELF through its 'art' block (deep-merged over data/art.json): its own "
          "snow terrain + litter atlas, frozen trees (tree entries [x, y, kind]: pine/birch/oak), ice water, a blue-hour "
          "day cycle. Every step (yours, your companion's, a friend's) leaves a print that fills back in "
          "(atmosphere.footprints, style 'snow'). Its secret is a snow-hare's den: see the 'secret' block (reveal type "
          "'tracks'). Generated by tools/gen_drifthallow_world.py (art: pokepals/tools/gen_drifthallow.py) - edit that "
          "and re-run, don't hand-tune positions.")

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Drifthallow (pilot)'). reveal.type 'tracks': "
                  "when the companion wears reveal.species (a fox) near the scent spot 'start', it leads the player along "
                  "'trail' (waypoints, the last is the den) laying bright paw-prints, waiting when the player falls behind "
                  "(TrailGuide / TracksDirector); at the end the prop rises. The server honours a claim only here, within "
                  "'radius' of 'position'.")
SECRET = {
    "id": "frost_flower",
    "position": list(FLOWER),
    "radius": 120.0,
    "prop": {"type": "frost_flower", "color": [0.62, 0.88, 1.0], "label": "a frost-flower", "tags": ["cold", "small", "odd", "old"]},
    "lore": "A flower made of frost: six clear petals and a little blue light at its heart. It's bitterly cold, but it doesn't melt in your hand.",
    "reveal": {
        "type": "tracks",
        "species": "fox",
        "start": list(START),
        "trail": [list(p) for p in TRAIL],
        "scent_radius": 150.0, "player_radius": 260.0, "sniff_seconds": 1.4, "waypoint_reach": 26.0,
        "wait_distance": 190.0, "resume_distance": 110.0, "give_up_distance": 720.0,
        "print_spacing": 20.0, "waypoint_patience": 14.0, "drift_hold": 30.0,
        "play_radius": 70.0, "play_interval": 16.0,
        "notice_range_low": 260.0, "notice_range_high": 640.0,
        "notice_cooldown_low": 16.0, "notice_cooldown_high": 6.0, "notice_hold": 2.5,
        "lines": {
            "notice": "Your companion stops short and stares off across the snow, nose working. Something small passed this way.",
            "play": "Your companion tumbles about in the snow, nose busy, as if it can almost catch something. A sharper nose might.",
            "sniff": "Your fox's nose goes down. There's something here, and it has decided to follow it.",
            "set_off": "It sets off across the snow, looking back now and then to check you're coming.",
            "wait": "It waits for you, nose lifted, until you catch up.",
            "lost": "The scent slips away. Wherever it stopped, a fox could pick it up again.",
        },
        "reveal_line": "The tracks end at a small round doorway under the drift. Something has grown in its mouth: a flower made of frost.",
    },
    "found_line": "The hare is long gone. It left its flower where only a fox would ever find it, and it has never melted.",
    "home_line": "Something has changed at home.",
    "qualities": ["quiet", "old", "watery"],
    "keepsake": {
        "id": "frost_posy", "type": "kept_frost_flower", "color": [0.62, 0.88, 1.0], "label": "a frost-flower in a dish of snow",
        "line": "A flower that never melts. Your companion sniffs it now and then, as if remembering something small and very fast.",
        "temperament": {"curiosity": 0.8, "energy": 0.45, "clinginess": 0.45},
    },
}


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "drifthallow",')
out.append('\t"intro": %s,' % json.dumps("Snow, and the blue light before the dark. Nothing here needs doing. Walk, and look back at where you've been."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": true, "spacing": 120, "inset": 24, "jitter": 34, "rows": 2, "row_gap": 60 },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.62, 0.70, 0.84],')
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
assert math.hypot(*(a - b for a, b in zip(DEN, TRAIL[-1]))) < 1
for a, b in zip(TRAIL_LINE[:-1], TRAIL_LINE[1:]):
    assert math.hypot(b[0] - a[0], b[1] - a[1]) < 230, "trail leg too long for a nose to hold"
    for pd in PONDS:
        assert _seg_dist(pd["center"], a, b) > pd["radius"] + 40, "the trail runs through a pond"
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
tl = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(TRAIL_LINE[:-1], TRAIL_LINE[1:]))
print("props:", len(d["props"]), "| trees:", kinds, "| trail: %d waypoints, %d px" % (len(TRAIL), tl))
for path in ["server/priv/world_seeds/drifthallow.json", "pokepals/tests/world_fixtures/drifthallow.json"]:
    open(path, "w").write(text)
print("wrote both files")
