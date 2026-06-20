class_name PlayerView
extends Node2D
## The player avatar: reads input, moves smoothly, and draws a simple placeholder
## figure. Movement is presentation/input concern, kept light. It exposes
## `velocity` so the companion's brain can anticipate where the player is heading.
##
## Input is intentionally forgiving: arrow keys (ui_* actions), WASD (physical keys
## so it works on any layout), and an optional on-screen joystick for touch.

@export var speed := 118.0
@export var accel := 11.0
@export var joystick_path: NodePath
@export var cosmetics_path := "res://data/cosmetics.json"

const APPEARANCE_SAVE_PATH := "user://player_appearance.json"

var velocity := Vector2.ZERO
var _joystick: Node = null
var _time := 0.0
var _facing := Vector2.DOWN  # eased toward the movement direction, held when still
var _style: ArtStyle
# The player's persistent LOOK (owned wardrobe + worn loadout) and the shared catalog it
# resolves against — the inventory/customization seam. The avatar is composited from the
# worn layers (AvatarCompositor); _avatar_layers caches the loaded textures so _draw
# doesn't re-resolve every frame, refreshed only when the loadout changes.
var _catalog: CosmeticsCatalog
var _appearance: PlayerAppearance
var _avatar_layers: Array = []
var _solids: Array = []
var _bounds := Rect2()
var _body_radius := 6.0
var _margin := 2.0
var _collide := false


## Hand the avatar the world's barriers to collide against (trees, props, water, edge).
func set_solids(solids: Array, bounds: Rect2, body_radius: float, margin: float) -> void:
	_solids = solids
	_bounds = bounds
	_body_radius = body_radius
	_margin = margin
	_collide = true


func _ready() -> void:
	# Crisp pixel art: nearest-neighbour sampling on this node only, so the dropped-in
	# sprite stays sharp when the 640x360 view is scaled up — without touching how the
	# procedural world is filtered.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if joystick_path != NodePath(""):
		_joystick = get_node_or_null(joystick_path)
	if _style == null:
		_style = ArtStyle.load_style()
	# Load the wardrobe catalog and the player's saved look (or a fresh default that owns and
	# wears the base set), then resolve the worn loadout into drawable layers once. Mirrors how
	# CompanionView loads its saved self — appearance is the player's portable, persisted self.
	_catalog = CosmeticsCatalog.load_catalog(cosmetics_path)
	var saved: Dictionary = SaveStore.load_json(APPEARANCE_SAVE_PATH)
	if saved.is_empty():
		_appearance = PlayerAppearance.make_default(_catalog)
	else:
		_appearance = PlayerAppearance.from_dict(saved, _catalog)
	_refresh_avatar()


## Re-resolve the worn loadout into drawable layers. Cheap; call it once at load and again
## whenever the equipped items or colors change (a future wardrobe screen), not every frame.
func _refresh_avatar() -> void:
	if _appearance == null or _catalog == null:
		_avatar_layers = []
		return
	_avatar_layers = AvatarCompositor.load_layers(_appearance.resolved_layers(_catalog))


## Hand the avatar its shared art direction (palette + light). Called by the world. The
## sprite layers now come from the cosmetics catalog (the wardrobe); style still drives the
## procedural fallback's colors below.
func set_style(style: ArtStyle) -> void:
	_style = style


## Persist the player's look. Cheap and idempotent; there's no runtime way to change the
## loadout yet (the wardrobe UI is a later rung), so this currently just keeps the save in
## step — but the round-trip is wired so equips persist the moment that UI lands.
func _save_appearance() -> void:
	if _appearance != null:
		SaveStore.save_json(APPEARANCE_SAVE_PATH, _appearance.to_dict())


## Save on the ways a session can end: window close, app backgrounded on mobile, or this
## node leaving the tree — the same moments CompanionView persists its self.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_save_appearance()


func _process(delta: float) -> void:
	_time += delta
	var dir := _input_direction()
	var desired := dir * speed
	# Exponential smoothing -> snappy but not robotic. (1 - e^(-k*dt)) is a
	# framerate-independent lerp weight.
	velocity = velocity.lerp(desired, 1.0 - exp(-accel * delta))
	var before := position
	position += velocity * delta
	# Keep out of barriers; reconcile velocity to the real (possibly slid) displacement
	# so facing/walk-cycle reflect what actually happened, not the blocked intent.
	if _collide:
		position = Solids.resolve(position, _body_radius, _solids, _bounds, _margin)
		velocity = (position - before) / maxf(delta, 0.0001)
	# Face where we're heading; hold the last facing when standing still.
	if velocity.length() > 8.0:
		_facing = _facing.lerp(velocity.normalized(), 1.0 - exp(-8.0 * delta))
	queue_redraw()


func _input_direction() -> Vector2:
	var v := Vector2.ZERO
	v.x = Input.get_axis("ui_left", "ui_right")
	v.y = Input.get_axis("ui_up", "ui_down")
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		v.y += 1.0
	if _joystick != null:
		v += _joystick.direction
	return v.limit_length(1.0)


func _draw() -> void:
	var cfg := _style.character("player")
	if AvatarCompositor.has_drawable(_avatar_layers):
		# Composite the worn wardrobe: a base body now, with hats/hair/outfits stacking on
		# top once obtained. A single base layer here is identical to the old single-sheet draw.
		AvatarCompositor.draw(self, _avatar_layers, {
			"facing": _facing,
			"speed": velocity.length(),
			"time": _time,
		})
		return
	VectorActor.draw(self, _style, {
		"facing": _facing,
		"speed": velocity.length(),
		"time": _time,
		"body_color": WorldData.to_color(cfg.get("body", [0.86, 0.52, 0.40])),
		"accent_color": WorldData.to_color(cfg.get("accent", [0.96, 0.81, 0.67])),
		"radius": 10.0,
		"head": true,
		"width": float(cfg.get("width", 1.0)),
	})
