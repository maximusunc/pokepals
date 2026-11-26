# Soft art (not pixel art)

`bobbledown.py` draws **Bobbledown**, the round world: the one place in the game that breaks
from the house pixel language on purpose. Nothing here has an outline or a hard edge. Shapes are
shaded as smooth spheres and domes, with:

- a per-pixel normal;
- a key light from the upper left;
- a cool bounce light from below;
- a glossy specular spot.

Everything is supersampled (4x) and box-filtered down, then saved at **twice** the world
resolution (`@2x` files). The client draws any `@2x` image at half size with linear filtering:

- `TreeView.tex_scale`;
- `WorldArt._prop_scale`;
- a pal species with `"hd": true` in `data/pals.json`.

So the curves stay smooth on any screen.

## Requirements

- Python 3.9+
- Pillow and numpy (tools-only; the PNGs are committed, so the game never needs Python)

## Usage

```
python bobbledown.py              # bobbledown.png: every tree, growth, prop and creature sheet
python ../gen_bobbledown.py       # bake them into assets/ (+ .import sidecars); ~2 minutes
```

`gen_bobbledown.py` takes an optional `trees`, `props` or `creatures` to bake just one group.
After baking, run `godot --headless --path pokepals --import`.

## Conventions

| What | Size (@2x px) | Feet at | Notes |
|---|---|---|---|
| tree (puff-tree, gumdrop, lollipop, bubble-stalk) | 104 x 120 | row 108 | puff-trees split trunk + canopy (only the canopy sways) |
| great tree (great puff) | 208 x 244 | row 228 | trunk + canopy |
| prop | varies | 16 px above the bottom | `base`, then grayscale `tint` (x the prop's colour), then untinted `gloss` |
| creature sheet | 64 px cells | row 48 of each cell | 8 motion + 16 idle columns x 5 facings, like every pal sheet |

## Lingerlong

`lingerlong.py` draws **Lingerlong**, the marble plaza, in the same smooth `@2x` language but as
stone rather than candy: polished white marble with soft veins and a glossy sheen, LILAC shadows
(never grey), brass accents, teal palms with a pink rim light, a warm key light from the upper left
and a pink bounce from below. It reuses Bobbledown's `Canvas` and adds a small G-buffer (geometry
first, one lighting pass after) so every piece is lit the same way.

The plaza's floor is polished, so every standing sprite has a soft mirror copy of its lowest part
baked **below** its foot line. How far that line sits above the image's bottom edge is the
sprite's `foot`, written with its world size (and, for props, its layers) to
`data/ll_details.json`.

```
python ../gen_lingerlong.py       # bake everything (+ .import sidecars, ll_details.json); ~1 minute
```

It takes an optional `sprites`, `props` or `textures` to bake one group.
