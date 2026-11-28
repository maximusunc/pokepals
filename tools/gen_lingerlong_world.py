#!/usr/bin/env python3
"""Generate LINGERLONG, the plaza in the sky, as a world spec.

A marble plaza floating in a pastel sky where it is always the same late afternoon (3200 x 3400). It is the
game's hangout world: the least puzzle and the most "a place to be with friends", so the middle of it is open
floor, kept clear for a crowd. Its story: Lingerlong was built as the place to meet. Everyone said "see you
there", and then everyone was a little late, so the plaza decided to wait, and has kept the same golden
afternoon going ever since so nobody would miss it.

The ground is ONE shader (PlazaGround, the spec's `plaza` block plus the art block's ground entity, render
"plaza"): polished marble checks inside the floors, a still pool, and everywhere else the sky, with clouds
drifting below. You can only stand on a floor or in the pool (PlazaRealm fences the union of them).

Regions, south to north: the Arrival Steps (where you come in), the Fountain Court with the wishing fountain
in its middle, the Palm Court (west) and the Gallery of Nobodies (east), the Pool Deck, and the Pool, whose
far edge is the edge of the world. Five arches stand about the plaza, and each is a door to exactly where you
already are. Except the Late Arch, which stands in the pool and runs a little late: it opens on the evening
the plaza has been saving, a little terrace floating on its own far to the north.

Its one SECRET (reveal type "doorway"): the place card on the table for two, on that terrace. The way there is
the Late Arch (the `doorway` block; the mechanic itself comes later).

Everything is hand-authored and symmetric, because it is architecture, not scatter. Standing art's foot lines
come from gates-of-elyra/data/ll_details.json (the art's reflection margin) when it exists.

Art: gates-of-elyra/tools/gen_lingerlong.py. Writes the server seed and the client test fixture.
Run from the repo root:  python3 tools/gen_lingerlong_world.py
"""
import json
import math
import os

S = "res://assets/sprites/"
BOUNDS_MIN = (-1600, -2200)
BOUNDS_MAX = (1600, 1200)
PLAYER_SPAWN = [0, 1010]
COMPANION_SPAWN = [-34, 1036]
PORTALS = [
    {"id": "lingerlong_way_home", "type": "portal", "position": [0, 1080], "color": [0.98, 0.78, 0.86], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

# ── colours (the contract's palette) ────────────────────────────────────────────────────────────────
def hexc(h, a=None):
    h = h.lstrip("#")
    c = [round(int(h[i:i + 2], 16) / 255.0, 3) for i in (0, 2, 4)]
    return c + [a] if a is not None else c


ROSE, MINT, LILAC, PEACH, DUSK = hexc("#f3c9d3"), hexc("#bfe6d8"), hexc("#d9cdf5"), hexc("#fbd9bf"), hexc("#8f86c9")
MARBLE, BRASS, CUSHION, PEARL = hexc("#f6efe6"), hexc("#e9c46a"), hexc("#f29bb5"), hexc("#fff6e6")

# ── the floors and the pool (x0, y0, x1, y1) ────────────────────────────────────────────────────────
FLOORS = [
    ("fountain_court", (-900, -300, 900, 900), ROSE),
    ("arrival_steps", (-260, 900, 260, 1120), ROSE),
    ("palm_court", (-1380, -200, -900, 620), PEACH),
    ("gallery_of_nobodies", (900, -200, 1380, 620), LILAC),
    ("pool_deck", (-1100, -460, 1100, -300), MINT),
    ("evening_terrace", (-200, -2000, 200, -1760), DUSK),
]
POOL = (-1100, -1000, 1100, -460)
TERRACE = FLOORS[5][1]
EVENING = {"rect": [TERRACE[0] - 360, TERRACE[1] - 200, TERRACE[2] + 360, TERRACE[3] + 260], "from_y": -1500}
PLAZA = {
    "tile": 40,
    "edge_radius": 4.0,
    "floors": [{"id": f, "rect": list(r), "tile_b": c} for f, r, c in FLOORS],
    "pool": {"rect": list(POOL)},
    "evening": EVENING,
}

REGIONS = [
    ("arrival_steps", (-260, 900), (260, 1200), PEACH),
    ("fountain_court", (-900, -300), (900, 900), ROSE),
    ("palm_court", (-1380, -200), (-900, 620), PEACH),
    ("gallery_of_nobodies", (900, -200), (1380, 620), LILAC),
    ("pool_deck", (-1100, -460), (1100, -300), MINT),
    ("the_pool", (-1100, -1000), (1100, -460), [0.66, 0.9, 0.94]),
    ("evening_terrace", (-200, -2000), (200, -1760), DUSK),
]

# ── standing art: sizes (world px) and foot lines ───────────────────────────────────────────────────
# The baked floor reflection hangs below each standing sprite's foot; ll_details.json says how far (world px
# from the image's bottom edge up to the foot line). Until the art lands, a guess of about a seventh of its height.
SIZES = {
    "ll_palm_a_trunk": (64, 112), "ll_palm_b_trunk": (64, 112), "ll_palm_c_trunk": (64, 112),
    "ll_great_palm_trunk": (112, 180), "ll_column": (28, 92), "ll_column_broken": (28, 44),
    "ll_arch": (96, 120), "ll_plinth": (36, 28), "ll_lamp": (20, 72), "ll_lamp_lit": (20, 72),
    "ll_umbrella": (60, 72), "ll_fountain_base": (176, 96), "ll_fountain_top": (176, 150),
    "ll_bench": (56, 28), "ll_lounger": (28, 52), "ll_planter": (36, 36), "ll_fern_pot": (24, 30),
    "ll_plaque": (22, 26), "ll_urn": (22, 30), "ll_pool_rail": (20, 26), "ll_ball": (20, 20),
    "ll_table_set": (48, 40), "ll_chair": (20, 30), "ll_cushion": (22, 12), "ll_place_card": (12, 10),
}
DETAILS_PATH = "gates-of-elyra/data/ll_details.json"
DETAILS = json.load(open(DETAILS_PATH)) if os.path.exists(DETAILS_PATH) else {}
GUESSED = []


def foot(stem):
    if stem in DETAILS and "foot" in DETAILS[stem]:
        return float(DETAILS[stem]["foot"])
    GUESSED.append(stem)
    if stem in ("ll_ball", "ll_place_card"):
        return 0.0
    return float(round(SIZES[stem][1] / 7.0))


def height(stem):
    if stem in DETAILS and "h" in DETAILS[stem]:
        return float(DETAILS[stem]["h"])
    return float(SIZES[stem][1])


# ── the fountain and the arches ─────────────────────────────────────────────────────────────────────
FOUNTAIN_C = (0, 240)
FOUNTAIN = {"id": "wishing_fountain", "center": list(FOUNTAIN_C), "radius": 72}
# The basin is a wide oval seen at a slant, so it blocks as a flat capsule (a fence with nothing drawn), not a
# circle of 72: a circle would keep you so far off that the fountain could not be examined from anywhere.
FENCES = [{"from": [FOUNTAIN_C[0] - 50, FOUNTAIN_C[1] - 4], "to": [FOUNTAIN_C[0] + 50, FOUNTAIN_C[1] - 4], "thickness": 64}]

ARCH_W, ARCH_DOOR, ARCH_DEPTH = 96, 52, 12
ARCHES = [
    ("promenade_arch", (0, 640), None),
    ("palm_arch", (-1140, -60), None),
    ("gallery_arch", (1140, -60), None),
    ("deck_arch", (-700, -380), None),
    ("late_arch", (620, -900), "dusk"),
    ("return_arch", (100, -1812), "noon"),   # the terrace's way back: east of the table, clear of it (see the doorway)
]


def arch(id, pos, view):
    x, y = pos
    leg = (ARCH_W - ARCH_DOOR) // 2
    b = {"id": id, "view": "arch", "rect": [x - ARCH_W // 2, y - ARCH_DEPTH, ARCH_W, ARCH_DEPTH], "h": 120,
         "solid_rects": [[x - ARCH_W // 2, y - ARCH_DEPTH, leg, ARCH_DEPTH], [x + ARCH_DOOR // 2, y - ARCH_DEPTH, leg, ARCH_DEPTH]]}
    if view:
        b["picture"] = view
    return b


BUILDINGS = [arch(*a) for a in ARCHES]
# ── the doorway: the Late Arch's secret way (DoorwayGate / DoorwayDirector) ─────────────────────────────
# One arch in the pool shows the evening in its doorway. Walk through it yourself and you come out the other side;
# send your companion (tap the arch, or Go look near it) and it trots to the threshold, sniffs, and steps into the
# picture, and while it waits in there the doorway is open: step in from the front and you are both on the terrace
# (`through`). The terrace's arch (`back_at`, showing the afternoon) takes you back (`back_to`) from either side,
# always. Every number is the gate's; `lines` are what gets said.
DOORWAY = {
    "arch": "late_arch", "at": [620, -900], "through": [14, -1834], "back_arch": "return_arch",
    "back_at": [100, -1812], "back_to": [620, -860],
    "beside": [-22, 14],                     # where the companion lands, from you, on either crossing
    "inside_at": [-7, -12], "inside_scale": 0.5,   # where it stands in the picture (arch space, from its foot), how small
    "ask_range": 380, "tap_radius": 48, "threshold": 18, "reach": 10,
    "go_speed": 92, "run_speed": 128, "run_distance": 240, "go_patience": 8, "pet_pause": 2.5,
    "sniff_low": 1.8, "sniff_high": 1.0, "step_seconds": 1.6, "vanish": 0.3,
    "hold_low": 7.0, "hold_high": 16.0, "out_seconds": 1.4, "cooldown": 1.2,
    "door_half_width": 20, "line": 4, "step_max": 48,
    "notice_range_low": 260, "notice_range_high": 560, "notice_cooldown_low": 16, "notice_cooldown_high": 7, "notice_hold": 2.4,
    "lines": {
        "notice": "Your companion keeps looking at the arch out in the pool. There's an evening in it.",
        "set_off": "Your companion sets off for the arch in the pool.",
        "busy": "Your companion is already on its way to the arch.",
        "sniff": "It sniffs at the doorway, ears up.",
        "inside": "Your companion steps into the picture and turns to look back at you. The door is open.",
        "came_out": "Your companion trots back out of the evening and finds you. Ask again whenever you like.",
        "called_out": "Your companion hops back out of the picture and comes to you.",
        "called_off": "Your companion leaves the arch for now and comes to you.",
        "lost_way": "Your companion can't find its way to the arch from here.",
        "plain_through": "You come out the other side, back in the pool. The evening stays in the picture.",
        "through": "You step through after it, into the evening.",
        "back": "You step back into the afternoon. It waited for you too.",
    },
}

# ── trees: [x, y, kind] (palms, columns, busts on plinths, lamps, parasols) ──────────────────────────
TREES = []
LANDMARKS = []


def tree(x, y, kind):
    TREES.append([x, y, kind])


def mirror(x, y, kind):
    tree(-x, y, kind)
    tree(x, y, kind)


PALMS = ["ll_palm_a", "ll_palm_b", "ll_palm_c"]
# the promenade: an avenue of palms from the arrival steps up to the fountain, lamps between them
for i, y in enumerate([1070, 950, 830, 710, 570, 450]):
    mirror(200, y, PALMS[i % 3])
for y in [1010, 890, 770, 510]:
    mirror(200, y, "ll_lamp")
# the court's four corners hold the great palms; lamps along its edges, clear of the joins to the wings
for x, y in [(-820, -220), (820, -220), (-820, 820), (820, 820)]:
    LANDMARKS.append({"type": "ll_great_palm", "position": [x, y]})
for x in [300, 600]:
    mirror(x, -270, "ll_lamp")
    mirror(x + 120 if x == 300 else x + 20, 870, "ll_lamp")
for y in [-120, 700]:
    mirror(870, y, "ll_lamp")
# the Palm Court: a palm at each corner, two parasols down the middle
for x, y in [(-1330, -150), (-950, -150), (-1330, 570), (-950, 570)]:
    tree(x, y, PALMS[(x + y) % 3])
for y in [150, 420]:
    tree(-1140, y, "ll_umbrella")
tree(-1350, 290, "ll_lamp")
# the Gallery of Nobodies: four busts floating over their plinths, a column at the back corners, one broken
BUSTS = [("ll_bust_a", (1040, 170)), ("ll_bust_b", (1240, 170)), ("ll_bust_c", (1040, 410)), ("ll_bust_d", (1240, 410))]
for kind, (x, y) in BUSTS:
    tree(x, y, kind)
tree(1340, -150, "ll_column")
tree(940, -150, "ll_column")
tree(1340, 570, "ll_column_broken")
tree(940, 570, "ll_column")
tree(1350, 290, "ll_lamp")
# the Pool Deck: parasols over pairs of loungers, lamps at the ends and either side of the middle (kept open)
DECK_PARASOLS = [-950, -420, 420, 950]
for x in DECK_PARASOLS:
    tree(x, -326, "ll_umbrella")
for x in [1070, 280]:
    mirror(x, -316, "ll_lamp")
# the evening terrace: lamps lit at its corners
for x, y in [(-176, -1980), (176, -1980), (-176, -1776), (176, -1776)]:
    tree(x, y, "ll_lamp_lit")

# ── props ───────────────────────────────────────────────────────────────────────────────────────────
PROPS = []
SEATS = []


def prop(id, type, pos, color, label, lore=None, tags=None, solid=None, radius=None):
    p = {"id": id, "type": type, "position": [round(pos[0]), round(pos[1])], "color": [round(c, 3) for c in color], "label": label}
    if tags:
        p["tags"] = tags
    if lore:
        p["interactive"] = True
        p["lore"] = lore
    if solid is not None:
        p["solid"] = solid
    if radius is not None:
        p["collision_radius"] = radius
    PROPS.append(p)
    return p


def seat(id, at, face, off=None):
    """A seat: `at` is where a sitter stands (its anchor, inside the furniture's collision), `face` the way they look,
    `off` where they step off to when they get up (clear of the furniture; a step south of the anchor if not given)."""
    fx, fy = face
    n = math.hypot(fx, fy) or 1.0
    if off is None:
        off = (at[0], at[1] + 22)
    SEATS.append({"id": id, "at": [round(at[0]), round(at[1])], "face": [round(fx / n, 3), round(fy / n, 3)],
                  "off": [round(off[0]), round(off[1])]})


def bench(id, x, y, lore=None):
    """A bench: drawn low, blocks as a short capsule (so its ends don't stop you dead), two seats facing the fountain."""
    prop(id, "ll_bench", (x, y), CUSHION, "a bench", lore, solid=False)
    FENCES.append({"from": [x - 16, y - 7], "to": [x + 16, y - 7], "thickness": 14})
    fx, fy = FOUNTAIN_C[0] - x, FOUNTAIN_C[1] - y
    face = (fx, fy) if math.hypot(fx, fy) < 400 else (0, 1)
    for k, dx in (("a", -12), ("b", 12)):
        # you get up off the bench's front (south), or off its back when you were facing north over it
        off_y = y - 24 if face[1] < -0.3 * math.hypot(*face) else y + 10
        seat("%s_%s" % (id, k), (x + dx, y - 6), face, (x + dx, off_y))


def lounger(id, x, y, face, lore=None):
    prop(id, "ll_lounger", (x, y), CUSHION, "a lounger", lore, solid=False)
    FENCES.append({"from": [x, y - 36], "to": [x, y - 10], "thickness": 18})
    seat(id, (x, y - 20), face, (x, y + 10) if face[1] >= 0 else (x, y - 56))


# The court: benches ring the fountain (all but straight south, where you walk up to it), the plaque in that gap.
BENCH_LORE = [
    "A bench facing the fountain. The cushion is warm, as if someone has only just got up. Nobody has.",
    "A good bench for waiting. It knows. It has done a great deal of waiting with people.",
]
for i, deg in enumerate([0, 45, 135, 180, 225, 270, 315]):
    a = math.radians(deg)
    bx = FOUNTAIN_C[0] + math.cos(a) * 150
    by = FOUNTAIN_C[1] + math.sin(a) * 150 + 10
    bench("fountain_bench_%d" % (i + 1), round(bx), round(by), BENCH_LORE[i % 2] if i in (1, 4) else None)
prop("brass_plaque", "ll_plaque", (0, 392), BRASS, "a brass plaque",
     "A brass plaque, polished by a great many thumbs. It says: 'LINGERLONG. Built as the place to meet. Five doors, "
     "and every one of them leads here. One of them leads here later.'", tags=["brass", "words"], solid=True, radius=6)
prop("wishing_fountain", "ll_fountain", FOUNTAIN_C, MARBLE, "the wishing fountain",
     "The wishing fountain. The water is warm and very clear, and the bottom of the basin glitters with coins from "
     "everywhere. It remembers every wish. It has never told anyone a single one.", tags=["water", "old", "wishes"], solid=False)
# urns where the promenade meets the court, planters along the court's south edge
for x in (-120, 120):
    prop("promenade_urn_%s" % ("w" if x < 0 else "e"), "ll_urn", (x, 880), MARBLE, "an urn", solid=True, radius=8)
for i, x in enumerate([-720, -520, 520, 720]):
    prop("court_planter_%d" % (i + 1), "ll_planter", (x, 880), MARBLE, "a planter of ferns", solid=True, radius=15)
prop("court_planter_ne", "ll_planter", (700, -260), MARBLE, "a planter of ferns",
     "Ferns, very green and very content. Somebody waters them. You have never seen who.", solid=True, radius=15)
prop("court_planter_nw", "ll_planter", (-700, -260), MARBLE, "a planter of ferns", solid=True, radius=15)

# The Palm Court: two loungers either side of each parasol, planters along the west edge, fern pots by the arch.
for j, y in enumerate([150, 420]):
    for side, dx in (("w", -62), ("e", 62)):
        lounger("palm_lounger_%d%s" % (j + 1, side), -1140 + dx, y + 30, (0, 1),
                "A lounger under a pink parasol. It is exactly the right amount of shade." if (j, side) == (0, "w") else None)
for i, y in enumerate([20, 290, 520]):
    if y != 290:
        prop("palm_planter_%d" % (i + 1), "ll_planter", (-1350, y), MARBLE, "a planter of ferns", solid=True, radius=15)
for x in (-1210, -1070):
    prop("palm_fern_%d" % (1 if x < -1140 else 2), "ll_fern_pot", (x, -52), MARBLE, "a fern in a pot", solid=True, radius=8)
prop("palm_court_sign", "ll_plaque", (-1000, 300), BRASS, "a little brass sign",
     "THE PALM COURT. 'Please take your time.' Underneath, smaller: 'You can't not, here.'", solid=True, radius=6)

# The Gallery of Nobodies: the four busts are examined through lore points at their plinths (drawn by the
# trees above, so nothing is drawn for these), urns by the walls, a sign by the arch.
BUST_LORE = {
    "ll_bust_a": ("The First to Arrive",
                  "THE FIRST TO ARRIVE, says the plinth. A calm face with a laurel. Early, and not the least bit smug about it. "
                  "It has been keeping an eye on the door for everyone else."),
    "ll_bust_b": ("Whoever Waved Back",
                  "WHOEVER WAVED BACK. A face under a sun hat, eyes closed, mid-smile. You waved at someone across a square once, "
                  "and they waved back, and neither of you ever found out who the other was. This is them. Or it's you."),
    "ll_bust_c": ("Someone's Friend",
                  "SOMEONE'S FRIEND. A scarf, a kind face. Not anybody's friend in particular. Everybody has one of these, and "
                  "the plaza thought they deserved a statue."),
    "ll_bust_d": ("The One Who Saved a Seat",
                  "THE ONE WHO SAVED A SEAT. A small fox-like creature, ears up, eyes closed, perfectly patient. Your companion "
                  "looks at it for a long moment, then sits down very straight beside the plinth."),
}
for kind, (x, y) in BUSTS:
    title, lore = BUST_LORE[kind]
    prop("bust_" + kind[-1], "ll_bust_lore", (x, y + 2), MARBLE, "a bust: %s" % title, lore, tags=["statue", "old"], solid=False)
for i, (x, y) in enumerate([(940, 290), (1340, 40), (940, 40)]):
    prop("gallery_urn_%d" % (i + 1), "ll_urn", (x, y), MARBLE, "an urn", solid=True, radius=8)
prop("gallery_sign", "ll_plaque", (1000, -40), BRASS, "a little brass sign",
     "THE GALLERY OF NOBODIES. 'None of these people are anyone in particular. Please do not touch the busts. They are "
     "ticklish.'", solid=True, radius=6)
for x in (1070, 1210):
    prop("gallery_fern_%d" % (1 if x < 1140 else 2), "ll_fern_pot", (x, -52), MARBLE, "a fern in a pot", solid=True, radius=8)

# The Pool Deck: a pair of loungers under each parasol, looking out over the water; ladder rails into the pool.
for x in DECK_PARASOLS:
    for side, dx in (("w", -34), ("e", 34)):
        lounger("deck_lounger_%d%s" % (DECK_PARASOLS.index(x) + 1, side), x + dx, -318, (0, -1),
                "A lounger facing the water. From here the pool runs all the way to the sky and stops." if (x, side) == (420, "e") else None)
for x in (-220, 220):
    prop("pool_rail_%s" % ("w" if x < 0 else "e"), "ll_pool_rail", (x, -466), [0.86, 0.9, 0.96], "a chrome rail",
         "A shiny ladder rail into the pool. The pool is only ankle deep. The rail is here for the look of the thing." if x < 0 else None,
         solid=False)
for i, x in enumerate([-1060, 1060]):
    prop("deck_planter_%d" % (i + 1), "ll_planter", (x, -400), MARBLE, "a planter of ferns", solid=True, radius=15)
# pool-edge seats: sit on the coping with your feet in the water
for i, x in enumerate([-820, -560, -120, 120, 560, 820]):
    seat("pool_edge_%d" % (i + 1), (x, -456), (0, -1))

# The Pool: a beach ball adrift, a sign at the far edge's corner.
prop("beach_ball", "ll_ball", (-300, -720), [0.98, 0.62, 0.74], "a beach ball",
     "A beach ball, drifting on the still water. Nobody remembers bringing it. It has never once drifted off the edge.",
     tags=["toy", "round"], solid=False)

# The evening terrace: the table for two, a chair, a floor cushion for whoever doesn't want a chair, fern pots. The
# table stands west of the middle and the return arch east of it, nearer the front, so nothing hides the table.
TABLE = (-56, -1890)
prop("terrace_table", "ll_table_set", TABLE, MARBLE, "a table for two",
     "A small round table laid for two, with a candle already lit. One place has a chair. The other has a cushion on the "
     "floor, just the right height for someone with four legs.", tags=["table", "evening"], solid=False)
FENCES.append({"from": [TABLE[0] - 10, TABLE[1] - 12], "to": [TABLE[0] + 10, TABLE[1] - 12], "thickness": 22})
prop("terrace_chair", "ll_chair", (TABLE[0] - 40, TABLE[1] + 2), MARBLE, "a chair", solid=False)
prop("terrace_cushion", "ll_cushion", (TABLE[0] + 40, TABLE[1] + 6), CUSHION, "a floor cushion", solid=False)
seat("terrace_chair", (TABLE[0] - 40, TABLE[1] - 2), (1, 0))
seat("terrace_cushion", (TABLE[0] + 40, TABLE[1] + 2), (-1, 0))
for x in (-150, 150):
    prop("terrace_fern_%s" % ("w" if x < 0 else "e"), "ll_fern_pot", (x, -1940), MARBLE, "a fern in a pot", solid=True, radius=8)

PROPS.sort(key=lambda p: (p["position"][1], p["position"][0]))   # WorldArt draws props in order: far ones first

# ── the secret: the place card on the table for two ────────────────────────────────────────────────
SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Lingerlong'). reveal.type 'doorway': the "
                  "Late Arch in the pool (the 'doorway' block) runs a little late, and once it opens on the evening the plaza "
                  "has been saving, walking through it sets you on the evening terrace, where the place card waits on the table "
                  "for two. The arch, the evening and the crossing all happen on the player's own screen, so the server only "
                  "checks 'this world, standing at it'.")
SECRET = {
    "id": "lingerlong_place_card",
    "position": [-48, -1888],
    "radius": 120.0,
    "prop": {"type": "ll_place_card", "color": [1.0, 0.97, 0.9], "label": "a place card", "tags": ["small", "made", "kind", "evening"]},
    "lore": "A little folded card on the table, propped against the candle. In neat handwriting it says: 'Saved for you. "
            "Sorry we're late.' There is a second name under yours, smaller, and your companion seems to know it is theirs.",
    "reveal": {
        "type": "doorway",
        "arch": "late_arch",
        "reveal_line": "The table is laid, the candle is lit, and there is a card with your name on it.",
    },
    "found_line": "You tuck the place card away. The plaza saved you an evening, and now you have the proof.",
    "home_line": "Something has changed at home.",
    "qualities": ["warm", "quiet", "crafted"],   # three of the home's eight core qualities
    "keepsake": {
        "id": "lingerlong_place_card_kept", "type": "kept_place_card", "color": [1.0, 0.97, 0.9], "label": "a place card on a little stand",
        "line": "The place card from the terrace, on a little brass stand. Your companion likes to sit beside it, as if it is still being saved a seat.",
        "temperament": {"curiosity": 0.4, "energy": 0.3, "clinginess": 0.8},
    },
}

# ── the look ────────────────────────────────────────────────────────────────────────────────────────
F = {stem: foot(stem) for stem in SIZES}


def palm_kind(v):
    return {"render": "sprite", "sway": 0.45, "foot": F["ll_palm_%s_trunk" % v],
            "trunk": S + "ll_palm_%s_trunk@2x.png" % v, "canopy": S + "ll_palm_%s_canopy@2x.png" % v}


def bust_kind(v):
    # a bust floats over its plinth: the plinth is the "trunk" (standing, reflected), the bust the "canopy", lifted
    # `height` over the plinth's top and bobbing `bob` px every `period` seconds (TreeView's float)
    return {"render": "sprite", "sway": 0.0, "foot": F["ll_plinth"], "trunk": S + "ll_plinth@2x.png", "canopy": S + "ll_bust_%s@2x.png" % v,
            "float": {"rest": height("ll_plinth") - F["ll_plinth"], "height": 14, "bob": 3, "period": 5.0, "shadow": 13}}


ENTITIES = {
    "ground": {
        "render": "plaza",
        "marble": S + "ll_marble.png", "caustics": S + "ll_caustics.png", "clouds": S + "ll_clouds.png",
        "tile_a": hexc("#fbf4ec"), "vein": hexc("#e6d8cf"), "grout": hexc("#e3cfd2"),
        "rim_lit": hexc("#fff8f0"), "rim_shade": hexc("#b9a7d6"), "thickness": 14.0,
        "sky": [hexc("#8fb8e8"), hexc("#c9b6f0"), hexc("#f7b7d2"), hexc("#ffd3a8"), hexc("#fff0c9")],
        "evening_sky": [hexc("#2b2a5c"), hexc("#2b2a5c"), hexc("#6a4c93"), hexc("#e07a9a"), hexc("#ffb482")],
        "sun": hexc("#fff6dc"), "sun_at": [-240, -1240], "sun_radius": 46.0,
        "water_deep": hexc("#7fd6d8"), "water_shallow": hexc("#a9e6ef"), "cloud": hexc("#fff4ea"),
        "horizon_fade": 220.0, "ripple_spacing": 22.0,
    },
    "understory": {"density": 0},
    "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 0}, "leaves": {"rate": 0},
                     "clouds": {"count": 0, "alpha": 0.0, "speed": 0}},
    "tree": palm_kind("a"),
    "ll_palm_a": palm_kind("a"), "ll_palm_b": palm_kind("b"), "ll_palm_c": palm_kind("c"),
    "ll_great_palm": {"render": "sprite", "sway": 0.3, "foot": F["ll_great_palm_trunk"],
                      "trunk": S + "ll_great_palm_trunk@2x.png", "canopy": S + "ll_great_palm_canopy@2x.png"},
    "ll_column": {"render": "sprite", "sway": 0.0, "foot": F["ll_column"], "sprite": S + "ll_column@2x.png"},
    "ll_column_broken": {"render": "sprite", "sway": 0.0, "foot": F["ll_column_broken"], "sprite": S + "ll_column_broken@2x.png"},
    "ll_lamp": {"render": "sprite", "sway": 0.0, "foot": F["ll_lamp"], "sprite": S + "ll_lamp@2x.png"},
    "ll_lamp_lit": {"render": "sprite", "sway": 0.0, "foot": F["ll_lamp_lit"], "sprite": S + "ll_lamp_lit@2x.png",
                    "glow": [1.0, 0.886, 0.627, 0.9], "glow_radius": 22.0, "glow_y": -56.0},
    "ll_umbrella": {"render": "sprite", "sway": 0.15, "foot": F["ll_umbrella"], "sprite": S + "ll_umbrella@2x.png"},
    "ll_bust_a": bust_kind("a"), "ll_bust_b": bust_kind("b"), "ll_bust_c": bust_kind("c"), "ll_bust_d": bust_kind("d"),
    # the arches (ArchView) and the fountain (FountainView): their art and foot lines
    "arch": {"frame": S + "ll_arch@2x.png", "foot": F["ll_arch"],
             "pictures": {"dusk": S + "ll_arch_view_dusk@2x.png", "noon": S + "ll_arch_view_noon@2x.png"}},
    "fountain": {"base": S + "ll_fountain_base@2x.png", "top": S + "ll_fountain_top@2x.png",
                 "foot": F["ll_fountain_base"], "top_foot": F["ll_fountain_top"],
                 "water": [0.78, 0.94, 0.98], "jet_height": 46.0, "spout_y": -112.0},
    "props": {
        "extra_types": ["ll_bench", "ll_lounger", "ll_planter", "ll_fern_pot", "ll_plaque", "ll_urn", "ll_pool_rail", "ll_ball",
                        "ll_table_set", "ll_chair", "ll_cushion", "ll_place_card"],
        # drawn by something else: the fountain by FountainView, a bust by its tree (these are only its words)
        "unseen": ["ll_fountain", "ll_bust_lore"],
        "foot": {t: F[t] for t in ["ll_bench", "ll_lounger", "ll_planter", "ll_fern_pot", "ll_plaque", "ll_urn", "ll_pool_rail",
                                   "ll_ball", "ll_table_set", "ll_chair", "ll_cushion", "ll_place_card"]},
        # the beach ball bobs on the water; the place card sits up on the table top (a float that doesn't bob)
        "float": {"ll_ball": {"height": 0, "bob": 1.5, "period": 3.6},
                  "ll_place_card": {"height": 21, "bob": 0, "period": 1.0}},
    },
    "prop_lights": {"ll_table_set": {"radius": 30, "y": -24, "alpha": 0.30}},
}
ART = {
    "palette": {
        "ground_top": hexc("#fbf4ec"), "ground_bottom": hexc("#f3c9d3"),
        "foliage_dark": hexc("#3fae9a"), "foliage_mid": [0.4, 0.78, 0.66], "foliage_light": hexc("#7fd8b4"),
        "bark": hexc("#c98f7a"), "water": hexc("#7fd6d8"), "rim": [1.0, 1.0, 1.0],
        "shadow": hexc("#b9a7d6"), "grass": hexc("#bfe6d8"), "water_rim": [1.0, 0.98, 0.95, 0.9],
    },
    "light": {"shadow_alpha": 0.14, "rim_strength": 0.3},
    "entities": ENTITIES,
    # one golden late afternoon, held (the plaza decided to wait)
    "daycycle": {"enabled": True, "hold": 0.0, "stops": [
        {"t": 0.0, "tint": [1.0, 0.975, 0.95], "vignette": [0.96, 0.70, 0.80], "vstrength": 0.2},
        {"t": 1.0, "tint": [1.0, 0.975, 0.95], "vignette": [0.96, 0.70, 0.80], "vstrength": 0.2},
    ]},
    # Visitors keep their own pixel look, lit by the afternoon: a warm pastel lift, the dark outline softened to plum.
    "actor_look": {
        "shadow_mult": [0.88, 0.80, 0.98], "shadow_boost": 1.15,
        "light_mult": [1.0, 0.97, 0.94], "light_boost": 1.05,
        "cast": [1.0, 0.80, 0.70], "cast_amount": 0.08,
        "saturation": 0.96,
        "line_glow": [0.55, 0.38, 0.58], "line_amount": 0.45, "line_cut": 0.16, "pulse_speed": 0.0,
    },
}

ATMOSPHERE = {
    "day_tint": [1.0, 0.975, 0.95],
    "vignette": {"strength": 0.2, "color": [0.96, 0.70, 0.80]},
    "wind": {"strength": 1.2, "speed": 0.5},
    "pollen": {"amount": 12, "color": [1.0, 0.94, 0.78]},
    "region_tint_alpha": 0.0,
    "grass": {"max": 0},
}

CROWD = {"cell": 480, "full": 40, "lite": 80}

HEADER = ("LINGERLONG - a marble plaza floating in a pastel sky, always the same late afternoon: the hangout world. "
          "'plaza' is its ground (PlazaGround, one shader; PlazaRealm fences it: you can stand only on a floor or in the pool). "
          "'fountain', 'seats', 'doorway' and 'crowd' are read by the fountain view, sitting, the Late Arch and the crowd "
          "rules. Generated by tools/gen_lingerlong_world.py (art: gates-of-elyra/tools/gen_lingerlong.py) - edit that and re-run, "
          "don't hand-tune positions.")


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


def pretty(obj):
    return json.dumps(obj, indent="\t", ensure_ascii=False).replace("\n", "\n\t")


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": r[3]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "lingerlong",')
out.append('\t"intro": %s,' % json.dumps("A marble plaza in the sky, where it is always the same late afternoon. Everyone's a little late here. The plaza doesn't mind."))
out.append('\t"chopping": false,')
out.append('\t"fishing": false,')
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"music": { "track": "res://assets/music/lingerlong.ogg", "volume_db": -22 },')  # tools/music/scores/lingerlong.score
out.append('\t"border": { "ring": false },')
out.append('\t"collision": %s,' % json.dumps({
    "tree_radius": 12, "great_tree_radius": 20, "pond_blocks": False, "body_radius": 6, "margin": 2,
    "kind_radius": {"ll_lamp": 4, "ll_lamp_lit": 4, "ll_column": 9, "ll_column_broken": 9, "ll_umbrella": 3,
                    "ll_bust_a": 13, "ll_bust_b": 13, "ll_bust_c": 13, "ll_bust_d": 13}}, separators=(", ", ": ")))
out.append('\t"ground_color": %s,' % json.dumps(hexc("#fff0c9")))
out.append('\t"art": %s,' % pretty(ART))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"plaza": %s,' % pretty(PLAZA))
out.append('\t"fountain": %s,' % json.dumps(FOUNTAIN))
out.append('\t"doorway": %s,' % json.dumps(DOORWAY))
out.append('\t"crowd": %s,' % json.dumps(CROWD))
out.append('\t"seats": [\n%s\n\t],' % block(SEATS))
out.append('\t"ponds": [],')
out.append('\t"paths": [],')
out.append('\t"fences": [\n%s\n\t],' % block(FENCES))
out.append('\t"buildings": [\n%s\n\t],' % block(BUILDINGS))
out.append('\t"landmarks": [\n%s\n\t],' % block(LANDMARKS))
out.append('\t"trees": [\n%s\n\t],' % block(TREES))
out.append('\t"props": [\n%s\n\t],' % block(PROPS))
out.append('\t"_secret_comment": %s,' % json.dumps(SECRET_COMMENT))
out.append('\t"secret": %s,' % pretty(SECRET))
out.append('\t"portals": [\n%s\n\t]' % block(PORTALS))
out.append("}")
text = "\n".join(out) + "\n"

# ── validate ─────────────────────────────────────────────────────────────────────────────────────────
d = json.loads(text)
GROUND = [r for _, r, _ in FLOORS] + [POOL]


def on_ground(x, y, rects=GROUND):
    return any(x0 <= x <= x1 and y0 <= y <= y1 for x0, y0, x1, y1 in rects)


def on_floor(x, y):
    return on_ground(x, y, [r for _, r, _ in FLOORS])


ids = [p["id"] for p in d["props"]]
assert len(ids) == len(set(ids)), "duplicate ids"
for p in d["props"]:
    assert bool(p.get("interactive")) == bool(p.get("lore")), "interactive iff lore: %s" % p["id"]
    x, y = p["position"]
    assert on_ground(x, y), "every prop stands on the plaza: %s" % p["id"]
for t in d["trees"] + [lm["position"] for lm in d["landmarks"]]:
    assert on_floor(t[0], t[1]), "every tree stands on a floor: %s" % t
for s in d["seats"]:
    assert on_ground(*s["at"]), "every seat is on the plaza: %s" % s["id"]
    assert on_ground(*s["off"]), "and you get up onto the plaza: %s" % s["id"]
for b in d["buildings"]:
    x, y, w, h = b["rect"]
    assert on_ground(x + w / 2, y + h), "every arch stands on the plaza: %s" % b["id"]
assert on_floor(*PLAYER_SPAWN) and on_floor(*COMPANION_SPAWN), "you arrive on the floor"
assert on_floor(*DOORWAY["through"]) and on_floor(*DOORWAY["back_to"]) is False and on_ground(*DOORWAY["back_to"]), \
    "the doorway sets you down on the terrace, and back in the pool"
assert on_floor(*SECRET["position"]) and abs(SECRET["position"][1] - TERRACE[1]) < 200, "the place card is on the terrace"
# the doorway names the arches where they stand, and the terrace's arch hides nothing on the table
_arch_at = {b["id"]: (b["rect"][0] + b["rect"][2] / 2, b["rect"][1] + b["rect"][3]) for b in d["buildings"]}
assert tuple(DOORWAY["at"]) == _arch_at[DOORWAY["arch"]] and tuple(DOORWAY["back_at"]) == _arch_at[DOORWAY["back_arch"]], \
    "the doorway's arches stand where it says"
bx, by = DOORWAY["back_at"]
for p in d["props"]:
    if p["id"] in ("terrace_table", "terrace_chair", "terrace_cushion"):
        x, y = p["position"]
        w = SIZES[p["type"]][0] / 2
        assert x + w < bx - ARCH_W / 2 - 4 or y > by, "the return arch stands clear of %s" % p["id"]
sx, sy = SECRET["position"]
assert sx + 6 < bx - ARCH_W / 2 - 4, "the return arch stands clear of the place card"
tx, ty = DOORWAY["through"]
assert on_floor(tx, ty) and on_floor(tx + DOORWAY["beside"][0], ty + DOORWAY["beside"][1]), "you both land on the terrace"
assert abs(tx - bx) > DOORWAY["door_half_width"] + 10 or ty > by + 20, "you don't land in the way back"
assert on_ground(DOORWAY["back_to"][0] + DOORWAY["beside"][0], DOORWAY["back_to"][1] + DOORWAY["beside"][1]), "you both land in the pool"
assert by + 30 <= TERRACE[3], "there's room to walk into the return arch from the front"
# the middle of the court stays open: nothing stands either side of the promenade, or north of the bench ring
OPEN = [(-580, -220, -240, 820), (240, -220, 580, 820), (-240, -240, 240, 60)]
for t in d["trees"] + [p["position"] for p in d["props"]]:
    assert not on_ground(t[0], t[1], OPEN), "something stands in the open floor: %s" % (t,)
# symmetric where it says so: the court's trees mirror across x = 0
court = sorted((t[0], t[1], t[2]) for t in d["trees"] if on_ground(t[0], t[1], [FLOORS[0][1], FLOORS[1][1]]))
mirrored = sorted((-x, y, k) for x, y, k in court)
assert [(x, y) for x, y, _ in court] == [(x, y) for x, y, _ in mirrored], "the court is symmetric"
print("props:", len(d["props"]), "| trees:", len(d["trees"]), "| seats:", len(d["seats"]), "| fences:", len(d["fences"]))
if GUESSED:
    print("NOTE: no %s yet, foot lines guessed for %d sprites; re-run once the art lands" % (DETAILS_PATH, len(set(GUESSED))))
for path in ["server/priv/world_seeds/lingerlong.json", "gates-of-elyra/tests/world_fixtures/lingerlong.json"]:
    open(path, "w").write(text)
print("wrote both files")
