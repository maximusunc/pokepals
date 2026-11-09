#!/usr/bin/env python3
"""Bake Thimblewick's pixel art (tools/pixelart/thimblewick.py) into game assets.

Writes, each with a .import sidecar (lossless, nearest-friendly, the same recipe as the other bakers):

  assets/sprites/tw_terrain.png                        the garden floor (5 moods side by side)
  assets/sprites/tw_details.png + data/tw_details.json fine litter lying on it (blades, petals, crumbs...)
  assets/sprites/tw_<flower>_{trunk,canopy}.png        the tall flower stalks (they stand like trees)
  assets/sprites/tw_clover<N>_{trunk,canopy}.png       clover leaves you could shelter under
  assets/sprites/tw_great_<name>_{trunk,canopy}.png    the great sunflowers (landmarks)
  assets/sprites/tw_grass<N>.png                       whole-sprite grass clumps
  assets/sprites/tw_picket_<style>_<N>.png             the fence's pickets (a missing one is a gap)
  assets/sprites/tw_understory_<name>.png              leaf rosettes and a toadstool
  assets/sprites/tw_tea.png                            the teacup pond's seamless tile
  assets/sprites/prop_<name>_base.png                  props, the props.py convention

Its own terrain/detail atlas and names (prefix tw_ / unique prop names) mean it edits no shared art. The
world's per-world art override (server/priv/world_seeds/thimblewick.json "art") points at these. Requires
Pillow (tools-only); the PNGs are committed so the game never needs Python. After regenerating run
`godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_thimblewick.py [--preview out.png]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))
sys.path.insert(0, HERE)

import thimblewick as art  # noqa: E402
from gen_pals import import_text  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))


def _save(img, rel):
    path = os.path.join(ROOT, rel)
    img.save(path, optimize=True)
    with open(path + ".import", "w") as f:
        f.write(import_text("res://" + rel))
    print("wrote", rel)


def export_all():
    _save(art.terrain_atlas(), "assets/sprites/tw_terrain.png")
    atlas, index = art.detail_atlas()
    _save(atlas, "assets/sprites/tw_details.png")
    with open(os.path.join(ROOT, "data", "tw_details.json"), "w") as f:
        f.write("{\n" + ",\n".join('\t"%s": %s' % (k, json.dumps(v)) for k, v in index.items()) + "\n}\n")
    print("wrote data/tw_details.json")
    for name in art.FLOWERS:
        trunk, canopy = art.flower_stalk(name)
        _save(trunk, "assets/sprites/tw_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/tw_%s_canopy.png" % name)
    for v in sorted(set(art.CLOVERS)):
        trunk, canopy = art.clover(v)
        _save(trunk, "assets/sprites/tw_clover%d_trunk.png" % v)
        _save(canopy, "assets/sprites/tw_clover%d_canopy.png" % v)
    for name in art.GREAT:
        trunk, canopy = art.sunflower(name)
        _save(trunk, "assets/sprites/tw_great_%s_trunk.png" % name)
        _save(canopy, "assets/sprites/tw_great_%s_canopy.png" % name)
    for v in art.GRASSES:
        _save(art.grass_clump(v), "assets/sprites/tw_grass%d.png" % v)
    for style, i in art.PICKETS:
        _save(art.picket(style, i), "assets/sprites/tw_picket_%s_%d.png" % (style, i))
    for name, fn in art.UNDERSTORY.items():
        _save(fn(), "assets/sprites/tw_understory_%s.png" % name)
    _save(art.tea_tile(), "assets/sprites/tw_tea.png")
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
