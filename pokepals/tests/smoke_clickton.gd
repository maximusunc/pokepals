extends SceneTree
## Headless smoke test for CLICKTON, the city made entirely of small colourful bricks. Loads the real World
## scene from the test fixture as if we'd come through the Vale's Gateway, and checks what makes it that:
##   * the ground is the studded baseplate (pixel ground layer over the brick terrain), roads/pavements/water
##     are plates, and the buildings are depth-sorted BuildingViews that block their whole footprint;
##   * every tree is built of bricks and doesn't sway; the props are brick props;
##   * our pair is rebuilt out of bricks (the brick shader), with no aura or bubble;
##   * no people and no creatures: no ambient pals, no encounter flock;
##   * the secret: ONE rainbow brick, set into a building's wall (drawn by that building, not WorldArt), which
##     can be examined, and which vanishes from the wall once it is taken;
##   * a body can't walk through a building or into the water; the way home is the Vale's Gateway.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_clickton.gd

const CLICKTON_ID := "88888888-8888-8888-8888-888888888888"

var _world: Node
var _frames := 0
var _done := false


func _process(_delta: float) -> bool:
	_frames += 1
	if _done:
		return true

	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(CLICKTON_ID, WorldData.load_json("res://tests/world_fixtures/clickton.json"))
		router.current_world = CLICKTON_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", CLICKTON_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var art: WorldArt = _world._world_art
	var data: Dictionary = _world._world_data

	# The ground is a baseplate; the city is plates and buildings.
	fails += _check(art.get_node_or_null("Ground") != null, "the ground is the studded baseplate (a pixel ground layer)")
	fails += _check(not art._soft, "no soft ground")
	fails += _check(art._plates.size() == (data["plates"] as Array).size(), "every plate is laid (%d)" % art._plates.size())
	var textured := 0
	for pl in art._plates:
		if pl["tex"] != null:
			textured += 1
	fails += _check(textured > 0, "the plates are studded tiles")
	var views: Array = []
	for c in _world._scenery.get_children():
		if c is BuildingView:
			views.append(c)
	fails += _check(views.size() == (data["buildings"] as Array).size() and views.size() > 50, "every building stands in the depth-sorted layer (%d)" % views.size())
	var textured_walls := 0
	for v in views:
		if v._wall_tex != null and v._roof_tex != null:
			textured_walls += 1
	fails += _check(textured_walls == views.size(), "every building is brick courses under a studded roof")

	# Trees and props are bricks.
	var trees := 0
	var rigid := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
			if c.sway_gain == 0.0 and (c.trunk_tex != null and c.canopy_tex != null):
				rigid += 1
	fails += _check(trees > 100 and rigid == trees, "every tree is built of bricks and stands rigid (%d of %d)" % [rigid, trees])
	for t in ["brick_lamp", "brick_bench", "brick_fountain", "brick_stall"]:
		fails += _check(art._prop_base.has(t), "%s is drawn from brick art" % t)

	# Our pair is rebuilt out of bricks, and nothing else about their look changes.
	fails += _check(_world._player.material is ShaderMaterial, "the player is rebuilt out of bricks")
	fails += _check(_world._companion.material is ShaderMaterial, "so is the companion")
	fails += _check(_world._player.get_node_or_null("VisitorBubble") == null and _world._player.get_node_or_null("OtherworldAura") == null, "no bubble or glow on top of the bricks")

	# No people and no creatures.
	fails += _check((data.get("ambient_pals", []) as Array).is_empty(), "no creatures")
	var creatures := 0
	for e in _world._interactables:
		if String(e.get("kind", "")) == "creature":
			creatures += 1
	fails += _check(creatures == 0, "no creatures to examine")

	# Barriers: a building blocks its whole footprint, and so does the water.
	var solids := Solids.build(data, [], data.get("collision", {}))
	var bounds := WorldData.bounds_rect(data)
	var first: Dictionary = (data["buildings"] as Array)[0]
	var rr: Array = first["rect"]
	var inside := Vector2(float(rr[0]) + 4.0, float(rr[1]) + float(rr[3]) * 0.5)
	var pushed := Solids.resolve(inside, 6.0, solids, bounds, 2.0)
	fails += _check(not Rect2(float(rr[0]), float(rr[1]), float(rr[2]), float(rr[3])).has_point(pushed), "a body at a building's wall is pushed out of it")
	var in_bay := Solids.resolve(Vector2(-700, 706), 6.0, solids, bounds, 2.0)
	fails += _check(in_bay.y < 700.0, "the bay's water blocks (a body at its edge is pushed back to the promenade)")

	# The secret: one rainbow brick in a wall.
	var secret: Dictionary = data.get("secret", {})
	fails += _check(String(secret.get("id", "")) == "rainbow_brick" and String(secret["reveal"]["type"]) == "always", "the one secret is a rainbow brick, there to be found")
	var holders: Array = []
	for v in views:
		if v.spec.has("inlay"):
			holders.append(v)
	fails += _check(holders.size() == 1, "exactly one building holds it (%d)" % holders.size())
	var entries := _secret_entries()
	fails += _check(entries.size() == 1, "it is laid out to be examined (%d)" % entries.size())
	if holders.size() == 1 and entries.size() == 1:
		var holder: BuildingView = holders[0]
		var e: Dictionary = entries[0]
		fails += _check(holder._inlay_index == int(e["render_index"]), "the building's brick is bound to the secret's prop")
		fails += _check(holder._rainbow_tex != null and not holder._inlay_gone, "the brick shows in the wall")
		# it sits at the foot of its wall, in standing room
		var wall_foot := holder.position
		fails += _check(absf((e["pos"] as Vector2).y - wall_foot.y) < 20.0 and absf((e["pos"] as Vector2).x - wall_foot.x) < holder.hw, "its examine spot is at the foot of that wall")
		fails += _check(art._unseen.has("rainbow_brick"), "WorldArt leaves its painting to the building")
		# taking it (what the server's yes does) clears it from the wall
		art.take_interactable(int(e["render_index"]))
		holder.tick(0.016, 0.0, false)
		fails += _check(holder._inlay_gone, "once taken, the wall has no brick in it")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")

	if fails == 0:
		print("ALL CLICKTON SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("CLICKTON SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _secret_entries() -> Array:
	var out: Array = []
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret":
			out.append(e)
	return out


func _check(cond: bool, label: String) -> int:
	print(("  PASS  " if cond else "  FAIL  ") + label)
	return 0 if cond else 1
