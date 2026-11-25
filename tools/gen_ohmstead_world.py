#!/usr/bin/env python3
"""Generate OHMSTEAD, the machine behind the Gateway, as a world spec.

A modest (3200 x 2432) world seen from inside the machine that draws all the others: a black void, a glowing
grid floor running off into the dark (one shader, GridGround), and everything on it a bright outline. Visitors
are redrawn as linework too (the art block's actor_look.wire): a person in magenta, a companion in amber.
Little mint RUNNERS carry packets of light along the grid's bright lines (the spec's `runners`: closed
routes; where each one is, is a pure function of time, so everyone sees them in the same places with nothing
simulated or sent).

Its one SECRET (docs/home-world-and-secrets-design.md, "Ohmstead"): a sector in the north-east has lost power.
Reveal type "circuit". You DIRECT your companion: tap a dead node and it runs there, laying a ribbon of light.
The ribbon has to visit every node and end on the outlet (a one-stroke puzzle); then power sweeps back and a
steady spark is waiting in the middle. The board is the `circuits` block's "sector" board.

Its reason to come back: the ARCADE, south of the middle. Two more boards with the same ribbon play, shared by
everyone there: the "table" (the server deals a fresh one each time it is closed) and "today" (one larger
board a day, the same for everyone). Closing one pays a few coins and sparks (the server decides).

Everything sits on the grid: the cell is 32, the bright lines every 128, and a board's nodes are 64 apart.

Hand-authored: regions, the boards' places, landmarks, every lore line, the art override, the secret.
Procedural (seeded, so re-running reproduces it): the sector's board, the scatter of trees and props.

Art assets come from pokepals/tools/gen_ohmstead.py. Writes the server seed and the client test fixture.
Run from the repo root:  python3 tools/gen_ohmstead_world.py
"""
import json
import math
import random

random.seed(0x0A11)

CELL = 32
MAJOR = 4
BIG = CELL * MAJOR              # 128: the bright lines
NODE = 64                       # a board's nodes are this far apart
BOUNDS_MIN = (-1600, -1216)
BOUNDS_MAX = (1600, 1216)
PLAYER_SPAWN = [-1184, 880]
COMPANION_SPAWN = [-1152, 904]
PORTALS = [
    {"id": "ohmstead_way_home", "type": "portal", "position": [-1264, 880], "color": [0.72, 0.55, 1.0], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

REGIONS = [
    ("the_inlet",   (-1600, 448),   (-768, 1216),  (0.37, 0.95, 1.0)),
    ("arcade",      (-768, 288),    (384, 1216),   (0.37, 0.95, 1.0)),
    ("the_cache",   (384, 160),     (1600, 1216),  (0.37, 0.95, 1.0)),
    ("the_bus",     (-1600, -224),  (1600, 288),   (0.37, 0.95, 1.0)),
    ("the_heap",    (-1600, -1216), (-512, -224),  (0.37, 0.95, 1.0)),
    ("clock_court", (-512, -1216),  (512, -224),   (0.37, 0.95, 1.0)),
    ("dark_sector", (512, -1216),   (1600, -224),  (0.37, 0.95, 1.0)),
]

# ── the boards ───────────────────────────────────────────────────────────────────────────────────────
# A board is a lattice of nodes, `cols` x `rows`, its top-left node at `origin`. Node index = row * cols + col.
SECTOR_ORIGIN = (832, -736)
SECTOR_COLS, SECTOR_ROWS = 5, 4
SECTOR_RECT = [704, -864, 512, 448]          # the patch of grid with no power (x, y, w, h)
TABLE_ORIGIN = (-640, 480)
TABLE_COLS, TABLE_ROWS = 5, 4
DAY_ORIGIN = (-224, 448)
DAY_COLS, DAY_ROWS = 7, 4       # (four rows: a board has to fit a 360-high view with room round it)


def board_rect(origin, cols, rows, pad=0):
    return (origin[0] - pad, origin[1] - pad, origin[0] + (cols - 1) * NODE + pad, origin[1] + (rows - 1) * NODE + pad)


def neighbours(i, cols, rows):
    c, r = i % cols, i // cols
    out = []
    if c > 0:
        out.append(i - 1)
    if c < cols - 1:
        out.append(i + 1)
    if r > 0:
        out.append(i - cols)
    if r < rows - 1:
        out.append(i + cols)
    return out


def on_edge(i, cols, rows):
    c, r = i % cols, i // cols
    return c == 0 or r == 0 or c == cols - 1 or r == rows - 1


def make_board(cols, rows, holes, rnd):
    """A one-stroke board: a random path through every cell of the lattice (the 'backbite' shuffle of a plain
    snake), with `holes` cells trimmed off its ends. What is left has a path through all of it from `source`
    to `sink`, both on the lattice's edge, so the ribbon can come in from a live line and go back out to one."""
    for _ in range(400):
        path = []
        for r in range(rows):
            row = [r * cols + c for c in range(cols)]
            path += row if r % 2 == 0 else row[::-1]
        for _ in range(cols * rows * 12):
            if rnd.random() < 0.5:
                path.reverse()
            end = path[-1]
            opts = [n for n in neighbours(end, cols, rows) if n != path[-2]]
            n = rnd.choice(opts)
            k = path.index(n)
            path = path[:k + 1] + path[k + 1:][::-1]
        cut_a = rnd.randint(0, holes)
        trimmed = path[cut_a:len(path) - (holes - cut_a)]
        gone = sorted(set(path) - set(trimmed))
        if on_edge(trimmed[0], cols, rows) and on_edge(trimmed[-1], cols, rows) and trimmed[0] != trimmed[-1]:
            return {"holes": gone, "source": trimmed[0], "sink": trimmed[-1], "solution": trimmed}
    raise AssertionError("no board")


SECTOR_BOARD = make_board(SECTOR_COLS, SECTOR_ROWS, 2, random.Random(0x5EC7))
SECRET_POS = (SECTOR_ORIGIN[0] + (SECTOR_COLS - 1) * NODE // 2, SECTOR_ORIGIN[1] + (SECTOR_ROWS - 1) * NODE // 2)

CIRCUITS = {
    "node": NODE,
    "boards": [
        {"id": "sector", "kind": "fixed", "origin": list(SECTOR_ORIGIN), "cols": SECTOR_COLS, "rows": SECTOR_ROWS,
         "holes": SECTOR_BOARD["holes"], "source": SECTOR_BOARD["source"], "sink": SECTOR_BOARD["sink"],
         "sector": SECTOR_RECT, "relight_s": 120, "label": "the dark sector"},
        {"id": "table", "kind": "dealt", "origin": list(TABLE_ORIGIN), "cols": TABLE_COLS, "rows": TABLE_ROWS,
         "holes": 2, "deal_s": 5, "label": "the table"},
        {"id": "today", "kind": "daily", "origin": list(DAY_ORIGIN), "cols": DAY_COLS, "rows": DAY_ROWS,
         "holes": 3, "label": "today's board"},
    ],
    # what closing a board pays everyone who laid part of its ribbon (the server grants it; "today" once a day each)
    "reward": {"table": {"coins": 5, "sparks": 1}, "today": {"coins": 20, "sparks": 3}},
    "tap_radius": 22.0,          # how near a node a tap has to land
    "arrive_radius": 7.0,        # the companion has reached a node
    "notice_range": 300.0,       # how near a board you are when its first line shows
    "release_distance": 520.0,   # walk this far from your companion and it lets the ribbon be
    "hint_delay_low": 14.0, "hint_delay_high": 4.0, "hint_hold": 1.8,   # by bond: how long before it glances at a good node
    "pet_pause": 3.0, "drift_hold": 30.0,
    "sweep_s": 2.4,              # how long the power takes to come back across the sector
    "camera_reach": [150.0, 80.0],   # how far the camera leans toward a board your companion is working on
    "camera_drop": 34.0,             # ...and how far below it the view sits, so the board clears the message pill
    "lines": {
        "near_sector": "This patch of the grid has no power. Its lines are cold, and the runners go the long way round.",
        "near_arcade": "The Arcade. Each board wants one ribbon of light through every node. Tap a node to send your companion.",
        "first": "The ribbon starts where the live line comes in: tap the node with the amber mark.",
        "start": "Your companion picks up a charge from the live line. Tap the next node along a line, and it carries the ribbon there.",
        "laid": "The ribbon follows it. Every node needs to be lit, and the ribbon has to end on the white outlet.",
        "not_line": "It can only run straight along a line, to a node the ribbon hasn't touched.",
        "bird": "A bird flies over the board and lays nothing. The ribbon needs feet on the lines.",
        "stuck": "The ribbon has nowhere left to go. Tap a lit node to wind it back to there.",
        "back": "The ribbon winds back.",
        "cleared": "Your companion comes to you, and the ribbon goes out.",
        "let_go": "Your companion leaves the ribbon where it is and comes to walk with you.",
        "other": "Someone else's ribbon. Tap the next node from its bright end, and yours carries it on.",
        "closed": "The board closes, and every node holds its light.",
        "dealt": "A new board lights up on the table.",
        "today_done": "Today's board is closed. A new one comes with the new day.",
        "paid": "Closed in {time}. {coins} and {sparks}.",
        "paid_plain": "Closed in {time}.",
        "best": " Your best: {best}.",
        "new_best": " That is your best yet.",
    },
}

LANDMARKS = [
    {"type": "great_tree", "position": [-1184, -832]},
    {"type": "great_tree", "position": [1216, 736]},
    {"type": "great_tree", "position": [320, -1024]},
    {"type": "great_tree", "position": [-1344, 160]},
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
AMBER = (1.0, 0.71, 0.28)
CYAN = (0.37, 0.95, 1.0)
RED = (1.0, 0.31, 0.43)

sx0, sy0, sw, sh = SECTOR_RECT
PYLONS = [(sx0, sy0), (sx0 + sw // 2, sy0), (sx0 + sw, sy0), (sx0, sy0 + sh // 2), (sx0 + sw, sy0 + sh // 2),
          (sx0, sy0 + sh), (sx0 + sw // 2, sy0 + sh), (sx0 + sw, sy0 + sh)]

SPECIAL = [
    prop("inlet_terminal", "oh_terminal", (-1104, 816), WHITE, "a welcome terminal",
         "Green letters, patiently scrolling. 'OHMSTEAD. You are behind the scenery now. Every world you have walked in is "
         "drawn from here, one line at a time, and the light on these lines is what keeps them lit. You look different "
         "because this is how the machine has always seen you. It likes your hat. The Arcade is east of here. North-east, a "
         "sector has lost its power: if you find it, tap a node and see what your companion does.'", solid=True, radius=6),
    prop("clock_fount", "oh_fount", (0, -96), CYAN, "the clock",
         "Rings of light, and a thin beam going straight up out of them into the dark. Once every little while a pulse runs "
         "up it, and when it does, every line in Ohmstead brightens very slightly, as if the whole place had breathed in.", solid=True, radius=14),
    prop("arcade_sign", "oh_arcade_sign", (-512, 400), WHITE, "the Arcade's sign",
         "ARCADE, in small bright capitals. Underneath, smaller: 'One ribbon. Every node. End on the white one. Nobody "
         "is keeping score but you.'", solid=True, radius=6),
    prop("today_sign", "oh_today_sign", (-32, 368), WHITE, "a sign: TODAY",
         "TODAY. 'This board is new each day, and it is the same board for everyone who comes. Once it is closed it stays "
         "lit until the day turns, so whoever arrives later can see it was done.'", solid=True, radius=6),
    prop("arcade_gate", "oh_gate", (-768, 576), WHITE, "the Arcade's gate", None, solid=False),
    prop("sector_terminal", "oh_terminal", (640, -480), WHITE, "a fault terminal",
         "Red letters this time. 'SECTOR 7: NO POWER. Cause: the loop is open. Remedy: one unbroken ribbon from the live "
         "line (amber mark) through every node to the outlet (white mark). A ribbon may not cross itself. Runners cannot do "
         "this. Runners carry. Something would have to lay it, node by node, on its own four feet.'", solid=True, radius=6),
    prop("heap_terminal", "oh_terminal", (-1056, -480), WHITE, "a terminal in the Heap",
         "'THE HEAP. Everything the worlds are not using right now is kept here: a pine nobody is standing under, a hill "
         "nobody is looking at. They wait as outlines. It does not seem to bother them.'", solid=True, radius=6),
    prop("cache_terminal", "oh_terminal", (960, 480), WHITE, "a terminal in the Cache",
         "'THE CACHE. Things that were wanted a moment ago and will be wanted again in a moment. A door's creak. The exact "
         "colour of a certain pond at dusk. Please do not rearrange them.'", solid=True, radius=6),
    prop("bus_terminal", "oh_terminal", (352, 96), WHITE, "a terminal by the Bus",
         "'THE BUS. The widest lines in Ohmstead, running west to east. The runners use them for the long hauls. If one "
         "stops in front of you it is only waiting for you to pass. They are very polite, and a little shy.'", solid=True, radius=6),
    prop("relay_west", "oh_tower", (-832, -96), CYAN, "a relay tower",
         "A lattice tower with a little dish. It hums one note, slightly flat. Your companion tilts its head at it.", solid=True, radius=8),
    prop("relay_east", "oh_tower", (1280, 32), CYAN, "a relay tower",
         "Another relay, pointed at the first one, far to the west. Whatever they are saying to each other, they have been "
         "saying it for a long time.", solid=True, radius=8),
]
CABIN_LORE = [
    "A little house made of nine lines. The door is the only warm thing about it, and it is very warm. Somebody, or "
    "something, lives here and has left the light on for you.",
    "A cabin, all edges. You can see straight through the walls to the other walls. There is a kettle in there, also made of lines.",
    "A house the machine drew and then kept. The door glows amber. On the step, a tiny cube, like a parcel nobody has collected.",
]
CABIN_SPOTS = [(-448, -352), (-256, -480), (-96, -384), (224, -416), (384, -544), (-352, -608)]
for i, pos in enumerate(CABIN_SPOTS):
    SPECIAL.append(prop("cabin_%d" % (i + 1), "oh_cabin", pos, WHITE, "a house of lines",
                        CABIN_LORE[i] if i < len(CABIN_LORE) else None, solid=True, radius=16))
for i, pos in enumerate(PYLONS):
    SPECIAL.append(prop("pylon_%d" % (i + 1), "oh_pylon", pos, RED, "a red marker",
                        "A red marker, blinking slowly. It stands at the edge of the ground that has no power." if i == 5 else None,
                        solid=True, radius=4))

# lamps along the Bus (the broad way west to east), and from the inlet up to it
LAMP_SPOTS = [(x, 64) for x in range(-1408, 1472, 256)] + [(x, -32) for x in range(-1280, 1472, 256)]
LAMP_SPOTS += [(-1120, 720), (-1120, 528), (-1120, 336), (-896, 656), (-896, 448)]
LAMP_SPOTS += [(576, -288), (608, -608), (704, -928), (1280, -384)]
for i, pos in enumerate(LAMP_SPOTS):
    SPECIAL.append(prop("lamp_%d" % (i + 1), "oh_lamp", pos, AMBER, "a lamp", None, solid=True, radius=3))

placed = [(p["position"][0], p["position"][1], 34) for p in SPECIAL]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 80))

# nothing is scattered on a board, in the dark sector, round the clock, or on the Bus
KEEP_RECTS = [
    (sx0 - 40, sy0 - 40, sx0 + sw + 40, sy0 + sh + 40),
    board_rect(TABLE_ORIGIN, TABLE_COLS, TABLE_ROWS, 110),
    board_rect(DAY_ORIGIN, DAY_COLS, DAY_ROWS, 110),
    (-1600, -64, 1600, 96),
    (-110, -200, 110, 10),
]


def in_keep(x, y, r=0):
    return any(x0 - r <= x <= x1 + r and y0 - r <= y <= y1 + r for x0, y0, x1, y1 in KEEP_RECTS)


def clear(x, y, r):
    if not (BOUNDS_MIN[0] + 90 <= x <= BOUNDS_MAX[0] - 90 and BOUNDS_MIN[1] + 90 <= y <= BOUNDS_MAX[1] - 90):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 190 or in_keep(x, y, r):
        return False
    return all(math.hypot(x - px, y - py) >= r + pr for px, py, pr in placed)


def scatter(region_id, n, r, tries=6000, snap=CELL // 2):
    rmin, rmax = next((a, b) for rid, a, b, _ in REGIONS if rid == region_id)
    out = []
    for _ in range(tries):
        if len(out) >= n:
            break
        # things stand on the grid's crossings and half-crossings, as if the machine had placed them
        x = round(random.uniform(rmin[0], rmax[0]) / snap) * snap
        y = round(random.uniform(rmin[1], rmax[1]) / snap) * snap
        if clear(x, y, r):
            placed.append((x, y, r))
            out.append((x, y))
    return out


TREES = []
PROPS = []


def trees(region, n, r=30):
    for x, y in scatter(region, n, r):
        TREES.append([x, y])


def props(region, n, type, label, r=18, solid=None, radius=None, color=WHITE):
    for i, (x, y) in enumerate(scatter(region, n, r)):
        PROPS.append(prop("%s_%s_%d" % (region, type, i), type, (x, y), color, label, solid=solid, radius=radius))


for reg, n_trees, chips, caps, coils, bits in [
    ("the_heap", 150, 2, 2, 1, 14), ("the_inlet", 46, 1, 2, 1, 8), ("arcade", 30, 0, 2, 2, 8),
    ("the_cache", 34, 16, 18, 8, 16), ("the_bus", 40, 2, 2, 2, 10), ("clock_court", 44, 2, 3, 2, 12),
    ("dark_sector", 40, 3, 4, 3, 10),
]:
    trees(reg, n_trees)
    props(reg, chips, "oh_chip", "a chip", r=26, solid=True, radius=12, color=CYAN)
    props(reg, caps, "oh_capacitor", "a capacitor", r=18, solid=True, radius=5, color=CYAN)
    props(reg, coils, "oh_coil", "a coil", r=18, solid=True, radius=6, color=CYAN)
    props(reg, bits, "oh_bit", "a loose bit", r=10, color=CYAN)

ALL_PROPS = SPECIAL + PROPS

# ── the runners: closed routes along the bright lines (every corner a multiple of 128) ─────────────────
def loop(*pts):
    return [list(p) for p in pts]


RUNNER_ROUTES = [
    loop((-1408, 128), (1408, 128), (1408, -128), (-1408, -128)),                     # round the Bus
    loop((-1408, 256), (-1408, 1024), (-896, 1024), (-896, 256)),                     # the inlet
    loop((-384, -256), (384, -256), (384, -1024), (-384, -1024)),                     # the clock court
    loop((512, -256), (512, -1024), (640, -1024), (640, -256)),                       # past the dark sector, the long way round
    loop((512, 256), (1408, 256), (1408, 1024), (512, 1024)),                         # the cache
    loop((-1408, -256), (-640, -256), (-640, -1024), (-1408, -1024)),                 # the heap
    loop((-768, 256), (256, 256), (256, 896), (-768, 896)),                           # round the Arcade
    loop((1280, -256), (1408, -256), (1408, -1024), (1280, -1024)),                   # east of the dark sector
]
RUNNERS = {"speed": 42.0, "per_route": 2, "sheet": "res://assets/sprites/oh_runner.png", "frame": 16, "frames": 4, "fps": 8,
           "shy_radius": 46.0, "trail": 22.0, "routes": RUNNER_ROUTES}

S = "res://assets/sprites/"


def tree_variants(names):
    return [{"trunk": S + "oh_%s_trunk.png" % n, "canopy": S + "oh_%s_canopy.png" % n} for n in names]


PROP_TYPES = ["oh_lamp", "oh_cabin", "oh_tower", "oh_sign", "oh_terminal", "oh_chip", "oh_capacitor", "oh_coil", "oh_pylon",
              "oh_bit", "oh_arcade_sign", "oh_today_sign", "oh_fount", "oh_gate"]
VOID = [0.02, 0.012, 0.05]
ART = {
    # the dark, and lines of light on it. Each colour has one job: cyan the world, magenta a person, amber a
    # companion (and warmth), violet the way home, red where the power is out, mint the runners.
    "palette": {
        "ground_top": VOID, "ground_bottom": VOID,
        "foliage_dark": [0.03, 0.03, 0.09], "foliage_mid": [0.10, 0.30, 0.38], "foliage_light": [0.37, 0.95, 1.0],
        "bark": [0.23, 0.59, 0.75], "water": [0.05, 0.10, 0.22], "rim": [0.37, 0.95, 1.0],
        "shadow": [0.0, 0.0, 0.0], "grass": VOID, "water_rim": [0.37, 0.95, 1.0, 0.7],
    },
    "light": {"shadow_alpha": 0.0, "rim_strength": 0.0},
    "entities": {
        "portal": {"frame_tint": [0.62, 0.50, 1.0],
                   "wire": {"line_color": [0.72, 0.55, 1.0], "inner_color": [0.88, 0.80, 1.0], "fill_color": [0.03, 0.02, 0.08, 0.86],
                            "line_cut": 0.16, "edge": 0.46, "keep": 0.10, "pulse_speed": 1.2}},
        "ground": {
            "render": "grid", "cell": CELL, "major": MAJOR,
            "void_color": VOID, "line_color": [0.37, 0.95, 1.0], "dead_color": [0.24, 0.18, 0.43],
            "step_color": [1.0, 0.31, 0.85], "paw_color": [1.0, 0.71, 0.28],
            "minor_alpha": 0.20, "major_alpha": 0.78, "halo": 0.22, "fade": 220.0,
            "pulse_speed": 70.0, "pulse_life": 2.4, "step_spacing": 26.0,
        },
        "understory": {"render": "sprite", "prefix": S + "oh_understory_", "types": ["bush_a", "bush_b", "stump"], "density": 0.3},
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 0}, "clouds": {"count": 0, "alpha": 0.0, "speed": 0},
                         "leaves": {"rate": 0.0, "colors": [[0.37, 0.95, 1.0]]}},
        "tree": {"render": "sprite", "sway": 0.0, "variants": tree_variants(["pine_a", "pine_b", "pine_c", "geo_a", "geo_b", "ball_a", "cube_a"])},
        "great_tree": {"render": "sprite", "sway": 0.0, "variants": tree_variants(["great_mast", "great_dome"])},
        "props": {"extra_types": PROP_TYPES},
        "prop_lights": {"oh_lamp": {"radius": 34, "y": -18, "alpha": 0.34},
                        "oh_cabin": {"radius": 22, "y": -4, "alpha": 0.22},
                        "oh_fount": {"radius": 60, "y": -20, "alpha": 0.30},
                        "oh_arcade_sign": {"radius": 40, "y": -18, "alpha": 0.20},
                        "oh_today_sign": {"radius": 36, "y": -18, "alpha": 0.20},
                        "oh_pylon": {"radius": 18, "y": -16, "alpha": 0.30}},
    },
    "actor_look": {
        "wire": {
            "line_cut": 0.20, "edge": 0.20, "keep": 0.16, "pulse_speed": 1.6, "aura_radius": 16.0, "aura_strength": 0.55,
            "fill_color": [0.03, 0.02, 0.08, 0.86],
            "player": {"line_color": [1.0, 0.55, 0.90], "inner_color": [0.93, 0.98, 1.0]},
            "companion": {"line_color": [1.0, 0.71, 0.28], "inner_color": [1.0, 0.90, 0.66]},
        },
    },
    "daycycle": {"enabled": False},
}

ATMOSPHERE = {
    "day_tint": [1.0, 1.0, 1.0],
    "vignette": {"strength": 0.52, "color": VOID},
    "scanlines": {"strength": 0.16, "spacing": 3.0},
    "wind": {"strength": 0.0, "speed": 0.0},
    "pollen": {"amount": 16, "color": [0.62, 0.92, 1.0]},
    "glow": {"pulse_speed": 0.8},
    "region_tint_alpha": 0.0,
    "grass": {"max": 0},
}

HEADER = ("OHMSTEAD - the machine behind the Gateway. A black void and a glowing grid floor (art.entities.ground.render "
          "'grid': GridGround, one shader), everything on it a bright outline, visitors redrawn as linework "
          "(art.actor_look.wire). Seven regions: the Inlet (where you arrive), the Arcade, the Cache, the Bus, the Heap, "
          "Clock Court and the Dark Sector. 'runners': closed routes little mint runners follow, a pure function of time. "
          "'circuits': the ribbon boards (CircuitBoard / CircuitDirector on the client, Server.Circuit on the server): "
          "'sector' is the secret's (reveal type 'circuit'), 'table' and 'today' are the Arcade's. Generated by "
          "tools/gen_ohmstead_world.py (art: pokepals/tools/gen_ohmstead.py) - edit that and re-run, don't hand-tune positions.")

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Ohmstead'). reveal.type 'circuit': the board "
                  "named by reveal.board (in 'circuits') has to be closed, one ribbon through every node from its source to its "
                  "sink, laid by a companion node by node; then the prop appears at 'position'. The board's state is shared and "
                  "server-authoritative (Server.Circuit), so unlike most reveals the server CAN check it: a claim is honoured "
                  "only while that board is closed, here, within 'radius' of 'position'.")
SECRET = {
    "id": "steady_spark",
    "position": list(SECRET_POS),
    "radius": 170.0,
    "prop": {"type": "steady_spark", "color": [1.0, 0.96, 0.82], "label": "a steady spark", "tags": ["glowing", "small", "bright"]},
    "lore": "One small spark, holding perfectly still in the middle of the lit board. Everything else here flickers a little. This doesn't. Your companion puts its nose very near it, and its outline goes a shade warmer.",
    "reveal": {
        "type": "circuit",
        "board": "sector",
        "dark_line": "The sector's power fades again, and the spark goes out with it. Close the loop once more and it will be back.",
        "lit_line": "Someone closed the loop here a little while ago: the sector is lit, and in the middle of the board something small and steady is waiting.",
        "reveal_line": "The last node takes the light. Power runs back across the sector line by line, and in the middle of the board something small and steady is waiting.",
    },
    "found_line": "The loop is closed, and the machine has one fewer thing to worry about. The spark that held it goes home with you.",
    "home_line": "Something has changed at home.",
    "qualities": ["glowing", "small", "made"],
    "keepsake": {
        "id": "steady_spark_kept", "type": "kept_steady_spark", "color": [1.0, 0.96, 0.82], "label": "a steady spark in a jar",
        "line": "A spark in a little glass jar, not flickering. Your companion likes to lie where its light falls and watch it not move.",
        "temperament": {"curiosity": 0.7, "energy": 0.6, "clinginess": 0.4},
    },
}


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "ohmstead",')
out.append('\t"intro": %s,' % json.dumps("Behind the scenery, where the worlds are drawn. The light on these lines keeps every other place lit. One patch of it has gone dark."))
out.append('\t"chopping": false,')
out.append('\t"fishing": false,')
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"music": { "track": "res://assets/music/ohmstead.ogg", "volume_db": -22 },')  # tools/music/scores/ohmstead.score
out.append('\t"border": { "ring": false },')
out.append('\t"collision": { "tree_radius": 6, "great_tree_radius": 18, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": %s,' % json.dumps(VOID))
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [],')
out.append('\t"paths": [],')
out.append('\t"landmarks": [\n%s\n\t],' % block(LANDMARKS))
out.append('\t"trees": [\n%s\n\t],' % block(TREES))
out.append('\t"props": [\n%s\n\t],' % block(ALL_PROPS))
out.append('\t"runners": %s,' % json.dumps(RUNNERS, separators=(", ", ": ")))
out.append('\t"circuits": %s,' % json.dumps(CIRCUITS, indent="\t", ensure_ascii=False).replace("\n", "\n\t"))
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
# the sector's board: its solution really is one stroke through every live node, from source to sink
sol = SECTOR_BOARD["solution"]
live = set(range(SECTOR_COLS * SECTOR_ROWS)) - set(SECTOR_BOARD["holes"])
assert set(sol) == live and len(sol) == len(live), "the solution visits every live node once"
assert sol[0] == SECTOR_BOARD["source"] and sol[-1] == SECTOR_BOARD["sink"]
for a, b in zip(sol, sol[1:]):
    assert b in neighbours(a, SECTOR_COLS, SECTOR_ROWS), "the solution steps node to neighbouring node"
# every board lies inside the bounds, on the grid, and nothing solid stands on it
for b in CIRCUITS["boards"]:
    x0, y0, x1, y1 = board_rect(b["origin"], b["cols"], b["rows"])
    assert x0 % CELL == 0 and y0 % CELL == 0, "boards sit on the grid"
    assert BOUNDS_MIN[0] + 60 < x0 and x1 < BOUNDS_MAX[0] - 60 and BOUNDS_MIN[1] + 60 < y0 and y1 < BOUNDS_MAX[1] - 60
    for p in d["props"]:
        px, py = p["position"]
        assert not (x0 - 20 <= px <= x1 + 20 and y0 - 20 <= py <= y1 + 20), "a prop stands on board %s: %s" % (b["id"], p["id"])
    for t in d["trees"]:
        assert not (x0 - 24 <= t[0] <= x1 + 24 and y0 - 24 <= t[1] <= y1 + 24), "a tree stands on board %s" % b["id"]
bx0, by0, bx1, by1 = board_rect(SECTOR_ORIGIN, SECTOR_COLS, SECTOR_ROWS)
assert sx0 < bx0 and bx1 < sx0 + sw and sy0 < by0 and by1 < sy0 + sh, "the sector's board lies inside its dark patch"
assert abs(SECRET_POS[0] - (bx0 + bx1) / 2) < 1 and abs(SECRET_POS[1] - (by0 + by1) / 2) < 1
# runner routes: closed, axis-aligned, on the bright lines, and none crosses the dark sector or a board
for route in RUNNER_ROUTES:
    for (ax, ay), (bx, by) in zip(route, route[1:] + route[:1]):
        assert ax == bx or ay == by, "a runner's route turns only at right angles"
        assert ax % BIG == 0 and ay % BIG == 0, "a runner's route follows the bright lines"
        for x0, y0, x1, y1 in [(sx0, sy0, sx0 + sw, sy0 + sh), board_rect(TABLE_ORIGIN, TABLE_COLS, TABLE_ROWS, 20),
                               board_rect(DAY_ORIGIN, DAY_COLS, DAY_ROWS, 20)]:
            lo_x, hi_x, lo_y, hi_y = min(ax, bx), max(ax, bx), min(ay, by), max(ay, by)
            assert not (lo_x < x1 and hi_x > x0 and lo_y < y1 and hi_y > y0) or (hi_x == lo_x and (lo_x <= x0 or lo_x >= x1)) \
                or (hi_y == lo_y and (lo_y <= y0 or lo_y >= y1)), "a runner's route crosses a board"
print("props:", len(d["props"]), "| trees:", len(d["trees"]), "| sector board:", SECTOR_BOARD, "| secret at:", SECRET_POS)
for path in ["server/priv/world_seeds/ohmstead.json", "pokepals/tests/world_fixtures/ohmstead.json"]:
    open(path, "w").write(text)
print("wrote both files")
