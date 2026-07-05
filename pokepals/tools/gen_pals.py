#!/usr/bin/env python3
"""Export the pixelart animal sprites as AMBIENT PAL sheets.

The ART lives in tools/pixelart (animals.py's species maps, directions.py's derived
8-direction facings, animal_motion.py's flight/trot cycles); this tool only bakes it
into the sheet shape the client's PalView reads. Change the art there, re-run this.

One sheet per species x natural color variant:

    256 px wide (8 motion frames, col 0 = idle), 32x32 cells.
    Rows = the RIGHT-handed facing family: down, down_right, right, up_right, up.
    The left family (down_left, left, up_left) is mirrored at runtime, exactly like
    directions.make_daemon_facing does.

Motion, straight from the source's animation vocabulary:
  • quadrupeds hop — the facing view lifted by walk.daemon_frames' dy cycle
    (0,-1,-2,-1 twice), baked per column.
  • the fox's RIGHT row is animal_motion's trot (stretch/stand/airborne-gather),
    phase-rotated so column 0 is the standing pose (the runtime's idle frame).
  • the bird gets an extra FLY row (animal_motion's wing-flap cycle, body rising on
    the downstroke); PalView switches to it while the bird is moving, so birds
    flutter between perches while the others amble. On the ground it hops.

data/pals.json is the client-side registry describing this layout (rows, fps,
variants, the bird's fly_row). Requires Pillow, like tools/pixelart; the PNGs and
.import sidecars are committed so the game never needs Python. After regenerating,
run `godot --headless --path pokepals --import`.

Run from anywhere:  python3 pokepals/tools/gen_pals.py [--preview out.png]
"""

import os
import sys
import hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pixelart"))

from PIL import Image  # noqa: E402

import animals          # noqa: E402
import directions       # noqa: E402
import animal_motion    # noqa: E402

SIZE = 32
COLS = 8
VIEWS = ["down", "down_right", "right", "up_right", "up"]
HOP_DY = (0, -1, -2, -1, 0, -1, -2, -1)   # walk.daemon_frames' little bounce
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "assets", "pals"))


def _shifted(img, dy):
    f = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    f.paste(img, (0, dy), img)
    return f


def _rot1(frames):
    # Start a cycle on its STAND pose so column 0 works as the idle frame.
    return frames[1:] + frames[:1]


def species_rows(species, variant):
    """The list of 8-frame rows for one sheet, in VIEWS order (+ the bird's fly row)."""
    rows = []
    for view in VIEWS:
        if species == "fox" and view == "right":
            rows.append(_rot1(animal_motion.fox_trot_frames(variant)))
        else:
            base = directions.make_daemon_facing(species, view, variant)
            rows.append([_shifted(base, dy) for dy in HOP_DY])
    if species == "bird":
        rows.append(animal_motion.bird_fly_frames(variant))
    return rows


def bake_sheet(species, variant):
    rows = species_rows(species, variant)
    sheet = Image.new("RGBA", (COLS * SIZE, len(rows) * SIZE), (0, 0, 0, 0))
    for r, frames in enumerate(rows):
        for c, f in enumerate(frames):
            sheet.paste(f, (c * SIZE, r * SIZE), f)
    return sheet


# --- Godot .import sidecar: lossless, nearest-friendly, no mipmaps (same as cosmetics).
def _uid_for(res_path):
    n = int(hashlib.md5(res_path.encode()).hexdigest()[:15], 16)
    chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    s = ""
    while n:
        s = chars[n % 36] + s
        n //= 36
    return "uid://c" + (s or "0")


def import_text(res_path):
    md5 = hashlib.md5(res_path.encode()).hexdigest()
    base = res_path.rsplit("/", 1)[1]
    dest = "res://.godot/imported/%s-%s.ctex" % (base, md5)
    return (
        "[remap]\n\n"
        'importer="texture"\n'
        'type="CompressedTexture2D"\n'
        'uid="%s"\n' % _uid_for(res_path)
        + 'path="%s"\n' % dest
        + "metadata={\n\"vram_texture\": false\n}\n\n"
        "[deps]\n\n"
        'source_file="%s"\n' % res_path
        + 'dest_files=["%s"]\n\n' % dest
        + "[params]\n\n"
        "compress/mode=0\n"
        "compress/high_quality=false\n"
        "compress/lossy_quality=0.7\n"
        "compress/hdr_compression=1\n"
        "compress/normal_map=0\n"
        "compress/channel_pack=0\n"
        "mipmaps/generate=false\n"
        "mipmaps/limit=-1\n"
        "roughness/mode=0\n"
        'roughness/src_normal=""\n'
        "process/fix_alpha_border=true\n"
        "process/premult_alpha=false\n"
        "process/normal_map_invert_y=false\n"
        "process/hdr_as_srgb=false\n"
        "process/hdr_clamp_exposure=false\n"
        "process/size_limit=0\n"
        "detect_3d/compress_to=1\n"
    )


def export_all():
    os.makedirs(OUT_DIR, exist_ok=True)
    for species, (_, ramps) in animals.SPECIES.items():
        for v in range(len(ramps)):
            path = os.path.join(OUT_DIR, "%s_%d.png" % (species, v))
            bake_sheet(species, v).save(path)
            res = "res://assets/pals/%s_%d.png" % (species, v)
            with open(path + ".import", "w") as f:
                f.write(import_text(res))
            print("wrote", os.path.relpath(path, os.path.join(HERE, "..")))


def preview(path):
    """Variant 0 of every species: all rows, all frames, upscaled for eyeballing."""
    sheets = [(sp, bake_sheet(sp, 0)) for sp in animals.SPECIES]
    pad = 6
    w = max(s.width for _, s in sheets) + 2 * pad
    h = sum(s.height + pad for _, s in sheets) + pad
    canvas = Image.new("RGBA", (w, h), (58, 58, 70, 255))
    y = pad
    for _, s in sheets:
        canvas.paste(s, (pad, y), s)
        y += s.height + pad
    canvas = canvas.resize((canvas.width * 3, canvas.height * 3), Image.NEAREST)
    canvas.save(path)
    print("wrote preview", path)


if __name__ == "__main__":
    export_all()
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
