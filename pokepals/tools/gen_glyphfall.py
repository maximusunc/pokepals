#!/usr/bin/env python3
"""Bake Glyphfall's art: the GLYPH ATLAS its whole look is drawn from, and its few own props.

Glyphfall is the world drawn in text characters (issue #159). The world underneath is ordinary pixel art; one
shader (assets/glyph_page.gdshader, on a GlyphPage layer) redraws the finished picture as monospace characters,
choosing each character from this atlas by what is under it:

  row 0  grass     . , ' ` " ; " v      row 5  stone   . : o ° O o 0 @
  row 1  leaves    ♠ ♣ (a tree is clubs and spades)   row 6  bloom   ' * * + ✿ * ❀ ✿
  row 2  water     ~ ≈                  row 7  people  the dense letters visitors and companions are written in
  row 3  earth     . : · - =            row 8  specials: the wrong glyph (&), a cursor block, and spares
  row 4  wood      | ! I H #             rows 9-12  the alphabet the paths are written in

Each row runs dark to bright in four pairs; the shader picks the pair by brightness and one of the two by a hash
of the cell, so a field of grass is not one repeated character.

Writes (each PNG with a .import sidecar, the same recipe as the other bakers):
  assets/sprites/gf_glyphs.png            the atlas: COLS x ROWS cells of CELL_W x CELL_H px, white on clear
  data/gf_glyphs.json                     its layout (cols, rows, and each row's characters), read by GlyphPage
  assets/sprites/prop_<name>_base.png     the world's own props (see PROPS)

The font is DejaVu Sans Mono Bold (free; Bitstream Vera licence), read from the system at bake time. Only its
rendered characters are committed, so the game never needs the font or Python. Requires Pillow (tools-only).
After regenerating run `godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_glyphfall.py
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
COLS = 8
ROWS = [
    ("grass",  ". , ' ` \" ; \" v"),
    ("leaves", "♠ ♣ ♣ ♠ ♣ ♣ ♣ ♠"),
    ("water",  "~ ~ ~ ≈ ≈ ~ ≈ ~"),
    ("earth",  ". . : . : · = :"),
    ("wood",   "| ! | I I H # H"),
    ("stone",  ". : o ° O o 0 @"),
    ("bloom",  "' * * + ✿ * ❀ ✿"),
    ("people", ": ; o x % & # @"),
    ("special", "& █ ? ¶ § _ ^ ·"),
    # the alphabet the paths are written in; the last cell is the space between words
    ("letters", "a b c d e f g h"),
    ("letters", "i j k l m n o p"),
    ("letters", "q r s t u v w x"),
    ("letters", "y z , . ' - ? SPACE"),
]


def _save(img, rel):
    path = os.path.join(ROOT, rel)
    img.save(path, optimize=True)
    with open(path + ".import", "w") as f:
        f.write(import_text("res://" + rel))
    print("wrote", rel)


def glyph_atlas():
    font = ImageFont.truetype(FONT, 40)
    ascent, descent = font.getmetrics()
    atlas = Image.new("RGBA", (COLS * CELL_W, len(ROWS) * CELL_H), (255, 255, 255, 0))
    for r, (_, chars) in enumerate(ROWS):
        cells = chars.split(" ")
        assert len(cells) == COLS, "row %d needs %d characters" % (r, COLS)
        for c, ch in enumerate(cells):
            cov = Image.new("L", (CELL_W, CELL_H), 0)
            d = ImageDraw.Draw(cov)
            if ch == "SPACE":
                continue
            w = d.textlength(ch, font=font)
            # centred across the cell, sitting on a shared baseline
            d.text(((CELL_W - w) / 2.0, (CELL_H - (ascent + descent)) / 2.0), ch, font=font, fill=255)
            cell = Image.new("RGBA", (CELL_W, CELL_H), (255, 255, 255, 0))
            cell.putalpha(cov)
            atlas.paste(cell, (c * CELL_W, r * CELL_H))
    return atlas


def export_all():
    _save(glyph_atlas(), "assets/sprites/gf_glyphs.png")
    layout = {"cols": COLS, "rows": len(ROWS), "cell": [CELL_W, CELL_H],
              "row_names": [n for n, _ in ROWS], "chars": [[" " if ch == "SPACE" else ch for ch in c.split(" ")] for _, c in ROWS]}
    with open(os.path.join(ROOT, "data", "gf_glyphs.json"), "w") as f:
        f.write(json.dumps(layout, ensure_ascii=False, indent="\t") + "\n")
    print("wrote data/gf_glyphs.json")


if __name__ == "__main__":
    export_all()
