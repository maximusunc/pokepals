#!/usr/bin/env python3
"""Generate CLICKTON, the little city made entirely of small colourful bricks, as a world spec.

Everything in Clickton is a brick: the baseplate ground, the roads and pavements (flat plates), the
buildings (courses of brick under studded roofs), the trees, the props, even the visitors, who are
rebuilt out of bricks by the world's `actor_look` (assets/brick_actor.gdshader). There are no
people here and no creatures: only the city, lit and tidy and waiting, and the one thing in it
that is hidden.

The SECRET: one single rainbow brick, set into the front wall of a cottage at the quiet west end of the
Quay Lane row, low down where a hand would reach. Slow bands of every colour swirl through it. `reveal: always`
(it is simply there to be found), claimed by examining it; the brick itself is painted by the building
(BuildingView `inlay`), because a prop in WorldArt would be drawn under the building.

Layout: a DENSE city of tall buildings and narrow lanes, like the Bazaar. The Quay (a promenade over a
studded bay with two piers and a lighthouse) is where you arrive; four lanes run east-west and three
north-south, and every block between them is packed with buildings: a TALL front row facing the lane to its
south, and a LOW back row behind it (a building hides the lane just north of it, so the buildings that stand
south of a lane are kept low). One small square in the middle holds the fountain, the clock tower and a
playground; the skyline of tall towers and the Brickworks stand along the north. Art: pokepals/tools/gen_clickton.py over tools/brickart/bricks.py.

Hand-authored: the street grid, the landmarks, every line of lore, the secret. Procedural (seeded): the
facades of the building rows and the scatter of trees and props in the open lots. Writes the server seed
and the client test fixture. Run from the repo root:  python3 tools/gen_clickton_world.py
"""
import json
import math
import random

random.seed(0xB41C4)

BOUNDS_MIN = (-1000, -760)
BOUNDS_MAX = (1000, 760)
PLAYER_SPAWN = [0, 592]
COMPANION_SPAWN = [-34, 614]
PORTALS = [
    {"id": "clickton_way_home", "type": "portal", "position": [110, 602], "color": [1.0, 0.85, 0.3], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

# ── the box of colours ────────────────────────────────────────────────────────────────────────────
def c(r, g, b):
    return [round(r / 255, 3), round(g / 255, 3), round(b / 255, 3)]


RED = c(196, 40, 27)
BLUE = c(13, 105, 171)
YELLOW = c(245, 205, 48)
GREEN = c(40, 127, 70)
ORANGE = c(218, 133, 64)
WHITE = c(242, 243, 243)
TAN = c(215, 197, 153)
PINK = c(255, 152, 220)
LAVENDER = c(167, 131, 200)
TEAL = c(18, 157, 157)
SKY = c(116, 184, 222)
LIME = c(164, 189, 71)
DKGREY = c(99, 95, 98)
GREY = c(163, 162, 165)
BROWN = c(150, 100, 60)
CREAM = c(250, 240, 210)
BLACK = c(40, 44, 52)

WALLS = [RED, ORANGE, YELLOW, GREEN, BLUE, WHITE, TAN, LAVENDER, PINK, TEAL, SKY, LIME]
ROOFS = [DKGREY, RED, BLUE, c(60, 70, 90), BROWN, GREEN, c(120, 60, 50)]
DOORS = [RED, BLUE, GREEN, YELLOW, c(105, 64, 40), TEAL]

# ── the street grid: narrow lanes, packed blocks ──────────────────────────────────────────────────
ROAD_W = 46
WALK = 12
HALF = ROAD_W // 2 + WALK          # 35: from a lane's centre line to the edge of its pavement
H_LANES = {"quay_lane": 480, "high_lane": 140, "clock_lane": -200, "skyline_lane": -540}
V_LANES = [(-500, -760, 560), (500, -760, 560), (0, -760, -200), (0, 140, 560)]    # (x, y0, y1)
AVENUES = sorted({x for x, _, _ in V_LANES})
COLS = [(-990, -535), (-465, -35), (35, 465), (535, 990)]       # between the north-south lanes' pavements
F_D = 110                                                         # a front row's depth
PLATES = []
NOGO = []
LANE_RECTS = []


def rect_of(x0, y0, x1, y1):
    return [int(x0), int(y0), int(x1 - x0), int(y1 - y0)]


def plate(x0, y0, x1, y1, kind, color, solid=False, shimmer=False, nogo=True):
    p = {"rect": rect_of(x0, y0, x1, y1), "kind": kind, "color": color}
    if solid:
        p["solid"] = True
    if shimmer:
        p["shimmer"] = True
    PLATES.append(p)
    if nogo:
        NOGO.append((x0, y0, x1, y1))


PAVE = c(206, 206, 210)
ASPHALT = c(86, 88, 96)
LINE = c(236, 236, 230)
for name, y in H_LANES.items():
    plate(-1000, y - HALF, 1000, y + HALF, "stud", PAVE)
    LANE_RECTS.append((-1000, y - HALF, 1000, y + HALF))
for x, y0, y1 in V_LANES:
    plate(x - HALF, y0, x + HALF, y1, "stud", PAVE)
    LANE_RECTS.append((x - HALF, y0, x + HALF, y1))
for name, y in H_LANES.items():
    plate(-1000, y - ROAD_W // 2, 1000, y + ROAD_W // 2, "road", ASPHALT, nogo=False)
for x, y0, y1 in V_LANES:
    plate(x - ROAD_W // 2, y0, x + ROAD_W // 2, y1, "road", ASPHALT, nogo=False)
for name, y in H_LANES.items():
    x = -980
    while x < 980:
        if all(abs((x + 10) - ax) > HALF + 6 for ax in AVENUES):
            plate(x, y - 1, x + 20, y + 1, "mark", LINE, nogo=False)
        x += 40
    for ax in AVENUES:
        for side in (-1, 1):
            zx = ax + side * (HALF + 5)
            for k in range(4):
                plate(zx - 2, y - ROAD_W // 2 + 4 + k * 10, zx + 2, y - ROAD_W // 2 + 9 + k * 10, "mark", LINE, nogo=False)
for ax, y0, y1 in V_LANES:
    y = y0 + 20
    while y < y1 - 20:
        if all(abs((y + 10) - ry) > HALF + 6 for ry in H_LANES.values()):
            plate(ax - 1, y, ax + 1, y + 20, "mark", LINE, nogo=False)
        y += 40

# the Quay: a promenade, a studded bay, two piers
PROM = c(222, 200, 150)
plate(-1000, 515, 1000, 640, "stud", PROM, nogo=False)
WATER = c(60, 140, 215)
PIER = c(168, 112, 66)
for x0, x1 in [(-1000, -340), (-260, 260), (340, 1000)]:
    plate(x0, 640, x1, 760, "stud", WATER, solid=True, shimmer=True)
for px in (-340, 260):
    plate(px, 640, px + 80, 760, "stud", WATER, solid=True, shimmer=True)     # under the pier's far end
    plate(px, 630, px + 80, 724, "stud", PIER)
# the little square: a tan plaza with a smooth inlay
PLAZA = (-190, -165, 190, 105)
plate(*PLAZA, "stud", c(238, 222, 182), nogo=False)
plate(-160, -140, 160, 80, "flat", c(226, 206, 160), nogo=False)

REGIONS = [
    ("the_quay", (-1000, 515), (1000, 760)),
    ("quay_row", (-1000, 175), (1000, 515)),
    ("the_square", (-200, -175), (200, 115)),
    ("high_street", (-1000, -165), (1000, 175)),
    ("clock_row", (-1000, -505), (1000, -165)),
    ("the_skyline", (-1000, -760), (1000, -505)),
]

# ── buildings ─────────────────────────────────────────────────────────────────────────────────────
BUILDINGS = []


def building(rect, h, wall, roof, **kw):
    b = {"id": "b%d" % (len(BUILDINGS) + 1), "rect": rect, "h": h, "wall": wall, "roof": roof}
    b.update(kw)
    BUILDINGS.append(b)
    NOGO.append((rect[0] - 4, rect[1] - 4, rect[0] + rect[2] + 4, rect[1] + rect[3] + 4))
    return b


def snap(v, n=8):
    return int(round(v / n) * n)


def fill_row(x0, x1, y1, d, kind, h_choices):
    """A packed terrace between x0..x1 whose south walls stand at y1, `d` deep."""
    x = ((x0 + 7) // 8) * 8
    while x < x1 - 60:
        w = snap(random.choice([88, 96, 104, 112, 120, 128, 144]))
        if x1 - (x + w) < 72:
            w = int((x1 - x) // 8) * 8
        wall = random.choice(WALLS)
        roof = random.choice(ROOFS)
        h = random.choice(h_choices)
        opts = {}
        if kind == "front":
            opts = {"door": True, "door_color": random.choice(DOORS), "windows": True}
            if random.random() < 0.65:
                opts["awning"] = random.choice([RED, BLUE, GREEN, YELLOW, ORANGE, TEAL])
            if h >= 120 and random.random() < 0.5:
                opts["tiers"] = [{"inset": 14, "h": random.choice([24, 36, 48]), "wall": random.choice(WALLS)}]
                if random.random() < 0.35:
                    opts["tiers"].append({"inset": 12, "h": 24})
            if random.random() < 0.35:
                opts["antenna"] = True
            if random.random() < 0.3:
                opts["flag"] = random.choice(WALLS)
        elif kind == "back":
            wall = random.choice([GREY, TAN, ORANGE, WHITE, SKY, LIME, c(200, 120, 90)])
            roof = random.choice([DKGREY, BROWN, c(60, 70, 90)])
            opts = {"windows": False}
            if random.random() < 0.4:
                opts["chimney"] = True
        elif kind == "works":
            wall = random.choice([RED, GREY, ORANGE, TAN, BLUE])
            roof = random.choice([DKGREY, c(70, 76, 90), RED])
            opts = {"windows": True, "chimney": random.random() < 0.85,
                    "tiers": [{"inset": 22, "h": random.choice([24, 36]), "wall": random.choice([GREY, DKGREY, TAN])}]}
        elif kind == "tower":
            opts = {"door": random.random() < 0.5, "door_color": random.choice(DOORS), "windows": True,
                    "tiers": [{"inset": 16, "h": random.choice([24, 36, 48]), "wall": random.choice([WHITE, CREAM, SKY])}]}
            if random.random() < 0.5:
                opts["antenna"] = True
            if random.random() < 0.3:
                opts["flag"] = random.choice(WALLS)
        building([x, y1 - d, w, d], h, wall, roof, **opts)
        x += w + random.choice([0, 0, 4])
        x = snap(x, 2)


FRONT_H = [96, 108, 120, 132, 144, 156, 168, 180]
BACK_H = [24, 30, 36]
# the three packed blocks: a tall front row facing the lane to the south, a low back row behind it
BLOCKS = [(480, 175), (140, -165), (-200, -505)]    # (the lane they front, the lane pavement they back onto)
COTTAGE_RECT = [-990, 335, 104, 110]
COTTAGE_CX = COTTAGE_RECT[0] + COTTAGE_RECT[2] // 2
for lane_y, back_edge in BLOCKS:
    fy = lane_y - HALF                           # the front row's south face
    for ci, (cx0, cx1) in enumerate(COLS):
        plaza_block = lane_y == 140
        if plaza_block and ci in (1, 2):
            # the square: only the outer ends of these columns hold buildings
            lo, hi = (cx0, PLAZA[0]) if ci == 1 else (PLAZA[2], cx1)
            fill_row(lo, hi, fy, F_D, "front", FRONT_H)
            fill_row(lo, hi, fy - F_D, fy - F_D - back_edge, "back", BACK_H)
            continue
        if lane_y == 480 and ci == 0:
            fill_row(COTTAGE_RECT[0] + COTTAGE_RECT[2] + 4, cx1, fy, F_D, "front", FRONT_H)
        else:
            fill_row(cx0, cx1, fy, F_D, "front", FRONT_H)
        fill_row(cx0, cx1, fy - F_D, fy - F_D - back_edge, "back", BACK_H)
# the skyline row along the north: a tall backdrop, the Brickworks' chimneys in the east
for ci, (cx0, cx1) in enumerate(COLS):
    fill_row(cx0, cx1, -575, 170, "works" if ci >= 2 else "tower", [168, 180, 192, 204, 216, 240] if ci < 2 else [96, 108, 120, 132])

# The secret's cottage: the westmost house on the Quay Lane, a different colour from the rest. Its front
# wall holds the brick: course ROW down from the wall's top, COL bricks along.
INLAY = {"prop": "secret_rainbow_brick", "row": 6, "col": 1}
COTTAGE = building(COTTAGE_RECT, 54, c(255, 236, 140), RED, door=True, door_color=c(40, 127, 70), roof_style="gable",
                   shutters=c(40, 127, 70), chimney=True, id="crooked_cottage", inlay=INLAY)
BRICK_X = COTTAGE_CX - COTTAGE_RECT[2] // 2 + 16 * INLAY["col"] + 8     # the brick's centre, in the world

# landmarks: the clock tower in the square, the lighthouse on the pier
building([-182, -165, 96, 72], 132, RED, DKGREY, id="clock_tower", door=True, door_color=c(105, 64, 40), windows=True, clock=True,
         tiers=[{"inset": 16, "h": 42, "wall": CREAM, "roof": RED}, {"inset": 14, "h": 24, "wall": YELLOW, "roof": RED}], flag=YELLOW)
building([-320, 676, 40, 36], 108, WHITE, RED, id="lighthouse", windows=True, door=False,
         tiers=[{"inset": 8, "h": 30, "wall": RED, "roof": DKGREY}, {"inset": 6, "h": 18, "wall": YELLOW, "roof": RED}])

# ── props ─────────────────────────────────────────────────────────────────────────────────────────
PROPS = []
TREES = []
LANDMARKS = []
used = set()


def prop(pid, typ, pos, color, label, lore=None, solid=None, r=None, tags=None):
    assert pid not in used, pid
    used.add(pid)
    p = {"id": pid, "type": typ, "position": [int(pos[0]), int(pos[1])], "color": color, "label": label}
    if lore:
        p["interactive"] = True
        p["lore"] = lore
    if tags:
        p["tags"] = tags
    if solid is not None:
        p["solid"] = solid
    if r is not None:
        p["collision_radius"] = r
    PROPS.append(p)
    return p


def blocked(x, y, rad):
    if not (BOUNDS_MIN[0] + 30 < x < BOUNDS_MAX[0] - 30 and BOUNDS_MIN[1] + 30 < y < BOUNDS_MAX[1] - 30):
        return True
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 110:
        return True
    return any(x0 - rad < x < x1 + rad and y0 - rad < y < y1 + rad for x0, y0, x1, y1 in NOGO)


PLACED = []


def scatter(rect, n, rad, fn, tries=3000):
    x0, y0, x1, y1 = rect
    got = 0
    for _ in range(tries):
        if got >= n:
            break
        x, y = random.uniform(x0, x1), random.uniform(y0, y1)
        if blocked(x, y, rad) or any(math.hypot(x - px, y - py) < rad + pr for px, py, pr in PLACED):
            continue
        PLACED.append((x, y, rad))
        fn(round(x), round(y), got)
        got += 1


def in_building(x, y, rad=6):
    return any(b["rect"][0] - rad < x < b["rect"][0] + b["rect"][2] + rad and b["rect"][1] - rad < y < b["rect"][1] + b["rect"][3] + rad for b in BUILDINGS)


# Lamps stand on the south pavement of every lane, hydrants and the like beside them.
for name, y in H_LANES.items():
    for x in range(-940, 960, 120):
        if all(abs(x - ax) > 60 for ax in AVENUES):
            prop("lamp_%s_%d" % (name, x), "brick_lamp", (x, y + HALF - 6), SKY, "a street lamp", solid=True, r=4)
FURNITURE = [("brick_hydrant", RED, "a fire hydrant", "It has never once been used. It is very proud of this, and stands a little straighter than the other hydrants."),
             ("brick_mailbox", BLUE, "a mailbox", "A mailbox. Inside, one letter, addressed to \"Whoever Lives Here\". It says: \"Welcome. It's lovely. Don't mind the corners.\""),
             ("brick_trashcan", DKGREY, "a bin", None),
             ("brick_cone", ORANGE, "a traffic cone", "Somebody put a cone here, years ago, for a reason that has since built itself into the road.")]
k = 0
for name, y in H_LANES.items():
    for x in range(-900, 920, 200):
        x += random.randrange(-24, 24)
        if any(abs(x - ax) < 70 for ax in AVENUES):
            continue
        typ, col, label, lore = FURNITURE[k % len(FURNITURE)]
        k += 1
        prop("furn_%d" % k, typ, (x + 60, y + HALF - 6), col, label, lore if k % 3 == 0 else None, solid=True, r=5)

# The Quay.
prop("welcome_sign", "brick_sign", (-110, 570), YELLOW, "a signpost of studs",
     "WELCOME TO CLICKTON, says the sign, in raised white studs. Underneath, in smaller ones: \"Population: you. Please touch the bricks. They like it.\"", solid=True, r=6)
prop("quay_bench_w", "brick_bench", (-230, 566), BLUE, "a bench on the quay",
     "A bench built for two, or one person and a very large dog. The bay laps against the baseplate just beyond it, studs and all.", solid=True, r=11)
prop("quay_bench_e", "brick_bench", (240, 566), RED, "a bench on the quay",
     "Somebody has left one single brick on the seat, as if saving it. It's yellow. You put it back exactly where it was.", solid=True, r=11)
prop("quay_duck", "brick_duck", (-560, 580), YELLOW, "a very large brick duck",
     "A duck of yellow bricks on a grey plinth, mid-quack. It is the only duck in Clickton, which is why it's allowed to be this big.", solid=True, r=18)
for i, x in enumerate([-800, -420, 420, 800]):
    prop("quay_bollard_%d" % i, "brick_bollard", (x, 632), YELLOW, "a bollard", solid=True, r=4)
for i, (x, y, col) in enumerate([(-780, 700, RED), (-150, 700, YELLOW), (80, 730, GREEN), (640, 704, ORANGE), (860, 730, TEAL), (-600, 730, PINK)]):
    prop("boat_%d" % i, "brick_boat", (x, y), col, "a little boat",
         "A boat made of eleven bricks and a very good mast. It bobs a stud's width up and down, which is the most a brick can manage." if i == 0 else None, solid=False)
prop("moored_boat", "brick_boat", (-230, 700), BLUE, "a boat tied to the pier",
     "It's tied to the pier with a brick on a string. The boat has never gone anywhere. It's the thought of leaving that matters.", solid=False)
prop("pier_crates", "brick_crates", (-300, 660), BROWN, "a stack of crates on the pier",
     "Crates of loose bricks, labelled with colours: RED (MOSTLY). BLUE (SOME). YELLOW (ONE, PROBABLY A MISTAKE).", solid=True, r=12)
prop("pier_barrel", "brick_barrel", (300, 670), YELLOW, "a barrel",
     "It rattles. Whatever's inside has a great many corners.", solid=True, r=8)
prop("lighthouse_sign", "brick_sign", (-292, 652), RED, "a small sign by the lighthouse",
     "THE LIGHTHOUSE. Its lamp is one clear yellow brick, and every night it shines exactly as far as the end of the pier, which is exactly as far as it needs to.", solid=True, r=6)

# The little square.
prop("fountain", "brick_fountain", (0, -30), SKY, "the fountain",
     "A fountain of grey bricks around a blue plate, with a spout of pale plates that never moves and never runs dry. Wishes go in the bowl. They're all the same wish: more bricks.", solid=True, r=30)
prop("square_plaque", "brick_sign", (-90, 70), TAN, "a plaque in the square",
     "THE FIRST BRICK. \"When Clickton was begun there was one brick, and it was every colour at once. The builder was so fond of it that, rather than waste it on a corner, they set it into a wall, low down where a hand could find it, and told nobody which wall. It never stopped swirling. They say it's near a quiet end of town, by the water.\"", solid=True, r=6)
prop("square_duck", "brick_duck", (120, 60), PINK, "a smaller brick duck",
     "The big duck on the quay has a cousin. This one is pink, and the size of a cat, and it is very, very pleased to be here.", solid=True, r=14)
prop("clock_sign", "brick_sign", (-60, -110), RED, "a small sign by the clock tower",
     "THE CLOCK TOWER. The clock is always exactly right, because it's the only one in Clickton, and so it's the one deciding.", solid=True, r=6)
prop("square_slide", "brick_slide", (140, -90), RED, "a slide",
     "A slide of blue plates, stepping down. Going down it makes a sound in your head, a soft ker-lik-lik-lik-lik, one for every stud.", solid=True, r=22)
prop("square_seesaw", "brick_seesaw", (120, -20), BLUE, "a seesaw",
     "It's balanced exactly level. It has been exactly level for as long as anyone can remember, which is a form of quiet joy.", solid=True, r=18)
prop("square_picnic", "brick_picnic", (-130, 20), RED, "a picnic table",
     "A table with a red-and-white cloth made of red and white plates. Somebody has laid out a picnic of tiny bricks. It looks delicious, if you are a brick.", solid=True, r=22)
for i, (x, y) in enumerate([(-100, -120), (60, -120), (-60, 90), (50, 90)]):
    prop("square_bench_%d" % i, "brick_bench", (x, y), [YELLOW, GREEN, RED, BLUE][i], "a bench in the square", solid=True, r=11)
for i, (x, y) in enumerate([(-170, -130), (170, -130), (-170, 90), (170, 90)]):
    prop("square_planter_%d" % i, "brick_planter", (x, y), BROWN, "a planter",
         "The flowers in this one are in rainbow order. Somebody took care." if i == 2 else None, solid=True, r=14)

# Signs at the lane corners, and the Brickworks.
prop("quay_row_sign", "brick_sign", (-440, 515 - 8), ORANGE, "a sign at the lane's end",
     "QUAY LANE. The shops here sell bricks by the colour, by the stud, and, on request, by the feeling. A little card says: \"ASK FOR THE ONE THAT'S BEEN WAITING.\"", solid=True, r=6)
prop("high_lane_sign", "brick_sign", (440, 140 + HALF - 6), GREEN, "a sign at a corner",
     "HIGH LANE. The buildings get taller toward the north, and the lane gets no wider, which is how it ended up so pleasantly shady.", solid=True, r=6)
prop("works_sign", "brick_sign", (640, -540 + HALF - 6), ORANGE, "the Brickworks sign",
     "THE BRICKWORKS. Every brick in Clickton was made here, once, in the same kiln. They all came out a different colour. Nobody has ever worked out why, and everyone is rather glad.", solid=True, r=6)
prop("skyline_sign", "brick_sign", (-640, -540 + HALF - 6), TEAL, "a sign under the tall buildings",
     "THE SKYLINE. Thirty-two floors of someone's idea of 'high up'. The lifts are very polite, and in no hurry.", solid=True, r=6)

for i, (x, y) in enumerate([(-560, 508), (560, 508), (-560, 168), (560, 168)]):
    prop("lane_planter_%d" % i, "brick_planter", (x, y), BROWN, "a planter",
         "A box of bricks with flowers made of smaller bricks, which need no water and are never any trouble." if i == 0 else None, solid=True, r=14)

PROPS = [p for p in PROPS if not in_building(p["position"][0], p["position"][1], 4)]
for p in PROPS:
    PLACED.append((p["position"][0], p["position"][1], 18))


def tree(x, y, _i):
    TREES.append([x, y])


scatter((-190, -165, 190, 105), 7, 24, tree)
scatter((-990, 520, 990, 630), 7, 24, tree)

# ── the secret ────────────────────────────────────────────────────────────────────────────────────
SECRET_POS = [BRICK_X, COTTAGE_RECT[1] + COTTAGE_RECT[3] + 10]
SECRET = {
    "id": "rainbow_brick",
    "position": [float(SECRET_POS[0]), float(SECRET_POS[1])],
    "radius": 120.0,
    "prop": {"type": "rainbow_brick", "color": [1.0, 1.0, 1.0], "label": "a brick of every colour", "tags": ["colour", "small", "odd", "old"]},
    "lore": "One brick, set into the wall among all the others, low down where a hand would find it. It fits as if it had always been part of the building, but every colour there is turns slowly through it, round and round, and it's very slightly warm.",
    "reveal": {"type": "always"},
    "found_line": "The first brick of Clickton, every colour at once. It comes out of the wall with a small, happy click.",
    "home_line": "Something has changed at home.",
    "qualities": ["crafted", "warm"],
    "keepsake": {
        "id": "first_brick",
        "type": "rainbow_brick",
        "color": [1.0, 1.0, 1.0],
        "label": "the first brick",
        "line": "Your companion sniffs the little rainbow brick, then sits down very close to it, the way you sit by something that matters.",
        "temperament": {"curiosity": 0.5, "energy": 0.4, "clinginess": 0.6},
    },
}

# ── art: Clickton re-skins everything (deep-merged over data/art.json) ─────────────────────────────
TREE_VARIANTS = ["green", "lime", "pine", "blossom", "green", "autumn", "teal", "green", "lime"]
ART = {
    "palette": {
        "ground_top": [0.36, 0.72, 0.34], "ground_bottom": [0.30, 0.62, 0.30], "foliage_dark": [0.2, 0.5, 0.3], "foliage_mid": [0.3, 0.62, 0.34],
        "foliage_light": [0.5, 0.8, 0.45], "bark": [0.42, 0.26, 0.16], "water": [0.24, 0.55, 0.84], "rim": [1.0, 1.0, 1.0], "shadow": [0.08, 0.08, 0.2],
        "grass": [0.3, 0.6, 0.3],
    },
    "light": {"shadow_alpha": 0.18, "rim_strength": 0.0},
    "entities": {
        "ground": {
            "render": "pixel", "terrain": "res://assets/sprites/ck_terrain.png", "tile": 128,
            "details": "res://assets/sprites/ck_details.png", "details_index": "res://data/ck_details.json",
            "shade": 0.0,
            "ramps": {
                "grass": [[0.15, 0.42, 0.18], [0.24, 0.56, 0.25], [0.31, 0.66, 0.30], [0.52, 0.84, 0.44]],
                "lush": [[0.10, 0.36, 0.20], [0.17, 0.48, 0.26], [0.23, 0.58, 0.31], [0.42, 0.76, 0.48]],
                "meadow": [[0.18, 0.46, 0.20], [0.29, 0.60, 0.27], [0.36, 0.70, 0.32], [0.56, 0.86, 0.46]],
                "dirt": [[0.55, 0.44, 0.28], [0.74, 0.62, 0.40], [0.84, 0.72, 0.48], [0.95, 0.86, 0.62]],
                "sand": [[0.55, 0.44, 0.28], [0.74, 0.62, 0.40], [0.84, 0.72, 0.48], [0.95, 0.86, 0.62]],
                "path": [[0.55, 0.44, 0.28], [0.74, 0.62, 0.40], [0.84, 0.72, 0.48], [0.95, 0.86, 0.62]],
                "worn": [[0.15, 0.42, 0.18], [0.24, 0.56, 0.25], [0.31, 0.66, 0.30], [0.52, 0.84, 0.44]],
            },
            "accents": [[0.77, 0.16, 0.11], [0.96, 0.80, 0.19], [0.95, 0.95, 0.95], [1.0, 0.60, 0.86]],
            "patches": {"lush": {"scale": 0.0032, "threshold": 0.56}, "meadow": {"scale": 0.0045, "threshold": 0.62}, "dirt": {"scale": 0.006, "threshold": 1.6}},
            "clump": {"scale": 0.011, "dark": 0.3, "light": 0.7},
            "scatter": {
                "density": 0.45,
                "open": [
                    {"names": ["lb_red_2x1", "lb_blue_2x2", "lb_yellow_1x1", "lb_green_2x1", "lb_white_4x1", "lb_orange_2x2", "lb_pink_1x1",
                               "lb_lime_plate", "lb_teal_2x1", "lb_red_plate", "lb_blue_1x1", "lb_yellow_2x1"], "weight": 8, "count": [1, 3]},
                    {"names": ["lb_heap_0", "lb_heap_1", "lb_heap_2"], "weight": 3, "count": [1, 1]},
                ],
                "under_trees": {"names": [], "ring": []},
                "path_edge": [], "reeds": [], "lilies": [],
            },
        },
        "understory": {"density": 0},
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 0}, "leaves": {"rate": 0}, "clouds": {"count": 0}},
        "tree": {"render": "sprite", "sway": 0.0, "variants": [
            {"trunk": "res://assets/sprites/ck_tree_%s_trunk.png" % v, "canopy": "res://assets/sprites/ck_tree_%s_canopy.png" % v} for v in TREE_VARIANTS]},
        "great_tree": {"render": "sprite", "sway": 0.0, "variants": [
            {"trunk": "res://assets/sprites/ck_great_%s_trunk.png" % v, "canopy": "res://assets/sprites/ck_great_%s_canopy.png" % v} for v in ("green", "autumn")]},
        "props": {"extra_types": ["brick_lamp", "brick_bench", "brick_hydrant", "brick_mailbox", "brick_planter", "brick_fountain", "brick_cone",
                                  "brick_crates", "brick_sign", "brick_duck", "brick_trashcan", "brick_picnic", "brick_flagpole", "brick_pile",
                                  "brick_bush", "brick_flowerbed", "brick_boat", "brick_barrel", "brick_stall", "brick_slide", "brick_seesaw",
                                  "brick_bollard", "brick_rock"],
                  "unseen": ["rainbow_brick"]},
        "building": {"render": "sprite", "wall": "res://assets/sprites/ck_wall.png", "roof": "res://assets/sprites/ck_roof.png",
                     "slope": "res://assets/sprites/ck_slope.png", "rainbow": "res://assets/sprites/ck_rainbow_brick.png"},
        "plate": {"render": "sprite", "stud": "res://assets/sprites/ck_plate_stud.png", "flat": "res://assets/sprites/ck_plate_flat.png",
                  "road": "res://assets/sprites/ck_plate_road.png"},
        "prop_lights": {"brick_lamp": {"radius": 26, "y": -34, "alpha": 0.16}},
    },
    "daycycle": {"enabled": True, "period_sec": 600, "loop": True, "stops": [
        {"t": 0.0, "tint": [1.0, 1.0, 1.0], "vignette": [0.30, 0.26, 0.40], "vstrength": 0.10},
        {"t": 1.0, "tint": [1.0, 0.99, 0.96], "vignette": [0.30, 0.26, 0.40], "vstrength": 0.12}]},
    # you are a visitor made of bricks, too (assets/brick_actor.gdshader)
    "actor_look": {"brick": {"cell": 4, "quantize": 0.6}},
}
ATMOSPHERE = {
    "day_tint": [1.0, 1.0, 1.0], "vignette": {"strength": 0.12, "color": [0.30, 0.26, 0.40]}, "wind": {"strength": 0.0, "speed": 0.0},
    "region_tint_alpha": 0.0, "grass": {"max": 0}, "pollen": {"amount": 4, "color": [1.0, 1.0, 1.0, 0.5]},
}

# ── assemble ──────────────────────────────────────────────────────────────────────────────────────
ALL_PROPS = PROPS
HEADER = ("CLICKTON - the little city made entirely of small colourful bricks. The ground is a studded baseplate, the roads and "
          "pavements are flat plates, the buildings are brick courses under studded roofs, the trees and props are built piece by "
          "piece, and every visitor (you, your companion, everyone else) is rebuilt out of bricks by the world's actor_look. No people "
          "and no creatures: just the city, tidy and lit and waiting. Its SECRET: one single rainbow brick set into the front wall of "
          "the Crooked Cottage at the quiet west end of the Quay Lane. Generated by tools/gen_clickton_world.py "
          "(art: pokepals/tools/gen_clickton.py over tools/brickart) - edit that and re-run, don't hand-tune positions.")
SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md): 'reveal' is 'always' (it is simply there to be found). "
                  "The brick is painted by the cottage's BuildingView 'inlay' (not by WorldArt, which would draw it under the building); "
                  "the world's art lists 'rainbow_brick' as an 'unseen' prop type for exactly that reason.")


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2])} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "clickton",')
out.append('\t"intro": %s,' % json.dumps("Everything here is made of bricks, and so, you notice, are you. Touch things. Look low down. One of the bricks is not like the others."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": false },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 14, "pond_blocks": false, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.30, 0.62, 0.30],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
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

# ── validate ──────────────────────────────────────────────────────────────────────────────────────
d = json.loads(text)
ids = [p["id"] for p in d["props"]] + [b["id"] for b in d["buildings"]]
assert len(ids) == len(set(ids)), "duplicate ids: %s" % [i for i in ids if ids.count(i) > 1]
for p in d["props"]:
    assert bool(p.get("interactive")) == bool(p.get("lore")), "interactive iff lore: %s" % p["id"]
    x, y = p["position"]
    assert BOUNDS_MIN[0] < x < BOUNDS_MAX[0] and BOUNDS_MIN[1] < y < BOUNDS_MAX[1], p["id"]
sp = d["player_spawn"]
for b in d["buildings"]:
    x, y, w, h = b["rect"]
    assert h % 2 == 0 and b["h"] % 6 == 0, b["id"]
    assert not (x - 30 < sp[0] < x + w + 30 and y - 30 < sp[1] < y + h + 30), "spawn inside %s" % b["id"]
    assert BOUNDS_MIN[0] <= x and x + w <= BOUNDS_MAX[0] and BOUNDS_MIN[1] <= y and y + h <= BOUNDS_MAX[1], b["id"]
# no two buildings overlap
bl = d["buildings"]
for i in range(len(bl)):
    for j in range(i + 1, len(bl)):
        a, b = bl[i]["rect"], bl[j]["rect"]
        assert not (a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]), "overlap %s %s" % (bl[i]["id"], bl[j]["id"])
# every building clear of the roads
for b in bl:
    x, y, w, h = b["rect"]
    if b["id"] in ("lighthouse", "clock_tower"):
        continue
    for lx0, ly0, lx1, ly1 in LANE_RECTS:
        assert not (x < lx1 and x + w > lx0 and y < ly1 and y + h > ly0), "%s %s on lane %s" % (b["id"], b["rect"], (lx0, ly0, lx1, ly1))
cott = next(b for b in bl if b["id"] == "crooked_cottage")
assert cott["inlay"]["prop"] == "secret_" + d["secret"]["id"]
walk_y = cott["rect"][1] + cott["rect"][3]
assert abs(d["secret"]["position"][1] - walk_y) < 20, "the secret must be standing room from its wall"
assert abs(d["secret"]["position"][0] - BRICK_X) < 1
print("buildings:", len(bl), "| plates:", len(d["plates"]), "| props:", len(d["props"]), "| interactive:", sum(1 for p in d["props"] if p.get("interactive")),
      "| trees:", len(d["trees"]))
for path in ["server/priv/world_seeds/clickton.json", "pokepals/tests/world_fixtures/clickton.json"]:
    open(path, "w").write(text)
print("wrote both files")
