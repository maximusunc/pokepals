#!/usr/bin/env python3
"""Export the pixel-art ground (tools/pixelart/ground.py) for the client.

Writes, beside the other sprites:
    assets/sprites/ground_terrain.png   the seamless terrain tiles, side by side
                                         (R = shade role 0..3, G = accent) -- read by
                                         assets/ground.gdshader through GroundLayer
    assets/sprites/ground_details.png   the scattered details (tufts, pebbles, reeds...)
    data/ground_details.json            where each detail sits in that atlas

data/art.json's "ground" entity points at these and holds the colour ramps the shader
paints the shade roles with. Change the art in tools/pixelart/ground.py, re-run this.
Requires Pillow; the PNGs + .import sidecars are committed so the game never needs
Python. After regenerating, run `godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_ground.py [--preview out.png]
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))
sys.path.insert(0, HERE)

import ground                     # noqa: E402
from gen_pals import import_text  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))


def _save(img, rel):
    path = os.path.join(ROOT, rel)
    img.save(path)
    imp = path + ".import"
    if not os.path.exists(imp):   # keep a Godot-normalized sidecar if one is already committed
        with open(imp, "w") as f:
            f.write(import_text("res://" + rel))
    print("wrote", rel)


def export_all():
    _save(ground.make_terrain_atlas(), "assets/sprites/ground_terrain.png")
    atlas, index = ground.make_detail_atlas()
    _save(atlas, "assets/sprites/ground_details.png")
    with open(os.path.join(ROOT, "data", "ground_details.json"), "w") as f:
        f.write("{\n" + ",\n".join('\t"%s": %s' % (k, json.dumps(v)) for k, v in index.items()) + "\n}\n")
    print("wrote data/ground_details.json")


if __name__ == "__main__":
    export_all()
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        ground.preview(sys.argv[2])
        print("wrote preview", sys.argv[2])
