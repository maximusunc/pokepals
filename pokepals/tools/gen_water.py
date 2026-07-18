#!/usr/bin/env python3
"""Export the pixel-art water as seamless tile PNGs for the world.

The ART lives in tools/pixelart/water.py (a seamless wave-field tile per body of water,
with the shared shade roles + top-left light). This tool only bakes it into the shape
the client reads: one small square tile per variant, dropped where WorldArt looks for
optional water art.

Why a TILE and not a whole sprite: a pond or a river can be any size, so -- unlike a tree,
which is one fixed silhouette -- water is drawn by TILING a single seamless square across
the shape (clipped to the pond circle / river rect) and scrolling it a texel at a time.
One tile is the whole surface and the whole animation.

Why this exists at all: WorldArt already supports drop-in water art -- if data/art.json's
`entities.water` / `river` / `pool` set `render: "sprite"` and name a `tile` image that
exists, WorldArt loads it (SpriteSlot.resolve) and tiles it instead of the flat filled
circle/rect. So "move the water off engine fills onto pixel art" is: bake these tiles, then
point those art.json entries at them. A missing tile silently falls back to the old fill, so
the repo and the headless smoke test stay green with zero art committed.

Output (res://assets/sprites/, beside player.png / tree_trunk.png) -- one tile per body of
water:
    water_pond.png     water_river.png     water_pool.png

Each PNG gets a committed .import sidecar (lossless, no mipmaps -- identical to the tree /
pal / cosmetic sheets), so the game never needs Python. Tiling and crispness are set by the
CanvasItem at draw time (WorldArt enables texture_repeat), not by the import. After
regenerating, run `godot --headless --path pokepals --import` so Godot rebuilds its cache.

Run from anywhere:  python3 pokepals/tools/gen_water.py [--preview out.png]
"""

import os
import sys
import hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))

import water  # noqa: E402

OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "assets", "sprites"))


# --- Godot .import sidecar: lossless, no mipmaps (the same recipe the tree / pal /
# cosmetic bakers use, so water imports exactly like the rest of the pixel art).
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
    for variant in water.RAMPS:
        _save(water.make_water_tile(variant), "water_%s.png" % variant)


def preview(path):
    water.preview_grid().save(path)
    print("wrote preview", path)


if __name__ == "__main__":
    export_all()
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
