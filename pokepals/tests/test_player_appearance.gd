class_name TestPlayerAppearance
## Tests for the player's persistent look — the wardrobe (owned) and loadout (equipped)
## that travel through every world. Pure data in, pure data out (no nodes, no filesystem
## for the synthetic-catalog cases), so this also documents the appearance save schema and
## the can-never-render-empty invariant.

static func run_all() -> int:
	var fails := 0
	print("TestPlayerAppearance")
	var catalog := _test_catalog()
	fails += _test_default_owns_base_and_equips_defaults(catalog)
	fails += _test_default_resolves_base_layer(catalog)
	fails += _test_grant_is_idempotent_and_validated(catalog)
	fails += _test_equip_requires_ownership_and_matching_slot(catalog)
	fails += _test_equipping_layers_it_in_z_order(catalog)
	fails += _test_required_slot_falls_back_to_default(catalog)
	fails += _test_unequip_respects_required(catalog)
	fails += _test_set_color_is_validated(catalog)
	fails += _test_round_trips(catalog)
	fails += _test_from_dict_drops_stale_state(catalog)
	fails += _test_from_dict_fills_missing(catalog)
	fails += _test_shipped_catalog_base_set()
	fails += _test_resolved_layers_carry_palette_color(catalog)
	fails += _test_shipped_catalog_wardrobe_slots()
	fails += _test_shipped_ramp_swatches()
	fails += _test_shipped_wardrobe_round_trip()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


# A small, self-contained catalog so the assertions don't depend on the shipped art set:
# a required body (with a base default), an optional headwear, plus a second body the player
# does NOT own by default, and one color slot over the body.
static func _test_catalog() -> CosmeticsCatalog:
	return CosmeticsCatalog.from_data({
		"slots": [
			{ "id": "body", "z": 0, "required": true },
			{ "id": "headwear", "z": 60 },
		],
		"color_slots": [
			{ "id": "skin_tone", "applies_to": "body", "default": "warm", "ramps": ["fair", "warm", "deep"] },
		],
		"items": {
			"base:body": { "slot": "body", "origin": "base", "default_for": "body", "sheet": "res://x/body.png" },
			"base:hat": { "slot": "headwear", "origin": "base", "sheet": "res://x/hat.png" },
			"world:crown": { "slot": "headwear", "origin": "thornfen", "sheet": "res://x/crown.png" },
			"world:robe": { "slot": "body", "origin": "thornfen", "sheet": "res://x/robe.png" },
		},
	})


static func _test_default_owns_base_and_equips_defaults(catalog: CosmeticsCatalog) -> int:
	var a := PlayerAppearance.make_default(catalog)
	var fails := 0
	fails += _ok(a.is_owned("base:body"), "owns the base body by default")
	fails += _ok(a.is_owned("base:hat"), "owns the base hat by default")
	fails += _ok(not a.is_owned("world:crown"), "does NOT own a world-granted item by default")
	fails += _ok(String(a.equipped.get("body", "")) == "base:body", "equips the base default in a required slot")
	fails += _ok(String(a.colors.get("skin_tone", "")) == "warm", "picks the default color ramp")
	return fails


static func _test_default_resolves_base_layer(catalog: CosmeticsCatalog) -> int:
	var a := PlayerAppearance.make_default(catalog)
	var layers := a.resolved_layers(catalog)
	var fails := 0
	# A fresh look with only the base body equipped resolves to exactly that one layer,
	# carrying the body's skin_tone palette — this is the "identical to today" base render.
	fails += _ok(layers.size() == 1, "a fresh look resolves to a single base body layer")
	fails += _ok(String(layers[0]["id"]) == "base:body", "the base layer is the base body")
	fails += _ok(String(layers[0]["palette"]) == "warm", "the body layer carries its color-slot palette")
	return fails


static func _test_grant_is_idempotent_and_validated(catalog: CosmeticsCatalog) -> int:
	var a := PlayerAppearance.make_default(catalog)
	var fails := 0
	fails += _ok(a.grant(catalog, "world:crown"), "granting a new item returns true")
	fails += _ok(a.is_owned("world:crown"), "the granted item is now owned")
	fails += _ok(not a.grant(catalog, "world:crown"), "re-granting an owned item returns false (idempotent)")
	fails += _ok(not a.grant(catalog, "nope:unknown"), "granting an unknown item is refused")
	return fails


static func _test_equip_requires_ownership_and_matching_slot(catalog: CosmeticsCatalog) -> int:
	var a := PlayerAppearance.make_default(catalog)
	var fails := 0
	# Can't wear what you don't own.
	fails += _ok(not a.equip(catalog, "world:crown"), "cannot equip an unowned item")
	a.grant(catalog, "world:crown")
	fails += _ok(a.equip(catalog, "world:crown"), "can equip once owned")
	fails += _ok(String(a.equipped.get("headwear", "")) == "world:crown", "the item lands in its own slot")
	fails += _ok(not a.equip(catalog, "nope:unknown"), "cannot equip an unknown item")
	return fails


static func _test_equipping_layers_it_in_z_order(catalog: CosmeticsCatalog) -> int:
	var a := PlayerAppearance.make_default(catalog)
	a.equip(catalog, "base:hat")
	var layers := a.resolved_layers(catalog)
	var fails := 0
	fails += _ok(layers.size() == 2, "body + hat resolve to two layers")
	# body (z 0) must come before headwear (z 60): back-to-front draw order.
	fails += _ok(String(layers[0]["id"]) == "base:body" and String(layers[1]["id"]) == "base:hat", "layers are ordered back-to-front by z")
	return fails


static func _test_required_slot_falls_back_to_default(catalog: CosmeticsCatalog) -> int:
	var a := PlayerAppearance.make_default(catalog)
	# Corrupt the equip so the required body slot holds nothing valid...
	a.equipped["body"] = ""
	var layers := a.resolved_layers(catalog)
	var fails := 0
	fails += _ok(layers.size() == 1 and String(layers[0]["id"]) == "base:body", "a required slot falls back to its base default (never renders empty)")
	return fails


static func _test_unequip_respects_required(catalog: CosmeticsCatalog) -> int:
	var a := PlayerAppearance.make_default(catalog)
	a.equip(catalog, "base:hat")
	var fails := 0
	fails += _ok(a.unequip(catalog, "headwear"), "can take off an optional slot")
	fails += _ok(not a.equipped.has("headwear"), "the optional slot is now bare")
	fails += _ok(not a.unequip(catalog, "body"), "cannot bare a required slot")
	fails += _ok(a.equipped.has("body"), "the required slot stays equipped")
	return fails


static func _test_set_color_is_validated(catalog: CosmeticsCatalog) -> int:
	var a := PlayerAppearance.make_default(catalog)
	var fails := 0
	fails += _ok(a.set_color(catalog, "skin_tone", "deep"), "can choose a valid ramp")
	fails += _ok(String(a.colors["skin_tone"]) == "deep", "the chosen ramp is stored")
	fails += _ok(not a.set_color(catalog, "skin_tone", "chartreuse"), "an unknown ramp is refused")
	fails += _ok(not a.set_color(catalog, "eye_color", "blue"), "an unknown color slot is refused")
	return fails


static func _test_round_trips(catalog: CosmeticsCatalog) -> int:
	var a := PlayerAppearance.make_default(catalog)
	a.grant(catalog, "world:crown")
	a.equip(catalog, "world:crown")
	a.set_color(catalog, "skin_tone", "deep")
	var r := PlayerAppearance.from_dict(a.to_dict(), catalog)
	var fails := 0
	fails += _ok(r.is_owned("world:crown"), "owned wardrobe survives a round-trip")
	fails += _ok(String(r.equipped.get("headwear", "")) == "world:crown", "equipped loadout survives a round-trip")
	fails += _ok(String(r.colors.get("skin_tone", "")) == "deep", "color choice survives a round-trip")
	return fails


# A stale save (an equip for an item no longer owned, a color ramp that's gone) must load
# without producing a broken avatar — the invalid bits are dropped, defaults cover them.
static func _test_from_dict_drops_stale_state(catalog: CosmeticsCatalog) -> int:
	var stale := {
		"version": 1,
		"owned": { "base:body": true, "base:hat": true },  # crown NOT owned...
		"equipped": { "body": "base:body", "headwear": "world:crown" },  # ...but saved as worn
		"colors": { "skin_tone": "chartreuse" },  # an invalid ramp
	}
	var r := PlayerAppearance.from_dict(stale, catalog)
	var fails := 0
	fails += _ok(not r.equipped.has("headwear") or String(r.equipped["headwear"]) != "world:crown", "an equip for an unowned item is dropped on load")
	fails += _ok(String(r.colors.get("skin_tone", "")) == "warm", "an invalid color ramp falls back to the default")
	fails += _ok(String(r.equipped.get("body", "")) == "base:body", "the required body still resolves after dropping stale state")
	return fails


static func _test_from_dict_fills_missing(catalog: CosmeticsCatalog) -> int:
	# An all-but-empty save still yields a complete, valid default look.
	var r := PlayerAppearance.from_dict({ "version": 1 }, catalog)
	var fails := 0
	fails += _ok(r.is_owned("base:body"), "a partial save still owns the base set")
	fails += _ok(String(r.equipped.get("body", "")) == "base:body", "a partial save still equips the base default")
	return fails


# Guards the SHIPPED catalog: the base set must have a body default so the real player
# avatar always resolves at least one layer (the base render the seam preserves).
static func _test_shipped_catalog_base_set() -> int:
	var catalog := CosmeticsCatalog.load_catalog("res://data/cosmetics.json")
	var a := PlayerAppearance.make_default(catalog)
	var layers := a.resolved_layers(catalog)
	var fails := 0
	fails += _ok(catalog.default_item_for_slot("body") != "", "the shipped catalog defines a base body default")
	fails += _ok(layers.size() >= 1, "the shipped default look resolves at least the base body layer")
	return fails


# Every resolved layer carries a 'palette_color' the compositor recolors dye layers onto. With the
# synthetic catalog (no swatches) it's empty — the "draw at native colors" path.
static func _test_resolved_layers_carry_palette_color(catalog: CosmeticsCatalog) -> int:
	var a := PlayerAppearance.make_default(catalog)
	var layers := a.resolved_layers(catalog)
	var fails := 0
	fails += _ok(layers[0].has("palette_color"), "resolved layers carry a palette_color field")
	fails += _ok((layers[0]["palette_color"] as Array).is_empty(), "no swatch declared -> palette_color empty (draw native)")
	return fails


# The SHIPPED wardrobe: the paper-doll slots the pixel-art avatar needs, and a clothed starter loadout
# (body + clothing + footwear + hair equipped; accessory/headwear left bare) with real choices per axis.
static func _test_shipped_catalog_wardrobe_slots() -> int:
	var catalog := CosmeticsCatalog.load_catalog("res://data/cosmetics.json")
	var a := PlayerAppearance.make_default(catalog)
	var fails := 0
	for slot in ["body", "outfit", "footwear", "accessory", "hair", "headwear"]:
		fails += _ok(catalog.has_slot(slot), "shipped catalog has the '%s' slot" % slot)
	fails += _ok(String(a.equipped.get("body", "")) != "", "starter equips a body build")
	fails += _ok(String(a.equipped.get("outfit", "")) != "", "starter equips clothing")
	fails += _ok(String(a.equipped.get("footwear", "")) != "", "starter equips footwear")
	fails += _ok(String(a.equipped.get("hair", "")) != "", "starter equips hair")
	fails += _ok(not a.equipped.has("accessory"), "starter leaves accessory bare")
	fails += _ok(not a.equipped.has("headwear"), "starter leaves headwear bare")
	var body_owned := 0
	for id in catalog.items_in_slot("body"):
		if a.is_owned(id):
			body_owned += 1
	fails += _ok(body_owned >= 2, "player owns multiple body builds to choose from")
	return fails


# The color swatches feed the recolor: a valid ramp resolves to an [r,g,b]; unknowns resolve to [].
static func _test_shipped_ramp_swatches() -> int:
	var catalog := CosmeticsCatalog.load_catalog("res://data/cosmetics.json")
	var fails := 0
	fails += _ok(catalog.ramp_color("skin_tone", "warm").size() == 3, "a skin_tone ramp resolves to an [r,g,b] swatch")
	fails += _ok(catalog.ramp_color("hair_color", "ink").size() == 3, "a hair_color ramp resolves to an [r,g,b] swatch")
	fails += _ok(catalog.ramp_color("skin_tone", "nope").is_empty(), "an unknown ramp has no swatch")
	fails += _ok(catalog.ramp_color("nope", "warm").is_empty(), "an unknown color slot has no swatch")
	return fails


# End-to-end mirror of what the customizer does against the SHIPPED catalog: swap to another owned body
# build and choose a skin tone, then confirm the resolved body layer reflects both (id + recolor swatch).
static func _test_shipped_wardrobe_round_trip() -> int:
	var catalog := CosmeticsCatalog.load_catalog("res://data/cosmetics.json")
	var a := PlayerAppearance.make_default(catalog)
	var fails := 0
	var alt_body := ""
	for id in catalog.items_in_slot("body"):
		if a.is_owned(id) and String(a.equipped.get("body", "")) != id:
			alt_body = id
			break
	fails += _ok(alt_body != "" and a.equip(catalog, alt_body), "can equip an alternate owned body build")
	fails += _ok(a.set_color(catalog, "skin_tone", "deep"), "can choose the 'deep' skin tone")
	var body_layer := {}
	for l in a.resolved_layers(catalog):
		if String(l.get("slot", "")) == "body":
			body_layer = l
	fails += _ok(String(body_layer.get("id", "")) == alt_body, "the chosen body build resolves as the body layer")
	fails += _ok(String(body_layer.get("palette", "")) == "deep", "the body layer carries the chosen skin ramp")
	var pc: Array = body_layer.get("palette_color", [])
	fails += _ok(pc.size() == 3 and pc == catalog.ramp_color("skin_tone", "deep"), "the body layer carries the 'deep' swatch for recolor")
	return fails
