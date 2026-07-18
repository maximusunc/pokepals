# Pixel Character & Daemon Generator

A procedural pixel-art system for a 2D top-down game: customizable player
characters (paper-doll layers + palette swaps), daemon companions in the
spirit of His Dark Materials (fixed appearance, multiple animal forms),
8-frame walk cycles, 8-directional facing, and animal movement (bird
wing-flap flight, fox trot).

Everything is generated from small, hand-editable ASCII pixel maps.
No AI generation, no external art -- every pixel is deliberate, and every
animation frame is *derived* from shared maps so frames can never drift
out of alignment.

## Requirements

- Python 3.9+
- Pillow (`pip install pillow`)

All five modules must live in the same directory (they import each other).
Run any module directly to regenerate its preview images into the current
directory:

```
python generator.py       # players.png       (24 random characters)
python animals.py         # daemons.png       (species x color variants)
python walk.py            # walk sheets + walk_demo.gif
python directions.py      # fox_compass.png + daemon_directions.png
python animal_motion.py   # animal_motion.png + animal_motion.gif
python trees.py           # trees.png (tree + great tree, ramp variants)
python water.py           # water.png (pond/river/pool tiles, tiled 2x2)
```

## File guide

| File | Contents |
|---|---|
| `generator.py` | Core: shade system, paint/outline functions, player layer maps (body, arms, garments, pants, shoes, hair, accessories), palettes, `make_character()` |
| `animals.py` | The 5 daemon species (cat, fox, rabbit, bird, wolf) as single maps + natural color variants, `make_daemon()` |
| `walk.py` | Player 8-frame walk cycles in 4 directions, arm swing poses, side/back view maps, `character_frames()`; daemon hop `daemon_frames()` |
| `directions.py` | 8-directional daemon facing (`make_daemon_facing()`), derived back/diagonal views, hand-drawn fox profile |
| `animal_motion.py` | Bird flight (`bird_fly_frames()`) and perch idle, fox trot (`fox_trot_frames()`) |
| `trees.py` | World scenery: a tree + a great tree as canopy `LAYOUTS` (foliage lobes + trunk), with derived lit-blob shading + the shared outline, `make_tree()` |
| `water.py` | World surfaces: a single SEAMLESS tile per body of water (pond/river/pool) from a summed integer-frequency `WAVES` field, shaded into glint/base/trough roles, `make_water_tile()` |

## Core concepts

### ASCII pixel maps

Every sprite part is a list of 32 strings of 32 characters:

```python
"..........233E3333E332.........."
```

| Char | Meaning |
|---|---|
| `.` | transparent |
| `1` | dark shade of the part's palette ramp |
| `2` | base shade |
| `3` | highlight shade |
| `E` | eye (fixed near-black) |

Light source is top-left: highlights go up/left, shadows down/right.
Every module validates map dimensions at import time with asserts -- if you
hand-edit a map and miscount a row, you get an immediate, specific error
(`"BODY row 7: 31 cols"`) instead of corrupted art.

### Palette ramps (color customization)

A ramp is `(dark, base, light)` RGB. Maps reference shade ROLES, not
colors, so recoloring anything = picking a different ramp. Player color
customization is just letting the player pick ramps. To add a color,
append a ramp to `SKIN_RAMPS`, `HAIR_RAMPS`, or `CLOTH_RAMPS` in
`generator.py` (or a species' variant list in `animals.py`).

### Layering (player customization)

Paint order in `make_character()`:

```
body -> pants -> shoes -> arms(skin) -> garment torso -> garment arm parts
     -> hair -> accessory
```

Garments live in the `GARMENTS` registry. Each garment declares parts by
ATTACHMENT: `torso` parts are static; `arm_l`/`arm_r` parts move with that
arm during animation (like parenting a sleeve sprite to an arm bone):

```python
GARMENTS = {
    "tee":  {"torso": SHIRT, "arm_l": SLEEVE_L, "arm_r": SLEEVE_R},
    "tank": {"torso": SHIRT, "arm_l": None,     "arm_r": None},
}
```

Note on paint order: it follows viewer DEPTH, not anatomy. Front view,
arms sit beside the torso; side view, the near arm is in front of the
torso and paints after it (handled per-view in `walk.py`).

### Derivation (why animation stays consistent)

Frames and views are computed from shared maps, never drawn twice:

- Opposite step = `mirror()` (reversed strings) of the drawn step
- Opposite side-view stride = `swap_near_far()` ('1'<->'2' shade swap)
- Left-facing anything = horizontal flip of the composited right-facing frame
- Back views = front maps with faces erased, hair filled over the head,
  collar closed, inner ears filled (+ per-species overlays like the
  rabbit's bobtail)
- Diagonal daemon facings = head-band rows shifted 1px toward the facing
- 1px auto-outline is applied to every finished frame

Change a base map and every derived frame/direction updates with it.

## Animation reference

### Player walk (walk.py)

8 frames per direction (down / up / right; left = flipped right):

- Front/back: stand -> half-lift -> full-lift -> half-lift -> stand -> (mirror)
- Side: contact stride -> half-stride -> passing -> half-stride -> opposite
  contact -> ...
- Body bob: upper layers shift 1px down on lifted/contact frames
- Arm swing: hand-drawn pivot POSES (not bitmap rotation, which smears at
  32px). Shoulder stays anchored; the hand ends 1px higher when swung
  (the arc). Pose tables: `ARM_POSE_L/R` (front), `SIDE_ARM_POSE` (side),
  with matching `SLEEVE_POSE_*` so garments follow the arm.

Suggested playback: ~10-12 fps; tune character move speed until feet
don't slide.

### Daemon facing (directions.py)

`make_daemon_facing(species, direction, variant)` with 8 directions
(`"down"`, `"down_right"`, `"right"`, ... ). The fox has a hand-drawn
profile; other species currently use a head-glance placeholder for pure
side facing (see "Add a species profile" below).

### Animal movement (animal_motion.py)

- Bird: body + wing pose maps (folded/up/mid/down). Flight cycle
  down->mid->up->mid twice per 8 frames; body rises on the downstroke,
  dips on recovery. `bird_idle_frames()` = perched with a settle.
- Fox: profile body + leg poses: stretch -> stand -> gather (airborne,
  sprite lifted 1px) -> stand, twice per 8 frames.

## How to make changes

### Tweak existing art
Edit the ASCII map in place, rerun the module, look at the preview.
The width asserts will catch miscounted rows.

### Add a color
Append a `(dark, base, light)` ramp to the relevant ramp list.

### Add a hairstyle
1. `generator.py`: add a front map to `HAIR_STYLES` (rows ~0-15).
2. `walk.py`: add a side map to `HAIR_SIDE` (back of head + any fall).
3. The back view is derived automatically (`hair_up()` fills the head).

### Add a garment (shirt, dress, armor...)
1. Draw a torso map (cols 10-21, rows 14-22 front; side equivalent).
2. Draw arm-part maps only if the garment covers arms; one per arm pose
   (neutral + swing front; neutral/fwd/back side) -- copy the SLEEVE_*
   maps as templates.
3. Register it in `GARMENTS` (generator.py) and `GARMENTS_SIDE` (walk.py).
No animation code changes needed.

### Add an accessory
Add maps to `ACCESSORIES` (front) and `ACC_SIDE` (side). Accessories that
make no sense from behind (glasses) are skipped for the up direction in
`character_frames()`.

### Add a daemon species
1. `animals.py`: draw one front map, add a `(MAP, [ramps])` entry to
   `SPECIES`.
2. `directions.py`: add a `CONFIG` entry (head rows, nose rows, inner-ear
   rows, optional back-view tail overlay). You now have 8 facings.
3. Optional -- a true profile: add a side map to `SIDE_MAPS`.
4. Optional -- locomotion: split the profile into body + leg poses like
   the fox in `animal_motion.py` (stretch/gather adapts to most quadrupeds;
   rabbits should hop with ear follow-through instead).

### Reshape or recolor a tree (`trees.py`)
Trees aren't hand-shaded pixel maps -- a canopy is too round for that to stay
clean -- so each one is a `LAYOUT`: a few foliage `lobes` `(cx, cy, r)` plus a
trunk box. The lit-blob shading and the outline are *derived* from that (like the
daemon back-views are derived), so:
- **Reshape:** edit a kind's `lobes`/`trunk` in `LAYOUTS`. More, smaller lobes =
  a bushier crown; a taller trunk box = a lankier tree. Rerun, check `trees.png`.
- **Recolor / new season:** add a `(dark, base, light)` foliage+bark entry to
  `RAMPS` (there's `summer`/`pine`/`autumn` already).
- **New kind (e.g. a stump, a sapling):** add a `LAYOUTS` entry; `make_tree()`
  and the baker pick it up with no other changes.

### Reshape or recolor water (`water.py`)
Water is a SURFACE, not a silhouette, so its unit is one SEAMLESS TILE the client tiles
across a pond or river of any size and scrolls a texel at a time (one tile is the whole
animation). The ripples are *derived* from a `WAVES` field — a couple of horizontal wave
bands summed at INTEGER frequencies, which is what makes the tile repeat with no seam:
- **Calmer / busier water:** edit the `WAVES` entries. Lower `amp` = flatter bands; add a
  wave or raise a `weight` for more chop. `GLINT`/`TROUGH` set how often the surface tips
  into a bright sparkle or a dark trough. Rerun, eyeball `water.png` (it's tiled 2×2 so any
  seam jumps out).
- **Recolor / new kind of water:** add a `(dark, base, light)` entry to `RAMPS` (there's
  `pond`/`river`/`pool`). `pond` is tuned to `data/art.json`'s palette `water`.

These feed `tools/gen_water.py`, which bakes one tile per variant —
`assets/sprites/water_{pond,river,pool}.png` — with `.import` sidecars. The game uses them
the moment `data/art.json`'s `entities.water` / `river` / `pool` name a `tile` image
(`render: "sprite"`); `world_tile` there sets how many world units one tile spans (bigger =
chunkier pixels). Remove the entries (or the files) and the water falls back to the old flat
engine fill. WorldArt enables `texture_repeat` so the tile wraps across the shape.

These feed `tools/gen_trees.py`, which bakes each kind as TWO layers —
`assets/sprites/{kind}_trunk.png` and `{kind}_canopy.png` (+ ramp variants) — with
`.import` sidecars. The split is what lets the trunk stay planted while only the
canopy sways in the wind (TreeView draws them separately). The game uses them the
moment `data/art.json`'s `entities.tree` / `entities.great_tree` name a `trunk` +
`canopy` (`render: "sprite"`); set them back to `procedural` for the old engine circles.

### Add an animation pose
Draw the pose map, add it to the relevant pose table
(`ARM_POSE_*`, `SIDE_ARM_POSE`, wing maps, fox leg maps), and reference it
in a frame sequence. Poses are just maps; sequences are just lists.

### Change timing / frame count
Frame sequences are the `legs = [...]`, `arm_poses = [...]`, `bobs = [...]`
lists in `character_frames()` and the `cycle` lists in `animal_motion.py`.
GIF speed is the `ms` parameter of the preview functions.

## Godot notes (planned exporter)

The structure maps directly onto Godot:

- One `AnimatedSprite2D` (or `Sprite2D` + `AnimationPlayer`) per layer;
  sleeve/arm-part sprites parented under the arm node -- exactly the
  `GARMENTS` attachment model.
- Import textures with **Filter off** (nearest) to keep pixels crisp.
- 8-frame walks at 10-12 fps; use an 8-way input vector -> the
  `DIRS_8` direction names.
- A future `export_godot.py` will emit per-layer spritesheets plus
  `SpriteFrames` resources; the per-pose/per-frame generation functions
  (`character_frames`, `make_daemon_facing`, `bird_fly_frames`,
  `fox_trot_frames`) are the API it will walk.

## License / provenance

All art is generated by the code in this repo from hand-authored maps --
no external assets, no AI image generation. Use it however your project
needs.
