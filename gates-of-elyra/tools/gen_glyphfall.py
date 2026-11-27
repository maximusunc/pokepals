#!/usr/bin/env python3
"""Bake Glyphfall's GLYPH ATLAS: every character the world is written in, as one image.

Glyphfall is the world drawn in text characters (issue #159). One shader (assets/glyph_page.gdshader, on a
GlyphPage layer) writes the page a character cell at a time, and every character it can write comes from this
atlas: the grass's tufts, the water's waves, the letters the paths are written in, the dense letters visitors
are set in, and every character used by the small pictures ("stamps") that trees and props are drawn as
(tools/gen_glyphfall_world.py authors those; a character it uses must be in CHARS below, and it checks).

Writes (the PNG with a .import sidecar, the same recipe as the other bakers):
  assets/sprites/gf_glyphs.png            the atlas: COLS columns of CELL_W x CELL_H px cells, white on clear
  data/gf_glyphs.json                     its layout: cols, rows, cell size, and `chars` (place 0 is the space)

The font is DejaVu Sans Mono Bold (free; Bitstream Vera licence), read from the system at bake time. Only its
rendered characters are committed, so the game never needs the font or Python. Requires Pillow (tools-only).
After regenerating run `godot --headless --path gates-of-elyra --import`.

Run from anywhere:  python3 gates-of-elyra/tools/gen_glyphfall.py
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_pals import import_text  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))
FONT = os.environ.get("GLYPH_FONT", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf")

CELL_W, CELL_H = 32, 48          # one character, 4x the 8 x 12 world px it is drawn at
COLS = 16
# Place 0 is the space. Then all of printable ASCII, then the few others the world is drawn with.
CHARS = [" "] + [chr(c) for c in range(33, 127)] + list("♣♠▲║│─┌┐└┘╔═╗╚╝╵╨☼→✿❀Ω•≈·°◊")
JOINED = set("║│─┌┐└┘╔═╗╚╝╵╨")   # line-drawing characters, which must reach the edges of their cell
assert len(CHARS) == len(set(CHARS)) and len(CHARS) <= 255


def _save(img, rel):
    path = os.path.join(ROOT, rel)
    img.save(path, optimize=True)
    with open(path + ".import", "w") as f:
        f.write(import_text("res://" + rel))
    print("wrote", rel)


def glyph_atlas():
    font = ImageFont.truetype(FONT, 40)
    ascent, descent = font.getmetrics()
    def ink(ch):
        im = Image.new("L", (CELL_W * 2, CELL_H * 2), 0)
        ImageDraw.Draw(im).text((8, 8), ch, font=font, fill=255)
        return im.tobytes()

    missing = ink("\uffff")   # what the font draws for a character it does not have
    rows = (len(CHARS) + COLS - 1) // COLS
    atlas = Image.new("RGBA", (COLS * CELL_W, rows * CELL_H), (255, 255, 255, 0))
    for i, ch in enumerate(CHARS):
        if ch == " ":
            continue
        assert ink(ch) != missing, "the font has no %r" % ch
        cov = Image.new("L", (CELL_W, CELL_H), 0)
        d = ImageDraw.Draw(cov)
        w = d.textlength(ch, font=font)
        # centred across the cell, sitting on a shared baseline
        d.text(((CELL_W - w) / 2.0, (CELL_H - (ascent + descent)) / 2.0), ch, font=font, fill=255)
        if ch in JOINED:
            # a line-drawing character is drawn in the font's own narrower cell and stretched to ours, so
            # the lines of neighbouring cells meet
            aw = int(round(w))
            own = Image.new("L", (aw, CELL_H), 0)
            ImageDraw.Draw(own).text((0, (CELL_H - (ascent + descent)) / 2.0), ch, font=font, fill=255)
            cov = own.resize((CELL_W, CELL_H), Image.LANCZOS)
        cell = Image.new("RGBA", (CELL_W, CELL_H), (255, 255, 255, 0))
        cell.putalpha(cov)
        atlas.paste(cell, ((i % COLS) * CELL_W, (i // COLS) * CELL_H))
    return atlas, rows


def export_all():
    atlas, rows = glyph_atlas()
    _save(atlas, "assets/sprites/gf_glyphs.png")
    layout = {"cols": COLS, "rows": rows, "cell": [CELL_W, CELL_H], "chars": CHARS}
    with open(os.path.join(ROOT, "data", "gf_glyphs.json"), "w") as f:
        f.write(json.dumps(layout, ensure_ascii=False, indent="\t") + "\n")
    print("wrote data/gf_glyphs.json (%d characters)" % len(CHARS))


if __name__ == "__main__":
    export_all()
