#!/usr/bin/env python3
"""Bake Lanternfold's pixel art (tools/pixelart/lanternfold.py) into game assets.

Writes, each with a .import sidecar (lossless, nearest-friendly, the same recipe as the other bakers):

  assets/sprites/lf_terrain.png                        the warm paper ground (5 moods side by side)
  assets/sprites/lf_details.png + data/lf_details.json fine litter lying on it (paper scraps, blades, stars)
  assets/sprites/lf_<name>_{trunk,canopy}.png          paper-cut trees in three depths (near, mid, far)
  assets/sprites/lf_great_<name>_{trunk,canopy}.png    the great trees (landmarks)
  assets/sprites/lf_understory_<name>.png              bushes and a stump
  assets/sprites/lf_pool.png                           the ink-pool's seamless still-water tile
  assets/sprites/lf_face.png                           the screen's limestone-and-paper face (greyscale, tinted warm)
  assets/sprites/prop_lf_<name>_base.png               small props, the props.py convention

Its own terrain/detail atlas, tiles and prop names (prefix lf_) mean it edits no shared art. The world's
per-world art override (server/priv/world_seeds/lanternfold.json "art") points at these. Requires Pillow
(tools-only); the PNGs are committed so the game never needs Python. After regenerating run
`godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_lanternfold.py [--preview out.png]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))
sys.path.insert(0, HERE)

import lanternfold as art  # noqa: E402
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
    _save(art.terrain_atlas(), "assets/sprites/lf_terrain.png")
    atlas, index = art.detail_atlas()
    _save(atlas, "assets/sprites/lf_details.png")
    with open(os.path.join(ROOT, "data", "lf_details.json"), "w") as f:
        f.write("{\n" + ",\n".join('\t"%s": %s' % (k, json.dumps(v)) for k, v in index.items()) + "\n}\n")
    print("wrote data/lf_details.json")
    for name, spec in art.GROVE.items():
        trunk, canopy = art.tree_parts(spec)
        _save(trunk, "assets/sprites/lf_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/lf_%s_canopy.png" % name)
    for name, spec in art.GREAT.items():
        trunk, canopy = art.tree_parts(spec)
        _save(trunk, "assets/sprites/lf_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/lf_%s_canopy.png" % name)
    for name, spec in art.UNDERSTORY.items():
        trunk, canopy = art.tree_parts(spec)
        _save(_composite(trunk, canopy), "assets/sprites/lf_understory_%s.png" % name)
    _save(art.pool_tile(), "assets/sprites/lf_pool.png")
    _save(art.face_tile(), "assets/sprites/lf_face.png")
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
