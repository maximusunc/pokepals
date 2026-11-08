#!/usr/bin/env python3
"""Bake Underroot's pixel art (tools/pixelart/underroot.py) into game assets.

Writes, each with a .import sidecar (lossless, nearest-friendly, the same recipe as the other bakers):

  assets/sprites/ur_terrain.png                       the cave floor (5 moods side by side)
  assets/sprites/ur_details.png + data/ur_details.json  fine litter lying on it (moss, rootlets, pebbles...)
  assets/sprites/ur_<name>_{trunk,canopy}.png         root pillars, mossy mounds, pale fungus
  assets/sprites/ur_great_<name>_{trunk,canopy}.png   the great columns (landmarks)
  assets/sprites/ur_understory_<name>.png             ferns and a stump
  assets/sprites/ur_pool.png                          the still black pool's seamless water tile
  assets/sprites/ur_root_wall.png                     the tunnel walls' seamless tangle of roots
  assets/sprites/prop_ur_<name>_{base,tint}.png       small props, the props.py convention

Its own terrain/detail atlas, tiles and prop names (prefix ur_) mean it edits no shared art. The world's
per-world art override (server/priv/world_seeds/underroot.json "art") points at these. Requires Pillow
(tools-only); the PNGs are committed so the game never needs Python. After regenerating run
`godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_underroot.py [--preview out.png]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))
sys.path.insert(0, HERE)

import underroot as art  # noqa: E402
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
    _save(art.terrain_atlas(), "assets/sprites/ur_terrain.png")
    atlas, index = art.detail_atlas()
    _save(atlas, "assets/sprites/ur_details.png")
    with open(os.path.join(ROOT, "data", "ur_details.json"), "w") as f:
        f.write("{\n" + ",\n".join('\t"%s": %s' % (k, json.dumps(v)) for k, v in index.items()) + "\n}\n")
    print("wrote data/ur_details.json")
    for name, spec in art.GROVE.items():
        trunk, canopy = art.tree_parts(spec)
        _save(trunk, "assets/sprites/ur_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/ur_%s_canopy.png" % name)
    for name, spec in art.GREAT.items():
        trunk, canopy = art.tree_parts(spec)
        _save(trunk, "assets/sprites/ur_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/ur_%s_canopy.png" % name)
    for name, spec in art.UNDERSTORY.items():
        trunk, canopy = art.tree_parts(spec)
        _save(_composite(trunk, canopy), "assets/sprites/ur_understory_%s.png" % name)
    _save(art.pool_tile(), "assets/sprites/ur_pool.png")
    _save(art.root_wall_tile(), "assets/sprites/ur_root_wall.png")
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
