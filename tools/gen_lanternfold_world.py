#!/usr/bin/env python3
"""Generate LANTERNFOLD, the shadow-puppet world, as a world spec.

A modest (3200 x 2400), walk-and-wonder world cut from paper: flat, layered silhouettes against a warm amber sky,
all lit by one great lantern at the north end. Trees are dark paper cut-outs in three depths (the far ones pale,
the near ones almost black), the ground is warm paper, the houses are flat shapes with a lit window. At the
north end a pale cliff face stands like a theatre's screen, and the great lantern in front of it throws a shadow
of everything that stands in its light onto it. No goal: a place to look at.

Its one SECRET (docs/home-world-and-secrets-design.md, "Lanternfold"): a shadow mural with one figure missing,
a bird in flight. Reveal type "shadow". You choose your companion's FORM and stand it in the lantern's light
(tap the lit ground); its shadow, projected from the lantern onto the face, grows as it nears the lantern and
slides as it moves. Only a bird's, from the right place, fills the gap (a bird's shadow is held in the air, the
rest stand on the ground). Then a door in the cliff opens on a little cut-paper bird, the secret. The numbers
(the face, the lantern, the spot, hover, tolerances, hold times, notice range) are the `reveal` block below.

Hand-authored: regions, ponds, the stage, the landmarks, every lore line, the art override, the secret.
Procedural (seeded, so re-running reproduces it): the scatter of trees and props, kept clear of the stage, the
door, the lantern road and the ponds.

Art assets come from pokepals/tools/gen_lanternfold.py. Writes the server seed and the client test fixture.
Run from the repo root:  python3 tools/gen_lanternfold_world.py
"""
import json
import math
import random

random.seed(0x1A57E)

BOUNDS_MIN = (-1600, -1200)
BOUNDS_MAX = (1600, 1200)
PLAYER_SPAWN = [-1100, 900]
COMPANION_SPAWN = [-1130, 930]
PORTALS = [
    {"id": "lanternfold_way_home", "type": "portal", "position": [-1172, 900], "color": [1.0, 0.78, 0.42], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

# ── the stage and its screen (every number here is mirrored into the secret's reveal block) ───────────────
FACE_HW = 190                  # half the screen's width
FACE_H = 112                   # how tall the face is
BASE_Y = -960                  # the face's foot (the screen's south edge)
SCREEN_DEPTH = 30              # the cliff's footprint, north of BASE_Y
LANTERN_PROP = (0, -816)       # the great lantern prop's position (its pole's foot is ~6 px below)
LANTERN = (0, LANTERN_PROP[1] + 6)       # the lantern's GROUND point: where the light comes from
D = LANTERN[1] - BASE_Y        # the lantern's distance from the screen's foot (150)
HOVER = 14.0                   # how high a bird's shadow is held aloft (px of the animal, scaled by s)
SPOT_SCALE = 2.0               # the gap bird's shadow is twice life size...
SPOT_X_ON_FACE = 14.0          # ...and lands this far right of the face's middle
SPOT = (round(LANTERN[0] + SPOT_X_ON_FACE / SPOT_SCALE), round(LANTERN[1] - D / SPOT_SCALE))
DOOR = {"x": 120, "w": 28, "h": 44}                     # x relative to the face's centre
SECRET_POS = (DOOR["x"], BASE_Y + 26)                    # on the door's threshold
STAGE_RECT = (-340, BASE_Y - 40, 340, LANTERN[1] + 90)   # nothing is scattered in here (x0, y0, x1, y1)

REGIONS = [
    ("footlights",      (-600, -1200),  (600, -600),    (1.00, 0.88, 0.66)),
    ("far_wood",        (-1600, -1200), (-600, -300),   (0.98, 0.86, 0.68)),
    ("near_wood",       (600, -1200),   (1600, -300),   (0.96, 0.82, 0.62)),
    ("marionette_lane", (-1600, -300),  (-300, 200),    (1.00, 0.86, 0.64)),
    ("cutout_village",  (-300, -600),   (800, 200),     (1.00, 0.90, 0.70)),
    ("reed_pools",      (800, -300),    (1600, 200),    (0.94, 0.82, 0.66)),
    ("paper_landing",   (-1600, 200),   (-500, 1200),   (1.00, 0.88, 0.68)),
    ("long_shadow",     (-500, 200),    (900, 1200),    (0.98, 0.84, 0.64)),
    ("moon_hill",       (900, 200),     (1600, 1200),   (0.96, 0.80, 0.62)),
]

WATER = [0.16, 0.08, 0.08]
PONDS = [
    {"center": [1180, -170], "radius": 100, "color": WATER},
    {"center": [1390, 20], "radius": 64, "color": WATER},
    {"center": [1010, 40], "radius": 56, "color": WATER},
    {"center": [260, 800], "radius": 120, "color": WATER},
    {"center": [-980, -90], "radius": 58, "color": WATER},
]

LANDMARKS = [   # great paper trees, for finding your way by
    {"type": "great_tree", "position": [-1250, -820]},
    {"type": "great_tree", "position": [1250, -820]},
    {"type": "great_tree", "position": [1320, 760]},
]


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
LAMP = (1.0, 0.82, 0.40)

# footlights: a post along each edge of the lantern's cone, so the lit stage reads as a stage
FOOTLIGHTS = []
for k, cy in enumerate([BASE_Y + 36, BASE_Y + 66, BASE_Y + 96, BASE_Y + 126]):
    d = LANTERN[1] - cy
    edge = FACE_HW * d / D          # where a shadow would just reach the face's edge
    for side in (-1, 1):
        FOOTLIGHTS.append((LANTERN[0] + side * (edge + 18), cy))

SPECIAL = [
    # the great lantern: the light everything here is cut by
    # NOT examinable (no lore): a tap near an examinable prop is an order to go and look at it, and the stage is
    # where taps must mean "stand there"; the lantern's story is on the painted notice beside the stage instead
    prop("great_lantern", "lf_great_lantern", LANTERN_PROP, LAMP, "the great lantern", solid=True, radius=6),
    prop("landing_sign", "lf_signboard", (-1060, 840), WHITE, "a notice board",
         "A paper notice, pinned straight. 'WELCOME TO LANTERNFOLD. Everything here is cut from paper and lit by one lantern, "
         "far to the north, which throws a shadow of whatever stands before it onto the cliff. Walk north. Tap the lit ground "
         "to stand your companion in the light, and watch the cliff. The cliff has a mural, and the mural has a gap. A "
         "companion's shape is on the little chip at the bottom right.'", solid=True, radius=5),
    prop("stage_board", "lf_signboard", (-400, -880), WHITE, "a painted notice",
         "'TONIGHT: THE CROSSING. A flock of birds against the moon. (One is missing. The painter said it would come when it "
         "was ready.) The great lantern, whose paper is as thin as a held breath and whose flame has never needed trimming, throws "
         "whatever stands before it onto the cliff. Please stand in the light and see: nearer the lantern, a shadow is bigger; to "
         "one side, it slides. Things that walk throw their shadows on the ground. A bird's shadow is up in the air, where a bird "
         "belongs.'", solid=True, radius=5),
    prop("puppeteer_cart", "lf_cart", (-980, 180), WHITE, "a puppeteer's cart",
         "A little cart with a curtain, and a stage the size of a bread-box lit by one tiny lamp. The puppeteer is nowhere "
         "about, but the stage is set: a cut-paper moon, and room for a bird.", solid=True, radius=12),
    prop("moon_pole", "lf_moon", (1260, 520), WHITE, "a paper moon on a pole",
         "A crescent of pale paper on a pole, turning very slowly. It is the moon from the mural, or its cousin."),
    prop("village_tower", "lf_cutout_tower", (430, -380), WHITE, "a cut-out tower",
         "A tall paper tower with one lit window at the top. Whoever lives there has been up all night, cutting out stars.", solid=True, radius=10),
]
LORE_HOUSES = [
    "A flat paper house with a lit window. You walk round the side and it is exactly as thin as it looks, which is very. "
    "The lamplight in the window is real, though.",
    "A cut-out house, dark against the amber, a warm window in each side. Someone has pinned a paper cat to the sill.",
    "A house made of one sheet of paper, folded into a roof. The door is a slit of light. You decide it is rude to knock.",
]
HOUSE_SPOTS = [(-120, -300), (180, -140), (-20, 60), (540, -60), (320, 120), (620, -300)]
for i, pos in enumerate(HOUSE_SPOTS):
    SPECIAL.append(prop("house_%d" % (i + 1), "lf_cutout_house", pos, WHITE, "a paper house",
                        LORE_HOUSES[i] if i < len(LORE_HOUSES) else None, solid=True, radius=14))
PUPPET_LORE = [
    "A little paper puppet on a stick, arms on pins. Its eye is a pinprick of warm light. It looks, for a moment, at you.",
    "A paper puppet with a red coat, held up by nobody. Somebody must have propped it here to watch the stage.",
    "A puppet with one arm raised, as if it were about to say something and then thought better of it.",
]
PUPPET_SPOTS = [(-1180, 760), (-1380, -150), (-820, 300), (700, 720), (-620, -560)]
for i, pos in enumerate(PUPPET_SPOTS):
    SPECIAL.append(prop("puppet_%d" % (i + 1), "lf_puppet_stick", pos, WHITE, "a paper puppet",
                        PUPPET_LORE[i] if i < len(PUPPET_LORE) else None, solid=True, radius=4))
for i, (x, y) in enumerate(FOOTLIGHTS):
    SPECIAL.append(prop("footlight_%d" % (i + 1), "lf_lantern_post", (x, y), LAMP, "a footlight",
                        None, solid=True, radius=3))

placed = [(p["position"][0], p["position"][1], 30) for p in SPECIAL]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 70))
KEEP_CLEAR = [(SECRET_POS[0], SECRET_POS[1], 90)]


def in_stage(x, y, r=0):
    x0, y0, x1, y1 = STAGE_RECT
    return x0 - r <= x <= x1 + r and y0 - r <= y <= y1 + r


# the lantern road: posts leading from the landing toward the stage, so the way north is lit
ROAD = [(-1100, 850), (-900, 560), (-640, 300), (-340, 40), (-120, -300), (-60, -560), (-20, -760)]


def near_road(x, y, r):
    for (ax, ay), (bx, by) in zip(ROAD, ROAD[1:]):
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
        if math.hypot(x - (ax + t * dx), y - (ay + t * dy)) < 40 + r:
            return True
    return False


def clear(x, y, r):
    if not (BOUNDS_MIN[0] + 140 <= x <= BOUNDS_MAX[0] - 140 and BOUNDS_MIN[1] + 140 <= y <= BOUNDS_MAX[1] - 140):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 200 or in_stage(x, y, r + 10) or near_road(x, y, r):
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


def depth_kind(y):
    """The layers of a paper theatre: far (north) pale, near (south) almost black, with a little mixing."""
    t = (y - BOUNDS_MIN[1]) / float(BOUNDS_MAX[1] - BOUNDS_MIN[1])       # 0 north .. 1 south
    t += random.uniform(-0.12, 0.12)
    return "far" if t < 0.36 else ("mid" if t < 0.66 else "near")


def trees(region, n, r=28):
    for x, y in scatter(region, n, r):
        TREES.append([x, y, depth_kind(y)])


def props(region, n, type, label, r=16, solid=None, radius=None, color=WHITE):
    for i, (x, y) in enumerate(scatter(region, n, r)):
        PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), color, label, solid=solid, radius=radius))


for reg, n_trees, rocks, fences in [
    ("far_wood", 70, 8, 2), ("near_wood", 70, 8, 2), ("marionette_lane", 40, 6, 3), ("cutout_village", 26, 4, 5),
    ("reed_pools", 34, 5, 1), ("paper_landing", 36, 5, 2), ("long_shadow", 40, 6, 2), ("moon_hill", 46, 6, 2), ("footlights", 18, 2, 0),
]:
    trees(reg, n_trees)
    props(reg, rocks, "lf_rock", "a flat rock", r=18, solid=True, radius=7)
    props(reg, fences, "lf_fence", "a paper fence", r=20, solid=True, radius=8)
props("reed_pools", 22, "lf_reed", "a clump of reeds", r=14)
props("long_shadow", 8, "lf_reed", "a clump of reeds", r=14)
props("marionette_lane", 4, "lf_puppet_stick", "a paper puppet", r=20, solid=True, radius=4)
props("cutout_village", 3, "lf_lantern_post", "a paper lantern", r=24, color=LAMP, solid=True, radius=3)
# the lantern road's posts
for i, (x, y) in enumerate(ROAD[:-1]):
    for j in range(3):
        t = (j + 1) / 4.0
        nx, ny = ROAD[i + 1]
        px, py = x + (nx - x) * t, y + (ny - y) * t
        # offset to one side, so the post stands beside the way and not on it
        L = math.hypot(nx - x, ny - y)
        ox, oy = -(ny - y) / L * 34, (nx - x) / L * 34
        PROPS.append(prop("road_%d_%d" % (i, j), "lf_lantern_post", (px + ox, py + oy), LAMP, "a paper lantern", solid=True, radius=3))

ALL_PROPS = SPECIAL + PROPS

S = "res://assets/sprites/"


def ramp(*rows):
    return [list(r) for r in rows]


def tree_variants(names):
    return [{"trunk": S + "lf_%s_trunk.png" % n, "canopy": S + "lf_%s_canopy.png" % n} for n in names]


NEAR = ["near_pine_a", "near_pine_b", "near_pine_c", "near_round_a", "near_oak_a"]
MID = ["mid_pine_a", "mid_round_a", "mid_oak_a", "mid_willow_a"]
FAR = ["far_pine_a", "far_round_a", "far_oak_a"]
PROP_TYPES = ["lf_great_lantern", "lf_lantern_post", "lf_cutout_house", "lf_cutout_tower", "lf_fence", "lf_signboard",
              "lf_puppet_stick", "lf_reed", "lf_rock", "lf_cart", "lf_moon"]
ART = {
    # warm paper under an amber sky; dark umber cut-outs; the lantern the only thing that glows
    "palette": {
        "ground_top": [0.95, 0.72, 0.42], "ground_bottom": [0.86, 0.60, 0.34],
        "foliage_dark": [0.12, 0.06, 0.05], "foliage_mid": [0.30, 0.15, 0.10], "foliage_light": [0.56, 0.32, 0.18],
        "bark": [0.16, 0.08, 0.06], "water": [0.16, 0.08, 0.08], "rim": [1.0, 0.86, 0.56],
        "shadow": [0.28, 0.10, 0.04], "grass": [0.92, 0.68, 0.38], "water_rim": [1.0, 0.82, 0.5, 0.7],
    },
    "light": {"shadow_alpha": 0.30, "rim_strength": 0.18},
    "entities": {
        "portal": {"frame_tint": [1.0, 0.80, 0.48]},
        "ground": {
            "render": "pixel", "terrain": S + "lf_terrain.png", "tile": 128,
            "details": S + "lf_details.png", "details_index": "res://data/lf_details.json",
            "shade": 0.20,
            "ramps": {
                "grass": ramp((0.80, 0.54, 0.30), (0.88, 0.64, 0.36), (0.95, 0.74, 0.44), (0.99, 0.84, 0.54)),
                "lush": ramp((0.74, 0.46, 0.26), (0.82, 0.55, 0.31), (0.90, 0.65, 0.38), (0.96, 0.76, 0.48)),
                "meadow": ramp((0.90, 0.68, 0.40), (0.96, 0.77, 0.47), (0.99, 0.85, 0.56), (1.00, 0.93, 0.70)),
                "dirt": ramp((0.58, 0.32, 0.18), (0.68, 0.40, 0.22), (0.77, 0.48, 0.27), (0.88, 0.62, 0.38)),
                "sand": ramp((0.92, 0.72, 0.46), (0.96, 0.80, 0.54), (0.99, 0.88, 0.64), (1.00, 0.95, 0.78)),
                "path": ramp((0.70, 0.44, 0.26), (0.78, 0.52, 0.31), (0.86, 0.62, 0.38), (0.94, 0.74, 0.50)),
                "worn": ramp((0.76, 0.50, 0.30), (0.84, 0.59, 0.36), (0.91, 0.69, 0.43), (0.97, 0.80, 0.54)),
            },
            "accents": [[1.0, 0.84, 0.44], [0.82, 0.38, 0.22]],
            "patches": {"lush": {"scale": 0.0036, "threshold": 0.58}, "meadow": {"scale": 0.0046, "threshold": 0.50},
                        "dirt": {"scale": 0.0055, "threshold": 0.78}},
            "clump": {"scale": 0.008, "dark": 0.34, "light": 0.66},
            "scatter": {
                "density": 0.7,
                "open": [
                    {"names": ["bladetuft_a", "bladetuft_b"], "weight": 24, "count": [1, 4], "sway": 0.3},
                    {"names": ["midtuft"], "weight": 8, "count": [1, 3], "sway": 0.2},
                    {"names": ["scrap_a", "scrap_b"], "weight": 14, "count": [1, 3]},
                    {"names": ["star"], "weight": 3},
                    {"names": ["pebbles", "flatstone"], "weight": 6, "count": [1, 2]},
                    {"names": ["ribbonbit"], "weight": 3},
                    {"names": ["ember"], "weight": 2},
                ],
                "under_trees": {"names": ["scrap_a", "midtuft"], "ring": ["bladetuft_a"]},
                "path_edge": [],
                "reeds": [],
                "lilies": [],
            },
        },
        "understory": {"render": "sprite", "prefix": S + "lf_understory_", "types": ["bush_a", "bush_b", "stump"], "density": 0.35},
        # paper scraps drift down now and then; no butterflies or fireflies: only the lantern glows
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 0},
                         "clouds": {"count": 3, "alpha": 0.06, "speed": 5},
                         "leaves": {"rate": 0.45, "colors": [[0.20, 0.09, 0.07], [0.90, 0.60, 0.30], [1.0, 0.86, 0.54]]}},
        "tree": {"render": "sprite", "sway": 0.12, "variants": tree_variants(NEAR + MID + FAR)},
        "near": {"render": "sprite", "sway": 0.10, "variants": tree_variants(NEAR)},
        "mid": {"render": "sprite", "sway": 0.12, "variants": tree_variants(MID)},
        "far": {"render": "sprite", "sway": 0.14, "variants": tree_variants(FAR)},
        "great_tree": {"render": "sprite", "sway": 0.08, "variants": tree_variants(["great_near", "great_mid"])},
        "water": {"render": "sprite", "tile": S + "lf_pool.png", "world_tile": 64},
        "pool": {"render": "sprite", "tile": S + "lf_pool.png", "world_tile": 64},
        "river": {"render": "sprite", "tile": S + "lf_pool.png", "world_tile": 64},
        "building": {"render": "sprite", "wall": S + "lf_face.png", "roof": S + "lf_face.png", "slope": S + "lf_face.png"},
        "props": {"extra_types": PROP_TYPES},
        "prop_lights": {"lf_great_lantern": {"radius": 150, "y": -26, "alpha": 0.42},
                        "lf_lantern_post": {"radius": 30, "y": -22, "alpha": 0.40},
                        "lf_cutout_tower": {"radius": 18, "y": -30, "alpha": 0.25},
                        "lf_cart": {"radius": 26, "y": -14, "alpha": 0.30}},
    },
    "daycycle": {"enabled": True, "period_sec": 900, "loop": True, "hold": 0.4, "stops": [
        {"t": 0.0, "tint": [1.0, 0.92, 0.78], "vignette": [0.30, 0.10, 0.04], "vstrength": 0.34},
        {"t": 1.0, "tint": [1.0, 0.84, 0.66], "vignette": [0.30, 0.08, 0.04], "vstrength": 0.46},
    ]},
}

ATMOSPHERE = {
    "day_tint": [1.0, 0.88, 0.70],
    "vignette": {"strength": 0.40, "color": [0.30, 0.09, 0.03]},
    "wind": {"strength": 0.5, "speed": 0.45},
    "pollen": {"amount": 24, "color": [1.0, 0.82, 0.46]},
    "glow": {"pulse_speed": 0.6},
    "region_tint_alpha": 0.06,
    "grass": {"max": 0},
}

HEADER = ("LANTERNFOLD - a shadow-puppet world. A walk-and-wonder world cut from paper: flat, layered silhouettes against a warm "
          "amber sky, all lit by one great lantern at the north end, which throws a shadow of whatever stands before it onto a "
          "cliff-face screen (ShadowScreenView, spec 'view': 'shadow_screen'). Nine regions: Paper Landing (where you arrive), "
          "Long Shadow, Moon Hill, Marionette Lane, Cutout Village, Reed Pools, Far Wood, Near Wood and the Footlights (the "
          "stage). It RE-SKINS ITSELF through its 'art' block (deep-merged over data/art.json): its own paper terrain + litter "
          "atlas, trees in three depths (tree entries [x, y, kind]: far/mid/near), an ink pool, cut-out props, one great "
          "lantern that glows. Its secret is a mural with a bird missing: see the 'secret' block (reveal type 'shadow'). "
          "Generated by tools/gen_lanternfold_world.py (art: pokepals/tools/gen_lanternfold.py) - edit that and re-run, "
          "don't hand-tune positions.")

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Lanternfold'). reveal.type 'shadow': the great "
                  "lantern at reveal.lantern projects whatever stands in its light onto the face (reveal.face) (ShadowCast); the "
                  "companion, stood on the lit ground by a tap, throws its CURRENT form's shadow; the bird's, held aloft by "
                  "reveal.hover and from near reveal.spot, fills the gap in the mural (MuralGuide), and the door in the cliff "
                  "opens on the prop (ShadowDirector / SecretDirector). The server honours a claim only here, within 'radius' of "
                  "'position'.")
SECRET = {
    "id": "paper_bird",
    "position": list(SECRET_POS),
    "radius": 120.0,
    "prop": {"type": "paper_bird", "color": [1.0, 0.76, 0.30], "label": "a paper bird", "tags": ["warm", "small", "old", "glowing"]},
    "lore": "A little bird cut from one sheet of paper, wings up, on a stick. It is dark against the light and warm in the hand, as if it had just flown out of the lantern. Your companion looks at it for a long moment, and then at the cliff, and then at its own shadow.",
    "reveal": {
        "type": "shadow",
        "face": {"x0": -FACE_HW, "x1": FACE_HW, "base_y": BASE_Y, "height": FACE_H},
        "lantern": list(LANTERN),
        "spot": list(SPOT),
        "species": "bird",
        "hover": HOVER,
        "place_tol": 26.0, "size_tol": 0.30, "fill_threshold": 0.80,
        "hold_low": 2.2, "hold_high": 1.2, "drain_rate": 1.5, "still_speed": 12.0,
        "settle_radius": 36.0, "close_at": 0.40, "wrong_place": 0.60,
        "notice_range_low": 360.0, "notice_range_high": 700.0, "notice_cooldown_low": 16.0, "notice_cooldown_high": 6.0, "notice_hold": 2.5,
        "pet_pause": 3.0, "release_distance": 760.0, "release_after": 3.0, "drift_hold": 30.0,
        "lines": {
            "arrive": "You step into the lantern's light, and your shadow flies up onto the cliff. Everything in the light throws one. Tap the lit ground to stand your companion in it, and watch the screen.",
            "stage": "Your companion goes and stands where you pointed, and stays until you call it.",
            "shadow": "Its shadow is on the screen now, and moves when it moves. Nearer the lantern it grows; off to one side it slides.",
            "notice": "Your companion stops and looks up at the mural. A flock of birds, and one of them missing.",
            "close": "The gap in the flock glows. A bird's shadow, nearly where it belongs.",
            "wrong": "Its shadow stands on the ground. The missing bird is in the air. It would need wings.",
            "holding": "The shadow holds still in the gap, and the paper warms round it.",
            "called": "Your companion trots back to you. Tap the lit ground to stand it in the light again.",
            "let_go": "Your companion lets the stage go and comes to walk with you again.",
        },
        "reveal_line": "The shadow settles into the gap like a bird coming home, and ink spreads through the paper to keep it. A door in the cliff swings open on warm light, and something small is waiting on its threshold.",
    },
    "found_line": "The mural was never missing a bird, only a shadow, and yours was the right one to lend. The little paper bird goes home with you.",
    "home_line": "Something has changed at home.",
    "qualities": ["warm", "old", "glowing"],
    "keepsake": {
        "id": "paper_bird_kept", "type": "kept_paper_bird", "color": [1.0, 0.76, 0.30], "label": "a paper bird on a stick",
        "line": "A bird cut from a single sheet of paper. Hold it up to the lamp and it throws a bird on the wall, and your companion, in whatever shape, watches it fly.",
        "temperament": {"curiosity": 0.8, "energy": 0.5, "clinginess": 0.4},
    },
}

BUILDINGS = [{
    "id": "screen", "view": "shadow_screen", "rect": [-FACE_HW, BASE_Y - SCREEN_DEPTH, FACE_HW * 2, SCREEN_DEPTH], "h": FACE_H,
    "lantern": list(LANTERN), "door": dict(DOOR),
}]

PATHS = []


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "lanternfold",')
out.append('\t"intro": %s,' % json.dumps("A world cut from paper, and lit by one great lantern. Everything throws a shadow here, and the cliff keeps them. Follow the lit posts north, to where the light gathers."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": true, "spacing": 120, "inset": 24, "jitter": 34, "rows": 2, "row_gap": 60 },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.95, 0.72, 0.42],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [\n%s\n\t],' % block(PONDS))
out.append('\t"paths": [],')
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
# the projection: the spot's shadow must land on the face, at the scale the authoring assumed
s_spot = D / (LANTERN[1] - SPOT[1])
x_spot = LANTERN[0] + (SPOT[0] - LANTERN[0]) * s_spot
assert abs(s_spot - SPOT_SCALE) < 0.05 and abs(x_spot - SPOT_X_ON_FACE) < 3.0, (s_spot, x_spot)
assert -FACE_HW + 150 < x_spot < FACE_HW - 150, "the gap bird has to leave room for the flock on both sides"
v_top = (HOVER + 24) * s_spot
assert v_top < FACE_H - 6, "the gap bird's top (%.0f) must fit the face (%d)" % (v_top, FACE_H)
assert SPOT[1] > BASE_Y + 40 and SPOT[1] < LANTERN[1] - 40, "the spot lies on the lit stage"
# the door and the secret sit on the face's foot, clear of the flock's ground and inside the screen
assert abs(DOOR["x"]) + DOOR["w"] < FACE_HW - 10
assert abs(SECRET_POS[0]) < FACE_HW and SECRET_POS[1] > BASE_Y
# nothing solid stands on the lit stage except the lantern and the footlights at its edges
for p in d["props"]:
    x, y = p["position"]
    if in_stage(x, y) and p["id"] not in ("great_lantern",) and not p["id"].startswith("footlight_"):
        raise AssertionError("a prop stands on the stage: %s" % p["id"])
for t in d["trees"]:
    assert not in_stage(t[0], t[1]), "a tree stands on the stage"
    assert math.hypot(t[0] - SECRET_POS[0], t[1] - SECRET_POS[1]) >= 89, "a tree stands at the door"
for pd in PONDS:
    for sp in [SPOT, SECRET_POS, LANTERN]:
        assert math.hypot(sp[0] - pd["center"][0], sp[1] - pd["center"][1]) > pd["radius"] + 40, "a landmark sits in a pond"
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("props:", len(d["props"]), "| trees:", kinds, "| spot:", SPOT, "| lantern:", LANTERN, "| D:", D)
for path in ["server/priv/world_seeds/lanternfold.json", "pokepals/tests/world_fixtures/lanternfold.json"]:
    open(path, "w").write(text)
print("wrote both files")
