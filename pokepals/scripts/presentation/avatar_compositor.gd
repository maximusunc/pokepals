class_name AvatarCompositor
extends RefCounted
## Draws a PAPER-DOLL avatar: a stack of directional, animated sprite layers composited
## back-to-front, each one blitted by the same per-frame logic SpriteActor already uses
## (it picks the right row for facing and column for the walk phase, anchored bottom-centre
## so every layer's feet land on the same ground). This is the presentation counterpart to
## PlayerAppearance: PlayerAppearance decides the ORDERED LIST of layers (pure data);
## AvatarCompositor turns each layer's 'sheet' into a Texture2D and draws them in order.
##
## A single base body layer drawn through here is byte-for-byte the old single-sheet player
## render — the compositor is the seam that lets hats/hair/outfits stack on top later without
## touching movement, collision, or the procedural fallback.
##
## Pure presentation; a layer whose sheet doesn't exist is silently dropped (SpriteSlot's
## discipline), so items can be declared in the catalog before their art is drawn.

## Turn the pure data layers from PlayerAppearance.resolved_layers() into DRAWABLE layers:
## load each 'sheet' to a Texture2D, keep the order, drop any whose texture is missing. Do
## this once when the loadout changes (not every frame) — Godot caches loads, but the array
## is what _draw iterates. Each returned entry is { tex, cfg, palette }, where cfg IS the
## item definition (it already carries frame/fps/walk_frames/idle_frame/dirs for SpriteActor).
static func load_layers(resolved: Array) -> Array:
	var out: Array = []
	for layer in resolved:
		var path := String(layer.get("sheet", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var tex := ResourceLoader.load(path) as Texture2D
		if tex == null:
			continue
		out.append({ "tex": tex, "cfg": layer, "palette": String(layer.get("palette", "")) })
	return out


## Whether there's anything to composite (at least one layer's art resolved). When false,
## the caller should fall back to its procedural look (VectorActor).
static func has_drawable(loaded: Array) -> bool:
	return not loaded.is_empty()


## Draw the loaded layers back-to-front. params (facing, speed, time) are shared by every
## layer so the whole avatar faces and walks as one. Palette (the per-layer recolor ramp) is
## carried through but not yet applied — the palette-swap shader is the deferred next step;
## until then every layer draws at its sheet's native colors, which is identical to today.
static func draw(ci: CanvasItem, loaded: Array, params: Dictionary) -> void:
	for layer in loaded:
		SpriteActor.draw(ci, layer["tex"], params, layer["cfg"])
