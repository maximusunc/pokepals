#!/usr/bin/env python3
"""Generate DOZEWOOD, the drowsy forest, as a world spec.

A modest (3200 x 2400), walk-and-nap world: mossy hollows, hammocks strung between posts, hanging lamps of
slow pale light, round heavy trees and willows trailing their vines, held at a long lilac dusk. Everything
here moves at half speed (slow wind, slow motes, a slow day cycle). No goal, no puzzle: a place to nap.

Its one SECRET (docs/home-world-and-secrets-design.md, "Dozewood"): a place your companion dreams of.
Reveal type "dream". Your companion only dozes off somewhere it feels safe: in one of four authored NAP
SPOTS (cushioned hollows), after a pet it welcomed, with you beside it and still, and calm (DreamGate, the
numbers are the `reveal` block below). Asleep, it dreams: a thought bubble shows a small picture of a
landmark, the Crooked Arch (always that one, a fixed authored choice). Walk there together, awake, and a
dream-lantern is waiting under it; examining it claims the secret as usual. Four other distinctive
landmarks stand elsewhere (a pond with three stones, a lantern log, a ring of toadstools, a sleeping
boulder), so the picture is something to recognise, not just to follow.

Hand-authored: regions, ponds, the nap spots, the landmarks, every lore line, the art override, the
secret. Procedural (seeded, so re-running reproduces it): the scatter of trees and props, kept clear of
the landmarks, nap spots, ponds and the landing.

Art assets come from pokepals/tools/gen_dozewood.py. Writes the server seed and the client test fixture.
Run from the repo root:  python3 tools/gen_dozewood_world.py
"""
import json
import math
import random

random.seed(0xD07E0)

BOUNDS_MIN = (-1600, -1200)
BOUNDS_MAX = (1600, 1200)
PLAYER_SPAWN = [0, 900]
COMPANION_SPAWN = [-30, 930]
PORTALS = [
    {"id": "dozewood_way_home", "type": "portal", "position": [-72, 900], "color": [0.78, 0.74, 1.0], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

REGIONS = [
    ("drowse_landing",  (-500, 640),   (500, 1200),   (0.80, 0.80, 0.98)),
    ("burrow_banks",    (500, 640),    (1600, 1200),  (0.84, 0.80, 0.94)),
    ("moss_hollows",    (-1600, -100), (-500, 1200),  (0.74, 0.86, 0.86)),
    ("lullaby_water",   (-500, -250),  (350, 640),    (0.74, 0.84, 0.96)),
    ("hammock_wood",    (350, -350),   (1600, 640),   (0.86, 0.82, 0.94)),
    ("yawning_rise",    (350, -1200),  (1600, -350),  (0.78, 0.78, 0.96)),
    ("lampwick_reach",  (-1600, -1200), (-500, -100), (0.90, 0.84, 0.88)),
    ("quiet_end",       (-500, -1200), (350, -250),   (0.80, 0.84, 0.94)),
]

WATER = [0.17, 0.30, 0.34]
PONDS = [
    {"center": [-60, 200], "radius": 190, "color": WATER},
    {"center": [-230, 130], "radius": 120, "color": WATER},
    {"center": [110, 280], "radius": 110, "color": WATER},
    {"center": [1010, -780], "radius": 85, "color": WATER},     # the pond of three stones
    {"center": [-700, -120], "radius": 70, "color": WATER},
]

LANDMARKS = [   # great trees, for finding your way by
    {"type": "great_tree", "position": [-1300, 700]},
    {"type": "great_tree", "position": [1250, 100]},
    {"type": "great_tree", "position": [350, -1000]},
]

# ── the nap spots: cushioned hollows ─────────────────────────────────────────────────────────────────
NAP_SPOTS = [(-380, 770), (-1050, 420), (820, 280), (-780, -560)]
# ── the landmarks (the arch is the one it dreams of) ─────────────────────────────────────────────────
ARCH = (-60, -960)
SECRET_POS = (-58, -954)
POND_STONES_CENTER = (1010, -780)
LANTERN_LOG = (-1180, -760)
TOAD_RING = (-1290, 160)
SLEEPER = (1250, 560)
STONES = [(POND_STONES_CENTER[0] + 124 * math.cos(math.radians(a)), POND_STONES_CENTER[1] + 124 * math.sin(math.radians(a)))
          for a in (-150, -30, 90)]


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
LAMP = (1.0, 0.90, 0.62)

NAP_LORE = [
    "A hollow in the moss, just the size of two, with a cushion someone left. It feels like a place where it's safe to close your eyes. Your companion might think so too, with a gentle pet and some quiet.",
    "A round dip in the moss, warm as a bed that's just been left. Whatever sleeps here sleeps well.",
    "A hollow between two roots, lined with soft lilac cloth. The moss around it has grown in a ring, to keep the draughts out.",
    "A hollow at the foot of a lamp, where the light is slow and low. Even you feel a little drowsy, standing next to it.",
]
SPECIAL = []
for i, (pos, lore) in enumerate(zip(NAP_SPOTS, NAP_LORE)):
    SPECIAL.append(prop("nap_%d" % (i + 1), "dz_nap_hollow", pos, WHITE, "a cushioned hollow", lore))
SPECIAL += [
    # the landmarks
    prop("lm_arch", "dz_crooked_arch", ARCH, WHITE, "a crooked arch",
         "An arch of old grey roots, grown crooked: one leg leans out, the top has slumped to the right. It frames nothing in particular, but the moss beneath it is a little brighter, as if something slept there."),
    prop("lm_lantern_log", "dz_lantern_log", LANTERN_LOG, LAMP, "a log with a lamp inside",
         "A hollow log, and a lamp glowing inside it, slow and pale. Somebody left it lit for whoever is sleeping in there. Nobody is.", solid=True, radius=12),
    prop("lm_toadstools", "dz_toadstool_ring", TOAD_RING, WHITE, "a ring of toadstools",
         "Seven small toadstools, standing in a ring round a dip in the moss. Nothing is inside the ring but the quiet."),
    prop("lm_sleeper", "dz_sleeper_stone", SLEEPER, WHITE, "a sleeping boulder",
         "A boulder with a blanket of moss pulled up to its brow, and one eye shut. You would swear it was breathing. You decide not to wake it.", solid=True, radius=14),
]
for i, (x, y) in enumerate(STONES):
    SPECIAL.append(prop("lm_stone_%d" % (i + 1), "dz_still_stone", (x, y), WHITE, "a smooth stone",
                        "One of three smooth stones set round the pond. They are warm, which a stone shouldn't be." if i == 0 else None,
                        solid=True, radius=6))
SPECIAL += [
    prop("landing_seat", "dz_cap_seat", (130, 940), WHITE, "a toadstool seat",
         "A flat-topped toadstool, exactly the right height for sitting. You sit. It is exactly right."),
    prop("landing_lamp", "dz_hanging_lamp", (-150, 880), LAMP, "a hanging lamp",
         "A paper lamp on a crook of wood. Its light comes and goes about once a breath, if you breathe slowly."),
    prop("hammock_1", "dz_hammock", (560, 560), WHITE, "a hammock",
         "A hammock slung between two posts. It's too small for you. It sways a little when you look at it, as if it knew."),
    prop("hammock_2", "dz_hammock", (-1000, 800), WHITE, "a hammock",
         "A lilac hammock with a pillow already in it. The pillow has a dent in it, and the dent is still warm."),
    prop("sleepy_log", "dz_sleepy_log", (450, 300), WHITE, "a mossy log",
         "A log so mossy it has become a sofa. Something small has been sleeping on it for a hundred years, on and off.", solid=True, radius=10),
    prop("old_stone", "dz_moss_stone", (-1350, -350), WHITE, "a stone with a name worn off",
         "Letters were cut here once. Moss has gently put them to bed.", solid=True, radius=6),
]

placed = [(p["position"][0], p["position"][1], 30) for p in SPECIAL]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 70))
KEEP_CLEAR = [(ARCH[0], ARCH[1], 130), (SECRET_POS[0], SECRET_POS[1], 130), (LANTERN_LOG[0], LANTERN_LOG[1], 110),
              (TOAD_RING[0], TOAD_RING[1], 110), (SLEEPER[0], SLEEPER[1], 110), (POND_STONES_CENTER[0], POND_STONES_CENTER[1], 220)]
KEEP_CLEAR += [(x, y, 110) for x, y in NAP_SPOTS]


def clear(x, y, r):
    if not (BOUNDS_MIN[0] + 140 <= x <= BOUNDS_MAX[0] - 140 and BOUNDS_MIN[1] + 140 <= y <= BOUNDS_MAX[1] - 140):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 200:
        return False
    if any(math.hypot(x - pd["center"][0], y - pd["center"][1]) < pd["radius"] * 1.2 + r for pd in PONDS):
        return False
    if any(math.hypot(x - kx, y - ky) < kr + r for kx, ky, kr in KEEP_CLEAR):
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


def trees(region, n, kind, r=28):
    for x, y in scatter(region, n, r):
        TREES.append([x, y, kind])


def props(region, n, type, label, r=16, solid=None, radius=None, color=WHITE):
    for i, (x, y) in enumerate(scatter(region, n, r)):
        PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), color, label, solid=solid, radius=radius))


def lamps(region, n):
    props(region, n, "dz_hanging_lamp", "a hanging lamp", r=20, color=LAMP)


for reg, rounds, oaks, willows, ferns, mounds in [
    ("moss_hollows", 38, 14, 34, 26, 14), ("lampwick_reach", 30, 12, 28, 18, 10), ("hammock_wood", 44, 16, 22, 20, 12),
    ("yawning_rise", 28, 10, 18, 14, 10), ("quiet_end", 22, 8, 18, 18, 8), ("lullaby_water", 10, 4, 14, 14, 6),
    ("drowse_landing", 12, 4, 10, 14, 6), ("burrow_banks", 24, 8, 16, 14, 10),
]:
    trees(reg, rounds, "round")
    trees(reg, oaks, "oak", 30)
    trees(reg, willows, "willow", 30)
    props(reg, ferns, "dz_fern_clump", "a fern")
    props(reg, mounds, "dz_moss_mound", "a mound of moss", r=18, solid=True, radius=8)
for reg, n in [("drowse_landing", 5), ("moss_hollows", 8), ("lampwick_reach", 9), ("hammock_wood", 8), ("yawning_rise", 5),
               ("quiet_end", 5), ("lullaby_water", 6), ("burrow_banks", 5)]:
    lamps(reg, n)
for reg, n in [("moss_hollows", 4), ("hammock_wood", 4), ("quiet_end", 2), ("burrow_banks", 3)]:
    props(reg, n, "dz_cap_seat", "a toadstool seat", r=18)
for reg, n in [("lampwick_reach", 3), ("yawning_rise", 3), ("moss_hollows", 3)]:
    props(reg, n, "dz_sleepy_log", "a mossy log", r=22, solid=True, radius=8)
props("yawning_rise", 4, "dz_moss_stone", "a mossy stone", r=18, solid=True, radius=6)

ALL_PROPS = SPECIAL + PROPS

S = "res://assets/sprites/"


def ramp(*rows):
    return [list(r) for r in rows]


def tree_variants(names):
    return [{"trunk": S + "dz_%s_trunk.png" % n, "canopy": S + "dz_%s_canopy.png" % n} for n in names]


ROUNDS = ["round_a", "round_b", "round_c"]
OAKS = ["oak_a", "oak_b"]
WILLOWS = ["willow_a", "willow_b", "willow_c"]
PROP_TYPES = ["dz_hanging_lamp", "dz_hammock", "dz_nap_hollow", "dz_moss_mound", "dz_sleepy_log", "dz_fern_clump",
              "dz_toadstool_ring", "dz_crooked_arch", "dz_still_stone", "dz_lantern_log", "dz_sleeper_stone", "dz_moss_stone", "dz_cap_seat"]
ART = {
    # a long lilac dusk: moss in a lavender shade, the lamps the only warm thing
    "palette": {
        "ground_top": [0.34, 0.50, 0.40], "ground_bottom": [0.26, 0.40, 0.34],
        "foliage_dark": [0.14, 0.24, 0.24], "foliage_mid": [0.30, 0.44, 0.36], "foliage_light": [0.55, 0.70, 0.50],
        "bark": [0.34, 0.28, 0.30], "water": [0.17, 0.30, 0.34], "rim": [1.0, 0.92, 0.74],
        "shadow": [0.10, 0.08, 0.22], "grass": [0.34, 0.50, 0.40], "water_rim": [0.78, 0.84, 0.66, 0.6],
    },
    "light": {"shadow_alpha": 0.20, "rim_strength": 0.14},
    "entities": {
        "portal": {"frame_tint": [0.80, 0.76, 1.0]},
        "ground": {
            "render": "pixel", "terrain": S + "dz_terrain.png", "tile": 128,
            "details": S + "dz_details.png", "details_index": "res://data/dz_details.json",
            "shade": 0.20,
            "ramps": {
                "grass": ramp((0.20, 0.34, 0.30), (0.27, 0.43, 0.35), (0.35, 0.53, 0.41), (0.56, 0.72, 0.50)),
                "lush": ramp((0.15, 0.28, 0.27), (0.21, 0.36, 0.32), (0.28, 0.45, 0.37), (0.44, 0.62, 0.46)),
                "meadow": ramp((0.28, 0.42, 0.38), (0.36, 0.52, 0.44), (0.45, 0.62, 0.50), (0.66, 0.78, 0.60)),
                "dirt": ramp((0.22, 0.20, 0.26), (0.30, 0.27, 0.33), (0.38, 0.34, 0.40), (0.52, 0.48, 0.52)),
                "sand": ramp((0.34, 0.32, 0.30), (0.44, 0.40, 0.34), (0.54, 0.49, 0.40), (0.70, 0.64, 0.50)),
                "path": ramp((0.26, 0.30, 0.30), (0.33, 0.37, 0.36), (0.40, 0.44, 0.42), (0.54, 0.58, 0.52)),
                "worn": ramp((0.24, 0.32, 0.32), (0.31, 0.40, 0.38), (0.38, 0.47, 0.43), (0.52, 0.62, 0.54)),
            },
            "accents": [[0.96, 0.90, 0.62], [0.78, 0.70, 0.94]],
            "patches": {"lush": {"scale": 0.0034, "threshold": 0.46}, "meadow": {"scale": 0.005, "threshold": 0.62},
                        "dirt": {"scale": 0.006, "threshold": 1.6}},
            "clump": {"scale": 0.008, "dark": 0.32, "light": 0.68},
            "scatter": {
                "density": 0.6,
                "open": [
                    {"names": ["mosstuft_a", "mosstuft_b"], "weight": 26, "count": [1, 4], "sway": 0.15},
                    {"names": ["fernlet", "fernlet_b"], "weight": 16, "count": [1, 3], "sway": 0.2},
                    {"names": ["fallenleaf", "leafpair"], "weight": 12, "count": [1, 3]},
                    {"names": ["mosspebble"], "weight": 6, "count": [1, 2]},
                    {"names": ["toadlet"], "weight": 5},
                    {"names": ["sleepbud"], "weight": 7, "count": [1, 2]},
                    {"names": ["drowsetwig"], "weight": 5},
                ],
                "under_trees": {"names": ["drowsetwig", "fallenleaf"], "ring": ["mosstuft_b"]},
                "path_edge": [],
                "reeds": ["reedlet"],
                "lilies": [],
            },
        },
        "understory": {"render": "sprite", "prefix": S + "dz_understory_", "types": ["bush_a", "bush_b", "stump"], "density": 0.7},
        # slow motes of lamp-coloured light always drift about; a few leaves let go, now and then
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 20, "always": True, "color": [1.0, 0.92, 0.62]},
                         "clouds": {"count": 4, "alpha": 0.07, "speed": 3},
                         "leaves": {"rate": 0.3, "colors": [[0.62, 0.74, 0.48], [0.82, 0.70, 0.46]]}},
        "tree": {"render": "sprite", "sway": 0.12, "variants": tree_variants(ROUNDS + OAKS + WILLOWS * 2)},
        "round": {"render": "sprite", "sway": 0.12, "variants": tree_variants(ROUNDS)},
        "oak": {"render": "sprite", "sway": 0.1, "variants": tree_variants(OAKS)},
        "willow": {"render": "sprite", "sway": 0.2, "variants": tree_variants(WILLOWS)},
        "great_tree": {"render": "sprite", "sway": 0.08, "variants": tree_variants(["great_oak", "great_willow"])},
        "water": {"render": "sprite", "tile": S + "dz_pond.png", "world_tile": 64},
        "pool": {"render": "sprite", "tile": S + "dz_pond.png", "world_tile": 64},
        "river": {"render": "sprite", "tile": S + "dz_pond.png", "world_tile": 64},
        "props": {"extra_types": PROP_TYPES},
        # the lamps' slow pale light: a soft halo that breathes
        "prop_lights": {"dz_hanging_lamp": {"radius": 40, "y": -20, "alpha": 0.40},
                        "dz_lantern_log": {"radius": 34, "y": -10, "alpha": 0.36}},
    },
    "daycycle": {"enabled": True, "period_sec": 700, "loop": True, "stops": [
        {"t": 0.0, "tint": [0.92, 0.90, 1.0], "vignette": [0.08, 0.06, 0.18], "vstrength": 0.40},
        {"t": 1.0, "tint": [0.86, 0.86, 1.0], "vignette": [0.10, 0.07, 0.22], "vstrength": 0.48},
    ]},
}

ATMOSPHERE = {
    "day_tint": [0.92, 0.90, 1.0],
    "vignette": {"strength": 0.40, "color": [0.08, 0.06, 0.18]},
    "wind": {"strength": 0.35, "speed": 0.25},
    "pollen": {"amount": 55, "color": [1.0, 0.94, 0.72]},
    "glow": {"pulse_speed": 0.45},
    "region_tint_alpha": 0.06,
    "grass": {"max": 0},
    "sparkles": {"count": 260, "colors": [[1.0, 0.94, 0.72], [0.82, 0.78, 1.0]]},
}

HEADER = ("DOZEWOOD - a drowsy forest held at a long lilac dusk. A walk-and-nap world (no goal, no puzzle): mossy hollows, "
          "hammocks, hanging lamps of slow pale light, round trees and willows trailing their vines. Everything moves at half "
          "speed. Eight regions: Drowse Landing (where you arrive), Burrow Banks, Moss Hollows, Lullaby Water, Hammock Wood, "
          "Yawning Rise, Lampwick Reach and the Quiet End. It RE-SKINS ITSELF through its 'art' block (deep-merged over "
          "data/art.json): its own moss terrain + litter atlas, dusky trees (tree entries [x, y, kind]: round/oak/willow), a "
          "still dark pond, breathing lamp lights, a slow day cycle. Its secret is a place your companion dreams of: see the "
          "'secret' block (reveal type 'dream'). Generated by tools/gen_dozewood_world.py (art: pokepals/tools/gen_dozewood.py) - "
          "edit that and re-run, don't hand-tune positions.")

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Dozewood'). reveal.type 'dream': the companion "
                  "only dozes off in one of reveal.spots (nap spots) when it feels safe (a welcomed pet, you still and close, a calm "
                  "mood; DreamGate), dreams of the landmark at reveal.landmark_position (picture: reveal.picture), and when you and "
                  "it walk there together the prop rises (DozeDirector / SecretDirector). The server honours a claim only here, "
                  "within 'radius' of 'position'.")
SECRET = {
    "id": "dream_lantern",
    "position": list(SECRET_POS),
    "radius": 120.0,
    "prop": {"type": "dream_lantern", "color": [1.0, 0.90, 0.62], "label": "a dream-lantern", "tags": ["warm", "small", "odd", "soft"]},
    "lore": "A paper lantern, no bigger than a loaf, and its light comes and goes like a sleeper's breath. It isn't hot. It's the warmth of a bed that has just been left.",
    "reveal": {
        "type": "dream",
        "landmark": "crooked_arch",
        "landmark_position": list(ARCH),
        "picture": S + "dz_dream_crooked_arch.png",
        "spots": [list(p) for p in NAP_SPOTS],
        "spot_radius": 120.0, "player_radius": 150.0, "together_distance": 100.0, "still_speed": 12.0,
        "pet_window": 40.0, "calm_arousal": 0.40, "calm_valence": -0.05,
        "fill_seconds_fresh": 16.0, "fill_seconds_bonded": 5.0, "drain_rate": 0.12,
        "settle_at": 0.30, "yawn_at": 0.55, "stir_below": 0.12, "dream_delay": 2.5,
        "wake_distance": 170.0, "wake_cooldown": 6.0,
        "arrive_radius": 150.0, "companion_radius": 190.0,
        "yawn_after": 45.0, "yawn_every": 150.0,
        "lines": {
            "hollow": "Your companion sniffs the cushioned hollow and looks up at you. It would settle here, if it felt safe: a gentle pet, and a little quiet.",
            "calm": "It's too wound up to settle. Stay still beside it a moment, and let it come down.",
            "settle": "It turns round once, twice, and lies down, nose tucked in.",
            "yawn": "It yawns, wide and slow. You feel it catch.",
            "asleep": "Its breathing slows. It is asleep.",
            "dream": "Soft bubbles rise from it. In the biggest, a place: a crooked arch of old roots, and a little brightness beneath it.",
            "wake_poked": "It stirs at your call and blinks up at you. The dream drifts off, but not all the way.",
            "pet_asleep": "It sighs in its sleep and tucks in closer under your hand. It sleeps on.",
            "wake_left": "It wakes as you go, and gets up to follow, still half in the dream.",
            "yawn_ambient": "Your companion yawns, huge and slow. You find you're yawning too.",
        },
        "reveal_line": "Your companion stops short under the arch and looks about, as if it has been here before. A paper lantern is glowing on the moss.",
    },
    "found_line": "It dreamed of this place, and you walked there together. The lantern is lit by nothing but the dream, and it goes home with you.",
    "home_line": "Something has changed at home.",
    "qualities": ["quiet", "warm", "glowing"],
    "keepsake": {
        "id": "dream_lamp", "type": "kept_dream_lantern", "color": [1.0, 0.90, 0.62], "label": "a dream-lantern on a cushion of moss",
        "line": "A lantern that glows when it is dreamed of. Your companion curls up beside it, now and then, and goes to sleep.",
        "temperament": {"curiosity": 0.4, "energy": 0.25, "clinginess": 0.7},
    },
}


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "dozewood",')
out.append('\t"intro": %s,' % json.dumps("Moss, and a lamp, and the light that never quite goes. Nothing here needs doing. Sit down; everything will wait."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": true, "spacing": 120, "inset": 24, "jitter": 34, "rows": 2, "row_gap": 60 },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.34, 0.50, 0.40],')
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
for t in d["trees"]:
    for kx, ky, kr in KEEP_CLEAR:
        assert math.hypot(t[0] - kx, t[1] - ky) >= kr - 1, "a tree stands in a landmark's clearing"
for pd in PONDS:
    for sp in NAP_SPOTS + [ARCH, SECRET_POS, LANTERN_LOG, TOAD_RING, SLEEPER]:
        assert math.hypot(sp[0] - pd["center"][0], sp[1] - pd["center"][1]) > pd["radius"] + 40, "a landmark/nap spot sits in a pond"
assert math.hypot(SECRET_POS[0] - ARCH[0], SECRET_POS[1] - ARCH[1]) < 20
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("props:", len(d["props"]), "| trees:", kinds)
for path in ["server/priv/world_seeds/dozewood.json", "pokepals/tests/world_fixtures/dozewood.json"]:
    open(path, "w").write(text)
print("wrote both files")
