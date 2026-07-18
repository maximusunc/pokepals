"""
Pixel-art tree generator -- same shading language as the character and daemon
generators, so trees read as part of the same hand-crafted world instead of the
engine's flat circles.

Shared conventions (see generator.py / animals.py):
  * shade ROLES, not colors -- '1' dark, '2' base, '3' highlight -- so recoloring
    a tree is just picking a different ramp;
  * light from the upper-left -- highlights land up/left, shadows fall down/right;
  * a 1px near-black auto-outline around the finished silhouette.

Where the character maps are hand-shaded pixel by pixel, a tree's canopy is too
big and too round for that to stay clean. So a tree is authored as a LAYOUT --
a few overlapping canopy "lobes" (the same overlapping foliage blobs the game
already draws in TreeView) plus a trunk box -- and the shading is DERIVED from
it, exactly like the outline and the daemons' back-views are derived elsewhere:

  1. rasterize the lobes + trunk into a silhouette,
  2. shade the canopy as a LIT BLOB (bright toward the light, a dark rim on the
     shadow side -- the pixel twin of ArtStyle.draw_blob),
  3. shade the trunk with a lit left edge,
  4. add the shared 1px outline.

Reshape a tree by editing its lobes; recolor it by swapping a ramp. No
randomness, no external art -- every tree is reproducible from the numbers below.
"""

from PIL import Image

# Near-black outline, a hair warmer than pure black so it sits in the bark family
# rather than reading as ink (matches the world's dark tones in data/art.json).
OUTLINE = (28, 24, 22, 255)

# Unit-ish direction the light comes FROM, pointing up-left. Kept in the same
# spirit as data/art.json's light.dir (up and a little left) so a baked tree is
# lit from the same side as everything drawn procedurally around it.
LIGHT = (-0.55, -0.83)

# ------------------------------------------------------------------- palettes
# (dark, base, light) for foliage and for bark. "summer" is tuned to the world
# palette in data/art.json (foliage_dark/mid/light + bark) so a baked tree drops
# straight into the existing scene; the others are honest ramp swaps.
RAMPS = {
    "summer": {
        "foliage": ((44, 82, 52), (71, 117, 77), (120, 168, 108)),
        "bark":    ((74, 54, 38), (105, 77, 54), (150, 116, 84)),
    },
    "pine": {
        "foliage": ((26, 58, 44), (40, 86, 60), (86, 140, 100)),
        "bark":    ((62, 46, 34), (94, 68, 48), (136, 104, 74)),
    },
    "autumn": {
        "foliage": ((150, 74, 26), (198, 120, 40), (238, 178, 84)),
        "bark":    ((74, 54, 38), (105, 77, 54), (150, 116, 84)),
    },
}

# --------------------------------------------------------------------- layouts
# size: (W, H). The client draws the sprite feet-at-bottom-centre, so the trunk
#   base sits flush with the bottom-centre of the canvas.
# lobes: (cx, cy, r) foliage discs, unioned into the canopy silhouette.
# trunk: (width, top) -- a bark column, horizontally centred, from row `top`
#   down to the base, widening by `flare` at the very bottom (a little root spread).
LAYOUTS = {
    "tree": {
        "size": (52, 60),
        "lobes": [
            (26, 30, 15),   # broad middle mass
            (14, 33, 12),   # left shoulder
            (38, 33, 12),   # right shoulder
            (25, 20, 17),   # upper crown
            (26, 12, 10),   # top bump
        ],
        "trunk": {"width": 8, "top": 34, "flare": 3},
    },
    "great_tree": {
        "size": (104, 122),
        "lobes": [
            (52, 60, 30),   # broad middle mass
            (26, 64, 24),   # left shoulder
            (78, 64, 24),   # right shoulder
            (50, 40, 34),   # upper crown
            (52, 22, 20),   # top bump
        ],
        "trunk": {"width": 18, "top": 66, "flare": 7},
    },
}


def _blank(w, h):
    return [[0] * w for _ in range(h)]


def _canopy_mask(layout):
    """Union the foliage lobes into a boolean silhouette grid."""
    w, h = layout["size"]
    mask = _blank(w, h)
    for (cx, cy, r) in layout["lobes"]:
        r2 = r * r
        for y in range(max(0, cy - r), min(h, cy + r + 1)):
            dy = y - cy
            for x in range(max(0, cx - r), min(w, cx + r + 1)):
                dx = x - cx
                if dx * dx + dy * dy <= r2:
                    mask[y][x] = 1
    return mask


def _trunk_mask(layout):
    """A centred bark column with a little root flare at the base."""
    w, h = layout["size"]
    t = layout["trunk"]
    mask = _blank(w, h)
    cx = w / 2.0
    for y in range(t["top"], h):
        # widen toward the very bottom for a rooted, planted look
        grow = t["flare"] * (y - t["top"]) / max(1, h - 1 - t["top"])
        half = (t["width"] + grow) / 2.0
        for x in range(int(round(cx - half)), int(round(cx + half))):
            if 0 <= x < w:
                mask[y][x] = 1
    return mask


def _solid(mask, x, y):
    return 0 <= y < len(mask) and 0 <= x < len(mask[0]) and mask[y][x]


def _shade_canopy(mask):
    """Derive a lit-blob shade grid (1 dark / 2 base / 3 light) from the mask.

    Interior volume is a radial ramp brightest toward a light-centre pulled up-left;
    then the true edges are re-asserted -- a crisp dark rim wherever the canopy faces
    away from the light (down/right), a bright rim where it faces into it (up/left) --
    so the silhouette stays readable at this size. This is the pixel-art reading of
    ArtStyle.draw_blob (base fill, lightened cap toward the light, bright rim cap)."""
    h, w = len(mask), len(mask[0])
    pts = [(x, y) for y in range(h) for x in range(w) if mask[y][x]]
    if not pts:
        return _blank(w, h)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    cx = sum(xs) / len(xs)
    cy = sum(ys) / len(ys)
    radius = 0.5 * max(max(xs) - min(xs), max(ys) - min(ys)) or 1.0
    # light-centre sits off the middle, toward the light
    lx = cx + LIGHT[0] * radius * 0.55
    ly = cy + LIGHT[1] * radius * 0.55

    shade = _blank(w, h)
    for (x, y) in pts:
        d = (((x - lx) ** 2 + (y - ly) ** 2) ** 0.5) / radius
        s = 3 if d < 0.52 else (2 if d < 0.92 else 1)
        # shadow rim: any leaf pixel whose down/right neighbour is open sky
        if not (_solid(mask, x + 1, y) and _solid(mask, x, y + 1)
                and _solid(mask, x + 1, y + 1)):
            s = 1
        # lit rim: a leaf pixel facing the light with open sky up/left
        elif not (_solid(mask, x - 1, y) and _solid(mask, x, y - 1)
                  and _solid(mask, x - 1, y - 1)):
            s = 3
        shade[y][x] = s
    return shade


def _shade_trunk(mask):
    """Bark shading: lit left edge, base middle, shadowed right edge (1/2/3)."""
    h, w = len(mask), len(mask[0])
    shade = _blank(w, h)
    for y in range(h):
        row = [x for x in range(w) if mask[y][x]]
        if not row:
            continue
        left, right = row[0], row[-1]
        span = max(1, right - left)
        for x in row:
            rel = (x - left) / span
            shade[y][x] = 3 if rel < 0.30 else (1 if rel > 0.72 else 2)
    return shade


def _add_outline(px, solid, w, h):
    """1px near-black outline hugging the silhouette (same idea as generator.add_outline,
    but size-agnostic and reading the union mask so it never bites into the trunk seam)."""
    edge = []
    for y in range(h):
        for x in range(w):
            if solid[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if _solid(solid, x + dx, y + dy):
                    edge.append((x, y))
                    break
    for (x, y) in edge:
        px[x, y] = OUTLINE


def _paint_part(shade, mask, ramp3):
    """One part (trunk or canopy) on its OWN full-size canvas, painted + outlined.

    Keeping each part on the full canvas (not cropped) is what lets the client draw
    them as two layers that line up perfectly: both are bottom-anchored at the same
    origin, so the only difference at draw time is the canopy's horizontal wind
    offset. Each part carries its own outline so its silhouette stays crisp when the
    canopy slides off the trunk in the wind."""
    h, w = len(mask), len(mask[0])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            if shade[y][x]:
                px[x, y] = ramp3[shade[y][x] - 1] + (255,)
    _add_outline(px, mask, w, h)
    return img


def make_tree_parts(kind="tree", variant="summer"):
    """The two independently-drawable layers of a tree: (trunk_img, canopy_img).

    The trunk is baked whole (including the stretch the canopy normally hides), so it
    stays complete when the canopy sways aside. `kind` picks a LAYOUT, `variant` a RAMP."""
    layout = LAYOUTS[kind]
    ramp = RAMPS[variant]
    trunk = _trunk_mask(layout)
    canopy = _canopy_mask(layout)
    trunk_img = _paint_part(_shade_trunk(trunk), trunk, ramp["bark"])
    canopy_img = _paint_part(_shade_canopy(canopy), canopy, ramp["foliage"])
    return trunk_img, canopy_img


def make_tree(kind="tree", variant="summer"):
    """The whole tree as one image (trunk with the canopy composited over it).

    This is the at-rest look for previews/tooling; the game draws the two parts from
    `make_tree_parts` separately so only the canopy catches the wind."""
    trunk_img, canopy_img = make_tree_parts(kind, variant)
    img = Image.new("RGBA", trunk_img.size, (0, 0, 0, 0))
    img.alpha_composite(trunk_img)
    img.alpha_composite(canopy_img)
    return img


def preview_grid(scale=4):
    """One row per kind, one column per variant -- eyeball the shape and the ramps."""
    kinds = list(LAYOUTS)
    variants = list(RAMPS)
    cellw = max(LAYOUTS[k]["size"][0] for k in kinds) + 8
    cellh = max(LAYOUTS[k]["size"][1] for k in kinds) + 8
    sheet = Image.new("RGBA",
                      (len(variants) * cellw + 8, len(kinds) * cellh + 8),
                      (58, 58, 70, 255))
    for r, kind in enumerate(kinds):
        for c, variant in enumerate(variants):
            spr = make_tree(kind, variant)
            # bottom-align in the cell, like the trees sit on the ground
            ox = 8 + c * cellw + (cellw - 8 - spr.width) // 2
            oy = 8 + r * cellh + (cellh - 8 - spr.height)
            sheet.paste(spr, (ox, oy), spr)
    return sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)


if __name__ == "__main__":
    preview_grid().save("trees.png")
    print("saved trees.png")
