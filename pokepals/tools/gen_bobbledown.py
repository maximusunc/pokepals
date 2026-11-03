#!/usr/bin/env python3
"""Bake Bobbledown's SMOOTH art (tools/softart/bobbledown.py) into game assets.

Unlike every other baker this one is not pixel art: the images are supersampled, anti-aliased and
saved at twice the world resolution. Every file is named "@2x"; the client draws an @2x image at half
size with linear filtering (Scenery, WorldArt and PalView all honour the suffix), so the curves stay
smooth at any screen size.

Writes, each with a .import sidecar:

  assets/sprites/bd_puff_<variant>_{trunk,canopy}@2x.png    puff-trees (4 colours)
  assets/sprites/bd_great_<variant>_{trunk,canopy}@2x.png   great puffs (2 colours)
  assets/sprites/bd_<growth>_<variant>@2x.png               gumdrops, lollipop trees, bubble-stalks
  assets/sprites/prop_<name>_{base,tint,gloss}@2x.png       small props (gloss sits over the tint)
  assets/pals/<species>_<variant>@2x.png                    the native creatures, PalView sheets

Requires Pillow + numpy (tools-only). After regenerating, run `godot --headless --path pokepals --import`.
Run from anywhere:  python3 pokepals/tools/gen_bobbledown.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "softart"))
sys.path.insert(0, HERE)

import bobbledown as art  # noqa: E402
from gen_pals import import_text  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))
SPRITES = os.path.join(ROOT, "assets", "sprites")
PALS = os.path.join(ROOT, "assets", "pals")

GROWTHS = {
    "gumdrop": (art.gumdrop, list(art.GUMDROP_VARIANTS)),
    "lolli": (art.lolli_tree, list(art.LOLLI_VARIANTS)),
    "bubble_stalk": (art.bubble_stalk, list(art.STALK_VARIANTS)),
}


def _save(img, folder, name):
    path = os.path.join(folder, name)
    img.save(path, optimize=True)
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(path + ".import", "w") as f:
        f.write(import_text("res://" + rel))
    print("wrote", rel)


def export_all(only=None):
    os.makedirs(SPRITES, exist_ok=True)
    os.makedirs(PALS, exist_ok=True)
    if only in (None, "trees"):
        for v in art.PUFF_VARIANTS:
            trunk, canopy = art.puff_tree(v)
            _save(trunk, SPRITES, "bd_puff_%s_trunk@2x.png" % v)
            _save(canopy, SPRITES, "bd_puff_%s_canopy@2x.png" % v)
        for v in art.GREAT_VARIANTS:
            trunk, canopy = art.puff_tree(v, great=True)
            _save(trunk, SPRITES, "bd_great_%s_trunk@2x.png" % v)
            _save(canopy, SPRITES, "bd_great_%s_canopy@2x.png" % v)
        for name, (fn, variants) in GROWTHS.items():
            for v in variants:
                _save(fn(v), SPRITES, "bd_%s_%s@2x.png" % (name, v))
    if only in (None, "props"):
        for name in art.PROP_BUILDERS:
            base, tint, gloss = art.make_prop(name)
            _save(base, SPRITES, "prop_%s_base@2x.png" % name)
            if tint is not None:
                _save(tint, SPRITES, "prop_%s_tint@2x.png" % name)
            if gloss is not None:
                _save(gloss, SPRITES, "prop_%s_gloss@2x.png" % name)
    if only in (None, "creatures"):
        for species, variants in art.CREATURE_VARIANTS.items():
            for v in range(len(variants)):
                _save(art.creature_sheet(species, v), PALS, "%s_%d@2x.png" % (species, v))
                print("   glow", species, v, art.creature_glow(species, v))


if __name__ == "__main__":
    export_all(sys.argv[1] if len(sys.argv) > 1 else None)
