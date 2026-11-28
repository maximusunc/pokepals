"""
Pixel-art ground -- the floor the whole world stands on, in the same hand-crafted
language as the trees, water and characters.

The ground used to be a soft gradient with one blurry noise texture stretched over the
whole map, so crisp pixel sprites stood on a smooth vector floor -- the main reason the
world read as flat. This module makes the floor pixel art too, in two parts:

1. TERRAIN TILES -- one seamless 128x128 tile per kind of ground (grass, lush clover,
   meadow, bare dirt, sand). Like water.py they are SURFACES: the client's ground shader
   (assets/ground.gdshader) repeats them across the world at one texel per world unit,
   picks which kind shows where from a noise field, and dithers the borders between
   kinds into pixel-crisp ragged edges. A tile stores SHADE ROLES, not colours:

     R = shade index 0..3 (dark .. highlight), stored as 0/85/170/255
     G = 255 where an ACCENT sits (a meadow's tiny flowers), coloured by the shader

   so a world recolours its ground by naming new ramps in its art block -- the textures
   never change. A tile holds only fine grain (blades, clover, pebbles) on a flat base;
   the shader adds the broad light/dark clumping from world-space noise, so nothing
   repeats in a visible grid.

2. DETAILS -- small sprites scattered on top of the terrain in natural CLUSTERS (grass
   tufts, pebbles, clover, fallen leaves, mushrooms, twigs, daisies, stepping stones) and
   along the shores (reeds, lily pads). Baked into one atlas with a JSON index of where
   each sprite sits. Flowers are grayscale so the client tints each with the world's own
   flower colours.

Seeded, deterministic: every tile and sprite is reproducible from the numbers below.
"""

import random

from PIL import Image

TILE = 128
KINDS = ["grass", "lush", "meadow", "dirt", "sand"]
OUTLINE = (28, 24, 22, 255)


def _stamp(grid, glyph, x0, y0, accent=None):
    """Paint a glyph [(dx, dy, shade), ...] into the grid, wrapping at the tile edge
    so a glyph that crosses the seam continues on the other side (keeps it seamless)."""
    for dx, dy, s in glyph:
        x, y = (x0 + dx) % TILE, (y0 + dy) % TILE
        grid[y][x] = s
        if accent is not None:
            accent[y][x] = 1


# glyphs: (dx, dy, shade). Light comes from the upper-left, so lit pixels sit up/left.
TUFT = [(0, 0, 0), (-1, 1, 0), (1, 1, 0)]                    # a dark little "^" of blades
BLADE = [(0, 0, 3), (0, 1, 2)]                                # a sunlit blade tip
CLOVER = [(0, -1, 2), (-1, 0, 2), (1, 0, 2), (0, 0, 3), (0, 1, 0), (1, 1, 0)]
FLOWER_DOT = [(0, 0, 3)]
FLOWER_PLUS = [(0, -1, 3), (-1, 0, 3), (1, 0, 3), (0, 0, 3), (0, 1, 0)]
PEBBLE = [(0, 0, 3), (1, 0, 3), (0, 1, 0), (1, 1, 0)]
PIT = [(0, 0, 0)]
SPECK_LIGHT = [(0, 0, 3)]
SPECK_DARK = [(0, 0, 1)]


def _flat(shade):
    return [[shade] * TILE for _ in range(TILE)]


def make_terrain(kind):
    """(shade_grid, accent_grid) for one terrain kind, each TILE x TILE.

    A tile carries only the FINE grain -- blades, tufts, clover, pebbles, specks -- on a flat
    base shade. The broad light/dark clumping is NOT baked in (it would repeat in a visible
    grid every 128 units); the shader paints it from world-space noise instead."""
    rng = random.Random("ground-" + kind)
    acc = [[0] * TILE for _ in range(TILE)]
    if kind in ("grass", "meadow"):
        g = _flat(1)
        for _ in range(420):
            _stamp(g, TUFT, rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(260):
            _stamp(g, BLADE, rng.randrange(TILE), rng.randrange(TILE))
        if kind == "meadow":
            for _ in range(70):
                glyph = FLOWER_PLUS if rng.random() < 0.4 else FLOWER_DOT
                _stamp(g, glyph, rng.randrange(TILE), rng.randrange(TILE), acc)
            # the dark stem pixel of a plus flower is not an accent
            for y in range(TILE):
                for x in range(TILE):
                    if acc[y][x] and g[y][x] == 0:
                        acc[y][x] = 0
    elif kind == "lush":
        g = _flat(1)
        for _ in range(170):
            _stamp(g, CLOVER, rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(300):
            _stamp(g, TUFT, rng.randrange(TILE), rng.randrange(TILE))
    elif kind == "dirt":
        g = _flat(1)
        for _ in range(90):
            _stamp(g, PEBBLE, rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(260):
            _stamp(g, PIT, rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(200):
            _stamp(g, SPECK_LIGHT, rng.randrange(TILE), rng.randrange(TILE))
    elif kind == "sand":
        g = _flat(2)
        for _ in range(380):
            _stamp(g, SPECK_DARK, rng.randrange(TILE), rng.randrange(TILE))
        for _ in range(160):
            _stamp(g, SPECK_LIGHT, rng.randrange(TILE), rng.randrange(TILE))
    else:
        raise KeyError(kind)
    return g, acc


def make_terrain_atlas():
    """All kinds side by side: (len(KINDS)*TILE) x TILE, R = shade role, G = accent."""
    img = Image.new("RGBA", (TILE * len(KINDS), TILE), (0, 0, 0, 255))
    px = img.load()
    for k, kind in enumerate(KINDS):
        g, acc = make_terrain(kind)
        for y in range(TILE):
            for x in range(TILE):
                px[k * TILE + x, y] = (g[y][x] * 85, 255 if acc[y][x] else 0, 0, 255)
    return img


# ------------------------------------------------------------------- details
# Each detail is an ASCII map + a ramp (dark, base, light). '1' dark, '2' base,
# '3' light, '.' clear. Outlined like every other sprite unless it's tiny ground
# litter (outline=False), which would look heavy with a black ring.
GREEN = ((58, 96, 58), (100, 146, 84), (150, 190, 110))
GREEN_LUSH = ((46, 84, 52), (78, 124, 72), (124, 168, 96))
STONE = ((88, 86, 84), (128, 124, 118), (176, 170, 160))
BARK = ((74, 54, 38), (105, 77, 54), (150, 116, 84))
CAP_RED = ((140, 42, 36), (196, 70, 52), (236, 140, 112))
LEAF_GOLD = ((150, 92, 30), (204, 142, 52), (238, 196, 104))
LEAF_RUST = ((128, 52, 30), (180, 86, 44), (226, 140, 86))
WHITE = ((168, 168, 160), (220, 220, 210), (255, 255, 248))
GRAY = ((110, 110, 110), (170, 170, 170), (230, 230, 230))   # tinted at runtime
REED = ((70, 82, 44), (110, 124, 62), (160, 168, 96))
CATTAIL = ((70, 46, 30), (104, 70, 44), (146, 104, 70))
LILY = ((40, 90, 64), (60, 124, 84), (104, 164, 116))
PINK = ((196, 110, 140), (236, 160, 186), (255, 216, 228))

DETAILS = {
    # grass tufts -- the swaying ones; three shapes so a meadow doesn't stamp one tuft
    "tuft_a": (GREEN, False, [
        "..3...",
        ".32.3.",
        ".2.32.",
        "12.21.",
        "1211..",
    ]),
    "tuft_b": (GREEN, False, [
        ".3..3..",
        ".2.32..",
        "32.2.3.",
        "2.12.2.",
        "21121..",
    ]),
    "tuft_c": (GREEN_LUSH, False, [
        "...3.",
        ".3.2.",
        ".2.23",
        "122.2",
        ".121.",
    ]),
    "pebbles": (STONE, False, [
        ".33..3",
        ".21.31",
        "......",
        "..32..",
        "..21..",
    ]),
    "stone": (STONE, True, [
        ".3332..",
        "332222.",
        "3222221",
        ".22111.",
    ]),
    "stone_b": (STONE, True, [
        "..332.",
        ".32222",
        "322221",
        ".2111.",
    ]),
    "twig": (BARK, False, [
        "3......",
        ".23..3.",
        "..2232.",
        "....21.",
    ]),
    "leaf_gold": (LEAF_GOLD, False, [
        ".33.",
        "3221",
        ".21.",
    ]),
    "leaf_rust": (LEAF_RUST, False, [
        "..3.",
        ".321",
        "321.",
    ]),
    "mushroom": (CAP_RED, True, [
        ".333.",
        "32322",
        ".1211",
        "..W..",
    ]),
    "clover": (GREEN_LUSH, False, [
        ".3.3.",
        "32323",
        ".212.",
        "..1..",
    ]),
    "daisies": (WHITE, False, [
        ".3....",
        "3Y3..3",
        ".3..3Y",
        "..g..3",
        "..g..g",
    ]),
    # a grayscale flower the client tints with the spec's own flower colours
    "flower": (GRAY, True, [
        ".3.",
        "3Y3",
        ".3.",
        ".g.",
        "gg.",
    ]),
    "reed_a": (REED, True, [
        ".c.",
        ".c.",
        ".c.",
        ".3.",
        "32.",
        "2.3",
        "2.2",
        "2.2",
        "212",
    ]),
    "reed_b": (REED, True, [
        "3...",
        "2..3",
        "2.32",
        "232.",
        "22..",
        "21..",
    ]),
    "lily": (LILY, True, [
        ".3333.",
        "322.22",
        "322221",
        ".1111.",
    ]),
    "lily_bloom": (LILY, True, [
        "..pp..",
        ".3pp3.",
        "322.22",
        "322221",
        ".1111.",
    ]),
}
# --- Nocthollow's night litter: dark moss and stone with luminous tips (the client haloes them) ---
GLOW_TEAL = ((20, 40, 70), (34, 70, 100), (130, 245, 225))
GLOW_PINK = ((40, 26, 70), (72, 50, 112), (255, 156, 232))
GLOW_CAP = ((40, 116, 140), (92, 218, 220), (204, 255, 250))
SHARD = ((60, 90, 160), (132, 192, 255), (232, 250, 255))
STARMOSS = ((20, 48, 52), (38, 86, 72), (206, 255, 150))
NIGHT_STONE = ((30, 30, 56), (54, 54, 88), (150, 232, 255))
NIGHT_REED = ((28, 56, 78), (48, 88, 110), (88, 138, 160))
NIGHT_LILY = ((18, 48, 70), (30, 80, 100), (62, 132, 152))

DETAILS.update({
    "glowtuft_a": (GLOW_TEAL, False, [
        "..3...",
        ".32.3.",
        ".2.32.",
        "12.21.",
        "1211..",
    ]),
    "glowtuft_b": (GLOW_PINK, False, [
        ".3..3..",
        ".2.32..",
        "32.2.3.",
        "2.12.2.",
        "21121..",
    ]),
    "glowcap": (GLOW_CAP, True, [
        ".333.",
        "33232",
        ".1211",
        "..w..",
    ]),
    "shard": (SHARD, True, [
        ".3.",
        "332",
        "332",
        "321",
        ".1.",
    ]),
    "starmoss": (STARMOSS, False, [
        ".3..2.3",
        "2232322",
        ".12121.",
    ]),
    "glowpebble": (NIGHT_STONE, False, [
        ".23..3",
        ".21.21",
        "......",
        "..32..",
        "..21..",
    ]),
    "glowreed": (NIGHT_REED, True, [
        ".b.",
        "bBb",
        ".b.",
        ".3.",
        "32.",
        "2.3",
        "2.2",
        "212",
    ]),
    "lumen_lily": (NIGHT_LILY, True, [
        "..qq..",
        ".3qQ3.",
        "322.22",
        "322221",
        ".1111.",
    ]),
})

# Extra fixed colours some maps use: Y flower centre, g stem, W mushroom stalk,
# c cattail head, p water-lily petal; w a glowcap's pale stalk, b/B a glowing reed's
# bulb (and its bright heart), q/Q a lumen lily's glowing petals.
EXTRA = {"Y": (246, 214, 84), "g": (82, 128, 74), "W": (226, 214, 190),
         "c": CATTAIL[1], "p": PINK[1], "w": (150, 190, 210),
         "b": (120, 236, 220), "B": (220, 255, 250), "q": (236, 120, 210), "Q": (255, 210, 244)}


def make_detail(name):
    ramp, outlined, rows = DETAILS[name]
    h, w = len(rows), max(len(r) for r in rows)
    pad = 1 if outlined else 0
    img = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    px = img.load()
    solid = set()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == '.':
                continue
            col = EXTRA[ch] if ch in EXTRA else ramp[int(ch) - 1]
            px[x + pad, y + pad] = tuple(col) + (255,)
            solid.add((x + pad, y + pad))
    if outlined:
        for (x, y) in list(solid):
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + dx, y + dy)
                if n not in solid and 0 <= n[0] < img.width and 0 <= n[1] < img.height:
                    px[n] = OUTLINE
    return img


def make_detail_atlas():
    """Pack every detail into one strip. Returns (image, index) where index maps a
    name to [x, y, w, h] in the atlas -- written beside the PNG as JSON."""
    imgs = {n: make_detail(n) for n in DETAILS}
    width = sum(i.width + 1 for i in imgs.values())
    height = max(i.height for i in imgs.values())
    atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    index, x = {}, 0
    for n, im in imgs.items():
        atlas.paste(im, (x, 0), im)
        index[n] = [x, 0, im.width, im.height]
        x += im.width + 1
    return atlas, index


# ------------------------------------------------------------------ preview
# Default ramps (darkest .. lightest), mirroring data/art.json's "ground" entity, so a
# preview shows what the game will draw.
PREVIEW_RAMPS = {
    "grass":  [(72, 110, 66), (88, 130, 76), (100, 142, 82), (136, 174, 100)],
    "lush":   [(54, 92, 58), (66, 110, 66), (78, 124, 72), (112, 156, 90)],
    "meadow": [(76, 114, 66), (94, 136, 78), (106, 148, 86), (142, 180, 104)],
    "dirt":   [(108, 84, 60), (130, 102, 72), (144, 114, 82), (180, 152, 110)],
    "sand":   [(140, 124, 92), (166, 148, 110), (182, 164, 122), (206, 190, 148)],
}


def preview(path, scale=3):
    atlas = make_terrain_atlas()
    apx = atlas.load()
    det, index = make_detail_atlas()
    w = TILE * len(KINDS)
    img = Image.new("RGBA", (w, TILE + det.height + 8), (40, 40, 48, 255))
    px = img.load()
    for k, kind in enumerate(KINDS):
        ramp = PREVIEW_RAMPS[kind]
        for y in range(TILE):
            for x in range(TILE):
                r, g, _, _ = apx[k * TILE + x, y]
                px[k * TILE + x, y] = ((236, 120, 160) if g else ramp[r // 85]) + (255,)
    img.paste(det, (4, TILE + 4), det)
    img.resize((img.width * scale, img.height * scale), Image.NEAREST).save(path)


if __name__ == "__main__":
    preview("ground.png")
    print("saved ground.png")
