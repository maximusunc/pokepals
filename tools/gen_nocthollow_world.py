#!/usr/bin/env python3
"""Generate NOCTHOLLOW — the night planet — as a world spec.

A big (4500 x 3500), walk-and-wonder world on another planet: a night that never ends and a land
that glows to fill it. No goal, no puzzle — a place, not a task. Eight regions ring a luminous lake,
each with its own growths, props and native creatures; glowing moss-veins lead out from the landing
to all of them.

Hand-authored: the regions, the veins (paths), the lake, the landmark trees, every lore line, and the
WORLD'S OWN ART OVERRIDE (the "art" block: night palette, glowing trees, luminous water, the
visitors' palette-shift + glow, prop lights). Procedural (seeded, so re-running reproduces it): the
scatter of trees/growths/props inside each region, placed with spacing and kept clear of the water,
the veins and the landing.

Art assets come from pokepals/tools/gen_nocthollow.py (tools/pixelart/nocthollow.py). Writes both the
server seed and the client test fixture. Run from the repo root:  python3 tools/gen_nocthollow_world.py
"""
import json
import math
import random

random.seed(0x0C7401)

BOUNDS_MIN = (-2250, -1750)
BOUNDS_MAX = (2250, 1750)
PLAYER_SPAWN = [0, 1150]
COMPANION_SPAWN = [-30, 1180]

# ── regions: (id, min, max, tint) — named areas the companion feels it has reached ─────────────────
REGIONS = [
    ("the_landing",      (-520, 560),    (520, 1700),   (0.62, 0.56, 1.00)),
    ("the_lumen_mere",   (-640, -1080),  (640, -160),   (0.30, 0.80, 1.00)),
    ("glowcap_wood",     (-2200, -880),  (-700, 680),   (0.20, 0.90, 0.80)),
    ("elder_hollow",     (-2200, -1700), (-700, -880),  (0.80, 0.40, 1.00)),
    ("breathing_fen",    (-2200, 680),   (-560, 1700),  (0.60, 1.00, 0.50)),
    ("crystal_steppe",   (700, -880),    (2200, 600),   (0.50, 0.90, 1.00)),
    ("skyward_rise",     (700, -1700),   (2200, -880),  (0.40, 0.50, 1.00)),
    ("bellbloom_meadow", (560, 600),     (2200, 1700),  (1.00, 0.50, 0.90)),
]

# ── the Lumen Mere: overlapping ponds make one organic lake, plus fen pools ─────────────────────────
LAKE_COLOR = [0.06, 0.12, 0.26]
PONDS = [
    {"center": [0, -560], "radius": 250, "color": LAKE_COLOR},
    {"center": [-250, -460], "radius": 170, "color": LAKE_COLOR},
    {"center": [260, -500], "radius": 180, "color": LAKE_COLOR},
    {"center": [60, -800], "radius": 150, "color": LAKE_COLOR},
    {"center": [-160, -740], "radius": 120, "color": LAKE_COLOR},
    # the Breathing Fen's warm pools
    {"center": [-1500, 1150], "radius": 110, "color": LAKE_COLOR},
    {"center": [-1180, 1360], "radius": 80, "color": LAKE_COLOR},
    {"center": [-1800, 900], "radius": 70, "color": LAKE_COLOR},
]

# ── moss-veins: the glowing trails that lead from the landing out to every region ──────────────────
VEIN = [0.06, 0.17, 0.25]
PATHS = [
    ([0, 1250], [0, 640]),           # landing → the mere's south shore
    ([0, 640], [-520, -120]),        # around the west shore
    ([0, 640], [540, -140]),         # around the east shore
    ([-520, -120], [-1350, -150]),   # into the glowcap wood
    ([-1350, -150], [-1500, -1150]), # up to the elder hollow
    ([540, -140], [1400, -100]),     # into the crystal steppe
    ([1400, -100], [1450, -1200]),   # up to the skyward rise
    ([0, 1000], [-1300, 1150]),      # down into the breathing fen
    ([0, 1000], [1350, 1150]),       # across to the bellbloom meadow
]
PATH_GLOW = True

# ── landmarks: the great Lumen Elders, seen (and walked behind) from afar ───────────────────────────
LANDMARKS = [
    {"type": "great_tree", "position": [-1500, -1290]},
    {"type": "great_tree", "position": [-1150, -1450]},
    {"type": "great_tree", "position": [-1880, -1080]},
    {"type": "great_tree", "position": [-380, -1150]},   # one leaning over the mere's north shore
]

# ── hand-placed props: lore, the landing, the special places ────────────────────────────────────────
SPECIAL = []


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


CYAN = (0.50, 1.00, 0.92)
PINK = (1.00, 0.56, 0.92)
VIOLET = (0.70, 0.56, 1.00)
GOLD = (1.00, 0.86, 0.48)
AZURE = (0.56, 0.78, 1.00)
LIME = (0.78, 1.00, 0.56)

# The landing: a ring of rune-stones around where you arrive, and the fallen star you arrive beside.
for i, ang in enumerate(range(0, 360, 60)):
    a = math.radians(ang + 30)
    SPECIAL.append(prop("landing_stone_%d" % i, "moonstone", (math.cos(a) * 150, 1150 + math.sin(a) * 92), CYAN,
                        "a humming rune-stone", solid=True, radius=8,
                        lore=None if i else "The runes on this stone glow a little brighter as you come near, as if it's been expecting visitors. The air hums very softly."))
SPECIAL += [
    prop("starfall", "star_shard", (0, 900), GOLD, "a fallen star",
         "A piece of fallen star, half-buried in the moss and still warm. The rocks around it have been glowing gold for longer than anyone remembers."),
    prop("landing_bench", "lumen_bench", (120, 990), CYAN, "a bench of pale fungus-wood",
         "A bench grown rather than built, from pale, springy fungus-wood. From here you can see the light of the Mere spilling over the hill."),
    prop("landing_moss", "glow_moss", (-110, 960), CYAN, "a cushion of starmoss",
         "Starmoss: soft as a pillow and faintly warm. Every footstep across it leaves a little print of light behind."),
]

# The Lumen Mere's shore and water.
SPECIAL += [
    prop("mere_stone", "moonstone", (330, -230), AZURE, "a shore-stone", solid=True, radius=8,
         lore="The water here never ripples on its own. It glows from somewhere deep down, steady as a held breath."),
    prop("mere_bench", "lumen_bench", (-300, -200), CYAN, "a fungus-wood bench",
         "Someone grew this bench to face the water. Sit long enough and the lights in the Mere seem to drift into slow constellations."),
]
for i, (x, y) in enumerate([(-60, -560), (110, -620), (-220, -480), (240, -470), (40, -790), (-160, -700), (300, -560), (-300, -420), (150, -380), (-40, -420)]):
    lore = None
    if i == 0:
        lore = "A lily-light, floating out on the Mere. Its bud opens and closes slowly, glowing a little brighter each time it opens."
    SPECIAL.append(prop("lily_%d" % i, "lily_light", (x, y), [CYAN, PINK, AZURE][i % 3], "a floating lily-light", lore=lore))

# Elder Hollow: the listening circle.
for i, ang in enumerate(range(0, 360, 45)):
    a = math.radians(ang)
    SPECIAL.append(prop("elder_ring_%d" % i, "moonstone", (-1500 + math.cos(a) * 120, -1080 + math.sin(a) * 70), VIOLET,
                        "a listening-stone", solid=True, radius=8))
SPECIAL += [
    prop("elder_heart", "moonstone", (-1500, -1080), PINK, "the heart-stone", solid=True, radius=9,
         lore="The old stones stand in a ring, all leaning toward the Elders. If you hold still, you can hear the trees creak, slow as breathing."),
    prop("elder_roots", "glow_moss", (-1260, -1360), VIOLET, "moss over the Elder's roots",
         "The Elders' glowing tendrils sway even when there's no wind, as if they're feeling for something."),
]

# Glowcap Wood.
SPECIAL += [
    prop("wood_ring", "glowcaps", (-1400, -300), CYAN, "a fairy-ring of glowcaps",
         "A perfect circle of glowcaps. Touch one and the whole ring brightens, one cap after the next, all the way round.", flare=True),
    prop("wood_fern", "curl_fern", (-1100, 300), LIME, "a curl-fern",
         "Curl-ferns open at night. Here it's always night, so they never quite finish uncurling."),
    prop("wood_snail_trail", "glow_moss", (-1700, 120), CYAN, "a shimmering trail on the moss",
         "A lanternsnail went by here not long ago. Its trail on the moss is still glowing faintly."),
]

# Breathing Fen.
SPECIAL += [
    prop("fen_vent", "vent", (-1350, 980), LIME, "a breathing vent",
         "The ground here breathes. Every so often the vent sighs out a cloud of glowing spores, and they drift up like slow snow falling the wrong way.", flare=True),
    prop("fen_puff", "spore_puff", (-1650, 1300), LIME, "a giant puffball",
         "Touch it and — fwump — it puffs out a little cloud of glowing spores, then puffs itself back up again.", flare=True),
    prop("fen_stone", "moonstone", (-950, 1500), LIME, "a sunken stone", solid=True, radius=8,
         lore="The pools are warm. Lanternsnails come here to rest, and the whole fen dims and brightens with them, like a slow pulse."),
]

# Crystal Steppe.
SPECIAL += [
    prop("steppe_shard", "star_shard", (1200, 200), AZURE, "a singing shard",
         "Brush the crystals and they ring, high and clear. Their notes take a long time to fade out across the steppe."),
    prop("steppe_stone", "moonstone", (1700, -400), AZURE, "a weathered stone", solid=True, radius=8,
         lore="The crystals out here grow so slowly that this cluster has likely been here since before the first moon rose."),
]

# Skyward Rise.
SPECIAL += [
    prop("rise_stone", "moonstone", (1450, -1300), VIOLET, "a sky-stone", solid=True, radius=8,
         lore="The runes are a map of the sky: two moons and a scatter of stars. One of the moons on it is marked with a tiny glowing dot."),
    prop("rise_shard", "star_shard", (1850, -1500), GOLD, "a star-shard",
         "This high up you can see the whole of the Mere glowing below, like a second sky lying on the ground."),
    prop("rise_bench", "lumen_bench", (1150, -1000), AZURE, "a lookout bench",
         "A good place to watch the driftrays. They circle up here in slow rings, their tails trailing light."),
]

# Bellbloom Meadow.
SPECIAL += [
    prop("meadow_bloom", "lumen_bloom", (1300, 1150), PINK, "a lumen-bloom",
         "A lumen-bloom. Touch it and it flares bright. Everyone nearby will see it light up, then fade slowly back to a soft glow.", flare=True),
    prop("meadow_stone", "moonstone", (1800, 900), PINK, "a garden-stone", solid=True, radius=8,
         lore="The bell-flowers here chime when a stiltwhisk brushes past. It sounds like very faraway music."),
]

# ── procedural scatter, per region ──────────────────────────────────────────────────────────────────
placed = []  # (x, y, r) of everything placed so far, for spacing
for p in SPECIAL:
    placed.append((p["position"][0], p["position"][1], 22))
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 60))


def _seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
    return math.hypot(p[0] - (ax + dx * t), p[1] - (ay + dy * t))


def clear(x, y, r, on_water=False):
    if not (BOUNDS_MIN[0] + 140 <= x <= BOUNDS_MAX[0] - 140 and BOUNDS_MIN[1] + 140 <= y <= BOUNDS_MAX[1] - 140):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 230:
        return False
    in_water = any(math.hypot(x - pd["center"][0], y - pd["center"][1]) < pd["radius"] * 0.85 for pd in PONDS)
    near_water = any(math.hypot(x - pd["center"][0], y - pd["center"][1]) < pd["radius"] * 1.2 + r for pd in PONDS)
    if on_water:
        if not in_water:
            return False
    elif near_water:
        return False
    if any(_seg_dist((x, y), a, b) < 30 + r for a, b in PATHS):
        return False
    return all(math.hypot(x - px, y - py) >= r + pr for px, py, pr in placed)


def scatter(region_id, n, r, tries=4000, on_water=False):
    rmin, rmax = next((a, b) for rid, a, b, _ in REGIONS if rid == region_id)
    out = []
    for _ in range(tries):
        if len(out) >= n:
            break
        x = random.uniform(rmin[0], rmax[0])
        y = random.uniform(rmin[1], rmax[1])
        if clear(x, y, r, on_water):
            placed.append((x, y, r))
            out.append((round(x), round(y)))
    return out


TREES = []   # [x, y] (a glowcap — the "tree" kind) or [x, y, kind]
PROPS = []


def trees(region, n, kind=None, r=26):
    for x, y in scatter(region, n, r):
        TREES.append([x, y] if kind is None else [x, y, kind])


def props(region, n, type, colors, label, r=16):
    for i, (x, y) in enumerate(scatter(region, n, r)):
        PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), random.choice(colors), label))


# Glowcap Wood: dense mushroom forest, floored with glowcaps, ferns and moss.
trees("glowcap_wood", 230, r=22)
props("glowcap_wood", 90, "glowcaps", [CYAN, AZURE, PINK], "a cluster of glowcaps")
props("glowcap_wood", 60, "curl_fern", [LIME, CYAN], "a curl-fern")
props("glowcap_wood", 70, "glow_moss", [CYAN, AZURE], "a patch of glow-moss")
# Elder Hollow: sparse, old, tall.
trees("elder_hollow", 40)
trees("elder_hollow", 16, "spore_stalk")
props("elder_hollow", 50, "glow_moss", [VIOLET, PINK], "a patch of glow-moss")
props("elder_hollow", 30, "glowcaps", [VIOLET, PINK], "a cluster of glowcaps")
# Breathing Fen: stalks, puffballs and vents among warm pools.
trees("breathing_fen", 50, "spore_stalk")
trees("breathing_fen", 24)
props("breathing_fen", 36, "spore_puff", [LIME, GOLD], "a puffball")
props("breathing_fen", 16, "vent", [LIME, CYAN], "a breathing vent")
props("breathing_fen", 60, "glow_moss", [LIME, CYAN], "a patch of glow-moss")
# Crystal Steppe: spires and shards on open ground.
trees("crystal_steppe", 80, "crystal_spire", r=28)
props("crystal_steppe", 60, "star_shard", [AZURE, CYAN, VIOLET], "a crystal shard")
props("crystal_steppe", 40, "glow_moss", [AZURE, VIOLET], "a patch of glow-moss")
# Skyward Rise: the tallest crystals, high and lonely.
trees("skyward_rise", 56, "crystal_spire", r=30)
trees("skyward_rise", 14)
props("skyward_rise", 40, "star_shard", [GOLD, VIOLET], "a star-shard")
# Bellbloom Meadow: arching bell-flowers and fields of lumen-blooms (every bloom flares).
trees("bellbloom_meadow", 70, "bell_flower")
trees("bellbloom_meadow", 14)
for i, (x, y) in enumerate(scatter("bellbloom_meadow", 90, 14)):
    PROPS.append(prop("meadow_bloom_%d" % i, "lumen_bloom", (x, y), random.choice([PINK, VIOLET, AZURE, GOLD]),
                      "a lumen-bloom", flare=True,
                      lore="The lumen-bloom flares at your touch, and everyone nearby will see it glow." if i % 4 == 0 else
                      ("It flares, bright as a struck match, then slowly settles back down." if i % 4 == 1 else
                       ("The light ripples out from your hand and over the petals." if i % 4 == 2 else
                        "It brightens, and the blooms around it seem to lean in."))))
props("bellbloom_meadow", 40, "glow_moss", [PINK, VIOLET], "a patch of glow-moss")
# The Mere's shore: blooms and moss right by the water, plus a few glowcaps.
props("the_lumen_mere", 40, "glow_moss", [CYAN, AZURE], "a patch of glow-moss", r=14)
props("the_lumen_mere", 24, "glowcaps", [CYAN, AZURE], "a cluster of glowcaps")
trees("the_lumen_mere", 18)
trees("the_lumen_mere", 10, "bell_flower")
# The Landing: a gentle welcome — a few blooms to touch, moss, and growths framing the arrival.
for i, (x, y) in enumerate(scatter("the_landing", 22, 16)):
    PROPS.append(prop("landing_bloom_%d" % i, "lumen_bloom", (x, y), random.choice([CYAN, PINK, AZURE]), "a lumen-bloom", flare=True,
                      lore="It flares at your touch. Everyone nearby will see the light." if i == 0 else "It blazes up at your touch, then settles back into a soft glow."))
props("the_landing", 40, "glow_moss", [CYAN, VIOLET], "a patch of glow-moss")
trees("the_landing", 26)
props("the_landing", 24, "glowcaps", [CYAN, PINK, AZURE], "a cluster of glowcaps")
props("the_landing", 14, "curl_fern", [LIME, CYAN], "a curl-fern")
trees("the_landing", 12, "bell_flower")
trees("the_landing", 6, "crystal_spire")

# ── native creatures: ambient pals, server-simulated, examinable (their lore lives in data/pals.json) ─
CREATURES = []


def creatures(region, species, n, roam, variants=3):
    for i, (x, y) in enumerate(scatter(region, n, 40)):
        CREATURES.append({"id": "%s_%s_%d" % (region, species, i), "home": [x, y], "roam_radius": roam,
                          "region": region, "species": species, "variant": random.randrange(variants)})


creatures("the_lumen_mere", "lumejelly", 5, 220)
creatures("the_landing", "lumejelly", 3, 200)
creatures("glowcap_wood", "glimmerhop", 7, 180)
creatures("the_landing", "glimmerhop", 3, 160)
creatures("glowcap_wood", "lanternsnail", 4, 120)
creatures("breathing_fen", "lanternsnail", 6, 140)
creatures("breathing_fen", "lumejelly", 3, 220)
creatures("crystal_steppe", "stiltwhisk", 6, 260)
creatures("bellbloom_meadow", "stiltwhisk", 4, 240)
creatures("bellbloom_meadow", "glimmerhop", 4, 180)
creatures("skyward_rise", "driftray", 6, 280)
creatures("the_lumen_mere", "driftray", 3, 260)
creatures("elder_hollow", "lumejelly", 4, 220)
creatures("elder_hollow", "lanternsnail", 2, 120)

ALL_PROPS = SPECIAL + PROPS

# ── the world's own ART OVERRIDE (deep-merged over data/art.json by ArtStyle.load_style) ─────────────
S = "res://assets/sprites/"
ART = {
    "palette": {
        "ground_top": [0.07, 0.06, 0.17],
        "ground_bottom": [0.04, 0.09, 0.17],
        "foliage_dark": [0.10, 0.08, 0.26],
        "foliage_mid": [0.16, 0.16, 0.40],
        "foliage_light": [0.30, 0.56, 0.70],
        "bark": [0.30, 0.26, 0.46],
        "water": [0.06, 0.12, 0.26],
        "rim": [0.70, 1.00, 0.95],
        "shadow": [0.0, 0.0, 0.04],
        "grass": [0.10, 0.28, 0.34],
        "water_rim": [0.45, 0.95, 1.00, 0.75],
    },
    "light": {"shadow_alpha": 0.32, "rim_strength": 0.3},
    "entities": {
        "tree": {"render": "sprite", "glow_radius": 30, "glow_y": -36, "sway": 0.5, "variants": [
            {"trunk": S + "noct_glowcap_teal_trunk.png", "canopy": S + "noct_glowcap_teal_canopy.png", "glow": [0.56, 1.0, 0.92]},
            {"trunk": S + "noct_glowcap_violet_trunk.png", "canopy": S + "noct_glowcap_violet_canopy.png", "glow": [1.0, 0.58, 0.96]},
            {"trunk": S + "noct_glowcap_azure_trunk.png", "canopy": S + "noct_glowcap_azure_canopy.png", "glow": [0.58, 0.8, 1.0]},
        ]},
        "great_tree": {"render": "sprite", "glow_radius": 70, "glow_y": -70, "sway": 0.4, "variants": [
            {"trunk": S + "noct_elder_cyan_trunk.png", "canopy": S + "noct_elder_cyan_canopy.png", "glow": [0.5, 0.98, 1.0]},
            {"trunk": S + "noct_elder_magenta_trunk.png", "canopy": S + "noct_elder_magenta_canopy.png", "glow": [1.0, 0.52, 0.9]},
        ]},
        "crystal_spire": {"render": "sprite", "glow_radius": 28, "glow_y": -26, "sway": 0.0, "variants": [
            {"sprite": S + "noct_crystal_spire_cyan.png", "glow": [0.5, 0.95, 1.0]},
            {"sprite": S + "noct_crystal_spire_rose.png", "glow": [1.0, 0.6, 0.95]},
            {"sprite": S + "noct_crystal_spire_gold.png", "glow": [1.0, 0.88, 0.5]},
        ]},
        "bell_flower": {"render": "sprite", "glow_radius": 20, "glow_y": -26, "sway": 0.8, "variants": [
            {"sprite": S + "noct_bell_flower_blue.png", "glow": [0.55, 0.85, 1.0]},
            {"sprite": S + "noct_bell_flower_pink.png", "glow": [1.0, 0.62, 0.92]},
            {"sprite": S + "noct_bell_flower_lime.png", "glow": [0.78, 1.0, 0.6]},
        ]},
        "spore_stalk": {"render": "sprite", "glow_radius": 22, "glow_y": -40, "sway": 0.6, "variants": [
            {"sprite": S + "noct_spore_stalk_amber.png", "glow": [1.0, 0.8, 0.42]},
            {"sprite": S + "noct_spore_stalk_mint.png", "glow": [0.62, 1.0, 0.78]},
        ]},
        "water": {"render": "sprite", "tile": S + "water_lumen.png", "world_tile": 64},
        "pool": {"render": "sprite", "tile": S + "water_lumen.png", "world_tile": 64},
        "river": {"render": "sprite", "tile": S + "water_lumen.png", "world_tile": 64},
        "props": {"extra_types": ["glowcaps", "lumen_bloom", "spore_puff", "curl_fern", "moonstone", "star_shard",
                                  "lily_light", "glow_moss", "vent", "lumen_bench"]},
        "prop_lights": {
            "lumen_bloom": {"radius": 34, "y": -12, "alpha": 0.5},
            "glowcaps": {"radius": 26, "y": -6, "alpha": 0.42},
            "glow_moss": {"radius": 26, "y": -2, "alpha": 0.36},
            "curl_fern": {"radius": 20, "y": -10, "alpha": 0.32},
            "moonstone": {"radius": 28, "y": -14, "alpha": 0.36},
            "star_shard": {"radius": 34, "y": -6, "alpha": 0.5, "motes": 2},
            "lily_light": {"radius": 24, "y": -2, "alpha": 0.5},
            "spore_puff": {"radius": 26, "y": -6, "alpha": 0.4, "motes": 3},
            "vent": {"radius": 30, "y": -2, "alpha": 0.42, "motes": 5},
            "lumen_bench": {"radius": 20, "y": -8, "alpha": 0.28},
        },
    },
    "daycycle": {"enabled": True, "period_sec": 300, "loop": True, "stops": [
        {"t": 0.0, "tint": [0.98, 0.98, 1.06], "vignette": [0.02, 0.02, 0.10], "vstrength": 0.46},
        {"t": 1.0, "tint": [0.92, 0.88, 1.04], "vignette": [0.08, 0.02, 0.14], "vstrength": 0.56},
    ]},
    "actor_look": {
        "shadow_mult": [0.54, 0.48, 1.0], "shadow_boost": 1.15,
        "light_mult": [0.85, 0.96, 1.0], "light_boost": 1.12,
        "cast": [0.30, 0.40, 0.85], "cast_amount": 0.12,
        "saturation": 1.1,
        "line_glow": [0.45, 0.95, 1.0], "line_amount": 0.7, "line_cut": 0.16,
        "aura": [0.5, 0.95, 1.0], "aura_radius": 24, "motes": 3,
    },
}

ATMOSPHERE = {
    "day_tint": [0.98, 0.98, 1.06],
    "vignette": {"strength": 0.5, "color": [0.02, 0.02, 0.10]},
    "wind": {"strength": 1.2, "speed": 0.6},
    "ground_noise": {"contrast": 0.24, "tint": [0.22, 0.10, 0.42]},
    "pollen": {"amount": 80, "color": [0.6, 1.0, 0.95]},
    "glow": {"pulse_speed": 0.9},
    "region_tint_alpha": 0.07,
    "grass": {"max": 900},
    "sparkles": {"count": 1100, "colors": [list(CYAN), list(PINK), list(VIOLET), list(GOLD), list(AZURE)]},
    "footprints": {"color": [0.55, 1.0, 0.9], "life": 5.0, "spacing": 15},
}

HEADER = ("NOCTHOLLOW - the night planet. A walk-and-wonder world (no goal, no puzzle): a night that never "
          "ends and a land that glows to fill it. Eight regions ring the Lumen Mere (a luminous lake): the "
          "Landing (where you arrive), Glowcap Wood, Elder Hollow, the Breathing Fen, the Crystal Steppe, the "
          "Skyward Rise and the Bellbloom Meadow, linked by glowing moss-veins. It RE-SKINS ITSELF through its "
          "'art' block (deep-merged over data/art.json): night palette, glowing mushroom-trees / Lumen Elders / "
          "crystal spires / bell-flowers / spore-stalks (tree entries [x, y, kind]), luminous water, prop lights, "
          "a slow aurora day-cycle, and actor_look - the palette shift + glow its visitors wear. Native creatures "
          "(lumejelly, glimmerhop, stiltwhisk, driftray, lanternsnail) are ambient pals; their lore and temperament "
          "live in data/pals.json. Props with 'flare': true blaze up when touched, relayed to everyone in the world. "
          "Generated by tools/gen_nocthollow_world.py (art: pokepals/tools/gen_nocthollow.py) - edit that and re-run, "
          "don't hand-tune positions.")


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "))


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
path_objs = [{"from": a, "to": b, "color": VEIN, "glow": PATH_GLOW} for a, b in PATHS]

out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "nocthollow",')
out.append('\t"intro": %s,' % json.dumps("The air hums, and everything glows. Wander, look closer, and touch the light — your footsteps will shine."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": true, "spacing": 120, "inset": 24, "jitter": 34, "rows": 2, "row_gap": 60 },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.06, 0.07, 0.17],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [\n%s\n\t],' % block(PONDS))
out.append('\t"paths": [\n%s\n\t],' % block(path_objs))
out.append('\t"landmarks": [\n%s\n\t],' % block(LANDMARKS))
out.append('\t"trees": [\n%s\n\t],' % block(TREES))
out.append('\t"props": [\n%s\n\t],' % block(ALL_PROPS))
out.append('\t"ambient_pals": [\n%s\n\t]' % block(CREATURES))
out.append("}")
text = "\n".join(out) + "\n"

# ── validate ─────────────────────────────────────────────────────────────────────────────────────────
d = json.loads(text)
ids = [p["id"] for p in d["props"]] + [c["id"] for c in d["ambient_pals"]]
assert len(ids) == len(set(ids)), "duplicate ids"
for p in d["props"]:
    assert bool(p.get("interactive")) == bool(p.get("lore")), "interactive iff lore: %s" % p["id"]
    if p.get("flare"):
        assert p.get("interactive"), "a flare prop must be touchable: %s" % p["id"]
    x, y = p["position"]
    assert BOUNDS_MIN[0] < x < BOUNDS_MAX[0] and BOUNDS_MIN[1] < y < BOUNDS_MAX[1], p["id"]
kinds = {}
for t in d["trees"]:
    k = t[2] if len(t) > 2 else "tree"
    kinds[k] = kinds.get(k, 0) + 1
print("props:", len(d["props"]), "| interactive:", sum(1 for p in d["props"] if p.get("interactive")),
      "| flare:", sum(1 for p in d["props"] if p.get("flare")), "| trees:", kinds,
      "| creatures:", len(d["ambient_pals"]))
for path in ["server/priv/world_seeds/nocthollow.json", "pokepals/tests/world_fixtures/nocthollow.json"]:
    open(path, "w").write(text)
print("wrote both files")
