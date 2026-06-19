class_name VectorActor
extends RefCounted
## A small, characterful flat-vector avatar drawn procedurally (no sprite sheets), so
## both the player and the companion share one cohesive look and animation language.
## Pure presentation: it's handed the actor's state each frame and draws it — a soft
## contact shadow, two feet that step in counter-phase, a lit body (and optional head)
## that squashes and stretches and leans the way it's heading, optional ears, and eyes
## that hide when the actor turns away and shift toward whatever it's attending to.
##
## All motion is derived from `speed` and `time`, so it animates itself from nothing
## but the movement the rest of the game already produces.
##
## params keys:
##   facing: Vector2  — which way it's pointing (player: velocity; companion: look dir)
##   speed: float     — current speed; gates the walk cycle
##   time: float      — accumulated seconds (drives the cycle)
##   squash: float    — external squash/stretch (companion hop/perk); +stretch, -squash
##   body_color, accent_color: Color
##   radius: float    — base body radius
##   ears: bool       — draw little ears (companion)
##   head: bool       — draw a head blob above the body (player)
##   eye_offset: Vector2 — extra eye shift (companion attention)

const MOVE_GATE := 6.0   # below this speed the actor is "idle" (matches the views' gates)
const CADENCE := 11.0    # walk-cycle steps per second


static func draw(ci: CanvasItem, style: ArtStyle, params: Dictionary) -> void:
	var facing: Vector2 = params.get("facing", Vector2.DOWN)
	var speed: float = params.get("speed", 0.0)
	var t: float = params.get("time", 0.0)
	var ext_squash: float = params.get("squash", 0.0)
	var body_color: Color = params.get("body_color", Color(0.7, 0.7, 0.8))
	var accent: Color = params.get("accent_color", body_color.lightened(0.3))
	var radius: float = params.get("radius", 9.0)
	var ears: bool = params.get("ears", false)
	var head: bool = params.get("head", false)
	var eye_offset: Vector2 = params.get("eye_offset", Vector2.ZERO)
	var width: float = params.get("width", 1.0)  # <1 = slimmer (narrower, same height)

	var fdir := facing
	if fdir.length() < 0.01:
		fdir = Vector2.DOWN
	fdir = fdir.normalized()
	var moving := speed > MOVE_GATE
	var phase := t * CADENCE

	# Which way is it looking? (8-way, but we only need a few facts to draw it.)
	var facing_up := fdir.y < -0.5
	var facing_down := fdir.y > 0.5
	var side_x := 0.0
	if absf(fdir.x) > 0.35:
		side_x = signf(fdir.x)

	# Walk cycle + squash/stretch.
	var bob := 0.0
	var stretch := 0.0
	if moving:
		bob = absf(sin(phase)) * 2.6
		stretch = sin(phase * 2.0) * 0.05
	else:
		bob = sin(t * 2.4) * 0.8  # gentle idle breathing
	var vscale := maxf(0.5, 1.0 + ext_squash + stretch)
	var hscale := 1.0 - (vscale - 1.0) * 0.55
	var lean := Vector2(fdir.x, 0.0) * (1.8 if moving else 0.0)

	# Contact shadow (flattened via the draw transform).
	var sh := style.color("shadow")
	ci.draw_set_transform(Vector2(0.0, 7.0), 0.0, Vector2(width, 0.42))
	ci.draw_circle(Vector2.ZERO, radius * 0.95, Color(sh.r, sh.g, sh.b, style.shadow_alpha()))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Feet, stepping in counter-phase (behind the body).
	var foot_color := body_color.darkened(0.25)
	var lift_l := (maxf(0.0, sin(phase)) * 2.4) if moving else 0.0
	var lift_r := (maxf(0.0, sin(phase + PI)) * 2.4) if moving else 0.0
	ci.draw_circle(Vector2(-radius * 0.45 * width, 5.0 - lift_l) + lean, radius * 0.30, foot_color)
	ci.draw_circle(Vector2(radius * 0.45 * width, 5.0 - lift_r) + lean, radius * 0.30, foot_color)

	# Body (a lit blob), squashed/stretched and leaning the way it moves.
	var body_center := Vector2(0.0, -radius * 0.35 - bob) + lean
	ci.draw_set_transform(body_center, 0.0, Vector2(hscale * width, vscale))
	style.draw_blob(ci, Vector2.ZERO, radius, body_color)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Where the face lives: on a head blob (player) or on the body (companion).
	var face_center := body_center
	var face_radius := radius
	if head:
		face_center = body_center + Vector2(0.0, -radius * 0.85)
		face_radius = radius * 0.62
		ci.draw_set_transform(face_center, 0.0, Vector2(hscale * width, vscale))
		style.draw_blob(ci, Vector2.ZERO, face_radius, accent)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Ears (companion), tucked on top of the body and tilting a little with the lean.
	if ears:
		var ear_color := body_color.darkened(0.06)
		var ey := body_center + Vector2(0.0, -radius * 0.72)
		ci.draw_circle(ey + Vector2(-radius * 0.55 * width, 0.0) + lean * 0.5, radius * 0.30, ear_color)
		ci.draw_circle(ey + Vector2(radius * 0.55 * width, 0.0) + lean * 0.5, radius * 0.30, ear_color)

	# Eyes — hidden when it's turned away (facing up), shifted toward attention/facing.
	if not facing_up:
		var eye_color := Color(0.12, 0.12, 0.16)
		var ex := face_radius * 0.42 * width
		var ey2 := face_center.y - face_radius * 0.04
		var look := eye_offset + Vector2(side_x * face_radius * 0.22 * width, (face_radius * 0.14 if facing_down else 0.0))
		if side_x != 0.0:
			ci.draw_circle(Vector2(side_x * ex * 0.6, ey2) + look, face_radius * 0.18, eye_color)
		else:
			ci.draw_circle(Vector2(-ex, ey2) + look, face_radius * 0.18, eye_color)
			ci.draw_circle(Vector2(ex, ey2) + look, face_radius * 0.18, eye_color)
