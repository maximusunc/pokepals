#!/usr/bin/env python3
"""Export the pixel-art portal as a single grayscale sprite for the world.

The ART lives in tools/pixelart/portal.py (a radial, dithered energy oval, shaded neutral).
This tool only bakes it into the shape the client reads: one PNG the client draws tinted.

Why grayscale / why one sprite: every portal in the world carries its own color (a gold
sun-warmed archway, a green hedge-gap, a purple shimmer, a blue way-home — it's data on the
prop). So the sprite is a neutral energy oval and WorldArt tints it per-portal with `modulate`
at draw time. One baked sprite serves every portal color. The breathing pulse and the sparks
orbiting the rim stay procedural in WorldArt (like the trees' sway), so this bakes only the
still shape.

Why this exists at all: WorldArt already supports drop-in art. If data/art.json's
`entities.portal` sets `render: "sprite"` and names a `sprite` image that exists, WorldArt
draws it (tinted) instead of the procedural shimmering ovals; a missing file silently falls
back to the procedural draw, so the repo and the headless smoke test stay green with no art.

Output: res://assets/sprites/portal.png (+ a committed .import sidecar, identical recipe to
the tree/water/pal bakers, so the game never needs Python). After regenerating, run
`godot --headless --path pokepals --import` so Godot rebuilds its import cache.

Run from anywhere:  python3 pokepals/tools/gen_portal.py [--preview out.png]
"""

import os
import sys
import hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))

import portal  # noqa: E402

OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "assets", "sprites"))


# --- Godot .import sidecar: lossless, no mipmaps (the same recipe the tree / water / pal
# bakers use, so the portal imports exactly like the rest of the pixel art).
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
    _save(portal.make_portal(), "portal.png")


def preview(path):
    portal.preview_grid().save(path)
    print("wrote preview", path)


if __name__ == "__main__":
    export_all()
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
