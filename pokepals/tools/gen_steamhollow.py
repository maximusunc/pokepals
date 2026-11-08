#!/usr/bin/env python3
"""Bake Steamhollow's pixel art (tools/pixelart/steamhollow.py) into game assets.

Writes, each with a .import sidecar (lossless, nearest-friendly, the same recipe as the other bakers):

  assets/sprites/sh_terrain.png                       the damp ground (5 moods side by side)
  assets/sprites/sh_details.png + data/sh_details.json  fine litter lying on it (moss, ferns, leaves...)
  assets/sprites/sh_<name>_{trunk,canopy}.png         cedars, maples, misty broadleaves, willows
  assets/sprites/sh_great_<name>_{trunk,canopy}.png   the great trees (landmarks)
  assets/sprites/sh_understory_<name>.png             bushes and a stump
  assets/sprites/sh_onsen.png                         the hot springs' seamless milky-water tile
  assets/sprites/sh_boards.png, sh_boards_v.png       boardwalk planks (east-west / north-south)
  assets/sprites/sh_wall.png, sh_roof.png, sh_slope.png  a bathhouse's timber wall and tile roof (greyscale)
  assets/sprites/prop_sh_<name>_base.png              small props, the props.py convention

Its own terrain/detail atlas, tiles and prop names (prefix sh_) mean it edits no shared art. The world's
per-world art override (server/priv/world_seeds/steamhollow.json "art") points at these. Requires Pillow
(tools-only); the PNGs are committed so the game never needs Python. After regenerating run
`godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_steamhollow.py [--preview out.png]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))
sys.path.insert(0, HERE)

import steamhollow as art  # noqa: E402
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
    _save(art.terrain_atlas(), "assets/sprites/sh_terrain.png")
    atlas, index = art.detail_atlas()
    _save(atlas, "assets/sprites/sh_details.png")
    with open(os.path.join(ROOT, "data", "sh_details.json"), "w") as f:
        f.write("{\n" + ",\n".join('\t"%s": %s' % (k, json.dumps(v)) for k, v in index.items()) + "\n}\n")
    print("wrote data/sh_details.json")
    for name, spec in art.GROVE.items():
        trunk, canopy = art.tree_parts(spec)
        _save(trunk, "assets/sprites/sh_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/sh_%s_canopy.png" % name)
    for name, spec in art.GREAT.items():
        trunk, canopy = art.tree_parts(spec)
        _save(trunk, "assets/sprites/sh_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/sh_%s_canopy.png" % name)
    for name, spec in art.UNDERSTORY.items():
        trunk, canopy = art.tree_parts(spec)
        _save(_composite(trunk, canopy), "assets/sprites/sh_understory_%s.png" % name)
    _save(art.onsen_tile(), "assets/sprites/sh_onsen.png")
    _save(art.boards_tile(True), "assets/sprites/sh_boards.png")
    _save(art.boards_tile(False), "assets/sprites/sh_boards_v.png")
    _save(art.wall_tile(), "assets/sprites/sh_wall.png")
    _save(art.roof_tile(), "assets/sprites/sh_roof.png")
    _save(art.roof_tile(), "assets/sprites/sh_slope.png")
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
