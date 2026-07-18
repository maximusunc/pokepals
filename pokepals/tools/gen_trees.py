#!/usr/bin/env python3
"""Export the pixel-art trees as flat PNG sprites for the world.

The ART lives in tools/pixelart/trees.py (canopy lobes + derived lit-blob shading +
the shared 1px outline). This tool only bakes it into the shape the client reads:
a single bottom-anchored sprite per tree kind, dropped where TreeView already looks
for optional art.

Why this exists: TreeView already supports drop-in art -- if data/art.json's
`entities.tree` / `entities.great_tree` set `render: "sprite"` and point at an image
that exists, Scenery loads it (SpriteSlot.resolve) and TreeView draws it feet-on-the-
ground instead of the procedural circles. So "move the grove off engine circles onto
pixel art" is: bake these PNGs, then flip those two art.json entries to "sprite".

Output (res://assets/sprites/, beside player.png / companion.png):
    tree.png            great_tree.png            <- "summer", what art.json points at
    tree_pine.png       great_tree_pine.png       <- ramp swaps, ready to wire when
    tree_autumn.png     great_tree_autumn.png        the grove wants variety

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


def export_all():
    os.makedirs(OUT_DIR, exist_ok=True)
    for kind in trees.LAYOUTS:
        for variant, suffix in VARIANT_SUFFIX.items():
            name = "%s%s.png" % (kind, suffix)
            path = os.path.join(OUT_DIR, name)
            trees.make_tree(kind, variant).save(path)
            res = "res://assets/sprites/%s" % name
            with open(path + ".import", "w") as f:
                f.write(import_text(res))
            print("wrote", os.path.relpath(path, os.path.join(HERE, "..")))


def preview(path):
    trees.preview_grid().save(path)
    print("wrote preview", path)


if __name__ == "__main__":
    export_all()
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
