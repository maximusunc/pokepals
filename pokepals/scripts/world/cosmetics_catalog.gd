class_name CosmeticsCatalog
extends RefCounted
## The shared dictionary of every cosmetic the player could wear, loaded from
## data/cosmetics.json. Pure data — no scene tree, no texture loading, no render
## references — so it stays portable (the same catalog could be served from a world
## or a server later) and is trivially testable headless. It answers "what items
## exist?", "what slots are there and in what draw order?", and "what's the base
## default for this slot?". The PRESENTATION layer (AvatarCompositor) is what turns a
## resolved item's 'sheet' into an actual Texture2D; this layer never touches the GPU.
##
## Mirrors the role ArtStyle plays for the world's palette, but for the player's
## wardrobe — and like every loader here, a missing/partial file degrades to empty
## rather than crashing, so callers fall back to defaults.

var _slots: Array = []        # [ { id, z, required } ], as authored (draw order = ascending z)
var _color_slots: Array = []  # [ { id, applies_to, default, ramps } ]
var _items: Dictionary = {}   # id -> item definition dict


## Load the catalog from cosmetics.json, falling back to an empty catalog if the file
## is missing or malformed (callers then see no items / no slots and cope).
static func load_catalog(path := "res://data/cosmetics.json") -> CosmeticsCatalog:
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		data = WorldData.load_json(path)
	return from_data(data)


## Build a catalog from an already-parsed dict (used by tests too).
static func from_data(data: Dictionary) -> CosmeticsCatalog:
	var c := CosmeticsCatalog.new()
	for s in data.get("slots", []):
		if s is Dictionary and s.has("id"):
			c._slots.append(s)
	for cs in data.get("color_slots", []):
		if cs is Dictionary and cs.has("id"):
			c._color_slots.append(cs)
	# Skip the doc-only "_comment" keys; real items are objects with a "slot".
	for key in data.get("items", {}):
		var it: Variant = data["items"][key]
		if it is Dictionary and it.has("slot"):
			c._items[key] = it
	return c


## The paper-doll slots in authored order. Each is { id, z, required }.
func slots() -> Array:
	return _slots


## The slot ids sorted back-to-front (ascending z) — the order layers must be drawn in.
func slots_by_z() -> Array:
	var ids: Array = []
	var sorted := _slots.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("z", 0)) < float(b.get("z", 0)))
	for s in sorted:
		ids.append(String(s["id"]))
	return ids


## The color (palette) slots: [ { id, applies_to, default, ramps } ].
func color_slots() -> Array:
	return _color_slots


## Is this a real slot id?
func has_slot(slot: String) -> bool:
	for s in _slots:
		if String(s["id"]) == slot:
			return true
	return false


## The draw order (z) for a slot, defaulting to an item's own z elsewhere if unknown.
func slot_z(slot: String) -> float:
	for s in _slots:
		if String(s["id"]) == slot:
			return float(s.get("z", 0))
	return 0.0


## Must this slot always resolve to an item (a required base layer like the body)?
func slot_required(slot: String) -> bool:
	for s in _slots:
		if String(s["id"]) == slot:
			return bool(s.get("required", false))
	return false


## An item definition by id, or an empty dict if unknown.
func item(id: String) -> Dictionary:
	return _items.get(id, {})


func has_item(id: String) -> bool:
	return _items.has(id)


## The slot an item fills, or "" if the item is unknown.
func item_slot(id: String) -> String:
	return String(_items.get(id, {}).get("slot", ""))


## Every base item id — the cosmetics owned by every player from the start.
func base_item_ids() -> Array:
	var out: Array = []
	for id in _items:
		if String(_items[id].get("origin", "")) == "base":
			out.append(id)
	return out


## The base default item id for a slot (the one tagged default_for == slot), or "" if
## the slot has no base default. This is what a required slot falls back to so the
## avatar can never render empty.
func default_item_for_slot(slot: String) -> String:
	for id in _items:
		if String(_items[id].get("default_for", "")) == slot:
			return id
	return ""
