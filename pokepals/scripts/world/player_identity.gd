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

var _id := ""


## This device's stable player token, generating + persisting one on first call.
func id() -> String:
	if _id != "":
		return _id
	var saved := SaveStore.load_json(PATH)
	var existing := String(saved.get("id", ""))
	if existing != "":
		_id = existing
	else:
		_id = _generate()
		SaveStore.save_json(PATH, { "id": _id })
	return _id


## A 128-bit random token as hex. Crypto's RNG is cryptographically strong, so collisions across
## players are effectively impossible — important since the token is also the access credential.
func _generate() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
