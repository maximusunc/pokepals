"""
Directional walk animations -- 4 directions x 4 frames, layer-consistent,
now with ARMS AS A SEPARATE LAYER so they swing while walking and stay
bare under sleeveless shirts.

Walk cycle = [idle, stepA, idle, stepB]; step B legs derive from step A.
Arm swing: front/back views raise the opposite arm 1px on each step;
side view slides the near arm +/-2px with the stride.
"""

import random
from PIL import Image
from generator import (W, H, BODY, SHIRT, PANTS, SHOES, ARM_L, ARM_R,
                       SLEEVE_L, SLEEVE_R, GARMENTS, HAIR_STYLES,
                       ACCESSORIES, SKIN_RAMPS, HAIR_RAMPS, CLOTH_RAMPS,
                       paint, add_outline)
import animals

BLANK = "." * 32

# ------------------------------------------------- front/back walk leg poses
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

# half-lift (front/back): raised foot 1px lower than the full step
PANTS_STEP_A_HALF = [BLANK] * 23 + [
    "...........2222222222...........",
    "...........2222112222...........",
    "...........2222..2222...........",
    "...........2222..2222...........",
    "...........2222..2222...........",
    ".................1111...........",
] + [BLANK] * 3

SHOES_STEP_A_HALF = [BLANK] * 28 + [
    "...........2222.................",
    "...........1111.222222..........",
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
    "..........222222222222..........",
    "..........222222222222..........",
    "..........222222222222..........",
    "..........222222222222..........",
    "..........222222222222..........",
    "..........222222222222..........",
    "..........111111111111..........",
] + [BLANK] * 9

ARM_SIDE = [BLANK] * 16 + [
    "..............2221..............",
    "..............2221..............",
    "..............2221..............",
    "..............2221..............",
    "..............2221..............",
    "..............2221..............",
    "..............2222..............",
    "..............1221..............",
] + [BLANK] * 8

SLEEVE_SIDE = [BLANK] * 16 + [
    "..............1221..............",
    "..............1221..............",
    "..............1221..............",
    "..............1221..............",
    "..............1221..............",
    "..............1221..............",
] + [BLANK] * 10

# ------------------------------------------ arm swing poses (pivot = shoulder)
# Drawn rotations: shoulder stays anchored, hand travels an arc (ends 1px
# higher when swung) -- reads as rotation without bitmap-rotation smearing.

# front view: arm angled 1px outward from the elbow down, hand raised
ARM_L_SWING = [BLANK] * 15 + [
    ".......332......................",
    ".......322......................",
    ".......322......................",
    ".......322......................",
    "......322.......................",
    "......322.......................",
    "......222.......................",
    "......122.......................",
] + [BLANK] * 9

SLEEVE_L_SWING = [BLANK] * 15 + [
    ".......333......................",
    ".......321......................",
    ".......321......................",
    ".......321......................",
    "......321.......................",
    "......321.......................",
] + [BLANK] * 11

# side view (facing right): arm swept forward / back along a diagonal
ARM_SIDE_FWD = [BLANK] * 16 + [
    "..............2221..............",
    "...............2221.............",
    "...............2221.............",
    "................2221............",
    "................2221............",
    ".................2222...........",
    ".................1221...........",
] + [BLANK] * 9

ARM_SIDE_BACK = [BLANK] * 16 + [
    "..............1222..............",
    ".............1222...............",
    ".............1222...............",
    "............1222................",
    "............1222................",
    "...........2222.................",
    "...........1221.................",
] + [BLANK] * 9

SLEEVE_SIDE_FWD = [BLANK] * 16 + [
    "..............1221..............",
    "...............1221.............",
    "...............1221.............",
    "................1221............",
    "................1221............",
] + [BLANK] * 11

SLEEVE_SIDE_BACK = [BLANK] * 16 + [
    "..............1221..............",
    ".............1221...............",
    ".............1221...............",
    "............1221................",
    "............1221................",
] + [BLANK] * 11

ARM_R_SWING = [r[::-1] for r in ARM_L_SWING]
SLEEVE_R_SWING = [r[::-1] for r in SLEEVE_L_SWING]

for _n, _g in [("ARM_L_SWING", ARM_L_SWING), ("SLEEVE_L_SWING", SLEEVE_L_SWING),
               ("ARM_SIDE_FWD", ARM_SIDE_FWD), ("ARM_SIDE_BACK", ARM_SIDE_BACK),
               ("SLEEVE_SIDE_FWD", SLEEVE_SIDE_FWD),
               ("SLEEVE_SIDE_BACK", SLEEVE_SIDE_BACK)]:
    assert len(_g) == H, f"{_n}: {len(_g)} rows"
    for _i, _r in enumerate(_g):
        assert len(_r) == W, f"{_n} r{_i}: {len(_r)} cols"

# pose lookup tables (a garment with arm parts supplies one per pose)
ARM_POSE_L = {"neutral": ARM_L, "swing": ARM_L_SWING}
ARM_POSE_R = {"neutral": ARM_R, "swing": ARM_R_SWING}
SLEEVE_POSE_L = {"neutral": SLEEVE_L, "swing": SLEEVE_L_SWING}
SLEEVE_POSE_R = {"neutral": SLEEVE_R, "swing": SLEEVE_R_SWING}
SIDE_ARM_POSE = {"neutral": ARM_SIDE, "fwd": ARM_SIDE_FWD,
                 "back": ARM_SIDE_BACK}
SIDE_SLEEVE_POSE = {"neutral": SLEEVE_SIDE, "fwd": SLEEVE_SIDE_FWD,
                    "back": SLEEVE_SIDE_BACK}

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
    "...........111..22222...........",
    "..........111....22222..........",
    ".........111......22222.........",
    ".........111.......2222.........",
    "........111........2222.........",
] + [BLANK] * 3

SHOES_SIDE_STRIDE = [BLANK] * 29 + [
    ".......1111........2222.........",
    ".......1111........22222........",
    ".......1111........11111........",
]

PANTS_SIDE_HALF = [BLANK] * 23 + [
    "...........2222222222...........",
    "............111.2222............",
    "...........111...2222...........",
    "...........111...2222...........",
    "..........111.....2222..........",
    "..........111.....2222..........",
] + [BLANK] * 3

SHOES_SIDE_HALF = [BLANK] * 29 + [
    ".........1111.....2222..........",
    ".........1111.....22222.........",
    ".........1111.....11111.........",
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

# side-view parts for each garment; "arm" parts ride the arm offset
GARMENTS_SIDE = {
    "tee":  {"torso": SHIRT_SIDE, "arm": SLEEVE_SIDE},
    "tank": {"torso": SHIRT_SIDE, "arm": None},
}

_ALL = {"PANTS_STEP_A": PANTS_STEP_A, "SHOES_STEP_A": SHOES_STEP_A,
        "PANTS_STEP_A_HALF": PANTS_STEP_A_HALF,
        "SHOES_STEP_A_HALF": SHOES_STEP_A_HALF,
        "PANTS_SIDE_HALF": PANTS_SIDE_HALF,
        "SHOES_SIDE_HALF": SHOES_SIDE_HALF,
        "BODY_SIDE": BODY_SIDE, "SHIRT_SIDE": SHIRT_SIDE,
        "ARM_SIDE": ARM_SIDE, "SLEEVE_SIDE": SLEEVE_SIDE,
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
    tr = str.maketrans("12", "21")
    out = [row.translate(tr) for row in grid]
    out[31] = grid[31]
    return out

PANTS_STEP_B = mirror(PANTS_STEP_A)
SHOES_STEP_B = mirror(SHOES_STEP_A)
PANTS_STEP_B_HALF = mirror(PANTS_STEP_A_HALF)
SHOES_STEP_B_HALF = mirror(SHOES_STEP_A_HALF)
PANTS_SIDE_STRIDE2 = swap_near_far(PANTS_SIDE_STRIDE)
SHOES_SIDE_STRIDE2 = swap_near_far(SHOES_SIDE_STRIDE)
PANTS_SIDE_HALF2 = swap_near_far(PANTS_SIDE_HALF)
SHOES_SIDE_HALF2 = swap_near_far(SHOES_SIDE_HALF)

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
def paint_at(dst, grid, ramp, dx=0, dy=0):
    if grid is None:
        return
    tmp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    paint(tmp, grid, ramp)
    dst.paste(tmp, (dx, dy), tmp)


def _compose(upper_parts, leg_parts, bob=0):
    """upper_parts: list of (grid, ramp, dx, dy); leg_parts: (grid, ramp)."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for grid, ramp in leg_parts:
        paint(img, grid, ramp)
    upper = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for grid, ramp, dx, dy in upper_parts:
        paint_at(upper, grid, ramp, dx, dy)
    img.paste(upper, (0, bob), upper)
    add_outline(img)
    return img


def character_frames(direction, hair=None, accessory=None, skin=None,
                     hair_c=None, shirt_c=None, pants_c=None, shoes_c=None,
                     acc_c=None, garment=None, rng=random):
    """4 walk frames for one direction, consistent outfit, swinging arms."""
    garment = garment or rng.choice(list(GARMENTS))
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
    g_front = GARMENTS[garment]
    g_side = GARMENTS_SIDE[garment]

    if direction in ("down", "up"):
        if direction == "down":
            body, shirt, hair_m = BODY, SHIRT, HAIR_STYLES[hair]
            acc_m = ACCESSORIES[accessory]
        else:
            body, shirt, hair_m = BODY_UP, SHIRT_UP, HAIR_UP[hair]
            acc_m = ACCESSORIES[accessory] if accessory == "headband" else None

        def upper(pose_l, pose_r):
            slv_l = SLEEVE_POSE_L[pose_l] if g_front["arm_l"] else None
            slv_r = SLEEVE_POSE_R[pose_r] if g_front["arm_r"] else None
            return [(body, skin, 0, 0),
                    (ARM_POSE_L[pose_l], skin, 0, 0),
                    (ARM_POSE_R[pose_r], skin, 0, 0),
                    (shirt, shirt_c, 0, 0),
                    (slv_l, shirt_c, 0, 0), (slv_r, shirt_c, 0, 0),
                    (hair_m, hair_c, 0, 0), (acc_m, acc_c, 0, 0)]

        stand = [(PANTS, pants_c), (SHOES, shoes_c)]
        halfA = [(PANTS_STEP_A_HALF, pants_c), (SHOES_STEP_A_HALF, shoes_c)]
        fullA = [(PANTS_STEP_A, pants_c), (SHOES_STEP_A, shoes_c)]
        halfB = [(PANTS_STEP_B_HALF, pants_c), (SHOES_STEP_B_HALF, shoes_c)]
        fullB = [(PANTS_STEP_B, pants_c), (SHOES_STEP_B, shoes_c)]
        legs = [stand, halfA, fullA, halfA, stand, halfB, fullB, halfB]
        # arm swings opposite the stepping leg, held through the lift
        arm_poses = [("neutral", "neutral"), ("neutral", "neutral"),
                     ("neutral", "swing"), ("neutral", "swing"),
                     ("neutral", "neutral"), ("neutral", "neutral"),
                     ("swing", "neutral"), ("swing", "neutral")]
        bobs = [0, 1, 1, 1, 0, 1, 1, 1]
        frames = [_compose(upper(*arm_poses[i]), legs[i], bobs[i])
                  for i in range(8)]
    else:  # right / left
        def upper(pose):
            # in profile the near arm is in FRONT of the torso -> paint after
            slv = SIDE_SLEEVE_POSE[pose] if g_side["arm"] else None
            return [(BODY_SIDE, skin, 0, 0),
                    (g_side["torso"], shirt_c, 0, 0),
                    (SIDE_ARM_POSE[pose], skin, 0, 0),
                    (slv, shirt_c, 0, 0),
                    (HAIR_SIDE[hair], hair_c, 0, 0),
                    (ACC_SIDE[accessory], acc_c, 0, 0)]

        strideA = [(PANTS_SIDE_STRIDE, pants_c), (SHOES_SIDE_STRIDE, shoes_c)]
        halfA = [(PANTS_SIDE_HALF, pants_c), (SHOES_SIDE_HALF, shoes_c)]
        stand = [(PANTS_SIDE_STAND, pants_c), (SHOES_SIDE_STAND, shoes_c)]
        halfB = [(PANTS_SIDE_HALF2, pants_c), (SHOES_SIDE_HALF2, shoes_c)]
        strideB = [(PANTS_SIDE_STRIDE2, pants_c), (SHOES_SIDE_STRIDE2, shoes_c)]
        legs = [strideA, halfA, stand, halfB, strideB, halfB, stand, halfA]
        # near leg forward -> near arm swings back, easing through neutral
        arm_poses = ["back", "back", "neutral", "fwd",
                     "fwd", "fwd", "neutral", "back"]
        bobs = [1, 0, 0, 0, 1, 0, 0, 0]
        frames = [_compose(upper(arm_poses[i]), legs[i], bobs[i])
                  for i in range(8)]
        if direction == "left":
            frames = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in frames]
    return frames


def daemon_frames(species, variant=None, facing="right", rng=random):
    base = animals.make_daemon(species, variant, rng)
    if facing == "left":
        base = base.transpose(Image.FLIP_LEFT_RIGHT)
    frames = []
    for dy in (0, -1, -2, -1, 0, -1, -2, -1):
        f = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        f.paste(base, (0, dy), base)
        frames.append(f)
    return frames


# --------------------------------------------------------- previews
DIRS = ["down", "left", "right", "up"]

def walk_sheet(seed=7, scale=6, garment=None):
    rng = random.Random(seed)
    outfit = dict(garment=garment or rng.choice(list(GARMENTS)),
                  hair=rng.choice(list(HAIR_STYLES)),
                  accessory=rng.choice(list(ACCESSORIES)),
                  skin=rng.choice(SKIN_RAMPS), hair_c=rng.choice(HAIR_RAMPS),
                  shirt_c=rng.choice(CLOTH_RAMPS),
                  pants_c=rng.choice(CLOTH_RAMPS),
                  shoes_c=rng.choice(CLOTH_RAMPS))
    pad = 6
    cell = W + pad
    per_dir = [character_frames(d, **outfit) for d in DIRS]
    n = len(per_dir[0])
    sheet = Image.new("RGBA", (n * cell + pad, 4 * cell + pad),
                      (58, 58, 70, 255))
    for r, frames in enumerate(per_dir):
        for c, f in enumerate(frames):
            sheet.paste(f, (pad + c * cell, pad + r * cell), f)
    return sheet.resize((sheet.width * scale, sheet.height * scale),
                        Image.NEAREST), outfit


def walk_gif(outfits, path, scale=6, ms=95):
    pad = 6
    cell = W + pad
    cols = []
    for outfit in outfits:
        cols += [character_frames(d, **outfit) for d in DIRS]
    daemon = daemon_frames("fox", 0)
    n = len(cols) + 1
    gif_frames = []
    for i in range(8):
        fr = Image.new("RGBA", (n * cell + pad, cell + pad), (58, 58, 70, 255))
        for c in range(len(cols)):
            spr = cols[c][i]
            fr.paste(spr, (pad + c * cell, pad), spr)
        fr.paste(daemon[i], (pad + len(cols) * cell, pad), daemon[i])
        fr = fr.resize((fr.width * scale, fr.height * scale), Image.NEAREST)
        gif_frames.append(fr.convert("P"))
    gif_frames[0].save(path, save_all=True, append_images=gif_frames[1:],
                       duration=ms, loop=0)


if __name__ == "__main__":
    sheet_tee, outfit_tee = walk_sheet(seed=7, garment="tee")
    sheet_tank, outfit_tank = walk_sheet(seed=11, garment="tank")
    sheet_tee.save("walk_sheet.png")
    sheet_tank.save("walk_sheet_tank.png")
    walk_gif([outfit_tee, outfit_tank], "walk_demo.gif")
    print("saved walk_sheet.png, walk_sheet_tank.png, walk_demo.gif")
