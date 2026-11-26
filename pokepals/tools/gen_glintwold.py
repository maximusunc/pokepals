#!/usr/bin/env python3
"""Bake Glintwold's LOW-POLY art (tools/lowpoly/glintwold.py) into game assets.

Every picture is a little 3D mesh, flat-shaded one clean colour per facet, supersampled and saved at
twice the world resolution ("@2x"); the client draws an @2x image at half size with linear filtering
(TreeView, WorldArt and PalView all honour the suffix).

Writes, each with a .import sidecar:

  assets/sprites/gw_pine_<v>_{trunk,canopy}@2x.png     low-poly pines (the world's "tree" kind)
  assets/sprites/gw_great_<v>_{trunk,canopy}@2x.png    the great faceted pine ("great_tree")
  assets/sprites/gw_round_<v>_{trunk,canopy}@2x.png    round-canopy trees, gold / rose / teal
  assets/sprites/gw_spire_<v>@2x.png                   crystal spires
  assets/sprites/gw_hill_<v>@2x.png                    hill-mounds you walk behind
  assets/sprites/gw_boulder_<v>@2x.png                 boulders
  assets/sprites/prop_<name>_base@2x.png (+ _tint)     props (the gem's tint takes the prop's colour)
  assets/pals/<species>_<v>@2x.png                     glintbuck, cobblet, foldwing (PalView sheets)
  assets/gw_shard_<0..8>.png, gw_heart_whole.png,      the Unfinished, cut into nine shards, whole,
  assets/gw_heart_shadow.png                           and its shadow on the Turning Floor
  data/gw_heartstone.json                              where each shard sits in the whole stone

Requires Pillow + numpy (tools-only). After regenerating, run `godot --headless --path pokepals --import`.
Run from anywhere:  python3 pokepals/tools/gen_glintwold.py [trees|props|creatures|heart]
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "lowpoly"))
sys.path.insert(0, HERE)

import glintwold as art  # noqa: E402
from gen_pals import import_text  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))
ASSETS = os.path.join(ROOT, "assets")
SPRITES = os.path.join(ASSETS, "sprites")
PALS = os.path.join(ASSETS, "pals")


def _save(img, folder, name):
    path = os.path.join(folder, name)
    img.save(path, optimize=True)
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(path + ".import", "w") as f:
        f.write(import_text("res://" + rel))
    print("wrote", rel)
    return "res://" + rel


def export_heart():
    whole, shards, shadow = art.heart_shards()
    fx, fy = art.HEART_W / 2, art.HEART_FEET
    out = {
        "_comment": ("The Unfinished (tools/gen_glintwold.py): one rose-quartz stone cut along its own facets "
                     "into nine shards. Images are @2x (draw at 'scale' 0.5). Every offset is in world px from "
                     "the stone's FOOT (the ground point under it) to the image's top-left; drawing all nine at "
                     "their offsets rebuilds 'whole' exactly. 'center' is the shard's visual centre from the foot, "
                     "'depth' how near the camera it sits (bigger = nearer). 'half' says whose view it answers to: "
                     "'you' shards are baked tinted toward aqua, 'companion' ones toward gold. The shadow stays put "
                     "on the floor."),
        "scale": 0.5,
        "hover": round(art.HEART_HOVER * art.HEART_SCALE, 2),
        "tints": {"you": [round(c, 3) for c in art.YOU_TINT], "companion": [round(c, 3) for c in art.COMPANION_TINT]},
        "whole": {
            "file": _save(whole, ASSETS, "gw_heart_whole.png"),
            "size": [whole.size[0] / 2, whole.size[1] / 2],
            "offset": [-fx / 2, -fy / 2],
        },
        "shadow": {
            "file": _save(shadow, ASSETS, "gw_heart_shadow.png"),
            "size": [shadow.size[0] / 2, shadow.size[1] / 2],
            "offset": [-shadow.size[0] / 4, -20.0],
        },
        "shards": [],
    }
    for i, (img, info) in enumerate(shards):
        entry = {"file": _save(img, ASSETS, "gw_shard_%d.png" % i)}
        entry.update(info)
        out["shards"].append(entry)
    path = os.path.join(ROOT, "data", "gw_heartstone.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    print("wrote data/gw_heartstone.json")


def export_all(only=None):
    os.makedirs(SPRITES, exist_ok=True)
    os.makedirs(PALS, exist_ok=True)
    if only in (None, "trees"):
        for v in art.PINE_VARIANTS:
            t, c = art.pine(v)
            _save(t, SPRITES, "gw_pine_%s_trunk@2x.png" % v)
            _save(c, SPRITES, "gw_pine_%s_canopy@2x.png" % v)
        for v in ("a", "b"):
            t, c = art.great_pine(v)
            _save(t, SPRITES, "gw_great_%s_trunk@2x.png" % v)
            _save(c, SPRITES, "gw_great_%s_canopy@2x.png" % v)
        for v in art.ROUND_VARIANTS:
            t, c = art.round_tree(v)
            _save(t, SPRITES, "gw_round_%s_trunk@2x.png" % v)
            _save(c, SPRITES, "gw_round_%s_canopy@2x.png" % v)
        for v in art.SPIRE_VARIANTS:
            _save(art.spire(v), SPRITES, "gw_spire_%s@2x.png" % v)
        for v in art.HILL_VARIANTS:
            _save(art.hill(v), SPRITES, "gw_hill_%s@2x.png" % v)
        for v in art.BOULDER_VARIANTS:
            _save(art.boulder(v), SPRITES, "gw_boulder_%s@2x.png" % v)
    if only in (None, "props"):
        for name in art.PROP_BUILDERS:
            base, tint = art.make_prop(name)
            _save(base, SPRITES, "prop_%s_base@2x.png" % name)
            if tint is not None:
                _save(tint, SPRITES, "prop_%s_tint@2x.png" % name)
    if only in (None, "creatures"):
        for species, variants in art.CREATURE_VARIANTS.items():
            for v in range(len(variants)):
                _save(art.creature_sheet(species, v), PALS, "%s_%d@2x.png" % (species, v))
    if only in (None, "heart"):
        export_heart()


if __name__ == "__main__":
    export_all(sys.argv[1] if len(sys.argv) > 1 else None)
