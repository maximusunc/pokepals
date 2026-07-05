class_name PlayerAppearance
extends RefCounted
## The player's persistent LOOK — the half of "you" that travels through every world,
## the visual mirror of CompanionSelf (the persistent mind). Pure data plus
## serialization: no scene tree, no texture loading, no render references, so it stays
## portable (it could be saved locally now and moved to an authoritative server later
## untouched) and is trivially testable headless. PRESENTATION (AvatarCompositor) turns
## the resolved layers into pixels; this class only decides WHAT is owned and worn.
##
## Two perspectives, kept as two fields:
##   owned:    the WARDROBE — the set of cosmetic ids the player has obtained, grown by
##             visiting worlds. { item_id: true }. Base items are always owned.
##   equipped: the LOADOUT — the currently worn item per paper-doll slot. { slot: id }.
##   colors:   the palette CHOICES per color slot (skin tone, hair color). { color_slot: ramp }.
##
## Invariant: every REQUIRED slot always resolves to something — equip() refuses an item
## the player doesn't own or that doesn't fit the slot, and resolution falls back to the
## slot's base default for anything missing/unknown, so the avatar can never render naked
## or broken (the same silent-fallback discipline as SpriteSlot/CosmeticsCatalog).
##
## from_dict() always starts from make_default() and layers saved values on top, so older
## save files keep loading as the catalog grows.

const SCHEMA_VERSION := 1

var owned: Dictionary = {}     # item_id -> true
var equipped: Dictionary = {}  # slot -> item_id
var colors: Dictionary = {}    # color_slot -> ramp id


## A fresh appearance seeded from the catalog: owns every base item, equips each slot's
## base default, and picks each color slot's default ramp. A brand-new player therefore
## has a complete, valid look with zero saved data.
static func make_default(catalog: CosmeticsCatalog) -> PlayerAppearance:
	var a := PlayerAppearance.new()
	for id in catalog.base_item_ids():
		a.owned[id] = true
	for slot_id in catalog.slots_by_z():
		var def := catalog.default_item_for_slot(slot_id)
		if def != "":
			a.equipped[slot_id] = def
	for cs in catalog.color_slots():
		a.colors[String(cs["id"])] = String(cs.get("default", ""))
	return a


## OBTAIN a cosmetic — the acquisition seam. Idempotent: adds the id to the wardrobe if
## the catalog knows it. Returns true if it was newly granted (false if already owned or
## unknown), so a caller can play a one-off "you found something to wear!" beat. Today this
## is called locally on a pickup; later the same call is driven by an authoritative server
## event, and this data class doesn't change.
func grant(catalog: CosmeticsCatalog, item_id: String) -> bool:
	if not catalog.has_item(item_id) or owned.has(item_id):
		return false
	owned[item_id] = true
	return true


func is_owned(item_id: String) -> bool:
	return owned.has(item_id)


## WEAR an owned item in its slot. Refuses (returns false) if the item is unknown, not
## owned, or doesn't belong to the slot it claims — so equipped can never hold something
## invalid. An empty item_id UNEQUIPS the slot (only allowed for non-required slots).
func equip(catalog: CosmeticsCatalog, item_id: String) -> bool:
	if item_id == "":
		return false
	if not catalog.has_item(item_id) or not owned.has(item_id):
		return false
	var slot := catalog.item_slot(item_id)
	if slot == "":
		return false
	equipped[slot] = item_id
	return true


## Bare a non-required slot (e.g. take off the hat). Refuses to clear a required slot,
## preserving the can-never-render-empty invariant.
func unequip(catalog: CosmeticsCatalog, slot: String) -> bool:
	if catalog.slot_required(slot):
		return false
	equipped.erase(slot)
	return true


## Choose a color ramp for a color slot (e.g. skin_tone -> "deep"). Validated against the
## slot's authored ramp choices; an unknown slot or ramp is refused.
func set_color(catalog: CosmeticsCatalog, color_slot: String, ramp: String) -> bool:
	for cs in catalog.color_slots():
		if String(cs["id"]) == color_slot:
			if String(ramp) in cs.get("ramps", []):
				colors[color_slot] = ramp
				return true
			return false
	return false


## RESOLVE the worn loadout into the ordered list of layers the compositor draws, back to
## front (ascending z). Pure DATA out — each layer is the item definition plus a 'palette'
## hint (the chosen ramp for whatever color slot targets this layer's slot, or "" for none).
## Required slots with nothing valid equipped fall back to their base default; an equipped
## item the catalog no longer knows is skipped (required slots still get their default). The
## presentation layer loads each 'sheet' and applies the palette; this stays GPU-free.
func resolved_layers(catalog: CosmeticsCatalog) -> Array:
	var layers: Array = []
	for slot_id in catalog.slots_by_z():
		var id := String(equipped.get(slot_id, ""))
		if id == "" or not catalog.has_item(id):
			# Nothing valid worn here — a required slot falls back to its base default.
			if catalog.slot_required(slot_id):
				id = catalog.default_item_for_slot(slot_id)
			if id == "" or not catalog.has_item(id):
				continue
		var def: Dictionary = catalog.item(id).duplicate(true)
		def["id"] = id
		def["palette"] = _palette_for_slot(catalog, slot_id)
		def["palette_color"] = _palette_color_for_slot(catalog, slot_id)
		layers.append(def)
	return layers


## The chosen color ramp that applies to a given paper-doll slot (e.g. the skin_tone ramp
## applies to "body"), or "" if no color slot targets it. Carried on the resolved layer for
## the deferred palette-swap shader to read.
func _palette_for_slot(catalog: CosmeticsCatalog, slot: String) -> String:
	for cs in catalog.color_slots():
		if String(cs.get("applies_to", "")) == slot:
			return String(colors.get(String(cs["id"]), cs.get("default", "")))
	return ""


## The [r,g,b] swatch (0..1) the compositor recolors this slot's grayscale layer onto — the
## chosen (or default) ramp's color for whatever color slot targets this slot, or [] if none
## (then the layer draws at its native colors). Pure data; the presentation layer does the pixels.
func _palette_color_for_slot(catalog: CosmeticsCatalog, slot: String) -> Array:
	for cs in catalog.color_slots():
		if String(cs.get("applies_to", "")) == slot:
			var ramp := String(colors.get(String(cs["id"]), cs.get("default", "")))
			return catalog.ramp_color(String(cs["id"]), ramp)
	return []


## Plain, JSON-serializable snapshot. Dictionaries are deep-copied so callers can't mutate
## our state by holding the returned dict.
func to_dict() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"owned": owned.duplicate(true),
		"equipped": equipped.duplicate(true),
		"colors": colors.duplicate(true),
	}


## Rebuild an appearance from a saved snapshot, starting from defaults so a partial/old save
## keeps loading as the catalog grows. Saved values are validated against the catalog: an
## equipped item that's no longer owned/known, or a color ramp that's gone, is dropped (the
## default already in place covers it), so a stale save can never produce a broken avatar.
static func from_dict(data: Dictionary, catalog: CosmeticsCatalog) -> PlayerAppearance:
	var a := make_default(catalog)
	if data.get("owned") is Dictionary:
		for id in data["owned"]:
			if catalog.has_item(String(id)):
				a.owned[String(id)] = true
	if data.get("equipped") is Dictionary:
		for slot_id in data["equipped"]:
			var id := String(data["equipped"][slot_id])
			# Only honor a saved equip that's still valid; equip() enforces own+slot.
			a.equip(catalog, id)
	if data.get("colors") is Dictionary:
		for cs in data["colors"]:
			a.set_color(catalog, String(cs), String(data["colors"][cs]))
	return a
