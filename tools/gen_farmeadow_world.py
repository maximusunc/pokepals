#!/usr/bin/env python3
"""Generate FARMEADOW, the first world seen from inside (the perspective view), as a world spec.

A rolling meadow and one long road. You arrive at its southern end, and the road runs north through fields,
past fences, haystacks, copses and windmills, all the way to the ruin of an old keep you can see from where you
start, standing small on the horizon. Walk it and it slowly grows. Nothing needs doing.

What makes it its own place is how it's SEEN: its spec's `view` block asks for the perspective ("inside") view
(PerspectiveView over ViewProjection / ViewRig; tuned in pokepals/data/view.json): a camera just behind you that
swings round behind the way you walk, the land running off to a horizon ringed with distant hills and windmills
(the backdrop panoramas), clouds drifting over. Everything that stands up is drawn to be seen from any side: the
windmills from 8 bearings ("angles"), the fences and the fingerpost as cards, the round keep and the haystacks
the same all the way round. It is still the same world underneath: the same companion, the same examine, the
same portal home.

Its SECRET is a skylark painted across a little farmyard (a barn wall, a scarecrow, bales, a dry-stone wall), which
only joins up into one picture from one spot, looking south (back the way you came): see SECRET below. Fishing works (the mill pond); chopping is off (the windmills, the keep and
the fences are tree kinds, and none of them is wood).

Hand-authored: the road, the fields, the windmills, the keep, every lore line, the art override. Procedural
(seeded, so re-running reproduces it): the copses, the hedgerow trees and the haystacks, kept clear of the road.

Art assets come from pokepals/tools/gen_horizon.py. Writes the server seed and the client test fixture. Run from
the repo root:  python3 tools/gen_farmeadow_world.py
"""
import json
import math
import random

random.seed(0xFA77)

BOUNDS_MIN = (-1800, -2100)
BOUNDS_MAX = (1800, 1500)
PLAYER_SPAWN = [0, 1240]
COMPANION_SPAWN = [-34, 1270]
PORTALS = [
    {"id": "farmeadow_way_home", "type": "portal", "position": [-80, 1250], "color": [0.74, 0.86, 0.62], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

# ── regions: (id, min, max, tint): a clean partition of the bounds ───────────────────────────────────
REGIONS = [
    ("road_end",       (-600, 800),   (600, 1500),   (0.96, 0.92, 0.78)),
    ("west_fields",    (-1800, 100),  (-600, 1500),  (0.86, 0.94, 0.72)),
    ("east_fields",    (600, 100),    (1800, 1500),  (0.90, 0.94, 0.70)),
    ("the_long_road",  (-600, -900),  (600, 800),    (0.92, 0.94, 0.80)),
    ("millpond",       (-1800, -900), (-600, 100),   (0.80, 0.92, 0.86)),
    ("windmill_rise",  (600, -900),   (1800, 100),   (0.92, 0.96, 0.74)),
    ("old_lands",      (-1800, -2100), (1800, -900), (0.88, 0.88, 0.84)),
]

# ── the long road, south to north (it gently wanders) ───────────────────────────────────────────────
ROAD = [(0, 1420), (0, 1120), (60, 820), (-40, 470), (-120, 120), (20, -240), (160, -600), (100, -960),
        (-40, -1300), (20, -1600), (40, -1770)]
LANES = [
    [(-120, 120), (-420, 40), (-700, -60)],                      # west, to the mill pond
    [(160, -600), (480, -520), (860, -420), (1020, -380)],       # east, up Windmill Rise
]
ROAD_COLOR = [0.62, 0.55, 0.40]
KEEP = (40, -1880)

PONDS = [
    {"center": [-880, -160], "radius": 150, "color": [0.42, 0.62, 0.70]},
    {"center": [-760, -60], "radius": 90, "color": [0.42, 0.62, 0.70]},
    {"center": [780, 1010], "radius": 80, "color": [0.42, 0.62, 0.70]},
]

WINDMILLS = [  # (x, y, the bearing its front faces)
    (1040, -330, 225), (1320, -760, 250), (-1180, 760, 90), (760, -1500, 200),
]


def _seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
    return math.hypot(p[0] - (ax + dx * t), p[1] - (ay + dy * t))


def _near_road(p, d):
    for line in [ROAD] + LANES:
        for a, b in zip(line[:-1], line[1:]):
            if _seg_dist(p, a, b) < d:
                return True
    return False


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


STONE = (0.72, 0.70, 0.66)
TREES = []      # [x, y, kind] or [x, y, kind, facing_deg]
FENCES = []     # the walls along each run of fence panels (segments; nothing drawn: the panels are the look)
LANDMARKS = [{"type": "keep", "position": list(KEEP)}]

# The things that stand up are tree kinds (drawn by TreeView, seen from any side); the ones you can examine
# also get an "unseen" prop at the same spot carrying the words (the art block lists the type as unseen).
SPECIAL = [
    prop("keep_stones", "hz_examine", KEEP, STONE, "the old keep",
         "A round keep, its top long gone. The stones are warm on the sunny side and cool on the other. You can see "
         "the whole road from here, and the place you started is too small to make out.", solid=True, radius=34),
    prop("fingerpost", "hz_examine", (70, 1080), STONE, "a fingerpost",
         "One arm points up the road: KEEP. The other points back the way you came, and the word on it has worn "
         "away. Somebody kept painting the first one."),
    prop("mill_east", "hz_examine", WINDMILLS[0][:2], STONE, "a windmill",
         "Its sails turn when nobody is looking. Flour dust lies on the step, and a cat-sized door is propped "
         "open with a stone."),
    prop("mill_west", "hz_examine", WINDMILLS[2][:2], STONE, "a windmill",
         "The oldest of the mills. Somebody has carved the date into the door frame, then scratched it out, as "
         "if it was nobody's business how old it was."),
    prop("millpond_stone", "rock", (-640, -230), STONE, "a flat stone by the pond",
         "A flat stone at the water's edge, worn smooth by people sitting just here. The pond holds the whole "
         "sky, and a fish now and then.", solid=True, radius=9),
    prop("road_milestone", "rock", (-60, 300), STONE, "a milestone",
         "A milestone. The number on it is half a mile less than the last one, but you don't remember passing "
         "the last one.", solid=True, radius=7),
    prop("rise_milestone", "rock", (230, -880), STONE, "another milestone",
         "Another milestone, nearer the keep. Someone has balanced a tiny stone on top, and a smaller one on "
         "that.", solid=True, radius=7),
]

placed = [(p["position"][0], p["position"][1], 28) for p in SPECIAL]
placed.append((KEEP[0], KEEP[1], 90))
for x, y, f in WINDMILLS:
    TREES.append([x, y, "windmill", f])
    placed.append((x, y, 60))
TREES.append([70, 1080, "signpost", 180])

# ── THE SECRET: the skylark picture ──────────────────────────────────────────────────────────────────
# A little farmyard stands in the field south of SPOT: an old barn wall, a scarecrow, straw bales and a stretch of
# dry-stone wall, each at its own distance. A skylark and a ring for the sun are painted across their fronts, and
# from SPOT, looking SOUTH (back the way you came up the road), the paint joins up into one picture. Where each
# stands comes from the art (data/hz_skylark.json, written by pokepals/tools/gen_horizon.py for data/view.json's
# camera); here they're stood in the world, each with an invisible wall along it (the spec's "fences").
SKYLARK = json.load(open("pokepals/data/hz_skylark.json"))
SPOT = (430, -1020)
FACING = 180.0
_cam = SKYLARK["camera"]
_f = _cam["back"] * math.cos(math.radians(_cam["pitch_deg"])) + _cam["height"] * math.sin(math.radians(_cam["pitch_deg"]))
_F = (0.0, 1.0)          # looking south
_R = (-1.0, 0.0)         # ...so screen right is west
EYE = (SPOT[0] - _F[0] * _cam["back"], SPOT[1] - _F[1] * _cam["back"])
BOARDS = []
FARMYARD_WALLS = []
for b in SKYLARK["objects"]:
    z = b["depth"]
    lat = b["x"] * z / _f
    pos = (EYE[0] + _F[0] * z + _R[0] * lat, EYE[1] + _F[1] * z + _R[1] * lat)
    BOARDS.append((b, pos))
    TREES.append([round(pos[0], 2), round(pos[1], 2), b["id"], 0])
    hw = b["w"] * 0.5 - 2
    FARMYARD_WALLS.append({"from": [round(pos[0] - hw, 1), round(pos[1], 1)], "to": [round(pos[0] + hw, 1), round(pos[1], 1)], "thickness": 8})
    placed.append((pos[0], pos[1], b["w"] * 0.5 + 10))
placed.append((SPOT[0], SPOT[1], 40))


def _in_view_of_picture(x, y, r):
    """Inside the wedge of ground between the spot's camera and the farmyard: kept clear so nothing hides it."""
    a = (x - EYE[0]) * _F[0] + (y - EYE[1]) * _F[1]
    if a <= 0 or a > 620:
        return False
    sx = ((x - EYE[0]) * _R[0] + (y - EYE[1]) * _R[1]) * _f / a   # where it'd be on screen, from the spot
    m = (r + 20) * _f / a
    return -25 - m < sx < 175 + m


def clear(x, y, r, road=70):
    if not (BOUNDS_MIN[0] + 150 <= x <= BOUNDS_MAX[0] - 150 and BOUNDS_MIN[1] + 150 <= y <= BOUNDS_MAX[1] - 150):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 220:
        return False
    if any(math.hypot(x - pd["center"][0], y - pd["center"][1]) < pd["radius"] * 1.2 + r for pd in PONDS):
        return False
    if _near_road((x, y), road + r):
        return False
    if _in_view_of_picture(x, y, r):
        return False
    return all(math.hypot(x - px, y - py) >= r + pr for px, py, pr in placed)


def fence(a, b, gap_every=0, gaps=()):
    """A run of fence panels from a to b, each a card facing across the run (toward its south/west side)."""
    d = math.hypot(b[0] - a[0], b[1] - a[1])
    n = max(1, int(d // 32))
    ux, uy = (b[0] - a[0]) / d, (b[1] - a[1]) / d
    # the face looks along the run's normal: the bearing of (uy, -ux) or its opposite, whichever is southward
    nx, ny = uy, -ux
    if ny < 0:
        nx, ny = -nx, -ny
    facing = math.degrees(math.atan2(nx, -ny)) % 360
    run = None
    for i in range(n + 1):
        if i == n or i in gaps:
            if run is not None:  # the run of panels just ended: one invisible wall along it (the spec's "fences")
                FENCES.append({"from": [round(a[0] + ux * run * d / n), round(a[1] + uy * run * d / n)],
                               "to": [round(a[0] + ux * i * d / n), round(a[1] + uy * i * d / n)], "thickness": 8})
                run = None
            continue
        if run is None:
            run = i
        x = a[0] + ux * (i + 0.5) * d / n
        y = a[1] + uy * (i + 0.5) * d / n
        TREES.append([round(x), round(y), "fence", round(facing)])
        placed.append((x, y, 14))


# fences along the road's first stretch, with field gates left open
fence((-70, 1060), (-70, 520), gaps=(6,))
fence((90, 1000), (120, 560), gaps=(4, 9))
# a paddock east of the road, haystacks inside
PADDOCK = ((260, 260), (720, 700))
fence((PADDOCK[0][0], PADDOCK[0][1]), (PADDOCK[1][0], PADDOCK[0][1]), gaps=(2,))
fence((PADDOCK[0][0], PADDOCK[1][1]), (PADDOCK[1][0], PADDOCK[1][1]))
fence((PADDOCK[0][0], PADDOCK[0][1]), (PADDOCK[0][0], PADDOCK[1][1]), gaps=(7,))
fence((PADDOCK[1][0], PADDOCK[0][1]), (PADDOCK[1][0], PADDOCK[1][1]))
for _ in range(400):
    x = random.uniform(PADDOCK[0][0] + 50, PADDOCK[1][0] - 50)
    y = random.uniform(PADDOCK[0][1] + 50, PADDOCK[1][1] - 50)
    if all(math.hypot(x - px, y - py) >= 70 for px, py, _ in placed):
        TREES.append([round(x), round(y), "haystack"])
        placed.append((x, y, 30))
    if sum(1 for t in TREES if t[2] == "haystack") >= 7:
        break
# a field of haystacks west of the road too
for _ in range(600):
    x = random.uniform(-1500, -700)
    y = random.uniform(300, 1200)
    if clear(x, y, 30):
        TREES.append([round(x), round(y), "haystack"])
        placed.append((x, y, 30))
    if sum(1 for t in TREES if t[2] == "haystack") >= 15:
        break


def copse(cx, cy, n, spread):
    got = 0
    for _ in range(n * 30):
        if got >= n:
            break
        x = random.gauss(cx, spread)
        y = random.gauss(cy, spread * 0.8)
        if clear(x, y, 22):
            TREES.append([round(x), round(y), "tree"])
            placed.append((x, y, 22))
            got += 1


def hedgerow(a, b, every=46, wobble=12):
    d = math.hypot(b[0] - a[0], b[1] - a[1])
    for i in range(int(d // every)):
        t = (i + random.uniform(0.2, 0.8)) / max(1, int(d // every))
        x = a[0] + (b[0] - a[0]) * t + random.uniform(-wobble, wobble)
        y = a[1] + (b[1] - a[1]) * t + random.uniform(-wobble, wobble)
        if clear(x, y, 16):
            TREES.append([round(x), round(y), "tree"])
            placed.append((x, y, 16))


# copses, near and far, so the road always has something passing by
for cx, cy, n, s in [(-420, 900, 7, 70), (420, 1180, 5, 60), (-380, 360, 9, 80), (380, -60, 8, 70),
                     (-520, -420, 10, 90), (720, -1260, 9, 80), (-560, -1200, 11, 100), (-1300, -1500, 14, 140),
                     (1300, -1650, 12, 120), (1350, 300, 10, 110), (-1450, 200, 9, 100), (1200, 1150, 8, 90),
                     (-1100, -700, 7, 80), (200, -1450, 6, 60), (-300, -1650, 6, 60)]:
    copse(cx, cy, n, s)
# hedgerows dividing the fields
for a, b in [((-1650, 80), (-650, 80)), ((650, 60), (1650, 60)), ((-1650, -900), (-700, -900)),
             ((700, -920), (1650, -920)), ((-1200, 1300), (-1200, 400)), ((1150, 1300), (1150, 500))]:
    hedgerow(a, b)

ALL_PROPS = SPECIAL + [
    prop("barn_wall", "hz_examine", BOARDS[0][1], STONE, "an old barn wall",
         "All that's left of a barn: one wall, still standing. Someone has painted on it, big dark brushstrokes that "
         "don't make anything. There's paint on the bales too, and on the stones. Odd."),
]

SECRET_COMMENT = ("This world's one SECRET. reveal.type 'align': the paint on the farmyard (tree kinds hz_barnwall, "
                  "hz_scarecrow, hz_bales, hz_drywall) only joins up into the skylark picture from 'spot' looking 'facing_deg' (south) with this world's perspective "
                  "camera. Standing still there facing near enough south captures the view (PerspectiveView.set_magnet), "
                  "it settles exactly, and held for 'hold_seconds' the painted lark lifts off and flutters "
                  "down at your feet as the prop (AlignGate / AlignDirector). The server only checks 'this world, "
                  "standing at it'.")
LARK_AT = (SPOT[0] - 30, SPOT[1] + 18)   # beside you (to your right, looking south), not hidden behind you
SECRET = {
    "id": "wooden_lark",
    "position": list(LARK_AT),
    "radius": 280.0,   # the lark lands beside you wherever you stood on the strip, so the claim reaches all of it
    "prop": {"type": "wooden_lark", "color": [0.62, 0.46, 0.32], "label": "a carved wooden lark", "tags": ["small", "made", "old", "odd"]},
    "lore": "A skylark carved from pale wood, wings up, worn smooth by hands. It's still warm, as if it had been flying.",
    "reveal": {
        "type": "align",
        "spot": list(SPOT),
        "facing_deg": FACING,
        "hold_seconds": 2.0,
        # Where you can stand: a strip along the line of sight, 60 back from the spot (124 with the radius) to 64 on
        # toward the picture, 64 either side. Anywhere on it the camera's eye goes to the one point the picture lines
        # up from (eye_back behind the spot) with the usual lens, so the picture is exactly as from the spot; only you
        # look bigger, the camera having come up nearer behind you.
        "capture_back": 60.0, "capture_ahead": 0.0, "eye_back": _cam["back"], "min_back": 90.0,
        "capture_radius": 64.0, "capture_deg": 35.0, "still_speed": 14.0, "center_tol": 1.5, "yaw_tol_deg": 1.0,
        "notice_range_low": 320.0, "notice_range_high": 720.0, "notice_cooldown_low": 16.0, "notice_cooldown_high": 6.0,
        "notice_hold": 2.0, "visit_range": 260.0, "visit_reset": 520.0,
        "lark_screen_x": SKYLARK["lark"]["screen"][0], "lark_screen_y": SKYLARK["lark"]["screen"][1],
        "lark_depth": SKYLARK["lark"]["depth"], "lark_span": SKYLARK["lark"]["span"],
        "bare": {b["id"]: b["bare"] for b in SKYLARK["objects"]},
        "lines": {
            "notice": "Your companion stops and looks back the way you came, as if something over there was looking at it.",
            "visit": "Your companion trots off and sits very still in one particular spot, looking south.",
            "settle": "From here, the paint on the barn wall and the bales starts to line up.",
        },
        "reveal_line": "The smudges of paint join up into one picture: a skylark crossing the sun. Then the lark isn't paint any more.",
    },
    "found_line": "Somebody painted a lark that could only be seen from one place, facing home. You found the place.",
    "home_line": "Something has changed at home.",
    "qualities": ["old", "made", "airy"],
    "keepsake": {
        "id": "lark_on_a_post", "type": "kept_wooden_lark", "color": [0.62, 0.46, 0.32], "label": "a wooden lark on a little post",
        "line": "The carved lark, on a post of its own. Your companion looks at it from one side, then the other, as if waiting for it to line up.",
        "temperament": {"curiosity": 0.75, "energy": 0.55, "clinginess": 0.4},
    },
}

AMBIENT_PALS = []
for i, (species, home, r) in enumerate([("rabbit", (-300, 700), 120), ("rabbit", (420, 900), 140), ("bird", (-200, 200), 160),
                                        ("rabbit", (-900, 500), 160), ("fox", (900, -200), 180), ("bird", (300, -700), 160),
                                        ("rabbit", (-400, -800), 140), ("bird", (-100, -1500), 160), ("cat", (-760, 120), 90)]):
    AMBIENT_PALS.append({"id": "pal_fm_%d" % i, "home": list(home), "roam_radius": r, "region": "fm", "species": species,
                         "variant": i % 3, "look": {"ear_rest": 2.0, "bounce_base": 2.6, "wag_life": 2.2, "body_scale": 0.86}})

# ── the world's own ART OVERRIDE (deep-merged over data/art.json): just the new upright kinds ─────────
S = "res://assets/sprites/"
ART = {
    "entities": {
        "windmill": {"render": "sprite", "sprite": S + "hz_windmill_0.png", "sway": 0.0,
                     "angles": [S + "hz_windmill_%d.png" % k for k in range(8)]},
        "keep": {"render": "sprite", "sprite": S + "hz_keep.png", "sway": 0.0},
        "fence": {"render": "sprite", "sprite": S + "hz_fence.png", "sway": 0.0, "card": True},
        "signpost": {"render": "sprite", "sprite": S + "hz_signpost.png", "sway": 0.0, "card": True},
        "haystack": {"render": "sprite", "sprite": S + "hz_haystack.png", "sway": 0.0},
        **{b["id"]: {"render": "sprite", "sprite": b["sprite"], "back": b["back"], "sway": 0.0, "card": True}
           for b in json.load(open("pokepals/data/hz_skylark.json"))["objects"]},
        # wooden_lark: the secret's prop stands up as the landed LarkFlight here; drawn flat it'd be a smear
        "props": {"unseen": ["hz_examine", "wooden_lark"]},
    },
}

# ── how it's seen: the perspective view, and what hangs round its horizon ─────────────────────────────
VIEW = {
    "projection": "perspective",
    "backdrop": {"hills": S + "hz_hills.png", "clouds": S + "hz_clouds.png", "cloud_drift": 0.0015},
}

ATMOSPHERE = {
    "day_tint": [1.03, 1.0, 0.94],
    "vignette": {"strength": 0.22, "color": [0.12, 0.10, 0.08]},
    "wind": {"strength": 2.0, "speed": 0.9},
    "pollen": {"amount": 28, "color": [1.0, 0.97, 0.8]},
    "region_tint_alpha": 0.04,
}

HEADER = ("FARMEADOW - a rolling meadow and one long road, the first world seen from INSIDE: its 'view' block asks for "
          "the perspective view (PerspectiveView; tuned in data/view.json), a camera just behind you that swings round "
          "behind the way you walk, the land running to a horizon ringed with hills (the backdrop panoramas). You arrive at "
          "the road's south end; it runs north past fences, haystacks, copses and windmills to the ruin of an old keep, "
          "small on the horizon from the start. Upright things are tree kinds drawn to be seen from any side: windmills "
          "from 8 bearings ('angles'), fences and the fingerpost as 'card's, the keep and the haystacks round. Tree entries "
          "are [x, y, kind] or [x, y, kind, facing bearing]. Its secret: see the 'secret' block (reveal type 'align'). Generated by tools/gen_farmeadow_world.py (art: "
          "pokepals/tools/gen_horizon.py) - edit that and re-run, don't hand-tune positions.")


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


paths = []
for ln in [ROAD] + LANES:
    for a, b in zip(ln[:-1], ln[1:]):
        paths.append({"from": list(a), "to": list(b), "color": ROAD_COLOR})

region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "farmeadow",')
out.append('\t"intro": %s,' % json.dumps("A meadow, and a long road. At the far end of it, very small, an old keep. There's no hurry."))
out.append('\t"view": %s,' % json.dumps(VIEW))
out.append('\t"chopping": false,')
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"music": { "track": "res://assets/music/farmeadow.ogg", "volume_db": -22 },')  # tools/music/scores/farmeadow.score
out.append('\t"border": { "ring": true, "spacing": 130, "inset": 24, "jitter": 34, "rows": 1 },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.46, 0.62, 0.34],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [\n%s\n\t],' % block(PONDS))
out.append('\t"paths": [\n%s\n\t],' % block(paths))
out.append('\t"landmarks": [\n%s\n\t],' % block(LANDMARKS))
out.append('\t"trees": [\n%s\n\t],' % block(TREES))
out.append('\t"_fences_comment": "Invisible walls along each run of fence panels, so the gaps between panels don\'t let you through (gates are left open). Segment solids like hedges, with nothing drawn: the fence you see is the panels.",')
out.append('\t"fences": [\n%s\n\t],' % block(FENCES + FARMYARD_WALLS))
out.append('\t"props": [\n%s\n\t],' % block(ALL_PROPS))
out.append('\t"ambient_pals": [\n%s\n\t],' % block(AMBIENT_PALS))
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
    assert BOUNDS_MIN[0] < t[0] < BOUNDS_MAX[0] and BOUNDS_MIN[1] < t[1] < BOUNDS_MAX[1], t
road_len = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(ROAD[:-1], ROAD[1:]))
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("fences:", len(d["fences"]), "| props:", len(d["props"]), "| trees:", kinds, "| road: %d px" % road_len)
for path in ["server/priv/world_seeds/farmeadow.json", "pokepals/tests/world_fixtures/farmeadow.json"]:
    open(path, "w").write(text)
print("wrote both files")
