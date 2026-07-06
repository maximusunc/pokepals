"""
Directional walk animations -- 4 directions x 4 frames, layer-consistent.

Directions: down (front), up (back, derived from front), right (hand-drawn
profile), left (mirror of right).

Walk cycle = [idle, stepA, idle, stepB]. stepB legs are derived from stepA
(mirror for front/back, near/far shade swap for side), so the two contact
poses can never drift apart. A 1px body bob is applied on contact frames.

Daemons get a 4-frame hop (vertical offsets) + horizontal flip for facing.
"""

import random

from PIL import Image

from player_generator import (W, H, BODY, SHIRT, PANTS, SHOES, HANDS, HAIR_STYLES,
                       ACCESSORIES, SKIN_RAMPS, HAIR_RAMPS, CLOTH_RAMPS,
                       paint, add_outline)
import daemon_generator

BLANK = "." * 32

# ------------------------------------------------- front/back walk leg poses
# step A = viewer-left leg raised, right leg planted. step B = mirror.
PANTS_STEP_A = [BLANK] * 23 + [
    "...........2222222222...........",
    "...........2222112222...........",
    "...........2222..2222...........",
    "...........2222..2222...........",
    ".................2222...........",
    ".................1111...........",
] + [BLANK] * 3

SHOES_STEP_A = [BLANK] * 27 + [
    "...........2222.................",
    "...........1111.222222..........",
    ".................222222.........",
    ".................222222.........",
    ".................111111.........",
]

# --------------------------------------------------------- side view (right)
BODY_SIDE = [
    BLANK, BLANK,
    "............22222222............",
    "..........233333333332..........",
    "..........233333333332..........",
    "..........233333333332..........",
    "..........233333333332..........",
    "..........233333333332..........",
    "..........23333333E3323.........",
    "..........23333333E3323.........",
    "..........233333333332..........",
    "..........233333333132..........",
    "...........2222222222...........",
    "............22111122............",
    "..............1111..............",
] + [BLANK] * 17

SHIRT_SIDE = [BLANK] * 14 + [
    "...........2322222222...........",
    "..........232222222221..........",
    "..........222122221222..........",
    "..........222122221222..........",
    "..........222122221222..........",
    "..........222122221222..........",
    "..........222122221222..........",
    "..........222122221222..........",
    "..........111111111111..........",
] + [BLANK] * 9

HANDS_SIDE = [BLANK] * 22 + [
    "..............2222..............",
    "..............1221..............",
] + [BLANK] * 8

PANTS_SIDE_STAND = [BLANK] * 23 + [
    "...........2222222222...........",
    "............11122222............",
    "............11122222............",
    "............11122222............",
    "............11122222............",
    "............11122222............",
] + [BLANK] * 3

SHOES_SIDE_STAND = [BLANK] * 29 + [
    "...........1111222222...........",
    "...........11112222222..........",
    "...........11111111111..........",
]

PANTS_SIDE_STRIDE = [BLANK] * 23 + [
    "...........2222222222...........",
    "...........1111122222...........",
    "...........11111.22222..........",
    "..........11111...22222.........",
    "..........11111....2222.........",
    ".........11111.....2222.........",
] + [BLANK] * 3

SHOES_SIDE_STRIDE = [BLANK] * 29 + [
    ".........111111....2222.........",
    ".........1111111...22222........",
    ".........1111111...11111........",
]

HAIR_SIDE = {
    "short": [
        BLANK,
        "............22222222............",
        "..........2233333332............",
        ".........223333333322...........",
        ".........22222222...............",
        ".........222....................",
        ".........222....................",
        ".........222....................",
        ".........222....................",
        ".........222....................",
    ] + [BLANK] * 22,
    "long": [
        BLANK,
        "............22222222............",
        "..........2233333332............",
        ".........223333333322...........",
        ".........22222222...............",
        "........2222....................",
        "........2222....................",
        "........2222....................",
        "........2222....................",
        "........2222....................",
        "........2211....................",
        "........2211....................",
        "........2211....................",
        "........2211....................",
        "........2111....................",
        ".........11.....................",
    ] + [BLANK] * 16,
    "spiky": [
        "...........2..2..2..............",
        "..........2222222222............",
        "..........2233333332............",
        ".........223333333322...........",
        ".........22222222...............",
        ".........222....................",
        ".........222....................",
        ".........222....................",
    ] + [BLANK] * 24,
}

ACC_SIDE = {
    "none": None,
    "headband": [BLANK] * 6 + [
        ".........2333333333332..........",
        ".........2222222222222..........",
    ] + [BLANK] * 24,
    "glasses": [BLANK] * 7 + [
        ".................1111...........",
        "............111111.11...........",
        ".................1111...........",
    ] + [BLANK] * 22,
}

# validate every hand-drawn side/step map
_ALL = {"PANTS_STEP_A": PANTS_STEP_A, "SHOES_STEP_A": SHOES_STEP_A,
        "BODY_SIDE": BODY_SIDE, "SHIRT_SIDE": SHIRT_SIDE,
        "HANDS_SIDE": HANDS_SIDE,
        "PANTS_SIDE_STAND": PANTS_SIDE_STAND,
        "SHOES_SIDE_STAND": SHOES_SIDE_STAND,
        "PANTS_SIDE_STRIDE": PANTS_SIDE_STRIDE,
        "SHOES_SIDE_STRIDE": SHOES_SIDE_STRIDE,
        **{f"hair_side_{k}": v for k, v in HAIR_SIDE.items()},
        **{f"acc_side_{k}": v for k, v in ACC_SIDE.items() if v}}
for name, grid in _ALL.items():
    assert len(grid) == H, f"{name}: {len(grid)} rows"
    for i, row in enumerate(grid):
        assert len(row) == W, f"{name} r{i}: {len(row)} cols"

# --------------------------------------------------------- derived maps
def mirror(grid):
    return [row[::-1] for row in grid]

def swap_near_far(grid):
    """Swap '1'/'2' so the other leg is forward in the side stride."""
    tr = str.maketrans("12", "21")
    out = [row.translate(tr) for row in grid]
    out[31] = grid[31]  # soles stay dark
    return out

PANTS_STEP_B = mirror(PANTS_STEP_A)
SHOES_STEP_B = mirror(SHOES_STEP_A)
PANTS_SIDE_STRIDE2 = swap_near_far(PANTS_SIDE_STRIDE)
SHOES_SIDE_STRIDE2 = swap_near_far(SHOES_SIDE_STRIDE)

# back view: erase face, fill hair over whole head, close the collar
BODY_UP = [r.replace('E', '3') for r in BODY]
BODY_UP[11] = BODY_UP[11].replace('11', '33')

SHIRT_UP = list(SHIRT)
SHIRT_UP[14] = SHIRT_UP[14].replace('222......222', '222222222222')

def hair_up(style):
    grid = []
    front = HAIR_STYLES[style]
    for y in range(H):
        row = list(front[y])
        if 2 <= y <= 12:
            for x in range(W):
                if BODY[y][x] != '.':
                    row[x] = '3' if y <= 3 else '2'
        grid.append(''.join(row))
    return grid

HAIR_UP = {k: hair_up(k) for k in HAIR_STYLES}

# --------------------------------------------------------- frame assembly
def _compose(upper_layers, leg_layers, bob=0):
    """upper_layers/leg_layers: list of (map, ramp). Bob shifts upper down."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for grid, ramp in leg_layers:
        paint(img, grid, ramp)
    upper = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for grid, ramp in upper_layers:
        paint(upper, grid, ramp)
    img.paste(upper, (0, bob), upper)
    add_outline(img)
    return img


def character_frames(direction, hair=None, accessory=None, skin=None,
                     hair_c=None, shirt_c=None, pants_c=None, shoes_c=None,
                     acc_c=None, rng=random):
    """Return 4 walk frames for one direction, with a consistent outfit."""
    hair = hair or rng.choice(list(HAIR_STYLES))
    accessory = accessory or rng.choice(list(ACCESSORIES))
    skin = skin or rng.choice(SKIN_RAMPS)
    hair_c = hair_c or rng.choice(HAIR_RAMPS)
    shirt_c = shirt_c or rng.choice(CLOTH_RAMPS)
    pants_c = pants_c or rng.choice(CLOTH_RAMPS)
    shoes_c = shoes_c or rng.choice(CLOTH_RAMPS)
    if acc_c is None:
        acc_c = ((25, 20, 25),) * 3 if accessory == "glasses" \
            else rng.choice(CLOTH_RAMPS)

    if direction in ("down", "up"):
        if direction == "down":
            body, shirt, hair_m = BODY, SHIRT, HAIR_STYLES[hair]
            acc_m = ACCESSORIES[accessory]
        else:
            body, shirt, hair_m = BODY_UP, SHIRT_UP, HAIR_UP[hair]
            acc_m = ACCESSORIES[accessory] if accessory == "headband" else None
        upper = [(body, skin), (shirt, shirt_c), (HANDS, skin),
                 (hair_m, hair_c), (acc_m, acc_c)]
        legs = [
            [(PANTS, pants_c), (SHOES, shoes_c)],
            [(PANTS_STEP_A, pants_c), (SHOES_STEP_A, shoes_c)],
            [(PANTS, pants_c), (SHOES, shoes_c)],
            [(PANTS_STEP_B, pants_c), (SHOES_STEP_B, shoes_c)],
        ]
        bobs = [0, 1, 0, 1]
        frames = [_compose(upper, legs[i], bobs[i]) for i in range(4)]
    else:  # right / left
        upper = [(BODY_SIDE, skin), (SHIRT_SIDE, shirt_c),
                 (HANDS_SIDE, skin), (HAIR_SIDE[hair], hair_c),
                 (ACC_SIDE[accessory], acc_c)]
        legs = [
            [(PANTS_SIDE_STRIDE, pants_c), (SHOES_SIDE_STRIDE, shoes_c)],
            [(PANTS_SIDE_STAND, pants_c), (SHOES_SIDE_STAND, shoes_c)],
            [(PANTS_SIDE_STRIDE2, pants_c), (SHOES_SIDE_STRIDE2, shoes_c)],
            [(PANTS_SIDE_STAND, pants_c), (SHOES_SIDE_STAND, shoes_c)],
        ]
        bobs = [1, 0, 1, 0]
        frames = [_compose(upper, legs[i], bobs[i]) for i in range(4)]
        if direction == "left":
            frames = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in frames]
    return frames


def daemon_frames(species, variant=None, facing="right", rng=random):
    """4-frame hop cycle; facing left flips the sprite."""
    base = daemon_generator.make_daemon(species, variant, rng)
    if facing == "left":
        base = base.transpose(Image.FLIP_LEFT_RIGHT)
    frames = []
    for dy in (0, -1, -2, -1):
        f = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        f.paste(base, (0, dy), base)
        frames.append(f)
    return frames


# --------------------------------------------------------- previews
DIRS = ["down", "left", "right", "up"]

def walk_sheet(seed=7, scale=6):
    rng = random.Random(seed)
    outfit = dict(hair=rng.choice(list(HAIR_STYLES)),
                  accessory=rng.choice(list(ACCESSORIES)),
                  skin=rng.choice(SKIN_RAMPS), hair_c=rng.choice(HAIR_RAMPS),
                  shirt_c=rng.choice(CLOTH_RAMPS),
                  pants_c=rng.choice(CLOTH_RAMPS),
                  shoes_c=rng.choice(CLOTH_RAMPS))
    pad = 6
    cell = W + pad
    sheet = Image.new("RGBA", (4 * cell + pad, 4 * cell + pad),
                      (58, 58, 70, 255))
    for r, d in enumerate(DIRS):
        for c, f in enumerate(character_frames(d, **outfit)):
            sheet.paste(f, (pad + c * cell, pad + r * cell), f)
    return sheet.resize((sheet.width * scale, sheet.height * scale),
                        Image.NEAREST), outfit


def walk_gif(outfit, path, scale=6, ms=140):
    pad = 6
    cell = W + pad
    per_dir = [character_frames(d, **outfit) for d in DIRS]
    daemon = daemon_frames("fox", 0)
    gif_frames = []
    for i in range(4):
        fr = Image.new("RGBA", (5 * cell + pad, cell + pad), (58, 58, 70, 255))
        for c in range(4):
            spr = per_dir[c][i]
            fr.paste(spr, (pad + c * cell, pad), spr)
        fr.paste(daemon[i], (pad + 4 * cell, pad), daemon[i])
        fr = fr.resize((fr.width * scale, fr.height * scale), Image.NEAREST)
        gif_frames.append(fr.convert("P"))
    gif_frames[0].save(path, save_all=True, append_images=gif_frames[1:],
                       duration=ms, loop=0)


if __name__ == "__main__":
    sheet, outfit = walk_sheet()
    sheet.save("./walk_sheet.png")
    walk_gif(outfit, "./walk_demo.gif")
    print("saved walk_sheet.png and walk_demo.gif")
