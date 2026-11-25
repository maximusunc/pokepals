#!/usr/bin/env python3
"""Bake Ohmstead's line art (tools/pixelart/ohmstead.py) into game assets.

Writes, each with a .import sidecar (lossless, nearest-friendly, the same recipe as the other bakers):

  assets/sprites/oh_<name>_{trunk,canopy}.png     wireframe trees (pines, faceted ones, a ball, a cube on a stem)
  assets/sprites/oh_great_<name>_{trunk,canopy}.png  the landmarks (a lattice mast, a geodesic dome)
  assets/sprites/oh_understory_<name>.png         small wire shrubs
  assets/sprites/prop_oh_<name>_base.png          props, the props.py convention
  assets/sprites/oh_runner.png                    the runners' 4-frame trot (16x16 frames, facing right)

The ground has no art at all: it is one shader (assets/ohm_grid.gdshader). Its own prop and tree names (prefix
oh_) mean it edits no shared art. The world's per-world art override (server/priv/world_seeds/ohmstead.json
"art") points at these. Requires Pillow (tools-only); the PNGs are committed so the game never needs Python.
After regenerating run `godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_ohmstead.py [--preview out.png]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))
sys.path.insert(0, HERE)

import ohmstead as art  # noqa: E402
from gen_pals import import_text  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))


def _save(img, rel):
    path = os.path.join(ROOT, rel)
    img.save(path, optimize=True)
    with open(path + ".import", "w") as f:
        f.write(import_text("res://" + rel))
    print("wrote", rel)


def export_all():
    for name, fn in list(art.GROVE.items()) + list(art.GREAT.items()):
        trunk, canopy = fn()
        _save(trunk, "assets/sprites/oh_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/oh_%s_canopy.png" % name)
    for name, fn in art.UNDERSTORY.items():
        _save(fn(), "assets/sprites/oh_understory_%s.png" % name)
    for name, fn in art.PROP_BUILDERS.items():
        _save(fn(), "assets/sprites/prop_%s_base.png" % name)
    _save(art.runner_sheet(), "assets/sprites/oh_runner.png")


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        art.preview(sys.argv[2])
    else:
        export_all()
