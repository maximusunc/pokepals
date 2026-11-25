#!/usr/bin/env python3
"""Generate GLYPHFALL, the world made of text characters, as a world spec (issue #159).

One of the "completely different skin" worlds. The story: somebody once described a valley so carefully that
the description became the place. So the valley IS its description: the grass is quote marks, the water is
tildes, the trees are clubs and spades, and the paths are the writer's own sentences, which you can read as
you walk along them. A modest (3200 x 2400) walk-and-wonder world, no goal and no puzzle.

How it looks is one layer (GlyphPage, assets/glyph_page.gdshader) laid over an ordinary pixel-art world: it
reads the finished picture and writes it again as monospace characters, choosing each from what is under it.
So this spec is a normal meadow world, tuned so its colours fall cleanly into the shader's families (olive
grass, green leaves, blue water, sandy earth), plus an `atmosphere.glyphs` block that turns the page on and
carries the sentences the paths are written in.

Its one SECRET (docs/home-world-and-secrets-design.md, "Glyphfall"): one character in the world is the wrong
glyph. Out in the Unwritten, where the description trails off, an ampersand stands among the quote marks of
the grass, the same colour as everything round it. You could walk past it all day. Your companion notices: it
stops and looks (reveal type "misprint"; the pure GlyphNotice, driven by MisprintDirector). Walk to where it is
looking and the ampersand catches the light; examining it claims the secret as usual, and the page is
corrected. Every number lives in this file's data, not in code.

Hand-authored: regions, ponds, paths, the paragraphs of trees, every lore line, the sentences, the secret.
Procedural (seeded, so re-running reproduces it): the loose scatter of trees and props.

Art: the shared meadow art, re-coloured through the `art` block; the glyph atlas comes from
pokepals/tools/gen_glyphfall.py. Writes the server seed and the client test fixture. Run from the repo root:
  python3 tools/gen_glyphfall_world.py
"""
import json
import math
import random

random.seed(0x61F4)

BOUNDS_MIN = (-1600, -1200)
BOUNDS_MAX = (1600, 1200)
PLAYER_SPAWN = [0, 930]
COMPANION_SPAWN = [-30, 955]
PORTALS = [
    {"id": "glyphfall_way_home", "type": "portal", "position": [-76, 930], "color": [0.80, 0.86, 0.70], "label": "the way back to the Vale",
     "target_world": "11111111-1111-1111-1111-111111111111", "target_portal": "vale_gateway"},
]

# ── regions: (id, min, max, tint): a clean partition of the bounds ───────────────────────────────────
REGIONS = [
    ("the_margin",     (-500, 640),    (500, 1200),  (0.90, 0.92, 0.78)),
    ("footnotes",      (500, 640),     (1600, 1200), (0.80, 0.90, 0.92)),
    ("the_inkwell",    (-1600, 200),   (-500, 1200), (0.74, 0.84, 0.96)),
    ("first_lines",    (-500, -150),   (1600, 640),  (0.94, 0.90, 0.74)),
    ("paragraph_wood", (-1600, -1200), (-500, 200),  (0.72, 0.90, 0.76)),
    ("the_heading",    (-500, -1200),  (500, -150),  (0.96, 0.82, 0.90)),
    ("the_unwritten",  (500, -1200),   (1600, -150), (0.88, 0.90, 0.80)),
]

# ── water: the Inkwell (two overlapping ponds), and three small footnotes ────────────────────────────
WATER = [0.24, 0.42, 0.62]
PONDS = [
    {"center": [-1060, 700], "radius": 210, "color": WATER},
    {"center": [-900, 800], "radius": 140, "color": WATER},
    {"center": [900, 900], "radius": 64, "color": WATER},
    {"center": [1190, 830], "radius": 52, "color": WATER},
    {"center": [1330, 1020], "radius": 58, "color": WATER},
]

# ── paths: the writer's sentences. The Long Sentence runs straight across the middle (so it reads); one
# path leaves it for the Unwritten and simply stops, part-way through a thought. ──────────────────────
PATH_COLOR = [0.72, 0.60, 0.40]
LONG_Y = 126   # the middle of a row of the page (rows are 12 px), so the sentence sits on its line


def run(points):
    return [(a, b) for a, b in zip(points[:-1], points[1:])]


LINES = [
    [(x, LONG_Y) for x in range(-1350, 1351, 270)],                    # the Long Sentence...
    [(x, LONG_Y + 12) for x in range(-1350, 1351, 270)],               # ...which runs to a second line
    [(0, 900), (0, 640), (0, 380), (0, LONG_Y)],                       # up from the margin
    [(0, LONG_Y), (0, -160), (0, -430), (0, -700)],                    # on to the Heading
    [(-810, LONG_Y), (-880, 300), (-960, 430)],                        # down to the Inkwell
    [(810, LONG_Y), (860, 400), (880, 640), (900, 790)],               # down to the footnotes
    [(540, LONG_Y), (640, -80), (760, -260), (860, -400)],             # into the Unwritten... and it stops
]
PATH_END = (860, -400)
PATH_SEGS = [seg for ln in LINES for seg in run(ln)]

LANDMARKS = [
    {"type": "great_tree", "position": [-220, -820]},
    {"type": "great_tree", "position": [230, -860]},
    {"type": "great_tree", "position": [-1320, 330]},
]

# ── THE WRONG GLYPH ──────────────────────────────────────────────────────────────────────────────────
# An ampersand in the grass of the Unwritten, a way past where the path gives out. It sits in the middle of
# its character cell (cells are 8 x 12 world px, pinned to the world).
CELL = (8, 12)


def cell_centre(x, y):
    return (math.floor(x / CELL[0]) * CELL[0] + CELL[0] / 2.0, math.floor(y / CELL[1]) * CELL[1] + CELL[1] / 2.0)


GLYPH = cell_centre(1068, -640)


def _seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
    return math.hypot(p[0] - (ax + dx * t), p[1] - (ay + dy * t))


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
PINK = (0.96, 0.52, 0.72)
GOLD = (0.98, 0.84, 0.36)
VIOLET = (0.74, 0.60, 0.96)

# ── hand-placed props: things the writer took the trouble to describe ────────────────────────────────
SPECIAL = [
    prop("margin_sign", "signpost", (70, 880), WHITE, "a signpost",
         "It says: GLYPHFALL. Under that, smaller: \"written down so that it would keep.\" Under that, smaller still, something crossed out.", solid=True, radius=5),
    prop("margin_bench", "bench", (-150, 800), WHITE, "a bench",
         "The word for a bench, and so, a bench. It holds your weight, which seems generous of a word."),
    prop("margin_flowers", "wildflowers", (150, 760), PINK, "some flowers",
         "Asterisks, mostly. Whoever wrote this place down could not draw a flower and did not let that stop them."),
    prop("sentence_stone", "chime_stone", (-300, 70), VIOLET, "a ringing stone",
         "Touch it and it sounds one clear note, the way a full stop sounds if you read aloud."),
    prop("sentence_lamp", "lantern", (300, 80), GOLD, "a lamp",
         "A lamp left by the path, so the sentence can be read after dark. It is never dark here. The lamp was left anyway.", solid=True, radius=5),
    prop("sentence_board", "notice_board", (-560, 60), WHITE, "a board of notes",
         "Notes to self, pinned up. \"More birds.\" \"Is the water too blue?\" \"Leave room at the end.\"", solid=True, radius=8),
    prop("inkwell_basin", "basin", (-760, 560), WHITE, "a stone bowl",
         "A bowl to wash a pen in. The water in it is the same water as the Inkwell, which is to say it is mostly the word 'water', and very clear."),
    prop("inkwell_log", "log", (-1300, 960), WHITE, "a fallen log",
         "\"A log lay by the water.\" That is all it says about it, and the log has been lying by the water ever since."),
    prop("wood_pillar", "broken_pillar", (-1080, -520), WHITE, "a broken column",
         "The only thing here that was crossed out and then let stay. You can still see the line through it.", solid=True, radius=7),
    prop("wood_mushrooms", "mushrooms", (-820, -300), WHITE, "mushrooms",
         "They grow in the gaps between paragraphs, where nobody was looking when they wrote."),
    prop("heading_carving", "carving", (0, -760), WHITE, "a carved stone",
         "The title, cut into stone at the top of everything. The letters are worn too soft to read. You can tell it was short, and that somebody liked it.", solid=True, radius=8),
    prop("heading_crystal", "crystal", (-120, -420), VIOLET, "a clear crystal",
         "Hold it up and everything behind it turns into small neat letters. Put it down and everything stays that way."),
    prop("footnote_berries", "berry_bush", (1060, 940), (0.86, 0.30, 0.40), "a berry bush",
         "A footnote says the berries are sweet. A footnote to the footnote says: in summer. It is always summer."),
    prop("footnote_crate", "crate", (760, 1040), WHITE, "a crate",
         "A crate of spare punctuation. Mostly commas. A world like this gets through a great many commas.", solid=True, radius=7),
    prop("unwritten_end", "rubble_pile", (PATH_END[0] + 26, PATH_END[1] - 18), WHITE, "the end of the path",
         "The path stops here, in the middle of a thought. Beyond it there is only grass, and whatever the writer meant to say next."),
    prop("unwritten_column", "column", (1360, -980), WHITE, "a lone column",
         "One column, holding up nothing yet. There was going to be more here. There is room for it.", solid=True, radius=7),
]

placed = [(p["position"][0], p["position"][1], 24) for p in SPECIAL]
for lm in LANDMARKS:
    placed.append((lm["position"][0], lm["position"][1], 70))


def clear(x, y, r, path_gap=34):
    if not (BOUNDS_MIN[0] + 140 <= x <= BOUNDS_MAX[0] - 140 and BOUNDS_MIN[1] + 140 <= y <= BOUNDS_MAX[1] - 140):
        return False
    if math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1]) < 170:
        return False
    if any(math.hypot(x - pd["center"][0], y - pd["center"][1]) < pd["radius"] * 1.15 + r for pd in PONDS):
        return False
    if any(_seg_dist((x, y), a, b) < path_gap + r for a, b in PATH_SEGS):
        return False
    # nothing stands near the wrong glyph: it is alone in open grass
    if math.hypot(x - GLYPH[0], y - GLYPH[1]) < 150 + r:
        return False
    return all(math.hypot(x - px, y - py) >= r + pr for px, py, pr in placed)


TREES = []
PROPS = []


def scatter(region_id, n, r, tries=4000):
    rmin, rmax = next((a, b) for rid, a, b, _ in REGIONS if rid == region_id)
    out = []
    for _ in range(tries):
        if len(out) >= n:
            break
        x = random.uniform(rmin[0], rmax[0])
        y = random.uniform(rmin[1], rmax[1])
        if clear(x, y, r):
            placed.append((x, y, r))
            out.append((round(x), round(y)))
    return out


def trees(region, n, kind="tree", r=26):
    for x, y in scatter(region, n, r):
        TREES.append([x, y, kind])


def props(region, n, type, label, r=16, solid=None, radius=None, color=WHITE):
    for x, y in scatter(region, n, r):
        PROPS.append(prop("%s_%s_%d" % (region, type, len(PROPS)), type, (x, y), color, label, solid=solid, radius=radius))


# PARAGRAPH WOOD: the trees stand in paragraphs. Each is a block of rows; the first row is indented and the
# last one stops short, the way a paragraph does. You walk the white space between the lines.
def paragraph(x0, y0, rows, cols, kind="tree", gap_x=46, gap_y=64, indent=2):
    last = random.randint(max(2, cols // 3), cols - 2)
    for r in range(rows):
        start = indent if r == 0 else 0
        end = last if r == rows - 1 else cols
        for c in range(start, end):
            x = x0 + c * gap_x + random.uniform(-3, 3)
            y = y0 + r * gap_y + random.uniform(-3, 3)
            if clear(x, y, 10, path_gap=30):
                placed.append((x, y, 20))
                TREES.append([round(x), round(y), kind])


paragraph(-1440, -1030, 4, 11)
paragraph(-1440, -700, 3, 9, kind="pine")
paragraph(-1000, -1000, 5, 8)
paragraph(-1400, -440, 4, 12)
paragraph(-1380, -110, 3, 10, kind="pine")
paragraph(-820, -620, 3, 6)
trees("paragraph_wood", 14)
props("paragraph_wood", 8, "mushrooms", "mushrooms")
props("paragraph_wood", 4, "log", "a fallen log")

# THE HEADING: blossom trees round the title stone, like an illuminated capital.
for i in range(12):
    a = i / 12.0 * math.tau
    x, y = 0 + math.cos(a) * 190, -760 + math.sin(a) * 130
    if clear(x, y, 12):
        placed.append((x, y, 22))
        TREES.append([round(x), round(y), "blossom"])
trees("the_heading", 26, "blossom", 30)
trees("the_heading", 12)
props("the_heading", 10, "wildflowers", "some flowers", color=PINK)
props("the_heading", 4, "wildflowers", "some flowers", color=GOLD)

# The rest: loose trees, and small things in the grass.
trees("the_margin", 16)
props("the_margin", 6, "wildflowers", "some flowers", color=GOLD)
props("the_margin", 3, "berry_bush", "a berry bush", color=(0.86, 0.30, 0.40))
trees("the_inkwell", 30)
trees("the_inkwell", 8, "pine")
props("the_inkwell", 5, "wildflowers", "some flowers", color=VIOLET)
props("the_inkwell", 4, "log", "a fallen log")
trees("first_lines", 46)
props("first_lines", 10, "wildflowers", "some flowers", color=PINK)
props("first_lines", 6, "wildflowers", "some flowers", color=GOLD)
props("first_lines", 5, "berry_bush", "a berry bush", color=(0.86, 0.30, 0.40))
props("first_lines", 4, "mushrooms", "mushrooms")
trees("footnotes", 22)
props("footnotes", 8, "wildflowers", "some flowers", color=VIOLET)
props("footnotes", 5, "mushrooms", "mushrooms")
# THE UNWRITTEN: almost nothing. A few trees at its edges, a few flowers, and a great deal of grass.
trees("the_unwritten", 9)
props("the_unwritten", 4, "wildflowers", "some flowers", color=GOLD)

ALL_PROPS = SPECIAL + PROPS

AMBIENT_PALS = []
for i, (species, home, r) in enumerate([("rabbit", (-260, 760), 120), ("bird", (240, 420), 150), ("cat", (-620, 250), 100),
                                        ("rabbit", (700, 380), 140), ("fox", (-1180, -260), 170), ("bird", (-80, -560), 150),
                                        ("rabbit", (1120, 700), 110), ("bird", (-760, 980), 140)]):
    AMBIENT_PALS.append({"id": "pal_gf_%d" % i, "home": list(home), "roam_radius": r, "region": "gf", "species": species,
                         "variant": i % 3, "look": {"ear_rest": 2.0, "bounce_base": 2.6, "wag_life": 2.2, "body_scale": 0.86}})

# ── the world's own ART OVERRIDE (deep-merged over data/art.json by ArtStyle.load_style) ─────────────
# The shared meadow art, tuned so each material's colour falls cleanly into one of the glyph shader's
# families: the grass is olive (yellow-green: quote marks), the trees are the green ones only (clubs and
# spades), blossom trees are pink (flowers), the paths are pale and sandy (the sentences).
S = "res://assets/sprites/"


def ramp(*rows):
    return [list(r) for r in rows]


def tree_variants(names):
    return [{"trunk": S + "grove_%s_trunk.png" % n, "canopy": S + "grove_%s_canopy.png" % n} for n in names]


ART = {
    "palette": {"water": WATER},
    "entities": {
        "portal": {"frame_tint": [0.86, 0.90, 0.78]},
        "ground": {
            "ramps": {
                "grass": ramp((0.36, 0.41, 0.17), (0.44, 0.50, 0.21), (0.50, 0.56, 0.24), (0.64, 0.70, 0.33)),
                "lush": ramp((0.27, 0.32, 0.13), (0.33, 0.39, 0.16), (0.39, 0.45, 0.19), (0.50, 0.57, 0.26)),
                "meadow": ramp((0.43, 0.47, 0.19), (0.51, 0.56, 0.23), (0.58, 0.63, 0.26), (0.72, 0.76, 0.36)),
                "dirt": ramp((0.50, 0.40, 0.27), (0.60, 0.49, 0.33), (0.67, 0.56, 0.38), (0.80, 0.70, 0.50)),
                "sand": ramp((0.58, 0.50, 0.34), (0.68, 0.59, 0.41), (0.75, 0.66, 0.46), (0.86, 0.78, 0.58)),
                "path": ramp((0.56, 0.46, 0.30), (0.66, 0.55, 0.37), (0.73, 0.62, 0.42), (0.85, 0.75, 0.54)),
                "worn": ramp((0.42, 0.45, 0.20), (0.50, 0.53, 0.24), (0.56, 0.59, 0.27), (0.69, 0.72, 0.36)),
            },
            "patches": {"lush": {"scale": 0.0034, "threshold": 0.56}, "meadow": {"scale": 0.0048, "threshold": 0.62},
                        "dirt": {"scale": 0.006, "threshold": 0.9}},
        },
        "ambient_life": {"butterflies": {"count": 0}, "fireflies": {"count": 0}, "leaves": {"rate": 0.0},
                         "clouds": {"count": 5, "alpha": 0.16, "speed": 7}},
        "tree": {"render": "sprite", "variants": tree_variants(["round_a", "oak_a", "round_b", "pine_a", "round_c", "oak_b", "fruit_a"])},
        "pine": {"render": "sprite", "variants": tree_variants(["pine_a", "pine_b"])},
        "blossom": {"render": "sprite", "variants": tree_variants(["blossom_a"])},
        # the secret's prop is a character on the page (GlyphPage draws it), so WorldArt never paints it
        "props": {"unseen": ["unseen"]},
    },
    # every visitor is drawn as they are, but marked in the picture, so the page writes them in fine print
    "actor_look": {"glyph": {"mark": 0.5, "lift": 0.12}},
    "daycycle": {"enabled": False},
}

# The sentences the paths are written in (GlyphPage: every cell of earth takes its letter from these, a line
# to each row of the page, so a path running east to west reads). Lower case, and only , . ' - ? besides.
SENTENCES = [
    "there is a valley and a path goes through it. ",
    "the grass is the long kind that leans when the wind comes. ",
    "the water is still enough to hold the whole sky. ",
    "the trees were here first and will tell you so. ",
    "it is always about four in the afternoon. ",
    "somebody small lives under the hedge and is not to be bothered. ",
    "nothing here needs doing. you are welcome to stay. ",
    "i wrote it down so that it would keep. ",
    "if you are reading this then it kept. ",
    "and the path goes on, and ",
]

ATMOSPHERE = {
    "day_tint": [1.0, 1.0, 1.0],
    "vignette": {"strength": 0.30, "color": [0.02, 0.03, 0.05]},
    "wind": {"strength": 1.2, "speed": 0.8},
    "pollen": {"amount": 0},
    "region_tint_alpha": 0.0,
    "grass": {"max": 0},
    # THE PAGE: the whole picture written again as monospace characters (GlyphPage). Full colour on a dark page.
    "glyphs": {
        "cell": list(CELL), "page": [0.035, 0.040, 0.060], "bg_tint": 0.10, "actor_bg": 0.42, "ink_floor": 0.5,
        "lum_lo": 0.10, "lum_hi": 0.72, "grass_gap": 0.3, "sway": 0.07, "water_rate": 1.1, "type_in": 1.6,
        "actor_box": [9, 17, -11],
        # a line of the page is two sentences end to end, so a path does not say the same thing twice in one view
        "sentences": [SENTENCES[i] + SENTENCES[(i + 4) % len(SENTENCES)] for i in range(len(SENTENCES))],
    },
}

HEADER = ("GLYPHFALL - a world made of text characters (issue #159). Somebody described a valley so carefully that the "
          "description became the place: the grass is quote marks, the water is tildes, the trees are clubs and spades, "
          "and the paths are the writer's sentences, readable as you walk. A walk-and-wonder world (no goal, no puzzle). "
          "Seven regions: the Margin (where you arrive), the Footnotes, the Inkwell, First Lines (the Long Sentence runs "
          "across it), Paragraph Wood (trees set in paragraphs), the Heading and the Unwritten. It is an ordinary meadow "
          "world underneath; 'atmosphere.glyphs' lays one layer over it (GlyphPage) that writes the finished picture "
          "again as monospace characters, and its 'art' block tunes the shared meadow art so each material's colour "
          "picks the right characters. Its secret is one wrong glyph: see the 'secret' block (reveal type 'misprint'). "
          "Generated by tools/gen_glyphfall_world.py (atlas: pokepals/tools/gen_glyphfall.py) - edit that and re-run, "
          "don't hand-tune positions.")

SECRET_COMMENT = ("This world's one SECRET (docs/home-world-and-secrets-design.md, 'Glyphfall'). reveal.type 'misprint': the "
                  "character cell holding 'position' shows reveal.glyph (an ampersand) in place of grass, in the grass's own "
                  "colour. As the player passes within the notice range (wider with bond) the companion stops and looks at "
                  "it for 'notice_hold' seconds, again after a cooldown (shorter with bond, and nearer). Once it has noticed "
                  "and the player comes within 'find_radius', the glyph catches the light and can be examined (GlyphNotice / "
                  "MisprintDirector). The prop's type is 'unseen': the page draws it, not WorldArt. The server honours a "
                  "claim only here, within 'radius' of 'position'.")
SECRET = {
    "id": "stray_ampersand",
    "position": [GLYPH[0], GLYPH[1]],
    "radius": 120.0,
    "prop": {"type": "unseen", "color": [1.0, 0.86, 0.42], "label": "an ampersand", "tags": ["small", "odd", "made", "bright"]},
    "lore": "An ampersand, standing in the grass where a blade of grass should be. It is warm, like something just set down. It means: and.",
    "reveal": {
        "type": "misprint",
        "glyph": "&",
        "notice_range_low": 150.0, "notice_range_high": 380.0,
        "notice_cooldown_low": 11.0, "notice_cooldown_high": 4.0, "notice_hold": 2.6,
        "near_radius": 110.0, "near_cooldown_factor": 0.4,
        "companion_radius": 150.0,
        "find_radius": 30.0, "glow_radius": 90.0,
        "lines": {
            "notice": "Your companion has stopped. It is looking hard at something in the grass, a way off.",
            "again": "It has stopped again, looking at the same place.",
            "near": "It is very close now. Your companion won't look at anything else.",
        },
        "reveal_line": "There. One of these is not grass. It is an ampersand, and now that you have seen it, it shines.",
    },
    "found_line": "The writer stopped here, on the word 'and'. You lift it out, and a blade of grass grows where it stood. The page is right now. The 'and' is yours.",
    "home_line": "Something has changed at home.",
    "qualities": ["quiet", "small", "made"],
    "keepsake": {
        "id": "kept_ampersand", "type": "kept_ampersand", "color": [1.0, 0.86, 0.42], "label": "an ampersand on a little stand",
        "line": "An 'and', kept on a stand. Your companion sits beside it now and then, as if waiting to hear the rest.",
        "temperament": {"curiosity": 0.85, "energy": 0.35, "clinginess": 0.5},
    },
}


def line(obj):
    return "\t\t" + json.dumps(obj, separators=(", ", ": "), ensure_ascii=False)


def block(items):
    return ",\n".join(line(x) for x in items)


paths = [{"from": list(a), "to": list(b), "color": PATH_COLOR} for a, b in PATH_SEGS]
region_objs = [{"id": r[0], "min": list(r[1]), "max": list(r[2]), "tint": [round(c, 2) for c in r[3]]} for r in REGIONS]
out = ["{"]
out.append('\t"_comment": %s,' % json.dumps(HEADER))
out.append('\t"world_id": "glyphfall",')
out.append('\t"intro": %s,' % json.dumps("Somebody wrote this valley down, and it kept. Nothing here needs doing. Walk, and read."))
out.append('\t"regions": [\n%s\n\t],' % block(region_objs))
out.append('\t"bounds": { "min": %s, "max": %s },' % (json.dumps(list(BOUNDS_MIN)), json.dumps(list(BOUNDS_MAX))))
out.append('\t"music": { "track": "res://assets/music/glyphfall.ogg", "volume_db": -22 },')  # tools/music/scores/glyphfall.score
out.append('\t"border": { "ring": true, "spacing": 96, "inset": 24, "jitter": 20, "rows": 2, "row_gap": 60 },')
out.append('\t"collision": { "tree_radius": 7, "great_tree_radius": 16, "pond_blocks": true, "body_radius": 6, "margin": 2 },')
out.append('\t"ground_color": [0.44, 0.50, 0.21],')
out.append('\t"path_meander": 0.0,')  # the paths are ruled lines of writing: they do not wander
out.append('\t"art": %s,' % json.dumps(ART, indent="\t").replace("\n", "\n\t"))
out.append('\t"atmosphere": %s,' % json.dumps(ATMOSPHERE, indent="\t", ensure_ascii=False).replace("\n", "\n\t"))
out.append('\t"player_spawn": %s,' % json.dumps(PLAYER_SPAWN))
out.append('\t"companion_spawn": %s,' % json.dumps(COMPANION_SPAWN))
out.append('\t"ponds": [\n%s\n\t],' % block(PONDS))
out.append('\t"paths": [\n%s\n\t],' % block(paths))
out.append('\t"landmarks": [\n%s\n\t],' % block(LANDMARKS))
out.append('\t"trees": [\n%s\n\t],' % block(TREES))
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
allowed = set("abcdefghijklmnopqrstuvwxyz ,.'-?")
for s in SENTENCES:
    assert set(s) <= allowed, "a sentence uses a character the atlas has no letter for: %r" % s
    assert len(s) <= 64, "a sentence is too long for its line: %r" % s
gx, gy = GLYPH
assert all(math.hypot(gx - t[0], gy - t[1]) > 120 for t in d["trees"]), "a tree stands over the wrong glyph"
assert all(_seg_dist(GLYPH, a, b) > 150 for a, b in PATH_SEGS), "the wrong glyph is on a path"
rmin, rmax = next((a, b) for rid, a, b, _ in REGIONS if rid == "the_unwritten")
assert rmin[0] < gx < rmax[0] and rmin[1] < gy < rmax[1]
kinds = {}
for t in d["trees"]:
    kinds[t[2]] = kinds.get(t[2], 0) + 1
print("props:", len(d["props"]), "| trees:", kinds, "| pals:", len(d["ambient_pals"]), "| glyph at", GLYPH)
for path in ["server/priv/world_seeds/glyphfall.json", "pokepals/tests/world_fixtures/glyphfall.json"]:
    open(path, "w").write(text)
print("wrote both files")
