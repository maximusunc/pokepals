class_name Scenery
extends Node2D
## The depth-sorted layer of the world. Its node has `y_sort_enabled = true`, so Godot
## draws its children back-to-front by their ground (Y) position. The Player and
## Companion live here (declared in world.tscn); `populate()` fills in one TreeView per
## tree, border tree, and landmark. Because everything anchors at its feet/base, the
## actors correctly slot in front of nearer trees and behind farther ones — letting you
## walk behind a tree's canopy. Ground, grass, flowers and props stay in WorldArt, which
## renders *underneath* this layer.

const TreeViewScript := preload("res://scripts/presentation/tree_view.gd")

# How far past the screen edge a tree still ticks/draws, so a tall canopy whose feet sit
# just off-screen doesn't pop in. Sized to the largest motif (a great tree's canopy).
const CULL_MARGIN := 200.0

var _time := 0.0
var _trees: Array[TreeView] = []  # cached so the per-frame cull doesn't re-walk get_children()


## One shared clock for the whole grove: advance time once, find the on-screen rect once,
## then tick (sway + redraw) only the trees the camera can see and hide the rest. This
## replaces the old per-tree `_process`/`queue_redraw` — the dominant per-frame cost in a
## large world — and, because hidden CanvasItems drop out of the y-sort pass, it also shrinks
## the sort/draw set to what's visible. Hiding a tree only stops its cosmetic sway; trees hold
## no logic, so nothing breaks while they're off-screen, and the shared `_time` means they
## resume mid-sway (no pop) when they scroll back in.
func _process(delta: float) -> void:
	if _trees.is_empty():
		return
	_time += delta
	var vis := ViewCull.visible_world_rect(self, CULL_MARGIN)
	var cull := vis.has_area()  # false in headless / before the camera exists → tick them all
	for tree in _trees:
		if cull and not vis.has_point(tree.position):
			if tree.visible:
				tree.visible = false
			continue
		if not tree.visible:
			tree.visible = true
		tree.set_time(_time)


## Spawn the world's trees as individually sortable nodes. `border_pts` is the same
## treeline the collision build uses — the server-generated ring from the spec's
## "border_trees" — so the drawn ring keeps matching its colliders.
func populate(data: Dictionary, border_pts: Array, style: ArtStyle) -> void:
	# Clear any trees from a previous populate (actors are kept — they're scene-defined).
	for child in get_children():
		if child is TreeView:
			child.queue_free()
	_trees.clear()

	var atmo: Dictionary = data.get("atmosphere", {})
	var wind: Dictionary = atmo.get("wind", {})
	var wind_strength := float(wind.get("strength", 2.6))
	var wind_speed := float(wind.get("speed", 1.15))
	# Optional drop-in art per KIND, resolved once and cached. A plain tree is the "tree" entity and a
	# landmark the "great_tree" one; a world may name others — a tree entry [x, y, "crystal_spire"] or a
	# landmark { "type": "elder" } draws from that entity instead (Nocthollow's glowing growths), and
	# collides exactly like a tree / great tree. An unknown kind quietly falls back to the plain tree.
	var arts := {}

	# Hand-placed trees, then the procedural border ring that frames the world.
	for t in data.get("trees", []):
		var kind := String(t[2]) if (t is Array and t.size() > 2) else "tree"
		_spawn_tree(WorldData.to_vec2(t), false, _art_for(arts, style, kind, "tree"), style, wind_strength, wind_speed)
	for p in border_pts:
		_spawn_tree(p, false, _art_for(arts, style, "tree", "tree"), style, wind_strength, wind_speed)

	# Landmarks: a few oversized, beckoning great trees you can see (and walk behind) from afar.
	for lm in data.get("landmarks", []):
		var kind := String(lm.get("type", "great_tree"))
		_spawn_tree(WorldData.to_vec2(lm["position"]), true, _art_for(arts, style, kind, "great_tree"), style, wind_strength, wind_speed)


## The resolved art for one scenery kind (cached in `cache`): its colour VARIANTS, each a split
## trunk + canopy (only the canopy sways), a whole "sprite", or nothing (procedural circles) — plus an
## optional glow (a soft light the growth gives off) and per-kind sway/shadow. An entity may list
## "variants": [{ trunk, canopy, sprite, glow }, …] (one is picked per tree by its position, so a grove
## mixes colours) or give a single set at its top level, as the meadow trees do.
func _art_for(cache: Dictionary, style: ArtStyle, kind: String, fallback: String) -> Dictionary:
	if cache.has(kind):
		return cache[kind]
	var cfg := style.entity(kind)
	if cfg.is_empty() and kind != fallback:
		cfg = style.entity(fallback)
	var variants: Array = []
	var raw: Array = cfg.get("variants", [cfg])
	for v in raw:
		var vc: Dictionary = cfg.duplicate()
		vc.erase("variants")
		vc.merge(v, true)
		variants.append({
			"tex": SpriteSlot.resolve(vc),
			"trunk": SpriteSlot.resolve(vc, "trunk"),
			"canopy": SpriteSlot.resolve(vc, "canopy"),
			"glow": WorldData.to_color(vc["glow"]) if vc.has("glow") else Color(0, 0, 0, 0),
		})
	var art := {
		"variants": variants,
		"glow_radius": float(cfg.get("glow_radius", 0.0)),
		"glow_y": float(cfg.get("glow_y", -24.0)),
		"sway": float(cfg.get("sway", 1.0)),
	}
	cache[kind] = art
	return art


func _spawn_tree(pos: Vector2, is_great: bool, art: Dictionary, style: ArtStyle, wind_strength: float, wind_speed: float) -> void:
	var tree: TreeView = TreeViewScript.new()
	tree.position = pos
	tree.is_great = is_great
	var variants: Array = art["variants"]
	var v: Dictionary = variants[int(absf(pos.x * 7.0 + pos.y * 13.0)) % variants.size()] if not variants.is_empty() else {}
	tree.tex = v.get("tex")
	tree.trunk_tex = v.get("trunk")
	tree.canopy_tex = v.get("canopy")
	tree.glow_color = v.get("glow", Color(0, 0, 0, 0))
	tree.glow_radius = art["glow_radius"]
	tree.glow_y = art["glow_y"]
	tree.sway_gain = art["sway"]
	tree.style = style
	tree.wind_strength = wind_strength
	tree.wind_speed = wind_speed
	tree.phase = _phase_for(pos)
	add_child(tree)
	_trees.append(tree)


## A stable pseudo-random wind phase derived from a world position, so each tree keeps
## the same sway offset every frame and across runs (mirrors WorldArt._phase_for).
func _phase_for(p: Vector2) -> float:
	return fposmod(p.x * 0.013 + p.y * 0.021, TAU)
