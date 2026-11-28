class_name DeviceLink
extends RefCounted
## DeviceLink — the pure rules behind playing on more than one device (issue 175). No nodes, no
## network: strings and numbers in, strings and numbers out, so it's unit-tested (test_device_link.gd).
##
##   * the CODE a player reads off one device and types on another: 8 characters, shown "ABCD-EFGH",
##     typed any way (lower case, with or without the dash or spaces);
##   * where the server's plain HTTP lives, worked out from the socket address Net already knows;
##   * what the server's answer to "may I have a ticket?" means;
##   * a short, friendly name for this device ("Web browser on Android", "Windows PC", "iPhone");
##   * "Seen 5 minutes ago" for the device list.
##
## The redeem wait (asking again every 2 s until the other device answers) is LinkRedeem, beside this.

## How many characters a code has, without its dash.
const CODE_LENGTH := 8


## What the player typed, made comparable: upper case, with every dash, space and other separator
## taken out. Letters and digits only; anything else is dropped.
static func normalize(typed: String) -> String:
	var out := ""
	for ch in typed.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


## Whether what was typed is a whole code (8 letters or digits once the dashes and spaces are gone).
## Deliberately loose about WHICH letters: the server knows its own alphabet and answers "invalid".
static func is_complete(typed: String) -> bool:
	return normalize(typed).length() == CODE_LENGTH


## A code as it is shown: "ABCD-EFGH". Anything that isn't a whole code is shown as it normalizes.
static func format(code: String) -> String:
	var n := normalize(code)
	if n.length() != CODE_LENGTH:
		return n
	return n.substr(0, 4) + "-" + n.substr(4)


## The server's plain-HTTP base from its socket address: "wss://host/ws" -> "https://host",
## "ws://host:4000/ws" -> "http://host:4000". The socket's "/ws" mount (and any "/websocket" after it)
## is dropped; a path before the mount is kept, so a server behind a path prefix still works. "" if the
## address isn't a ws:// or wss:// one.
static func http_base(ws_url: String) -> String:
	var url := ws_url.strip_edges()
	var scheme := ""
	if url.begins_with("wss://"):
		scheme = "https://"
		url = url.substr(6)
	elif url.begins_with("ws://"):
		scheme = "http://"
		url = url.substr(5)
	else:
		return ""
	var q := url.find("?")
	if q >= 0:
		url = url.substr(0, q)
	url = url.rstrip("/")
	if url.ends_with("/websocket"):
		url = url.substr(0, url.length() - 10).rstrip("/")
	if url.ends_with("/ws"):
		url = url.substr(0, url.length() - 3).rstrip("/")
	if url == "":
		return ""
	return scheme + url


## What the server's answer to POST /session means: { kind: "ticket", ticket } (go and connect with it),
## { kind: "revoked" } (this device was signed out), or { kind: "failed" } (anything else: the usual
## couldn't-connect path). `body` is the parsed JSON body (null or anything else if it wasn't JSON).
static func ticket_outcome(status: int, body: Variant) -> Dictionary:
	var b: Dictionary = body if body is Dictionary else {}
	if status == 200 and b.get("ticket") is String and String(b["ticket"]) != "":
		return { "kind": "ticket", "ticket": String(b["ticket"]) }
	if status == 401 and String(b.get("error", "")) == "revoked":
		return { "kind": "revoked" }
	return { "kind": "failed" }


## A short, friendly name for a device, with nothing personal in it. `os_name` is OS.get_name()
## ("Windows", "macOS", "Linux", "Android", "iOS", "Web", ...), `model` OS.get_model_name() (e.g.
## "iPhone14,2", "iPad13,1"; "GenericDevice" where there's none), and `user_agent` the browser's on the
## web build ("" elsewhere).
static func friendly_name(os_name: String, model: String, user_agent := "") -> String:
	match os_name:
		"Web":
			return "%s on %s" % [_browser(user_agent), _web_platform(user_agent)] if user_agent != "" else "Web browser"
		"iOS":
			if model.begins_with("iPad"):
				return "iPad"
			return "iPhone"
		"Android":
			return "Android phone"
		"Windows":
			return "Windows PC"
		"macOS":
			return "Mac"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return "Linux PC"
	return "Device"


static func _browser(ua: String) -> String:
	# Order matters: Edge and Opera say "Chrome" too, and Chrome says "Safari".
	if ua.contains("Edg/"):
		return "Edge"
	if ua.contains("OPR/"):
		return "Opera"
	if ua.contains("Firefox/") or ua.contains("FxiOS/"):
		return "Firefox"
	if ua.contains("Chrome/") or ua.contains("CriOS/"):
		return "Chrome"
	if ua.contains("Safari/"):
		return "Safari"
	return "Web browser"


static func _web_platform(ua: String) -> String:
	if ua.contains("iPhone"):
		return "iPhone"
	if ua.contains("iPad"):
		return "iPad"
	if ua.contains("Android"):
		return "Android"
	if ua.contains("Windows"):
		return "Windows"
	if ua.contains("Mac OS X") or ua.contains("Macintosh"):
		return "Mac"
	if ua.contains("CrOS"):
		return "Chromebook"
	if ua.contains("Linux"):
		return "Linux"
	return "the web"


## "This device", or when another one was last here: "Here now" (online in the last 2 minutes), "Seen 5
## minutes ago", "Seen 3 hours ago", "Seen yesterday", "Seen 4 days ago", "Seen a while ago" (over a month).
## `last_seen_ms` is unix ms, or null when the server has never seen it. `now_ms` is unix ms too.
static func seen_text(last_seen_ms: Variant, now_ms: int) -> String:
	if not (last_seen_ms is int or last_seen_ms is float):
		return "Not seen yet"
	var mins := int(maxf(0.0, float(now_ms) - float(last_seen_ms)) / 60000.0)
	if mins < 2:
		return "Here now"
	if mins < 60:
		return "Seen %d minutes ago" % mins
	var hours := mins / 60
	if hours < 24:
		return "Seen an hour ago" if hours == 1 else "Seen %d hours ago" % hours
	var days := hours / 24
	if days == 1:
		return "Seen yesterday"
	if days <= 30:
		return "Seen %d days ago" % days
	return "Seen a while ago"


## "9:58" for the code's countdown: whole minutes and seconds left (never below 0:00).
static func countdown_text(seconds_left: float) -> String:
	var s := maxi(0, ceili(seconds_left))
	return "%d:%02d" % [s / 60, s % 60]
