# Low-poly art (flat-shaded meshes)

`lowpoly.py` is a small renderer for **Glintwold**, the faceted world. It builds real little 3D
meshes and draws each triangle in one clean colour. There are no outlines, no gradients inside a
facet and no dither. The pieces:

- **Meshes:** cones, stacked cone tiers, prisms and frustums, lathed solids, crystals, low icospheres
  (20 or 80 faces) with seeded jitter, boxes, and flat double-sided panels (wings, paper folds).
  Each face remembers its primitive's centre, so its outward normal survives jitter and transforms.
- **Camera:** one fixed orthographic camera, 40 degrees above the horizon, looking north. That matches
  the game's top-down 3/4 view: a ground length shows about 0.64 as tall, an upright one about 0.77.
- **Shading:** each facet's normal against a light from the upper left picks ONE colour from a short
  ramp (darkest first). A `Split` material picks a ramp by the normal instead: grass on the tops of
  hills and moss on stones, stone on the steep sides.
- **Shadows:** flat and hard-edged, the mesh projected onto the ground toward the lower right, in
  `#3A4A6B` at 18%.
- **Output:** a depth buffer at 4x supersampling, box-filtered down, saved at **twice** the world
  resolution (`@2x`). The client draws an @2x image at half size with linear filtering.

`glintwold.py` builds the world's things from those meshes. `glintwold_art.json` is the part of
the world spec's `art` block that points at them; the world generator merges it with
`glintwold_look.json` (ground, water, actors, day cycle).

## Requirements

- Python 3.9+
- Pillow and numpy (tools-only; the PNGs are committed, so the game never needs Python)

## Usage

```
python glintwold.py [out.png]     # a contact sheet of everything (default glintwold.png)
python ../gen_glintwold.py        # bake into assets/ (+ .import sidecars) and data/gw_heartstone.json; ~25 s
```

`gen_glintwold.py` takes an optional `trees`, `props`, `creatures` or `heart` to bake one group.
After baking, run `godot --headless --path pokepals --import`.

## Conventions

| What | Size (@2x px) | Feet at | Notes |
|---|---|---|---|
| pine, round tree (`tree`, `gw_round`) | 104 x 150 | row 138 | trunk + canopy layers; only the canopy sways |
| great pine (`great_tree`) | 232 x 380 | row 364 | trunk + canopy |
| crystal spire (`gw_spire`) | 120 x 230 | row 218 | one sprite, no sway |
| hill (`gw_hill`) | 380 x 250 | row 238 | the feet are its FRONT edge: the mound lies north of them |
| boulder (`gw_boulder`) | 72 x 64 | row 52 | |
| prop | varies | 16 px above the bottom | `base`, plus a grayscale `tint` for `gw_gem` (coloured by the prop) |
| creature sheet | 64 px cells | row 48 of each cell | 8 motion + 16 idle columns x 5 facings, like every pal sheet |

Creatures are posed by turning the same mesh to each facing, so all five rows agree.

## World sizes, for laying a world out

In world px (half the image size). Every tree kind collides with the spec's `collision.tree_radius`.

- `tree` (pines): about 30-36 wide, 55-65 tall. Radius 8 is right.
- `great_tree`: about 85 wide, 165 tall. `great_tree_radius` 16.
- `gw_round`: about 30-38 wide, 45-55 tall. Radius 8.
- `gw_spire`: about 45-55 wide, 60-70 tall. Radius 8 (10 for a roomier feel).
- `gw_boulder`: about 27 wide, 20 tall. Radius 8 is a little tight; 10-12 if it is a prop instead.
- `gw_hill`: about 145-175 wide and 75-95 tall. Its tree point is the front edge; the mound covers roughly 85 px
  either side and up to 55 px north of it. The tree radius covers only the front centre, so add a
  solid for the rest, for example a `fences` segment (fences draw nothing) from (x-70, y-26) to
  (x+70, y-26) with thickness 44.
- The Unfinished: about 100 wide and 175 tall on screen, hanging 15 px over its foot.

## The Unfinished

`heart_mesh()` is ONE stone. It is drawn once, then every visible face is given to one of nine
shards (Voronoi cells of nine seeds laid 2, 3, 2, 2 across the silhouette), so the shards are whole
facets and fit back together exactly. `data/gw_heartstone.json` lists each shard's image, size, its
offset from the stone's foot, its centre and depth, and whose half it is (`you` or `companion`,
alternating so each half is spread over the stone). The shard images are baked faintly tinted toward
their half's colour; `gw_heart_whole.png` is untinted. `gw_heart_shadow.png` stays on the floor.
