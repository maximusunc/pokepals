#!/usr/bin/env python3
"""Generate LOFTREACH, the sky-island world, as a world spec.

Grassy islets float in open sky (3400 x 2600), joined by rope bridges, with windmills, kites and a sea of cloud
drifting below. Breezy, bright and high; no goal, no puzzle, only a secret for a companion with wings.

Its one SECRET (docs/home-world-and-secrets-design.md, "Loftreach"): a nest on an islet you cannot reach on
foot. Shift your companion into a bird and send it up (the radial's "Go up"); the camera rises with it, and from
high above the high clouds make a picture, a great arrow, and the islands all lean the same way: toward the nest.
Once the bird has looked at the nest and the head of the way there, a rope bridge appears (fades in) and can be
walked. Reveal type "skyview" (SkyView / SkyDirector). All the numbers live in this file's data, not in code.

Hand-authored: island centres and sizes, the bridges, the picture, every lore line, the art override.
Procedural (seeded): the island outlines (egg shapes leaning toward the nest), the scatter of trees and props.
The island polygons ARE the world: the walkable ground, the collision fence (SkyRealm.solids) and the drawn
turf. A hidden bridge has no gap in the fence until revealed.

Art comes from pokepals/tools/gen_loftreach.py. Writes the server seed and the client test fixture.
Run from the repo root:  python3 tools/gen_loftreach_world.py
"""
import json
import math
import random

random.seed(0x10F7)

BOUNDS_MIN = (-1700, -1300)
BOUNDS_MAX = (1700, 1300)
PLAYER_SPAWN = [-1290, 800]
COMPANION_SPAWN = [-1250, 830]
PORTALS = [
    {"id": "loftreach_way_home", "type": "portal", "position": [-1392, 770], "color": [0.80, 0.92, 1.0], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

NEST_ISLE = "rookery"
NEST_C = (1400, -700)

# id, name, centre, radius, tint
ISLANDS = [
    ("landing",   "Anchor Landing",    (-1300, 760),  230, (0.86, 0.96, 0.92)),
    ("millstone", "Millstone Lea",     (-560, 560),   320, (0.98, 0.96, 0.84)),
    ("kite",      "Kite Green",        (240, 780),    280, (0.90, 0.96, 1.00)),
    ("orchard",   "Cloud Orchard",     (-1250, 80),   280, (1.00, 0.90, 0.94)),
    ("vane",      "Vane Hill",         (-250, -260),  300, (0.92, 0.98, 0.92)),
    ("pennant",   "Pennant Crag",      (560, -380),   300, (1.00, 0.94, 0.86)),
    ("pasture",   "Lantern Pasture",   (980, 360),    270, (1.00, 0.97, 0.86)),
    ("perch",     "High Perch",        (-480, -960),  260, (0.90, 0.94, 1.00)),
    (NEST_ISLE,   "The Rookery",       NEST_C,        170, (1.00, 0.98, 0.90)),
]
BRIDGES = [
    ("landing", "millstone"), ("millstone", "kite"), ("landing", "orchard"), ("orchard", "millstone"),
    ("millstone", "vane"), ("vane", "pennant"), ("kite", "pasture"), ("pasture", "pennant"), ("vane", "perch"),
]
HIDDEN_BRIDGE = ("pennant", NEST_ISLE)
BRIDGE_W = 80.0
ICENTER = {i[0]: i[2] for i in ISLANDS}
IRADIUS = {i[0]: i[3] for i in ISLANDS}

# every island leans toward the nest: egg shapes whose blunt point faces the way the hidden bridge goes
_pc = ICENTER["pennant"]
LEAN = math.atan2(NEST_C[1] - _pc[1], NEST_C[0] - _pc[0])


def island_poly(cid, c, r, n=34):
    s = (c[0] * 0.013 + c[1] * 0.021) % math.tau
    pts = []
    for i in range(n):
        a = math.tau * i / n
        k = r * (1.0 + 0.20 * math.cos(a - LEAN)) * (1.0 + 0.06 * math.sin(3 * a + s) + 0.045 * math.sin(5 * a - s * 1.7))
        pts.append((c[0] + math.cos(a) * k, c[1] + math.sin(a) * k))
    return pts


POLYS = {i[0]: island_poly(i[0], i[2], i[3]) for i in ISLANDS}


def in_poly(p, poly):
    x, y = p
    inside = False
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        if (a[1] > y) != (b[1] > y) and x < a[0] + (y - a[1]) / (b[1] - a[1]) * (b[0] - a[0]):
            inside = not inside
    return inside


def seg_dist(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / max(1e-9, dx * dx + dy * dy)))
    return math.hypot(p[0] - (a[0] + dx * t), p[1] - (a[1] + dy * t))


def edge_dist(p, cid):
    poly = POLYS[cid]
    return min(seg_dist(p, poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))


def ray_exit(c, toward, cid):
    """Where the ray from centre `c` toward `toward` leaves island `cid`'s outline."""
    dx, dy = toward[0] - c[0], toward[1] - c[1]
    d = math.hypot(dx, dy)
    ux, uy = dx / d, dy / d
    lo, hi = 0.0, IRADIUS[cid] * 1.6
    for _ in range(40):
        mid = (lo + hi) / 2
        if in_poly((c[0] + ux * mid, c[1] + uy * mid), POLYS[cid]):
            lo = mid
        else:
            hi = mid
    return (round(c[0] + ux * lo, 1), round(c[1] + uy * lo, 1))


def bridge(a, b, hidden=False):
    ma = ray_exit(ICENTER[a], ICENTER[b], a)
    mb = ray_exit(ICENTER[b], ICENTER[a], b)
    out = {"id": "%s_%s" % (a, b), "from": a, "to": b, "a": list(ma), "b": list(mb), "width": BRIDGE_W}
    if hidden:
        out["hidden"] = True
    return out


BRIDGE_OBJS = [bridge(a, b) for a, b in BRIDGES]
HID = bridge(*HIDDEN_BRIDGE, hidden=True)
HID["id"] = "sky_bridge"
BRIDGE_OBJS.append(HID)

# ── validate the sky: the islands stand apart, and no bridge crosses a third island ───────────────────
ids = [i[0] for i in ISLANDS]
for i, a in enumerate(ids):
    for b in ids[i + 1:]:
        # closest approach of the two outlines
        best = min(math.hypot(p[0] - q[0], p[1] - q[1]) for p in POLYS[a] for q in POLYS[b])
        assert best > 110, "islands %s and %s are too close (%.0f)" % (a, b, best)
for br in BRIDGE_OBJS:
    a, b = br["a"], br["b"]
    ln = math.hypot(b[0] - a[0], b[1] - a[1])
    assert 120 < ln < 620, "bridge %s is %.0f long" % (br["id"], ln)
    ux, uy = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
    nx, ny = -uy, ux
    for k in range(1, 40):
        t = k / 40.0
        if t * ln < 60 or (1 - t) * ln < 60:
            continue   # the strip's corners may dip into an island at a slanted mouth
        for off in (-BRIDGE_W / 2, 0, BRIDGE_W / 2):
            p = (a[0] + (b[0] - a[0]) * t + nx * off, a[1] + (b[1] - a[1]) * t + ny * off)
            for cid in ids:
                assert not in_poly(p, POLYS[cid]), "bridge %s runs over island %s" % (br["id"], cid)
print("bridges:", [(b["id"], round(math.hypot(b["b"][0] - b["a"][0], b["b"][1] - b["a"][1]))) for b in BRIDGE_OBJS])

HEAD = tuple(HID["a"])    # the head of the hidden way, on Pennant Crag
FAR = tuple(HID["b"])     # where it lands on the Rookery
NEST = (round(NEST_C[0] + 8), round(NEST_C[1] + 6))   # the nest sits near the Rookery's middle

# ── the picture in the high clouds: a great arrow from over Vane Hill to the Rookery, its head over the nest ─
TAIL = (-120, -300)
TIP = (NEST_C[0] - 70, NEST_C[1] + 10)
ang = math.atan2(TIP[1] - TAIL[1], TIP[0] - TAIL[0])
PUFFS = []   # [x, y, variant, scale]


def puff(x, y, s):
    PUFFS.append([round(x), round(y), len(PUFFS) % 2, round(s, 2)])


L = math.hypot(TIP[0] - TAIL[0], TIP[1] - TAIL[1])
k = 0
while k * 78.0 < L - 70:
    t = k * 78.0
    puff(TAIL[0] + math.cos(ang) * t + random.uniform(-6, 6), TAIL[1] + math.sin(ang) * t + random.uniform(-6, 6), 1.0 + 0.25 * math.sin(k * 1.3))
    k += 1
for side in (-1, 1):
    ba = ang + math.pi + side * math.radians(30)
    for j in range(1, 5):
        puff(TIP[0] + math.cos(ba) * j * 66, TIP[1] + math.sin(ba) * j * 66, 0.95)
puff(TIP[0], TIP[1], 1.3)
# fletching: two short feathers at the tail
for side in (-1, 1):
    fa = ang + side * math.radians(35)
    for j in range(1, 3):
        puff(TAIL[0] - math.cos(ang) * 30 + math.cos(fa) * j * 60 * -1, TAIL[1] - math.sin(ang) * 30 + math.sin(fa) * j * 60 * -1, 0.8)
VANTAGE = (round((TAIL[0] + TIP[0]) / 2 + 150), round((TAIL[1] + TIP[1]) / 2 - 70))
print("picture: %d puffs, arrow %d px long, vantage %s, head %s, nest %s" % (len(PUFFS), L, VANTAGE, HEAD, NEST))


def prop(id, type, pos, label, lore=None, solid=None, radius=None, tags=None):
    p = {"id": id, "type": type, "position": [round(pos[0]), round(pos[1])], "color": [1.0, 1.0, 1.0], "label": label}
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


def at(cid, dx, dy):
    c = ICENTER[cid]
    return (c[0] + dx, c[1] + dy)


# ── hand-placed props ───────────────────────────────────────────────────────────────────────────────
WIND_POS = at("millstone", 40, -20)
SPECIAL = [
    prop("landing_sign", "lr_sign", at("landing", 40, 70), "a signpost",
         "Carved on a signpost, in a hurry: 'Mind the edge. The sky has no handrail. Everything up here leans one way, toward the same far thing. '"
         "Watch the vanes.'", solid=True, radius=6),
    prop("landing_bench", "lr_bench", at("landing", -30, -90), "a bench", "A bench facing nothing but sky. It is the best view on the island, and somebody has worn the paint off the middle.", solid=True, radius=10),
    prop("landing_planter", "lr_planter", at("landing", 90, -40), "a planter", "Windflowers, in a box, on a rock, in the sky. They are doing very well."),
    prop("landing_lamp", "lr_lamp", at("landing", 110, 40), "a lamp", "A lamp on a post. By dusk it is the only thing for a mile that is not either a cloud or a hill.", solid=True, radius=5),
    prop("landing_barrel", "lr_barrel", at("landing", -110, 70), "a barrel", "Empty, and it rings when you tap it, which carries a long way up here.", solid=True, radius=7),
    prop("mill", "lr_windmill", WIND_POS, "the windmill",
         "The sails turn without any hurry. The miller is not in; the grain is, in the form of sacks, and every one is labelled 'for the clouds'.", solid=True, radius=22),
    prop("mill_hay_a", "lr_haystack", at("millstone", -150, 60), "a haystack", "Warm, and it smells of a summer that is on some other island.", solid=True, radius=11),
    prop("mill_hay_b", "lr_haystack", at("millstone", -140, 130), "another haystack", "A haystack. A very good one to lie against and look up."),
    prop("mill_bench", "lr_bench", at("millstone", 130, 90), "a bench", "A bench set so that you face the sails. Watching them turn is what it is for.", solid=True, radius=10),
    prop("mill_sign", "lr_sign", at("millstone", -70, 130), "a signpost", "'Millstone Lea. Flour by wind. The wind is the only thing here that works for free, and it knows.'", solid=True, radius=6),
    prop("mill_barrel", "lr_barrel", at("millstone", 90, -80), "a barrel", "Full. Of what, nobody has ever asked.", solid=True, radius=7),
    prop("kite_stake_a", "lr_kite_stake", at("kite", -90, -30), "a kite stake", "A stake with a spool of line. The line goes up and does not come back down for a good long while."),
    prop("kite_stake_b", "lr_kite_stake", at("kite", 30, -110), "a kite stake", "The line from this one is tied in a knot that says someone meant it."),
    prop("kite_stake_c", "lr_kite_stake", at("kite", 100, 20), "a kite stake", "The line is taut, and sings."),
    prop("kite_stake_d", "lr_kite_stake", at("kite", -20, 90), "a kite stake", "A little kite on a short string, for beginners, who are also kites."),
    prop("kite_hammock", "lr_hammock", at("kite", -140, 110), "a hammock", "Slung between two posts, over the long drop. People sleep here. It is, they say, better than the ground."),
    prop("kite_pennant", "lr_pennant", at("kite", 140, -80), "a string of pennants", "Bunting, snapping in the wind like a lot of small, bright applause."),
    prop("kite_sign", "lr_sign", at("kite", 10, 30), "a signpost", "'Kite Green. All kites are welcome. Kites are tied to the ground, mostly for their own good.'", solid=True, radius=6),
    prop("orchard_bench", "lr_bench", at("orchard", -20, 80), "a bench", "A bench under blossom. Petals fall on it, and nobody sweeps them off, for good reason.", solid=True, radius=10),
    prop("orchard_planter", "lr_planter", at("orchard", 80, -20), "a planter", "Poppies, windflowers, buttercups. It is the sky's own idea of a bouquet."),
    prop("orchard_sign", "lr_sign", at("orchard", 20, 160), "a signpost", "'Cloud Orchard. Pick what you like. The apples taste of rain; that is the cloud in them.'", solid=True, radius=6),
    prop("vane_a", "lr_vane", at("vane", 0, 0), "a weathervane",
         "A weathervane. Wind from the south, the west, the south again; it does not matter. The arrow points, firmly, up and to the right.", solid=True, radius=5),
    prop("vane_b", "lr_vane", at("vane", -130, 100), "another weathervane", "This vane points up and to the right as well. Whatever it is pointing at, it has been pointing at it for a long time.", solid=True, radius=5),
    prop("vane_c", "lr_vane", at("vane", 120, 90), "a third weathervane", "A third vane, in complete agreement with the other two. Somebody has painted 'FAR' on its post, and underlined it.", solid=True, radius=5),
    prop("vane_stone", "lr_standing_stone", at("vane", 40, 180), "a standing stone",
         "A bird, scratched into the stone, wings up, looking out over the edge. Under it, smaller: 'what the clouds draw, only a bird can read'.", solid=True, radius=8),
    prop("pennant_stone", "lr_standing_stone", at("pennant", -60, 100), "a standing stone",
         "Another bird scratched into a stone, and this time a line, from its beak out across the sky. It stops at the edge of the stone, but not of the idea.", solid=True, radius=8),
    prop("pennant_flag_a", "lr_pennant", at("pennant", -120, -60), "a flag pole", "Bunting. It all streams one way, and it is the same way as the vanes."),
    prop("pennant_boulder_a", "lr_boulder", at("pennant", -140, 40), "a mossy boulder", "A boulder with moss on the side the wind does not reach."),
    prop("pasture_perch", "lr_perch", at("pasture", -60, -40), "a dovecote", "A dovecote on a post. The doves are out. They come and go over the edge, which no one can quite see the point of, and then they are back."),
    prop("pasture_hay", "lr_haystack", at("pasture", 80, 60), "a haystack", "A haystack the size of a small hill, with a small hill's confidence.", solid=True, radius=11),
    prop("pasture_bench", "lr_bench", at("pasture", -20, 110), "a bench", "A bench for lantern-watching.", solid=True, radius=10),
    prop("perch_dove_a", "lr_perch", at("perch", -80, 20), "a dovecote", "Empty. The doves say the view from here is no good, and they have somewhere better to be.", solid=True, radius=6),
    prop("perch_dove_b", "lr_perch", at("perch", 70, 50), "a dovecote", "A dovecote with feathers all round the door. They are not discarded. They have been arranged.", solid=True, radius=6),
    prop("perch_stone", "lr_standing_stone", at("perch", 0, -80), "a standing stone",
         "A bird again, and this one has something under its wings: a line of tiny clouds, all pointing the same way. 'Ask the one who flies. Shift it to a bird, and tell it to go up.'", solid=True, radius=8),
    prop("perch_vane", "lr_vane", at("perch", 110, -30), "a weathervane", "Up and to the right. Always.", solid=True, radius=5),
    prop("rookery_boulder", "lr_boulder", at("rookery", -60, 40), "a boulder", "A boulder, a good long way from anywhere you could have walked to.", solid=True, radius=8),
]
# lamps in the pasture
for i, (dx, dy) in enumerate([(-130, 10), (-10, 60), (110, -10), (0, -110), (120, 100)]):
    SPECIAL.append(prop("pasture_lamp_%d" % i, "lr_lamp", at("pasture", dx, dy), "a lamp", "A lamp on a post, lit even in daylight, for the thought.", solid=True, radius=5))

# the nest and everything else about the Rookery lives in the secret; the spot is the nest's
placed = [(p["position"][0], p["position"][1], 30) for p in SPECIAL]
placed.append((WIND_POS[0], WIND_POS[1], 50))
placed.append((NEST[0], NEST[1], 80))
LANDMARKS = [
    {"type": "great_apple", "position": list(at("orchard", -120, -80))},
    {"type": "great_oak", "position": list(at("millstone", -190, -150))},
]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 70))

MOUTHS = []
for b in BRIDGE_OBJS:
    MOUTHS.append(tuple(b["a"]))
    MOUTHS.append(tuple(b["b"]))
SPAWNS = [tuple(PLAYER_SPAWN), tuple(COMPANION_SPAWN), (PORTALS[0]["position"][0], PORTALS[0]["position"][1])]


def clear_ok(cid, x, y, r, edge_margin):
    if not in_poly((x, y), POLYS[cid]):
        return False
    if edge_dist((x, y), cid) < edge_margin + r:
        return False
    if any(math.hypot(x - m[0], y - m[1]) < 130 + r for m in MOUTHS):
        return False
    if any(math.hypot(x - s[0], y - s[1]) < 120 + r for s in SPAWNS):
        return False
    return all(math.hypot(x - px, y - py) >= r + pr for px, py, pr in placed)


def scatter(cid, n, r, tries=4000, edge_margin=34):
    c = ICENTER[cid]
    R = IRADIUS[cid] * 1.3
    out = []
    for _ in range(tries):
        if len(out) >= n:
            break
        x = c[0] + random.uniform(-R, R)
        y = c[1] + random.uniform(-R, R)
        if clear_ok(cid, x, y, r, edge_margin):
            placed.append((x, y, r))
            out.append((round(x), round(y)))
    return out


TREES = []
PROPS = []


def trees(cid, n, kind, r=26):
    for x, y in scatter(cid, n, r, edge_margin=44):
        TREES.append([x, y, kind])


def props(cid, n, type, label, r=16, solid=None, radius=None):
    for i, (x, y) in enumerate(scatter(cid, n, r)):
        PROPS.append(prop("%s_%s_%d" % (cid, type, i), type, (x, y), label, solid=solid, radius=radius))


trees("landing", 5, "round")
trees("landing", 3, "birch")
trees("millstone", 8, "oak")
trees("millstone", 5, "round")
trees("kite", 5, "round")
trees("kite", 3, "birch")
trees("orchard", 12, "blossom")
trees("orchard", 8, "fruit")
trees("orchard", 4, "round")
trees("vane", 10, "pine")
trees("vane", 6, "birch")
trees("pennant", 8, "pine")
trees("pennant", 4, "gold")
trees("pasture", 7, "gold")
trees("pasture", 5, "round")
trees("perch", 8, "pine")
trees("perch", 5, "birch")
trees(NEST_ISLE, 3, "pine", 24)
props("millstone", 4, "lr_boulder", "a boulder", r=18, solid=True, radius=8)
props("vane", 4, "lr_boulder", "a boulder", r=18, solid=True, radius=8)
props("pennant", 3, "lr_boulder", "a boulder", r=18, solid=True, radius=8)
props("perch", 3, "lr_boulder", "a boulder", r=18, solid=True, radius=8)
props("orchard", 3, "lr_planter", "a planter", r=18)
props("kite", 2, "lr_barrel", "a barrel", r=14, solid=True, radius=7)
ALL_PROPS = SPECIAL + PROPS

# ── the kites: bright diamonds on long lines, flying up and to the right (the way everything leans) ──
KITE_COLORS = [[0.96, 0.36, 0.30], [0.98, 0.78, 0.22], [0.30, 0.62, 0.96], [0.62, 0.40, 0.86], [0.34, 0.80, 0.52], [0.98, 0.56, 0.74]]
KITES = []
for i, pid in enumerate(["kite_stake_a", "kite_stake_b", "kite_stake_c", "kite_stake_d"]):
    pp = next(p for p in SPECIAL if p["id"] == pid)
    KITES.append({"anchor": [pp["position"][0], pp["position"][1] - 6], "len": [190, 240, 150, 110][i], "color": KITE_COLORS[i % 6], "phase": i * 1.7, "size": [14, 16, 13, 10][i]})
for i, (cid, dx, dy, ln) in enumerate([("pasture", 40, -20, 200), ("pennant", 90, 40, 170), ("orchard", 100, 40, 140)]):
    cc = at(cid, dx, dy)
    KITES.append({"anchor": [round(cc[0]), round(cc[1])], "len": ln, "color": KITE_COLORS[(i + 4) % 6], "phase": 3 + i * 2.1, "size": 12, "free": True})

SKY = {
    "colors": {"top": [0.46, 0.70, 0.96], "mid": [0.66, 0.84, 0.99], "bottom": [0.90, 0.95, 1.0]},
    "turf": "res://assets/sprites/lr_turf.png", "rock": "res://assets/sprites/lr_rock.png",
    "details": "res://assets/sprites/lr_details.png", "details_index": "res://data/lr_details.json",
    "clouds": {"textures": ["lr_cloud_a", "lr_cloud_b", "lr_cloud_c", "lr_cloud_d"], "count": 150, "parallax": 0.72, "drift": [9.0, -3.0], "alpha": 0.92, "seed": 17},
    "hiclouds": {"textures": ["lr_hicloud_a", "lr_hicloud_b"], "alpha": 0.95},
    "cliff_depth": 58.0, "edge_radius": 5.0, "rail_radius": 3.0,
    "shadow": [0.30, 0.44, 0.68, 0.20],
    "litter_density": 0.00055,
    "islands": [{"id": i[0], "name": i[1], "poly": [[round(p[0], 1), round(p[1], 1)] for p in POLYS[i[0]]]} for i in ISLANDS],
    "bridges": BRIDGE_OBJS,
    "windmills": [{"pos": [WIND_POS[0], WIND_POS[1]], "hub": [WIND_POS[0], WIND_POS[1] - 72], "blade": 54.0, "speed": 0.5}],
    "kites": KITES,
    "picture": {"puffs": PUFFS, "alpha": 0.95},
}

# ── the world's own ART OVERRIDE (deep-merged over data/art.json by ArtStyle.load_style) ─────────────
S = "res://assets/sprites/"


def tree_variants(names):
    return [{"trunk": S + "lr_%s_trunk.png" % n, "canopy": S + "lr_%s_canopy.png" % n} for n in names]


ART = {
    "palette": {
        "ground_top": [0.46, 0.70, 0.96], "ground_bottom": [0.90, 0.95, 1.0],
        "foliage_dark": [0.18, 0.42, 0.28], "foliage_mid": [0.36, 0.66, 0.34], "foliage_light": [0.68, 0.88, 0.46],
        "bark": [0.49, 0.37, 0.27], "water": [0.62, 0.80, 0.92], "rim": [1.0, 0.98, 0.9],
        "shadow": [0.20, 0.30, 0.50], "grass": [0.41, 0.69, 0.35],
    },
    "light": {"shadow_alpha": 0.20, "rim_strength": 0.22},
    "entities": {
        "portal": {"frame_tint": [0.80, 0.92, 1.0]},
        "ground": {"render": "none"},
        "understory": {"render": "sprite", "prefix": S + "lr_understory_", "types": ["bush_a", "bush_b", "bush_bloom", "stump"], "density": 0.35},
        "ambient_life": {"butterflies": {"count": 10, "colors": [[1.0, 0.86, 0.3], [1.0, 0.7, 0.85], [0.7, 0.85, 1.0]]},
                         "fireflies": {"count": 0}, "clouds": {"count": 0},
                         "leaves": {"rate": 0.5, "colors": [[1.0, 0.8, 0.86], [0.9, 0.96, 0.6], [1.0, 0.95, 0.8]]}},
        "tree": {"render": "sprite", "sway": 0.5, "variants": tree_variants(["round_a", "round_b", "oak_a", "birch_a"])},
        "round": {"render": "sprite", "sway": 0.5, "variants": tree_variants(["round_a", "round_b"])},
        "oak": {"render": "sprite", "sway": 0.4, "variants": tree_variants(["oak_a"])},
        "birch": {"render": "sprite", "sway": 0.6, "variants": tree_variants(["birch_a", "birch_b"])},
        "pine": {"render": "sprite", "sway": 0.3, "variants": tree_variants(["pine_a", "pine_b"])},
        "blossom": {"render": "sprite", "sway": 0.5, "variants": tree_variants(["blossom_a", "blossom_b"])},
        "fruit": {"render": "sprite", "sway": 0.4, "variants": tree_variants(["fruit_a"])},
        "gold": {"render": "sprite", "sway": 0.5, "variants": tree_variants(["gold_a"])},
        "great_tree": {"render": "sprite", "sway": 0.25, "variants": tree_variants(["great_oak"])},
        "great_apple": {"render": "sprite", "sway": 0.25, "variants": tree_variants(["great_apple"])},
        "great_oak": {"render": "sprite", "sway": 0.25, "variants": tree_variants(["great_oak"])},
        "props": {"extra_types": ["lr_windmill", "lr_kite_stake", "lr_vane", "lr_sign", "lr_boulder", "lr_barrel", "lr_haystack", "lr_planter",
                                  "lr_lamp", "lr_bench", "lr_pennant", "lr_perch", "lr_standing_stone", "lr_hammock"]},
    },
    "daycycle": {"enabled": True, "period_sec": 600, "loop": True, "stops": [
        {"t": 0.0, "tint": [1.0, 1.0, 1.0], "vignette": [0.40, 0.58, 0.86], "vstrength": 0.12},
        {"t": 1.0, "tint": [1.0, 0.96, 0.92], "vignette": [0.46, 0.56, 0.84], "vstrength": 0.16},
    ]},
}

ATMOSPHERE = {
    "day_tint": [1.0, 1.0, 1.0],
    "vignette": {"strength": 0.12, "color": [0.40, 0.58, 0.86]},
    "wind": {"strength": 3.4, "speed": 1.3},
    "pollen": {"amount": 0},
    "region_tint_alpha": 0.0,
    "grass": {"max": 0},
    "sparkles": {"count": 0},
}

# regions: each island's box (the companion's sense of "a new place")
REGIONS = []
for cid, name, c, r, tint in ISLANDS:
    xs = [p[0] for p in POLYS[cid]]
    ys = [p[1] for p in POLYS[cid]]
    REGIONS.append({"id": cid, "min": [round(min(xs)), round(min(ys))], "max": [round(max(xs)), round(max(ys))], "tint": list(tint)})

HEADER = ("LOFTREACH - sky islands. Grassy islets float in open sky (3400 x 2600), joined by rope bridges, with windmills, kites and a sea "
          "of cloud drifting below. The 'sky' block IS the world: islands (closed outlines: the turf, and the fence you cannot walk past, "
          "see SkyRealm), bridges (walkable strips; one is hidden until your companion has seen it from above), the windmill and kites, "
          "and 'picture' (the high clouds that make an arrow, seen only from far up). Eight islands (Anchor Landing where you arrive, Millstone Lea, "
          "Kite Green, Cloud Orchard, Vane Hill, Pennant Crag, Lantern Pasture, High Perch) and an islet you cannot walk to (The Rookery). It "
          "RE-SKINS ITSELF through its 'art' block (deep-merged over data/art.json): its own turf, rock, trees (tree entries [x, y, kind]: "
          "round/oak/birch/pine/blossom/fruit/gold). Its secret is a nest: see the 'secret' block (reveal type 'skyview'). Generated by "
          "tools/gen_loftreach_world.py (art: pokepals/tools/gen_loftreach.py) - edit that and re-run, don't hand-tune positions.")

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Loftreach'). reveal.type 'skyview': shift the companion into "
                  "a bird (reveal.species) and tell it to Go up; the camera rises with it and, from the 'vantage', the high clouds ('sky.picture') "
                  "show an arrow toward the nest. When the bird has looked at every one of 'targets' from high enough for 'see_secs' (SkyView), the "
                  "hidden bridge 'bridge' (sky.bridges) appears and can be walked to the nest, which is the secret's prop. The server honours a "
                  "claim only here, within 'radius' of 'position'.")
SECRET = {
    "id": "sky_nest",
    "position": list(NEST),
    "radius": 130.0,
    "prop": {"type": "lr_nest", "color": [0.86, 0.72, 0.46], "label": "a nest", "tags": ["woven", "high", "warm", "quiet"]},
    "lore": "A nest, woven from rope-ends, wind-flowers and feathers, and warm as if someone has only just left it. In it, one pale egg, with a faint blue light in the shell, and a single feather laid across it like a letter.",
    "reveal": {
        "type": "skyview",
        "species": "bird",
        "bridge": HID["id"],
        "vantage": list(VANTAGE),
        "targets": [list(NEST), [round(HEAD[0]), round(HEAD[1])]],
        "head": [round(HEAD[0]), round(HEAD[1])],
        "rise_secs": 1.6, "fly_speed": 1100.0, "travel_min": 0.9, "travel_max": 3.0,
        "stay_low": 5.0, "stay_high": 10.0, "hold_add": 3.0, "stay_cap": 20.0, "descend_secs": 1.5, "min_flight": 0.7,
        "zoom_low": 0.38, "zoom_high": 0.30, "bird_lift": 220.0,
        "see_alt": 0.72, "see_secs": 1.2, "view_margin": 30.0, "picture_from": 0.35, "picture_to": 0.8,
        "reveal_secs": 3.0, "after_reveal_stay": 2.2,
        "notice_range_low": 780.0, "notice_range_high": 1250.0, "notice_cooldown_low": 18.0, "notice_cooldown_high": 8.0, "notice_hold": 2.5,
        "look_back_secs": 3.0,
        "lines": {
            "notice": "Your companion stops at the edge and stares out across the sky at something you cannot see.",
            "not_bird": "Only a bird can climb that high. Shift your companion into its Bird shape, then tell it to Go up.",
            "launch": "Your companion's wings open, and it lifts off, and the whole sky tips up to meet you.",
            "picture": "From up here the clouds are not scattered. They lie in a line, and they have a point.",
            "seen": "It has seen it: the arrow, the far islet, and the edge of Pennant Crag where it would begin. A rope bridge unspools out of the haze.",
            "hold": "Your companion hangs on the wind a little longer.",
            "landed": "Your companion comes down beside you, windblown and pleased. Follow the arrow, to the edge of Pennant Crag.",
            "ended": "Your companion banks, and glides home.",
            "bridge": "A rope bridge, where nothing was. It runs out from the edge of Pennant Crag, toward the far islet.",
        },
        "reveal_line": "The nest is just as you saw it from above: woven, warm, and still. One pale egg lies in it, with a feather across it.",
    },
    "found_line": "A nest at the end of a path in the sky. The egg was not yours to take; the feather was. Your companion looked down on it, and now so can you.",
    "home_line": "Something has changed at home.",
    "qualities": ["high", "old", "warm"],
    "keepsake": {
        "id": "nest_feather", "type": "kept_nest", "color": [0.86, 0.72, 0.46], "label": "a little nest with a feather across it",
        "line": "A small woven nest, one pale egg, one long feather. The feather lifts, a little, when no one is moving.",
        "temperament": {"curiosity": 0.8, "energy": 0.6, "clinginess": 0.3},
    },
}


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "loftreach",')
out.append('\t"intro": %s,' % json.dumps("Islands in open sky, joined by ropes, with the wind going one way. Everything here leans toward something far off. Mind the edge."))
out.append('\t"regions": [\n%s\n\t],' % block(REGIONS))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": false, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.56, 0.78, 0.96],')
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [],')
out.append('\t"paths": [],')
out.append('\t"sky": %s,' % json.dumps(SKY, indent="\t", ensure_ascii=False, separators=(",", ": ")).replace("\n", "\n\t"))
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
BAD = []
pids = [p["id"] for p in d["props"]]
assert len(pids) == len(set(pids)), "duplicate ids"
for p in d["props"]:
    assert bool(p.get("interactive")) == bool(p.get("lore")), "interactive iff lore: %s" % p["id"]
    x, y = p["position"]
    home = next((c for c in ids if in_poly((x, y), POLYS[c])), None)
    assert home is not None, "prop off the islands: %s" % p["id"]
    if edge_dist((x, y), home) <= 40:
        BAD.append((p["id"], round(edge_dist((x, y), home))))
assert not BAD, "props too near an island's edge (move them in): %s" % BAD
for t in d["trees"]:
    assert any(in_poly((t[0], t[1]), POLYS[c]) for c in ids), "tree in the sky: %s" % t
for lm in d["landmarks"]:
    assert any(in_poly(tuple(lm["position"]), POLYS[c]) for c in ids), "landmark in the sky"
assert in_poly(tuple(PLAYER_SPAWN), POLYS["landing"]) and in_poly(tuple(COMPANION_SPAWN), POLYS["landing"])
assert in_poly(tuple(PORTALS[0]["position"]), POLYS["landing"]), "the portal home is on the landing"
assert in_poly(NEST, POLYS[NEST_ISLE]), "the nest is on the Rookery"
assert edge_dist(NEST, NEST_ISLE) > 60
for tgt in d["secret"]["reveal"]["targets"]:
    assert abs(tgt[0] - VANTAGE[0]) < 760 and abs(tgt[1] - VANTAGE[1]) < 420, "a target is out of the bond-0 view: %s" % tgt
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("props:", len(d["props"]), "| trees:", kinds)
for path in ["server/priv/world_seeds/loftreach.json", "pokepals/tests/world_fixtures/loftreach.json"]:
    open(path, "w").write(text)
print("wrote both files")
