# Player Appearance & Wardrobe — Working Design

A living record of how player customization works and where it's headed, in the same
spirit as `companion-design.md`: capture what's **resolved and built now**, and keep the
door open to the MMO destination without building it yet.

**Status legend:** ✅ Resolved / built · 🔶 In progress · ⬜ Open / deferred · ⚠️ Flagged.

> **Scope honesty.** Rungs 1–2 (the offline single-player core) are complete; the full
> inventory + acquisition + wardrobe UI is still **future-rung content**. What's built now
> is only the **architectural seam** — the part that's cheap today and expensive to
> retrofit later (the CLAUDE.md "keep the door open" discipline). Renders identically to
> before; opens the door to everything below.

---

## ✅ Core idea — appearance is portable *self*, not scene state

The player's look is the visual mirror of the companion's mind:

| Persistent "you" | What it is | Class | Save file |
|---|---|---|---|
| **`PlayerAppearance`** | the *look* you carry through worlds | `scripts/world/player_appearance.gd` | `user://player_appearance.json` |
| **`CompanionSelf`** | the *mind* that travels with you | `scripts/world/companion_self.gd` | `user://companion_self.json` |

Both are **pure data** — no scene tree, no texture loading, no render references — so they
stay portable (local save now, authoritative server later, untouched) and are testable
headless. This is the "companion as self" pillar applied to the avatar: the two together
are the whole portable *you*.

---

## ✅ Two perspectives, two fields

The request had two halves; they're two different concerns, kept separate:

| Perspective | Means | Lives in |
|---|---|---|
| **Inventory** | *what you own* — the wardrobe, grown by visiting worlds | `PlayerAppearance.owned` + the catalog (`data/cosmetics.json`) |
| **Customization** | *what you're wearing* — the assembled loadout | `PlayerAppearance.equipped` → `AvatarCompositor` |

`colors` (palette choices like skin tone / hair color) is the third field — the cheap
"palette" half of the chosen art approach.

---

## ✅ Art approach — paper-doll layers + palette (decided)

The avatar is a **paper-doll**: a stack of transparent, directional sprite layers drawn
back-to-front by ascending `z` (body → outfit → footwear → hair → headwear → held). Each
layer follows the **existing sheet convention** (rows = facing, cols = walk cycle; see
`SpriteActor`), so the renderer is the per-layer logic we already had, looped.

- **Shape** comes from layers (mix any hat + any outfit; a world can also grant a one-piece
  costume — that's just the degenerate single-big-layer case).
- **Color** comes from **palette-swap** ramps on color slots (skin tone, hair color) — tiny
  data, no new art per variant. *(Landed as a CPU recolor bake — see the pixel-art pipeline section.)*

A single base body layer drawn through the compositor is **byte-for-byte the old
single-sheet render**, so this is a pure seam, not a visual change.

---

## ✅ Inventory side — the catalog & owning things

**`data/cosmetics.json`** is the shared dictionary of every wearable, defined as data (add
one without code changes), loaded by **`CosmeticsCatalog`** (pure). Each item:

```jsonc
"riverbank:reed_hat": {                       // WORLD-NAMESPACED id ("origin:name")
  "slot": "headwear", "name": "Woven Reed Hat", "origin": "riverbank",
  "sheet": "res://assets/cosmetics/reed_hat.png", "z": 60,
  "frame": [32,32], "fps": 8, "walk_frames": 4, "idle_frame": 0,
  "dirs": { "down":0, "side":1, "up":2 }
}
```

- **World-namespaced ids** mirror the companion's area ids (`world:region`): a world's drops
  are self-contained and a server can grant them by id without collision. Straight path to
  the world-of-worlds north star.
- **Base set:** `origin:"base"` items are owned by every player from the start and are the
  slot defaults (`default_for`), so a fresh player has a complete, valid look with zero saved
  data.
- **Acquisition** is one idempotent call — `PlayerAppearance.grant(catalog, id)` — returning
  whether it was *newly* granted (for a "you found something to wear!" beat). Local on a
  pickup today; an authoritative server event later, same call.
- **Silent fallback:** an item whose `sheet` doesn't exist is skipped at draw time, so items
  can be **declared before their art is drawn** (`riverbank:reed_hat` is such a placeholder).

---

## ✅ Customization side — wearing & rendering

`PlayerAppearance` holds `equipped` (slot → item id) and validates every change:

- `equip` refuses an item you don't own or that doesn't fit the slot.
- `unequip` refuses to bare a **required** slot.
- **Invariant — never renders empty/broken:** `resolved_layers()` falls back to a required
  slot's base default for anything missing/unknown; `from_dict` drops stale equips/colors a
  growing catalog no longer supports. The avatar can't render naked.

**Rendering** (`AvatarCompositor`, presentation): `PlayerAppearance.resolved_layers()` →
ordered **data** layers (pure); the compositor loads each `sheet` and draws it via
`SpriteActor`. `PlayerView` resolves once into `_avatar_layers` (cached; refresh on loadout
change, not per frame) and composites in `_draw`, keeping the **procedural `VectorActor`
fallback** for when no art resolves.

### Logic/presentation split (held)
- **Logic** (`/scripts/world`): `PlayerAppearance`, `CosmeticsCatalog` — pure, headless,
  server-ready.
- **Presentation** (`/scripts/presentation`): `AvatarCompositor`, `PlayerView` — the only
  side that touches textures/the GPU.

---

## ✅ The companion mirror — same compositor, different source of truth

Companions are **not player-customizable**; their look is **derived**, not chosen:

| | Player | Companion |
|---|---|---|
| Source of truth | **chosen** — the wardrobe `equipped` map | **derived** — a pure function of `CompanionSelf` |
| Resolver | `PlayerAppearance.resolved_layers()` | ⬜ a future `CompanionLook.layers_for(self, cfg)` |
| Renderer | `AvatarCompositor` | the **same** compositor |

This already has a seed: `companion_view.gd` maps eased `mood_valence`/`mood_arousal` to
tail wag, ear posture, and idle bounce. `CompanionLook` extends that same idea from
"animation params" to "which asset *layers*" — birth/identity → base form & markings,
disposition → variant, mood → expression overlay. Deterministic, no player input, reuses the
player's compositor.

---

## ✅ Pixel-art pipeline — creation, wardrobe, recolor (built)

The paper-doll seam is now a working, playable loop:

- **Component art** — `tools/gen_cosmetics.py` authors per-slot 32×32 / 3-dir / 4-frame sheets
  (grayscale bodies + hair for recolor; baked-color outfit/footwear/headwear/accessory) into
  `res://assets/cosmetics/<slot>/`, all registered to one shared skeleton so they stack pixel-perfect.
  Run `godot --headless --path pokepals --import` after regenerating so Godot imports the new PNGs.
- **Catalog** — `data/cosmetics.json` now ships an `accessory` slot and a real base set: three body
  builds, three hairs, three outfits, two footwear, two headwear, two accessories. The fresh loadout is
  a clothed starter (average build + tunic + boots + short hair + default skin/hair color).
- **Recolor (landed)** — color slots carry `swatches` ([r,g,b] per ramp). `resolved_layers()` carries a
  `palette_color`, and `AvatarCompositor` CPU-bakes a recolored copy of each grayscale dye layer
  (luminance → swatch shadow/highlight, outline preserved), cached by (sheet, ramp). Skin tone and hair
  color now actually show. `assets/palette_swap.gdshader` is shipped as the alternative for a future
  Sprite2D-node path. (This also unblocks the color shop's "deferred recolor step".)
- **Creation** — a brand-new player (no server appearance yet) is routed through the `AvatarCustomizer`
  in "create" mode before the world seeds their save: `PresenceDirector` raises `needs_creation` (instead
  of silently seeding the default), the world opens the overlay paused, and on confirm
  `PresenceDirector.apply_local_look()` performs the first `push_save`.
- **Wardrobe** — the same overlay reopens from the gear menu ("Wardrobe") to restyle mid-play; Done runs
  the same `apply_local_look` (refresh + re-broadcast identity + save), so friends re-render the new look
  live via the existing identity relay. `AvatarPreview` mirrors the real render path so the portrait is
  exactly what you become in the world.

## ⬜ Deferred (future rungs — the architecture above means none force a rewrite)

- **Server-economy cosmetics** — buying *new* clothing/accessories (not just colors) still needs the
  integer `item_def_id` ↔ string catalog reconciliation + an `equip` wire message hitting `Economy.equip`.
  Today the wardrobe only offers items the player already owns (the base set); the shop path is separate.
- **Acquisition in worlds** — wire `grant()` to actual pickups/rewards; a "new!" beat.
- **`CompanionLook` resolver** — the derived-companion-appearance function above (companions still use
  their own separate rig, not this pipeline).
- **More art + polish** — per-world cosmetic drops, item thumbnails in the grid, a real 4th (left) row.

---

## Code touchpoints (built now)

- `data/cosmetics.json` — the catalog (slots, color slots, items; base set + one placeholder).
- `scripts/world/cosmetics_catalog.gd` — `CosmeticsCatalog` (pure loader/queries).
- `scripts/world/player_appearance.gd` — `PlayerAppearance` (owned/equipped/colors, grant/
  equip/resolve, save round-trip).
- `scripts/presentation/avatar_compositor.gd` — `AvatarCompositor` (load + draw layers).
- `scripts/presentation/player_controller.gd` — `PlayerView` now composites the worn loadout
  (was a single sheet); persists appearance on session end.
- `tests/test_player_appearance.gd` — schema + invariants (default look, grant/equip
  validation, z-order, required-slot fallback, color validation, round-trip, stale-save
  recovery, shipped-catalog base set).

## Notes / conventions
- Keep `PlayerAppearance`/`CosmeticsCatalog` presentation-agnostic and headless-safe
  (no `SceneTree`/render deps), per CLAUDE.md — only the compositor/`PlayerView` touch art.
- Data-driven: items, slots, and color ramps live in `data/cosmetics.json`; adding content is
  a data edit, not a code change.
- `art.json`'s `characters.player` block now feeds only the procedural fallback's colors; the
  player's sprite layers come from the catalog.
