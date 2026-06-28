class_name RuinMechanisms
extends RefCounted
## The Ruin's pair-operated mechanisms as PURE LOGIC. The ancient builders made this place to be
## worked by a person AND their companion together: a hidden weight-plate, uncovered by the
## companion's search, raises a linked slab once the companion settles its weight on it. The
## GEOMETRY — where a plate hides, how near the companion must search to uncover it, how the slab
## looks lifting — lives in the controller/spec (presentation). THIS owns only the RULES: a plate
## starts hidden, a search uncovers it, weight on an uncovered plate opens its slab, and a Threshold
## slab LATCHES open once raised (the builders meant the doorway to stay). State in, state out — no
## nodes, no rendering, no filesystem — so it's unit-testable, runs headless, and is portable to a
## server later (where shared co-op ward state will eventually live).
##
## The shape generalises past the Threshold: more wards (one plate→one slab) cover the later rooms,
## and a non-latching ward (open only while weighted) is what the Paired Hall's "the mechanism slips
## the moment the companion leaves" beat is built from — already expressible here, unused for now.

# One WARD: a hidden plate linked to a slab.
#   found    — the search has uncovered the plate (the companion pawed the moss away).
#   occupied — weight rests on the plate right now (the companion is standing on it).
#   open     — the slab is raised.
#   latch    — once open, STAY open even after the plate clears (the Threshold doorway). A
#              non-latching ward falls shut the instant the weight leaves (a later-room mechanism).
var _wards: Dictionary = {}  # id -> { found, occupied, open, latch }


## Declare a ward. Idempotent on id (re-adding resets it), so a fresh visit lays the Ruin out clean.
func add_ward(id: String, latch: bool = true) -> void:
	_wards[id] = { "found": false, "occupied": false, "open": false, "latch": latch }


## The companion's search uncovered this plate. Idempotent — uncovering an already-found plate is a
## harmless no-op (newly_found=false). Returns { found, newly_found, open }. Because opening is
## recomputed from found AND occupied, this also opens the slab if the companion was already standing
## where the (until-now buried) plate lay — so the uncover/settle ORDER never matters.
func uncover(id: String) -> Dictionary:
	if not _wards.has(id):
		return { "found": false, "newly_found": false, "open": false }
	var w: Dictionary = _wards[id]
	var newly := not bool(w["found"])
	w["found"] = true
	var newly_open := _recompute(w)
	return { "found": true, "newly_found": newly, "open": bool(w["open"]), "newly_open": newly_open }


## Set whether weight rests on this plate right now (the companion settling on / stepping off it).
## Opening requires the plate to be FOUND as well — standing on still-buried moss engages nothing.
## Returns { occupied, open, newly_open }. A latched slab stays open once raised; a non-latching one
## follows the weight (this is the seam the Paired Hall's "slips when it leaves" beat will use).
func set_occupied(id: String, occupied: bool) -> Dictionary:
	if not _wards.has(id):
		return { "occupied": false, "open": false, "newly_open": false }
	var w: Dictionary = _wards[id]
	w["occupied"] = occupied
	var newly_open := _recompute(w)
	return { "occupied": occupied, "open": bool(w["open"]), "newly_open": newly_open }


## Recompute open-state from found && occupied, honouring the latch, and report whether it just
## OPENED this call (false→true) so the controller can fire the one-time "slab rises" flourish.
## Engaging (found AND weighted) always opens; releasing only closes a non-latching ward — a latched
## one, once open, stays open. Order-independent, which is why uncover() and set_occupied() both call it.
func _recompute(w: Dictionary) -> bool:
	var was_open := bool(w["open"])
	if bool(w["found"]) and bool(w["occupied"]):
		w["open"] = true
	elif not bool(w["latch"]):
		w["open"] = false
	# latched + currently open + now released → leave it open (sticky).
	return bool(w["open"]) and not was_open


func is_found(id: String) -> bool:
	return _wards.has(id) and bool(_wards[id]["found"])


func is_occupied(id: String) -> bool:
	return _wards.has(id) and bool(_wards[id]["occupied"])


func is_open(id: String) -> bool:
	return _wards.has(id) and bool(_wards[id]["open"])


## Every declared ward id, for the controller to drive its referee loop over.
func ward_ids() -> Array:
	return _wards.keys()
