#!/usr/bin/env python3
"""Generate UNDERROOT, the caves beneath the great tree, as a world spec.

A walk-and-wonder cave (2800 x 2100): twisting root tunnels and a handful of chambers, in the dark. You see
only a small soft circle round yourself (MistVeil in its darkness setting, tuned by `atmosphere.fog` below);
glow-moss, glowcaps and your companion's own light each thin the dark into a pocket, so it is hushed and
safe-dark (warm, close, a little magical), not scary. There are no enemies and no fail states.

Its one SECRET (docs/home-world-and-secrets-design.md, "Underroot"): the ROOT-HEART, a seed glowing deep in
the tangle. The tunnels are maze-ish enough that steering yourself there in the dark is genuinely hard; the
way is to DELEGATE: tap your companion, choose "Go look", and FOLLOW its light (reveal type "follow": the pure
FollowGuide and FollowDirector on the client). It leads through the tunnels and waits when you fall behind;
if you push ahead of it, it holds back (and in the end lets the lead go). Every number (how far it can sense
by bond, its pace, how patient it is) lives in this file's data, not in code.

Hand-authored: the grid size, the chambers, the heart's place, every lore line, the art override, the secret.
Procedural (seeded, so re-running reproduces it): the tunnel maze (a randomised depth-first spanning tree with
a few extra loops, searched over seeds until the way from the arrival to the heart is a pleasant length), and
the scatter of glow-moss and fixtures. The generator checks that the heart is reachable, that the way there
runs to about 50 to 65 cells, and that nothing solid blocks a tunnel.

Art assets come from pokepals/tools/gen_underroot.py. Writes the server seed and the client test fixture.
Run from the repo root:  python3 tools/gen_underroot_world.py
"""
import json
import math
import random
from collections import deque

# ── the grid ─────────────────────────────────────────────────────────────────────────────────────────
COLS, ROWS, P = 21, 15, 120          # cells and pitch (px between tunnel centre lines)
THICK = 30                           # wall thickness: a tunnel is P - THICK = 90 px clear
X0, Y0 = -COLS * P // 2, -ROWS * P // 2
BOUNDS_MIN = (-1400, -1050)
BOUNDS_MAX = (1400, 1050)


def cell_center(i, j):
    return (X0 + (i + 0.5) * P, Y0 + (j + 0.5) * P)


ENTRANCE = (10, 13)                   # the cell the way in stands in (inside the Rootfall chamber)
PLAYER_SPAWN = [0, 840]
COMPANION_SPAWN = [-30, 868]
PORTALS = [
    {"id": "underroot_way_home", "type": "portal", "position": [-86, 840], "color": [0.70, 0.92, 0.66], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

# chambers: (id, cols a..b, rows a..b, label) -- every wall inside is knocked out
CHAMBERS = [
    ("rootfall",       (9, 11),  (13, 14), "the Rootfall"),
    ("heartwood",      (1, 3),   (1, 3),   "the Heartwood"),
    ("drip_hall",      (8, 11),  (1, 3),   "the Drip Hall"),
    ("hush_pools",     (2, 4),   (11, 13), "the Hush Pools"),
    ("glowcap_garden", (1, 3),   (6, 8),   "the Glowcap Garden"),
    ("lantern_room",   (16, 19), (1, 2),   "the Lantern Room"),
    ("old_stair",      (16, 19), (6, 8),   "the Old Stair"),
    ("cairn_row",      (16, 19), (11, 13), "Cairn Row"),
    ("the_tangle",     (8, 12),  (6, 8),   "the Tangle"),
]
HEART_CELL = (2, 2)                   # the middle of the Heartwood
HEART = cell_center(*HEART_CELL)

# regions: nine areas in a 3 x 3 split of the grid, one per chamber (tinted a touch)
REGION_TINTS = {
    "heartwood": (0.98, 0.84, 0.50), "drip_hall": (0.60, 0.74, 0.90), "lantern_room": (0.92, 0.78, 0.55),
    "glowcap_garden": (0.70, 0.60, 0.92), "the_tangle": (0.58, 0.74, 0.60), "old_stair": (0.80, 0.66, 0.52),
    "hush_pools": (0.50, 0.70, 0.86), "rootfall": (0.74, 0.90, 0.62), "cairn_row": (0.72, 0.72, 0.78),
}
REGION_GRID = [   # (id, col range, row range)
    ("heartwood", (0, 6), (0, 4)), ("drip_hall", (7, 13), (0, 4)), ("lantern_room", (14, 20), (0, 4)),
    ("glowcap_garden", (0, 6), (5, 9)), ("the_tangle", (7, 13), (5, 9)), ("old_stair", (14, 20), (5, 9)),
    ("hush_pools", (0, 6), (10, 14)), ("rootfall", (7, 13), (10, 14)), ("cairn_row", (14, 20), (10, 14)),
]


def chamber_of(i, j):
    for cid, (a, b), (c, d), _ in CHAMBERS:
        if a <= i <= b and c <= j <= d:
            return cid
    return None


# ── the maze: open[(i, j)] = set of neighbours it is open to ─────────────────────────────────────────
def build_maze(seed):
    rng = random.Random(seed)
    openn = {(i, j): set() for i in range(COLS) for j in range(ROWS)}

    def link(a, b):
        openn[a].add(b)
        openn[b].add(a)

    # randomised depth-first search: long, winding corridors with few branches
    start = (rng.randrange(COLS), rng.randrange(ROWS))
    seen = {start}
    stack = [start]
    while stack:
        cur = stack[-1]
        i, j = cur
        nbrs = [n for n in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1)) if n in openn and n not in seen]
        if not nbrs:
            stack.pop()
            continue
        nxt = rng.choice(nbrs)
        link(cur, nxt)
        seen.add(nxt)
        stack.append(nxt)
    # chambers: every wall inside one comes out
    for cid, (a, b), (c, d), _ in CHAMBERS:
        for i in range(a, b + 1):
            for j in range(c, d + 1):
                for n in ((i + 1, j), (i, j + 1)):
                    if n[0] <= b and n[1] <= d:
                        link((i, j), n)
    # a few loops, so it is a tangle rather than a single winding road
    walls = [((i, j), n) for i in range(COLS) for j in range(ROWS) for n in ((i + 1, j), (i, j + 1))
             if n in openn and n not in openn[(i, j)]]
    rng.shuffle(walls)
    for a, b in walls[: int(len(walls) * 0.045)]:
        link(a, b)
    return openn


def distances(openn, src):
    d = {src: 0}
    q = deque([src])
    while q:
        c = q.popleft()
        for n in openn[c]:
            if n not in d:
                d[n] = d[c] + 1
                q.append(n)
    return d


MAZE_SEED = None
OPEN = None
for s in range(1, 20000):
    o = build_maze(s)
    d = distances(o, ENTRANCE)
    if len(d) == COLS * ROWS and 50 <= d[HEART_CELL] <= 62:
        # and a maze with real texture: plenty of dead ends
        dead = sum(1 for c, n in o.items() if len(n) == 1)
        if dead >= 28:
            MAZE_SEED, OPEN = s, o
            break
assert OPEN is not None, "no maze seed met the route-length target"
DIST = distances(OPEN, ENTRANCE)
ROUTE_CELLS = DIST[HEART_CELL]

# ── turn the closed walls into merged runs (the maze's hedges) ────────────────────────────────────────
H_WALL = set()   # (i, j): the horizontal wall on the line y = Y0 + j*P, spanning column i
V_WALL = set()   # (i, j): the vertical wall on the line x = X0 + i*P, spanning row j
for j in range(ROWS + 1):
    for i in range(COLS):
        if j == 0 or j == ROWS:
            H_WALL.add((i, j))
        elif (i, j) not in OPEN[(i, j - 1)]:
            H_WALL.add((i, j))
for i in range(COLS + 1):
    for j in range(ROWS):
        if i == 0 or i == COLS:
            V_WALL.add((i, j))
        elif (i, j) not in OPEN[(i - 1, j)]:
            V_WALL.add((i, j))


def vertex_has_vertical(i, j):    # a vertical wall touches the grid vertex (i, j)
    return (i, j - 1) in V_WALL or (i, j) in V_WALL


def vertex_has_horizontal(i, j):
    return (i - 1, j) in H_WALL or (i, j) in H_WALL


HEDGES = []
for j in range(ROWS + 1):                       # horizontal runs
    i = 0
    while i < COLS:
        if (i, j) in H_WALL:
            k = i
            while k + 1 < COLS and (k + 1, j) in H_WALL:
                k += 1
            x_a, x_b = X0 + i * P, X0 + (k + 1) * P
            if vertex_has_vertical(i, j):
                x_a -= THICK // 2
            if vertex_has_vertical(k + 1, j):
                x_b += THICK // 2
            y = Y0 + j * P
            HEDGES.append({"from": [x_a, y], "to": [x_b, y], "thickness": THICK})
            i = k + 1
        else:
            i += 1
for i in range(COLS + 1):                       # vertical runs
    j = 0
    while j < ROWS:
        if (i, j) in V_WALL:
            k = j
            while k + 1 < ROWS and (i, k + 1) in V_WALL:
                k += 1
            y_a, y_b = Y0 + j * P, Y0 + (k + 1) * P
            if vertex_has_horizontal(i, j):
                y_a -= THICK // 2
            if vertex_has_horizontal(i, k + 1):
                y_b += THICK // 2
            x = X0 + i * P
            HEDGES.append({"from": [x, y_a], "to": [x, y_b], "thickness": THICK})
            j = k + 1
        else:
            j += 1

# ── the pools (still, black water, in the chambers) ──────────────────────────────────────────────────
WATER = [0.05, 0.10, 0.16]
PONDS = [
    {"center": [round(c) for c in cell_center(3, 12)], "radius": 38, "color": WATER},             # Hush Pools
    {"center": [round(cell_center(2, 11)[0] - 10), round(cell_center(2, 11)[1] + 18)], "radius": 30, "color": WATER},
    {"center": [round(cell_center(9, 2)[0]), round(cell_center(9, 2)[1])], "radius": 34, "color": WATER},          # Drip Hall
    {"center": [round(cell_center(11, 1)[0] + 20), round(cell_center(11, 1)[1])], "radius": 28, "color": WATER},
    {"center": [round(cell_center(18, 12)[0]), round(cell_center(18, 12)[1] + 14)], "radius": 26, "color": WATER},  # Cairn Row
]

LANDMARKS = [
    {"type": "great_tree", "position": [0, 720]},        # the great root, coming down into the Rootfall
    {"type": "great_tree", "position": [0, -30]},        # a column of moss in the middle of the Tangle
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


AQUA = (0.46, 0.96, 0.78)
GOLD = (1.0, 0.82, 0.46)
VIOLET = (0.78, 0.62, 1.0)
WHITE = (1.0, 1.0, 1.0)

# ── hand-placed fixtures: the things to look at, and the hints at how to find the heart ──────────────
SPECIAL = []


def at(i, j, dx=0, dy=0):
    c = cell_center(i, j)
    return (c[0] + dx, c[1] + dy)


SPECIAL += [
    prop("rootfall_stone", "ur_stone", (-70, 780), WHITE, "a flat stone with scratches on it",
         "Letters have been scratched into a flat stone, by someone patient. 'To whoever comes down: do not hurry. The dark here is not hungry, only large. Let your companion go first, and follow its light.' Below, smaller: 'It knows the way better than you do. Tap it, and ask it to Go look.'", solid=True, radius=8),
    prop("rootfall_moss_a", "ur_glowmoss", (60, 790), AQUA, "a patch of glow-moss"),
    prop("rootfall_moss_b", "ur_glowmoss", (-120, 700), AQUA, "a patch of glow-moss"),
    prop("rootfall_moss_c", "ur_glowmoss", (110, 850), GOLD, "a patch of glow-moss"),
    prop("rootfall_caps", "ur_glowcap", (130, 740), VIOLET, "a few glowcaps"),
    prop("rootfall_sprout", "ur_sprout", (-130, 760), GOLD, "a pale seedling",
         "A pale seedling, no taller than your hand, has come up out of the loam and leaned itself, with great effort, toward the way you came in. It is leaning toward a light that is a very long way up. Its tip glows, a little, in case that helps.", solid=False),
    prop("tangle_lantern", "ur_lantern", at(9, 7, 20, 10), WHITE, "an old iron lantern",
         "An iron lantern, long cold, set down neatly on the floor. Someone came this way once with a light of their own, and put it down, and went on without it. You like to think they didn't need it any more."),
    prop("tangle_knot", "ur_rootknot", at(11, 6, 0, 24), WHITE, "a knot of root",
         "A root as thick as your waist has tied itself into a knot, perhaps to see what that was like. It looks pleased with the result.", solid=True, radius=9),
    prop("garden_cap_a", "ur_glowcap", at(2, 7, -26, 20), VIOLET, "glowcaps",
         "Pale caps, glowing the colour of a thought you almost had. They sway, though nothing here is moving. Your companion's nose twitches at them and then, politely, at nothing.", solid=False),
    prop("pools_drip", "ur_drip", at(3, 11, 28, -20), WHITE, "a dripping stone",
         "Drip. Pause. Drip. A single bright drop falls from the dark above onto a stone that has been worn into a bowl by exactly this. You count to eleven between drops, and then lose your place, happily.", solid=True, radius=6),
    prop("drip_door", "ur_door", at(9, 3, 30, 22), WHITE, "a very small door",
         "A very small round door, set into the side of a root, with a brass knob and one worn step. Someone small lives here. They are, you suspect, out, and would like you to keep it quiet that they leave the door unlocked.", solid=True, radius=8),
    prop("lantern_room_lantern", "ur_lantern", at(18, 1, -10, 14), WHITE, "a second cold lantern",
         "Another cold lantern, and beside it a folded blanket, and beside that a cup with a little water in it. Whoever sat here sat for a long time, in the dark, being quite all right."),
    prop("lantern_room_sprout", "ur_sprout", at(17, 2, 20, 10), AQUA, "a pale seedling",
         "A seedling, very pale, leaning toward the lantern as if it might, one day, light. It is not discouraged."),
    prop("stair_door", "ur_door", at(17, 7, -10, 22), WHITE, "a small door, with a smaller one beside it",
         "A tiny door. Beside it, an even tinier one. You step back, and decide that the whole of Underroot is probably full of doors, and you are simply too large to see most of them.", solid=True, radius=8),
    prop("stair_knot", "ur_rootknot", at(19, 8, -18, 10), WHITE, "a stair of roots",
         "The roots here have grown into steps, going up into a ceiling that is not there. They end after four. Your companion sits on the top one and looks quite proud of itself.", solid=True, radius=9),
    prop("cairn_a", "ur_cairn", at(17, 12, 10, 30), WHITE, "a little cairn",
         "A little stack of pebbles, three high, set on a flat stone. Travellers leave them for company. You add one of your own, and the stack does not fall.", solid=False),
    prop("cairn_b", "ur_cairn", at(19, 11, -20, 20), WHITE, "a little cairn",
         "Another cairn, older, mossed over at the bottom. There is a very small footprint in the clay beside it, going in the same direction as yours.", solid=False),
    prop("cairn_c", "ur_cairn", at(16, 13, 24, 0), WHITE, "a cairn of two",
         "Two pebbles, one on the other. Someone didn't have more, and wanted to mark the place anyway. It is somehow the best cairn in the cave.", solid=False),
    prop("heartwood_knot", "ur_rootknot", at(1, 2, -10, 0), WHITE, "the roots round the Heartwood",
         "The roots grow close and low round this chamber, curving in toward the middle the way a hand curls round something small. The whole room is leaning in on it.", solid=True, radius=9),
]

placed = [(p["position"][0], p["position"][1], 26) for p in SPECIAL]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 60))
placed.append((HEART[0], HEART[1], 110))
placed.append((PLAYER_SPAWN[0], PLAYER_SPAWN[1], 70))
placed.append((PORTALS[0]["position"][0], PORTALS[0]["position"][1], 50))

rng = random.Random(0x0ED100)


def pond_clear(x, y, r):
    return all(math.hypot(x - pd["center"][0], y - pd["center"][1]) > pd["radius"] + r + 14 for pd in PONDS)


def spot_ok(x, y, r):
    return pond_clear(x, y, r) and all(math.hypot(x - px, y - py) >= r + pr for px, py, pr in placed)


# ── the scatter: glow-moss along the tunnels (never solid), and the chambers' root pillars ───────────
TREES = []
PROPS = []
dead_ends = {c for c, n in OPEN.items() if len(n) == 1 and chamber_of(*c) is None}


def add(type, label, pos, color, r, solid=None, radius=None, tag=""):
    x, y = pos
    if not spot_ok(x, y, r):
        return False
    placed.append((x, y, r))
    PROPS.append(prop("%s_%d" % (tag or type, len(PROPS)), type, (x, y), color, label, solid=solid, radius=radius))
    return True


for (i, j), n in sorted(OPEN.items()):
    cx, cy = cell_center(i, j)
    ch = chamber_of(i, j)
    if ch is None:
        # tunnels: a moss patch now and then (they are the lamps that make the dark readable), a glowcap
        # at a dead end, and the odd stone tucked against a wall
        if rng.random() < 0.20:
            add("ur_glowmoss", "a patch of glow-moss", (cx + rng.uniform(-26, 26), cy + rng.uniform(-26, 26)),
                AQUA if rng.random() < 0.65 else GOLD, 22, tag="moss")
        if (i, j) in dead_ends:
            add("ur_glowmoss", "a patch of glow-moss", (cx + rng.uniform(-14, 14), cy + rng.uniform(-14, 14)), AQUA, 22, tag="moss")
            add("ur_glowcap", "a few glowcaps", (cx + rng.uniform(-24, 24), cy + rng.uniform(-24, 24)), VIOLET, 20, tag="cap")
        elif rng.random() < 0.07:
            add("ur_glowcap", "a few glowcaps", (cx + rng.uniform(-26, 26), cy + rng.uniform(-26, 26)), VIOLET if rng.random() < 0.6 else AQUA, 20, tag="cap")
        if rng.random() < 0.05:
            add("ur_stone", "a mossy stone", (cx + rng.choice([-1, 1]) * 30, cy + rng.choice([-1, 1]) * 30), WHITE, 18, solid=True, radius=8, tag="stone")
    else:
        # chambers: moss and caps through the floor, a root pillar or three
        if rng.random() < 0.30:
            add("ur_glowmoss", "a patch of glow-moss", (cx + rng.uniform(-45, 45), cy + rng.uniform(-45, 45)),
                AQUA if rng.random() < 0.6 else GOLD, 22, tag="moss")
        if rng.random() < 0.16:
            add("ur_glowcap", "a few glowcaps", (cx + rng.uniform(-40, 40), cy + rng.uniform(-40, 40)), VIOLET, 20, tag="cap")
        if ch == "glowcap_garden" and rng.random() < 0.7:
            add("ur_glowcap", "a few glowcaps", (cx + rng.uniform(-40, 40), cy + rng.uniform(-40, 40)), rng.choice([VIOLET, AQUA, GOLD]), 20, tag="cap")
        if ch == "drip_hall" and rng.random() < 0.18:
            add("ur_drip", "a dripping stone", (cx + rng.uniform(-40, 40), cy + rng.uniform(-40, 40)), WHITE, 18, solid=True, radius=6, tag="drip")
        if ch not in ("rootfall", "heartwood") and rng.random() < 0.32:
            x, y = cx + rng.uniform(-38, 38), cy + rng.uniform(-38, 38)
            if spot_ok(x, y, 28):
                placed.append((x, y, 28))
                TREES.append([round(x), round(y), rng.choice(["pillar", "pillar", "mound", "fungus"])])
        if ch == "heartwood" and (i, j) != HEART_CELL and rng.random() < 0.55:
            # a ring of low things round the heart, never in the way of it
            x, y = cx + rng.uniform(-38, 38), cy + rng.uniform(-38, 38)
            if math.hypot(x - HEART[0], y - HEART[1]) > 100 and spot_ok(x, y, 26):
                placed.append((x, y, 26))
                TREES.append([round(x), round(y), rng.choice(["mound", "fungus", "pillar"])])

ALL_PROPS = SPECIAL + PROPS

# ── the firefly glade (usable items, crafting; docs/usable-items-design.md) ─────────────────────────────
# Fireflies gather only at the END of the two dark worlds (here and Steamhollow), beside the secret, so the
# lantern they make (the tinker in the bazaar) is a reward for having found your way through once, and makes the
# second pass easier. A glass jar on a little table (a "firefly_jar" prop, appended after the layout so nothing
# else moves): examine it and a firefly drifts down into it for you. One at a time. Its faint glow thins the dark
# a little (atmosphere.fog.lit). Drawn by the client (FireflyGlade); the server checks the jar.
FIREFLY_GLADES = [{"id": "glade_heartwood", "position": [round(HEART[0]) - 50, round(HEART[1]) + 40], "radius": 44}]
for g in FIREFLY_GLADES:
    ALL_PROPS.append(prop("jar_" + g["id"], "firefly_jar_table", (g["position"][0] + 18, g["position"][1] + 24), WHITE,
                          "a glass jar on a little table",
                          'A glass jar on a little round table at the edge of the Heartwood, its lid set beside it. Fireflies drift here in the warm dark by the root-heart, the only ones in all the caves. They drift lower when you come near, as if one of them wanted to come along.',
                          tags=["made", "light"], solid=True, radius=8))
    ALL_PROPS[-1]["firefly_jar"] = True


# ── checks: nothing solid may block a tunnel (leave at least ~56 px of the 90 clear) ──────────────────
def solid_discs():
    out = [(t[0], t[1], 7) for t in TREES]
    out += [(lm["position"][0], lm["position"][1], 16) for lm in LANDMARKS]
    out += [(p["position"][0], p["position"][1], p.get("collision_radius", 8)) for p in ALL_PROPS if p.get("solid")]
    out += [(pd["center"][0], pd["center"][1], pd["radius"]) for pd in PONDS]
    return out


for x, y, r in solid_discs():
    i, j = int((x - X0) // P), int((y - Y0) // P)
    if chamber_of(i, j) is None:
        cx, cy = cell_center(i, j)
        # in a tunnel cell: the disc must sit within 22 px of a wall-facing edge, not in the middle
        assert max(abs(x - cx), abs(y - cy)) >= 22 or r <= 6, "a solid thing sits in the middle of a tunnel at %s" % ((x, y),)

# ── the world's own ART OVERRIDE (deep-merged over data/art.json by ArtStyle.load_style) ─────────────
S = "res://assets/sprites/"


def ramp(*rows):
    return [list(r) for r in rows]


def tree_variants(names):
    return [{"trunk": S + "ur_%s_trunk.png" % n, "canopy": S + "ur_%s_canopy.png" % n} for n in names]


PILLARS = ["pillar_a", "pillar_b", "pillar_c"]
MOUNDS = ["mound_a", "mound_b"]
FUNGI = ["fungus_a", "fungus_b"]
ART = {
    # a dim, earthy palette: the dark itself is the veil's job, so the art stays readable inside a pocket
    "palette": {
        "ground_top": [0.20, 0.17, 0.16], "ground_bottom": [0.16, 0.14, 0.14],
        "foliage_dark": [0.10, 0.20, 0.20], "foliage_mid": [0.20, 0.36, 0.32], "foliage_light": [0.42, 0.62, 0.52],
        "bark": [0.20, 0.14, 0.12], "water": [0.06, 0.12, 0.18], "rim": [0.80, 0.92, 0.74],
        "shadow": [0.02, 0.03, 0.06], "grass": [0.20, 0.17, 0.16], "water_rim": [0.40, 0.60, 0.66, 0.5],
    },
    "light": {"shadow_alpha": 0.30, "rim_strength": 0.10},
    "entities": {
        "portal": {"frame_tint": [0.78, 0.82, 0.70]},
        "ground": {
            "render": "pixel", "terrain": S + "ur_terrain.png", "tile": 128,
            "details": S + "ur_details.png", "details_index": "res://data/ur_details.json",
            "shade": 0.2,
            "ramps": {
                "grass": ramp((0.13, 0.10, 0.10), (0.18, 0.14, 0.13), (0.24, 0.19, 0.17), (0.34, 0.27, 0.22)),
                "lush": ramp((0.10, 0.17, 0.15), (0.14, 0.24, 0.20), (0.19, 0.31, 0.25), (0.28, 0.42, 0.32)),
                "meadow": ramp((0.19, 0.15, 0.13), (0.25, 0.20, 0.17), (0.32, 0.26, 0.21), (0.44, 0.36, 0.27)),
                "dirt": ramp((0.10, 0.08, 0.09), (0.14, 0.11, 0.11), (0.19, 0.15, 0.14), (0.27, 0.21, 0.18)),
                "sand": ramp((0.26, 0.20, 0.16), (0.34, 0.27, 0.21), (0.42, 0.34, 0.26), (0.55, 0.45, 0.33)),
                "path": ramp((0.24, 0.19, 0.15), (0.31, 0.25, 0.20), (0.38, 0.31, 0.24), (0.50, 0.42, 0.31)),
                "worn": ramp((0.16, 0.13, 0.12), (0.21, 0.17, 0.15), (0.27, 0.22, 0.18), (0.38, 0.31, 0.24)),
            },
            "accents": [[0.70, 1.0, 0.80]],
            "patches": {"lush": {"scale": 0.005, "threshold": 0.50}, "meadow": {"scale": 0.006, "threshold": 0.62},
                        "dirt": {"scale": 0.007, "threshold": 0.70}},
            "clump": {"scale": 0.009, "dark": 0.34, "light": 0.66},
            "scatter": {
                "density": 0.7,
                "open": [
                    {"names": ["mosstuft_a", "mosstuft_b"], "weight": 20, "count": [1, 3], "sway": 0.1},
                    {"names": ["rootlet", "rootlet_b"], "weight": 18, "count": [1, 3]},
                    {"names": ["pebbles"], "weight": 10, "count": [1, 3]},
                    {"names": ["stone", "puddle"], "weight": 5},
                    {"names": ["glowspeck"], "weight": 5},
                    {"names": ["clayflake", "seedpod", "bone"], "weight": 3},
                ],
                "under_trees": {"names": ["rootlet", "stone"], "ring": ["mosstuft_a"]},
                "path_edge": [],
                "reeds": [],
                "lilies": [],
            },
        },
        "understory": {"render": "sprite", "prefix": S + "ur_understory_", "types": ["fern_a", "fern_b", "stump"], "density": 0.3},
        # a few glow-worms drifting in the dark; no butterflies, no clouds, no leaves (there is no sky down here)
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 14, "color": [0.66, 1.0, 0.82], "always": True},
                         "clouds": {"count": 0}, "leaves": {"rate": 0.0, "colors": [[0.5, 0.4, 0.3]]}},
        "tree": {"render": "sprite", "sway": 0.1, "variants": tree_variants(PILLARS + MOUNDS + FUNGI)},
        "pillar": {"render": "sprite", "sway": 0.12, "variants": tree_variants(PILLARS)},
        "mound": {"render": "sprite", "sway": 0.05, "variants": tree_variants(MOUNDS)},
        "fungus": {"render": "sprite", "sway": 0.08, "variants": tree_variants(FUNGI)},
        "great_tree": {"render": "sprite", "sway": 0.08, "variants": tree_variants(["great_root", "great_moss"])},
        "water": {"render": "sprite", "tile": S + "ur_pool.png", "world_tile": 64},
        "pool": {"render": "sprite", "tile": S + "ur_pool.png", "world_tile": 64},
        "river": {"render": "sprite", "tile": S + "ur_pool.png", "world_tile": 64},
        # the tunnel walls are the maze's hedge slot, here a tangle of roots
        "hedge": {"render": "sprite", "tile": S + "ur_root_wall.png", "world_tile": 44, "highlight": [0.60, 0.44, 0.30, 0.55]},
        "props": {"extra_types": ["ur_glowmoss", "ur_glowcap", "ur_drip", "ur_rootknot", "ur_stone", "ur_lantern",
                                  "ur_sprout", "ur_door", "ur_cairn"]},
        "prop_lights": {
            "ur_glowmoss": {"radius": 34, "y": 3, "alpha": 0.40},
            "ur_glowcap": {"radius": 30, "y": -3, "alpha": 0.36},
            "ur_sprout": {"radius": 18, "y": -4, "alpha": 0.30},
        },
    },
    # held in the same low, cool light: nothing changes down here
    "daycycle": {"enabled": True, "period_sec": 600, "loop": True, "hold": 0.5, "stops": [
        {"t": 0.0, "tint": [0.86, 0.88, 0.96], "vignette": [0.03, 0.04, 0.08], "vstrength": 0.40},
        {"t": 1.0, "tint": [0.82, 0.84, 0.94], "vignette": [0.03, 0.04, 0.08], "vstrength": 0.46}]},
}

ATMOSPHERE = {
    "day_tint": [0.84, 0.88, 0.96],
    "vignette": {"strength": 0.40, "color": [0.02, 0.03, 0.06]},
    "wind": {"strength": 0.2, "speed": 0.3},
    "pollen": {"amount": 8, "color": [0.7, 1.0, 0.86]},
    "region_tint_alpha": 0.05,
    "grass": {"max": 0},
    # the defining feature: the dark. MistVeil, tuned to be nearly black, steady, and cut by pockets of light
    "fog": {
        "clear_radius": 52, "fade_radius": 175, "color": [0.015, 0.02, 0.04], "warm": [0.50, 0.95, 0.72],
        "density": 0.97, "swirl": 0.06, "noise_scale": 0.016, "drift": [1.5, 0.7], "fade_in": 2.5,
        "light_clear": 0.93, "max_lights": 8, "companion_radius": 76, "friend_radius": 60,
        "lit": {
            "prop_types": {
                "ur_glowmoss": {"radius": 64, "warm": 0.95, "x": 0, "y": 3},
                "firefly_jar_table": {"radius": 36, "warm": 1.0, "x": 0, "y": -24},
                "ur_glowcap": {"radius": 54, "warm": 0.9, "x": 0, "y": -3},
                "ur_sprout": {"radius": 30, "warm": 0.8, "x": 0, "y": -4},
            },
        },
    },
}

HEADER = ("UNDERROOT - the caves beneath the great tree. A walk-and-wonder cave (no goal, no enemies, no fail states): "
          "twisting root tunnels and nine chambers in the dark, where you see only a small soft circle round yourself "
          "(atmosphere.fog, MistVeil as a darkness) and glow-moss, glowcaps and your companion's own light thin it into "
          "pockets. Nine regions: the Rootfall (where you arrive), the Tangle, the Drip Hall, the Hush Pools, the Glowcap "
          "Garden, the Lantern Room, the Old Stair, Cairn Row and the Heartwood. The tunnel walls are 'hedges' (axis-aligned "
          "segments the nav grid already understands) drawn as roots through the art block's hedge tile. It RE-SKINS ITSELF "
          "through its 'art' block (deep-merged over data/art.json). Its secret is the root-heart: see the 'secret' block "
          "(reveal type 'follow': ask your companion to Go look and follow its light). Generated by "
          "tools/gen_underroot_world.py (art: pokepals/tools/gen_underroot.py) - edit that and re-run, don't hand-tune positions. "
          "Maze seed %d, %d cells from the arrival to the heart." % (MAZE_SEED, ROUTE_CELLS))

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Underroot'). reveal.type 'follow': a seed "
                  "glowing deep in the tangle of tunnels. You ask your companion to Go look and FOLLOW its light (FollowGuide / "
                  "FollowDirector): it leads along a route planned through the tunnels at a pace that grows with bond, waits "
                  "when you fall behind, holds back (then lets go) if you push ahead of it, and loses the scent after "
                  "'reach' px if the bond is young (ask again). When you and it have both arrived (arrive_*), the heart rises. "
                  "The server honours a claim only here, within 'radius' of 'position'.")
SECRET = {
    "id": "root_heart",
    "position": [round(HEART[0]), round(HEART[1])],
    "radius": 120.0,
    "prop": {"type": "root_heart", "color": [1.0, 0.82, 0.42], "label": "a glowing seed in the roots", "tags": ["plant", "old", "glowing", "warm"]},
    "lore": "A seed the size of an egg, held in a cradle of roots and glowing from inside, slowly, like something with a pulse. The whole cave seems to lean in round it. Your companion sits very close, as though it had known where to come all along.",
    "reveal": {
        "type": "follow",
        "reach_low": 1000.0, "reach_high": 7000.0,
        "pace_low": 74.0, "pace_high": 100.0,
        "wait_low": 150.0, "wait_high": 190.0, "resume_distance": 90.0, "give_up_distance": 900.0,
        "waypoint_reach": 26.0, "waypoint_patience": 14.0,
        "ahead_margin_low": 70.0, "ahead_margin_high": 110.0, "ahead_lateral": 75.0, "ahead_look": 700.0,
        "ahead_patience_low": 7.0, "ahead_patience_high": 14.0,
        "arrive_player": 130.0, "arrive_companion": 170.0,
        "notice_range_low": 300.0, "notice_range_high": 620.0, "notice_cooldown_low": 18.0, "notice_cooldown_high": 8.0, "notice_hold": 2.5,
        "glimmer_range": 320.0, "glimmer_radius": 54.0, "heart_radius": 120.0, "lead_light_radius": 132.0, "light_ease": 0.6,
        "drift_hold": 30.0, "pet_pause": 3.0,
        "reveal_line": "The roots part, and there it is: a seed, glowing from inside, held in the tangle like a heartbeat.",
        "lines": {
            "ask": "You ask your companion to go look. Its light swells, and it sets off into the dark. Stay behind it, and follow.",
            "wait": "It stops, and waits, turning its light back toward you. It will not go on without you.",
            "balk": "Your companion stops short and dims its light. It won't lead from behind you. Fall in behind it, and it will go on.",
            "let_go": "It gives up the lead and comes to walk beside you. Ask it to go look again, and let it go first.",
            "scent_lost": "Your companion's light dips. It has lost the way, for now. Ask it to go look again.",
            "lost": "Your companion lets the way go, and comes back to you.",
            "called": "Your companion comes back to you. Ask it to go look again, whenever you are ready.",
            "notice": "Your companion stops, and looks into the dark. Something down here is glowing, and it can feel it.",
            "at_heart": "It stops, and its light steadies. It has brought you here.",
            "no_way": "Your companion looks around, and can find no way from here.",
        },
    },
    "found_line": "It was here all along, in the dark, glowing for anyone who would stop hunting for it and follow.",
    "home_line": "Something has changed at home.",
    "qualities": ["quiet", "glowing", "old"],
    "keepsake": {
        "id": "root_heart_kept", "type": "kept_root_heart", "color": [1.0, 0.82, 0.42], "label": "a seed wrapped in small roots",
        "line": "A seed from the deepest root of the great tree, glowing slowly. Your companion curls up beside it, and its eyes catch the light.",
        "temperament": {"curiosity": 0.5, "energy": 0.2, "clinginess": 0.7},
    },
}


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


region_objs = []
for rid, (c0, c1), (r0, r1) in REGION_GRID:
    region_objs.append({"id": rid, "min": [X0 + c0 * P, Y0 + r0 * P], "max": [X0 + (c1 + 1) * P, Y0 + (r1 + 1) * P],
                        "tint": [round(c, 2) for c in REGION_TINTS[rid]]})
# the outermost regions reach the bounds, so every walkable point is in one
region_objs[0]["min"] = list(BOUNDS_MIN)
region_objs[2]["max"][0] = BOUNDS_MAX[0]
region_objs[2]["min"][1] = BOUNDS_MIN[1]
for k in (0, 1, 2):
    region_objs[k]["min"][1] = BOUNDS_MIN[1]
for k in (6, 7, 8):
    region_objs[k]["max"][1] = BOUNDS_MAX[1]
for k in (0, 3, 6):
    region_objs[k]["min"][0] = BOUNDS_MIN[0]
for k in (2, 5, 8):
    region_objs[k]["max"][0] = BOUNDS_MAX[0]

out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "underroot",')
out.append('\t"intro": %s,' % json.dumps("Under the great tree the roots go down a long way. It is very dark and perfectly quiet, and you can see only as far as your own feet and the glow of the moss. Somewhere in the tangle something is glowing. Tap your companion and choose Go look, then follow its light."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.17, 0.14, 0.13],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [\n%s\n\t],' % block(PONDS))
out.append('\t"paths": [],')
out.append('\t"hedges": [\n%s\n\t],' % block(HEDGES))
out.append('\t"landmarks": [\n%s\n\t],' % block(LANDMARKS))
out.append('\t"trees": [\n%s\n\t],' % block(TREES))
out.append('\t"props": [\n%s\n\t],' % block(ALL_PROPS))
out.append('\t"_firefly_glades_comment": %s,' % json.dumps("Where fireflies gather (usable items, crafting): beside the secret, at the end of the world. The glade has a glass jar on a little table (a 'firefly_jar' prop): examine it and a firefly drifts down into the jar for you. You carry one at a time; the tinker in the bazaar makes a lantern with one. The server honours a catch only at a jar."))
out.append('\t"firefly_glades": [\n%s\n\t],' % block(FIREFLY_GLADES))
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
assert len(DIST) == COLS * ROWS, "some cell is unreachable"
assert 50 <= ROUTE_CELLS <= 62
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("maze seed:", MAZE_SEED, "| route to the heart: %d cells (~%d px)" % (ROUTE_CELLS, ROUTE_CELLS * P),
      "| hedges:", len(HEDGES), "| props:", len(d["props"]), "| trees:", kinds, "| dead ends:", sum(1 for n in OPEN.values() if len(n) == 1))
for path in ["server/priv/world_seeds/underroot.json", "pokepals/tests/world_fixtures/underroot.json"]:
    open(path, "w").write(text)
print("wrote both files")
