#!/usr/bin/env python3
"""Bake Loftreach's pixel art (tools/pixelart/loftreach.py) into game assets.

Writes, each with a .import sidecar (lossless, nearest-friendly, the same recipe as the other bakers):

  assets/sprites/lr_turf.png                           the islands' sunlit turf (a seamless 128 px tile)
  assets/sprites/lr_rock.png                           the cliff faces' stratified rock (a seamless 128 px tile)
  assets/sprites/lr_details.png + data/lr_details.json fine litter lying on the turf (tufts, daisies, windflowers ...)
  assets/sprites/lr_<name>_{trunk,canopy}.png          the islands' trees (round, oak, birch, pine, blossom, fruit, gold)
  assets/sprites/lr_great_<name>_{trunk,canopy}.png    the great trees (landmarks)
  assets/sprites/lr_understory_<name>.png              bushes and a stump
  assets/sprites/lr_cloud_<a-d>.png                    the sea of cloud under the islands
  assets/sprites/lr_hicloud_<a,b>.png                  the high clouds that, from far above, make the picture
  assets/sprites/prop_lr_<name>_base.png               small props, the props.py convention

Its own tiles, atlases and prop names (prefix lr_) means it edits no shared art. The world's per-world art
override (server/priv/world_seeds/loftreach.json "art") points at these. Requires Pillow (tools-only); the PNGs
are committed so the game never needs Python. After regenerating run `godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_loftreach.py [--preview out.png]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))
sys.path.insert(0, HERE)

import loftreach as art  # noqa: E402
from gen_pals import import_text  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))


def _save(img, rel):
    path = os.path.join(ROOT, rel)
    img.save(path, optimize=True)
    with open(path + ".import", "w") as f:
        f.write(import_text("res://" + rel))
    print("wrote", rel)


def _composite(trunk, canopy):
    img = canopy.copy() if trunk is None else trunk.copy()
    if trunk is not None:
        img.alpha_composite(canopy)
    return img


def export_all():
    _save(art.turf_tile(), "assets/sprites/lr_turf.png")
    _save(art.rock_tile(), "assets/sprites/lr_rock.png")
    atlas, index = art.detail_atlas()
    _save(atlas, "assets/sprites/lr_details.png")
    with open(os.path.join(ROOT, "data", "lr_details.json"), "w") as f:
        f.write("{\n" + ",\n".join('\t"%s": %s' % (k, json.dumps(v)) for k, v in index.items()) + "\n}\n")
    print("wrote data/lr_details.json")
    for name, spec in art.GROVE.items():
        trunk, canopy = art.tree_parts(spec)
        _save(trunk, "assets/sprites/lr_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/lr_%s_canopy.png" % name)
    for name, spec in art.GREAT.items():
        trunk, canopy = art.tree_parts(spec)
        _save(trunk, "assets/sprites/lr_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/lr_%s_canopy.png" % name)
    for name, spec in art.UNDERSTORY.items():
        trunk, canopy = art.tree_parts(spec)
        _save(_composite(trunk, canopy), "assets/sprites/lr_understory_%s.png" % name)
    for name in list(art.CLOUD_LOW) + list(art.CLOUD_HIGH):
        _save(art.cloud_sprite(name), "assets/sprites/%s.png" % name)
    for name in art.PROP_BUILDERS:
        base, tint = art.make_prop(name)
        _save(base, "assets/sprites/prop_%s_base.png" % name)
        if tint is not None:
            _save(tint, "assets/sprites/prop_%s_tint.png" % name)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        art.preview(sys.argv[2])
    else:
        export_all()
