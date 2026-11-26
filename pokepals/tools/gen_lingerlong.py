#!/usr/bin/env python3
"""Bake Lingerlong's SMOOTH art (tools/softart/lingerlong.py) into game assets.

Like Bobbledown's baker, this is not pixel art: images are supersampled, anti-aliased and saved at twice
the world resolution ("@2x"; the client draws an @2x image at half size with linear filtering). Every
standing sprite carries a soft mirror reflection baked below its foot line (the plaza's floor is
polished); how far the foot line sits above the image's bottom edge is written to data/ll_details.json.

Writes, each with a .import sidecar:

  assets/sprites/ll_<thing>@2x.png                  tall, y-sorted sprites (palms as trunk + canopy, the
                                                    great palm, columns, the arch and its two doorway views,
                                                    busts and their plinth, lamps, the parasol, the fountain)
  assets/sprites/ll_<prop>_{base,tint,gloss}@2x.png low props (tint is grayscale, x the instance colour;
                                                    gloss is untinted and sits on top)
  assets/sprites/ll_{marble,caustics,clouds}.png    tileable shader textures (NOT @2x)
  data/ll_details.json                              per sprite: foot, w, h (world px) and, for props, layers

ll_details.json is keyed by file name without "@2x.png" (props by their bare name, e.g. "ll_bench", whose
files are ll_bench_<layer>@2x.png). `w` and `h` are the whole image in world px (half its pixel size); `foot`
is world px from the image's bottom edge up to the foot line, where the thing meets the floor. The fountain's
two images instead put that line through the fountain's CENTRE ("anchor": "center"), so both draw at the
fountain's centre point; the top is drawn y-sorted over the basin.

Requires Pillow + numpy (tools-only). After regenerating, run `godot --headless --path pokepals --import`.
Run from anywhere:  python3 pokepals/tools/gen_lingerlong.py   (optionally: sprites | props | textures)
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "softart"))
sys.path.insert(0, HERE)

import lingerlong as art  # noqa: E402
from gen_pals import import_text  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))
SPRITES = os.path.join(ROOT, "assets", "sprites")
DETAILS = os.path.join(ROOT, "data", "ll_details.json")


def _save(img, name):
    path = os.path.join(SPRITES, name)
    img.save(path, optimize=True)
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(path + ".import", "w") as f:
        f.write(import_text("res://" + rel))
    print("wrote", rel)


def _entry(img, foot):
    return {"foot": foot, "w": img.width // 2, "h": img.height // 2}


def export_all(only=None):
    os.makedirs(SPRITES, exist_ok=True)
    details = {}
    if os.path.exists(DETAILS):
        with open(DETAILS) as f:
            details = json.load(f)
    if only in (None, "sprites"):
        for stem, (img, foot) in art.tall_sprites().items():
            _save(img, stem + "@2x.png")
            details[stem] = _entry(img, foot)
        details["ll_fountain_base"]["anchor"] = "center"
        details["ll_fountain_top"]["anchor"] = "center"
        # where the light sits, in world px above the foot line (for the world's prop lights)
        for stem in ("ll_lamp", "ll_lamp_lit"):
            details[stem]["light_y"] = art.LAMP_LIGHT_Y
        details["ll_arch"]["door"] = {"w": art.ARCH_DOOR_W, "h": art.ARCH_DOOR_H}
    if only in (None, "props"):
        for name in art.PROPS:
            base, tint, gloss, layers = art.make_prop(name)
            _save(base, "ll_%s_base@2x.png" % name)
            if tint is not None:
                _save(tint, "ll_%s_tint@2x.png" % name)
            if gloss is not None:
                _save(gloss, "ll_%s_gloss@2x.png" % name)
            details["ll_" + name] = dict(_entry(base, art.FOOT_PROP // 2), layers=layers)
        details["ll_table_set"]["light_y"] = art.TABLE_LIGHT_Y
    if only in (None, "textures"):
        _save(art.tex_marble(), "ll_marble.png")
        _save(art.tex_caustics(), "ll_caustics.png")
        _save(art.tex_clouds(), "ll_clouds.png")
    with open(DETAILS, "w") as f:
        json.dump(dict(sorted(details.items())), f, indent="\t")
        f.write("\n")
    print("wrote", os.path.relpath(DETAILS, ROOT))


if __name__ == "__main__":
    export_all(sys.argv[1] if len(sys.argv) > 1 else None)
