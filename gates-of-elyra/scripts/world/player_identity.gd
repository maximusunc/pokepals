extends Node
## PlayerIdentity — the ONE piece of local persistence in the online-only world.
##
## The companion's grown self and the wardrobe live on the SERVER now; nothing about the game is
## saved to this device. What we keep locally is a single stable, random *token* — a credential,
## not game data — so the server can recognize a returning player and hand back the right companion.
## No accounts: the token IS the identity. It's minted once on first launch and kept in
## user://player_id.json; wiping that file makes this device a brand-new player.
##
## Registered as the "PlayerIdentity" autoload (see project.godot). Reachable as PlayerIdentity.id().

const PATH := "user://player_id.json"
## The game was called "Kithbound" until 2026-11. Desktop builds keep user:// in a folder named after
## the game, so a returning player's token is still in the old folder; it is adopted once (copied to
## PATH) so they keep their companion. Where there is no such file (a new player, or a platform that
## keeps user:// elsewhere) nothing happens.
const LEGACY_NAME := "Kithbound"

var _id := ""


## This device's stable player token, generating + persisting one on first call.
func id() -> String:
	if _id != "":
		return _id
	var saved := SaveStore.load_json(PATH)
	var existing := String(saved.get("id", ""))
	if existing == "":
		existing = _legacy_id()
		if existing != "":
			SaveStore.save_json(PATH, { "id": existing })
	if existing != "":
		_id = existing
	else:
		_id = _generate()
		SaveStore.save_json(PATH, { "id": _id })
	return _id


## The token saved under the game's old name, or "" if there is none.
func _legacy_id() -> String:
	var old := OS.get_user_data_dir().get_base_dir().path_join(LEGACY_NAME).path_join("player_id.json")
	return String(SaveStore.load_json(old).get("id", ""))


## A 128-bit random token as hex. Crypto's RNG is cryptographically strong, so collisions across
## players are effectively impossible — important since the token is also the access credential.
func _generate() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
