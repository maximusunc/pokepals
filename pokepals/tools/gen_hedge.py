#!/usr/bin/env python3
"""Export the pixel-art hedge as a seamless tile PNG for the maze walls.

The ART lives in tools/pixelart/hedge.py (a seamless leafy tile in the lit-top greens). This
tool bakes it into the one image the client tiles along each hedge run. The maze is a grid, so
every run is an axis-aligned rectangle; WorldArt tiles this over the shaded front face and the
sunlit top of each wall (the front modulated darker), like water tiles across a pond.

Output: res://assets/sprites/hedge.png (+ a committed .import sidecar, identical recipe to the
water/tree/portal bakers). WorldArt uses it the moment data/art.json's `entities.hedge` names a
`tile`; a missing file falls back to the flat-green procedural hedges, so the repo and the
headless smoke test stay green. After regenerating, run `godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_hedge.py [--preview out.png]
"""

import os
import sys
import hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))

import hedge  # noqa: E402

OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "assets", "sprites"))


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
    _save(hedge.make_hedge_tile(), "hedge.png")


def preview(path):
    hedge.preview_grid().save(path)
    print("wrote preview", path)


if __name__ == "__main__":
    export_all()
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
