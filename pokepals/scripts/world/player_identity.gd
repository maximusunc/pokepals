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
##
## DEV/TEST OVERRIDE: two instances of the project on one machine share the same user:// dir, so they
## share one token — and the server (keyed by user_id) would treat them as the SAME player, who can't
## see themselves. To test multiplayer locally, give each instance a distinct token via the env var
## POKEPALS_TOKEN or the command-line user arg `--token=...` (after a `--`), e.g.:
##   godot --path . -- --token=alice      # instance 1
##   godot --path . -- --token=bob        # instance 2
## An overridden token is NOT persisted to disk (it's a transient test identity).

const PATH := "user://player_id.json"

var _id := ""


## This device's stable player token, generating + persisting one on first call. Honors a dev/test
## override (env var / command-line) so same-host instances can act as distinct players.
func id() -> String:
	if _id != "":
		return _id
	var override := _token_override()
	if override != "":
		_id = override
		return _id
	var saved := SaveStore.load_json(PATH)
	var existing := String(saved.get("id", ""))
	if existing != "":
		_id = existing
	else:
		_id = _generate()
		SaveStore.save_json(PATH, { "id": _id })
	return _id


## A token from the environment or the command line, for local multiplayer testing. Empty if none.
## Scans both the user args (after `--`) and the full arg list, so it works whether you pass
## `--token=` via a terminal launch or the editor's "Customize Run Instances" arguments field.
func _token_override() -> String:
	var env := OS.get_environment("POKEPALS_TOKEN")
	if env != "":
		return env
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--token="):
			return arg.substr("--token=".length())
	return ""


## A 128-bit random token as hex. Crypto's RNG is cryptographically strong, so collisions across
## players are effectively impossible — important since the token is also the access credential.
func _generate() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
