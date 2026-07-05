"""
8-direction daemon facings, built by DERIVING views from each species'
front map (so all species get 8 directions for free), plus optional
hand-drawn profiles for hero species (fox so far).

Directions: down, down_right, right, up_right, up, up_left, left, down_left
- up        : front map with face erased, inner ears filled, tail overlay
- diagonals : front/back map with the head band shifted 1px toward facing
- right     : hand-drawn profile if available, else front with a 2px
              head "glance" shift (placeholder until profiled)
- left side : mirrors of the right-side family
"""

import random
from PIL import Image
from generator import paint, add_outline, W, H
import animals

BLANK = "." * 32

# ------------------------------------------------ hand-drawn fox profile
FOX_SIDE = [
    BLANK, BLANK, BLANK, BLANK, BLANK,
    "....................2...2.......",
    "...................22..22.......",
    "...................21..12.......",
    "..................22222222......",
    ".................2333333332.....",
    ".................2333333332.....",
    ".................233333E332.....",
    ".................2333333332333..",
    "...222...........2333333332331..",
    "..22222..........2233333332.....",
    ".22222222222222222233333333.....",
    ".33222.233333333333333333.......",
    ".3332..233333333333333332.......",
    ".333...233333333333333332.......",
    ".......233333333333333332.......",
    "........2222222222222222........",
    ".........1122......1122.........",
    ".........1122......1122.........",
    ".........1122......1122.........",
    ".........1122......1122.........",
    ".........1122......1122.........",
    BLANK, BLANK, BLANK, BLANK, BLANK, BLANK,
]

SIDE_MAPS = {"fox": FOX_SIDE}

for name, grid in SIDE_MAPS.items():
    assert len(grid) == H, f"{name}_side: {len(grid)} rows"
    for i, row in enumerate(grid):
        assert len(row) == W, f"{name}_side r{i}: {len(row)} cols"

# -------------------------------------- per-species derivation config
# head_rows: rows shifted for diagonal "turn"; nose_rows / inner_ear_rows:
# rows cleaned when deriving the back view; tail_overlay: extra pixels
# visible from behind, as (row, col_start, chars).
CONFIG = {
    "cat":    dict(head_rows=range(6, 16), nose_rows=[12],
                   inner_ear_rows=[7], tail_overlay=[]),
    "fox":    dict(head_rows=range(4, 16), nose_rows=[14],
                   inner_ear_rows=[6, 7], tail_overlay=[]),
    "rabbit": dict(head_rows=range(3, 16), nose_rows=[13],
                   inner_ear_rows=range(4, 10),
                   tail_overlay=[(20, 14, "33"), (21, 14, "33")]),
    "bird":   dict(head_rows=range(11, 17), nose_rows=[14],
                   inner_ear_rows=[], tail_overlay=[]),
    "wolf":   dict(head_rows=range(3, 16), nose_rows=[13],
                   inner_ear_rows=[5, 6], tail_overlay=[]),
}


def _shift_right(row, n=1):
    return "." * n + row[:-n] if n else row


def derive_back(species):
    grid, _ = animals.SPECIES[species]
    cfg = CONFIG[species]
    out = list(grid)
    for y in range(H):
        row = out[y]
        row = row.replace('E', '3')                       # erase eyes
        if y in cfg["nose_rows"]:
            row = row.replace('1', '3')                   # erase nose
        if y in cfg["inner_ear_rows"]:
            row = row.replace('1', '2')                   # fill inner ear
        out[y] = row
    for (y, x0, chars) in cfg["tail_overlay"]:
        row = list(out[y])
        for i, ch in enumerate(chars):
            row[x0 + i] = ch
        out[y] = ''.join(row)
    return out


def derive_view(species, direction):
    """Return the map for one of the 5 base views (right-handed set)."""
    front, _ = animals.SPECIES[species]
    cfg = CONFIG[species]
    if direction == "down":
        return front
    if direction == "up":
        return derive_back(species)
    if direction == "down_right":
        return [_shift_right(r, 1) if y in cfg["head_rows"] else r
                for y, r in enumerate(front)]
    if direction == "up_right":
        back = derive_back(species)
        return [_shift_right(r, 1) if y in cfg["head_rows"] else r
                for y, r in enumerate(back)]
    if direction == "right":
        if species in SIDE_MAPS:
            return SIDE_MAPS[species]
        return [_shift_right(r, 2) if y in cfg["head_rows"] else r
                for y, r in enumerate(front)]          # glance placeholder
    raise ValueError(direction)


MIRROR_OF = {"left": "right", "down_left": "down_right",
             "up_left": "up_right"}


def make_daemon_facing(species, direction, variant=None, rng=random):
    _, ramps = animals.SPECIES[species]
    ramp = ramps[variant] if variant is not None else rng.choice(ramps)
    flip = direction in MIRROR_OF
    base_dir = MIRROR_OF.get(direction, direction)
    grid = derive_view(species, base_dir)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    paint(img, grid, ramp)
    add_outline(img)
    if flip:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    return img


DIRS_8 = ["down", "down_right", "right", "up_right",
          "up", "up_left", "left", "down_left"]

# compass layout: grid positions for a 3x3 with center empty
COMPASS_POS = {"up_left": (0, 0), "up": (0, 1), "up_right": (0, 2),
               "left": (1, 0), "right": (1, 2),
               "down_left": (2, 0), "down": (2, 1), "down_right": (2, 2)}


def compass(species, variant=0, scale=6):
    pad = 6
    cell = W + pad
    sheet = Image.new("RGBA", (3 * cell + pad, 3 * cell + pad),
                      (58, 58, 70, 255))
    for d, (r, c) in COMPASS_POS.items():
        spr = make_daemon_facing(species, d, variant)
        sheet.paste(spr, (pad + c * cell, pad + r * cell), spr)
    return sheet.resize((sheet.width * scale, sheet.height * scale),
                        Image.NEAREST)


def all_species_sheet(scale=5):
    pad = 6
    cell = W + pad
    rows = len(animals.SPECIES)
    sheet = Image.new("RGBA", (8 * cell + pad, rows * cell + pad),
                      (58, 58, 70, 255))
    for r, name in enumerate(animals.SPECIES):
        for c, d in enumerate(DIRS_8):
            spr = make_daemon_facing(name, d, 0)
            sheet.paste(spr, (pad + c * cell, pad + r * cell), spr)
    return sheet.resize((sheet.width * scale, sheet.height * scale),
                        Image.NEAREST)


if __name__ == "__main__":
    compass("fox").save("fox_compass.png")
    all_species_sheet().save("daemon_directions.png")
    print("saved fox_compass.png and daemon_directions.png")
