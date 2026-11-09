class_name SecretDirector
extends Node
## A world's one SECRET (see docs/home-world-and-secrets-design.md): the thing each destination world
## hides, which, once found, settles into your home world. The maze's is a hedge seed at its heart.
##
## The spec authors it as a `secret` block: an id, where it rests, the prop it shows as, its lore, and
## the small, warm lines of the finding. This director lays the prop out (unless you've already found
## it, so for you it's simply gone), turns an examine of it into a claim, and plays the finding beat
## when the SERVER honours that claim: the companion perks up at it, the screen fades to black, the
## found line rises in white at the centre with "something has changed at home" beneath it, and while
## it holds the seed is taken; the world fades back without it. No popup, no score (S-5).
##
## The server is the judge (S-3), so nothing is "found" until it says so: examining only asks.
##
## A secret's `reveal` says how it becomes findable (W-1..W-5), so each world's can be a different kind:
##   * `always` (default): the prop is simply there (the Maze's seed, the Bazaar's river-drop);
##   * `ward_open`: the prop is there but can only be taken once a Ruin ward is open. Until then
##     examining it reads its `locked_lore`; after, examining it lights it (`lit_line`) and claims it
##     (the Ruin's lantern, which you relight yourself once the great door opens);
##   * `stillness`: nothing shows until you've kept still in a place with your companion settled beside
##     you (StillnessGate), while lights gather over it (MereLights); then the prop rises (Nocthollow);
##   * `hunt_perfect`: nothing shows until a hunt finds every salamander in one go; then the prop
##     appears (the Riverbank's elder).
##   * `touch_all`: nothing shows until you've touched every one of the reveal's `props` (flare props)
##     in one visit; each one you ring stays lit for you and reads the next of the reveal's `lines`, so
##     the progress is told, never counted; the last brings the prop up (Bobbledown's seven
##     chime-bubbles and the Burbler's first breath).
##   * `tracks`: nothing shows until your companion, wearing the right animal (a fox), has led you along
##     an authored trail to its end (TracksDirector over the pure TrailGuide); then the prop appears
##     there (Drifthallow's frost-flower, in a snow-hare's den).
##   * `dream`: nothing shows until your companion has dozed off in one of the world's nap spots, dreamed
##     of a place (a picture in a thought bubble), and you and it have walked to that place together
##     (DozeDirector over the pure DreamGate); then the prop is there (Dozewood's dream-lantern, under
##     the crooked arch). Once found, the naps and dreams stay as a quiet toy; only the prop is gone.
##   * `listen`: the prop (a little bronze bell, Steamhollow) is simply there in the fog, but only your
##     companion can hear where; ListenDirector over the pure ListenGuide turns its gaze toward the sound
##     when you are both settled, and the bell shows through the mist only up close. Examining it claims.
##   * `echo`: nothing shows until you have walked up to a hidden cave in the cliff (HowlDirector over the
##     pure EchoField / EchoGuide): in wolf form your companion howls, the canyon answers in ripples, and one
##     answer comes from where there is no wall. Walking up opens the crack, and the answering stone is
##     there (Hollowsong). Once found, howling stays a quiet toy; only the stone is gone.
##   * `follow`: nothing shows until you and your companion have both arrived at the place; the dark makes
##     it hard to steer there yourself, so you ask your companion to "Go look" and FOLLOW its light
##     (FollowDirector over the pure FollowGuide); the prop (Underroot's root-heart) rises on arrival.
##   * `shadow`: nothing shows until the mural's gap is filled: you choose your companion's form and stand it in
##     the great lantern's light, so its SHADOW falls on the cliff-face screen (ShadowDirector over the pure
##     ShadowCast / MuralGuide); only a bird's, from the right place, fits the gap, and then a door in the cliff
##     opens on the prop (Lanternfold's paper bird). Once found, the shadows stay a quiet toy.


##   * `reflection`: nothing shows until your companion's reflection, turned into a different animal by the
##     mirror lake, has walked the shore and stopped over the stone's place (ReflectionDirector over the pure
##     ReflectionWalker, drawn by the world's ReflectionLayer); then the prop (Stillglass's mirror stone)
##     rises on the bank. Once found, the reflection stays a quiet toy; only the stone is gone.
##   * `skyview`: the prop (Loftreach's nest) is in plain sight on an islet no foot can reach; shifted into a bird and
##     sent up (the radial's Go up), your companion rises, the camera with it, and from high above the high clouds make a
##     picture that points the way; once it has looked at the islet and the bridge's head, a hidden rope bridge comes
##     down (SkyDirector over the pure SkyView / SkyRealm). Examining the nest claims. Once found, going up stays a toy.
## The server checks the conditions it can (an open door, a perfect hunt) before honouring a claim.

## How near your companion must be for you to count as "settled together" (stillness).
const STILL_COMPANION_RADIUS := 110.0
## Per-frame movement (px) under which you count as standing still.
const STILL_EPS := 0.6

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _entry: Dictionary = {}    # the secret's examinable entry (shared with the controller's list), or {}
var _claiming := false         # a claim is in flight; a second examine shouldn't send another
var _secret: Dictionary = {}   # this world's secret block, while it's still to be found
var _interactables: Array      # the controller's examine list (staged reveals add to it)
var _gate: StillnessGate
var _lights: MereLights
var _tracks: TracksDirector
var _doze: DozeDirector
var _listen: ListenDirector
var _howl: HowlDirector
var _cliffs: Array = []        # the world's building views (a cliff holds the cave)
var _follow: FollowDirector
var _shadow: ShadowDirector
var _screens: Array = []        # the world's shadow-screen views (Lanternfold)
var _reflection: ReflectionDirector
var _sky: SkyDirector
var _last_player_pos := Vector2.ZERO
var _rung := {}                # touch_all: the reveal props we've touched this visit (id -> true)
var _found_props: Array = []   # touch_all, already found: its props stay rung on every visit


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView, interactables: Array) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player
	_interactables = interactables
	Net.secret_found.connect(_on_secret_found)
	Net.secret_refused.connect(_on_secret_refused)
	Net.discoveries_received.connect(_on_discoveries)


## Fold this world's secret (if it has one, and we haven't found it) into the world's props, as an
## examinable prop of kind "secret". Called during content layout, BEFORE the controller turns
## `combined` into its examine list, so the seed draws and prompts like any other prop.
func setup_secret(data: Dictionary, combined: Array) -> void:
	_entry = {}
	_secret = {}
	_gate = null
	if is_instance_valid(_lights):
		_lights.queue_free()  # a rebuilt world lays its secret out afresh
	_lights = null
	if is_instance_valid(_tracks):
		_tracks.queue_free()
	_tracks = null
	if is_instance_valid(_doze):
		_doze.queue_free()
	_doze = null
	if is_instance_valid(_listen):
		_listen.queue_free()
	_listen = null
	if is_instance_valid(_howl):
		if is_instance_valid(_howl.ripples()):
			_howl.ripples().queue_free()
		_howl.queue_free()
	_howl = null
	if is_instance_valid(_follow):
		_follow.queue_free()
	_follow = null
	if is_instance_valid(_shadow):
		_shadow.queue_free()
	_shadow = null
	if is_instance_valid(_reflection):
		_reflection.queue_free()
	_reflection = null
	if is_instance_valid(_sky):
		_sky.finish()
		_sky.queue_free()
	_sky = null
	var secret: Dictionary = data.get("secret", {})
	if secret.has("id") and String((secret.get("reveal", {}) as Dictionary).get("type", "")) == "skyview" \
			and Net.has_discovery(String(secret["id"])):
		_open_sky_bridge(data, secret)   # found already: the bridge is simply down, and going up stays a quiet toy
		_start_sky(secret, true)
	_found_props = []
	if secret.has("id") and String((secret.get("reveal", {}) as Dictionary).get("type", "")) == "touch_all":
		_found_props = (secret["reveal"] as Dictionary).get("props", [])
	if secret.has("id") and String((secret.get("reveal", {}) as Dictionary).get("type", "")) == "dream" \
			and Net.has_discovery(String(secret["id"])):
		_start_doze(secret)   # found already: the dozing stays, the prop doesn't come back
	if secret.has("id") and String((secret.get("reveal", {}) as Dictionary).get("type", "")) == "echo" \
			and Net.has_discovery(String(secret["id"])):
		_start_howl(secret, true)   # found already: the cave stays open and the howling stays, the stone doesn't
	if secret.has("id") and String((secret.get("reveal", {}) as Dictionary).get("type", "")) == "shadow" \
			and Net.has_discovery(String(secret["id"])):
		_start_shadow(secret, true)   # found already: the door stays open and the shadows stay a toy, the prop doesn't come
	if secret.has("id") and String((secret.get("reveal", {}) as Dictionary).get("type", "")) == "reflection" \
			and Net.has_discovery(String(secret["id"])):
		_start_reflection(secret, true)   # found already: the lake keeps its walking reflection, the stone doesn't come
	if not secret.has("id") or Net.has_discovery(String(secret["id"])):
		return
	_secret = secret
	_rung = {}
	match _reveal_type():
		"stillness":
			# Nothing to see yet: the lights wait over the water for you to be still.
			var r: Dictionary = secret["reveal"]
			_gate = StillnessGate.new(float(r.get("seconds", 20.0)), float(r.get("drift_back", 0.5)))
			_lights = MereLights.new()
			_lights.name = "MereLights"
			_lights.center = WorldData.to_vec2(r.get("lights_center", secret.get("position", [0, 0])))
			_lights.ring_radius = float(r.get("lights_radius", 80.0))
			_world_art.add_child(_lights)
		"hunt_perfect":
			pass  # appears only after a perfect hunt (on_hunt_won)
		"touch_all":
			pass  # appears once every one of its props has been touched (on_touched)
		"tracks":
			# Nothing to see yet: a fox has to lead you to the den along the hare's trail.
			_tracks = TracksDirector.new()
			_tracks.name = "TracksDirector"
			add_child(_tracks)
			_tracks.setup(_host, _companion, _world_art, _player)
			_tracks.configure(secret)
			_tracks.trail_done.connect(_on_trail_done)
		"dream":
			# Nothing to see yet: it has to doze off in a hollow, dream, and be walked to the dreamed place.
			_start_doze(secret)
		"listen":
			# The bell hangs in the fog from the start; the companion is the only one who hears it.
			combined.append(_secret_prop())
			_listen = ListenDirector.new()
			_listen.name = "ListenDirector"
			add_child(_listen)
			_listen.setup(_host, _companion, _world_art, _player)
			_listen.configure(secret)
		"echo":
			# Nothing to see yet: a wolf has to howl, and you have to find where the canyon answers wrong.
			_start_howl(secret, false)
		"follow":
			# Nothing to see yet: the root-heart glimmers in the dark until you are both led there.
			_follow = FollowDirector.new()
			_follow.name = "FollowDirector"
			add_child(_follow)
			_follow.setup(_host, _companion, _world_art, _player)
			_follow.configure(secret)
			_follow.heart_reached.connect(_on_heart_reached)
		"shadow":
			# Nothing to see yet: the gap in the mural has to be filled by the right shadow.
			_start_shadow(secret, false)
		"reflection":
			# Nothing to see yet: the lake's picture of your companion has to turn and walk you to the stone.
			_start_reflection(secret, false)
		"skyview":
			# The nest is there from the start, on an islet you cannot walk to; a bird's-eye view brings the way down.
			combined.append(_secret_prop())
			_start_sky(secret, false)
		_:
			combined.append(_secret_prop())


## Loftreach: the secret's hidden bridge is open for this visit (found already), so the world's barriers and
## the drawn bridge start with it down.
func _open_sky_bridge(data: Dictionary, secret: Dictionary) -> void:
	var sky: Dictionary = data.get("sky", {})
	var id := String((secret.get("reveal", {}) as Dictionary).get("bridge", ""))
	var revealed: Array = sky.get("revealed", [])
	if id != "" and not revealed.has(id):
		revealed.append(id)
	sky["revealed"] = revealed


func _start_sky(secret: Dictionary, found: bool) -> void:
	_sky = SkyDirector.new()
	_sky.name = "SkyDirector"
	add_child(_sky)
	_sky.setup(_host, _companion, _world_art, _player)
	_sky.configure(secret, found)


## The radial's Go up, and whether this world offers it.
func sky_available() -> bool:
	return _sky != null


func try_go_up() -> void:
	if _sky != null:
		_sky.try_go_up()


## A tap on the world while your companion's eyes are up: true when it brought the bird home.
func on_world_tap() -> bool:
	return _sky != null and _sky.on_world_tap()


func _start_shadow(secret: Dictionary, found: bool) -> void:
	_shadow = ShadowDirector.new()
	_shadow.name = "ShadowDirector"
	add_child(_shadow)
	_shadow.setup(_host, _companion, _world_art, _player)
	_shadow.configure(secret, found)
	_shadow.mural_done.connect(_on_mural_done)
	for s in _screens:
		if is_instance_valid(s):
			_shadow.bind_screen(s)


## The gap is filled: the door in the cliff opens, and the paper bird is there on its threshold.
func _on_mural_done() -> void:
	if _reveal_type() == "shadow" and _entry.is_empty() and not _secret.is_empty():
		_reveal(String((_secret["reveal"] as Dictionary).get("reveal_line", "")))


## A tap on EMPTY ground (the world controller found nothing to examine or command there): in a shadow world,
## a tap on the lit stage stands your companion there. Returns whether it did.
func on_ground_tap(world: Vector2) -> bool:
	return _shadow != null and _shadow.on_ground_tap(world)


func _start_reflection(secret: Dictionary, found: bool) -> void:
	_reflection = ReflectionDirector.new()
	_reflection.name = "ReflectionDirector"
	add_child(_reflection)
	_reflection.setup(_host, _companion, _world_art, _player)
	_reflection.configure(secret, found)
	_reflection.stone_surfaced.connect(_on_stone_surfaced)


func _start_howl(secret: Dictionary, found: bool) -> void:
	_howl = HowlDirector.new()
	_howl.name = "HowlDirector"
	add_child(_howl)
	_howl.setup(_host, _companion, _world_art, _player)
	_howl.configure(secret, found)
	_howl.cave_opened.connect(_on_cave_opened)
	for c in _cliffs:
		if is_instance_valid(c) and not (c as CliffView).is_queued_for_deletion() and (c as CliffView).spec.has("cave"):
			_howl.bind_cliff(c)


## Scenery has stood the world's buildings up: hand the one with the cave in it to the howling.
func bind_buildings(views: Array) -> void:
	_screens = views.filter(func(v: Variant) -> bool: return v is ShadowScreenView)
	if _shadow != null:
		for s in _screens:
			_shadow.bind_screen(s)
	_cliffs = views.filter(func(v: Variant) -> bool: return v is CliffView)
	if _howl != null:
		for c in _cliffs:
			if (c as CliffView).spec.has("cave"):
				_howl.bind_cliff(c)


## The radial's Howl, and whether this world offers it.
func howl_available() -> bool:
	return _howl != null


func try_howl() -> void:
	if _howl != null:
		_howl.try_howl()


## You walked up to the cave: it has opened, and the answering stone is there.
func _on_cave_opened() -> void:
	if _reveal_type() == "echo" and _entry.is_empty() and not _secret.is_empty():
		_reveal(String((_secret["reveal"] as Dictionary).get("reveal_line", "")))


func _start_doze(secret: Dictionary) -> void:
	_doze = DozeDirector.new()
	_doze.name = "DozeDirector"
	add_child(_doze)
	_doze.setup(_host, _companion, _world_art, _player)
	_doze.configure(secret)
	_doze.place_found.connect(_on_place_found)


## The secret's prop, as the world spec authors any prop (kind "secret" in the examine list).
func _secret_prop() -> Dictionary:
	var prop: Dictionary = (_secret.get("prop", {}) as Dictionary).duplicate(true)
	prop["id"] = "secret_" + String(_secret["id"])
	prop["position"] = _secret.get("position", [0, 0])
	prop["interactive"] = true
	prop["lore"] = String(_secret.get("lore", ""))
	prop["secret"] = _secret
	return prop


func _reveal_type() -> String:
	return String((_secret.get("reveal", {}) as Dictionary).get("type", "always"))


## Per frame: drive a stillness secret (fill while you're still by the place with your companion
## beside you; the lights gather as it fills). A no-op for every other kind.
func update(delta: float) -> void:
	if _tracks != null:
		_tracks.update(delta)
	if _doze != null:
		_doze.update(delta)
	if _listen != null:
		_listen.update(delta)
	if _howl != null:
		_howl.update(delta)
	if _follow != null:
		_follow.update(delta)
	if _shadow != null:
		_shadow.update(delta)
	if _reflection != null:
		_reflection.update(delta)
	if _sky != null:
		_sky.update(delta)
	if _gate == null or _gate.is_done() or _player == null:
		return
	var r: Dictionary = _secret.get("reveal", {})
	var moved := _player.position.distance_to(_last_player_pos)
	_last_player_pos = _player.position
	var in_place := _player.position.distance_to(WorldData.to_vec2(r.get("center", _secret.get("position", [0, 0])))) <= float(r.get("radius", 150.0))
	var settled := moved < STILL_EPS and _companion.position.distance_to(_player.position) <= STILL_COMPANION_RADIUS
	var completed := _gate.update(delta, in_place, settled)
	_lights.set_progress(_gate.fraction())
	if completed:
		_reveal(String(r.get("reveal_line", "")))


## The hunt found every salamander in one go: the Riverbank's elder shows itself.
func on_hunt_won(_found: int) -> void:
	if _reveal_type() == "hunt_perfect" and _entry.is_empty() and not _secret.is_empty():
		_reveal(String((_secret["reveal"] as Dictionary).get("reveal_line", "")))


## The fox led us to the hare's den: the frost-flower shows.
func _on_trail_done() -> void:
	if _reveal_type() == "tracks" and _entry.is_empty() and not _secret.is_empty():
		_reveal(String((_secret["reveal"] as Dictionary).get("reveal_line", "")))


## We walked to the place the companion dreamed of, together: the dream-lantern shows.
func _on_place_found() -> void:
	if _reveal_type() == "dream" and _entry.is_empty() and not _secret.is_empty():
		_reveal(String((_secret["reveal"] as Dictionary).get("reveal_line", "")))


## We (both of us) reached the root-heart: it rises out of the roots.
func _on_heart_reached() -> void:
	if _reveal_type() == "follow" and _entry.is_empty() and not _secret.is_empty():
		_follow.mark_revealed()
		_reveal(String((_secret["reveal"] as Dictionary).get("reveal_line", "")))


## The reflection stopped over the stone's place: the stone rises on the bank.
func _on_stone_surfaced() -> void:
	if _reveal_type() == "reflection" and _entry.is_empty() and not _secret.is_empty():
		_reveal(String((_secret["reveal"] as Dictionary).get("reveal_line", "")))


## "Go look" is on offer in a world whose secret is led to (Underroot): the radial's entry lights up while
## the heart is still to be found, and is greyed once you've reached it.
func can_go_look() -> bool:
	return _follow != null and _follow.can_ask()


## The player chose "Go look": the companion leads (FollowDirector), and you follow.
func go_look() -> void:
	if _follow != null:
		_follow.ask()


## The pockets where the dark thins round something only just in view (the faint bell, once you are close;
## the companion's lead-light and the root-heart's glimmer); the MistVeil asks every frame. Empty in every
## world without such a secret.
func mist_pockets() -> Array:
	var out: Array = _listen.mist_pockets() if _listen != null else []
	if _follow != null:
		out.append_array(_follow.mist_pockets())
	return out


## We touched a prop (touch_all): if it's one of the reveal's props we haven't rung yet this visit, keep
## it lit for us, read the next line of the reveal (or, for the last, bring the secret up) and return
## true, so the controller doesn't also read its ordinary lore. Anything else returns false.
func on_touched(entry: Dictionary) -> bool:
	if _secret.is_empty() or _reveal_type() != "touch_all" or not _entry.is_empty():
		return false
	var r: Dictionary = _secret["reveal"]
	var ids: Array = r.get("props", [])
	var id := String(entry.get("id", ""))
	if not ids.has(id):
		return false
	_world_art.set_lit(int(entry["render_index"]), true)
	if _rung.has(id):
		_host.show_hint(String(r.get("again_line", entry.get("lore", ""))))
		return true
	_rung[id] = true
	if _rung.size() >= ids.size():
		_reveal(String(r.get("reveal_line", "")))
		return true
	var lines: Array = r.get("lines", [])
	var line := String(entry.get("lore", ""))
	if not lines.is_empty():
		line = String(lines[clampi(_rung.size() - 1, 0, lines.size() - 1)])
	_host.show_hint(line)
	return true


## The world is drawn: if we found this world's touch_all secret on an earlier visit, its props show as
## rung (quietly, no pulse), so it's clear at a glance that you've already sung this world's song.
## Before it's found, every visit starts with them all waiting again.
func after_world_drawn() -> void:
	if _found_props.is_empty() or not _secret.is_empty():
		return  # not a touch_all world, or still to be found this visit
	_light_found_props()


func _light_found_props() -> void:
	for e in _interactables:
		if _found_props.has(String(e.get("id", ""))):
			_world_art.set_lit(int(e["render_index"]), true, true)


## How many of a touch_all reveal's props we've rung this visit (tests, and the smoke check).
func rung_count() -> int:
	return _rung.size()


## Bring a staged secret into the world: draw its prop, add it to the examine list, let the companion
## notice it, and say the line that goes with it.
func _reveal(line: String) -> void:
	var prop := _secret_prop()
	var pos := WorldData.to_vec2(prop["position"])
	var render_index := _world_art.add_interactable(pos, WorldData.to_color(prop.get("color", [0.8, 0.8, 0.8])), String(prop.get("type", "")))
	var entry := {
		"pos": pos, "label": String(prop.get("label", "something")), "id": String(prop["id"]), "tags": prop.get("tags", []),
		"kind": "secret", "render_index": render_index, "lore": String(prop["lore"]), "affordances": {}, "secret": _secret,
	}
	_interactables.append(entry)
	_entry = entry
	_host.secret_taken()  # the examine scan's cached nearest is stale (a new thing to examine)
	_companion.notify_interaction(pos, String(prop["id"]), entry["tags"])
	if line != "":
		_host.show_hint(line)


## The controller built this prop's examine entry: keep it, so the finding can retire it.
func adopt_entry(entry: Dictionary) -> void:
	_entry = entry


## Whether an examine entry is a secret that's been taken (the controller's scans skip it).
static func is_taken(entry: Dictionary) -> bool:
	return bool(entry.get("_taken", false))


## Examining the secret: read its lore, let the companion amble over to look, and ask the server.
func examine(entry: Dictionary) -> void:
	_companion.notify_interaction(entry["pos"], String(entry["id"]), entry["tags"])
	var reveal: Dictionary = (entry["secret"] as Dictionary).get("reveal", {})
	if String(reveal.get("type", "")) == "ward_open":
		# Not yet: the door is still shut, and the lantern stays dark.
		if not _host.ward_open(String(reveal.get("ward", ""))):
			_host.show_hint(String(reveal.get("locked_lore", entry["lore"])))
			return
		# You relight it yourself, then take it.
		_world_art.set_lit(int(entry["render_index"]), true)
		_host.show_hint(String(reveal.get("lit_line", entry["lore"])))
	else:
		_host.show_hint(String(entry["lore"]))
	if _claiming:
		return
	_claiming = true
	Net.claim_secret(String(entry["secret"]["id"]))


## The server honoured the claim. Take the seed out of the world and play the small, warm beat.
func _on_secret_found(secret_id: String, _is_new: bool, with_names: Array) -> void:
	_claiming = false
	if _entry.is_empty() or String(_entry["secret"]["id"]) != secret_id:
		return
	var secret: Dictionary = _entry["secret"]
	_companion.delight_at(_entry["pos"])
	# S-4: the moment names the friends who were near you ("Found with Sam."), above the home line.
	var aside := String(secret.get("home_line", ""))
	if not with_names.is_empty():
		aside = "Found with %s.\n%s" % [SecretDirector.names_phrase(with_names), aside]
	_host.play_moment(String(secret.get("found_line", "")), aside)
	# Taken under cover of the dark, so the world comes back without it.
	get_tree().create_timer(_host.MOMENT_FADE_IN).timeout.connect(_take)


## "Sam", "Sam and Wren", "Sam, Wren and Moss": how the moment names the friends who were there.
static func names_phrase(names: Array) -> String:
	var n: Array = names.map(func(x: Variant) -> String: return String(x))
	if n.size() <= 1:
		return "".join(n)
	return ", ".join(n.slice(0, n.size() - 1)) + " and " + String(n[-1])


func _on_secret_refused(_secret_id: String) -> void:
	_claiming = false


## A join's discovery list arrived after we laid the world out (a cold build, or a find made on
## another device): if it says we already have this one, quietly take it away.
func _on_discoveries(ids: Array) -> void:
	if not _secret.is_empty() and _reveal_type() == "shadow" and _entry.is_empty() and ids.has(String(_secret.get("id", ""))):
		_secret = {}   # found on another device: the door is open and the shadows stay, the prop doesn't come
		if _shadow != null:
			_shadow.set_found()
	if not _secret.is_empty() and _reveal_type() == "skyview" and ids.has(String(_secret.get("id", ""))) and _sky != null:
		_sky.set_found()   # found on another device: the bridge is down (the nest is taken away by the ordinary path below)
	if not _secret.is_empty() and _reveal_type() == "echo" and _entry.is_empty() and ids.has(String(_secret.get("id", ""))):
		_secret = {}   # found on another device: the howling stays, the stone doesn't come
	if not _secret.is_empty() and _reveal_type() == "reflection" and _entry.is_empty() and ids.has(String(_secret.get("id", ""))):
		_secret = {}   # found on another device: the walking reflection stays, the stone doesn't come
		if _reflection != null:
			_reflection.finish()
	if not _secret.is_empty() and _reveal_type() == "dream" and _entry.is_empty() and ids.has(String(_secret.get("id", ""))):
		_secret = {}   # found on another device: the nap and the dream stay, the prop doesn't come
	if not _entry.is_empty() and not is_taken(_entry) and ids.has(String(_entry["secret"]["id"])):
		_take()
	# found on another device (or the list arrived after the build): its chimes show as rung too
	if not _secret.is_empty() and ids.has(String(_secret.get("id", ""))) and not _found_props.is_empty():
		_light_found_props()


func _take() -> void:
	if _sky != null:
		_sky.finish()
	if _shadow != null:
		_shadow.finish()
	if _listen != null:
		_listen.finish()
	if _follow != null:
		_follow.finish()
	if _reflection != null:
		_reflection.finish()
	# Every entry for this secret, not just the one we adopted: should the world ever hold more than one
	# (it did, from a layout bug), none may be left behind to be found again.
	var id := String(_entry["secret"]["id"])
	for e in _interactables:
		if String(e.get("kind", "")) == "secret" and String((e.get("secret", {}) as Dictionary).get("id", "")) == id and not is_taken(e):
			e["_taken"] = true
			_world_art.take_interactable(int(e["render_index"]))
	_host.secret_taken()
