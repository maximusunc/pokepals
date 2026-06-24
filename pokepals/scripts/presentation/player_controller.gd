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
# How fast a REMOTE puppet eases toward its latest received transform. Remote state lands ~20 Hz;
# we render at 60 fps by lerping toward the newest sample, so a friend's avatar glides, not steps.
const REMOTE_LERP_RATE := 14.0

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
# Networked PUPPET mode. A locally-controlled avatar (_is_local, the default) reads input and
# collides. A REMOTE puppet (set via set_remote() before it enters the tree) runs NEITHER: it's
# driven purely by transforms arriving over Net and smoothed toward here, never reads input, and
# never touches the local save — its look comes from the friend's identity packet (apply_identity).
var _is_local := true
var _target_pos := Vector2.ZERO       # latest position received from the owner (remote only)
var _target_facing := Vector2.DOWN    # latest facing received from the owner (remote only)


## Mark this avatar a REMOTE puppet. MUST be called after instantiate() and before add_child(),
## so the flag is set before _ready runs (no input wiring, no local save load).
func set_remote() -> void:
	_is_local = false


func is_local() -> bool:
	return _is_local


## The local avatar's current facing, for the world to fold into its broadcast packet.
func facing() -> Vector2:
	return _facing


## A plain, JSON-ready snapshot of the worn look, for the world's identity packet. The mirror
## of apply_identity below — what one client sends, the other rebuilds.
func appearance_dict() -> Dictionary:
	if _appearance == null:
		return {}
	return _appearance.to_dict()


## Render this puppet as the friend's actual avatar. The incoming dict is UNTRUSTED: from_dict
## rebuilds from defaults and validates every owned/equipped id against the local catalog,
## silently dropping anything unknown — so a malformed or hostile packet can never break the
## avatar. Remote only; the local avatar owns its look from its own save.
func apply_identity(appearance: Dictionary) -> void:
	if _catalog == null:
		_catalog = CosmeticsCatalog.load_catalog(cosmetics_path)
	_appearance = PlayerAppearance.from_dict(appearance, _catalog)
	_refresh_avatar()


## Feed a remote puppet the owner's latest transform. We only STORE it here; _process eases the
## body toward it so motion stays smooth between the ~20 Hz samples. Pure presentation: this never
## moves a local avatar (the world only calls it on puppets).
func set_remote_state(pos: Vector2, face: Vector2) -> void:
	_target_pos = pos
	if face.length() > 0.01:
		_target_facing = face.normalized()


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
	# The worn look lives on the SERVER now (online-only). Start on the default; the local
	# avatar adopts the server's wardrobe via apply_appearance once it loads, and a remote
	# puppet is overwritten by the friend's identity packet — so neither reads a local save.
	_appearance = PlayerAppearance.make_default(_catalog)
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


## Adopt the server's canonical wardrobe on the LOCAL avatar (on connect / world hop). The
## mirror of apply_identity, which does the same for a remote puppet: rebuild from the
## (untrusted) dict against the catalog and re-composite the worn layers.
func apply_appearance(appearance: Dictionary) -> void:
	if appearance.is_empty():
		return
	if _catalog == null:
		_catalog = CosmeticsCatalog.load_catalog(cosmetics_path)
	_appearance = PlayerAppearance.from_dict(appearance, _catalog)
	_refresh_avatar()


func _process(delta: float) -> void:
	_time += delta
	if not _is_local:
		_process_remote(delta)
		return
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


## A REMOTE puppet: no input, no collision (its owner is authoritative over it). We just glide
## toward the latest received position, deriving velocity from that movement so the same
## walk-cycle/facing code lights up — and fall back to the owner's last reported facing when it's
## standing still. This is what turns ~20 Hz samples into smooth, alive motion on our screen.
func _process_remote(delta: float) -> void:
	var before := position
	position = position.lerp(_target_pos, 1.0 - exp(-REMOTE_LERP_RATE * delta))
	velocity = (position - before) / maxf(delta, 0.0001)
	var aim := velocity.normalized() if velocity.length() > 8.0 else _target_facing
	_facing = _facing.lerp(aim, 1.0 - exp(-8.0 * delta))
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
