"""
Daemon movement animations.

- Bird: wing-flap flight cycle. The bird is split into a wingless body
  plus wing POSE maps (up / mid / down / folded). The body rises on the
  downstroke and dips on the recovery stroke -- the opposition that makes
  flapping read as lift rather than twitching.
- Fox: side-view trot using the hand-drawn profile: stretch / gather leg
  poses with an airborne suspension moment on the gather.
- Other species keep the hop from walk.py (daemon_frames) until they get
  profiles; wiring a new species in means one leg-pose set like the fox's.

All frames are 8 long to share one animation clock with the player walk.
"""

import random
from PIL import Image
from generator import paint, add_outline, W, H
import animals
from directions import FOX_SIDE

BLANK = "." * 32

# ------------------------------------------------------------ bird wings
# '1' shade = dark flight feathers against the '3' body highlight
WINGS_FOLDED = [BLANK] * 18 + [
    "..........1..........1..........",
    "..........1..........1..........",
    "..........1..........1..........",
    "..........1..........1..........",
    "..........1..........1..........",
] + [BLANK] * 9

WINGS_UP = [BLANK] * 14 + [
    "......11................11......",
    "......111..............111......",
    ".......111............111.......",
    "........111..........111........",
    ".........11..........11.........",
] + [BLANK] * 13

WINGS_MID = [BLANK] * 18 + [
    "......11111..........11111......",
    ".....11111............11111.....",
] + [BLANK] * 12

WINGS_DOWN = [BLANK] * 18 + [
    "..........1..........1..........",
    "........111..........111........",
    ".......111............111.......",
    "......111..............111......",
    "......11................11......",
] + [BLANK] * 9

# wingless bird body: folded-wing pixels ('1' in rows 18-22) become body
_bird_front, _ = animals.SPECIES["bird"]
BIRD_BODY = [r.replace('1', '3') if 18 <= y <= 22 else r
             for y, r in enumerate(_bird_front)]

# ------------------------------------------------------------ fox trot legs
# profile body without legs (leg rows 21-25 blanked)
FOX_BODY_SIDE = FOX_SIDE[:21] + [BLANK] * 11

FOX_LEGS_STAND = [BLANK] * 21 + [
    ".........1122......1122.........",
    ".........1122......1122.........",
    ".........1122......1122.........",
    ".........1122......1122.........",
    ".........1122......1122.........",
] + [BLANK] * 6

FOX_LEGS_STRETCH = [BLANK] * 21 + [
    ".........1122......1122.........",
    "........1122........1122........",
    ".......1122..........1122.......",
    "......1122............1122......",
    "......1122............1122......",
] + [BLANK] * 6

FOX_LEGS_GATHER = [BLANK] * 21 + [
    "..........1122....1122..........",
    "...........1122..1122...........",
    "............11221122............",
] + [BLANK] * 8

for _n, _g in [("WINGS_FOLDED", WINGS_FOLDED), ("WINGS_UP", WINGS_UP),
               ("WINGS_MID", WINGS_MID), ("WINGS_DOWN", WINGS_DOWN),
               ("FOX_LEGS_STAND", FOX_LEGS_STAND),
               ("FOX_LEGS_STRETCH", FOX_LEGS_STRETCH),
               ("FOX_LEGS_GATHER", FOX_LEGS_GATHER)]:
    assert len(_g) == H, f"{_n}: {len(_g)} rows"
    for _i, _r in enumerate(_g):
        assert len(_r) == W, f"{_n} r{_i}: {len(_r)} cols"

# ------------------------------------------------------------ assembly
def _frame(parts, dy=0):
    """parts: list of (grid, ramp). dy shifts the whole sprite."""
    base = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for grid, ramp in parts:
        paint(base, grid, ramp)
    add_outline(base)
    if dy:
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        img.paste(base, (0, dy), base)
        return img
    return base


def bird_fly_frames(variant=None, facing="right", rng=random):
    """8-frame flap: down(lift) -> mid -> up(recovery, dip) -> mid, twice."""
    _, ramps = animals.SPECIES["bird"]
    ramp = ramps[variant] if variant is not None else rng.choice(ramps)
    cycle = [(WINGS_DOWN, -1), (WINGS_MID, 0), (WINGS_UP, 1), (WINGS_MID, 0)]
    frames = []
    for wings, dy in cycle * 2:
        f = _frame([(BIRD_BODY, ramp), (wings, ramp)], dy)
        if facing == "left":
            f = f.transpose(Image.FLIP_LEFT_RIGHT)
        frames.append(f)
    return frames


def bird_idle_frames(variant=None, facing="right", rng=random):
    """Perched: folded wings with an occasional settle (1px dip)."""
    _, ramps = animals.SPECIES["bird"]
    ramp = ramps[variant] if variant is not None else rng.choice(ramps)
    frames = []
    for dy in (0, 0, 0, 1, 0, 0, 0, 0):
        f = _frame([(BIRD_BODY, ramp), (WINGS_FOLDED, ramp)], dy)
        if facing == "left":
            f = f.transpose(Image.FLIP_LEFT_RIGHT)
        frames.append(f)
    return frames


def fox_trot_frames(variant=None, facing="right", rng=random):
    """8-frame trot: stretch -> stand -> gather(airborne) -> stand, twice."""
    _, ramps = animals.SPECIES["fox"]
    ramp = ramps[variant] if variant is not None else rng.choice(ramps)
    cycle = [(FOX_LEGS_STRETCH, 0), (FOX_LEGS_STAND, 0),
             (FOX_LEGS_GATHER, -1), (FOX_LEGS_STAND, 0)]
    frames = []
    for legs, dy in cycle * 2:
        f = _frame([(FOX_BODY_SIDE, ramp), (legs, ramp)], dy)
        if facing == "left":
            f = f.transpose(Image.FLIP_LEFT_RIGHT)
        frames.append(f)
    return frames


# ------------------------------------------------------------ previews
def motion_sheet(scale=6):
    rows = [bird_fly_frames(0), bird_idle_frames(0), fox_trot_frames(0)]
    pad = 6
    cell = W + pad
    sheet = Image.new("RGBA", (8 * cell + pad, len(rows) * cell + pad),
                      (58, 58, 70, 255))
    for r, frames in enumerate(rows):
        for c, f in enumerate(frames):
            sheet.paste(f, (pad + c * cell, pad + r * cell), f)
    return sheet.resize((sheet.width * scale, sheet.height * scale),
                        Image.NEAREST)


def motion_gif(path, scale=6, ms=95):
    seqs = [bird_fly_frames(0), bird_fly_frames(3, facing="left"),
            fox_trot_frames(0), fox_trot_frames(2, facing="left")]
    pad = 6
    cell = W + pad
    gif_frames = []
    for i in range(8):
        fr = Image.new("RGBA", (len(seqs) * cell + pad, cell + pad),
                       (58, 58, 70, 255))
        for c, seq in enumerate(seqs):
            fr.paste(seq[i], (pad + c * cell, pad), seq[i])
        fr = fr.resize((fr.width * scale, fr.height * scale), Image.NEAREST)
        gif_frames.append(fr.convert("P"))
    gif_frames[0].save(path, save_all=True, append_images=gif_frames[1:],
                       duration=ms, loop=0)


if __name__ == "__main__":
    motion_sheet().save("animal_motion.png")
    motion_gif("animal_motion.gif")
    print("saved animal_motion.png and animal_motion.gif")
