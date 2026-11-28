class_name PackLogic
extends RefCounted
## The pure decisions behind world packs (see AssetPacks, which does the downloading): where the
## server's HTTP face is, and which of a world's packs still have to be fetched. No nodes, no network,
## no autoloads: state in, answer out, so it's unit-testable and portable.


## "wss://host/ws" -> "https://host/"; "ws://10.0.0.5:4000/ws" -> "http://10.0.0.5:4000/". The server's
## HTTP face is on the same host and port as its socket.
static func http_base(socket_url: String) -> String:
	var u := socket_url.strip_edges()
	if u.begins_with("wss://"):
		u = "https://" + u.substr(6)
	elif u.begins_with("ws://"):
		u = "http://" + u.substr(5)
	var slash := u.find("/", u.find("://") + 3)
	if slash >= 0:
		u = u.substr(0, slash)
	return u + "/"


## The descriptors in `packs` whose art isn't loadable yet. A pack counts as present if its probe file
## exists, whether mounted earlier, bundled in the build, or simply running from the editor. A
## descriptor with no probe can't be shown to be present, so it counts as missing.
static func missing(packs: Array) -> Array:
	var out: Array = []
	for pack in packs:
		if not ResourceLoader.exists(String(pack.get("probe", ""))):
			out.append(pack)
	return out
