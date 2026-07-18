"""
Pixel-art portal generator -- the shimmering doorways between worlds, in the same
hand-crafted pixel language as trees.py / water.py, but with one twist: a portal is
GRAYSCALE. Every portal in the world carries its own color (a gold sun-warmed archway,
a green hedge-gap, a purple shimmer, a blue way-home), so the baked sprite is a neutral
energy oval and the client TINTS it per-portal with `modulate` at draw time -- one sprite,
every color. (The trees bake their color in; a portal can't, because the color is data.)

Unlike a tree (lit from the top-left) a portal is pure energy, so it's shaded RADIALLY:
brightest at the core, falling to a dark rim, dithered between bands so the gradient reads
as chunky pixel steps rather than a smooth airbrush. The oval's edge feathers out with an
ordered-dither stipple (the pixel-art way to fade without anti-aliasing). The breathing
pulse and the sparks orbiting the rim stay procedural in the client (like the trees' sway),
so this bakes only the still shape.

Grayscale value maps straight onto the tint: a value-v pixel drawn with modulate=color
becomes v*color, so the white-ish core lands on the full portal hue and the dark rim on a
deep shade of it. No randomness -- the sprite is reproducible from the numbers below.
"""

from PIL import Image

# Sprite canvas + the energy oval inside it (upright: taller than wide, a standing doorway).
W, H = 28, 52
CX, CY = 13.5, 25.5
RX, RY = 12.5, 24.5

# The radial value ramp, core → rim, quantized into these chunky levels (0 dark … 1 white).
# The ordered dither below scatters pixels between adjacent levels so the banding reads as
# hand-placed pixel shading, not a gradient.
LEVELS = [0.30, 0.45, 0.62, 0.80, 1.0]

# 4x4 Bayer matrix (normalised to [0,1)) — the classic ordered-dither threshold pattern.
_BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]
BAYER = [[v / 16.0 for v in row] for row in _BAYER]


def _radius(x, y):
    """Elliptical radius: 0 at the core, 1 on the oval's edge."""
    dx = (x + 0.5 - CX) / RX
    dy = (y + 0.5 - CY) / RY
    return (dx * dx + dy * dy) ** 0.5


def _quantize(value, bx, by):
    """Ordered-dither `value` (0..1) onto the LEVELS, so transitions stipple pixel-by-pixel."""
    step = 1.0 / (len(LEVELS) - 1)
    nudged = value + (BAYER[by % 4][bx % 4] - 0.5) * step
    idx = int(round(nudged * (len(LEVELS) - 1)))
    idx = max(0, min(len(LEVELS) - 1, idx))
    return LEVELS[idx]


def make_portal():
    """The neutral (grayscale) portal energy oval, RGBA. Tint it with modulate in the client."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        for x in range(W):
            d = _radius(x, y)
            if d > 1.02:
                continue
            # a small solid bright core reads as the hot centre of the doorway; beyond it the
            # value falls core→rim, dithered into chunky levels so it reads as pixel energy
            if d < 0.22:
                value = 1.0
            else:
                value = _quantize(1.0 - 0.72 * min(d, 1.0), x, y)
            g = round(value * 255)
            if d <= 0.88:
                a = 255
            else:
                # feather the edge: a stipple that thins out toward d=1 (pixel-art fade)
                a = 255 if BAYER[y % 4][x % 4] < (1.02 - d) / 0.14 else 0
            if a:
                px[x, y] = (g, g, g, a)
    return img


def preview_grid(scale=6):
    """The neutral sprite plus a few tint swatches (the real portal colors), on a green bg."""
    tints = [
        (188, 168, 245),  # vale shimmer (purple)
        (245, 209, 128),  # sun-warmed archway (gold)
        (140, 179, 107),  # vine-shrouded / hedge (green)
        (168, 204, 245),  # way home (blue)
    ]
    cols = 1 + len(tints)
    pad = 6
    cell_w, cell_h = W + pad, H + pad
    sheet = Image.new("RGBA", (cols * cell_w + pad, cell_h + pad), (110, 148, 92, 255))
    base = make_portal()
    # neutral first
    sheet.alpha_composite(base, (pad, pad))
    for i, tint in enumerate(tints):
        tinted = Image.new("RGBA", base.size, (0, 0, 0, 0))
        tp = tinted.load()
        bp = base.load()
        for y in range(H):
            for x in range(W):
                r, g, b, a = bp[x, y]
                if a:
                    tp[x, y] = (r * tint[0] // 255, g * tint[1] // 255, b * tint[2] // 255, a)
        sheet.alpha_composite(tinted, (pad + (i + 1) * cell_w, pad))
    return sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)


if __name__ == "__main__":
    preview_grid().save("portal.png")
    print("saved portal.png")
