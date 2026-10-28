class_name WorldDirectory
extends RefCounted
## The Gateway's world-directory STATE: the current search, the pages of world cards the server has
## answered with, and how they shelve for display. Pure logic, no nodes — the WorldPicker (presentation)
## asks it what to draw and Net carries the requests — so it's unit-testable like NavAgent.
##
## Searches race: typing "riv" then "rive" fires two requests, and their answers can land in either
## order. Every request gets a fresh number, and only the answer to the LATEST one is kept, so a stale
## page can never overwrite the search you're actually looking at.

var _query := ""
var _req := 0          # the number of the latest request sent; answers to any other are stale
var _loading := false  # a request is in flight
var _more := false     # the server said another page exists past what we hold
var _worlds: Array = []  # cards in server order (featured first, then by name)


## Start a fresh search for `query` (trimmed; blank = everything). Drops the held results. Returns the
## request number to send with it.
func begin_search(query: String) -> int:
	_query = query.strip_edges()
	_worlds = []
	_more = false
	return _begin()


## Ask for the next page of the current search. Returns its request number, or -1 when there's nothing
## more to fetch (no further page, or a request is already in flight).
func begin_more() -> int:
	if not _more or _loading:
		return -1
	return _begin()


## The offset the next request should start from (the cards already held).
func next_offset() -> int:
	return _worlds.size()


## Take an answer from the server. Returns true if it was adopted (the latest request, at the offset
## we expected); a stale or out-of-order page is ignored and returns false.
func accept(req: int, offset: int, worlds: Array, more: bool) -> bool:
	if req != _req or not _loading or offset != _worlds.size():
		return false
	_loading = false
	_more = more
	for w in worlds:
		var card := _clean_card(w)
		if not card.is_empty():
			_worlds.append(card)
	return true


func query() -> String:
	return _query


func is_loading() -> bool:
	return _loading


func has_more() -> bool:
	return _more


func worlds() -> Array:
	return _worlds


## The cards grouped into labelled shelves for display: [ { "title": String, "worlds": Array } ]. With
## no search, featured worlds get their own shelf above everything else; a search is one flat list of
## matches. Empty shelves are left out.
func sections() -> Array:
	if _query != "":
		return [] if _worlds.is_empty() else [{ "title": "Matches", "worlds": _worlds }]
	var featured: Array = []
	var rest: Array = []
	for w in _worlds:
		if bool(w["featured"]):
			featured.append(w)
		else:
			rest.append(w)
	var out: Array = []
	if not featured.is_empty():
		out.append({ "title": "Featured", "worlds": featured })
	if not rest.is_empty():
		out.append({ "title": "All worlds", "worlds": rest })
	return out


## A line for the list area when it has no cards to show ("" when it does).
func status_text() -> String:
	if not _worlds.is_empty():
		return ""
	if _loading:
		return "Looking for worlds…"
	if _query == "":
		return "No other worlds to visit yet."
	return "No worlds match \"%s\"." % _query


## How a world's live head-count reads on its card.
static func presence_text(players: int) -> String:
	if players <= 0:
		return "quiet"
	return "%d here" % players


func _begin() -> int:
	_req += 1
	_loading = true
	return _req


## A card from the wire, normalised (untrusted input: anything may be missing or the wrong type), or {}
## if it can't be travelled to (no world id).
static func _clean_card(w: Variant) -> Dictionary:
	if not (w is Dictionary):
		return {}
	var d := w as Dictionary
	var id := String(d.get("world_id", "")) if d.get("world_id") is String else ""
	if id == "":
		return {}
	var players: Variant = d.get("players", 0)
	var accent: Variant = d.get("accent")
	var tags: Variant = d.get("tags", [])
	return {
		"world_id": id,
		"name": String(d.get("name", "")) if d.get("name") is String and String(d.get("name")) != "" else "An unnamed world",
		"blurb": String(d.get("blurb", "")) if d.get("blurb") is String else "",
		"tags": tags if tags is Array else [],
		"accent": accent if accent is Array and (accent as Array).size() >= 3 else [],
		"featured": d.get("featured") is bool and bool(d.get("featured")),
		"players": int(players) if (players is int or players is float) else 0,
	}
