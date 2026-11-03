#!/usr/bin/env python3
"""Generate BOBBLEDOWN, the round world, as a world spec.

The one world that breaks from the pixel art. Bobbledown was BLOWN, not built: at the bottom of the
Fizzwell, a lagoon that never stops fizzing, sleeps the Old Burbler, round as a moon and soft as a
cloud. Every breath it takes in its sleep rises as a bubble, and every bubble that ever rose became
something: a gumdrop hill, a puff-tree, a bobbling. That's why nothing here has a corner. You do,
a little; the bobblings find this fascinating.

They say the Burbler's very first breath never popped, and that it is still down there, kept safe
for someone who sings the Burbler its lullaby. The lullaby is seven notes, and each is kept in a
CHIME-BUBBLE somewhere in Bobbledown. Ring all seven in one visit and the first breath rises from the
Fizzwell to its southern shore. That is this world's SECRET (`touch_all`, see SecretDirector /
Server.SecretReveal): a wander through every corner of the world, told in lines rather than counted.

Eight regions ring the Fizzwell: Popping Green (where you arrive), the High Hush, Gumdrop Hills, the
Puffwood, Jellybottom, Lollipop Grove, the Bubblefield and the Pillow Dunes, linked by candy-ribbon
paths. Its 'art' block re-skins it (deep-merged over data/art.json): a SOFT ground instead of the
pixel one (pastel dapples, rounded ribbon paths, fizzing ponds), smooth @2x trees, growths, props
and creatures (pokepals/tools/gen_bobbledown.py), air full of drifting bubbles, and a pastel
actor_look with bubble motes for its visitors.

Hand-authored: the regions, the paths, the Fizzwell, the landmarks, every line of lore, the seven
chimes. Procedural (seeded): the scatter of growths, props and creatures inside each region. Writes the
server seed and the client test fixture. Run from the repo root:  python3 tools/gen_bobbledown_world.py
"""
import json
import math
import random

random.seed(0xB0BB1E)

BOUNDS_MIN = (-1900, -1500)
BOUNDS_MAX = (1900, 1500)
PLAYER_SPAWN = [0, 1060]
COMPANION_SPAWN = [-34, 1090]

STRAWBERRY = (1.00, 0.62, 0.72)
MINT = (0.60, 0.92, 0.80)
LEMON = (1.00, 0.90, 0.56)
LILAC = (0.78, 0.68, 1.00)
PEACH = (1.00, 0.76, 0.62)
SKY = (0.62, 0.84, 1.00)
BUBBLEGUM = (1.00, 0.72, 0.90)
CREAM = (1.00, 0.96, 0.90)

# ── regions: (id, min, max, tint) ──────────────────────────────────────────────────────────────────
REGIONS = [
    ("popping_green",   (-560, 560),    (560, 1450),   (0.80, 1.00, 0.86)),
    ("the_fizzwell",    (-640, -820),   (640, 80),     (0.70, 0.88, 1.00)),
    ("the_high_hush",   (-640, -1450),  (640, -820),   (0.86, 0.80, 1.00)),
    ("gumdrop_hills",   (-1850, -1450), (-640, -300),  (1.00, 0.74, 0.80)),
    ("the_puffwood",    (-1850, -300),  (-560, 700),   (1.00, 0.84, 0.96)),
    ("jellybottom",     (-1850, 700),   (-560, 1450),  (0.70, 0.94, 1.00)),
    ("lollipop_grove",  (640, -1450),   (1850, -300),  (1.00, 0.92, 0.70)),
    ("the_bubblefield", (560, -300),    (1850, 700),   (0.84, 0.92, 1.00)),
    ("pillow_dunes",    (560, 700),     (1850, 1450),  (1.00, 0.88, 0.80)),
]

# ── the Fizzwell: overlapping ponds make one round lagoon, plus Jellybottom's pools ────────────────
WATER = [0.62, 0.84, 0.98]
PONDS = [
    {"center": [0, -380], "radius": 250, "color": WATER},
    {"center": [-230, -300], "radius": 150, "color": WATER},
    {"center": [240, -320], "radius": 160, "color": WATER},
    {"center": [-60, -590], "radius": 150, "color": WATER},
    {"center": [140, -560], "radius": 130, "color": WATER},
    # Jellybottom's round pools
    {"center": [-1300, 1050], "radius": 120, "color": WATER},
    {"center": [-1020, 1260], "radius": 80, "color": WATER},
    {"center": [-1600, 860], "radius": 70, "color": WATER},
    {"center": [-1560, 1300], "radius": 60, "color": WATER},
]

# ── candy-ribbon paths from the Green out to every region ──────────────────────────────────────────
RIBBON = [1.00, 0.95, 0.86]
PATHS = [
    ([0, 1150], [0, 560]),             # the Green -> the Fizzwell's south shore
    ([0, 560], [-470, 40]),            # round the west shore
    ([0, 560], [480, 30]),             # round the east shore
    ([-470, 40], [-1250, 100]),        # into the Puffwood
    ([-1250, 100], [-1250, -880]),     # up into Gumdrop Hills
    ([480, 30], [1250, 150]),          # into the Bubblefield
    ([1250, 150], [1250, -880]),       # up into Lollipop Grove
    ([0, 900], [-1150, 1000]),         # down to Jellybottom
    ([0, 900], [1200, 1050]),          # across to the Pillow Dunes
    ([-470, 40], [-420, -980]),        # round the west of the lagoon, up to the High Hush
    ([-420, -980], [0, -1150]),
]

# ── landmarks: great puffs, seen (and walked behind) from afar ──────────────────────────────────────
LANDMARKS = [
    {"type": "great_tree", "position": [-1300, -420]},
    {"type": "great_tree", "position": [-1500, 330]},
    {"type": "great_tree", "position": [1500, -300]},
    {"type": "great_tree", "position": [340, -1150]},
]


def prop(id, type, pos, color, label, lore=None, tags=None, flare=False, solid=None, radius=None):
    p = {"id": id, "type": type, "position": [round(pos[0]), round(pos[1])], "color": [round(c, 2) for c in color], "label": label}
    if tags:
        p["tags"] = tags
    if lore:
        p["interactive"] = True
        p["lore"] = lore
    if flare:
        p["flare"] = True
    if solid is not None:
        p["solid"] = solid
    if radius is not None:
        p["collision_radius"] = radius
    return p


SPECIAL = []

# Popping Green: where visitors pop in, a sign, a bench, cushions to sit on.
SPECIAL += [
    prop("green_sign", "sign_bubble", (110, 960), STRAWBERRY, "a round signboard",
         "WELCOME TO BOBBLEDOWN, says the sign, in very round letters. Underneath, smaller: \"Everything here was breathed, not built. Mind the bubbles. They're somebody's.\""),
    prop("green_bench", "candy_bench", (-140, 940), BUBBLEGUM, "a soft candy bench",
         "The bench gives a little when you lean on it, like a cushion, and then very slowly puffs itself back up."),
    prop("green_cushion", "cloud_cushion", (220, 1180), SKY, "a cloud cushion",
         "A scrap of cloud that's settled down for a rest. It's warm on top, like somebody was just sitting on it."),
    prop("green_lamp_w", "bubble_lamp", (-90, 820), BUBBLEGUM, "a bubble-lamp",
         "A lamp that's a bubble on a stick. The light inside it drifts about, as if it's looking for the way out and is in no hurry to find it."),
    prop("green_lamp_e", "bubble_lamp", (90, 820), MINT, "a bubble-lamp"),
]

# The Fizzwell's shores.
SPECIAL += [
    prop("fizz_stone", "marsh_stone", (-330, -70), CREAM, "a marshmallow stone", solid=True, radius=9,
         lore="The Fizzwell fizzes all the time, never stopping, never hurrying. Bobblings come here to listen. They say it sounds like snoring, if you listen long enough."),
    prop("fizz_bench", "candy_bench", (330, -60), SKY, "a bench facing the water",
         "From here you can watch the bubbles rise out of the Fizzwell and drift off over the world. Every one of them is going to be something, one day."),
    prop("fizz_spring_a", "fizz_spring", (-420, -520), SKY, "a fizzing spring",
         "A little spring, fizzing up from underneath. It tickles your fingers and smells faintly of lemons.", flare=True),
    prop("fizz_spring_b", "fizz_spring", (420, -540), MINT, "a fizzing spring",
         "The spring fizzes harder when you touch it, as if it's laughing.", flare=True),
]

# The High Hush: a quiet hill above the lagoon, where the story is written down.
SPECIAL += [
    prop("hush_sign", "sign_bubble", (-120, -1080), LILAC, "an old round sign",
         "\"Down at the bottom of the Fizzwell sleeps the Old Burbler, round as a moon and soft as a cloud. Every breath it takes in its sleep rises as a bubble, and every bubble that ever rose became something: a hill, a tree, a bobbling. That is why nothing here has a corner.\""),
    prop("hush_stone", "marsh_stone", (120, -1110), LILAC, "a listening stone", solid=True, radius=9,
         lore="Carved into the stone, very small: \"They say the Burbler's first breath never popped. They say it's kept safe down there, waiting for someone to sing the Burbler its lullaby. Seven notes, kept in seven chime-bubbles, each one resting by a landmark of Bobbledown.\""),
    prop("hush_bench", "candy_bench", (0, -940), LILAC, "a bench on the hush",
         "It's very quiet up here. You can hear the Fizzwell below, and every so often a pop, very small and very far away."),
]

# Gumdrop Hills, the Puffwood, Jellybottom, Lollipop Grove, the Bubblefield, the Pillow Dunes.
SPECIAL += [
    prop("hills_stone", "marsh_stone", (-1000, -1150), STRAWBERRY, "a sugared stone", solid=True, radius=9,
         lore="The gumdrops grow a little every time it rains. It rains sugar here, about once a year, and everyone goes outside with their mouths open."),
    prop("puff_bench", "candy_bench", (-1050, 300), BUBBLEGUM, "a bench in the Puffwood",
         "The puff-trees are softer than they look, and they look very soft. Some of the puffkins live inside them."),
    prop("jelly_stone", "marsh_stone", (-900, 1150), SKY, "a stone by the pools", solid=True, radius=9,
         lore="The pools in Jellybottom are just a little thicker than water. Drop a pebble in and it sinks slowly, wobbling, and the wobblers all turn to watch."),
    prop("lolli_sign", "sign_bubble", (1000, -700), LEMON, "a striped signpost",
         "LOLLIPOP GROVE, says the sign. Then: PLEASE DO NOT LICK THE TREES. Then, underneath in different handwriting: they don't mind really."),
    prop("field_stone", "marsh_stone", (1500, 500), SKY, "a bubble-watcher's stone", solid=True, radius=9,
         lore="The bubble-blooms here open into bubbles instead of petals. When one pops, another starts to grow in its place, slowly, like a held breath."),
    prop("dunes_cushion", "cloud_cushion", (1100, 1300), PEACH, "a sunken cloud cushion",
         "The dunes are made of something like marshmallow, sun-warm and soft. Walking on them leaves round footprints that puff back up behind you."),
]

# ── the seven CHIME-BUBBLES: one note of the Burbler's lullaby each (this world's secret) ─────────
CHIME_LORE = "A chime-bubble on its curly stand, a little note curled up inside it. It rings one round, warm note when you touch it."
# Each rests by its region's landmark (a great puff, or the region's sign or stone), well in from the
# edge of the world, so the hunt is a wander between the places you'd notice anyway.
CHIMES = [
    ("chime_green", (175, 935), BUBBLEGUM),          # by the welcome sign, where you arrive
    ("chime_hills", (-1215, -395), STRAWBERRY),      # under the great puff in Gumdrop Hills
    ("chime_puffwood", (-1410, 380), LILAC),         # under the Puffwood's great puff
    ("chime_jellybottom", (-960, 1100), SKY),        # by the stone above the pools
    ("chime_lollipop", (1075, -665), LEMON),         # beside the Lollipop Grove sign
    ("chime_bubblefield", (1585, -245), MINT),       # under the great puff at the Bubblefield's edge
    ("chime_dunes", (1180, 1265), PEACH),            # by the sunken cloud cushion in the dunes
]
for cid, pos, col in CHIMES:
    SPECIAL.append(prop(cid, "chime_bubble", pos, col, "a chime-bubble", CHIME_LORE, tags=["chime", "music", "round"], flare=True))

# ── procedural scatter ──────────────────────────────────────────────────────────────────────────────
placed = []
for p in SPECIAL:
    placed.append((p["position"][0], p["position"][1], 26))
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 64))


def _seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
    return math.hypot(p[0] - (ax + dx * t), p[1] - (ay + dy * t))


SECRET_POS = (40.0, -70.0)


def clear(x, y, r):
    if not (BOUNDS_MIN[0] + 140 <= x <= BOUNDS_MAX[0] - 140 and BOUNDS_MIN[1] + 140 <= y <= BOUNDS_MAX[1] - 140):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 220:
        return False
    if math.hypot(x - SECRET_POS[0], y - SECRET_POS[1]) < 90:
        return False
    if any(math.hypot(x - pd["center"][0], y - pd["center"][1]) < pd["radius"] * 1.2 + r for pd in PONDS):
        return False
    if any(_seg_dist((x, y), a, b) < 30 + r for a, b in PATHS):
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


def trees(region, n, kind=None, r=26):
    for x, y in scatter(region, n, r):
        TREES.append([x, y] if kind is None else [x, y, kind])


def props(region, n, type, colors, label, r=16, flare_lore=None):
    for i, (x, y) in enumerate(scatter(region, n, r)):
        if flare_lore:
            PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), random.choice(colors), label,
                              flare_lore[i % len(flare_lore)], flare=True))
        else:
            PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), random.choice(colors), label))


BLOOM_LORE = [
    "The bubble-bloom wobbles at your touch, and its bubble shines brighter for a moment. Everyone nearby sees it.",
    "It bobs, and a little shimmer runs round its bubble like a giggle.",
    "Touch it and it glows, round and bright, then settles down again.",
]
SPRING_LORE = ["The spring fizzes up at your touch, tickling, and a few bubbles drift off into the air."]

# Popping Green: a gentle welcome of a few of everything.
trees("popping_green", 18)
trees("popping_green", 6, "lolli")
trees("popping_green", 5, "bubble_stalk")
props("popping_green", 14, "bubble_bloom", [BUBBLEGUM, SKY, MINT], "a bubble-bloom", flare_lore=BLOOM_LORE)
props("popping_green", 14, "puff_bush", [MINT, BUBBLEGUM, LEMON], "a puff-bush")
props("popping_green", 10, "pebble_pops", [LILAC, PEACH, SKY], "some pebble-pops")
props("popping_green", 8, "jellybeans", [STRAWBERRY, LEMON, MINT, LILAC], "a heap of jellybeans")
# The Fizzwell's shore: bubble-stalks and springs, kept low so the lagoon stays open.
trees("the_fizzwell", 14, "bubble_stalk")
props("the_fizzwell", 10, "fizz_spring", [SKY, MINT], "a fizzing spring", flare_lore=SPRING_LORE)
props("the_fizzwell", 16, "bubble_bloom", [SKY, BUBBLEGUM], "a bubble-bloom", flare_lore=BLOOM_LORE)
props("the_fizzwell", 12, "pebble_pops", [SKY, LILAC], "some pebble-pops")
# The High Hush: sparse, still, lilac.
trees("the_high_hush", 22)
trees("the_high_hush", 8, "bubble_stalk")
props("the_high_hush", 18, "cloud_cushion", [LILAC, SKY, CREAM], "a cloud cushion")
props("the_high_hush", 10, "puff_bush", [LILAC, SKY], "a puff-bush")
# Gumdrop Hills: rolling gumdrops of every flavour.
trees("gumdrop_hills", 70, "gumdrop", r=34)
trees("gumdrop_hills", 14)
props("gumdrop_hills", 30, "jellybeans", [STRAWBERRY, LEMON, MINT, LILAC, PEACH], "a heap of jellybeans")
props("gumdrop_hills", 16, "pebble_pops", [STRAWBERRY, PEACH], "some pebble-pops")
# The Puffwood: thick with puff-trees, floored with puff-bushes and cushions.
trees("the_puffwood", 150, r=24)
props("the_puffwood", 50, "puff_bush", [BUBBLEGUM, LILAC, MINT], "a puff-bush")
props("the_puffwood", 20, "cloud_cushion", [BUBBLEGUM, CREAM], "a cloud cushion")
# Jellybottom: bubble-stalks round the pools, springs, jellybeans.
trees("jellybottom", 40, "bubble_stalk")
trees("jellybottom", 24)
props("jellybottom", 16, "fizz_spring", [SKY, MINT], "a fizzing spring", flare_lore=SPRING_LORE)
props("jellybottom", 24, "jellybeans", [SKY, MINT, LILAC], "a heap of jellybeans")
props("jellybottom", 20, "pebble_pops", [SKY, MINT], "some pebble-pops")
# Lollipop Grove: rows of lollipops among gumdrops.
trees("lollipop_grove", 80, "lolli", r=26)
trees("lollipop_grove", 16, "gumdrop", r=32)
props("lollipop_grove", 28, "jellybeans", [LEMON, PEACH, STRAWBERRY], "a heap of jellybeans")
props("lollipop_grove", 16, "puff_bush", [LEMON, PEACH], "a puff-bush")
# The Bubblefield: a meadow of bubble-blooms, every one touchable.
trees("the_bubblefield", 30, "bubble_stalk")
trees("the_bubblefield", 16)
props("the_bubblefield", 80, "bubble_bloom", [SKY, MINT, BUBBLEGUM, LILAC, LEMON], "a bubble-bloom", r=14, flare_lore=BLOOM_LORE)
# The Pillow Dunes: open, soft, peachy, a few great cushions.
trees("pillow_dunes", 20, "gumdrop", r=34)
trees("pillow_dunes", 10)
props("pillow_dunes", 40, "cloud_cushion", [PEACH, CREAM, BUBBLEGUM], "a cloud cushion", r=20)
props("pillow_dunes", 20, "pebble_pops", [PEACH, LEMON], "some pebble-pops")

# ── native creatures: ambient pals, server-simulated, examinable (lore in data/pals.json) ────────────
CREATURES = []


def creatures(region, species, n, roam):
    for i, (x, y) in enumerate(scatter(region, n, 40)):
        CREATURES.append({"id": "%s_%s_%d" % (region, species, i), "home": [x, y], "roam_radius": roam,
                          "region": region, "species": species, "variant": random.randrange(3)})


creatures("popping_green", "bobbling", 5, 200)
creatures("popping_green", "puffkin", 2, 160)
creatures("the_fizzwell", "bubblefin", 5, 220)
creatures("the_fizzwell", "wobbler", 2, 140)
creatures("the_high_hush", "puffkin", 4, 200)
creatures("gumdrop_hills", "bobbling", 6, 240)
creatures("gumdrop_hills", "rollypoll", 4, 200)
creatures("the_puffwood", "puffkin", 6, 200)
creatures("the_puffwood", "bobbling", 3, 180)
creatures("jellybottom", "wobbler", 7, 160)
creatures("jellybottom", "bubblefin", 3, 200)
creatures("lollipop_grove", "rollypoll", 5, 220)
creatures("lollipop_grove", "bobbling", 3, 200)
creatures("the_bubblefield", "bubblefin", 5, 260)
creatures("the_bubblefield", "wobbler", 3, 180)
creatures("pillow_dunes", "rollypoll", 4, 240)
creatures("pillow_dunes", "puffkin", 3, 220)

ALL_PROPS = SPECIAL + PROPS

# ── the world's own ART OVERRIDE ────────────────────────────────────────────────────────────────────
S = "res://assets/sprites/"
ART = {
    "palette": {
        "ground_top": [0.76, 0.94, 0.84],
        "ground_bottom": [0.94, 0.83, 0.95],
        "foliage_dark": [0.92, 0.62, 0.78],
        "foliage_mid": [1.00, 0.74, 0.86],
        "foliage_light": [1.00, 0.88, 0.94],
        "bark": [0.86, 0.62, 0.46],
        "water": WATER,
        "rim": [1.00, 1.00, 1.00],
        "shadow": [0.44, 0.32, 0.52],
        "grass": [0.70, 0.90, 0.76],
        "water_rim": [1.00, 0.97, 0.94, 0.95],
    },
    "light": {"shadow_alpha": 0.16, "rim_strength": 0.35},
    "entities": {
        # No pixels underfoot: the SOFT ground (WorldArt) -- a mint-to-lilac wash with sugared dapples,
        # rounded ribbon paths and fizzing ponds.
        "ground": {"render": "soft"},
        "understory": {"density": 0},
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 0}, "leaves": {"rate": 0},
                         "clouds": {"count": 4, "alpha": 0.05, "speed": 7.0},
                         "bubbles": {"count": 18, "colors": [list(BUBBLEGUM), list(SKY), list(MINT), list(LEMON), list(LILAC)]}},
        "tree": {"render": "sprite", "sway": 0.8, "variants": [
            {"trunk": S + "bd_puff_%s_trunk@2x.png" % v, "canopy": S + "bd_puff_%s_canopy@2x.png" % v}
            for v in ("strawberry", "mint", "lilac", "lemon")]},
        "great_tree": {"render": "sprite", "sway": 0.5, "variants": [
            {"trunk": S + "bd_great_%s_trunk@2x.png" % v, "canopy": S + "bd_great_%s_canopy@2x.png" % v}
            for v in ("bubblegum", "sky")]},
        "gumdrop": {"render": "sprite", "sway": 0.0, "variants": [
            {"sprite": S + "bd_gumdrop_%s@2x.png" % v} for v in ("cherry", "lime", "grape", "orange")]},
        "lolli": {"render": "sprite", "sway": 0.3, "variants": [
            {"sprite": S + "bd_lolli_%s@2x.png" % v} for v in ("rose", "sky", "lemon", "mint")]},
        "bubble_stalk": {"render": "sprite", "sway": 0.9, "variants": [
            {"sprite": S + "bd_bubble_stalk_%s@2x.png" % v} for v in ("pink", "sky", "mint")]},
        # the shared pixel water tiles would be the only pixels left: the soft ponds draw themselves
        "water": {"render": "soft"},
        "pool": {"render": "soft"},
        "river": {"render": "soft"},
        "props": {"extra_types": ["marsh_stone", "bubble_bloom", "jellybeans", "puff_bush", "fizz_spring", "candy_bench",
                                  "chime_bubble", "bubble_lamp", "pebble_pops", "cloud_cushion", "sign_bubble"]},
        "prop_lights": {
            "chime_bubble": {"radius": 40, "y": -44, "alpha": 0.34, "motes": 4, "size": 1.6,
                             "saturate": True, "ripple": True},
            "bubble_lamp": {"radius": 26, "y": -27, "alpha": 0.26},
            "bubble_bloom": {"radius": 14, "y": -15, "alpha": 0.14},
            "fizz_spring": {"radius": 16, "y": -4, "alpha": 0.16, "motes": 3},
        },
    },
    "daycycle": {"enabled": True, "period_sec": 360, "loop": True, "stops": [
        {"t": 0.0, "tint": [1.0, 1.0, 1.0], "vignette": [0.86, 0.72, 0.92], "vstrength": 0.18},
        {"t": 1.0, "tint": [1.0, 0.95, 0.97], "vignette": [1.0, 0.76, 0.84], "vstrength": 0.24},
    ]},
    # Visitors keep their own (pixel) look, which is rather the point -- you're the square ones here --
    # but in the world's light: a pastel lift, the dark outline softened to plum. And each of you walks
    # about inside a soap bubble of your own (VisitorBubble), which pops into being as you arrive:
    # you're just a visitor in a bubble world.
    "actor_look": {
        "shadow_mult": [0.86, 0.76, 0.98], "shadow_boost": 1.2,
        "light_mult": [1.0, 0.96, 0.98], "light_boost": 1.06,
        "cast": [1.0, 0.72, 0.86], "cast_amount": 0.08,
        "saturation": 0.95,
        "line_glow": [0.56, 0.38, 0.62], "line_amount": 0.55, "line_cut": 0.16, "pulse_speed": 0.0,
        "bubble": {"tint": [1.0, 0.76, 0.92], "radius": 21, "y": -9, "pop_delay": 0.5,
                   "companion": {"radius": 21, "y": -8}},
    },
}

ATMOSPHERE = {
    "day_tint": [1.0, 1.0, 1.0],
    "vignette": {"strength": 0.2, "color": [0.86, 0.72, 0.92]},
    "wind": {"strength": 1.6, "speed": 0.7},
    "ground_noise": {"contrast": 0.10, "tint": [1.0, 0.82, 0.92]},
    "region_tint_alpha": 0.12,
    "grass": {"max": 0},
    "soft_ground": {"dots": {"count": 800, "radius": [8, 34], "alpha": 0.16,
                             "colors": [list(BUBBLEGUM), list(LEMON), list(SKY), list(MINT), [1, 1, 1]]}},
    "fizz": {"per_pond": 9, "color": [1.0, 1.0, 1.0]},
}

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, W-6). 'reveal' says how it becomes "
                  "findable (see SecretDirector / Server.SecretReveal): touch_all -- ring every chime-bubble in 'props' "
                  "in one visit; each one reads the next of 'lines', and the last raises the first breath at 'position'.")
SECRET = {
    "id": "first_bubble",
    "position": list(SECRET_POS),
    "radius": 130.0,
    "prop": {"type": "first_bubble", "color": [0.86, 0.92, 1.0], "label": "the Burbler's first breath",
             "tags": ["round", "odd", "old"]},
    "lore": "The Old Burbler's very first breath: a bubble that has never popped, not once, in all the ages since. It's warm, and it hums the lullaby very quietly to itself.",
    "reveal": {
        "type": "touch_all",
        "props": [c[0] for c in CHIMES],
        "lines": [
            "The chime-bubble rings one round, warm note. Far below the Fizzwell, something very big turns over in its sleep.",
            "A second note, a little higher, joins the first and hangs in the air. The bubbles in the Fizzwell rise a little faster.",
            "Three notes now. Somewhere nearby, a bobbling starts humming along, not very well.",
            "Four notes. It's starting to sound like a tune: a slow, rocking one, the kind you sing to someone asleep.",
            "Five notes. The Fizzwell is fizzing hard now, as if something down there is listening.",
            "Six. The lullaby is almost whole. Just one chime-bubble left, somewhere you haven't been yet.",
        ],
        "again_line": "It rings its note again, round and warm. You've already sung this part of the lullaby.",
        "reveal_line": "The seventh note rings, and the whole lullaby hangs over Bobbledown at once. Down in the Fizzwell the Old Burbler sighs in its sleep, and a single, very old bubble rises to the lagoon's south shore.",
    },
    "found_line": "The Burbler kept its first breath safe all this time. Now it's let you carry it home.",
    "home_line": "Something has changed at home.",
    "qualities": ["old", "watery"],
    "keepsake": {
        "id": "kept_bubble",
        "type": "kept_bubble",
        "color": [0.86, 0.92, 1.0],
        "label": "the first breath, in a cup",
        "line": "Your companion nudges the bubble with its nose. It wobbles, and doesn't pop. It never will.",
        "temperament": {"curiosity": 0.7, "energy": 0.5, "clinginess": 0.35},
    },
}

HEADER = ("BOBBLEDOWN - the round world. A walk-and-wonder world that breaks from the pixel art: everything was "
          "BREATHED, not built, by the Old Burbler asleep under the Fizzwell, so nothing has a corner. Eight regions "
          "ring the fizzing lagoon: Popping Green (where you arrive), the High Hush, Gumdrop Hills, the Puffwood, "
          "Jellybottom, Lollipop Grove, the Bubblefield and the Pillow Dunes. It RE-SKINS ITSELF through its 'art' "
          "block: a SOFT ground (pastel dapples, ribbon paths, fizzing ponds), smooth @2x growths/props/creatures "
          "(pokepals/tools/gen_bobbledown.py), drifting bubbles and a pastel actor_look. Native creatures (bobbling, "
          "puffkin, wobbler, rollypoll, bubblefin) are ambient pals with lore in data/pals.json. Its SECRET: ring all "
          "seven chime-bubbles in one visit and the Burbler's first breath rises. Generated by tools/gen_bobbledown_world.py "
          "- edit that and re-run, don't hand-tune positions.")


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
path_objs = [{"from": a, "to": b, "color": RIBBON} for a, b in PATHS]

out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "bobbledown",')
out.append('\t"intro": %s,' % json.dumps("Everything here is round, and soft, and humming. You feel a little square. Touch things: they wobble back."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": true, "spacing": 110, "inset": 24, "jitter": 30, "rows": 2, "row_gap": 56 },')
out.append('\t"collision": { "tree_radius": 8, "great_tree_radius": 18, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.90, 0.95, 0.93],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [\n%s\n\t],' % block(PONDS))
out.append('\t"paths": [\n%s\n\t],' % block(path_objs))
out.append('\t"landmarks": [\n%s\n\t],' % block(LANDMARKS))
out.append('\t"trees": [\n%s\n\t],' % block(TREES))
out.append('\t"props": [\n%s\n\t],' % block(ALL_PROPS))
out.append('\t"_secret_comment": %s,' % json.dumps(SECRET_COMMENT))
out.append('\t"secret": %s,' % json.dumps(SECRET, indent="\t", ensure_ascii=False).replace("\n", "\n\t"))
out.append('\t"ambient_pals": [\n%s\n\t]' % block(CREATURES))
out.append("}")
text = "\n".join(out) + "\n"

# ── validate ─────────────────────────────────────────────────────────────────────────────────────────
d = json.loads(text)
ids = [p["id"] for p in d["props"]] + [c["id"] for c in d["ambient_pals"]]
assert len(ids) == len(set(ids)), "duplicate ids"
by_id = {p["id"]: p for p in d["props"]}
for p in d["props"]:
    assert bool(p.get("interactive")) == bool(p.get("lore")), "interactive iff lore: %s" % p["id"]
    if p.get("flare"):
        assert p.get("interactive"), "a flare prop must be touchable: %s" % p["id"]
    x, y = p["position"]
    assert BOUNDS_MIN[0] < x < BOUNDS_MAX[0] and BOUNDS_MIN[1] < y < BOUNDS_MAX[1], p["id"]
for cid in SECRET["reveal"]["props"]:
    assert by_id[cid].get("flare"), "every chime must be a flare prop (the server tracks flares): %s" % cid
assert len(SECRET["reveal"]["lines"]) == len(CHIMES) - 1
for cid, pos, _ in CHIMES:
    region = [r for r in REGIONS if r[1][0] <= pos[0] <= r[2][0] and r[1][1] <= pos[1] <= r[2][1]]
    assert region, cid
    assert abs(pos[0]) < BOUNDS_MAX[0] - 250 and abs(pos[1]) < BOUNDS_MAX[1] - 200, "%s is too near the edge" % cid
    assert all(math.hypot(pos[0] - pd["center"][0], pos[1] - pd["center"][1]) > pd["radius"] + 30 for pd in PONDS), cid
kinds = {}
for t in d["trees"]:
    k = t[2] if len(t) > 2 else "tree"
    kinds[k] = kinds.get(k, 0) + 1
print("props:", len(d["props"]), "| interactive:", sum(1 for p in d["props"] if p.get("interactive")),
      "| flare:", sum(1 for p in d["props"] if p.get("flare")), "| trees:", kinds,
      "| creatures:", len(d["ambient_pals"]))
for path in ["server/priv/world_seeds/bobbledown.json", "pokepals/tests/world_fixtures/bobbledown.json"]:
    open(path, "w").write(text)
print("wrote both files")
