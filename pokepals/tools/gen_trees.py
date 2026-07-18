#!/usr/bin/env python3
"""Export the pixel-art trees as flat PNG sprites for the world.

The ART lives in tools/pixelart/trees.py (canopy lobes + derived lit-blob shading +
the shared 1px outline). This tool only bakes it into the shape the client reads:
TWO bottom-anchored sprites per tree kind -- a stationary TRUNK and a separate
CANOPY -- dropped where TreeView looks for optional art.

Why two parts: TreeView draws the trunk fixed and offsets only the canopy by the
wind, so the tree sways from the crown while its base stays planted (a single
sprite would slide the whole trunk). Both parts share the tree's full canvas and are
bottom-anchored at the same origin, so they line up with nothing but that horizontal
canopy offset between them.

Why this exists at all: TreeView already supports drop-in art -- if data/art.json's
`entities.tree` / `entities.great_tree` set `render: "sprite"` and name `trunk` +
`canopy` images that exist, Scenery loads them (SpriteSlot.resolve) and TreeView
draws them instead of the procedural circles. So "move the grove off engine circles
onto pixel art" is: bake these PNGs, then point those two art.json entries at them.

Output (res://assets/sprites/, beside player.png / companion.png) -- per kind, a
`_trunk` and a `_canopy` PNG; "summer" is the default (no ramp suffix) that
art.json points at, the others are ramp swaps ready to wire when the grove wants
variety:
    tree_trunk.png         tree_canopy.png          great_tree_trunk.png ...
    tree_pine_trunk.png    tree_pine_canopy.png     ...
    tree_autumn_trunk.png  tree_autumn_canopy.png   ...

Each PNG gets a committed .import sidecar (lossless, nearest-neighbour friendly, no
mipmaps -- identical to the pal/cosmetic sheets), so the game never needs Python and
the headless smoke test stays green. After regenerating, run
`godot --headless --path pokepals --import` so Godot rebuilds its import cache.

Run from anywhere:  python3 pokepals/tools/gen_trees.py [--preview out.png]
"""

import os
import sys
import hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))

import trees  # noqa: E402

OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "assets", "sprites"))

# variant -> filename suffix. "summer" is the default (no suffix): it is what the
# game's art.json references, so tree.png / great_tree.png are the live sprites.
VARIANT_SUFFIX = {"summer": "", "pine": "_pine", "autumn": "_autumn"}


# --- Godot .import sidecar: lossless, nearest-friendly, no mipmaps (same recipe the
# pal and cosmetic bakers use, so trees import exactly like the rest of the pixel art).
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


def _save(img, name):
    path = os.path.join(OUT_DIR, name)
    img.save(path)
    with open(path + ".import", "w") as f:
        f.write(import_text("res://assets/sprites/%s" % name))
    print("wrote", os.path.relpath(path, os.path.join(HERE, "..")))


def export_all():
    os.makedirs(OUT_DIR, exist_ok=True)
    for kind in trees.LAYOUTS:
        for variant, suffix in VARIANT_SUFFIX.items():
            trunk_img, canopy_img = trees.make_tree_parts(kind, variant)
            _save(trunk_img, "%s%s_trunk.png" % (kind, suffix))
            _save(canopy_img, "%s%s_canopy.png" % (kind, suffix))


def preview(path):
    trees.preview_grid().save(path)
    print("wrote preview", path)


if __name__ == "__main__":
    export_all()
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
