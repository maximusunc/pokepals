#!/usr/bin/env python3
"""Bake Nocthollow's pixel art (tools/pixelart/nocthollow.py) into game assets.

Writes, each with a .import sidecar (lossless, nearest-friendly — same as the other bakers):

  assets/sprites/noct_glowcap_<variant>_{trunk,canopy}.png   the mushroom-trees (3 colours)
  assets/sprites/noct_elder_<variant>_{trunk,canopy}.png     the Lumen Elder great trees (2 colours)
  assets/sprites/noct_<growth>_<variant>.png                 tall y-sorted growths (spires, bells, stalks)
  assets/sprites/prop_<name>_base.png (+ _tint.png)          small props, the props.py convention
  assets/pals/<species>_<variant>.png                        the planet's creatures, PalView sheets

The ART lives in tools/pixelart/nocthollow.py; this tool only bakes it. The world's per-world art
override (server/priv/world_seeds/nocthollow.json "art") and data/pals.json point at these files.
Requires Pillow, like tools/pixelart; the PNGs are committed so the game never needs Python. After
regenerating, run `godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_nocthollow.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))
sys.path.insert(0, HERE)

import nocthollow as art  # noqa: E402
from gen_pals import import_text  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))
SPRITES = os.path.join(ROOT, "assets", "sprites")
PALS = os.path.join(ROOT, "assets", "pals")

GROWTHS = {
    "crystal_spire": (art.crystal_spire, ["cyan", "rose", "gold"]),
    "bell_flower": (art.bell_flower, ["blue", "pink", "lime"]),
    "spore_stalk": (art.spore_stalk, ["amber", "mint"]),
}


def _save(img, folder, name):
    path = os.path.join(folder, name)
    img.save(path)
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(path + ".import", "w") as f:
        f.write(import_text("res://" + rel))
    print("wrote", rel)


def export_all():
    os.makedirs(SPRITES, exist_ok=True)
    os.makedirs(PALS, exist_ok=True)
    for v in art.CAP_VARIANTS:
        trunk, canopy = art.glowcap_tree(v)
        _save(trunk, SPRITES, "noct_glowcap_%s_trunk.png" % v)
        _save(canopy, SPRITES, "noct_glowcap_%s_canopy.png" % v)
    for v in art.ELDER_VARIANTS:
        trunk, canopy = art.elder_tree(v)
        _save(trunk, SPRITES, "noct_elder_%s_trunk.png" % v)
        _save(canopy, SPRITES, "noct_elder_%s_canopy.png" % v)
    for name, (fn, variants) in GROWTHS.items():
        for v in variants:
            _save(fn(v), SPRITES, "noct_%s_%s.png" % (name, v))
    for name in art.PROP_BUILDERS:
        base, tint = art.make_prop(name)
        _save(base, SPRITES, "prop_%s_base.png" % name)
        if tint is not None:
            _save(tint, SPRITES, "prop_%s_tint.png" % name)
    for species, variants in art.CREATURE_VARIANTS.items():
        for v in range(len(variants)):
            _save(art.creature_sheet(species, v), PALS, "%s_%d.png" % (species, v))
            print("   glow", species, v, [round(c, 2) for c in art.creature_glow(species, v)])


if __name__ == "__main__":
    export_all()
