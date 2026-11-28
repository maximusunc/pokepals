class_name WorldAreas
## Resolves which named AREA a world position falls in. An area's stable id is
## "world_id:region_id" (or just "world_id" when the position is in no named region —
## the world's open "wilds"). Two things fall out of that one rule:
##   • sub-regions of a single large world are distinct region_ids;
##   • separate worlds are distinct world_ids.
## Because the companion's familiarity map (its memory) is part of its persistent self and
## these ids are world-namespaced, it REMEMBERS every place across every world it has
## visited — revisiting a known area pays no fresh discovery, while a brand-new world is all
## novel. That is the seed of the "one companion, many worlds" north star.
##
## Pure and presentation-agnostic: a region is just { id, min, max } in world space; a
## different presentation (or a non-spatial world) is free to supply area ids however it
## likes — the companion logic only ever consumes the resolved string.

static func resolve(pos: Vector2, world_id: String, regions: Array) -> String:
	if world_id == "":
		return ""
	for r in regions:
		if not (r is Dictionary) or not (r.has("min") and r.has("max")):
			continue
		var mn: Vector2 = r["min"]
		var mx: Vector2 = r["max"]
		if pos.x >= mn.x and pos.x <= mx.x and pos.y >= mn.y and pos.y <= mx.y:
			return "%s:%s" % [world_id, String(r.get("id", "region"))]
	return world_id
