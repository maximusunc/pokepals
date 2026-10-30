"""
Real leg cycles for the daemon quadrupeds -- posed from the SAME standing
facing maps directions.py draws, so every frame stays on-model.

Before this, a walking animal was its standing map nudged up and down
(walk.daemon_frames' hop): the legs never moved. Here each frame is a
POSE applied to the map:

  * legs   -- found automatically: the connected pixel groups below the
              body's underside (the lowest row with a wide run). Each leg
              gets a role -- near/far x front/hind -- from where it sits
              (front = toward the head, near = lower feet). In a profile
              the near and far legs are drawn as one '1122' column; they
              split by shade ('1' = far, the rest = near) so all four legs
              can move. A leg is posed with a LIFT (shin rows dropped so
              the foot rises, the foot row kept) and a SWING (sheared from
              its hip so the foot reaches forward or back).
  * body   -- everything above the legs drops 1px on the planted-and-
              spread beats, the bob that makes weight read.
  * tail / ears -- an optional box per view, sheared from its root so the
              tip sways (a cat's swish, a fox's brush, a rabbit's ears
              blown back on the hop).
  * blink  -- eyes ('E') close to the dark shade for a frame.
  * sprite -- the whole frame lifted (a rabbit's hop leaves the ground).

The back view is still DERIVED (directions._derive) -- but from the posed
front map, so its legs step too, and its tail overlay sways.

A GAIT is just a list of poses (8 for a move cycle, IDLE_FRAMES for the
idle loop), authored per species below. Pure functions over ASCII maps,
like the rest of tools/pixelart.
"""

import math
from PIL import Image
from generator import paint, add_outline, W, H
import animals
import directions

GROUND = 25          # every standing map's feet sit on this row
IDLE_FRAMES = 16


def _rnd(x):
    """Round half away from zero, so a swing is symmetric fore and aft."""
    return int(math.copysign(math.floor(abs(x) + 0.5), x))


# ------------------------------------------------------------ leg finding
def _zone_top(grid):
    """First row below the body: one past the lowest row with a wide run."""
    for y in range(H - 1, -1, -1):
        run = best = 0
        for ch in grid[y]:
            run = run + 1 if ch != '.' else 0
            best = max(best, run)
        if best >= 6:
            return y + 1
    raise ValueError("no body found")


def _components(grid, top):
    seen, comps = set(), []
    for y in range(top, H):
        for x in range(W):
            if grid[y][x] == '.' or (y, x) in seen:
                continue
            stack, comp = [(y, x)], {}
            seen.add((y, x))
            while stack:
                cy, cx = stack.pop()
                comp[(cy, cx)] = grid[cy][cx]
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if top <= ny < H and 0 <= nx < W and grid[ny][nx] != '.' \
                            and (ny, nx) not in seen:
                        seen.add((ny, nx))
                        stack.append((ny, nx))
            comps.append(comp)
    return comps


def _cx(comp):
    return sum(x for _, x in comp) / len(comp)


def _bottom(comp):
    return max(y for y, _ in comp)


def find_legs(grid, view):
    """{role: {(y, x): ch}} for a right-handed view's legs.

    Roles: nf / ff / nh / fh (near/far, front/hind). A front or back view
    shows only the two front legs: 'nf' is the viewer's left, 'ff' the right.
    """
    top = _zone_top(grid)
    comps = sorted(_components(grid, top), key=_cx)
    if view in ("down", "up"):
        assert len(comps) == 2, f"{view}: {len(comps)} legs"
        return top, {"nf": comps[0], "ff": comps[1]}
    if view == "right":
        assert len(comps) == 2, f"profile: {len(comps)} legs"
        legs = {}
        for end, comp in zip("hf", comps):            # hind is further from the head
            legs["f" + end] = {k: c for k, c in comp.items() if c == '1'}
            legs["n" + end] = {k: c for k, c in comp.items() if c != '1'}
        return top, legs
    assert len(comps) == 4, f"{view}: {len(comps)} legs"
    hind, front = comps[:2], comps[2:]
    legs = {}
    for end, pair in (("h", hind), ("f", front)):
        near, far = sorted(pair, key=_bottom, reverse=True)
        legs["n" + end], legs["f" + end] = near, far
    return top, legs


def pose_leg(pix, swing, lift, keep=1):
    """Lift the foot `lift` rows (dropping shin rows, keeping the foot row)
    and shear the leg from its hip so the foot sits `swing` px forward."""
    if not pix:
        return {}
    t = min(y for y, _ in pix)
    b = max(y for y, _ in pix)
    n = b - t + 1
    k = max(0, min(lift, n - keep))
    n2 = n - k
    out = {}
    for (y, x), ch in pix.items():
        if y == b:
            y = b - k                                  # the foot rises...
        elif y >= b - k:
            continue                                   # ...over the dropped shin rows
        off = _rnd(swing * (y - t) / (n2 - 1)) if n2 > 1 else _rnd(swing)
        out[(y, x + off)] = ch
    return out


# --------------------------------------------------- tail / ear shearing
def shear(grid, region, amp):
    """Shear the pixels inside a box so its far end moves `amp` px.

    region: ('v', r0, r1, c0, c1, root_row) -- a tail/ears standing up or
            hanging down: each ROW shifts in x, more the further from root.
            ('h', r0, r1, c0, c1, root_col) -- a tail streaming sideways:
            each COLUMN shifts in y.
    """
    if not region or not amp:
        return grid
    axis, r0, r1, c0, c1, root = region
    g = [list(r) for r in grid]
    span = max(abs(r - root) for r in (r0, r1)) if axis == 'v' \
        else max(abs(c - root) for c in (c0, c1))
    moved = {}
    for y in range(r0, r1 + 1):
        for x in range(c0, c1 + 1):
            ch = g[y][x]
            if ch == '.':
                continue
            dist = abs(y - root) if axis == 'v' else abs(x - root)
            off = _rnd(amp * dist / span)
            g[y][x] = '.'
            moved[(y, x + off) if axis == 'v' else (y + off, x)] = ch
    for (y, x), ch in moved.items():
        if 0 <= y < H and 0 <= x < W:
            g[y][x] = ch
    return ["".join(r) for r in g]


# ------------------------------------------------------- per-view regions
# Only tails that stand clear of the body sway (a tail fused into the rump
# would tear a seam). Rabbit ears blow back on the hop instead.
TAILS = {
    "cat": {"right": ('v', 13, 15, 3, 4, 16),
            "down_right": ('v', 6, 11, 2, 4, 12),
            "up_right": ('v', 7, 13, 2, 4, 14)},
    "fox": {"right": ('h', 13, 18, 0, 6, 7),
            "down_right": ('v', 9, 11, 0, 4, 12)},
    "wolf": {"right": ('v', 16, 19, 0, 3, 15),
             "down_right": ('v', 12, 15, 0, 2, 11)},
    "rabbit": {},
}
EARS = {
    "rabbit": {"right": ('v', 3, 8, 13, 22, 9),
               "down_right": ('v', 5, 11, 17, 23, 12),
               "up_right": ('v', 2, 8, 17, 23, 9)},
}


# ------------------------------------------------------------- the poser
def pose_view(species, view, pose):
    """The posed ASCII map for one right-handed view (no outline yet)."""
    if view == "up":
        front = pose_view(species, "down", dict(pose, tail=0, blink=False))
        cfg = directions.CONFIG[species]
        overlay = _sway_overlay(cfg["tail_overlay"], pose.get("tail", 0))
        return directions._derive(front, cfg["nose_rows"],
                                  cfg["inner_ear_rows"], overlay=overlay)
    grid = directions.derive_view(species, view)
    top, legs = find_legs(grid, view)
    body = [list(r) for r in grid]
    for pix in legs.values():
        for (y, x) in pix:
            body[y][x] = '.'
    body = ["".join(r) for r in body]
    body = shear(body, TAILS.get(species, {}).get(view), pose.get("tail", 0))
    body = shear(body, EARS.get(species, {}).get(view), pose.get("ears", 0))
    if pose.get("blink"):
        body = [r.replace('E', '1') for r in body]

    out = [['.'] * W for _ in range(H)]
    bdy = pose.get("body", 0)
    order = ["fh", "ff", "nh", "nf"]                   # far legs first
    for role in order:
        if role not in legs:
            continue
        swing, lift = pose.get(role, (0, 0))
        if view in ("down", "up"):
            swing = 0                                  # toward/away: lift only
        keep = 1 + bdy                                 # stay visible under a dropped body
        for (y, x), ch in pose_leg(legs[role], swing, lift, keep).items():
            if 0 <= x < W:
                out[y][x] = ch
    for y in range(H):
        sy = y - bdy
        if 0 <= sy < H:
            for x, ch in enumerate(body[sy]):
                if ch != '.':
                    out[y][x] = ch
    return ["".join(r) for r in out]


def _sway_overlay(overlay, amp):
    if not overlay or not amp:
        return overlay
    y0 = overlay[0][0]
    span = max(1, overlay[-1][0] - y0)
    return [(y, x + _rnd(amp * (y - y0) / span), chars) for (y, x, chars) in overlay]


def render(species, view, pose, variant=0):
    """A posed 32x32 frame for a right-handed view, outlined, lifted."""
    if species in QUADRUPEDS:
        grid = pose_view(species, view, pose)
    else:                                              # the bird: perched, no legs to pose
        grid = directions.derive_view(species, view)
        if pose.get("blink"):
            grid = [r.replace('E', '1') for r in grid]
    _, ramps = animals.SPECIES[species]
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    paint(img, grid, ramps[variant])
    add_outline(img)
    dy = pose.get("sprite", 0)
    if dy < 0:
        top = min(y for y, r in enumerate(grid) if r.strip('.'))
        dy = max(dy, 1 - top)                          # never clip the ears
    if dy:
        lifted = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        lifted.paste(img, (0, dy), img)
        img = lifted
    return img


# ------------------------------------------------------------------ gaits
def _walk(amp, lift, bob=1, bounce=0, tail=0, frames=8):
    """A four-beat-ish walk/trot: diagonal pairs (near-front + far-hind,
    then far-front + near-hind) swing forward lifted, plant, and push back.
    The body drops on the spread beats; `bounce` lifts the whole sprite at
    mid-swing (a trot's moment of suspension)."""
    poses = []
    for i in range(frames):
        phi = 2 * math.pi * i / frames
        p = {}
        for role, off in (("nf", 0), ("fh", 0), ("ff", math.pi), ("nh", math.pi)):
            a = phi + off
            p[role] = (_rnd(amp * math.cos(a)), _rnd(lift * max(0.0, -math.sin(a))))
        spread = i % (frames // 2) == 0
        p["body"] = bob if spread else 0
        p["sprite"] = -bounce if i % (frames // 2) == frames // 4 else 0
        p["tail"] = _rnd(tail * math.sin(phi))
        poses.append(p)
    return poses


def _hop():
    """A rabbit's hop: crouch, push off, sail with ears streaming back,
    reach, land, settle. One hop per 8-frame cycle."""
    table = [
        # sprite body   front      hind     ears
        (0,     1,   (0, 0),   (1, 0),    0),
        (-1,    0,   (-1, 1),  (-2, 0),  -1),
        (-2,    0,   (1, 1),   (-2, 1),  -2),
        (-3,    0,   (2, 1),   (-1, 2),  -2),
        (-2,    0,   (2, 0),   (0, 2),   -1),
        (-1,    0,   (1, 0),   (1, 1),    0),
        (0,     1,   (0, 0),   (1, 0),    1),
        (0,     0,   (0, 0),   (0, 0),    0),
    ]
    return [{"sprite": s, "body": b, "nf": f, "ff": f, "nh": h, "fh": h, "ears": e}
            for s, b, f, h, e in table]


GAITS = {
    "cat": _walk(amp=2, lift=1, bob=1, tail=1),        # soft, low, tail swishing
    "fox": _walk(amp=2, lift=2, bob=1, bounce=1, tail=1),  # brisk trot, brush bobbing
    "wolf": _walk(amp=3, lift=2, bob=1, tail=1),       # long loping strides
    "rabbit": _hop(),
}


def _idle(tail=1, ears=0, blink_at=11, breath=(5, 6, 7)):
    """A resting loop: a slow tail swish, one blink, a breath (the body
    settling 1px), and for the rabbit an ear twitch. Mostly still -- it
    should read as alive, not fidgety."""
    swish = [0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, -1, -1, -1, 0, 0]
    poses = []
    for i in range(IDLE_FRAMES):
        p = {"tail": swish[i] * tail, "blink": i == blink_at,
             "body": 1 if i in breath else 0}
        if ears and i in (13, 14):
            p["ears"] = -ears
        poses.append(p)
    return poses


IDLES = {
    # perched: a blink and a little settle of the feathers (the whole bird dips 1px)
    "bird": [{"blink": i == 9, "sprite": 1 if i in (4, 5) else 0} for i in range(IDLE_FRAMES)],
    "cat": _idle(tail=1),
    "fox": _idle(tail=1),
    "wolf": _idle(tail=1, breath=(4, 5, 6, 7)),
    "rabbit": _idle(tail=0, ears=1),
}

QUADRUPEDS = tuple(GAITS)
VIEWS = ["down", "down_right", "right", "up_right", "up"]


def move_frames(species, view, variant=0):
    return [render(species, view, p, variant) for p in GAITS[species]]


def idle_frames(species, view, variant=0):
    return [render(species, view, p, variant) for p in IDLES[species]]


# --------------------------------------------------------------- previews
def preview_sheet(path, scale=4):
    pad = 4
    cell = W + pad
    rows = [(sp, v) for sp in QUADRUPEDS for v in VIEWS]
    sheet = Image.new("RGBA", (8 * cell + pad, len(rows) * cell + pad), (58, 58, 70, 255))
    for r, (sp, v) in enumerate(rows):
        for c, f in enumerate(move_frames(sp, v)):
            sheet.paste(f, (pad + c * cell, pad + r * cell), f)
    sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST).save(path)


def preview_gif(path, scale=5, ms=100, idle=False):
    pad = 4
    cell = W + pad
    seqs = [(idle_frames if idle else move_frames)(sp, v)
            for sp in QUADRUPEDS for v in VIEWS]
    n = len(seqs[0])
    cols = len(VIEWS)
    frames = []
    for i in range(n):
        fr = Image.new("RGBA", (cols * cell + pad, len(QUADRUPEDS) * cell + pad),
                       (58, 58, 70, 255))
        for k, seq in enumerate(seqs):
            fr.paste(seq[i], (pad + (k % cols) * cell, pad + (k // cols) * cell), seq[i])
        frames.append(fr.resize((fr.width * scale, fr.height * scale), Image.NEAREST)
                      .convert("P"))
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=ms, loop=0)


if __name__ == "__main__":
    preview_sheet("gaits.png")
    preview_gif("gaits.gif")
    preview_gif("idles.gif", ms=200, idle=True)
    print("saved gaits.png, gaits.gif, idles.gif")
