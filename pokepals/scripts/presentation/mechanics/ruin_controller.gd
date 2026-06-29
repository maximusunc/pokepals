class_name RuinController
extends Node
## THE RUIN — the companion-as-actor puzzle, SHARED — lifted out of world_controller. The authoritative
## ward state lives on the SERVER (Server.RuinMechanisms, per world), so everyone present converges on one
## truth. This client only: DETECTS what its OWN companion does (search nosing near a plate; weight
## stepping on/off) and reports abstract intents to the server, then RENDERS whatever ward state the
## server echoes back (reveal the plate, raise the slab). The companion's brain stays truth-blind
## throughout — it never learns where a plate is; the local detection feeds only the intent stream and the
## body, never the mind. Also owns the descent gloom (the Cistern's puzzle dark + per-region dimming).
##
## Talks back to the host (the World) through its small public seam: show_hint, peer_count (the paired
## hall's waking tier), rebuild_solids_dropping (drop a raised slab's collider), is_daycycle_enabled
## (gloom yields to a world that animates its own day tint). No-op in worlds without a "ruin" block.

const CARRY_REACH := 38.0  # how near the companion must get to "arrive" at the source / the brazier
const HALL_REFRESH := 1.0   # seconds between re-issuing a Paired-Hall plate hold (before its hold lapses)
# Ambient gloom: the screen eases toward GLOOM_DARK by the player's current region's "gloom" (0 = the
# bright Wood, rising as you descend into the ruin). CISTERN_UNLIT is the extra dark its light-ward
# chamber holds until the brazier is relit. See docs/the-ruin-narrative-and-world.md.
const GLOOM_DARK := Color(0.24, 0.28, 0.28)
const CISTERN_UNLIT := 0.88

var _host: Node
var _companion: CompanionView
var _player: PlayerView
var _world_art: WorldArt
var _day_tint: CanvasModulate
var _interactables: Array = []  # the controller's master list (shared ref), for render-index resolution

# Ward state: SERVER-AUTHORITATIVE (shared across everyone in the world). Each ward dict carries the
# per-ward geometry for our own detection plus local flags mirroring the server (found/open) and which
# intents we've already sent. Empty in worlds without a "ruin" spec block.
var _wards: Array = []
var _seeking := false   # true while a "go look" search is out, so only a delegated sweep uncovers a plate
var _gloom := 0.0
var _gloom_rect := Rect2()
var _gloom_ward: Dictionary = {}
var _region_glooms: Array = []  # [ { rect: Rect2, gloom: float } ] — per-region ambient darkness
var _base_day_tint := Color.WHITE


## Wire up the host seam + scene refs, and listen for the server's authoritative ward state. The Net
## connection is auto-dropped when this node is freed on a world hop, so it never duplicates.
func setup(host: Node, companion: CompanionView, player: PlayerView, world_art: WorldArt, day_tint: CanvasModulate) -> void:
	_host = host
	_companion = companion
	_player = player
	_world_art = world_art
	_day_tint = day_tint
	Net.ward_state_received.connect(_on_ward_state)


## Build the Ruin from the spec's "ruin" block, resolving render indices from the (already laid-out)
## interactables. A no-op in worlds without a "ruin" block, so every other world is untouched.
func configure(data: Dictionary, interactables: Array) -> void:
	_interactables = interactables
	_setup_ruin(data)


## Whether this world is a Ruin (drives the opening hint).
func has_wards() -> bool:
	return not _wards.is_empty()


## Whether any ward is still shut (gates the "Go look" affordance).
func has_unopened_ward() -> bool:
	return _any_ward_unopened()


## Run every frame: detect our companion's ward actions + report intents, then ease the descent gloom.
func update(delta: float) -> void:
	_update_ruin(delta)
	_update_gloom(delta)


## Build the Ruin's wards from the spec's "ruin" block: the per-ward geometry this client needs to
## DETECT its companion's actions (where the plate hides, how near to uncover/weight it, which slab it
## raises), plus local flags mirroring the server's authoritative found/open. Resolves each slab's
## render index from the interactables laid out in _setup_contents. No-op in worlds without a "ruin" block.
func _setup_ruin(data: Dictionary) -> void:
	_wards.clear()
	_seeking = false
	_gloom_rect = Rect2()
	_gloom_ward = {}
	_base_day_tint = _day_tint.color
	# Per-region ambient gloom (the descent dimmer): cache each region's rect + declared darkness.
	_region_glooms.clear()
	for r in data.get("regions", []):
		if r.has("gloom"):
			var mn := WorldData.to_vec2(r["min"])
			_region_glooms.append({ "id": String(r.get("id", "")), "rect": Rect2(mn, WorldData.to_vec2(r["max"]) - mn), "gloom": float(r["gloom"]) })
	for wd in data.get("ruin", {}).get("wards", []):
		var slab_id := String(wd.get("slab_id", ""))
		# Decoy points (Warren-style wards): identical-looking gaps where the companion's nose says
		# "not here". Drive the which-one tell off these vs. the true plate. Empty for a plain ward.
		var decoys: Array = []
		for d in wd.get("decoys", []):
			decoys.append(WorldData.to_vec2(d))
		# Light-ward (Cistern): has a 'source' (the ember the player kindles) + a brazier + murals. The
		# carry is a directed fetch (source → plate), not a search; kindling stands in for 'uncover'.
		var is_light: bool = wd.has("source")
		var mural_idx: Array = []
		for mid in wd.get("murals", []):
			mural_idx.append(_render_index_for_id(String(mid)))
		# Paired ward (the Paired Hall): two plates that must bear weight AT ONCE. Build the plate list
		# (key → world pos + render index) for the hold logic and the per-plate glow feedback.
		var is_paired: bool = wd.has("plates")
		var plates: Array = []
		var occ_sent := {}
		for pkey in wd.get("plates", []):
			var k := String(pkey)
			plates.append({
				"key": k,
				"pos": WorldData.to_vec2(wd.get("plate_" + k, [0, 0])),
				"render": _render_index_for_id(String(wd.get("plate_" + k + "_id", ""))),
			})
			occ_sent[k] = false
		var ward := {
			"id": String(wd.get("id", "ward")),
			"plate": WorldData.to_vec2(wd.get("plate", [0, 0])),
			"uncover_r": float(wd.get("uncover_radius", 120.0)),
			"occupy_r": float(wd.get("occupy_radius", 34.0)),
			"slab_id": slab_id,
			"slab_render_index": _render_index_for_id(slab_id),
			"plate_render_index": -1,
			"hint": String(wd.get("hint", "")),
			"decoys": decoys,
			"is_light": is_light,
			"source": WorldData.to_vec2(wd.get("source", [0, 0])),
			"source_id": String(wd.get("source_id", "")),
			"ember_render_index": _render_index_for_id(String(wd.get("source_id", ""))),
			"brazier_render_index": _render_index_for_id(String(wd.get("brazier_id", ""))),
			"mural_render_indices": mural_idx,
			"region_rect": _region_rect(data, String(wd.get("region", ""))),
			"kindled": false,
			"carry_phase": "idle",
			# Paired Hall: the two plates, which plate our companion is assigned to hold, which (if any)
			# we've wedged, the occupy we've reported per plate, and the hold-refresh timer.
			"is_paired": is_paired,
			"plates": plates,
			"wedge_id": String(wd.get("wedge_id", "")),
			"assigned": "",
			"wedged": "",
			"occ_sent": occ_sent,
			"refresh": 0.0,
			# Local mirror of the server's authoritative state + which intents we've already sent.
			"found": false,
			"revealed": false,
			"open": false,
			"uncover_sent": false,
			"occupied_sent": false,
		}
		_wards.append(ward)
		# The dark chamber whose gloom we lift on lighting (the light-ward with a region).
		if is_light and (ward["region_rect"] as Rect2).get_area() > 0.0:
			_gloom_rect = ward["region_rect"]
			_gloom_ward = ward


## "Go look": send the companion off to search. _seeking gates the referee so ONLY a delegated
## sweep uncovers a plate — the companion merely trailing you past it does nothing (the search is
## the point). The brain (and bond) decide how the sweep actually goes; here we just issue it.
func try_seek() -> void:
	if _wards.is_empty() or not _any_ward_unopened():
		return
	# In the Cistern (a dark light-ward chamber), "Go look" is a CARRY, not a search: it can't do anything
	# until you've named the need and woken the ember. Gated to the chamber so it never hijacks the
	# Threshold/Warren search elsewhere.
	var lw := _active_light_ward()
	if not lw.is_empty():
		if not bool(lw["kindled"]):
			_host.show_hint("Pitch dark — your companion casts about but finds nothing to work. Something here must be lit first.")
		elif String(lw["carry_phase"]) == "idle":
			_begin_carry(lw)
		return
	# In the Paired Hall, "Go look" sends the companion to STAND a plate (and hold it): the nearest one
	# not already wedged, so after jamming the wedge on one you naturally send it to the other.
	var hw := _active_paired_ward()
	if not hw.is_empty():
		var key := _nearest_plate_key(hw, _player.position, true)
		if key == "":
			_host.show_hint("Both plates are spoken for — the door should be giving way.")
		else:
			hw["assigned"] = key
			hw["refresh"] = 0.0
			_companion.issue_command("settle", _plate_pos(hw, key))
			_host.show_hint("Your companion crosses to a plate and sets its weight on it. Now the other must be held too.")
		return
	_seeking = true
	_companion.issue_command("seek")
	_host.show_hint("You send your companion off to search.")


## A prop was examined: if it's a Ruin fixture, handle it and return true (the caller then skips the
## generic examine beat). Covers kindling the Cistern ember, jamming the Paired-Hall wedge, and the
## nudge that examining an unsolved slab gives. Returns false for any non-Ruin prop.
func try_examine(entry: Dictionary) -> bool:
	var id := String(entry["id"])
	# KINDLE the Cistern ember: examining the dead ember is the deduction — naming that this place needs
	# light. It wakes the ember (its art) and stands in for the light-ward's 'uncover' (found) on the
	# server, arming the carry. Idempotent (only the first kindle of an unlit ward does anything).
	var lw := _light_ward_for_source(id)
	if not lw.is_empty() and not bool(lw["open"]) and not bool(lw["kindled"]):
		lw["kindled"] = true
		var eri := int(lw["ember_render_index"])
		if eri >= 0:
			_world_art.open_slab(eri)
		Net.send_ward_uncover(String(lw["id"]))
		_host.show_hint("You breathe on the old ember — it wakes, and a mote of light lifts free. Now send your companion to carry it.")
		return true
	# Jam the WEDGE onto a plate (the lonely Paired-Hall workaround): examining the wedge holds the plate
	# nearest it, so your one companion is free to stand the other. _update_hall keeps the wedge's weight
	# reported even after the companion leaves.
	var hw := _paired_ward_for_wedge(id)
	if not hw.is_empty() and not bool(hw["open"]):
		var key := _nearest_plate_key(hw, entry["pos"])
		if key != "":
			hw["wedged"] = key
			_host.show_hint("Your companion drags the wedge onto the near plate — it settles, and the stone holds it down. Now send it to stand the other.")
		return true
	# Examining an unsolved Ruin slab nudges you toward the real move — sending your companion.
	var ward := _ward_for_slab(id)
	if not ward.is_empty() and not bool(ward["open"]):
		_host.show_hint(String(ward.get("hint", "The slab won't budge. Maybe your companion can find what works it.")))
		return true
	return false


## Run every frame: DETECT what OUR companion is doing and report abstract intents to the server (which
## holds the authoritative shared ward state). Opening is NOT decided here — it arrives via the server's
## echo (_on_ward_state), so every player sees the same gate open. For each not-yet-open ward:
##   • UNCOVER — while a search is out, once our companion's sweep noses within uncover range, predict
##     the reveal locally (so the find feels instant), send our companion to settle, and tell the server.
##   • OCCUPY — once the plate is revealed, report (edge-triggered) our companion stepping on / off it.
func _update_ruin(delta: float) -> void:
	if _wards.is_empty():
		return
	var cpos: Vector2 = _companion.position
	for w in _wards:
		if bool(w["open"]):
			continue
		# Paired ward (Paired Hall): keep our companion on its plate and report our weight per plate.
		if bool(w["is_paired"]):
			_update_hall(w, cpos, delta)
			continue
		# Light-ward (Cistern): advance the carry instead of the search-uncover detection.
		if bool(w["is_light"]):
			_update_carry(w, cpos)
			continue
		# Warren-style ward (has decoys): drive the which-gap TELL — the companion perks and turns toward
		# the TRUE gap as it nears it, so the player can read it and trust it over their own eyes.
		if not w["decoys"].is_empty():
			_drive_nook_tell(w, cpos)
		var near := cpos.distance_to(w["plate"])
		if not bool(w["uncover_sent"]) and _seeking and near <= float(w["uncover_r"]):
			w["uncover_sent"] = true
			_reveal_plate(w, true)                       # local prediction; server echo confirms
			_companion.issue_command("settle", w["plate"])
			Net.send_ward_uncover(String(w["id"]))
		if bool(w["revealed"]):
			var on := near <= float(w["occupy_r"])
			if on != bool(w["occupied_sent"]):
				w["occupied_sent"] = on
				Net.send_ward_occupy(String(w["id"]), on)


## The server's authoritative ward state arrived (on join, or whenever anyone's companion acts): adopt
## it. A ward newly FOUND reveals its plate (so you see one a friend's companion uncovered); a ward newly
## OPEN raises the slab for everyone. Idempotent — our own predicted reveal is already in, so this won't
## double it.
func _on_ward_state(wards: Array) -> void:
	for entry in wards:
		if not (entry is Dictionary):
			continue
		var w := _ward_by_id(String(entry.get("id", "")))
		if w.is_empty():
			continue
		# Paired ward (Paired Hall): light each plate that's bearing weight (the glow everyone sees), and
		# open the door once the server says both hold. No buried plate to reveal.
		if bool(w["is_paired"]):
			var plates_state: Variant = entry.get("plates", {})
			if plates_state is Dictionary:
				for p in w["plates"]:
					_world_art.set_lit(int(p["render"]), bool((plates_state as Dictionary).get(String(p["key"]), false)))
			if bool(entry.get("open", false)) and not bool(w["open"]):
				_open_ward(w)
			continue
		if bool(entry.get("found", false)) and not bool(w["found"]):
			_reveal_plate(w, false)
		if bool(entry.get("open", false)) and not bool(w["open"]):
			_open_ward(w)


## The Warren's "which gap?" TELL — presentation only. While a search is out, when the companion comes
## within (bond-scaled) sense range of the TRUE gap it perks and turns toward it (glance_toward) — a read
## the player can trust over their own eyes. Crucially this uses glance_toward, NOT the salamander point_at:
## point_at FREEZES the body (it's "stop and point out the rock"), which would strand the companion at
## sense range and never let it nose in; a glance only redirects the gaze + perks, so it keeps moving in to
## clear the gap. The decoys get no tell on purpose — its confidence landing on one of several alike gaps
## IS the moment. Scaled by bond, like every tell. The brain never learns the truth: this feeds only the body.
func _drive_nook_tell(w: Dictionary, cpos: Vector2) -> void:
	if not _seeking or bool(w["found"]):
		return
	if cpos.distance_to(w["plate"]) <= lerpf(80.0, 150.0, _companion.bond_value()):
		_companion.glance_toward(w["plate"])


## The active light-ward (Cistern) if you're standing in its dark chamber, else {}. Region-gated so
## "Go look" only means CARRY when you're actually in the Cistern — elsewhere it stays a search.
func _active_light_ward() -> Dictionary:
	for w in _wards:
		if bool(w["open"]) or not bool(w["is_light"]):
			continue
		var rect: Rect2 = w["region_rect"]
		if rect.get_area() > 0.0 and not rect.has_point(_player.position):
			continue
		return w
	return {}


## The light-ward whose ember (source) has this interactable id, or {} — for the kindle.
func _light_ward_for_source(id: String) -> Dictionary:
	for w in _wards:
		if bool(w["is_light"]) and String(w["source_id"]) == id:
			return w
	return {}


## Start the carry: send the companion to FETCH the woken light from the source. _update_carry takes
## it from there (source → brazier → deliver). One leg at a time via the Seek action's "settle".
func _begin_carry(w: Dictionary) -> void:
	w["carry_phase"] = "to_source"
	_companion.issue_command("settle", w["source"])
	_host.show_hint("Your companion pads off to fetch the light.")


## Advance the Cistern carry each frame: once the companion reaches the source it takes up the mote and
## bears it to the brazier; arriving there is the DELIVERY — reported to the server as the ward's
## 'occupy', which (with the kindle's 'uncover') opens it for everyone. The brazier lighting, the murals
## and the dark lifting all follow from the server's open echo (_open_ward → _light_cistern).
func _update_carry(w: Dictionary, cpos: Vector2) -> void:
	match String(w["carry_phase"]):
		"to_source":
			if cpos.distance_to(w["source"]) <= CARRY_REACH:
				w["carry_phase"] = "to_brazier"
				_companion.issue_command("settle", w["plate"])
				_host.show_hint("It takes up the mote of light and carries it to the brazier.")
		"to_brazier":
			if cpos.distance_to(w["plate"]) <= float(w["occupy_r"]):
				w["carry_phase"] = "delivered"
				Net.send_ward_occupy(String(w["id"]), true)


# ── The Paired Hall: a door that yields only while BOTH plates bear weight at once. Each client holds
# its OWN companion on a plate (or jams a wedge) and reports its weight PER PLATE; the server combines
# everyone's and opens when all plates hold (see Server.RuinMechanisms paired wards). Two pairs → a
# companion to each; alone → a wedge on one plate, your companion on the other. ──

## Run every frame for the hall: keep our assigned companion standing on its plate (refresh the settle
## before its hold lapses, so a brief lapse can't drop the door), and report our weight on each plate —
## our companion standing on it, OR a wedge we've jammed (which holds even when the companion leaves).
func _update_hall(w: Dictionary, cpos: Vector2, delta: float) -> void:
	if String(w["assigned"]) != "":
		w["refresh"] = float(w["refresh"]) - delta
		if float(w["refresh"]) <= 0.0:
			w["refresh"] = HALL_REFRESH
			_companion.issue_command("settle", _plate_pos(w, String(w["assigned"])))
	for p in w["plates"]:
		var key := String(p["key"])
		var on := cpos.distance_to(p["pos"]) <= float(w["occupy_r"]) or String(w["wedged"]) == key
		if on != bool(w["occ_sent"][key]):
			w["occ_sent"][key] = on
			Net.send_ward_occupy(String(w["id"]), on, key)


## The unopened paired ward whose chamber you're standing in, else {} (region-gated like the Cistern,
## so "Go look" only means "stand a plate" inside the Paired Hall).
func _active_paired_ward() -> Dictionary:
	for w in _wards:
		if bool(w["open"]) or not bool(w["is_paired"]):
			continue
		var rect: Rect2 = w["region_rect"]
		if rect.get_area() > 0.0 and not rect.has_point(_player.position):
			continue
		return w
	return {}


## The paired ward whose wedge has this interactable id, or {} — for the wedge examine.
func _paired_ward_for_wedge(id: String) -> Dictionary:
	for w in _wards:
		if bool(w["is_paired"]) and String(w["wedge_id"]) == id:
			return w
	return {}


## The world pos / render index of a paired ward's plate by key.
func _plate_pos(w: Dictionary, key: String) -> Vector2:
	for p in w["plates"]:
		if String(p["key"]) == key:
			return p["pos"]
	return Vector2.ZERO


## The key of the plate nearest the player (any), or the nearest one NOT already wedged, or "" if none.
func _nearest_plate_key(w: Dictionary, from: Vector2, skip_wedged := false) -> String:
	var best := ""
	var best_d := INF
	for p in w["plates"]:
		if skip_wedged and String(w["wedged"]) == String(p["key"]):
			continue
		var d := from.distance_to(p["pos"])
		if d < best_d:
			best_d = d
			best = String(p["key"])
	return best


## The light-flooding payoff when the great door opens — TIERED by who's present. Solo (you wedged one
## plate, your companion held the other): a muted waking, real but a little lonely. With a second pair
## (≥2 players here): the full waking — the old two glimpsed for a moment. The hint carries it; the door
## itself is opened by _open_ward.
func _wake_paired_hall(w: Dictionary) -> void:
	var present: int = 1 + _host.peer_count()
	if present >= 2:
		_host.show_hint("Light runs the whole length of the hall — and for a breath, two figures and their companions stand where you do, long ago. The great door swings wide.")
	else:
		_host.show_hint("With a grind the great door opens — just enough. A single lamp gutters alight in the dark. You did it alone, the patient way.")
	# The Waking: light floods back. Permanently lift the depths' gloom (paired_hall + the sanctum beyond),
	# so stepping through into the reward is the brightest beat since the forest — and, if you're here to
	# witness it, a one-shot warm bloom sweeps the screen (fuller/longer with a second pair present).
	_lift_gloom("paired_hall", 0.12)
	_lift_gloom("sanctum", 0.04)
	# Flash only for someone actually AT the hall to witness it — not on a far re-entry sync, and not
	# jarringly across the map when a friend's pair opens it (the spawn point is ~1340px off).
	var hall_center := _player.position
	if w.has("plate_a") and w.has("plate_b"):
		hall_center = (WorldData.to_vec2(w["plate_a"]) + WorldData.to_vec2(w["plate_b"])) * 0.5
	if _player.position.distance_to(hall_center) < 900.0:
		_play_waking_flash(present >= 2)


## Set the ambient gloom of a named region (used by the Waking to lift the depths once the great door
## opens). No-op if the region declares no gloom. The change is permanent for this visit, so the lit
## sanctum stays bright as you move through it.
func _lift_gloom(region_id: String, value: float) -> void:
	for rg in _region_glooms:
		if String(rg.get("id", "")) == region_id:
			rg["gloom"] = value


## The Waking bloom: a warm, full-screen wash that swells then fades — light flooding back the moment the
## great door opens. Built in code on its own CanvasLayer (above the world, below nothing it needs to read),
## torn down when the tween finishes. `full` (a second pair present) makes it brighter and a touch longer.
func _play_waking_flash(full: bool) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 80
	var rect := ColorRect.new()
	rect.color = Color(1.0, 0.95, 0.82, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	add_child(layer)
	var peak := 0.62 if full else 0.42
	var tw := create_tween()
	tw.tween_property(rect, "color:a", peak, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(rect, "color:a", 0.0, 1.9 if full else 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(layer.queue_free)


## The Cistern lit (server-confirmed open): light the brazier and wake the murals (their clues for the
## Paired Hall). The sealed door and the dark are handled by _open_ward / the gloom, which key off
## the ward being open.
func _light_cistern(w: Dictionary) -> void:
	var bri := int(w["brazier_render_index"])
	if bri >= 0:
		_world_art.open_slab(bri)
	for mi in w["mural_render_indices"]:
		if int(mi) >= 0:
			_world_art.open_slab(int(mi))


## Cistern gloom: while you stand in the dark chamber with its light-ward still unlit, darken the whole
## scene (the CanvasModulate day tint) — the cue that makes you NAME the need. Eases in/out, and lifts
## the moment the brazier catches (the ward opens). No-op in worlds without a Cistern, and skipped if a
## daycycle owns the tint.
func _update_gloom(delta: float) -> void:
	if _host.is_daycycle_enabled():
		return
	if _region_glooms.is_empty() and _gloom_ward.is_empty():
		return
	# Ambient darkness of the region you're standing in (the Wood is 0, the depths darker)...
	var target := _region_gloom_at(_player.position)
	# ...and the Cistern's puzzle dark on top: near-black in its chamber until the brazier is lit.
	if not _gloom_ward.is_empty() and not bool(_gloom_ward["open"]) and _gloom_rect.get_area() > 0.0 and _gloom_rect.has_point(_player.position):
		target = maxf(target, CISTERN_UNLIT)
	_gloom = lerpf(_gloom, target, 1.0 - exp(-2.5 * delta))
	_day_tint.color = _base_day_tint.lerp(GLOOM_DARK, _gloom)


## The ambient gloom of the region containing `pos` (first match), or 0 (bright) if none declares one.
func _region_gloom_at(pos: Vector2) -> float:
	for rg in _region_glooms:
		if (rg["rect"] as Rect2).has_point(pos):
			return float(rg["gloom"])
	return 0.0


## Reveal a ward's plate: mark it found, draw the uncovered stone (once), and narrate. `mine` tells the
## finder's snappy "your companion noses it out" beat from the calmer "a plate lies uncovered" a friend's
## search produced. Idempotent on the draw, so the predicted reveal and the server echo never double up.
func _reveal_plate(w: Dictionary, mine: bool) -> void:
	w["found"] = true
	if bool(w["revealed"]):
		return
	w["revealed"] = true
	if bool(w["is_light"]):
		# A light-ward (Cistern): 'found' comes from kindling the ember (already narrated), and the brazier
		# is already drawn — there's no buried plate to reveal here.
		return
	if w["decoys"].is_empty():
		# A buried plate (Threshold-style): spawn its uncovered stone where the search found it.
		w["plate_render_index"] = _world_art.add_interactable(w["plate"], Color(0.62, 0.66, 0.60), "plate")
		_host.show_hint("Your companion noses through the moss and uncovers a worn stone plate." if mine
			else "A worn stone plate lies uncovered nearby.")
	else:
		# A Warren nook: the gap is already drawn; the clear (open state) is the reveal, so just narrate.
		_host.show_hint("Your companion noses past the look-alike gaps to the one that truly goes through." if mine
			else "A companion noses out the gap that goes through.")


## A ward opened (server-confirmed): mark it, hoist the slab into a lintel (visual), and DROP its
## collider (the host rebuilds the solids without it and re-hands them to both bodies) so the doorway is
## truly walkable — for everyone present, whoever's companion opened it.
func _open_ward(ward: Dictionary) -> void:
	ward["open"] = true
	_seeking = false
	var sri := int(ward.get("slab_render_index", -1))
	if sri >= 0:
		_world_art.open_slab(sri)
	_host.rebuild_solids_dropping(String(ward.get("slab_id", "")))
	if bool(ward.get("is_paired", false)):
		# The Paired Hall: both plates held — the great door yields. A tiered waking (full with a second
		# pair present, muted alone). Stop holding (the open gate already skips _update_hall).
		ward["assigned"] = ""
		_wake_paired_hall(ward)
	elif bool(ward.get("is_light", false)):
		# The Cistern: the carried light catches — the brazier flares, the murals wake, and the dark lifts
		# (the gloom keys off this ward being open), as the sealed door grinds aside.
		_light_cistern(ward)
		_host.show_hint("The brazier catches — warm light floods the chamber, the old carvings wake, and the sealed door grinds open.")
	else:
		_host.show_hint("Stone grinds on stone — the slab rises, and the way lies open.")


## The render index (in world_art's draw list) of the interactable with this id, or -1. Props keep
## their original index there, so this resolves a ward's slab to the thing world_art draws.
func _render_index_for_id(id: String) -> int:
	for e in _interactables:
		if String(e.get("id", "")) == id:
			return int(e.get("render_index", -1))
	return -1


## The world-space rect of the named region (for the Cistern gloom), or an empty Rect2 if none.
func _region_rect(data: Dictionary, name: String) -> Rect2:
	if name == "":
		return Rect2()
	for r in data.get("regions", []):
		if String(r.get("id", "")) == name:
			var mn := WorldData.to_vec2(r["min"])
			return Rect2(mn, WorldData.to_vec2(r["max"]) - mn)
	return Rect2()


## True if any ward is still shut (per our mirror of the server state) — gates the "Go look" affordance.
func _any_ward_unopened() -> bool:
	for w in _wards:
		if not bool(w["open"]):
			return true
	return false


## The ward whose slab has this id (empty dict if none) — for the examine-the-slab nudge.
func _ward_for_slab(slab_id: String) -> Dictionary:
	for w in _wards:
		if String(w["slab_id"]) == slab_id:
			return w
	return {}


## The ward with this id (empty dict if none) — for applying server ward-state echoes.
func _ward_by_id(id: String) -> Dictionary:
	for w in _wards:
		if String(w["id"]) == id:
			return w
	return {}
