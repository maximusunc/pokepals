extends SceneTree
## Headless smoke test for BOBBLEDOWN, the round world. Loads the real World scene from the test fixture
## as if we'd come through the Vale's Gateway, and checks the things that make it the one world that
## breaks from the pixel art, plus its secret:
##   * a SOFT ground (no pixel GroundLayer; sugared dapples, fizzing ponds) and no pixel water tiles;
##   * every growth, prop and creature is smooth @2x art, drawn at half size and linearly filtered;
##   * our pair wears the world's pastel light; the air is full of bubbles;
##   * the native creatures are examinable and are NOT companion forms;
##   * the secret: ringing the chime-bubbles reads the lullaby's lines (a repeat doesn't count), and the
##     seventh brings the Burbler's first breath up by the Fizzwell, ready to examine;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_bobbledown.gd

const BOBBLEDOWN_ID := "77777777-7777-7777-7777-777777777777"
const NATIVE := ["bobbling", "puffkin", "wobbler", "rollypoll", "bubblefin"]

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
		net.prime_world_spec(BOBBLEDOWN_ID, WorldData.load_json("res://tests/world_fixtures/bobbledown.json"))
		router.current_world = BOBBLEDOWN_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", BOBBLEDOWN_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var art: WorldArt = _world._world_art

	# The soft ground, not the pixel one.
	fails += _check(art._soft, "the ground is soft")
	fails += _check(art.get_node_or_null("Ground") == null, "no pixel ground layer")
	fails += _check(art._dots.size() > 400, "the ground is dappled (%d)" % art._dots.size())
	fails += _check(art._fizz.size() > 20, "the ponds fizz (%d bubbles)" % art._fizz.size())
	fails += _check(art._pond_tex == null, "no pixel water tiles")
	fails += _check(art._grass.is_empty(), "no grass tufts")

	# Every growth is smooth @2x art.
	var trees := 0
	var hd := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
			if c.tex_scale == 0.5 and c.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST and (c.tex != null or c.canopy_tex != null):
				hd += 1
	fails += _check(trees > 400, "the world is full of round growths (%d)" % trees)
	fails += _check(hd == trees, "every growth is smooth @2x art (%d of %d)" % [hd, trees])

	# The props are smooth too, with their gloss.
	for t in ["chime_bubble", "marsh_stone", "bubble_bloom", "puff_bush", "candy_bench"]:
		fails += _check(art._prop_scale.get(t, 1.0) == 0.5, "%s is drawn from @2x art" % t)
	fails += _check(art._prop_gloss.has("chime_bubble"), "the chime-bubble has its gloss layer")

	# Our pair, in the world's light.
	fails += _check(_world._player.material is ShaderMaterial, "the player wears the world's pastel light")
	fails += _check(_world._player.get_node_or_null("VisitorBubble") != null and _world._player.get_node_or_null("VisitorBubbleFront") != null, "the player walks about inside a bubble")
	fails += _check(_world._companion.get_node_or_null("VisitorBubble") != null, "so does the companion")
	var pb: VisitorBubble = _world._player.get_node_or_null("VisitorBubble")
	var cb: VisitorBubble = _world._companion.get_node_or_null("VisitorBubble")
	if pb != null and cb != null:
		fails += _check(cb.radius < pb.radius, "the companion's bubble is the smaller one")
	fails += _check(_world._player.get_node_or_null("OtherworldAura") == null, "the bubble replaces the old glow")
	fails += _check(int(_world._style.entity("ambient_life").get("bubbles", {}).get("count", 0)) > 0, "the air is full of bubbles")

	# No native creature is a companion form.
	var native_forms := 0
	for f in PalView.available_forms():
		if NATIVE.has(String(f["species"])):
			native_forms += 1
	fails += _check(native_forms == 0, "no native creature is a companion form")

	# Native creatures: smooth, and examinable.
	var creatures: Array = []
	for e in _world._interactables:
		if String(e.get("kind", "")) == "creature":
			creatures.append(e)
	fails += _check(creatures.size() >= 60, "native creatures are examinable (%d)" % creatures.size())
	if not creatures.is_empty():
		var v: PalView = creatures[0]["view"]
		fails += _check(v._scale == 0.5 and v.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "creatures are smooth @2x sheets")

	# The secret: the seven chime-bubbles.
	var secret: Dictionary = _world._world_data.get("secret", {})
	var chime_ids: Array = secret.get("reveal", {}).get("props", [])
	fails += _check(chime_ids.size() == 7, "seven chime-bubbles hold the lullaby")
	fails += _check(_secret_entries().is_empty(), "the first breath hasn't risen yet")
	fails += _check(_lit_chimes(chime_ids) == 0, "a visit before the secret is found starts with every chime waiting")
	var lines: Array = secret["reveal"]["lines"]
	for i in chime_ids.size():
		var idx := _index_of(String(chime_ids[i]))
		if idx < 0:
			fails += _check(false, "chime %s is examinable" % chime_ids[i])
			continue
		_ring(idx)
		if i < chime_ids.size() - 1:
			fails += _check(_world._hint.text == String(lines[i]), "chime %d reads the lullaby's line %d" % [i + 1, i + 1])
			var ri := int(_world._interactables[idx]["render_index"])
			fails += _check(bool(art._interactables[ri].get("opened", false)), "chime %d stays lit once rung" % [i + 1])
			fails += _check(_secret_entries().is_empty(), "still no first breath after %d" % [i + 1])
		if i == 0:
			_ring(idx)  # ringing the same one again doesn't count
			fails += _check(_world._secret_dir.rung_count() == 1, "a repeat ring doesn't count")
			fails += _check(_world._hint.text == String(secret["reveal"]["again_line"]), "a repeat ring says so")
	fails += _check(_world._hint.text == String(secret["reveal"]["reveal_line"]), "the seventh note brings it up")
	var found := _secret_entries()
	fails += _check(found.size() == 1, "the first breath has risen (%d)" % found.size())
	if found.size() == 1:
		fails += _check((found[0]["pos"] as Vector2).distance_to(WorldData.to_vec2(secret["position"])) < 1.0, "it rose where the secret rests")

	# A revisit once the secret is found: every chime shows as rung from the start.
	for id in chime_ids:
		var ci := _index_of(String(id))
		if ci >= 0:
			art.set_lit(int(_world._interactables[ci]["render_index"]), false)
	_world._secret_dir._secret = {}  # what setup_secret leaves for a secret already found
	_world._secret_dir.after_world_drawn()
	fails += _check(_lit_chimes(chime_ids) == chime_ids.size(), "once it's found, every chime shows as rung on a revisit")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")

	if fails == 0:
		print("ALL BOBBLEDOWN SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("BOBBLEDOWN SMOKE FAILED: %d" % fails)
		quit(1)
	return true


## Stand right on the chime and examine it (it should be the nearest thing to us there).
func _ring(idx: int) -> void:
	_world._player.position = _world._interactables[idx]["pos"] + Vector2(0, 3)
	_world._invalidate_nearest()
	var near: int = _world._nearest_interactable()
	if near != idx:
		print("  note: nearest was %s, not the chime" % _world._interactables[near].get("id", "?"))
	_world._try_interact()


func _lit_chimes(ids: Array) -> int:
	var n := 0
	for id in ids:
		var i := _index_of(String(id))
		if i >= 0 and bool(_world._world_art._interactables[int(_world._interactables[i]["render_index"])].get("opened", false)):
			n += 1
	return n


func _index_of(id: String) -> int:
	for i in _world._interactables.size():
		if String(_world._interactables[i].get("id", "")) == id:
			return i
	return -1


func _secret_entries() -> Array:
	var out: Array = []
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret":
			out.append(e)
	return out


func _check(cond: bool, label: String) -> int:
	print(("  PASS  " if cond else "  FAIL  ") + label)
	return 0 if cond else 1
