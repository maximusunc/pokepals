#!/usr/bin/env python3
"""Bake CLICKTON's brick art (tools/brickart/bricks.py) into game assets. Everything is built of studs.

Writes, each with a .import sidecar:

  assets/sprites/ck_terrain.png                      the baseplate the ground is made of (5 kinds side by side)
  assets/sprites/ck_details.png + data/ck_details.json   loose bricks lying about
  assets/sprites/ck_{wall,roof,slope,plate_stud,plate_flat,plate_road,rainbow_brick}.png
                                                     greyscale tiles the client tints per building / plate
  assets/sprites/ck_tree_<variant>_{trunk,canopy}.png, ck_great_<variant>_{trunk,canopy}.png
  assets/sprites/prop_brick_<name>_{base,tint}.png   props

Requires Pillow (tools-only). After regenerating run `godot --headless --path pokepals --import`.
Run from anywhere:  python3 pokepals/tools/gen_clickton.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "brickart"))
sys.path.insert(0, HERE)

import bricks as art  # noqa: E402
from gen_pals import import_text  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))
SPRITES = os.path.join(ROOT, "assets", "sprites")


def _save(img, rel):
    path = os.path.join(ROOT, rel)
    img.save(path, optimize=True)
    with open(path + ".import", "w") as f:
        f.write(import_text("res://" + rel))
    print("wrote", rel)


def export_all():
    os.makedirs(SPRITES, exist_ok=True)
    _save(art.terrain_atlas(), "assets/sprites/ck_terrain.png")
    atlas, index = art.detail_atlas()
    _save(atlas, "assets/sprites/ck_details.png")
    with open(os.path.join(ROOT, "data", "ck_details.json"), "w") as f:
        f.write("{\n" + ",\n".join('\t"%s": %s' % (k, json.dumps(v)) for k, v in index.items()) + "\n}\n")
    _save(art.wall_tile(), "assets/sprites/ck_wall.png")
    _save(art.stud_tile(32), "assets/sprites/ck_roof.png")
    _save(art.roof_slope_tile(), "assets/sprites/ck_slope.png")
    _save(art.stud_tile(32), "assets/sprites/ck_plate_stud.png")
    _save(art.stud_tile(32, flat=True), "assets/sprites/ck_plate_flat.png")
    _save(art.road_tile(), "assets/sprites/ck_plate_road.png")
    _save(art.rainbow_brick(), "assets/sprites/ck_rainbow_brick.png")
    for v in art.TREE_VARIANTS:
        trunk, canopy = art.make_tree(v)
        _save(trunk, "assets/sprites/ck_tree_%s_trunk.png" % v)
        _save(canopy, "assets/sprites/ck_tree_%s_canopy.png" % v)
    for v in ("green", "autumn"):
        trunk, canopy = art.make_tree(v, great=True)
        _save(trunk, "assets/sprites/ck_great_%s_trunk.png" % v)
        _save(canopy, "assets/sprites/ck_great_%s_canopy.png" % v)
    for name in art.PROPS:
        base, tint = art.make_prop(name)
        _save(base, "assets/sprites/prop_%s_base.png" % name)
        if tint is not None:
            _save(tint, "assets/sprites/prop_%s_tint.png" % name)


if __name__ == "__main__":
    export_all()
