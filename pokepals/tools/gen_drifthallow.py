#!/usr/bin/env python3
"""Bake Drifthallow's pixel art (tools/pixelart/drifthallow.py) into game assets.

Writes, each with a .import sidecar (lossless, nearest-friendly, the same recipe as the other bakers):

  assets/sprites/dh_terrain.png                       the snow the ground is made of (5 moods side by side)
  assets/sprites/dh_details.png + data/dh_details.json  fine litter lying on it (dry tufts, rime, pebbles...)
  assets/sprites/dh_<name>_{trunk,canopy}.png         snow-laden pines, frozen birches, frosted oaks
  assets/sprites/dh_great_<name>_{trunk,canopy}.png   the great trees (landmarks)
  assets/sprites/dh_understory_<name>.png             snowy bushes and stumps
  assets/sprites/dh_ice.png                           the frozen ponds' seamless tile
  assets/sprites/prop_<name>_base.png                 small props, the props.py convention

Its own terrain/detail atlas and prop names (prefix dh_ / unique prop names) mean it edits no shared
art. The world's per-world art override (server/priv/world_seeds/drifthallow.json "art") points at
these. Requires Pillow (tools-only); the PNGs are committed so the game never needs Python. After
regenerating run `godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_drifthallow.py [--preview out.png]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))
sys.path.insert(0, HERE)

import drifthallow as art  # noqa: E402
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
    _save(art.terrain_atlas(), "assets/sprites/dh_terrain.png")
    atlas, index = art.detail_atlas()
    _save(atlas, "assets/sprites/dh_details.png")
    with open(os.path.join(ROOT, "data", "dh_details.json"), "w") as f:
        f.write("{\n" + ",\n".join('\t"%s": %s' % (k, json.dumps(v)) for k, v in index.items()) + "\n}\n")
    print("wrote data/dh_details.json")
    for name, spec in art.GROVE.items():
        trunk, canopy = art.tree_parts(spec)
        _save(trunk, "assets/sprites/dh_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/dh_%s_canopy.png" % name)
    for name, spec in art.GREAT.items():
        trunk, canopy = art.tree_parts(spec)
        _save(trunk, "assets/sprites/dh_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/dh_%s_canopy.png" % name)
    for name, spec in art.UNDERSTORY.items():
        trunk, canopy = art.tree_parts(spec)
        _save(_composite(trunk, canopy), "assets/sprites/dh_understory_%s.png" % name)
    _save(art.ice_tile(), "assets/sprites/dh_ice.png")
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
