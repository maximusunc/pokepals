"""
Pixel-art prop generator -- the world's small hand-placed things (lanterns, crystals,
mushrooms, benches, crates, stonework...) as hand-authored ASCII pixel maps, in the same
shading language as the character generator: '.' transparent, light from the upper-left,
a shared 1px near-black outline.

Two layers per prop, exactly like the trees split trunk/canopy:
  * BASE -- fixed-material pixels (wood, stone, stalks), painted from the prop's own little
    palette (letters), plus the shared outline. Baked in; the same for every instance.
  * TINT -- the one part whose COLOR is data on the prop (a lantern's globe, a mushroom's
    cap, a signpost's board, a crystal's gem). Authored GRAYSCALE with the digit roles
    '1'/'2'/'3' (dark/base/light) and drawn by the client with modulate = the instance's
    colour, so a value-v pixel becomes v*colour -- one sprite, every colour (same trick as
    the portal). A prop with no digit chars has no tint layer; a prop that's ALL tint (a
    crystal) has a base layer holding only the outline.

Animated bits -- a lantern's glow, a torch's flame, a shopkeeper's idle bob -- stay
procedural in WorldArt (like the trees' sway); this bakes only the still silhouette.

Every map is validated for a rectangular grid at import time, so a miscounted row fails
loudly ("crystal row 4: 13 cols") instead of baking corrupt art. No randomness.
"""

from PIL import Image

# Near-black outline, a hair warm so it sits with the world's dark tones (matches trees.py).
OUTLINE = (28, 24, 22, 255)

# Grayscale value for each tint role, tinted by the instance colour in the client.
TINT_VALUE = {"1": 0.44, "2": 0.70, "3": 1.0}


def _c(rgb):
    return (round(rgb[0] * 255), round(rgb[1] * 255), round(rgb[2] * 255), 255)


# Shared little material palettes (letters), so props read as one set. Lowercase = darker
# shade, uppercase = lighter shade of the same material.
WOOD = {"w": (0.34, 0.25, 0.17), "W": (0.48, 0.36, 0.24)}
DARKWOOD = {"k": (0.24, 0.18, 0.13), "K": (0.36, 0.27, 0.18)}
STONE = {"s": (0.44, 0.45, 0.42), "S": (0.60, 0.61, 0.57)}
METAL = {"m": (0.28, 0.26, 0.24), "M": (0.42, 0.40, 0.37)}
LEAF = {"g": (0.24, 0.40, 0.26), "G": (0.36, 0.54, 0.34)}
WHITE = {"o": (0.90, 0.90, 0.84), "O": (0.98, 0.98, 0.93)}
EMBERC = {"e": (0.30, 0.26, 0.24), "E": (0.20, 0.15, 0.13)}


def _merge(*ds):
    out = {}
    for d in ds:
        out.update(d)
    return out


# --------------------------------------------------------------------------- props
# Each: size is derived from the map. "map" rows are equal-length strings. "palette" gives
# the letter → rgb for the base layer; digits are the tint layer. "ground" is how many px of
# the map's bottom sit BELOW the prop's world point (so the sprite plants on the ground).
PROPS = {
    # ---- Glowing group -------------------------------------------------------------
    # A faceted gem: all tint (its colour is data), a lit upper-left facet (3) and a
    # shadowed lower-right (1), split by a bright edge down the middle.
    "crystal": {
        "ground": 1,
        "palette": {},
        "map": [
            "......3.......",
            ".....333......",
            "....33231.....",
            "...3323311....",
            "..332233111...",
            "..332233111...",
            ".33222331111..",
            ".33222331111..",
            ".13222331111..",
            ".11222331111..",
            "..1222331111..",
            "..1223331111..",
            "...123331 11..".replace(" ", "1"),
            "....1331111...",
            ".....13111....",
            "......131.....",
            ".......1......",
        ],
    },
    # A post topped with a glowing globe. Base = wood post + a little cap; tint = the globe.
    "lantern": {
        "ground": 2,
        "palette": _merge(WOOD, DARKWOOD),
        "map": [
            "..kKk..",
            ".13331.",
            "1333331",
            "1333331",
            "1333331",
            "1333331",
            ".13331.",
            "..kKk..",
            "..wWw..",
            "..wWw..",
            "..wWw..",
            "..wWw..",
            "..wWw..",
            ".kwWwk.",
        ],
    },
    # A wall bracket holding a torch stub (flame is procedural). Small; mostly the bracket.
    "torch": {
        "ground": 0,
        "palette": _merge(METAL, DARKWOOD),
        "map": [
            ".333.",
            ".333.",
            ".kKk.",
            ".kKk.",
            "mkKkm",
            ".mMm.",
            "..m..",
        ],
    },
    # A cracked stone ember-bowl (the glowing coals + hovering mote are procedural, drawn on
    # top by _draw_ember for the kindled/cold states — so the bowl itself carries no glow).
    "ember": {
        "ground": 1,
        "palette": _merge(STONE, EMBERC),
        "map": [
            ".e.e.e.",
            "eEEEEEe",
            "sEEEEEs",
            "sSEEEsS",
            ".sSSSs.",
            "..sss..",
        ],
    },
    # A brazier: a metal bowl on a footed stand (flame procedural). Base only.
    "brazier": {
        "ground": 2,
        "palette": _merge(METAL, EMBERC),
        "map": [
            "mMMMMMm",
            "mEEEEEm",
            ".mMMMm.",
            "..mMm..",
            "..mMm..",
            "..mMm..",
            ".mMMMm.",
            "mm...mm",
        ],
    },
}


# --------------------------------------------------------------------------- builders
# Geometric props (cairns, logs, basins…) are painted procedurally instead of hand-counted
# ASCII — far less error-prone for round shapes — but produce the SAME two-layer output. A
# Canvas offers disc/rect/line primitives onto a base image (fixed materials) and a tint
# image (grayscale colour-is-data), tracks the solid mask, and shares the 1px outline.
class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.tint = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.bpx, self.tpx = self.base.load(), self.tint.load()
        self.solid = [[0] * w for _ in range(h)]
        self.has_tint = False

    def _mark(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.solid[y][x] = 1
            return True
        return False

    def base_px(self, x, y, rgb):
        if self._mark(x, y):
            self.bpx[x, y] = _c(rgb)

    def tint_px(self, x, y, role):
        if self._mark(x, y):
            v = round(TINT_VALUE[role] * 255)
            self.tpx[x, y] = (v, v, v, 255)
            self.has_tint = True

    def disc(self, cx, cy, r, fn, top_only=False):
        for y in range(int(cy - r), int(cy + r) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                dx, dy = x - cx, y - cy
                if dx * dx + dy * dy <= r * r and (not top_only or dy <= 0):
                    fn(x, y, dx, dy)

    def rect(self, x0, y0, w, h, fn):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                fn(x, y, x - x0, y - y0)

    def outline(self):
        _add_outline(self.bpx, self.solid, self.w, self.h)


def _role(dx, dy, r):
    """A lit-blob shade role from an offset: bright up/left ('3'), dark down/right ('1')."""
    t = (-dx - dy) / max(1.0, r * 1.3)
    return "3" if t > 0.32 else ("1" if t < -0.34 else "2")


def _shade(rgb, dx, dy, r):
    """Same idea for a fixed material: lighten up/left, darken down/right."""
    t = (-dx - dy) / max(1.0, r * 1.3)
    if t > 0.32:
        return tuple(min(1.0, c + 0.12) for c in rgb)
    if t < -0.34:
        return tuple(max(0.0, c - 0.14) for c in rgb)
    return rgb


def _b_chime_stone(c):
    # a little cairn: three settling stones, all tint (the stone colour is data)
    for cx, cy, r in [(7.0, 13.0, 4.3), (6.0, 8.0, 3.4), (7.0, 3.6, 2.6)]:
        c.disc(cx, cy, r, lambda x, y, dx, dy, rr=r: c.tint_px(x, y, _role(dx, dy, rr)))
    c.outline()


def _b_wildflowers(c):
    # a small clustered patch: green stems (base) topped with tinted blossoms
    for sx, by, h in [(4, 12, 4), (8, 13, 5), (12, 11, 4)]:
        for yy in range(by - h, by + 1):
            c.base_px(sx, yy, LEAF["g"])
    for bx, byy, r in [(4.0, 7.0, 2.3), (8.0, 7.5, 2.6), (12.0, 6.5, 2.3)]:
        c.disc(bx, byy, r, lambda x, y, dx, dy, rr=r: c.tint_px(x, y, _role(dx, dy, rr)))
        c.tint_px(int(bx), int(byy), "3")  # bright pip at each centre
    c.outline()


def _b_mushrooms(c):
    # a tiny ring of spotted toadstools: white stalks (base), tinted caps with real white spots
    shrooms = [(4.0, 12, 2.6, [(-1, -1)]), (9.0, 12, 3.1, [(1, -1), (-1, 0)]), (13.0, 12, 2.2, [(0, -1)])]
    for mx, by, cr, spots in shrooms:
        for yy in range(by - 2, by + 1):
            c.base_px(int(mx), yy, WHITE["O"])
        spot_cells = {(int(mx) + sx, int(by - cr) + sy) for sx, sy in spots}

        def paint(x, y, dx, dy, cr=cr, cells=spot_cells):
            if (x, y) in cells:
                c.base_px(x, y, WHITE["O"])   # white spot: base, so the tint leaves it alone
            else:
                c.tint_px(x, y, _role(dx, dy, cr))
        c.disc(mx, by - cr, cr, paint, top_only=True)
    c.outline()


def _b_berry_bush(c):
    # a rounded shrub (base green, baked in — its colour barely varies) dotted with red berries
    for cx, cy, r in [(6.0, 10.0, 5.0), (12.0, 10.0, 5.0), (9.0, 7.0, 5.4)]:
        c.disc(cx, cy, r, lambda x, y, dx, dy, rr=r: c.base_px(x, y, _shade(LEAF["G"], dx, dy, rr)))
    for bx, by in [(4, 8), (11, 6), (14, 9), (8, 11), (9, 8)]:
        c.base_px(bx, by, (0.80, 0.22, 0.26))
        c.base_px(bx, by - 1, (0.90, 0.34, 0.36))
    c.outline()


def _b_log(c):
    # a fallen, mossy log on its side (base, baked): a wood drum with an end-face and a moss cap
    for x in range(2, 26):
        for y in range(6, 14):
            c.base_px(x, y, _shade(WOOD["w"], 0, y - 10, 5))
    for y in range(6, 14):  # lit top edge
        c.base_px(2 + (y - 6), 6, WOOD["W"])
    c.disc(4.0, 10.0, 4.2, lambda x, y, dx, dy: c.base_px(x, y, _shade(WOOD["W"], dx, dy, 4)))  # near end-face
    c.base_px(4, 10, WOOD["w"])
    c.base_px(4, 9, (0.30, 0.22, 0.15))  # the heart-rings dot
    for mx in range(9, 24, 3):           # moss tufts along the top
        c.base_px(mx, 5, LEAF["G"])
        c.base_px(mx + 1, 5, LEAF["g"])
    c.outline()


def _b_basin(c):
    # a small stone basin holding still water (base, baked): a stone rim ellipse + a blue pool
    for x in range(2, 20):
        dx = (x - 11) / 9.0
        for y in range(6, 16):
            dy = (y - 11) / 5.0
            if dx * dx + dy * dy <= 1.0:
                c.base_px(x, y, _shade(STONE["s"], x - 11, y - 11, 9))
    for x in range(4, 18):               # the water surface, inset
        dx = (x - 11) / 7.0
        for y in range(7, 13):
            dy = (y - 10) / 3.0
            if dx * dx + dy * dy <= 1.0:
                c.base_px(x, y, (0.40, 0.56, 0.64))
    c.base_px(7, 8, (0.85, 0.92, 0.95))  # a glint
    c.base_px(8, 8, (0.85, 0.92, 0.95))
    c.outline()


def _b_bench(c):
    # a simple weathered seat (base wood, baked): a seat plank, a backrest rail, two legs
    for x in range(2, 24):
        c.base_px(x, 8, WOOD["W"])
        c.base_px(x, 9, WOOD["w"])
    for x in range(2, 24):
        c.base_px(x, 4, WOOD["W"])       # backrest rail
    for lx in (4, 21):
        for y in range(10, 15):
            c.base_px(lx, y, DARKWOOD["k"])
        c.base_px(lx, 5, WOOD["w"])       # back uprights
        c.base_px(lx, 6, WOOD["w"])
        c.base_px(lx, 7, WOOD["w"])
    c.outline()


def _b_signpost(c):
    # a leaning post (base wood) with a board whose colour is data (tint)
    for y in range(6, 20):
        c.base_px(9, y, WOOD["w"])
        c.base_px(10, y, WOOD["W"])
    c.rect(3, 4, 14, 7, lambda x, y, lx, ly: c.tint_px(x, y, "3" if ly < 2 or lx < 2 else "2"))
    c.outline()


BUILDERS = {
    "chime_stone": _b_chime_stone,
    "wildflowers": _b_wildflowers,
    "mushrooms": _b_mushrooms,
    "berry_bush": _b_berry_bush,
    "log": _b_log,
    "basin": _b_basin,
    "bench": _b_bench,
    "signpost": _b_signpost,
}

# Canvas size per builder prop (w, h).
BUILDER_SIZE = {
    "chime_stone": (15, 18),
    "wildflowers": (17, 15),
    "mushrooms": (18, 14),
    "berry_bush": (18, 16),
    "log": (30, 17),
    "basin": (22, 18),
    "bench": (26, 16),
    "signpost": (20, 21),
}


def _grid(name):
    rows = PROPS[name]["map"]
    w = len(rows[0])
    for i, r in enumerate(rows):
        assert len(r) == w, "%s row %d: %d cols (want %d)" % (name, i, len(r), w)
    return rows, w, len(rows)


def _solid_at(solid, x, y):
    return 0 <= y < len(solid) and 0 <= x < len(solid[0]) and solid[y][x]


def _add_outline(px, solid, w, h):
    for y in range(h):
        for x in range(w):
            if solid[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if _solid_at(solid, x + dx, y + dy):
                    px[x, y] = OUTLINE
                    break


def make_prop_parts(name):
    """(base_img, tint_img_or_None) for a prop -- base carries fixed materials + outline,
    tint carries the grayscale colour-is-data part (or None if the prop has none). Works for
    both ASCII-map props (PROPS) and procedurally-built ones (BUILDERS)."""
    if name in BUILDERS:
        w, h = BUILDER_SIZE[name]
        c = Canvas(w, h)
        BUILDERS[name](c)
        return c.base, (c.tint if c.has_tint else None)
    spec = PROPS[name]
    pal = spec["palette"]
    rows, w, h = _grid(name)
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    tint = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bpx, tpx = base.load(), tint.load()
    solid = [[0] * w for _ in range(h)]
    has_tint = False
    for y in range(h):
        for x in range(w):
            ch = rows[y][x]
            if ch == ".":
                continue
            solid[y][x] = 1
            if ch in TINT_VALUE:
                v = round(TINT_VALUE[ch] * 255)
                tpx[x, y] = (v, v, v, 255)
                has_tint = True
            elif ch in pal:
                bpx[x, y] = _c(pal[ch])
            else:
                raise KeyError("%s: char %r not a tint role or in palette" % (name, ch))
    _add_outline(bpx, solid, w, h)  # outline hugs the whole silhouette, on the base layer
    return base, (tint if has_tint else None)


def all_names():
    """Every prop name, ASCII-map and procedural, in a stable order."""
    return list(PROPS) + list(BUILDERS)


def preview_grid(scale=6):
    """Every prop composited (base + a demo-tinted tint) on a green ground, for eyeballing."""
    demo = {"crystal": (0.62, 0.80, 0.82), "lantern": (0.95, 0.80, 0.45),
            "torch": (1.0, 0.66, 0.30), "ember": (0.95, 0.62, 0.30),
            "brazier": (0.75, 0.55, 0.35), "chime_stone": (0.66, 0.70, 0.78),
            "wildflowers": (0.74, 0.55, 0.85), "mushrooms": (0.86, 0.34, 0.32),
            "signpost": (0.44, 0.56, 0.74)}
    names = all_names()
    cell = 40
    cols = min(6, len(names))
    import_rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell + 8, import_rows * cell + 8), (110, 148, 92, 255))
    for i, name in enumerate(names):
        base, tint = make_prop_parts(name)
        comp = base.copy()
        if tint is not None:
            t = demo.get(name, (0.8, 0.8, 0.85))
            tinted = Image.new("RGBA", tint.size, (0, 0, 0, 0))
            tp, sp = tinted.load(), tint.load()
            for y in range(tint.height):
                for x in range(tint.width):
                    r, g, b, a = sp[x, y]
                    if a:
                        tp[x, y] = (r * _c(t)[0] // 255, g * _c(t)[1] // 255, b * _c(t)[2] // 255, a)
            comp.alpha_composite(tinted)
        cx = 4 + (i % cols) * cell + (cell - 8 - comp.width) // 2
        cy = 4 + (i // cols) * cell + (cell - 8 - comp.height)
        sheet.alpha_composite(comp, (cx, cy))
    return sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)


if __name__ == "__main__":
    preview_grid().save("props.png")
    print("saved props.png")
