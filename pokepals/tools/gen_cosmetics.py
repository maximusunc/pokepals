#!/usr/bin/env python3
"""Generate the per-component avatar sprite sheets — the paper-doll wardrobe.

Why this exists: like `gen_player_sprite.py`, the art is authored *here*, in code, as a
small set of named colors and composable primitives, so the whole look lives in the diff
and is tweakable (change a number, re-run). No third-party deps — each PNG is written by
hand with zlib + struct so it runs anywhere.

Every sheet follows the SAME convention the renderer already reads (see sprite_actor.gd
and EXPORT_SPEC in the design handoff, mirror-left variant):

    128 x 96 px, 32x32 cells, COLS=4 (walk cycle, col 0 = idle), ROWS=3 (down, side, up).
    Left-facing is the SIDE row drawn flipped at runtime.

The KEY discipline is shared REGISTRATION: every layer is drawn against one canonical
skeleton (see ANATOMY below) with one shared per-frame walk bob, so a hat sits on the
head and a tunic on the torso no matter which body build is underneath — they stack
pixel-perfect on the common bottom-centre origin (feet at y≈29).

Two families of layer:
  • DYE layers (body, hair) are authored in GRAYSCALE. The runtime recolors them by
    mapping luminance onto a chosen ramp color (skin tone, hair color) — see
    avatar_compositor.gd's CPU bake / palette_swap.gdshader. Keep the outline dark, paint
    the form in three grays (shade/mid/highlight).
  • FIXED layers (outfit, footwear, headwear, accessory) carry their own baked colors.

Output: assets/cosmetics/<slot>/<id>.png — one file per catalog item id (the stem).

Run from anywhere:  python3 pokepals/tools/gen_cosmetics.py [--preview <slot>:<id>]
"""

import os
import sys
import zlib
import struct
import hashlib

SIZE = 32
COLS, ROWS = 4, 3  # 4 walk frames, 3 facings (down, side, up)
FACINGS = ["down", "side", "up"]

TRANSPARENT = (0, 0, 0, 0)

# --- Shared grayscale ramp for DYE layers (body, hair) ---------------------------------
# The runtime recolor keys off luminance: near-black stays outline; the three grays map
# onto shadow / mid / highlight of the chosen ramp color. Keep these spread out so the
# recolored form still reads as shaded.
OUTLINE = (30, 22, 20, 255)   # luminance ~0.09  -> preserved as the dark outline
G_SHADE = (92, 92, 92, 255)   # luminance ~0.36  -> ramp shadow
G_MID = (150, 150, 150, 255)  # luminance ~0.59  -> ramp mid
G_HI = (208, 208, 208, 255)   # luminance ~0.82  -> ramp highlight

DYE_PALETTE = {".": TRANSPARENT, "o": OUTLINE, "d": G_SHADE, "m": G_MID, "l": G_HI}


# --- Tiny raster helpers (operate on a SIZE x SIZE list-of-lists of chars) --------------
def blank():
    return [["." for _ in range(SIZE)] for _ in range(SIZE)]


def put(g, x, y, ch):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        g[y][x] = ch


def disk(g, cx, cy, r, ch):
    r2 = r * r
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r2:
                put(g, x, y, ch)


def rect(g, x0, y0, x1, y1, ch):
    for y in range(min(y0, y1), max(y0, y1) + 1):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            put(g, x, y, ch)


def taper(g, top_y, bot_y, w_top, w_bot, ch, dy=0, cx=16, hem_dx=0):
    """A trapezoid whose half-width grows linearly top->bottom, optionally swaying at the
    hem — the shape most garments (and the torso) are built from."""
    span = max(1, bot_y - top_y)
    for y in range(top_y, bot_y + 1):
        f = (y - top_y) / span
        w = round(w_top + (w_bot - w_top) * f)
        dx = round(hem_dx * f)
        rect(g, cx - w + dx, y + dy, cx + w - 1 + dx, y + dy, ch)


def trace_outline(g, body_chars):
    """Any transparent pixel touching the silhouette becomes the dark outline 'o'."""
    out = [row[:] for row in g]
    for y in range(SIZE):
        for x in range(SIZE):
            if g[y][x] != ".":
                continue
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < SIZE and 0 <= ny < SIZE and g[ny][nx] in body_chars:
                    out[y][x] = "o"
                    break
    return out


# --- Shared skeleton ---------------------------------------------------------------------
# One canonical anatomy every layer aligns to. x is centred on 16. Values are the DOWN
# facing; side/up nudge a few features. Feet land at y≈29 so the bottom-centre origin
# matches gen_player_sprite.py.
ANATOMY = {
    "head_c": (16, 8),
    "head_r": 4.3,
    "neck_y": 12,
    "shoulder_y": 13,
    "hip_y": 21,
    "knee_y": 25,
    "ankle_y": 28,
    "foot_y": 29,
}


def walk(frame):
    """Shared per-frame walk: frames 1&3 are 'pass' poses lifted 1px; 0&2 are grounded.
    hem_dx sways the skirt/hem; foot lift alternates. Every layer applies the SAME bob so
    the whole stack rises and falls together."""
    bob = -1 if frame in (1, 3) else 0
    hem_dx = {0: 0, 1: 1, 2: 0, 3: -1}[frame]
    l_lift = 1 if frame == 1 else 0
    r_lift = 1 if frame == 3 else 0
    return bob, hem_dx, l_lift, r_lift


def side_dx(facing):
    """Profile facings shift features toward the way they look (sheet faces right)."""
    return 1 if facing == "side" else 0


# =======================================================================================
# BODY (dye layer, grayscale). Three builds differ only in shoulder/torso width and a
# touch of height, all inside the same envelope so one garment fits every build.
# =======================================================================================
def build_body(shoulder, torso_bot_half, foot_spread):
    def builder(frame, facing):
        g = blank()
        bob, hem_dx, l_lift, r_lift = walk(frame)
        a = ANATOMY
        hc = (a["head_c"][0] + side_dx(facing), a["head_c"][1] + bob)

        # legs / feet (behind torso), a plain stance with an alternating step
        lx, rx = 16 - foot_spread, 16 + foot_spread - 1
        if facing == "side":
            lx, rx = 15, 18  # one foot forward in profile
        rect(g, lx - 1, a["knee_y"] + bob, lx + 1, a["foot_y"] - l_lift + bob, "m")
        rect(g, rx - 1, a["knee_y"] + bob, rx + 1, a["foot_y"] - r_lift + bob, "m")

        # torso: shoulders down to hips
        taper(g, a["shoulder_y"] + bob, a["hip_y"] + bob, shoulder, torso_bot_half, "m",
              cx=16 + side_dx(facing))
        # a soft shaded core down the middle for form
        rect(g, 15 + side_dx(facing), a["shoulder_y"] + 1 + bob, 16 + side_dx(facing),
             a["hip_y"] - 1 + bob, "d")

        # arms at the sides
        arm_x = shoulder + 1
        rect(g, 16 - arm_x + side_dx(facing), a["shoulder_y"] + bob,
             16 - arm_x + side_dx(facing), a["hip_y"] - 2 + bob, "m")
        rect(g, 15 + arm_x + side_dx(facing), a["shoulder_y"] + bob,
             15 + arm_x + side_dx(facing), a["hip_y"] - 2 + bob, "m")

        # neck + head
        rect(g, 15 + side_dx(facing), a["neck_y"] + bob, 16 + side_dx(facing),
             a["neck_y"] + bob, "d")
        disk(g, hc[0], hc[1], a["head_r"], "m")
        # a highlight catch on the up-left of the head (matches the world light)
        disk(g, hc[0] - 1, hc[1] - 1, a["head_r"] * 0.5, "l")

        # face: eyes on down/side, hidden facing up (back of head)
        if facing == "down":
            put(g, hc[0] - 2, hc[1] + 1, "o")
            put(g, hc[0] + 2, hc[1] + 1, "o")
        elif facing == "side":
            put(g, hc[0] + 2, hc[1] + 1, "o")   # single visible eye
            put(g, hc[0] + 3, hc[1], "m")       # nose tip

        return trace_outline(g, "mdl")
    return builder


# =======================================================================================
# HAIR (dye layer, grayscale). Sits on/around the head. Bald = simply no hair item.
# =======================================================================================
def hair_short(frame, facing):
    g = blank()
    bob, *_ = walk(frame)
    a = ANATOMY
    hc = (a["head_c"][0] + side_dx(facing), a["head_c"][1] + bob)
    disk(g, hc[0], hc[1] - 1, a["head_r"] + 0.5, "m")     # a rounded cap
    disk(g, hc[0] - 1, hc[1] - 2, a["head_r"] * 0.6, "l")
    if facing != "up":
        rect(g, hc[0] - 4, hc[1] - 1, hc[0] + 3, hc[1] - 1, "m")  # fringe
        rect(g, hc[0] - 4, hc[1] + 1, hc[0] - 3, hc[1] + 3, "d")  # sideburn hint
    return trace_outline(g, "mdl")


def hair_long(frame, facing):
    g = blank()
    bob, hem_dx, *_ = walk(frame)
    a = ANATOMY
    hc = (a["head_c"][0] + side_dx(facing), a["head_c"][1] + bob)
    disk(g, hc[0], hc[1] - 1, a["head_r"] + 0.7, "m")
    disk(g, hc[0] - 1, hc[1] - 2, a["head_r"] * 0.6, "l")
    # long fall down past the shoulders, swaying with the hem
    left = hc[0] - 4
    right = hc[0] + 3
    for y in range(hc[1], a["hip_y"] - 2 + bob):
        sway = round(hem_dx * (y - hc[1]) / 8.0)
        put(g, left + sway, y, "m")
        put(g, left + 1 + sway, y, "d")
        if facing == "down":
            put(g, right + sway, y, "m")
            put(g, right - 1 + sway, y, "d")
    return trace_outline(g, "mdl")


def hair_bun(frame, facing):
    g = blank()
    bob, *_ = walk(frame)
    a = ANATOMY
    hc = (a["head_c"][0] + side_dx(facing), a["head_c"][1] + bob)
    disk(g, hc[0], hc[1] - 1, a["head_r"] + 0.4, "m")
    disk(g, hc[0] - 1, hc[1] - 2, a["head_r"] * 0.55, "l")
    bx = hc[0] + (2 if facing == "side" else 0)
    disk(g, bx, hc[1] - a["head_r"] - 1, 2.0, "m")   # the top-knot
    disk(g, bx - 1, hc[1] - a["head_r"] - 2, 1.0, "l")
    return trace_outline(g, "mdl")


# =======================================================================================
# FIXED-COLOR layers. Each carries its own palette dict (chars -> RGBA).
# =======================================================================================
def _shade(rgb, f):
    return (int(rgb[0] * f), int(rgb[1] * f), int(rgb[2] * f), 255)


def _lit(rgb, f):
    return (int(rgb[0] + (255 - rgb[0]) * f), int(rgb[1] + (255 - rgb[1]) * f),
            int(rgb[2] + (255 - rgb[2]) * f), 255)


def garment_palette(base):
    """Standard 3-tone garment palette keyed 'c' (mid), 'd' (shade), 'l' (light)."""
    return {".": TRANSPARENT, "o": OUTLINE,
            "c": base + (255,), "d": _shade(base, 0.72), "l": _lit(base, 0.28)}


def outfit_builder(base, kind):
    pal = garment_palette(base)

    def builder(frame, facing):
        g = blank()
        bob, hem_dx, *_ = walk(frame)
        a = ANATOMY
        cx = 16 + side_dx(facing)
        top = a["shoulder_y"] + bob
        if kind == "tunic":
            taper(g, top, a["hip_y"] + 2 + bob, 4, 6, "c", cx=cx, hem_dx=hem_dx)
            rect(g, cx - 4, a["hip_y"] + bob, cx + 3, a["hip_y"] + 2 + bob, "d")  # hem shade
        elif kind == "overalls":
            taper(g, top, a["hip_y"] + bob, 4, 4, "c", cx=cx)          # bib torso
            # trouser legs
            rect(g, cx - 3, a["hip_y"] + bob, cx - 1, a["ankle_y"] + bob, "c")
            rect(g, cx + 1, a["hip_y"] + bob, cx + 3, a["ankle_y"] + bob, "c")
            put(g, cx - 3, top + 1, "l")
            put(g, cx + 2, top + 1, "l")  # two straps' highlights
        elif kind == "dress":
            taper(g, top, a["knee_y"] + 1 + bob, 4, 8, "c", cx=cx, hem_dx=hem_dx)
            rect(g, cx - 7, a["knee_y"] + bob, cx + 6, a["knee_y"] + 1 + bob, "d")
        # a light catch on the up-left shoulder
        put(g, cx - 3, top, "l")
        return trace_outline(g, "cdl")
    builder._palette = pal
    return builder


def footwear_builder(base, kind):
    pal = garment_palette(base)

    def builder(frame, facing):
        g = blank()
        bob, hem_dx, l_lift, r_lift = walk(frame)
        a = ANATOMY
        lx, rx = 15, 17
        if facing == "side":
            lx, rx = 15, 18
        yb = a["foot_y"] + bob
        if kind == "boots":
            rect(g, lx - 1, a["knee_y"] + 1 + bob, lx + 1, yb - l_lift, "c")
            rect(g, rx - 1, a["knee_y"] + 1 + bob, rx + 1, yb - r_lift, "c")
        elif kind == "sandals":
            rect(g, lx - 1, yb - 1 - l_lift, lx + 1, yb - l_lift, "c")
            rect(g, rx - 1, yb - 1 - r_lift, rx + 1, yb - r_lift, "c")
        return trace_outline(g, "cdl")
    builder._palette = pal
    return builder


def headwear_builder(base, kind):
    pal = garment_palette(base)

    def builder(frame, facing):
        g = blank()
        bob, *_ = walk(frame)
        a = ANATOMY
        hc = (a["head_c"][0] + side_dx(facing), a["head_c"][1] + bob)
        if kind == "cap":
            disk(g, hc[0], hc[1] - 2, a["head_r"] + 0.6, "c")          # dome
            rect(g, hc[0] - 5, hc[1] - 2, hc[0] + 4, hc[1] - 2, "c")   # brim band
            if facing != "up":
                rect(g, hc[0] + 1, hc[1] - 2, hc[0] + 5, hc[1] - 2, "d")  # forward bill
            put(g, hc[0] - 2, hc[1] - 3, "l")
        elif kind == "bonnet":
            disk(g, hc[0], hc[1] - 1, a["head_r"] + 1.1, "c")          # rounded bonnet
            disk(g, hc[0], hc[1], a["head_r"] + 0.2, ".")             # cut the face out
            if facing == "up":
                disk(g, hc[0], hc[1] - 1, a["head_r"] + 1.1, "c")     # full back
            put(g, hc[0] - 3, hc[1] - 3, "l")
        return trace_outline(g, "cdl")
    builder._palette = pal
    return builder


def accessory_builder(base, kind):
    pal = garment_palette(base)

    def builder(frame, facing):
        g = blank()
        bob, *_ = walk(frame)
        a = ANATOMY
        hc = (a["head_c"][0] + side_dx(facing), a["head_c"][1] + bob)
        if kind == "glasses":
            if facing == "up":
                return g  # not visible from behind
            if facing == "down":
                rect(g, hc[0] - 2, hc[1] + 1, hc[0] - 1, hc[1] + 1, "c")
                rect(g, hc[0] + 1, hc[1] + 1, hc[0] + 2, hc[1] + 1, "c")
                put(g, hc[0], hc[1] + 1, "c")  # bridge
            else:
                rect(g, hc[0] + 1, hc[1] + 1, hc[0] + 2, hc[1] + 1, "c")
        elif kind == "scarf":
            y = a["neck_y"] + bob + 1
            rect(g, hc[0] - 3, y, hc[0] + 2, y, "c")
            rect(g, hc[0] - 3, y, hc[0] + 2, y + 1, "d")
            if facing != "up":
                rect(g, hc[0] + 1, y, hc[0] + 2, y + 3, "c")  # a dangling tail
        return trace_outline(g, "cdl")
    builder._palette = pal
    return builder


# --- Item registry -----------------------------------------------------------------------
# (slot, id_stem, builder, palette). id_stem is the catalog filename stem (art/<slot>/<stem>.png).
ITEMS = [
    ("body", "build_slight", build_body(shoulder=4, torso_bot_half=3, foot_spread=2), DYE_PALETTE),
    ("body", "build_average", build_body(shoulder=5, torso_bot_half=4, foot_spread=2), DYE_PALETTE),
    ("body", "build_sturdy", build_body(shoulder=6, torso_bot_half=5, foot_spread=3), DYE_PALETTE),

    ("hair", "hair_short", hair_short, DYE_PALETTE),
    ("hair", "hair_long", hair_long, DYE_PALETTE),
    ("hair", "hair_bun", hair_bun, DYE_PALETTE),

    ("outfit", "tunic", outfit_builder((92, 132, 84), "tunic"), None),
    ("outfit", "overalls", outfit_builder((74, 96, 150), "overalls"), None),
    ("outfit", "sundress", outfit_builder((176, 96, 74), "dress"), None),

    ("footwear", "boots", footwear_builder((90, 66, 50), "boots"), None),
    ("footwear", "sandals", footwear_builder((150, 120, 84), "sandals"), None),

    ("headwear", "cap", headwear_builder((90, 78, 64), "cap"), None),
    ("headwear", "bonnet", headwear_builder((196, 176, 130), "bonnet"), None),

    ("accessory", "glasses", accessory_builder((60, 54, 60), "glasses"), None),
    ("accessory", "scarf", accessory_builder((168, 84, 92), "scarf"), None),
]


# --- PNG writer (no deps) ----------------------------------------------------------------
def _chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def encode_png(width, height, rgba_rows):
    raw = bytearray()
    for row in rgba_rows:
        raw.append(0)
        for (r, g, b, a) in row:
            raw += bytes((r, g, b, a))
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (sig + _chunk(b"IHDR", ihdr)
            + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + _chunk(b"IEND", b""))


# --- Godot .import sidecar --------------------------------------------------------------
# Written next to each PNG so Godot imports these as LOSSLESS, nearest-filter, no-mipmap
# textures (matching assets/sprites/player.png.import) — critical for the DYE layers, whose
# grayscale ramp a VRAM-compressed import would wreck. The .ctex under .godot/ is still
# regenerated by 'godot --headless --path pokepals --import'; if Godot recomputes the uid/
# path it only rewrites those lines — the [params] (compress/mode=0) are honored either way.
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


def build_grids(builder):
    # grids[row][col] is a 32x32 char grid, row = facing, col = walk frame.
    return [[builder(c, FACINGS[r]) for c in range(COLS)] for r in range(ROWS)]


def sheet_rows(grids, palette):
    w, h = COLS * SIZE, ROWS * SIZE
    rows = []
    for ry in range(h):
        row = []
        r, fy = divmod(ry, SIZE)
        for rx in range(w):
            c, fx = divmod(rx, SIZE)
            row.append(palette[grids[r][c][fy][fx]])
        rows.append(row)
    return w, h, rows


def preview(grids):
    for r in range(ROWS):
        print(f"\n=== {FACINGS[r]} ===")
        for fy in range(SIZE):
            print("   ".join("".join(grids[r][c][fy]) for c in range(COLS)))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.normpath(os.path.join(here, "..", "assets", "cosmetics"))

    want = None
    if "--preview" in sys.argv:
        i = sys.argv.index("--preview")
        want = sys.argv[i + 1] if i + 1 < len(sys.argv) else None

    count = 0
    for slot, stem, builder, palette in ITEMS:
        pal = palette if palette is not None else _palette_of(builder)
        grids = build_grids(builder)
        if want == f"{slot}:{stem}":
            preview(grids)
            return
        w, h, rows = sheet_rows(grids, pal)
        out_dir = os.path.join(root, slot)
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, f"{stem}.png")
        with open(out, "wb") as fh:
            fh.write(encode_png(w, h, rows))
        res_path = f"res://assets/cosmetics/{slot}/{stem}.png"
        with open(out + ".import", "w") as fh:
            fh.write(import_text(res_path))
        count += 1
        print(f"wrote assets/cosmetics/{slot}/{stem}.png  ({w}x{h})  (+ .import)")
    if want is not None:
        print(f"(no item matched --preview {want})")
    print(f"\n{count} component sheets written.")


# Fixed-color builders close over their own palette; we stash it on the function so the
# registry can pass None and we recover it here. Set below after builder creation.
def _palette_of(builder):
    return getattr(builder, "_palette", DYE_PALETTE)


if __name__ == "__main__":
    main()
