#!/usr/bin/env python3
"""Generate CLICKTON, the little city made entirely of small colourful bricks, as a world spec.

Everything in Clickton is a brick: the baseplate ground, the roads and pavements (flat plates), the
buildings (courses of brick under studded roofs), the trees, the props, even the visitors, who are
rebuilt out of bricks by the world's `actor_look` (assets/brick_actor.gdshader). There are no
people here and no creatures: only the city, lit and tidy and waiting, and the one thing in it
that is hidden.

The SECRET: one single rainbow brick, set into the front wall of a cottage at the quiet west end of the
Quay Road row, low down where a hand would reach. It has a little glint now and then. `reveal: always`
(it is simply there to be found), claimed by examining it; the brick itself is painted by the building
(BuildingView `inlay`), because a prop in WorldArt would be drawn under the building.

Layout: the Quay (where you arrive, a promenade over a studded bay with two piers) at the bottom; three
streets (Quay Road, Main Street, North Road) crossed by three avenues; a row of buildings along the north
side of every street; open lots behind them: Pleasant Park (west), the Town Square (middle, a clock tower
and a fountain), the Station Yard (east, with a train of brick carriages), and the Brickworks and the
Hilltop Orchard in the north. Art: pokepals/tools/gen_clickton.py over tools/brickart/bricks.py.

Hand-authored: the street grid, the landmarks, every line of lore, the secret. Procedural (seeded): the
facades of the building rows and the scatter of trees and props in the open lots. Writes the server seed
and the client test fixture. Run from the repo root:  python3 tools/gen_clickton_world.py
"""
import json
import math
import random

random.seed(0xB41C4)

BOUNDS_MIN = (-1500, -1150)
BOUNDS_MAX = (1500, 1150)
PLAYER_SPAWN = [0, 628]
COMPANION_SPAWN = [-34, 650]
PORTALS = [
    {"id": "clickton_way_home", "type": "portal", "position": [110, 640], "color": [1.0, 0.85, 0.3], "label": "the way back to the Vale",
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

# ── the street grid ───────────────────────────────────────────────────────────────────────────────
ROAD_W = 64
WALK = 18
H_ROADS = {"north_road": -640, "main_street": -60, "quay_road": 500}
V_ROADS = [(-760, -1150, 500), (0, -1150, -640), (0, -60, 500), (760, -1150, 500)]   # (x, y0, y1)
SEGMENTS = [(-1480, -810), (-710, -50), (50, 710), (810, 1480)]   # between the avenues' pavements
ROW_D = 110                                                      # every building row's depth

PLATES = []        # drawn in order
NOGO = []          # rects (x0, y0, x1, y1) nothing is scattered into


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
# pavements first (so every junction is road), then the roads, then the painted lines
for name, y in H_ROADS.items():
    plate(-1500, y - ROAD_W // 2 - WALK, 1500, y + ROAD_W // 2 + WALK, "stud", PAVE)
for x, y0, y1 in V_ROADS:
    plate(x - ROAD_W // 2 - WALK, y0, x + ROAD_W // 2 + WALK, y1, "stud", PAVE)
for name, y in H_ROADS.items():
    plate(-1500, y - ROAD_W // 2, 1500, y + ROAD_W // 2, "road", ASPHALT, nogo=False)
for x, y0, y1 in V_ROADS:
    plate(x - ROAD_W // 2, y0, x + ROAD_W // 2, y1, "road", ASPHALT, nogo=False)
# dashed centre lines along every street, skipping the junctions; zebra crossings beside them
LINE = c(236, 236, 230)
AVENUES = sorted({x for x, _, _ in V_ROADS})
for name, y in H_ROADS.items():
    x = -1480
    while x < 1480:
        if all(abs((x + 12) - ax) > ROAD_W // 2 + 8 for ax in AVENUES):
            plate(x, y - 2, x + 24, y + 2, "mark", LINE, nogo=False)
        x += 48
    for ax in AVENUES:
        for side in (-1, 1):
            zx = ax + side * (ROAD_W // 2 + 10)
            for k in range(5):
                plate(zx - 3, y - ROAD_W // 2 + 6 + k * 11, zx + 3, y - ROAD_W // 2 + 12 + k * 11, "mark", LINE, nogo=False)
for ax, y0, y1 in V_ROADS:
    y = y0 + 24
    while y < y1 - 24:
        if all(abs((y + 12) - ry) > ROAD_W // 2 + 8 for ry in H_ROADS.values()):
            plate(ax - 2, y, ax + 2, y + 24, "mark", LINE, nogo=False)
        y += 48

# ── the Quay: a promenade, a studded bay, two piers ───────────────────────────────────────────────
PROM = c(222, 200, 150)
plate(-1500, 550, 1500, 700, "stud", PROM)
WATER = c(60, 140, 215)
plate(-1500, 700, -460, 1150, "stud", WATER, solid=True, shimmer=True)
plate(-380, 700, 380, 1150, "stud", WATER, solid=True, shimmer=True)
plate(460, 700, 1500, 1150, "stud", WATER, solid=True, shimmer=True)
PIER = c(168, 112, 66)
plate(-460, 900, -380, 1150, "stud", WATER, solid=True, shimmer=True)
plate(380, 900, 460, 1150, "stud", WATER, solid=True, shimmer=True)
plate(-460, 690, -380, 900, "stud", PIER)
plate(380, 690, 460, 900, "stud", PIER)

# ── the town square, the park, the station yard ───────────────────────────────────────────────────
SQUARE = (-330, -560, 330, -250)
plate(*SQUARE, "stud", c(238, 222, 182))
plate(-300, -530, 300, -280, "flat", c(226, 206, 160), nogo=False)     # a smooth inlay, tile-fashion
PARK = (-1450, -590, -810, -250)
plate(*PARK, "stud", c(120, 200, 90), nogo=False)
POND = (-1280, -500, -1000, -370)
plate(*POND, "stud", WATER, solid=True, shimmer=True)
YARD = (810, -590, 1450, -250)
plate(*YARD, "stud", c(190, 190, 196))
plate(820, -440, 1440, -380, "flat", c(110, 100, 96))                    # the track bed
for k in range(31):
    plate(826 + k * 20, -440, 832 + k * 20, -380, "mark", c(160, 120, 80), nogo=False)   # sleepers
plate(820, -421, 1440, -417, "mark", c(210, 210, 215), nogo=False)         # rails
plate(820, -403, 1440, -399, "mark", c(210, 210, 215), nogo=False)
PLATFORM = (840, -350, 1420, -300)
plate(*PLATFORM, "stud", c(240, 232, 200))
MARKET = (-600, 40, 600, 300)
plate(*MARKET, "stud", c(244, 210, 150))                                # the Market Lot's tiled floor
HILL = (-1450, -1100, -820, -830)
plate(*HILL, "stud", c(160, 214, 110), nogo=False)
YARD_N = (60, -1110, 1450, -830)
plate(*YARD_N, "stud", c(176, 176, 184), nogo=False)

REGIONS = [
    ("the_quay", (-1500, 520), (1500, 1150)),
    ("main_street", (-1500, 300), (1500, 520)),
    ("the_market_lot", (-1500, -60), (1500, 300)),
    ("the_square", (-330, -580), (330, -240)),
    ("pleasant_park", (-1500, -600), (-800, -240)),
    ("station_yard", (800, -600), (1500, -240)),
    ("north_road", (-1500, -830), (1500, -600)),
    ("hilltop_orchard", (-1500, -1150), (-800, -830)),
    ("the_brickworks", (50, -1150), (1500, -830)),
    ("skyline_row", (-800, -1150), (50, -830)),
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


def fill_row(x0, x1, y1, kind, d=ROW_D, max_h=None, alley_every=3):
    """Terrace of buildings between x0..x1 whose south walls stand at y1."""
    x = snap(x0 + random.choice([0, 0, 8]))
    placed = 0
    out = []
    while x < x1 - 70:
        w = snap(random.choice([88, 96, 104, 112, 120, 128, 136]))
        if x + w > x1:
            w = snap(x1 - x)
        if w < 72:
            break
        wall = random.choice(WALLS)
        roof = random.choice(ROOFS)
        opts = {}
        if kind == "shop":
            h = random.choice([66, 72, 78, 84])
            opts = {"door": True, "awning": random.choice([RED, BLUE, GREEN, YELLOW, ORANGE, TEAL]), "door_color": random.choice(DOORS)}
            if random.random() < 0.3:
                opts["flag"] = random.choice(WALLS)
            if random.random() < 0.25:
                opts["antenna"] = True
        elif kind == "office":
            h = random.choice([96, 108, 120, 132, 144])
            opts = {"door": True, "door_color": random.choice(DOORS)}
            if random.random() < 0.5:
                opts["tiers"] = [{"inset": 14, "h": random.choice([24, 36, 48]), "wall": random.choice(WALLS)}]
                if random.random() < 0.4:
                    opts["tiers"].append({"inset": 14, "h": 24})
            if random.random() < 0.4:
                opts["antenna"] = True
            if random.random() < 0.3:
                opts["flag"] = random.choice(WALLS)
        elif kind == "house":
            h = random.choice([48, 54, 60])
            wall = random.choice([WHITE, CREAM, YELLOW, PINK, SKY, LIME, TAN, c(240, 170, 150)])
            roof = random.choice([RED, BLUE, c(120, 60, 50), GREEN, DKGREY, ORANGE])
            opts = {"door": True, "door_color": random.choice(DOORS), "roof_style": "gable",
                    "shutters": random.choice([GREEN, BLUE, RED, TEAL, WHITE])}
            if random.random() < 0.55:
                opts["chimney"] = True
        elif kind == "factory":
            h = random.choice([72, 84, 96])
            roof = random.choice([DKGREY, c(70, 76, 90), RED])
            opts = {"windows": True, "chimney": random.random() < 0.8,
                    "tiers": [{"inset": 20, "h": random.choice([24, 36]), "wall": random.choice([GREY, DKGREY, TAN])}]}
            wall = random.choice([RED, GREY, ORANGE, TAN, BLUE])
        else:
            h = 84
        if max_h:
            h = min(h, max_h)
        out.append(building([x, y1 - d, w, d], h, wall, roof, **opts))
        placed += 1
        x += w + (random.choice([40, 48]) if placed % alley_every == 0 else random.choice([4, 6]))
        x = snap(x, 2)
    return out


# The secret's cottage: the westmost house on the Quay Road, a different colour from the rest so it is easy to
# find once you know what you're looking for. Its front wall is the one with the brick in it.
cottage_rect = [-1480, 360, 104, 90]
COTTAGE_X = cottage_rect[0] + cottage_rect[2] // 2
COTTAGE = building(cottage_rect, 54, c(255, 236, 140), RED, door=True, door_color=c(40, 127, 70), roof_style="gable",
                   shutters=c(40, 127, 70), chimney=True, id="crooked_cottage",
                   inlay={"prop": "secret_rainbow_brick", "x": -26, "y": -15})

# houses along the Quay Road at both ends, shops along its middle, offices along Main Street and North Road
fill_row(-1340, -810, 450, "house", d=90, alley_every=4)
fill_row(810, 1480, 450, "house", d=90, alley_every=4)
fill_row(-710, -50, 450, "shop")
fill_row(50, 710, 450, "shop")
fill_row(-1480, -810, -110, "house", d=90)
fill_row(810, 1480, -110, "house", d=90)
fill_row(-710, -50, -110, "office")
fill_row(50, 710, -110, "office")
fill_row(-1480, -810, -690, "shop")
fill_row(-710, -50, -690, "office")
fill_row(50, 710, -690, "office")
fill_row(810, 1480, -690, "shop")

# ── landmarks: the clock tower, the lighthouse, the station, the train, the Brickworks ─────────────
building([-48, -576, 96, 72], 120, RED, DKGREY, id="clock_tower", door=True, door_color=c(105, 64, 40), windows=True, clock=True,
         tiers=[{"inset": 16, "h": 42, "wall": CREAM, "roof": RED}, {"inset": 14, "h": 24, "wall": YELLOW, "roof": RED}], flag=YELLOW)
building([-440, 828, 40, 36], 108, WHITE, RED, id="lighthouse", windows=True, door=False,
         tiers=[{"inset": 8, "h": 30, "wall": RED, "roof": DKGREY}, {"inset": 6, "h": 18, "wall": YELLOW, "roof": RED}], antenna=False)
building([880, -590, 300, 96], 78, TAN, BLUE, id="station", door=True, door_color=BLUE, awning=BLUE, flag=RED, windows=True,
         tiers=[{"inset": 110, "h": 30, "wall": CREAM, "roof": BLUE}], clock=False)
TRAIN_Y = -388
CARS = [("engine", 1000, RED, True), ("coach_a", 1100, BLUE, False), ("coach_b", 1190, YELLOW, False), ("coach_c", 1280, GREEN, False)]
for cid, cx, col, eng in CARS:
    building([cx, TRAIN_Y - 20, 84 if not eng else 72, 24], 36, col, DKGREY, id=cid, windows=not eng, chimney=eng,
             tiers=[{"inset": 8, "h": 18, "wall": c(60, 60, 70)}] if eng else [])
# the Brickworks
building([140, -940, 220, 130], 96, ORANGE, DKGREY, id="kiln_hall", chimney=True, windows=True,
         tiers=[{"inset": 30, "h": 36, "wall": GREY}], door=True, door_color=DKGREY)
building([440, -940, 180, 130], 84, GREY, c(70, 76, 90), id="mould_shed", windows=True, chimney=True, antenna=True)
building([700, -950, 260, 140], 108, RED, DKGREY, id="the_brickworks", door=True, door_color=BLUE, windows=True, chimney=True, flag=WHITE,
         tiers=[{"inset": 40, "h": 42, "wall": ORANGE}])
building([1040, -930, 200, 120], 78, BLUE, DKGREY, id="packing_shed", windows=True, door=True, door_color=YELLOW)
# the skyline: a few tall ones along the back of the north road
for i, (x, w, h) in enumerate([(-700, 120, 168), (-540, 104, 144), (-380, 128, 192), (-200, 104, 156), (-60, 96, 132)]):
    building([x, -960, w, 100], h, random.choice([BLUE, TEAL, GREY, SKY, LAVENDER]), random.choice([DKGREY, BLUE]), windows=True, door=(i % 2 == 0),
             tiers=[{"inset": 18, "h": 36, "wall": WHITE}], antenna=(i % 2 == 1), id="sky_%d" % i)

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
    if not (BOUNDS_MIN[0] + 40 < x < BOUNDS_MAX[0] - 40 and BOUNDS_MIN[1] + 40 < y < BOUNDS_MAX[1] - 40):
        return True
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 140:
        return True
    return any(x0 - rad < x < x1 + rad and y0 - rad < y < y1 + rad for x0, y0, x1, y1 in NOGO)


PLACED = []


def scatter(rect, n, rad, fn, tries=3000, keep=0):
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


# Lamps and hydrants stand along the pavements; benches and planters by the shops.
for name, y in H_ROADS.items():
    x = -1400
    while x < 1400:
        if all(abs(x - ax) > 70 for ax in AVENUES):
            prop("lamp_%s_%d" % (name, x), "brick_lamp", (x, y - ROAD_W // 2 - 6), SKY, "a street lamp", solid=True, r=5)
        x += 220
# spots the pavement furniture must not use
FURN = []

SIGN_COL = [RED, BLUE, GREEN, YELLOW, TEAL, ORANGE]

# The Quay: the welcome, the boats, the bollards.
prop("welcome_sign", "brick_sign", (-110, 618), YELLOW, "a signpost of studs",
     "WELCOME TO CLICKTON, says the sign, in raised white studs. Underneath, in smaller ones: \"Population: you. Please touch the bricks. They like it.\"", solid=True, r=6)
prop("quay_bench_w", "brick_bench", (-240, 612), BLUE, "a bench on the quay",
     "A bench built for two, or one person and a very large dog. The bay laps against the baseplate just beyond it, studs and all.", solid=True, r=11)
prop("quay_bench_e", "brick_bench", (250, 612), RED, "a bench on the quay",
     "Somebody has left one single brick on the seat, as if saving it. It's yellow. You put it back exactly where it was.", solid=True, r=11)
prop("quay_duck", "brick_duck", (-560, 620), YELLOW, "a very large brick duck",
     "A duck of yellow bricks on a grey plinth, mid-quack. It is the only duck in Clickton, which is why it's allowed to be this big.", solid=True, r=18)
for i, x in enumerate([-860, -300, 300, 860, 1240]):
    prop("quay_bollard_%d" % i, "brick_bollard", (x, 690), YELLOW, "a bollard", solid=True, r=4)
for i, (x, y, col) in enumerate([(-900, 880, RED), (-640, 1010, BLUE), (-160, 900, YELLOW), (150, 1040, GREEN), (640, 960, ORANGE), (1050, 880, TEAL), (-1180, 1030, PINK)]):
    prop("boat_%d" % i, "brick_boat", (x, y), col, "a little boat",
         ("A boat made of eleven bricks and a very good mast. It bobs a stud's width up and down, which is the most a brick can manage." if i == 0 else None), solid=False)
prop("moored_boat", "brick_boat", (-340, 880), ORANGE, "a boat tied to the pier",
     "It's tied to the pier with a brick on a string. The boat has never gone anywhere. It's the thought of leaving that matters.", solid=False)
prop("pier_crates", "brick_crates", (-420, 780), BROWN, "a stack of crates on the pier",
     "Crates of loose bricks, labelled with colours: RED (MOSTLY). BLUE (SOME). YELLOW (ONE, PROBABLY A MISTAKE).", solid=True, r=12)
prop("pier_barrel", "brick_barrel", (420, 790), YELLOW, "a barrel",
     "It rattles. Whatever's inside has a great many corners.", solid=True, r=8)
prop("lighthouse_sign", "brick_sign", (-420, 730), RED, "a small sign by the lighthouse",
     "THE LIGHTHOUSE. Its lamp is one clear yellow brick, and every night it shines exactly as far as the end of the pier, which is exactly as far as it needs to.", solid=True, r=6)

# The Market Lot: stalls, crates, a planter or two.
for i, (x, y, col) in enumerate([(-420, 120, RED), (-210, 200, BLUE), (0, 120, GREEN), (210, 200, YELLOW), (420, 120, TEAL)]):
    prop("stall_%d" % i, "brick_stall", (x, y), col, "a market stall",
         ["The stall sells bricks by the colour, by the stud, and, on request, by the feeling. A little card says: \"ASK FOR THE ONE THAT'S BEEN WAITING.\"",
          "A stall of lovely small things, every one a different brick. There's nobody to pay, so you pay with admiration, which is accepted.",
          "Hanging from the awning: a string of little round plates, like coins. They clink in a way that sounds exactly like a market.",
          "This stall sells only corner pieces. It has a very loyal customer, who isn't here right now.",
          "A stall of plates, all flat, all lovely. A sign says: \"SMOOTH. NO STUDS. ASK ABOUT OUR SMOOTH.\""][i], solid=True, r=18)
prop("market_sign", "brick_sign", (-560, 60), ORANGE, "the market sign",
     "THE MARKET LOT. Open all hours, because nobody has ever closed it. The floor here is tiled in tan plates, the colour of toast.", solid=True, r=6)
for i, (x, y) in enumerate([(-500, 260), (-300, 40), (300, 40), (500, 260)]):
    prop("market_planter_%d" % i, "brick_planter", (x, y), [BROWN, RED, BLUE, GREEN][i], "a planter",
         "A box of bricks with flowers made of smaller bricks, which need no water and are never any trouble." if i == 0 else None, solid=True, r=14)

# The Town Square.
prop("fountain", "brick_fountain", (0, -400), SKY, "the fountain",
     "A fountain of grey bricks around a blue plate, with a spout of pale plates that never moves and never runs dry. Wishes go in the bowl. They're all the same wish: more bricks.", solid=True, r=30)
prop("square_plaque", "brick_sign", (-110, -300), TAN, "a plaque in the square",
     "THE FIRST BRICK. \"When Clickton was begun there was one brick, and it was every colour at once. The builder was so fond of it that, rather than waste it on a corner, they set it into a wall, low down where a hand could find it, and told nobody which wall. They say it winks, now and then, if you're patient. They say it's near a quiet end of town.\"", solid=True, r=6)
prop("square_duck", "brick_duck", (180, -300), PINK, "a smaller brick duck",
     "The big duck on the quay has a cousin. This one is pink, and the size of a cat, and it is very, very pleased to be here.", solid=True, r=14)
for i, x in enumerate([-240, 240]):
    prop("square_flag_%d" % i, "brick_flagpole", (x, -540), [RED, BLUE][i], "a flagpole",
         "The flag is one flat plate on a pole, and it's flying perfectly, in a breeze that has never needed to blow." if i == 0 else None, solid=True, r=5)
for i, (x, y) in enumerate([(-200, -440), (200, -440), (-120, -330), (120, -330)]):
    prop("square_bench_%d" % i, "brick_bench", (x, y), [YELLOW, GREEN, RED, BLUE][i], "a bench in the square", solid=True, r=11)
for i, (x, y) in enumerate([(-290, -520), (290, -520), (-290, -290), (290, -290)]):
    prop("square_planter_%d" % i, "brick_planter", (x, y), [BROWN, BROWN, BROWN, BROWN][i], "a planter",
         "The flowers in this one are in rainbow order. Somebody took care." if i == 2 else None, solid=True, r=14)
prop("clock_sign", "brick_sign", (-100, -480), RED, "a small sign by the clock tower",
     "THE CLOCK TOWER. The clock is always exactly right, because it's the only one in Clickton, and so it's the one deciding.", solid=True, r=6)

# Pleasant Park.
prop("park_sign", "brick_sign", (-1130, -300), GREEN, "the park sign",
     "PLEASANT PARK. Please keep off the studs. (Nobody has ever managed this. The sign is mostly decorative.)", solid=True, r=6)
prop("park_slide", "brick_slide", (-1330, -330), RED, "a slide",
     "A slide of blue plates, stepping down. Going down it makes a sound in your head, a soft ker-lik-lik-lik-lik, one for every stud.", solid=True, r=22)
prop("park_seesaw", "brick_seesaw", (-1230, -310), BLUE, "a seesaw",
     "It's balanced exactly level. It has been exactly level for as long as anyone can remember, which is a form of quiet joy.", solid=True, r=18)
for i, (x, y) in enumerate([(-1190, -560), (-1330, -440), (-940, -440), (-1180, -330)]):
    prop("park_bench_%d" % i, "brick_bench", (x, y), [GREEN, YELLOW, RED, BLUE][i], "a park bench", solid=True, r=11)
prop("picnic", "brick_picnic", (-1000, -330), RED, "a picnic table",
     "A table with a red-and-white cloth made of red and white plates. Somebody has laid out a picnic of tiny bricks. It looks delicious, if you are a brick.", solid=True, r=22)
prop("pond_sign", "brick_sign", (-1140, -350), SKY, "the pond sign",
     "THE POND. Studs, in blue, all the way down. Please do not feed the ducks. (There is one duck. It does not eat. It's on the quay.)", solid=True, r=6)

# The Station Yard.
prop("station_sign", "brick_sign", (1000, -290), BLUE, "the station sign",
     "CLICKTON CENTRAL. The 12:00 to Somewhere leaves at noon, forever. The train is always here, always about to go, which is the best a train can be.", solid=True, r=6)
for i, x in enumerate([920, 1060, 1200, 1340]):
    prop("platform_bench_%d" % i, "brick_bench", (x, -326), [RED, YELLOW, GREEN, BLUE][i], "a platform bench", solid=True, r=11)
prop("train_note", "brick_sign", (1380, -290), ORANGE, "a note by the tracks",
     "Pinned to the post: \"THE ENGINE IS A SHADE OF RED THE CARRIAGES ENVY. PLEASE DO NOT TELL THE CARRIAGES.\"", solid=True, r=6)

# The Brickworks and the north.
prop("works_sign", "brick_sign", (780, -820), ORANGE, "the Brickworks sign",
     "THE BRICKWORKS. Every brick in Clickton was made here, once, in the same kiln. They all came out a different colour. Nobody has ever worked out why, and everyone is rather glad.", solid=True, r=6)
for i, (x, y) in enumerate([(300, -810), (360, -790), (560, -800), (900, -800), (1100, -810)]):
    prop("works_crates_%d" % i, "brick_crates", (x, y), [BROWN, RED, BROWN, BLUE, BROWN][i], "stacked crates", solid=True, r=12)
for i, (x, y) in enumerate([(240, -790), (480, -800), (1000, -790), (1240, -800)]):
    prop("works_pile_%d" % i, "brick_pile", (x, y), WHITE, "a pile of loose bricks",
         "Bricks of every colour, in a heap. The heap has an air of having been there a while, waiting for someone to have an idea." if i == 0 else None, solid=False)
prop("orchard_sign", "brick_sign", (-1100, -860), LIME, "the orchard sign",
     "THE HILLTOP ORCHARD. The apples are red 1x1s, one to a tree. They have never ripened and will never fall, and you may not pick them, but you're welcome to look.", solid=True, r=6)
prop("skyline_sign", "brick_sign", (-300, -826), TEAL, "a sign under the tall buildings",
     "THE SKYLINE. Thirty-two floors of someone's idea of 'high up'. The lifts are very polite, and in no hurry.", solid=True, r=6)

# Street furniture: hydrants, mailboxes, bins and cones along the pavements.
FURNITURE = [("brick_hydrant", RED, "a fire hydrant", "It has never once been used. It is very proud of this, and stands a little straighter than the other hydrants."),
             ("brick_mailbox", BLUE, "a mailbox", "A mailbox. Inside, one letter, addressed to \"Whoever Lives Here\". It says: \"Welcome. It's lovely. Don't mind the corners.\""),
             ("brick_trashcan", DKGREY, "a bin", None), ("brick_cone", ORANGE, "a traffic cone", "Somebody put a cone here, years ago, for a reason that has since built itself into the road.")]
ROW_SIDEWALKS = [(y - ROAD_W // 2 - 6) for y in H_ROADS.values()]
k = 0
for y in ROW_SIDEWALKS:
    for x in range(-1300, 1300, 190):
        x += random.randrange(-30, 30)
        if any(abs(x - ax) < 80 for ax in AVENUES) or random.random() < 0.45:
            continue
        typ, col, label, lore = FURNITURE[k % len(FURNITURE)]
        k += 1
        prop("furn_%d" % k, typ, (x + 70, y), col, label, lore if k % 3 == 0 else None, solid=True, r=6)

# trees: street trees along the avenues' pavements, orchards and groves in the lots
def tree(x, y, _i):
    TREES.append([x, y])


def great(x, y, _i):
    LANDMARKS.append({"type": "great_tree", "position": [x, y]})


for ax, y0, y1 in V_ROADS:
    for y in range(y0 + 60, y1 - 40, 170):
        if all(abs(y - ry) > 90 for ry in H_ROADS.values()):
            for side in (-1, 1):
                TREES.append([ax + side * (ROAD_W // 2 + WALK + 12), y])
# hold the trees to places that aren't a building
def _bld_hit(x, y, rad=10):
    return any(b["rect"][0] - rad < x < b["rect"][0] + b["rect"][2] + rad and b["rect"][1] - rad < y < b["rect"][1] + b["rect"][3] + rad for b in BUILDINGS)
TREES = [t for t in TREES if not _bld_hit(t[0], t[1], 14) and abs(t[0]) < 1450 and abs(t[1]) < 1120]

# remove generated furniture/lamps that ended up inside a building
PROPS = [p for p in PROPS if not _bld_hit(p["position"][0], p["position"][1], 6)]

for p in PROPS:
    PLACED.append((p["position"][0], p["position"][1], 20))
for t in TREES:
    PLACED.append((t[0], t[1], 20))
scatter((-1450, -590, -810, -250), 3, 60, great)
scatter(PARK, 38, 24, tree)
scatter(HILL, 70, 24, tree)
scatter(YARD_N, 16, 24, tree)
scatter((-780, -590, -350, -250), 10, 24, tree)
scatter((350, -590, 800, -250), 10, 24, tree)
scatter((-1450, 60, -800, 330), 12, 24, tree)
scatter((800, 60, 1450, 330), 12, 24, tree)
for rect, n in [(PARK, 8), ((-780, -590, -350, -250), 4), ((350, -590, 800, -250), 4), (HILL, 10), ((-1450, 60, -800, 330), 5), ((800, 60, 1450, 330), 5)]:
    scatter(rect, n, 14, lambda x, y, i: PROPS.append({"id": "bush_%d_%d" % (x, y), "type": "brick_bush", "position": [x, y], "color": GREEN, "label": "a bush", "solid": True, "collision_radius": 9}))
scatter(PARK, 5, 16, lambda x, y, i: PROPS.append({"id": "flowerbed_%d_%d" % (x, y), "type": "brick_flowerbed", "position": [x, y], "color": GREEN, "label": "a flowerbed"}))
scatter((800, 60, 1450, 330), 3, 16, lambda x, y, i: PROPS.append({"id": "bed_%d_%d" % (x, y), "type": "brick_flowerbed", "position": [x, y], "color": GREEN, "label": "a flowerbed"}))
for rect, n in [((-1450, 60, -800, 330), 4), ((800, 60, 1450, 330), 4), (YARD_N, 5), (HILL, 3)]:
    scatter(rect, n, 14, lambda x, y, i: PROPS.append({"id": "rocks_%d_%d" % (x, y), "type": "brick_rock", "position": [x, y], "color": GREY, "label": "a heap of grey bricks", "solid": True, "collision_radius": 10}))

# ── the secret ────────────────────────────────────────────────────────────────────────────────────
SECRET_POS = [COTTAGE_X - 26, 460]
SECRET = {
    "id": "rainbow_brick",
    "position": [float(SECRET_POS[0]), float(SECRET_POS[1])],
    "radius": 120.0,
    "prop": {"type": "rainbow_brick", "color": [1.0, 1.0, 1.0], "label": "a brick of every colour", "tags": ["colour", "small", "odd", "old"]},
    "lore": "One brick, set into the wall among all the others, low down where a hand would find it, and striped in every colour there is. It fits so well you'd never have seen it if it hadn't winked. It's very slightly warm.",
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
          "the Crooked Cottage at the quiet west end of the Quay Road. Generated by tools/gen_clickton_world.py "
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
    for name, ry in H_ROADS.items():
        if b["id"] in ("lighthouse", "station") or b["id"].startswith("coach") or b["id"] == "engine":
            continue
        assert not (y < ry + ROAD_W // 2 + WALK and y + h > ry - ROAD_W // 2 - WALK and (x < 1500 and x + w > -1500)), "%s sits on %s" % (b["id"], name)
cott = next(b for b in bl if b["id"] == "crooked_cottage")
assert cott["inlay"]["prop"] == "secret_" + d["secret"]["id"]
walk_y = cott["rect"][1] + cott["rect"][3]
assert abs(d["secret"]["position"][1] - walk_y) < 20, "the secret must be standing room from its wall"
print("buildings:", len(bl), "| plates:", len(d["plates"]), "| props:", len(d["props"]), "| interactive:", sum(1 for p in d["props"] if p.get("interactive")),
      "| trees:", len(d["trees"]), "| great:", len(d["landmarks"]))
for path in ["server/priv/world_seeds/clickton.json", "pokepals/tests/world_fixtures/clickton.json"]:
    open(path, "w").write(text)
print("wrote both files")
