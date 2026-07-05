#!/usr/bin/env python3
"""Export the hand-authored pixelart character maps as per-layer wardrobe sheets.

The ART lives in tools/pixelart (ASCII pixel maps + pose tables — see its README);
this tool only ADAPTS it to the game's paper-doll contracts. Change the art there,
re-run this, and every layer sheet regenerates in step.

Per item sheet (one PNG per catalog item, like the old gen_cosmetics.py):

    256 x 96 px, 32x32 cells, COLS=8 (walk cycle, col 0 = idle), ROWS=3 (down, side, up).
    Left-facing is the SIDE row drawn flipped at runtime (SpriteActor).

The pixelart package composites a whole character and outlines the FINISHED frame;
the runtime instead stacks per-item layers by slot z. Two adaptations bridge that gap
without touching the source maps:

  • OUTLINE OWNERSHIP — the single silhouette outline is computed against a fixed
    "mannequin" (body+arms, pants, shoes, shirt torso — the required slots, whose
    silhouettes don't vary between items) and each outline pixel is assigned to the
    top-most adjacent layer's sheet. Optional layers (hair) carry only the outline
    they ADD beyond the mannequin. Stacked at runtime, the layers reproduce exactly
    the composite's one-silhouette outline — no seams between shirt and skin.
  • ARM CARVE (side view) — in profile the near arm paints OVER the shirt torso and
    the hand over the pants hip (walk.py's paint order). The arm lives in the body
    sheet (it's skin), so the shirt/pants sheets get the arm's silhouette carved out
    per frame and the body layer shows through — the same registration trick the
    old cosmetics used to keep the face visible under hair.

Every layer is a DYE layer: authored grayscale (dark outline + 3 grays), recolored at
runtime by the color slot that targets its paper-doll slot (avatar_compositor.gd maps
luminance onto the chosen swatch). Glasses are the one exception — near-black ink,
below the recolor threshold, so they stay dark under any palette. The side walk cycle
is phase-rotated so column 0 is the standing pose (the runtime's idle frame); the loop
itself is unchanged from walk.py.

Requires Pillow (like tools/pixelart). Output PNGs + .import sidecars are committed,
so the game and other contributors never need it. After regenerating, run
`godot --headless --path pokepals --import` so Godot refreshes the .ctex imports.

Run from anywhere:  python3 pokepals/tools/gen_wardrobe.py [--preview out.png]
"""

import os
import sys
import hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))

from PIL import Image  # noqa: E402

import generator as G  # noqa: E402
import walk as WK      # noqa: E402

SIZE = 32
COLS, ROWS = 8, 3            # 8 walk frames x (down, side, up)
ROW_OF = {"down": 0, "side": 1, "up": 2}
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "assets", "cosmetics"))

# Grayscale dye ramp — same convention the old cosmetics used and the runtime expects:
# near-black outline (preserved by the recolor), three grays -> shadow/mid/highlight.
OUTLINE = (30, 22, 20, 255)
GRAY = {"1": (92, 92, 92, 255), "2": (150, 150, 150, 255), "3": (208, 208, 208, 255)}
INK = (25, 20, 25, 255)      # eyes, and the whole glasses layer — below the recolor cut

# Slot z-order (must match data/cosmetics.json) — outline pixels go to the top-most
# adjacent required layer so nothing ever paints over them wrongly.
Z = {"body": 0, "legwear": 15, "outfit": 20, "footwear": 25}


# --------------------------------------------------------------- frame recipes
# Copied structurally from walk.character_frames so the exported layers animate in
# exact lockstep with the source's composite frames.
def _front_legs():
    stand = (G.PANTS, G.SHOES)
    half_a = (WK.PANTS_STEP_A_HALF, WK.SHOES_STEP_A_HALF)
    full_a = (WK.PANTS_STEP_A, WK.SHOES_STEP_A)
    half_b = (WK.PANTS_STEP_B_HALF, WK.SHOES_STEP_B_HALF)
    full_b = (WK.PANTS_STEP_B, WK.SHOES_STEP_B)
    return [stand, half_a, full_a, half_a, stand, half_b, full_b, half_b]


FRONT_LEGS = _front_legs()
FRONT_ARMS = [("neutral", "neutral"), ("neutral", "neutral"),
              ("neutral", "swing"), ("neutral", "swing"),
              ("neutral", "neutral"), ("neutral", "neutral"),
              ("swing", "neutral"), ("swing", "neutral")]
FRONT_BOBS = [0, 1, 1, 1, 0, 1, 1, 1]


def _rot2(seq):
    # Start the side cycle on the STAND pose so column 0 works as the idle frame.
    return list(seq[2:]) + list(seq[:2])


def _side_legs():
    stride_a = (WK.PANTS_SIDE_STRIDE, WK.SHOES_SIDE_STRIDE)
    half_a = (WK.PANTS_SIDE_HALF, WK.SHOES_SIDE_HALF)
    stand = (WK.PANTS_SIDE_STAND, WK.SHOES_SIDE_STAND)
    half_b = (WK.PANTS_SIDE_HALF2, WK.SHOES_SIDE_HALF2)
    stride_b = (WK.PANTS_SIDE_STRIDE2, WK.SHOES_SIDE_STRIDE2)
    return _rot2([stride_a, half_a, stand, half_b, stride_b, half_b, stand, half_a])


SIDE_LEGS = _side_legs()
SIDE_ARMS = _rot2(["back", "back", "neutral", "fwd", "fwd", "fwd", "neutral", "back"])
SIDE_BOBS = _rot2([1, 0, 0, 0, 1, 0, 0, 0])


# --------------------------------------------------------------- tiny grid ops
def stamp(cells, grid, dy=0):
    """Paint an ASCII map's shade chars into a {(x,y): ch} dict (later wins)."""
    if grid is None:
        return
    for y, row in enumerate(grid):
        ny = y + dy
        if not 0 <= ny < SIZE:
            continue
        for x, ch in enumerate(row):
            if ch != ".":
                cells[(x, ny)] = ch


def solid(grid, dy=0):
    s = set()
    if grid is None:
        return s
    for y, row in enumerate(grid):
        ny = y + dy
        if not 0 <= ny < SIZE:
            continue
        for x, ch in enumerate(row):
            if ch != ".":
                s.add((x, ny))
    return s


def outline_of(sil):
    out = set()
    for (x, y) in sil:
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < SIZE and 0 <= ny < SIZE and (nx, ny) not in sil:
                out.add((nx, ny))
    return out


def adjacent(p, sil):
    x, y = p
    return ((x + 1, y) in sil or (x - 1, y) in sil or
            (x, y + 1) in sil or (x, y - 1) in sil)


# --------------------------------------------------------------- one animation frame
class FrameCtx:
    """Everything about one (view, frame): each required layer's cells, the mannequin
    silhouette, and the outline pixels each required layer owns."""

    def __init__(self, view, i):
        self.view = view
        front = view in ("down", "up")
        self.bob = FRONT_BOBS[i] if front else SIDE_BOBS[i]
        pants_map, shoes_map = (FRONT_LEGS if front else SIDE_LEGS)[i]

        if front:
            body_map = G.BODY if view == "down" else WK.BODY_UP
            pose_l, pose_r = FRONT_ARMS[i]
            self.body = {}
            stamp(self.body, body_map, self.bob)
            stamp(self.body, WK.ARM_POSE_L[pose_l], self.bob)
            stamp(self.body, WK.ARM_POSE_R[pose_r], self.bob)
            self.sleeves = [WK.SLEEVE_POSE_L[pose_l], WK.SLEEVE_POSE_R[pose_r]]
            self.torso_map = G.SHIRT if view == "down" else WK.SHIRT_UP
            self.arm_mask = set()   # front arms never overlap garments
        else:
            pose = SIDE_ARMS[i]
            self.body = {}
            stamp(self.body, WK.BODY_SIDE, self.bob)
            stamp(self.body, WK.SIDE_ARM_POSE[pose], self.bob)
            self.sleeves = [WK.SIDE_SLEEVE_POSE[pose]]
            self.torso_map = WK.SHIRT_SIDE
            self.arm_mask = solid(WK.SIDE_ARM_POSE[pose], self.bob)

        self.pants = {}
        stamp(self.pants, pants_map)          # legs never bob (walk.py paints them fixed)
        for p in self.arm_mask:               # the hand paints over the hip in profile
            self.pants.pop(p, None)
        self.shoes = {}
        stamp(self.shoes, shoes_map)

        self.torso = {}
        stamp(self.torso, self.torso_map, self.bob)
        torso_sil = set(self.torso)           # pre-carve: the slot's stable silhouette
        for p in self.arm_mask:               # near arm shows in FRONT of the shirt
            self.torso.pop(p, None)

        # The mannequin: every required slot's silhouette. Combo-independent (one body,
        # one pants/shoes shape per frame, tee and tank share the torso), so the outline
        # split below is valid whatever the player wears.
        sils = {"body": set(self.body), "legwear": solid(pants_map),
                "outfit": torso_sil, "footwear": set(self.shoes)}
        self.mannequin = set().union(*sils.values())
        self.rim = outline_of(self.mannequin)

        # Each composite-outline pixel goes to the TOP-most adjacent layer's sheet.
        self.rim_of = {k: set() for k in sils}
        by_z_desc = sorted(sils, key=lambda k: -Z[k])
        for p in self.rim:
            for k in by_z_desc:
                if adjacent(p, sils[k]):
                    self.rim_of[k].add(p)
                    break

    def added_rim(self, sil):
        """Outline pixels an optional layer (hair) contributes beyond the mannequin."""
        return outline_of(self.mannequin | sil) - self.rim


# Build every frame context once; all item sheets read from these.
CTX = {v: [FrameCtx(v, i) for i in range(COLS)] for v in ("down", "side", "up")}


# --------------------------------------------------------------- layer -> frame cells
def layer_frame(item, view, i):
    """Returns (cells {(x,y): shade char}, rim set) for one item in one frame."""
    ctx = CTX[view][i]
    cells, rim = {}, set()

    if item == "body":
        cells = dict(ctx.body)
        rim = ctx.rim_of["body"]
    elif item == "pants":
        cells = dict(ctx.pants)
        rim = ctx.rim_of["legwear"]
    elif item == "shoes":
        cells = dict(ctx.shoes)
        rim = ctx.rim_of["footwear"]
    elif item in ("tee", "tank"):
        cells = dict(ctx.torso)
        if item == "tee":
            for sleeve in ctx.sleeves:
                stamp(cells, sleeve, ctx.bob)
        rim = ctx.rim_of["outfit"]
    elif item in G.HAIR_STYLES:
        hair_map = {"down": G.HAIR_STYLES, "up": WK.HAIR_UP, "side": WK.HAIR_SIDE}[view][item]
        stamp(cells, hair_map, ctx.bob)
        rim = ctx.added_rim(set(cells))
    elif item == "headband":
        m = G.ACCESSORIES["headband"] if view in ("down", "up") else WK.ACC_SIDE["headband"]
        stamp(cells, m, ctx.bob)
    elif item == "glasses":
        if view != "up":  # no glasses from behind (same rule as walk.character_frames)
            m = G.ACCESSORIES["glasses"] if view == "down" else WK.ACC_SIDE["glasses"]
            stamp(cells, m, ctx.bob)
    else:
        raise KeyError(item)
    return cells, rim


def bake_sheet(item, ink=False):
    img = Image.new("RGBA", (COLS * SIZE, ROWS * SIZE), (0, 0, 0, 0))
    px = img.load()
    for view, row in ROW_OF.items():
        for i in range(COLS):
            cells, rim = layer_frame(item, view, i)
            ox, oy = i * SIZE, row * SIZE
            for (x, y), ch in cells.items():
                if ink or ch == "E":
                    px[ox + x, oy + y] = INK
                else:
                    px[ox + x, oy + y] = GRAY[ch]
            for (x, y) in rim:
                if (x, y) not in cells:
                    px[ox + x, oy + y] = OUTLINE
    return img


# --------------------------------------------------------------- Godot .import sidecar
# Same lossless / no-VRAM-compress / no-mipmap import the old cosmetics wrote — a
# VRAM-compressed import would wreck the grayscale dye ramp.
def _uid_for(res_path):
    n = int(hashlib.md5(res_path.encode()).hexdigest()[:15], 16)
    chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    s = ""
    while n:
        s = chars[n % 36] + s
        n //= 36
    return "uid://c" + (s or "0")


def import_text(res_path):
    md5 = hashlib.md5(res_path.encode()).hexdigest()
    base = res_path.rsplit("/", 1)[1]
    dest = "res://.godot/imported/%s-%s.ctex" % (base, md5)
    return (
        "[remap]\n\n"
        'importer="texture"\n'
        'type="CompressedTexture2D"\n'
        'uid="%s"\n' % _uid_for(res_path)
        + 'path="%s"\n' % dest
        + "metadata={\n\"vram_texture\": false\n}\n\n"
        "[deps]\n\n"
        'source_file="%s"\n' % res_path
        + 'dest_files=["%s"]\n\n' % dest
        + "[params]\n\n"
        "compress/mode=0\n"
        "compress/high_quality=false\n"
        "compress/lossy_quality=0.7\n"
        "compress/hdr_compression=1\n"
        "compress/normal_map=0\n"
        "compress/channel_pack=0\n"
        "mipmaps/generate=false\n"
        "mipmaps/limit=-1\n"
        "roughness/mode=0\n"
        'roughness/src_normal=""\n'
        "process/fix_alpha_border=true\n"
        "process/premult_alpha=false\n"
        "process/normal_map_invert_y=false\n"
        "process/hdr_as_srgb=false\n"
        "process/hdr_clamp_exposure=false\n"
        "process/size_limit=0\n"
        "detect_3d/compress_to=1\n"
    )


# --------------------------------------------------------------- catalog of sheets
# (slot dir, file stem, ink?) — stems match the item ids in data/cosmetics.json.
SHEETS = [
    ("body", "body", False),
    ("legwear", "pants", False),
    ("outfit", "tee", False),
    ("outfit", "tank", False),
    ("footwear", "shoes", False),
    ("hair", "short", False),
    ("hair", "long", False),
    ("hair", "spiky", False),
    ("headwear", "headband", False),
    ("accessory", "glasses", True),
]


def export_all():
    for slot, stem, ink in SHEETS:
        d = os.path.join(OUT_DIR, slot)
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, stem + ".png")
        bake_sheet(stem, ink=ink).save(path)
        res = "res://assets/cosmetics/%s/%s.png" % (slot, stem)
        with open(path + ".import", "w") as f:
            f.write(import_text(res))
        print("wrote", os.path.relpath(path, os.path.join(HERE, "..")))


# --------------------------------------------------------------- preview (dev only)
def _recolor(img, base):
    """Approximate avatar_compositor.gd's luminance->swatch bake, for eyeballing."""
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    src, dst = img.load(), out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = src[x, y]
            if a == 0:
                continue
            lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
            if lum < 0.18:
                dst[x, y] = (r, g, b, a)
                continue
            t = min(1.0, max(0.0, (lum - 0.18) / (0.95 - 0.18)))
            t = t * t * (3 - 2 * t)
            lo = tuple(int(c * 0.72) for c in base)
            hi = tuple(int(c + (255 - c) * 0.28) for c in base)
            dst[x, y] = tuple(int(lo[k] + (hi[k] - lo[k]) * t) for k in range(3)) + (255,)
    return out


def preview(path):
    """A walking default look, layered + recolored the way the runtime does it."""
    looks = [  # (item stack with swatch bases 0..255)
        [("body", "body", (198, 134, 66)), ("legwear", "pants", (95, 95, 100)),
         ("outfit", "tee", (50, 95, 160)), ("footwear", "shoes", (165, 55, 55)),
         ("hair", "short", (60, 48, 36))],
        [("body", "body", (250, 205, 168)), ("legwear", "pants", (55, 130, 75)),
         ("outfit", "tank", (200, 155, 50)), ("footwear", "shoes", (95, 95, 100)),
         ("hair", "long", (180, 50, 50)), ("headwear", "headband", (125, 80, 160)),
         ("accessory", "glasses", None)],
    ]
    pad, cell = 6, COLS * SIZE + 6
    sheet = Image.new("RGBA", (COLS * SIZE + 2 * pad, len(looks) * (ROWS * SIZE + pad) + pad),
                      (58, 58, 70, 255))
    for li, look in enumerate(looks):
        composite = Image.new("RGBA", (COLS * SIZE, ROWS * SIZE), (0, 0, 0, 0))
        for slot, stem, base in look:
            layer = Image.open(os.path.join(OUT_DIR, slot, stem + ".png")).convert("RGBA")
            if base is not None:
                layer = _recolor(layer, base)
            composite.paste(layer, (0, 0), layer)
        sheet.paste(composite, (pad, pad + li * (ROWS * SIZE + pad)), composite)
    sheet = sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST)
    sheet.save(path)
    print("wrote preview", path)


if __name__ == "__main__":
    export_all()
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
