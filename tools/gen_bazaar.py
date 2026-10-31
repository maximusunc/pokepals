#!/usr/bin/env python3
"""Generate the Bazaar: a compact, lantern-lit souk (docs/home-world-and-secrets-design.md, W-5).

One winding covered lane between sandstone walls, always evening: you arrive at its east end, it turns
north into a small square with a fountain, leaves west, and turns north again to the great arch at the
far end (facing you as you walk up to it). Stalls line the lane shoulder to shoulder with someone minding
nearly every one, people walk it, strings of lights, bunting and brass lanterns hang overhead, rugs lie on
the cobbles, and a narrow forgotten alley off the west lane hides the river-drop.

How the space is built: the lane is a union of axis-aligned WALKABLE rects. It's rasterized on a 10 px
grid; the WALLS are the outline of that shape (merged into long segment solids, each tagged with the side
the street is on, so only street-facing runs get arches), and the ROOFS are everything else (merged into
rects). Stalls are placed against the walls, never in an opening. Deterministic (seeded): re-running
reproduces the same layout. Writes both the server seed and the client test fixture.
"""
import json, math, random

rng = random.Random(0x50E4A2)

CELL = 10
WALL_T = 30.0

# ── the walkable lane, as rects (x0, y0, x1, y1); +y is south (down the screen) ─────────────────────────
RECTS = {
    "entry_lane":  (420, 260, 1100, 510),   # where you arrive (east end), running west
    "turn_north":  (420, -60, 670, 510),    # bends north toward the square
    "the_square":  (-40, -220, 420, 180),   # the little square with its fountain
    "west_lane":   (-560, -170, -40, 80),   # leaves the square, west
    "arch_lane":   (-560, -620, -310, 80),  # turns north to the great arch
    "forgotten_alley": (-430, 80, -320, 330),  # a narrow dead end off the west lane
}
REGION_OF = {"entry_lane": "the_lane", "turn_north": "the_lane", "the_square": "the_square",
             "west_lane": "the_lane", "arch_lane": "the_lane", "forgotten_alley": "forgotten_alley"}
REGION_TINT = {"the_lane": (0.92, 0.66, 0.40), "the_square": (0.96, 0.74, 0.44), "forgotten_alley": (0.40, 0.42, 0.52)}

xs = [r[0] for r in RECTS.values()] + [r[2] for r in RECTS.values()]
ys = [r[1] for r in RECTS.values()] + [r[3] for r in RECTS.values()]
BOUNDS_MIN = (min(xs) - 60, min(ys) - 80)
BOUNDS_MAX = (max(xs) + 60, max(ys) + 60)

NX = (BOUNDS_MAX[0] - BOUNDS_MIN[0]) // CELL
NY = (BOUNDS_MAX[1] - BOUNDS_MIN[1]) // CELL


def walkable_cell(ix, iy):
    if ix < 0 or iy < 0 or ix >= NX or iy >= NY:
        return False
    x = BOUNDS_MIN[0] + ix * CELL + CELL / 2
    y = BOUNDS_MIN[1] + iy * CELL + CELL / 2
    return any(r[0] <= x <= r[2] and r[1] <= y <= r[3] for r in RECTS.values())


WALK = [[walkable_cell(ix, iy) for ix in range(NX)] for iy in range(NY)]


def walkable(x, y):
    ix = int((x - BOUNDS_MIN[0]) // CELL)
    iy = int((y - BOUNDS_MIN[1]) // CELL)
    return 0 <= ix < NX and 0 <= iy < NY and WALK[iy][ix]


def wx(ix):
    return BOUNDS_MIN[0] + ix * CELL


def wy(iy):
    return BOUNDS_MIN[1] + iy * CELL


# ── walls: the outline of the walkable shape, merged into long runs ───────────────────────────────────
walls = []
# Horizontal edges between rows iy-1 and iy. "down" = the street is below the edge (you see its face).
for iy in range(NY + 1):
    run = None
    for ix in range(NX + 1):
        above = iy > 0 and ix < NX and WALK[iy - 1][ix]
        below = iy < NY and ix < NX and WALK[iy][ix]
        face = "down" if (below and not above) else ("up" if (above and not below) else None)
        if run and (face != run[1]):
            walls.append({"from": [wx(run[0]), wy(iy)], "to": [wx(ix), wy(iy)], "thickness": WALL_T, "face": run[1]})
            run = None
        if face and not run:
            run = (ix, face)
for ix in range(NX + 1):
    run = None
    for iy in range(NY + 1):
        left = ix > 0 and iy < NY and WALK[iy][ix - 1]
        right = ix < NX and iy < NY and WALK[iy][ix]
        face = "right" if (right and not left) else ("left" if (left and not right) else None)
        if run and (face != run[1]):
            walls.append({"from": [wx(ix), wy(run[0])], "to": [wx(ix), wy(iy)], "thickness": WALL_T, "face": run[1]})
            run = None
        if face and not run:
            run = (iy, face)

# ── roofs: every non-walkable cell, merged greedily into rects ────────────────────────────────────────
roofs = []
used = [[False] * NX for _ in range(NY)]
for iy in range(NY):
    for ix in range(NX):
        if WALK[iy][ix] or used[iy][ix]:
            continue
        w = 0
        while ix + w < NX and not WALK[iy][ix + w] and not used[iy][ix + w]:
            w += 1
        h = 1
        while iy + h < NY and all(not WALK[iy + h][ix + k] and not used[iy + h][ix + k] for k in range(w)):
            h += 1
        for dy in range(h):
            for dx in range(w):
                used[iy + dy][ix + dx] = True
        roofs.append([wx(ix), wy(iy), w * CELL, h * CELL])


# ── props ─────────────────────────────────────────────────────────────────────────────────────────────
def prop(id, type, pos, color, label, tags, solid=None, r=None, lore=None, **extra):
    e = {"id": id, "type": type, "position": [round(pos[0]), round(pos[1])],
         "color": [round(c, 2) for c in color], "label": label, "tags": tags}
    if solid is not None: e["solid"] = solid
    if r is not None: e["collision_radius"] = r
    if lore is not None: e["lore"] = lore
    e.update(extra)
    # A prop opts into being examinable only if Examining it does something: it reads out a 'lore'
    # line, or it's the shopkeeper (opens the shop). Everything else stays scenery.
    if lore is not None or type == "shopkeeper": e["interactive"] = True
    return e


SQ = RECTS["the_square"]
SQ_C = ((SQ[0] + SQ[2]) / 2, (SQ[1] + SQ[3]) / 2)
ENTRY = (1030, 385)
ARCH = (-435, -460)
PLAYER_SPAWN = [955, 385]
COMPANION_SPAWN = [925, 405]

special = [
    prop("the_fountain", "fountain", SQ_C, (0.74, 0.62, 0.48), "the fountain", ["water", "made", "rest"], True, 34,
         lore="The fountain in the little square. Its water catches every lantern in the lane, so it's never quite dark here."),
    prop("great_arch", "great_arch", ARCH, (0.82, 0.64, 0.44), "the great arch", ["made", "landmark"], False,
         lore="The great arch at the end of the lane, carved with knots that never quite meet. Beyond it, the way home."),
    prop("shop_stall", "stall", (SQ[0] + 150, SQ[1] + 46), (0.74, 0.56, 0.86), "the dye-maker's shop", ["made", "market"], True, 18),
    prop("color_merchant", "shopkeeper", (SQ[0] + 150, SQ[1] + 92), (0.86, 0.62, 0.46), "the color merchant", ["person", "made"]),
    prop("wet_boots_man", "wanderer", (SQ[2] - 50, SQ[1] + 60), (0.34, 0.36, 0.42), "a man with wet boots", ["person"],
         lore="His boots are wet, though it hasn't rained here in living memory. He smiles like he knows where the water went, and asks only one thing: have you seen it too?"),
]
NPC_COMPANION = [SQ[0] + 200, SQ[1] + 92]

lanterns = [prop("lantern_sq_%d" % i, "lantern", p, (0.98, 0.78, 0.42), "a hanging lantern", ["light", "made"])
            for i, p in enumerate([(SQ[0] + 30, SQ[3] - 30), (SQ[2] - 30, SQ[3] - 30), (SQ[0] + 30, SQ[1] + 120)])]

# The forgotten alley: dim, a long-closed stall at its mouth, crates, and the river-drop at its end.
AL = RECTS["forgotten_alley"]
alley = [
    # the long-closed stall stands against the lane wall right beside the alley's mouth
    prop("alley_closed_stall", "stall", (AL[0] - 50, AL[1] - WALL_T / 2 - 26), (0.46, 0.50, 0.56), "an empty stall, long closed", ["made", "market"], True, 14,
         lore="An empty stall, its awning faded almost white. Nobody has opened it in a long time. Further in, something catches the light."),
    prop("alley_crate_1", "crate", (AL[0] + 26, AL[1] + 90), (0.44, 0.40, 0.34), "some forgotten crates", ["made", "market"], True, 9),
    prop("alley_crate_2", "crate", (AL[2] - 26, AL[1] + 170), (0.42, 0.38, 0.32), "some forgotten crates", ["made", "market"], True, 9),
]
SECRET = {
    "id": "river_drop", "position": [(AL[0] + AL[2]) / 2, AL[3] - 40], "radius": 120.0,
    "prop": {"type": "river_drop", "color": [0.55, 0.85, 1.0], "label": "a drop of river-glass", "tags": ["shiny", "odd", "glow"]},
    "lore": "At the very end of the alley, where nobody comes: a single drop of glass, no bigger than a thumbnail. A ripple of light still moves inside it, as if it remembers being water.",
    "reveal": {"type": "always"},
    "found_line": "A drop of river-water, kept in glass. Somewhere in the lane, someone once made it hold light instead.",
    "home_line": "Something has changed at home.",
    "qualities": ["crafted", "glowing"],
    "keepsake": {"id": "river_drop", "type": "river_drop", "color": [0.55, 0.85, 1.0], "label": "a drop of river-glass",
                 "line": "The drop of river-glass from the Bazaar. Your companion likes to sit where the light from it falls.",
                 "temperament": {"curiosity": 0.75, "energy": 0.45, "clinginess": 0.4}},
}

RESERVED = [(p["position"][0], p["position"][1], 46) for p in special + lanterns + alley] + [
    (ENTRY[0], ENTRY[1], 70), (PLAYER_SPAWN[0], PLAYER_SPAWN[1], 50), (NPC_COMPANION[0], NPC_COMPANION[1], 30),
    (ARCH[0], ARCH[1], 90), (SQ_C[0], SQ_C[1], 90)]

# ── stalls against the walls, shoulder to shoulder; someone minding nearly every one ──────────────────
GOODS = [("a spice stall", "spice_stall"), ("a pepper stall", "spice_stall"), ("a saffron stall", "spice_stall"),
         ("a tea stall", "spice_stall"), ("a dried-fruit stall", "spice_stall"), ("a lantern-maker's stall", "stall"),
         ("a rug stall", "stall"), ("a brass stall", "stall"), ("a perfumer's stall", "stall"), ("a sweets stall", "spice_stall"),
         ("a silk stall", "stall"), ("a glass stall", "stall"), ("a potter's stall", "stall")]
AWNINGS = [(0.78, 0.26, 0.20), (0.86, 0.56, 0.18), (0.30, 0.50, 0.56), (0.62, 0.30, 0.46), (0.82, 0.70, 0.40), (0.54, 0.32, 0.20)]
HOLDER_COLORS = [(0.86, 0.62, 0.46), (0.62, 0.72, 0.86), (0.80, 0.56, 0.66), (0.66, 0.78, 0.58),
                 (0.88, 0.76, 0.46), (0.70, 0.62, 0.82), (0.84, 0.70, 0.58), (0.58, 0.70, 0.74)]
HOLDER_LINES = [
    "\"Smell that? Cardamom from the hill farms. One pinch and the whole tea changes its mind.\"",
    "\"Try a fig. No, take two. You look like someone who's walked a long way.\"",
    "\"Every lantern in this lane was lit by someone's grandmother, once. We just keep them going.\"",
    "\"Saffron's dear this season. Worth it, though. Smell the gold in it.\"",
    "\"Sit a while if you like. Nobody hurries in the evening market.\"",
    "\"That one's made of brass and patience. Mostly patience.\"",
    "\"Honey cakes, warm from the stones. Your companion's already decided, I think.\"",
    "\"Pick a colour, any colour. My dyes hold through a hundred washes and one heartbreak.\"",
    "\"The best things in the lane are at the end of it. Or so the arch-keepers say.\"",
    "\"Silk from beyond the far hills. Feel how it pours.\"",
    "\"Lanterns, lanterns! One for every window you want to come home to.\"",
    "\"Mind the rugs, friend. Or don't; they've been walked on for a hundred years.\"",
]
HOLDER_LABELS = ["a stallholder", "a spice-seller", "a lantern-maker", "a weaver", "a sweet-seller", "a brass-seller"]

solid_spots = [(p["position"][0], p["position"][1]) for p in special + lanterns + alley]
stalls, holders = [], []


def try_stall(x, y, toward):
    """A stall at (x, y) backed onto a wall, its street side `toward` (a unit (dx, dy))."""
    # The whole footprint must be in the lane, the wall must really be right behind it (so it's never
    # in an opening), and nothing reserved or already placed may be too close.
    if not all(walkable(x + dx, y + dy) for dx in (-28, 0, 28) for dy in (-18, 0, 18)):
        return False
    if walkable(x - toward[0] * 55, y - toward[1] * 55):
        return False
    if any(math.hypot(x - rx, y - ry) < rr for rx, ry, rr in RESERVED):
        return False
    # The great arch is the lane's end: nothing stands between it and the wall behind it.
    if y < ARCH[1] + 40 and RECTS["arch_lane"][0] <= x <= RECTS["arch_lane"][2]:
        return False
    if any(math.hypot(x - sx, y - sy) < 60 for sx, sy in solid_spots):
        return False
    label, typ = rng.choice(GOODS)
    sid = "stall_%d" % (len(stalls) + 1)
    stalls.append(prop(sid, typ, (x, y), rng.choice(AWNINGS), label, ["made", "market"], True, 16))
    solid_spots.append((x, y))
    if rng.random() < 0.9:
        hx, hy = x + toward[0] * 30, y + toward[1] * 30
        holders.append(prop("holder_%d" % (len(holders) + 1), "stallholder", (hx, hy), rng.choice(HOLDER_COLORS),
                            rng.choice(HOLDER_LABELS), ["person", "market"], lore=rng.choice(HOLDER_LINES),
                            facing=[toward[0], toward[1]]))
    return True


INSET = WALL_T / 2 + 26  # wall half-thickness, then the stall's half-depth and a little room
for name, (x0, y0, x1, y1) in RECTS.items():
    if name in ("forgotten_alley",):
        continue
    for x in range(int(x0) + 40, int(x1) - 30, 64):
        try_stall(x, y0 + INSET, (0, 1))   # against the north wall, facing south into the lane
        try_stall(x, y1 - INSET, (0, -1))  # against the south wall, facing north
    for y in range(int(y0) + 50, int(y1) - 40, 60):
        try_stall(x0 + INSET + 6, y, (1, 0))   # against the west wall
        try_stall(x1 - INSET - 6, y, (-1, 0))  # against the east wall

# Rugs down the middle of the lane, every so often.
RUG_COLORS = [(0.62, 0.18, 0.16), (0.24, 0.30, 0.50), (0.56, 0.34, 0.16), (0.40, 0.20, 0.34)]
rugs = []
for name in ("entry_lane", "west_lane"):
    x0, y0, x1, y1 = RECTS[name]
    cy = (y0 + y1) / 2
    for x in range(int(x0) + 140, int(x1) - 100, 200):
        if not any(math.hypot(x - rx, cy - ry) < rr for rx, ry, rr in RESERVED):
            rugs.append(prop("rug_%d" % (len(rugs) + 1), "rug", (x, cy + 10), rng.choice(RUG_COLORS), "a worn rug", ["made"]))
for name in ("turn_north", "arch_lane"):
    x0, y0, x1, y1 = RECTS[name]
    cx = (x0 + x1) / 2
    for y in range(int(y0) + 140, int(y1) - 120, 200):
        if not any(math.hypot(cx - rx, y - ry) < rr for rx, ry, rr in RESERVED):
            rugs.append(prop("rug_%d" % (len(rugs) + 1), "rug", (cx, y), rng.choice(RUG_COLORS), "a worn rug", ["made"]))

# ── overhead: strings of lights, bunting and brass lanterns spanning the lane wall to wall ────────────
garlands = []
KINDS = ["lights", "bunting", "lights", "lanterns"]
k = 0
for name in ("entry_lane", "west_lane"):
    x0, y0, x1, y1 = RECTS[name]
    for x in range(int(x0) + 60, int(x1) - 40, 80):
        garlands.append({"from": [x, y0 + 4], "to": [x + 30, y1 - 4], "sag": 22, "kind": KINDS[k % 4]}); k += 1
for name in ("turn_north", "arch_lane"):
    x0, y0, x1, y1 = RECTS[name]
    for y in range(int(y0) + 60, int(y1) - 40, 80):
        garlands.append({"from": [x0 + 4, y], "to": [x1 - 4, y + 24], "sag": 18, "kind": KINDS[k % 4]}); k += 1
# the square: strings from its corners toward the fountain
for corner in [(SQ[0] + 8, SQ[1] + 8), (SQ[2] - 8, SQ[1] + 8), (SQ[0] + 8, SQ[3] - 8), (SQ[2] - 8, SQ[3] - 8)]:
    garlands.append({"from": list(corner), "to": [SQ_C[0], SQ_C[1] - 70], "sag": 26, "kind": "lights"})
    garlands.append({"from": list(corner), "to": [SQ_C[0], SQ_C[1] - 70], "sag": 46, "kind": "bunting"})

# ── walking traffic: people strolling the lane (server-simulated ambient pals, drawn as people) ────────
HAIR = ["base:hair_short", "base:hair_long", "base:hair_spiky"]
TOPS = ["base:tee", "base:tank"]
SKIN = ["golden", "umber", "rose", "fair"]
HAIR_COLORS = ["bark", "chestnut", "wheat", "slate", "ember"]
CLOTH = ["river", "clay", "moss", "violet", "stone", "gold"]


def random_person(r=None):
    r = r or rng
    equipped = {"body": "base:body", "legwear": "base:pants", "outfit": r.choice(TOPS),
                "footwear": "base:shoes", "hair": r.choice(HAIR)}
    if r.random() < 0.3:
        equipped["headwear"] = "base:headband"
    colors = {"skin_tone": r.choice(SKIN), "hair_color": r.choice(HAIR_COLORS), "top_color": r.choice(CLOTH),
              "legwear_color": r.choice(CLOTH), "footwear_color": r.choice(CLOTH), "headwear_color": r.choice(CLOTH)}
    return {"equipped": equipped, "colors": colors}


walkers = []
LANE_PARTS = ["entry_lane", "turn_north", "the_square", "the_square", "west_lane", "arch_lane"]
for i in range(30):
    x0, y0, x1, y1 = RECTS[LANE_PARTS[i % len(LANE_PARTS)]]
    hx = rng.uniform(x0 + 70, x1 - 70)
    hy = rng.uniform(y0 + 70, y1 - 70)
    walkers.append({"id": "walker_%d" % (i + 1), "home": [round(hx), round(hy)], "roam_radius": 110,
                    "person": {"appearance": random_person()}})

# Stallholders are real people too: each stands at their stall dressed like the walkers (the client
# draws them as a still remote PlayerView facing the lane). Their own random stream, so adding them
# moved nothing else.
holder_rng = random.Random(9137)
for h in holders:
    h["person"] = {"appearance": random_person(holder_rng)}
# ...and so is the colour merchant, minding the shop's stall (still type "shopkeeper": Examine opens the shop).
for p in special:
    if p["id"] == "color_merchant":
        p["person"] = {"appearance": random_person(holder_rng)}
        p["facing"] = [0, 1]

# ── checks ────────────────────────────────────────────────────────────────────────────────────────────
all_props = special + lanterns + stalls + holders + rugs + alley
ids = [p["id"] for p in all_props]
assert len(ids) == len(set(ids)), "duplicate ids"
for p in special + lanterns + stalls + alley:
    assert walkable(*p["position"]), "%s is outside the lane" % p["id"]
# Everything that matters is reachable from where you arrive (flood fill over walkable cells, minus solids).
def cell_of(x, y):
    return int((x - BOUNDS_MIN[0]) // CELL), int((y - BOUNDS_MIN[1]) // CELL)
blocked = set()
for p in all_props:
    if p.get("solid"):
        r = p.get("collision_radius", 8) + 8
        cx, cy = p["position"]
        for iy in range(int((cy - r - BOUNDS_MIN[1]) // CELL), int((cy + r - BOUNDS_MIN[1]) // CELL) + 1):
            for ix in range(int((cx - r - BOUNDS_MIN[0]) // CELL), int((cx + r - BOUNDS_MIN[0]) // CELL) + 1):
                if math.hypot(wx(ix) + CELL / 2 - cx, wy(iy) + CELL / 2 - cy) < r:
                    blocked.add((ix, iy))
start = cell_of(*PLAYER_SPAWN)
seen = {start}
todo = [start]
while todo:
    ix, iy = todo.pop()
    for nx, ny in ((ix + 1, iy), (ix - 1, iy), (ix, iy + 1), (ix, iy - 1)):
        if (nx, ny) in seen or not (0 <= nx < NX and 0 <= ny < NY) or not WALK[ny][nx] or (nx, ny) in blocked:
            continue
        # keep a body's width off the walls
        if not all(WALK[ny + dy][nx + dx] for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2) if 0 <= ny + dy < NY and 0 <= nx + dx < NX):
            continue
        seen.add((nx, ny))
        todo.append((nx, ny))
for what, pos in [("the secret", SECRET["position"]), ("the arch", (ARCH[0], ARCH[1] + 30)), ("the shopkeeper", special[3]["position"]),
                  ("the fountain's edge", (SQ_C[0], SQ_C[1] + 60)), ("the wet-boots man", (special[4]["position"][0], special[4]["position"][1] + 30))]:
    assert cell_of(*pos) in seen, "%s at %s isn't reachable from the entrance" % (what, pos)
print("souk: %d walls, %d roofs, %d stalls, %d stallholders, %d rugs, %d garlands, %d walkers | bounds %s..%s" % (
    len(walls), len(roofs), len(stalls), len(holders), len(rugs), len(garlands), len(walkers), BOUNDS_MIN, BOUNDS_MAX))

# ── emit ──────────────────────────────────────────────────────────────────────────────────────────────
def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


regions = []
for name, r in RECTS.items():
    reg = REGION_OF[name]
    regions.append({"id": reg if reg != "the_lane" else name, "min": [r[0], r[1]], "max": [r[2], r[3]],
                    "tint": [round(c, 2) for c in REGION_TINT[reg]]})
paths = []
for name in ("entry_lane", "west_lane"):
    x0, y0, x1, y1 = RECTS[name]
    paths.append({"from": [x0 + 20, (y0 + y1) / 2], "to": [x1 - 20, (y0 + y1) / 2], "color": [0.58, 0.46, 0.34]})
for name in ("turn_north", "arch_lane"):
    x0, y0, x1, y1 = RECTS[name]
    paths.append({"from": [(x0 + x1) / 2, y0 + 20], "to": [(x0 + x1) / 2, y1 - 20], "color": [0.58, 0.46, 0.34]})

ART = {
    "entities": {
        "ground": {
            "ramps": {
                "grass":  [[0.40, 0.30, 0.22], [0.50, 0.38, 0.28], [0.56, 0.43, 0.31], [0.66, 0.52, 0.38]],
                "lush":   [[0.38, 0.28, 0.20], [0.46, 0.35, 0.25], [0.52, 0.40, 0.29], [0.62, 0.49, 0.36]],
                "meadow": [[0.42, 0.31, 0.22], [0.52, 0.39, 0.28], [0.58, 0.44, 0.32], [0.68, 0.54, 0.40]],
                "dirt":   [[0.44, 0.32, 0.23], [0.54, 0.41, 0.30], [0.60, 0.46, 0.34], [0.72, 0.57, 0.42]],
                "path":   [[0.50, 0.38, 0.28], [0.62, 0.48, 0.36], [0.68, 0.54, 0.40], [0.80, 0.66, 0.50]],
                "worn":   [[0.48, 0.37, 0.27], [0.58, 0.46, 0.34], [0.64, 0.51, 0.38], [0.76, 0.62, 0.46]],
            },
            "accents": [[0.92, 0.56, 0.32], [0.96, 0.84, 0.46], [0.86, 0.42, 0.40], [0.98, 0.92, 0.78]],
            "scatter": {"density": 0.15, "grass_tint": [1.2, 0.95, 0.7]},
        },
        # no meadow bushes or stumps on the cobbles
        "understory": {"density": 0.0},
        # The souk's walls, roofs and unmoving stalls are drawn once into textures (StaticBake), not
        # repainted every frame. Anything that sways, flickers or glows stays live.
        "static_bake": {"enabled": True, "types": ["stall", "spice_stall", "rug", "crate"]},
        "ambient_life": {"butterflies": {"count": 0}, "clouds": {"count": 0}, "leaves": {"rate": 0.0},
                         "fireflies": {"count": 18, "always": True, "color": [1.0, 0.78, 0.42]}},
    },
    # Always evening: the day cycle held at dusk, in warm amber rather than the meadows' violet, so the
    # lanterns throw their full pools of light.
    "daycycle": {"enabled": True, "hold": 1.0, "stops": [
        {"t": 0.0, "tint": [1.02, 0.92, 0.80], "vignette": [0.10, 0.05, 0.03], "vstrength": 0.40},
        {"t": 1.0, "tint": [0.96, 0.78, 0.62], "vignette": [0.12, 0.05, 0.02], "vstrength": 0.52}]},
}

HEADER = ("THE BAZAAR: a compact, lantern-lit souk, always evening. One winding covered lane between sandstone "
          "walls: arrive at its east end, it turns north into a little square with a fountain, leaves west, and turns "
          "north again to the great arch at the far end (the way home). Stalls line it shoulder to shoulder with "
          "someone minding nearly every one; people walk it; lights, bunting and brass lanterns hang overhead; rugs "
          "lie on the cobbles; a narrow forgotten alley off the west lane hides the river-drop. Generated by "
          "tools/gen_bazaar.py: edit that and re-run, don't hand-tune. 'walls' are segment solids (each with the side "
          "its street is on, 'face'); 'roofs' are the buildings beyond them; 'garlands' hang overhead.")

out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "bazaar",')
out.append('\t"regions": [\n%s\n\t],' % block(regions))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": false },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.52, 0.40, 0.30],')
out.append('\t"art": %s,' % json.dumps(ART, separators=(", ", ": ")))
out.append('\t"atmosphere": { "day_tint": [0.96, 0.80, 0.64], "vignette": { "strength": 0.5, "color": [0.12, 0.05, 0.02] }, '
           '"wind": { "strength": 0.8, "speed": 0.7 }, "ground_noise": { "contrast": 0.10, "tint": [0.42, 0.30, 0.20] }, '
           '"pollen": { "amount": 22, "color": [1.0, 0.82, 0.5] }, "glow": { "pulse_speed": 1.2 }, "region_tint_alpha": 0.10 },')
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"paths": [\n%s\n\t],' % block(paths))
out.append('\t"walls": [\n%s\n\t],' % block(walls))
out.append('\t"roofs": [\n%s\n\t],' % block(roofs))
out.append('\t"garlands": [\n%s\n\t],' % block(garlands))
out.append('\t"props": [\n%s\n\t],' % block(all_props))
out.append('\t"npc_companion": { "position": %s, "look": { "ear_rest": 7.0, "bounce_base": 2.4, "wag_life": 3.5, "eye_lift": 2.5, "coat_warm": 0.35, "body_scale": 1.12 } },' % json.dumps(NPC_COMPANION))
out.append('\t"_secret_comment": %s,' % json.dumps("This world's one SECRET (docs/home-world-and-secrets-design.md, W-5): no puzzle, a small shiny treasure found only by wandering, at the end of the forgotten alley off the west lane. The server honours a claim only here, within 'radius' of 'position'."))
out.append('\t"secret": %s,' % json.dumps(SECRET, indent="\t", ensure_ascii=False).replace("\n", "\n\t"))
out.append('\t"_walkers_comment": %s,' % json.dumps("Walking traffic: server-simulated like any ambient pal (shared, so everyone sees the same crowd; the walls keep them in the lane), drawn by the client as people from each 'person' appearance."))
out.append('\t"ambient_pals": [\n%s\n\t],' % block(walkers))
out.append('\t"portals": [')
out.append('\t\t{ "id": "bazaar_entry", "type": "portal", "position": %s, "color": [0.96, 0.82, 0.50], "label": "the way back to the Vale", "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_bazaar_portal" },' % json.dumps(list(ENTRY)))
out.append('\t\t{ "id": "bazaar_arch", "type": "portal", "position": %s, "color": [0.98, 0.76, 0.42], "label": "the great arch", "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_bazaar_portal" }' % json.dumps([ARCH[0], ARCH[1] + 26]))
out.append('\t]')
out.append("}")
text = "\n".join(out) + "\n"

d = json.loads(text)
assert any(i["type"] == "shopkeeper" for i in d["props"]), "no shopkeeper"
for i in d["props"]:
    want = bool(i.get("lore")) or i["type"] == "shopkeeper"
    assert bool(i.get("interactive", False)) == want, "interactive flag mismatch on %s" % i["id"]
for path in ["server/priv/world_seeds/bazaar.json", "pokepals/tests/world_fixtures/bazaar.json"]:
    open(path, "w").write(text)
print("wrote both files")
