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


## Spawn the world's trees as individually sortable nodes. `border_pts` is the same
## treeline the collision build uses (Solids.border_positions), so the drawn ring keeps
## matching its colliders.
func populate(data: Dictionary, border_pts: Array, style: ArtStyle) -> void:
	# Clear any trees from a previous populate (actors are kept — they're scene-defined).
	for child in get_children():
		if child is TreeView:
			child.queue_free()

	var atmo: Dictionary = data.get("atmosphere", {})
	var wind: Dictionary = atmo.get("wind", {})
	var wind_strength := float(wind.get("strength", 2.6))
	var wind_speed := float(wind.get("speed", 1.15))
	var tree_tex := SpriteSlot.resolve(style.entity("tree"))
	var great_tree_tex := SpriteSlot.resolve(style.entity("great_tree"))

	# Hand-placed trees, then the procedural border ring that frames the world.
	for t in data.get("trees", []):
		_spawn_tree(WorldData.to_vec2(t), false, tree_tex, style, wind_strength, wind_speed)
	for p in border_pts:
		_spawn_tree(p, false, tree_tex, style, wind_strength, wind_speed)

	# Landmarks: a few oversized, beckoning great trees you can see (and walk behind) from afar.
	for lm in data.get("landmarks", []):
		_spawn_tree(WorldData.to_vec2(lm["position"]), true, great_tree_tex, style, wind_strength, wind_speed)


func _spawn_tree(pos: Vector2, is_great: bool, tex: Texture2D, style: ArtStyle, wind_strength: float, wind_speed: float) -> void:
	var tree: TreeView = TreeViewScript.new()
	tree.position = pos
	tree.is_great = is_great
	tree.tex = tex
	tree.style = style
	tree.wind_strength = wind_strength
	tree.wind_speed = wind_speed
	tree.phase = _phase_for(pos)
	add_child(tree)


## A stable pseudo-random wind phase derived from a world position, so each tree keeps
## the same sway offset every frame and across runs (mirrors WorldArt._phase_for).
func _phase_for(p: Vector2) -> float:
	return fposmod(p.x * 0.013 + p.y * 0.021, TAU)
