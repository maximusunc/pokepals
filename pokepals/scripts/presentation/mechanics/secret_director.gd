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

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt

var _entry: Dictionary = {}    # the secret's examinable entry (shared with the controller's list), or {}
var _claiming := false         # a claim is in flight; a second examine shouldn't send another


func setup(host: Node, companion: CompanionView, world_art: WorldArt) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	Net.secret_found.connect(_on_secret_found)
	Net.secret_refused.connect(_on_secret_refused)
	Net.discoveries_received.connect(_on_discoveries)


## Fold this world's secret (if it has one, and we haven't found it) into the world's props, as an
## examinable prop of kind "secret". Called during content layout, BEFORE the controller turns
## `combined` into its examine list, so the seed draws and prompts like any other prop.
func setup_secret(data: Dictionary, combined: Array) -> void:
	_entry = {}
	var secret: Dictionary = data.get("secret", {})
	if not secret.has("id") or Net.has_discovery(String(secret["id"])):
		return
	var prop: Dictionary = (secret.get("prop", {}) as Dictionary).duplicate(true)
	prop["id"] = "secret_" + String(secret["id"])
	prop["position"] = secret.get("position", [0, 0])
	prop["interactive"] = true
	prop["lore"] = String(secret.get("lore", ""))
	prop["secret"] = secret
	combined.append(prop)


## The controller built this prop's examine entry: keep it, so the finding can retire it.
func adopt_entry(entry: Dictionary) -> void:
	_entry = entry


## Whether an examine entry is a secret that's been taken (the controller's scans skip it).
static func is_taken(entry: Dictionary) -> bool:
	return bool(entry.get("_taken", false))


## Examining the secret: read its lore, let the companion amble over to look, and ask the server.
func examine(entry: Dictionary) -> void:
	_companion.notify_interaction(entry["pos"], String(entry["id"]), entry["tags"])
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
	if not _entry.is_empty() and not is_taken(_entry) and ids.has(String(_entry["secret"]["id"])):
		_take()


func _take() -> void:
	_entry["_taken"] = true
	_world_art.take_interactable(int(_entry["render_index"]))
	_host.secret_taken()
