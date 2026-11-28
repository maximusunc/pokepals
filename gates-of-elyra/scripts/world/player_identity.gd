extends Node
## PlayerIdentity — the ONE piece of local persistence in the online-only world.
##
## The companion's grown self and the wardrobe live on the SERVER now; nothing about the game is
## saved to this device. What we keep locally is a single stable, random *token* — a credential,
## not game data — so the server can recognize a returning player and hand back the right companion.
## No passwords: the token is THIS DEVICE's secret. It's minted once on first launch and kept in
## user://player_id.json; wiping that file makes this device a brand-new player. One player can have
## several devices, each with its own token: a transfer code links a new device to an existing player
## (issue 175), and the new device then ADOPTS a token the server has tied to that player (adopt()).
## The token is never sent over the socket itself: Net trades it for a short-lived ticket first.
##
## Registered as the "PlayerIdentity" autoload (see project.godot). Reachable as PlayerIdentity.id().

const PATH := "user://player_id.json"
## The game was called "Kithbound" until 2026-11. Desktop builds keep user:// in a folder named after
## the game, so a returning player's token is still in the old folder; it is adopted once (copied to
## PATH) so they keep their companion. Where there is no such file (a new player, or a platform that
## keeps user:// elsewhere) nothing happens.
const LEGACY_NAME := "Kithbound"

## Where the token is kept. Only a test changes it (to play two devices in one process).
var path := PATH

var _id := ""


## This device's stable player token, generating + persisting one on first call.
func id() -> String:
	if _id != "":
		return _id
	var saved := SaveStore.load_json(path)
	var existing := String(saved.get("id", ""))
	if existing == "" and path == PATH:
		existing = _legacy_id()
		if existing != "":
			SaveStore.save_json(path, { "id": existing })
	if existing != "":
		_id = existing
	else:
		_id = _generate()
		SaveStore.save_json(path, { "id": _id })
	return _id


## Make `token` this device's identity from now on (a transfer code linked it to a player, or the
## player chose to start fresh). The token it replaces is kept in the file under "previous", so
## nothing is ever destroyed: a mistake can be undone by hand.
func adopt(token: String) -> void:
	if token == "":
		return
	var saved := SaveStore.load_json(path)
	var previous: Array = saved.get("previous", []) if saved.get("previous") is Array else []
	var old := String(saved.get("id", _id))
	if old != "" and old != token and not previous.has(old):
		previous.append(old)
	_id = token
	SaveStore.save_json(path, { "id": token, "previous": previous })


## A brand-new token, not yet anyone's (what a new device offers when it redeems a code).
func fresh_token() -> String:
	return _generate()


## A short, friendly name for this device, for the other devices' lists ("Chrome on Android",
## "Windows PC", "iPhone"). Nothing personal: the platform and, on the web, the browser.
func device_name() -> String:
	var ua := ""
	if OS.has_feature("web"):
		var nav = JavaScriptBridge.get_interface("navigator")
		if nav != null:
			ua = str(nav.userAgent)
	return DeviceLink.friendly_name(OS.get_name(), OS.get_model_name(), ua)


## The token saved under the game's old name, or "" if there is none.
func _legacy_id() -> String:
	var old := OS.get_user_data_dir().get_base_dir().path_join(LEGACY_NAME).path_join("player_id.json")
	return String(SaveStore.load_json(old).get("id", ""))


## A 128-bit random token as hex. Crypto's RNG is cryptographically strong, so collisions across
## players are effectively impossible — important since the token is also the access credential.
func _generate() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
