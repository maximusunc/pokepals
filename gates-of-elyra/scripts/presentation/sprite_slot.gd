class_name SpriteSlot
extends RefCounted
## Optional drop-in art. If an art.json entry sets "render": "sprite" and points at an
## image that actually exists, load it; otherwise return null so the caller falls back
## to procedural drawing. A referenced-but-missing file degrades silently — so the repo
## (and the headless smoke test) stay green with zero art committed, and you can replace
## any one thing (a tree, a prop, the player, the companion) with your OWN vector art,
## one piece at a time, by editing art.json alone.
##
## Authoring your own art (done at a desktop, in the Godot editor):
##  - Make a flat-vector image in any tool. SVG is ideal (crisp, scalable); PNG works too.
##  - Drop it under assets/sprites/ and let Godot import it. For SVG, the import "scale"
##    (and editor/scale_with_dpi) decides its on-screen size — the game's base resolution
##    is 640x360, so author/scale accordingly and re-import in the editor.
##  - Commit BOTH the .svg/.png AND its generated .import file, or it won't load.
##  - Point art.json at it, e.g. characters.companion = {"render":"sprite",
##    "sprite":"res://assets/sprites/companion.svg"}. Set render back to "procedural" to
##    return to the built-in look.

## Resolve the image at config key `key` (default "sprite") to a texture, or null.
## The `key` lets one entity name several images — e.g. a tree splits its art into a
## stationary "trunk" and a wind-swayed "canopy" so only the crown catches the wind
## (see TreeView). A missing/absent file still degrades silently to procedural.
static func resolve(cfg: Dictionary, key := "sprite") -> Texture2D:
	if String(cfg.get("render", "procedural")) != "sprite":
		return null
	var path := String(cfg.get(key, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


## Draw a sprite anchored bottom-centre at the node's origin (feet on the ground),
## with an optional horizontal offset (e.g. wind sway). Keeps user art aligned the
## same way the procedural avatars/trees are.
static func draw(ci: CanvasItem, tex: Texture2D, offset_x := 0.0) -> void:
	var sz := tex.get_size()
	ci.draw_texture(tex, Vector2(offset_x - sz.x * 0.5, 8.0 - sz.y))
