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
    tint carries the grayscale colour-is-data part (or None if the prop has no tint chars)."""
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


def preview_grid(scale=6):
    """Every prop composited (base + a demo-tinted tint) on a green ground, for eyeballing."""
    demo = {"crystal": (0.62, 0.80, 0.82), "lantern": (0.95, 0.80, 0.45),
            "torch": (1.0, 0.66, 0.30), "ember": (0.95, 0.62, 0.30),
            "brazier": (0.75, 0.55, 0.35)}
    names = list(PROPS)
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
