#!/usr/bin/env python3
"""The HOUSE in a player's home (home building; docs/usable-items-design.md "Home building").

Writes the `house` block of the home template (server/priv/home/home.json), and marks the home as a place
where no axe works (`base.chopping: false`). Server.HomeWorld places the house once the carpenter has been
paid: it widens the glade to the north by `extend_north` and stands the house `from_north` below the new north
edge, centred, translating everything here (all LOCAL: x, y from the footprint's top-left corner) into world
coordinates. The client draws it (HouseView, HouseFurniture; WorldArt draws the floors and display shelves as
plates) and walls it in (the building's `solid_rects`).

A cosy cottage, three rooms side by side so every wall between them runs north-south (so a cutaway view reads
cleanly: you see the back wall of every room, and the rest are low walls):

    +---------------- north (back) wall: windows, shelves, the fireplace's chimney breast ----------------+
    | KITCHEN            | LIVING ROOM                      | BEDROOM                                    |
    | counter, sink,     | fireplace, bookshelf, armchairs, | bed, nightstands, wardrobe, a chest        |
    | stove, table and   | a rug, a couch facing the fire   | at the bed's foot                          |
    | chairs             |                                  |                                            |
    +--------------------+------------ front door ----------+--------------------------------------------+

Your finds move in with you once it's built: the companion's chosen keepsakes stand on the seven
`display_spots` (plinths by the fire, a side table, the chest...), and every other find you've made sits on the
`curio_spots` (low shelves along the walls). Re-run after editing: python3 tools/gen_home_house.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, "server/priv/home/home.json")

W, D, T = 560, 220, 8          # footprint width, depth, wall thickness
WALL_H = 64                    # how tall the walls stand (px, in the oblique view)
DOOR = (256, 304)              # the front door's gap in the south wall
ROOMS = [
    {"id": "kitchen", "x0": 8, "x1": 186},
    {"id": "living", "x0": 194, "x1": 366},
    {"id": "bedroom", "x0": 374, "x1": 552},
]
GAP = (130, 178)               # the doorway in each partition (y range)

# The carpenter's look: the same one she wears in the bazaar (tools/gen_bazaar.py, CARPENTER_LOOK).
CARPENTER_LOOK = {"equipped": {"body": "base:body", "legwear": "base:pants", "outfit": "base:tee",
                               "footwear": "base:shoes", "hair": "base:hair_long", "headwear": "base:headband"},
                  "colors": {"skin_tone": "umber", "hair_color": "chestnut", "top_color": "clay",
                             "legwear_color": "stone", "footwear_color": "clay", "headwear_color": "gold"}}

WOOD = [0.60, 0.42, 0.26]
WOOD_LIGHT = [0.72, 0.54, 0.34]


def rect(x, y, w, h):
    return [x, y, w, h]


# ── walls (solid) ────────────────────────────────────────────────────────────────────────────────────────
walls = [
    rect(0, 0, W, T),                                  # north (its face is drawn by the back wall)
    rect(0, 0, T, D), rect(W - T, 0, T, D),            # west, east
    rect(0, D - T, DOOR[0], T), rect(DOOR[1], D - T, W - DOOR[1], T),   # south, either side of the door
]
for x in (186, 366):                                   # the two partitions, each with a doorway
    walls.append(rect(x, T, T, GAP[0] - T))
    walls.append(rect(x, GAP[1], T, D - T - GAP[1]))

# ── floors (always: the boards go down first) and the low walls as seen from inside ─────────────────────────
floors = [
    {"rect": rect(8, 8, 178, 204), "kind": "tiles", "color": [0.86, 0.80, 0.68]},
    {"rect": rect(194, 8, 172, 204), "kind": "planks", "color": [0.66, 0.48, 0.30]},
    {"rect": rect(374, 8, 178, 204), "kind": "planks", "color": [0.72, 0.56, 0.38]},
    {"rect": rect(186, GAP[0], T, GAP[1] - GAP[0]), "kind": "planks", "color": [0.66, 0.48, 0.30]},
    {"rect": rect(366, GAP[0], T, GAP[1] - GAP[0]), "kind": "planks", "color": [0.66, 0.48, 0.30]},
    {"rect": rect(DOOR[0], D - T, DOOR[1] - DOOR[0], T), "kind": "planks", "color": [0.58, 0.42, 0.26]},
]
for w in walls[1:]:
    if w[1] == D - T and w[3] == T:
        continue  # the south wall is drawn by the house itself (a low strip in front of you)
    floors.append({"rect": w, "kind": "wall", "color": [0.90, 0.84, 0.72]})

# ── display: plinths for the keepsakes, low shelves for every other find ──────────────────────────────────────
display_plinths = [
    rect(212, 10, 26, 16),    # living room, left of the fire (the favourite)
    rect(312, 10, 22, 16),    # living room, right of the fire
    rect(164, 10, 20, 16),    # kitchen, by the stove
    rect(378, 10, 22, 16),    # bedroom, by the door
    rect(218, 166, 18, 14),   # a side table by the couch
    rect(324, 166, 18, 14),   # and its pair
]
CHEST = rect(440, 100, 40, 16)   # the chest at the bed's foot


def top_spot(r):
    """Where a prop stands so its feet land in the middle of a plinth's top face (props draw feet at +8)."""
    x, y, w, h = r
    feet = y + (h - 5) / 2.0 + 1.0
    return [x + w / 2.0, round(feet - 8.0, 1)]


display_spots = [top_spot(r) for r in display_plinths] + [top_spot(CHEST)]

shelves = [
    {"rect": rect(8, 62, 18, 140), "spots": [[17, f] for f in (72, 94, 116, 138, 160, 182)]},     # kitchen, west wall
    {"rect": rect(534, 40, 18, 150), "spots": [[543, f] for f in (52, 76, 100, 124, 148, 172)]},  # bedroom, east wall
    {"rect": rect(200, 196, 48, 12), "spots": [[212, 201], [236, 201]]},                           # living room, front
    {"rect": rect(312, 196, 48, 12), "spots": [[324, 201], [348, 201]]},
]
# Spread the finds round the house: one from each shelf in turn (so the first few land in different rooms),
# and along each shelf every other spot first (so a few finds don't crowd together).
def spread(spots):
    return spots[0::2] + spots[1::2]


queues = [spread(sh["spots"]) for sh in shelves]
curio_spots = []
while any(queues):
    for q in queues:
        if q:
            fx, fy = q.pop(0)
            curio_spots.append([fx, fy - 8.0])

built_plates = [
    {"rect": rect(226, 82, 108, 60), "kind": "rug", "color": [0.66, 0.24, 0.20]},
    {"rect": rect(432, 112, 76, 54), "kind": "rug", "color": [0.30, 0.42, 0.62]},
    {"rect": rect(44, 100, 96, 56), "kind": "rug", "color": [0.52, 0.60, 0.40]},
]
for r in display_plinths:
    built_plates.append({"rect": r, "kind": "plinth", "color": WOOD_LIGHT})
built_plates.append({"rect": CHEST, "kind": "chest", "color": [0.56, 0.36, 0.22]})
for sh in shelves:
    built_plates.append({"rect": sh["rect"], "kind": "shelf", "color": WOOD})

# ── furniture: y-sorted pieces, feet at `at`; `solid` walls them in (once built) ───────────────────────────────
def piece(kind, at, w, solid=None, **extra):
    p = {"kind": kind, "at": at, "w": w}
    if solid:
        p["solid"] = solid
    p.update(extra)
    return p


furniture = [
    # kitchen
    piece("counter", [68, 30], 108, rect(14, 8, 108, 22)),
    piece("stove", [143, 32], 34, rect(126, 8, 34, 24)),
    piece("chair_s", [92, 114], 14),
    piece("table", [92, 140], 56, rect(64, 120, 56, 18)),
    piece("chair_e", [56, 138], 14),
    piece("chair_w", [128, 138], 14),
    piece("chair_n", [92, 154], 14),
    piece("plant", [176, 204], 14),
    # living room
    piece("lamp", [202, 46], 12),
    piece("fireplace", [280, 28], 52, rect(254, 8, 52, 20)),
    piece("bookshelf", [351, 22], 26, rect(338, 8, 26, 14)),
    piece("armchair_e", [214, 122], 24, rect(203, 108, 22, 14)),
    piece("armchair_w", [346, 122], 24, rect(335, 108, 22, 14)),
    piece("coffee_table", [280, 120], 34),
    piece("couch", [280, 186], 76, rect(242, 170, 76, 16)),
    piece("plant", [358, 196], 14),
    # bedroom
    piece("nightstand", [413, 26], 18, rect(404, 10, 18, 16)),
    piece("bed", [456, 86], 64, rect(424, 8, 64, 76)),
    piece("nightstand", [499, 26], 18, rect(490, 10, 18, 16)),
    piece("wardrobe", [530, 24], 36, rect(512, 8, 36, 16)),
    piece("plant", [386, 200], 14),
]
# the chest and the shelves block too (they're plates, drawn on the floor, but you don't walk through them)
furniture_solids = [p["solid"] for p in furniture if "solid" in p] + [CHEST] + [sh["rect"] for sh in shelves] \
    + [r for r in display_plinths]

# What hangs on the back (north) wall of each room, seen from inside: x ranges, local.
decor = [
    {"kind": "window", "x0": 28, "x1": 62},
    {"kind": "jar_shelf", "x0": 70, "x1": 120},
    {"kind": "pots", "x0": 128, "x1": 158},
    {"kind": "painting", "x0": 214, "x1": 238},
    {"kind": "small_painting", "x0": 314, "x1": 332},
    {"kind": "picture", "x0": 380, "x1": 400},
    {"kind": "window", "x0": 436, "x1": 476},
    {"kind": "clock", "x0": 504, "x1": 512},
]
# The front of the house, seen from outside: windows on the south face (x ranges, local).
front_windows = [[52, 96], [118, 160], [204, 240], [320, 356], [400, 440], [480, 524]]

house = {
    "_comment": "The HOUSE (home building; tools/gen_home_house.py writes this, re-run it after editing). Placed by "
                "Server.HomeWorld once the carpenter in the bazaar has been paid (Server.House): the glade widens to "
                "the north by 'extend_north' and the house stands centred, 'from_north' below the new north edge. "
                "Everything below is LOCAL (from the footprint's top-left). While it's being built you see a timber "
                "frame on its floor, and the carpenter at work; once built, the furniture, rugs and display shelves "
                "go in and your finds move inside: keepsakes on 'display_spots', every other find on 'curio_spots'.",
    "extend_north": 440,
    "from_north": 150,
    "size": [W, D],
    "wall_h": WALL_H,
    "wall_t": T,
    "door": list(DOOR),
    "rooms": ROOMS,
    "walls": walls,
    "floors": floors,
    "built_plates": built_plates,
    "furniture": furniture,
    "furniture_solids": furniture_solids,
    "display_spots": display_spots,
    "curio_spots": curio_spots,
    "decor": decor,
    "front_windows": front_windows,
    "chimney_x": 280,
    "colors": {"plaster": [0.93, 0.88, 0.78], "timber": [0.42, 0.28, 0.18], "roof": [0.58, 0.30, 0.22],
               "stone": [0.62, 0.60, 0.56], "door": [0.44, 0.58, 0.40], "inside": [0.96, 0.90, 0.80]},
    "carpenter": {"appearance": CARPENTER_LOOK,
                  # where she works, in order: round the outside by the front (so she never walks through a wall)
                  # and in through the door
                  "work_spots": [[120, 246], [280, 238], [280, 120], [280, 238], [440, 246], [586, 246], [586, 110],
                                 [586, 246], [280, 250], [-26, 246], [-26, 110], [-26, 246]]},
}

with open(TEMPLATE) as f:
    tpl = json.load(f)
tpl["base"]["chopping"] = False
tpl["house"] = house
with open(TEMPLATE, "w") as f:
    f.write(json.dumps(tpl, indent=1, ensure_ascii=False))
print("wrote the house into %s: %d display spots, %d curio spots, %d pieces of furniture"
      % (TEMPLATE, len(display_spots), len(curio_spots), len(furniture)))
