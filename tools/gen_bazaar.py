#!/usr/bin/env python3
"""Generate the (bigger, denser) Thousand-Knot Bazaar world JSON.

Special props (Vanes, Knuckle furniture, lore signposts, the merchant + shop, the
wet-boots man, lanterns, the portal) are authored by hand below. The STALLS and CRATES
that pack each Knot are placed procedurally on a jittered grid with collision-aware
spacing, so the rows feel dense but stay walkable and nothing overlaps. Deterministic
(seeded), so re-running reproduces the same layout. Emits one interactable per line to
keep the file reviewable, then writes both the server seed and the client test fixture.
"""
import json, math, random

random.seed(0xB47AA2)

# ── world envelope (bigger than before: 3400 x 2600) ───────────────────────────────────
BOUNDS_MIN = (-1700, -1400)
BOUNDS_MAX = (1700, 1200)

REGIONS = [
    ("the_vein",          (-1700, -130), (1700, 130),  (0.80, 0.74, 0.58)),
    ("spice_knot",        (-1660, 170),  (-420, 1180), (0.86, 0.46, 0.22)),
    ("knuckle_south",     (-360, 170),   (360, 720),   (0.70, 0.60, 0.46)),
    ("ragpickers_tangle", (420, 170),    (1660, 1180), (0.32, 0.24, 0.18)),
    ("glassblowers_run",  (-1660, -960), (-420, -170), (0.36, 0.52, 0.82)),
    ("knuckle_north",     (-360, -960),  (360, -170),  (0.66, 0.60, 0.50)),
    ("bonewrights_knot",  (420, -960),   (1660, -170), (0.62, 0.70, 0.80)),
    ("high_stalls",       (-1000, -1380),(1000, -1000),(0.82, 0.78, 0.52)),
]

VEIN = {"rect": [-1700, -130, 3400, 260], "color": [0.74, 0.66, 0.50], "rim": [0.86, 0.80, 0.66]}

PLAYER_SPAWN = [-260, 360]
COMPANION_SPAWN = [-310, 392]

PATHS = [
    ([-1560, 0], [1560, 0]),       # the Vein spine
    ([0, 170], [0, 130]),          # South Knuckle down into the Vein
    ([-320, 420], [320, 420]),     # South Knuckle cross-way
    ([-700, 1140], [-700, 130]),   # Spice feeder
    ([700, 1140], [700, 130]),     # Ragpicker feeder
    ([-700, -940], [-700, -130]),  # Glass feeder
    ([700, -940], [700, -130]),    # Bone feeder
    ([0, -130], [0, -1180]),       # North Knuckle climb up to the High Stalls
]
PATH_CLEAR = 24.0  # keep stalls this far off a path centre, so lanes stay legible

FLOWERS = [
    [-360, 520, 0.92, 0.62, 0.30], [320, 520, 0.86, 0.40, 0.45],
    [-360, -440, 0.70, 0.78, 0.90], [360, -440, 0.84, 0.84, 0.88],
    [-80, 600, 0.95, 0.85, 0.40], [80, -640, 0.74, 0.80, 0.92],
]

# ── hand-authored special interactables ────────────────────────────────────────────────
def stall(id, type, pos, color, label, tags, solid=None, r=None, lore=None):
    e = {"id": id, "type": type, "position": [round(pos[0]), round(pos[1])],
         "color": [round(c, 2) for c in color], "label": label, "tags": tags}
    if solid is not None: e["solid"] = solid
    if r is not None: e["collision_radius"] = r
    if lore is not None: e["lore"] = lore
    # A prop opts into being examinable only if Examining it does something: it reads out a 'lore'
    # line, or it's the shopkeeper (opens the shop). Everything else stays static scenery.
    if lore is not None or type == "shopkeeper": e["interactive"] = True
    return e

SPECIAL = [
    stall("vane_copper_chimney", "chimney", (-1040, 680), (0.80, 0.50, 0.30), "the Copper Chimney", ["made", "landmark"], True, 16,
          "The Copper Chimney, forever smoking over the Spice Knot. Lost? Find its smoke and you've found your way."),
    stall("vane_prism_tower", "prism_tower", (-1040, -570), (0.55, 0.70, 0.95), "the Prism Tower", ["made", "landmark"], True, 14,
          "The Prism Tower throws rainbows over the Glassblowers' Run — a colour you can steer by from half the bazaar."),
    stall("vane_ivory_finger", "ivory_spire", (1040, -570), (0.90, 0.90, 0.84), "the Ivory Finger", ["made", "landmark"], True, 13,
          "The Ivory Finger, a carved spire pointing skyward over the hushed Bonewrights' Knot."),
    stall("vane_crooked_mast", "crooked_mast", (1040, 700), (0.42, 0.32, 0.22), "the Crooked Mast", ["made", "landmark"], True, 10,
          "The Crooked Mast leans over the Ragpicker's Tangle like a ship run aground in a river that left without it."),
    stall("vane_sky_anchor", "sky_anchor", (0, -1190), (0.70, 0.74, 0.58), "the Sky-Anchor", ["made", "landmark"], True, 14,
          "The Sky-Anchor hangs over the High Stalls on its chains — visible clear across the channel, for an anchor with no water to drop into."),

    stall("knuckle_south_well", "dry_well", (0, 460), (0.66, 0.58, 0.46), "the dry fountain", ["made", "knuckle"], True, 22,
          "A dry fountain. There's a green stain a hand's-width above the floor — the old waterline. The river stood this high, once."),
    stall("knuckle_south_board", "notice_board", (-150, 320), (0.60, 0.46, 0.32), "the South Knuckle notice-board", ["made", "knuckle"], True, 10,
          "THE THOUSAND-KNOT BAZAAR, in the bed of the Sleeping River. The river didn't dry up — it was sold, in a bargain no one quite remembers. The Knots are the slow repayment of that debt."),
    stall("knuckle_south_shrine", "shrine", (170, 320), (0.64, 0.56, 0.46), "a roadside shrine", ["made", "knuckle", "rest"],
          lore="A little shrine with a steady candle. A good place to stop a while, here at the bazaar's main crossing."),

    stall("knuckle_north_well", "dry_well", (0, -560), (0.64, 0.62, 0.56), "the dry fountain", ["made", "knuckle"], True, 22,
          "Another dry fountain, another high-water mark. Some vendors keep them swept, as if expecting the water back any morning now."),
    stall("knuckle_north_board", "notice_board", (-150, -460), (0.58, 0.52, 0.42), "the North Knuckle notice-board", ["made", "knuckle"], True, 10,
          "All roads run downhill to the Vein — follow the dry channel and you'll never be lost. They say the water returns when the debt is paid. A few quiet vendors are betting on when."),
    stall("knuckle_north_shrine", "shrine", (170, -460), (0.62, 0.56, 0.48), "a roadside shrine", ["made", "knuckle", "rest"],
          lore="A candle gutters in a stone niche. From here the climb north leads up to the High Stalls and the long views."),

    stall("sign_spice", "signpost", (-640, 360), (0.62, 0.43, 0.30), "a painted signboard", ["made", "lore"],
          lore="The first stalls were boats. Look at the curve of those old roofs — they were hulls, beached in the dry channel and never refloated."),
    stall("sign_glass", "signpost", (-640, -360), (0.44, 0.56, 0.74), "an etched glass placard", ["made", "lore"],
          lore="We melt sand from the dry bed. Every window in the Run is a piece of the river, made to hold light instead of water."),
    stall("sign_bone", "signpost", (680, -360), (0.74, 0.76, 0.80), "a carved bone marker", ["made", "lore"],
          lore="The Bonewrights keep the founder's ledgers. The page with the name is missing. It was removed, not lost."),
    stall("sign_ragpicker", "signpost", (680, 360), (0.44, 0.34, 0.26), "a tin scrap-sign", ["made", "lore"],
          lore="Someone down here sells river-charts. Charts of a river that doesn't exist yet. Ask for the man with wet boots."),
    stall("sign_high_stalls", "signpost", (-260, -1120), (0.80, 0.72, 0.44), "a weathered vista-sign", ["made", "lore"],
          lore="From up here you see the whole channel. On still mornings the dust in it moves like a current. The ones who watch are the ones who bet."),

    stall("wet_boots_man", "wanderer", (1180, 760), (0.34, 0.36, 0.42), "a man with wet boots", ["person", "ragpicker"],
          lore="His boots are wet — in a city built on a dry river, that means something. He deals in charts of water not yet returned, and asks only one thing: when?"),

    stall("shop_stall", "stall", (-1100, 240), (0.74, 0.56, 0.86), "the dye-maker's shop", ["made", "market"], True, 18),
    stall("color_merchant", "shopkeeper", (-1100, 296), (0.86, 0.62, 0.46), "the color merchant", ["person", "made"]),
]

# Lanterns — light, spread across the Knots + Knuckles. Placed before stalls so the grid avoids them.
LANTERNS = [
    ("lantern_spice_a", (-1040, 420), (0.95, 0.78, 0.42)), ("lantern_spice_b", (-720, 760), (0.95, 0.78, 0.42)),
    ("lantern_spice_c", (-520, 360), (0.95, 0.78, 0.42)),
    ("lantern_glass_a", (-1040, -360), (0.78, 0.86, 0.95)), ("lantern_glass_b", (-720, -640), (0.78, 0.86, 0.95)),
    ("lantern_bone_a", (760, -360), (0.86, 0.88, 0.92)), ("lantern_bone_b", (1040, -640), (0.86, 0.88, 0.92)),
    ("lantern_rag_a", (620, 360), (0.92, 0.70, 0.40)), ("lantern_rag_b", (980, 640), (0.92, 0.70, 0.40)),
    ("lantern_rag_c", (1220, 480), (0.92, 0.70, 0.40)), ("lantern_rag_d", (760, 960), (0.92, 0.70, 0.40)),
    ("lantern_high_a", (-380, -1100), (0.96, 0.84, 0.50)), ("lantern_high_b", (380, -1100), (0.96, 0.84, 0.50)),
    ("lantern_knuckle_s", (-80, 600), (0.95, 0.78, 0.42)), ("lantern_knuckle_n", (-80, -640), (0.95, 0.78, 0.42)),
]

# ── reserved obstacles the stall grid must keep clear of (x, y, clear_radius) ───────────
RESERVED = []
for e in SPECIAL:
    p = e["position"]
    typ = e["type"]
    clr = {"chimney":30,"prism_tower":28,"ivory_spire":26,"crooked_mast":24,"sky_anchor":32,
           "dry_well":40,"notice_board":28,"shrine":24,"signpost":22,"wanderer":26,
           "shopkeeper":28,"stall":30}.get(typ, 24)
    RESERVED.append((p[0], p[1], clr))
RESERVED.append((-1035, 308, 22))               # npc_companion puppet
RESERVED.append((280, 360, 46))                 # the bazaar_entry portal
RESERVED.append((PLAYER_SPAWN[0], PLAYER_SPAWN[1], 50))
RESERVED.append((COMPANION_SPAWN[0], COMPANION_SPAWN[1], 30))
for _id, pos, _c in LANTERNS:
    RESERVED.append((pos[0], pos[1], 20))

def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx-ax, by-ay
    if dx == 0 and dy == 0:
        return math.hypot(px-ax, py-ay)
    t = max(0.0, min(1.0, ((px-ax)*dx + (py-ay)*dy) / (dx*dx + dy*dy)))
    return math.hypot(px-(ax+t*dx), py-(ay+t*dy))

def near_path(x, y, clear=PATH_CLEAR):
    return any(seg_dist(x, y, a[0], a[1], b[0], b[1]) < clear for a, b in PATHS)

def near_reserved(x, y, extra=0.0):
    return any(math.hypot(x-rx, y-ry) < (rr+extra) for rx, ry, rr in RESERVED)

# ── per-Knot fill: (fill_rect, spacing, min_sep, density, cap, palette, labels) ─────────
KNOTS = {
    "spice": dict(rect=(-1620, 330, -460, 1140), spacing=78, min_sep=70, density=0.92, cap=34,
        palette=[(0.84,0.46,0.38),(0.86,0.58,0.30),(0.80,0.42,0.30),(0.84,0.66,0.34),(0.78,0.40,0.30),(0.86,0.66,0.30),(0.82,0.50,0.36),(0.88,0.54,0.26)],
        labels=["a spice stall","a pepper stall","a sweets stall","a tea stall","a chili stall","a grain stall","a honey stall","a fruit stall","a saffron stall","a cardamom stall","a roast-nut stall","a flatbread stall","a dried-fig stall","a clay-pot stall"]),
    "glass": dict(rect=(-1620, -940, -460, -210), spacing=72, min_sep=64, density=0.92, cap=30,
        palette=[(0.40,0.70,0.85),(0.55,0.45,0.85),(0.35,0.78,0.70),(0.50,0.60,0.88),(0.62,0.48,0.86),(0.45,0.72,0.80),(0.58,0.52,0.90)],
        labels=["a glassblower's stall","an enchanter's stall","an alchemist's stall","a lens-grinder's stall","a beadwork stall","a bottle stall","a mirror stall","a stained-glass stall","a phial stall","a charm-cutter's stall"]),
    "bone": dict(rect=(460, -940, 1620, -210), spacing=76, min_sep=68, density=0.88, cap=28,
        palette=[(0.80,0.82,0.86),(0.74,0.76,0.80),(0.86,0.86,0.82),(0.70,0.74,0.80),(0.78,0.80,0.84),(0.82,0.84,0.88)],
        labels=["a relic stall","a bonewright's stall","a scrimshaw stall","a ledger-keeper's stall","a reliquary stall","an ossuary stall","a charm-bone stall","a dust-and-incense stall","a memory-keeper's stall"]),
    "rag": dict(rect=(460, 210, 1620, 1140), spacing=60, min_sep=55, density=0.95, cap=50,
        palette=[(0.42,0.32,0.24),(0.46,0.34,0.24),(0.38,0.30,0.24),(0.34,0.28,0.22),(0.48,0.36,0.26),(0.40,0.30,0.22),(0.44,0.34,0.26),(0.50,0.38,0.26)],
        labels=["a rag stall","a salvage stall","a curio stall","a black-market stall","a scrap stall","a smoke-stall","a chart-seller's stall","a tinker's stall","a fortune stall","a lockpick stall","a found-things stall","a whisper stall","a cast-off stall"]),
    "high": dict(rect=(-960, -1360, 960, -1010), spacing=80, min_sep=72, density=0.85, cap=24,
        palette=[(0.86,0.72,0.36),(0.90,0.80,0.50),(0.84,0.70,0.40),(0.88,0.76,0.44),(0.86,0.74,0.42),(0.90,0.82,0.52)],
        labels=["a gilded stall","a silk stall","a jeweller's stall","a vintner's stall","a perfumer's stall","a goldwright's stall","a fine-cloth stall","a spice-of-kings stall","a rare-book stall"]),
}

placed = []  # (x, y) of every placed solid stall/crate (for inter-stall spacing)

def jitter_color(c):
    return tuple(min(1.0, max(0.0, ch + random.uniform(-0.03, 0.03))) for ch in c)

def gen_stalls(prefix, cfg):
    rect = cfg["rect"]; sp = cfg["spacing"]; ms = cfg["min_sep"]
    x0, y0, x1, y1 = rect
    out = []
    n = 0
    ny = int((y1 - y0) // sp) + 1
    nx = int((x1 - x0) // sp) + 1
    cells = [(ix, iy) for iy in range(ny) for ix in range(nx)]
    random.shuffle(cells)
    for ix, iy in cells:
        if n >= cfg["cap"]:
            break
        if random.random() > cfg["density"]:
            continue
        cx = x0 + ix * sp + sp * 0.5 + random.uniform(-sp*0.28, sp*0.28)
        cy = y0 + iy * sp + sp * 0.5 + random.uniform(-sp*0.28, sp*0.28)
        if not (x0 <= cx <= x1 and y0 <= cy <= y1):
            continue
        if near_path(cx, cy) or near_reserved(cx, cy, 16):
            continue
        if any(math.hypot(cx-px, cy-py) < ms for px, py in placed):
            continue
        col = jitter_color(random.choice(cfg["palette"]))
        lbl = random.choice(cfg["labels"])
        out.append(stall("%s_stall_%d" % (prefix, n+1), "stall", (cx, cy), col, lbl, ["made","market"], True, 16))
        placed.append((cx, cy))
        n += 1
    return out

def gen_crates(prefix, cfg, count, colors):
    rect = cfg["rect"]; x0, y0, x1, y1 = rect
    out = []; n = 0; tries = 0
    while n < count and tries < count*60:
        tries += 1
        cx = random.uniform(x0, x1); cy = random.uniform(y0, y1)
        if near_path(cx, cy, 18) or near_reserved(cx, cy, 12):
            continue
        if any(math.hypot(cx-px, cy-py) < 34 for px, py in placed):
            continue
        col = jitter_color(random.choice(colors))
        out.append(stall("%s_crate_%d" % (prefix, n+1), "crate", (cx, cy), col, "a stack of crates", ["made","market"], True, 9))
        placed.append((cx, cy)); n += 1
    return out

stalls = []
for key in ["spice", "glass", "bone", "rag", "high"]:
    stalls += gen_stalls(key, KNOTS[key])

# crates thicken the Tangle into a maze; a little fine cargo dresses the High Stalls
crates = gen_crates("rag", KNOTS["rag"], 18, [(0.50,0.40,0.28),(0.46,0.36,0.26)])
high_crate_cfg = dict(KNOTS["high"]);
crates += gen_crates("high", high_crate_cfg, 7, [(0.84,0.72,0.44),(0.80,0.68,0.40)])

lanterns = [stall(i, "lantern", p, c, "a hanging lantern", ["light","made"]) for i, p, c in LANTERNS]

counts = {}
for s in stalls:
    pre = s["id"].split("_stall_")[0]
    counts[pre] = counts.get(pre, 0) + 1
print("stalls per Knot:", counts, "| total stalls:", len(stalls), "| crates:", len(crates), "| lanterns:", len(lanterns))

# ── overlap / bounds validation ─────────────────────────────────────────────────────────
all_solid = []
for e in SPECIAL + stalls + crates + lanterns:
    if e.get("solid") or e["type"] in ("signpost","lantern"):
        r = e.get("collision_radius", {"signpost":7,"lantern":6}.get(e["type"], 8))
        all_solid.append((e["id"], e["position"][0], e["position"][1], r))
bad = 0
for i in range(len(all_solid)):
    for j in range(i+1, len(all_solid)):
        a, b = all_solid[i], all_solid[j]
        d = math.hypot(a[1]-b[1], a[2]-b[2])
        if d < a[3] + b[3] - 1.0:  # circles actually overlap
            bad += 1
            if bad <= 8: print("  OVERLAP", a[0], b[0], "d=%.1f r=%d+%d" % (d, a[3], b[3]))
for e in SPECIAL + stalls + crates + lanterns:
    x, y = e["position"]
    if not (BOUNDS_MIN[0]+10 <= x <= BOUNDS_MAX[0]-10 and BOUNDS_MIN[1]+10 <= y <= BOUNDS_MAX[1]-10):
        print("  OUT OF BOUNDS", e["id"], e["position"])
print("solid-overlap pairs:", bad)

# ── emit JSON (one interactable per line, tab-indented, grouped with comments) ───────────
def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "))

interactable_groups = [
    ("the five Vanes — the skyline compass, one tall landmark per Knot", SPECIAL[0:5]),
    ("the Knuckle plazas: dry well, notice-board, rest shrine", SPECIAL[5:11]),
    ("one lore signpost per Knot (Examine to read its story fragment)", SPECIAL[11:16]),
    ("the wet-boots man (Ragpicker's Tangle quest seed)", SPECIAL[16:17]),
    ("the colour merchant + shop (Spice Knot onboarding)", SPECIAL[17:19]),
    ("Spice Knot stalls (procedurally packed; tidy rows — onboarding)", [s for s in stalls if s["id"].startswith("spice_")]),
    ("Glassblowers' Run stalls", [s for s in stalls if s["id"].startswith("glass_")]),
    ("Bonewrights' Knot stalls (quieter, paler)", [s for s in stalls if s["id"].startswith("bone_")]),
    ("Ragpicker's Tangle stalls + crates (densest, maziest)", [s for s in stalls if s["id"].startswith("rag_")] + [c for c in crates if c["id"].startswith("rag_")]),
    ("High Stalls (wealthiest, gilded) + fine cargo", [s for s in stalls if s["id"].startswith("high_")] + [c for c in crates if c["id"].startswith("high_")]),
    ("lanterns", lanterns),
]
# Groups are separated by a blank line only (JSON has no comments, and a comment OBJECT inside the
# array would crash to_vec2(it["position"]) — so the group notes live in _props_comment).
parts = [",\n".join(line(e) for e in group) for _note, group in interactable_groups if group]
body = ",\n\n".join(parts)
INTER_COMMENT = "All the props world_art draws, grouped in array order: " + "; ".join(
    note for note, group in interactable_groups if group) + ". A prop is static scenery unless it opts in with \"interactive\": true (the Vanes, Knuckle furniture, lore signposts, the wet-boots man, and the merchant — each does something or reads out a lore line on Examine; stalls/crates/lanterns just convey themselves by appearance). Stalls/crates are generated by tools/gen_bazaar.py — edit that and re-run to re-pack, don't hand-tune positions."

def vec_line(items):
    return ",\n".join("\t\t" + json.dumps(x, separators=(", ", ": ")) for x in items)

region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c,2) for c in r[3]]} for r in REGIONS]
path_objs = [{"from": a, "to": b, "color": [0.50, 0.42, 0.32]} for a, b in PATHS]

HEADER = "THE THOUSAND-KNOT BAZAAR — a sprawling fantasy market wound around the dry bed of the Sleeping River (the river that 'was sold'). Reached from the Vale through the sun-warmed archway. PILLARS: (1) NAVIGATION — the Vein (a sunken dry channel) runs the world's width and every Knot's paths drain into it; five tall VANES are the skyline compass; two KNUCKLE plazas anchor the middle. (2) ATMOSPHERE & LORE — five KNOT districts, each a tinted region with its own palette, Vane, and one story fragment (Examine its lore signpost or a Knuckle notice-board). Stalls are placed procedurally (see tools/gen_bazaar.py) so rows feel packed but stay walkable — tidy in Spice (onboarding), tangled in the Ragpicker's. +y is south, -y is north; colors [r,g,b] 0..1. world_art draws by 'type'; new types: vein + chimney/prism_tower/ivory_spire/crooked_mast/sky_anchor (Vanes), dry_well/notice_board/shrine, wanderer, crate. A prop's optional 'lore' is read out on Examine."

out = []
out.append("{")
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "bazaar",')
out.append('\t"regions": [')
out.append(vec_line(region_objs))
out.append('\t],')
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"border": { "ring": true, "spacing": 200, "inset": 28, "jitter": 30, "rows": 1, "row_gap": 54 },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.62, 0.52, 0.40],')
out.append('\t"atmosphere": {')
out.append('\t\t"day_tint": [1.05, 0.97, 0.85],')
out.append('\t\t"vignette": { "strength": 0.30, "color": [0.10, 0.07, 0.06] },')
out.append('\t\t"wind": { "strength": 1.6, "speed": 1.0 },')
out.append('\t\t"ground_noise": { "contrast": 0.12, "tint": [0.42, 0.34, 0.24] },')
out.append('\t\t"pollen": { "amount": 34, "color": [0.92, 0.84, 0.62] },')
out.append('\t\t"glow": { "pulse_speed": 1.2 },')
out.append('\t\t"region_tint_alpha": 0.16')
out.append('\t},')
out.append('\t"vein": %s,' % json.dumps(VEIN, separators=(", ", ": ")))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"paths": [')
out.append(vec_line(path_objs))
out.append('\t],')
out.append('\t"flowers": [')
out.append(vec_line(FLOWERS))
out.append('\t],')
out.append('\t"_props_comment": %s,' % json.dumps(INTER_COMMENT))
out.append('\t"props": [')
out.append(body)
out.append('\t],')
out.append('\t"npc_companion": {')
out.append('\t\t"position": [-1035, 308],')
out.append('\t\t"look": { "ear_rest": 7.0, "bounce_base": 2.4, "wag_life": 3.5, "eye_lift": 2.5, "coat_warm": 0.35, "body_scale": 1.12 }')
out.append('\t},')
out.append('\t"portals": [')
out.append('\t\t{ "id": "bazaar_entry", "type": "portal", "position": [280, 360], "color": [0.96, 0.82, 0.50], "label": "the sun-warmed archway", "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_bazaar_portal" }')
out.append('\t]')
out.append("}")
text = "\n".join(out) + "\n"

# validate it parses + integrity
d = json.loads(text)
props = d["props"]
ids = [i["id"] for i in props if i.get("id")]
assert len(ids) == len(set(ids)), "dup ids"
assert any(i["type"] == "shopkeeper" for i in props), "no shopkeeper"
assert any(p["id"] == "bazaar_entry" for p in d["portals"]), "no portal"
assert d["npc_companion"], "no npc"
# Interactivity opts in: examinable exactly when it has lore or is the shopkeeper.
for i in props:
    want = bool(i.get("lore")) or i["type"] == "shopkeeper"
    assert bool(i.get("interactive", False)) == want, "interactive flag mismatch on %s" % i.get("id")
interactive = sum(1 for i in props if i.get("interactive"))
print("PARSES OK | props:", len(props), "| interactive:", interactive, "| real ids:", len(ids))

for path in ["server/priv/world_seeds/bazaar.json", "pokepals/tests/world_fixtures/bazaar.json"]:
    open(path, "w").write(text)
print("wrote both files")
