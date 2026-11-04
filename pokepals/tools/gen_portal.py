#!/usr/bin/env python3
"""Export the pixel-art portals: the small mossy stone ring (every world's way home) and the Vale's
grand carved arch (the Gateway).

The ART lives in tools/pixelart/portal.py. Each portal bakes three images on one canvas, so they line
up by construction (PortalView draws all three at the same anchor):

  * <name>.png        the stonework, moss and vines, in full colour (never tinted)
  * <name>_swirl.png  a sheet of FRAMES grayscale swirl frames side by side, tinted per-portal at draw
                      time with the portal's own colour (every portal's colour is data, so one sheet
                      serves them all)
  * <name>_runes.png  a white mask of the carved runes, drawn over the frame in the portal's colour
                      with a breathing alpha, so the runes glow

The breathing, rising motes, halo and the Gateway's drift through the hues stay procedural in the
client. data/art.json's `entities.portal` / `entities.gateway` name these files and the geometry the
client needs (anchor, opening); a missing file falls back to procedural drawing.

Output: res://assets/sprites/portal_ring*.png and gateway_arch*.png (+ committed .import sidecars,
the same lossless recipe as the tree / water / pal bakers).

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
    ring = portal.make_ring()
    _save(ring.frame, "portal_ring.png")
    _save(portal.make_ring_swirl(ring), "portal_ring_swirl.png")
    _save(ring.runes, "portal_ring_runes.png")
    arch = portal.make_arch()
    _save(arch.frame, "gateway_arch.png")
    _save(portal.make_arch_swirl(arch), "gateway_arch_swirl.png")
    _save(arch.runes, "gateway_arch_runes.png")
    print("geometry: ring %dx%d foot row %d, arch %dx%d foot row %d, %d swirl frames" % (
        portal.RING_W, portal.RING_H, portal.RING_ANCHOR_Y, portal.ARCH_W, portal.ARCH_H,
        portal.ARCH_ANCHOR_Y + 8, portal.FRAMES))  # the arch's steps reach 8 px below its point
    print("(art.json anchor_y = the foot row: the canvas row that lands on the ground plane)")


def preview(path):
    portal.preview_grid().save(path)
    print("wrote preview", path)


if __name__ == "__main__":
    export_all()
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
