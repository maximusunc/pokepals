#!/usr/bin/env python3
"""Bake the loading screen: the three things you see before the world appears, made to look like ONE
continuous screen.

  A. the WEB page that shows while the browser downloads the game (web/shell.html, a Godot "custom
     HTML shell"); a fox trots in place over a little gold progress path
  B. the BOOT SPLASH the engine shows while it starts, before any of our code runs
     (assets/loading/boot_splash.png): a still image, so the fox stands
  C. the connection gate (scripts/presentation/lobby.gd), drawn live in Godot: the fox trots again
     while we connect

All three share one background, one Silkscreen wordmark and one fox (fox_0's right-facing row from
the pal sheets), laid out on the game's 640x360 canvas at the same spots, so each hand-off is seamless.
The layout numbers below are mirrored in lobby.gd (search LOADING LAYOUT); keep the two in step.

Outputs (committed, like the other bakes):
  * assets/loading/boot_splash.png (+ .import)   the splash, 1280x720 (the canvas at 2x)
  * assets/loading/wordmark.png (+ .import)      the wordmark at 1x, for reference / reuse
  * web/shell.html                               the HTML shell, with the wordmark and the fox strip
                                                 inlined as data URIs so it needs no extra files

Run from anywhere:  python3 pokepals/tools/gen_loading.py
"""
import base64
import hashlib
import io
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))

FOX_SHEET = os.path.join(ROOT, "assets", "pals", "fox_0.png")
FONT = os.path.join(ROOT, "assets", "fonts", "Silkscreen-Regular.ttf")
OUT_DIR = os.path.join(ROOT, "assets", "loading")
SHELL_TEMPLATE = os.path.join(HERE, "loading", "shell_template.html")
SHELL_OUT = os.path.join(ROOT, "web", "shell.html")

# --- the shared look (mirrored in lobby.gd) ---------------------------------------------------
BG = (27, 21, 16)            # #1b1510, a deep warm ink (the UiStyle INK family, darkened)
PAPER = (244, 236, 218)      # UiStyle.PAPER, the wordmark
GOLD = (223, 165, 62)        # UiStyle.GOLD, the progress path
CANVAS = (640, 360)          # the game's base viewport
WORDMARK_TEXT = "KITHBOUND"
WORDMARK_SIZE = 16           # Silkscreen is drawn on an 8px grid; 16 keeps it pixel-crisp
WORDMARK_SPACING = 1
WORDMARK_TOP = 106           # y of the wordmark's box on the canvas
FOX_TOP = 132                # y of the fox's 64px box
FOX_SCALE = 2                # 32px cell -> 64px
SPLASH_SCALE = 2             # the splash PNG is the canvas at 2x (1280x720)

# --- the fox sheet (data/pals.json) -----------------------------------------------------------
CELL = 32
ROW_RIGHT = 2
TROT_FRAMES = 8              # move columns 0..7
STAND_COL = 8                # the first idle-loop column: the calm standing pose
FEET_ROW = 27                # the last row of the fox's feet inside its 32px cell
SHADOW_W = 34


def shadow_center_y():
    """Canvas y of the shade's centre: right under the fox's feet."""
    return FOX_TOP + FEET_ROW * FOX_SCALE


def wordmark():
    """The wordmark at 1x, no anti-aliasing, letter-spaced like UiFonts.pixel(false, 1)."""
    font = ImageFont.truetype(FONT, WORDMARK_SIZE)
    widths = [font.getbbox(ch)[2] if ch != " " else WORDMARK_SIZE // 2 for ch in WORDMARK_TEXT]
    w = sum(widths) + WORDMARK_SPACING * (len(WORDMARK_TEXT) - 1)
    h = WORDMARK_SIZE + 4
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.fontmode = "1"
    x = 0
    for ch, cw in zip(WORDMARK_TEXT, widths):
        # a 1px warm drop shadow, like the lobby title's
        d.text((x, 1), ch, font=font, fill=(20, 14, 8, 140))
        d.text((x, 0), ch, font=font, fill=PAPER + (255,))
        x += cw + WORDMARK_SPACING
    return im.crop(im.getbbox())


def fox_cell(sheet, col):
    return sheet.crop((col * CELL, ROW_RIGHT * CELL, (col + 1) * CELL, (ROW_RIGHT + 1) * CELL))


def fox_strip(sheet):
    """The 8 trot frames side by side (256x32), for the web page's CSS sprite animation."""
    strip = Image.new("RGBA", (CELL * TROT_FRAMES, CELL), (0, 0, 0, 0))
    for i in range(TROT_FRAMES):
        strip.paste(fox_cell(sheet, i), (i * CELL, 0))
    return strip


def shadow(canvas, cx, y, w):
    """A soft little oval of shade under the fox's feet, in solid pixels (no blur). Drawn on its own
    layer and composited, so it darkens the background rather than replacing it."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse((cx - w // 2, y - 2, cx + w // 2, y + 2), fill=(0, 0, 0, 70))
    canvas.alpha_composite(layer)


def splash(mark, sheet):
    w, h = CANVAS
    canvas = Image.new("RGBA", (w, h), BG + (255,))
    canvas.alpha_composite(mark, ((w - mark.width) // 2, WORDMARK_TOP))
    fox = fox_cell(sheet, STAND_COL).resize((CELL * FOX_SCALE, CELL * FOX_SCALE), Image.NEAREST)
    shadow(canvas, w // 2, shadow_center_y(), SHADOW_W)
    canvas.alpha_composite(fox, ((w - fox.width) // 2, FOX_TOP))
    return canvas.convert("RGB").resize((w * SPLASH_SCALE, h * SPLASH_SCALE), Image.NEAREST)


def data_uri(im):
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


# --- Godot .import sidecar: the same lossless, no-mipmap recipe as the other pixel-art bakers.
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


def save_png(im, name):
    path = os.path.join(OUT_DIR, name)
    im.save(path, "PNG", optimize=True)
    res = "res://assets/loading/" + name
    with open(path + ".import", "w") as f:
        f.write(import_text(res))
    print("wrote", os.path.relpath(path, ROOT))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(SHELL_OUT), exist_ok=True)
    sheet = Image.open(FOX_SHEET).convert("RGBA")
    mark = wordmark()
    save_png(mark, "wordmark.png")
    save_png(splash(mark, sheet), "boot_splash.png")

    with open(SHELL_TEMPLATE) as f:
        html = f.read()
    subs = {
        "__BG__": "#%02x%02x%02x" % BG,
        "__PAPER__": "#%02x%02x%02x" % PAPER,
        "__GOLD__": "#%02x%02x%02x" % GOLD,
        "__WORDMARK_SRC__": data_uri(mark),
        "__WORDMARK_W__": str(mark.width),
        "__WORDMARK_H__": str(mark.height),
        "__WORDMARK_TOP__": str(WORDMARK_TOP),
        "__FOX_SRC__": data_uri(fox_strip(sheet)),
        "__FOX_TOP__": str(FOX_TOP),
        "__SHADOW_TOP__": str(shadow_center_y() - 2),
        "__SHADOW_W__": str(SHADOW_W),
        "__FOX_FRAMES__": str(TROT_FRAMES),
    }
    for k, v in subs.items():
        html = html.replace(k, v)
    assert "__" not in html.replace("__proto__", ""), "unfilled placeholder in shell template"
    with open(SHELL_OUT, "w") as f:
        f.write(html)
    print("wrote", os.path.relpath(SHELL_OUT, ROOT))


if __name__ == "__main__":
    main()
