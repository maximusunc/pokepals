#!/usr/bin/env python3
"""Bake Horizon's pixel art (tools/pixelart/horizon.py) into game assets.

Writes, each with a .import sidecar (lossless, nearest-friendly, the same recipe as the other bakers):

  assets/sprites/hz_hills.png    the ring of distant hills round the horizon (a 360 degree panorama)
  assets/sprites/hz_clouds.png   the band of clouds above it (a 360 degree panorama)

A perspective world's spec points its view block's "backdrop" at these. Requires Pillow (tools-only); the PNGs
are committed so the game never needs Python. After regenerating run `godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_horizon.py [--preview out.png]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))
sys.path.insert(0, HERE)

import horizon as art  # noqa: E402
from gen_pals import import_text  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))


def _save(img, rel):
    path = os.path.join(ROOT, rel)
    img.save(path, optimize=True)
    with open(path + ".import", "w") as f:
        f.write(import_text("res://" + rel))
    print("wrote", rel)


def main():
    hills = art.hills_panorama()
    clouds = art.clouds_panorama()
    _save(hills, "assets/sprites/hz_hills.png")
    _save(clouds, "assets/sprites/hz_clouds.png")
    if "--preview" in sys.argv:
        from PIL import Image
        out = Image.new("RGBA", (art.W, art.CLOUDS_H + art.HILLS_H), (120, 170, 228, 255))
        out.alpha_composite(clouds, (0, 0))
        out.alpha_composite(hills, (0, art.CLOUDS_H))
        dest = sys.argv[sys.argv.index("--preview") + 1]
        out.save(dest)
        print("wrote", dest)


if __name__ == "__main__":
    main()
