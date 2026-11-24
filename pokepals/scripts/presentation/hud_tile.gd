class_name HudTile
extends Control
## One tappable HUD piece: a cream tile, a round button or a quiet row, holding a line icon (HudIcons),
## an animal sprite (a frame of a pal sheet), a label, or a mix. Every new HUD surface (the menu sheet,
## the companion column, the shapes row, the bag button) is built from these, so they all press, dim
## and highlight alike.
##
## It draws itself and hears taps through gui_input (a mouse-left press, which a touch also arrives as),
## like the hotbar, so it never needs a Button's theme. Pure presentation: it emits `pressed`.

signal pressed

## "tile": a cream tile with an ink rim. "primary": the same, warm gold-cream with a dark rim (the
## everyday things). "round": a cream disc. "ghost": nothing behind it until pressed (a row inside a
## panel). "dark": an ink tile with cream marks. "danger": a cream tile with a rust rim and rust marks.
@export var look := "tile"
@export var icon := ""
@export var text := ""
@export var font_size := 11
@export var icon_size := 18.0
@export var radius := 10.0
## Highlighted (the current shape, an item's selected slot): a gold ring.
var selected := false:
	set(value):
		if value != selected:
			selected = value
			queue_redraw()
## A softer glow ring than `selected`, for something newly on offer (a world's own trick).
var glow := false:
	set(value):
		if value != glow:
			glow = value
			queue_redraw()
## An animal to draw instead of (or beside) the icon: a sheet texture and the frame to show.
var sprite: Texture2D
var sprite_region := Rect2()
var sprite_scale := 1.0

var _down := false
var _fill := Color(0, 0, 0, 0)  # what the icon sits on (the moon cuts its crescent in it)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_sprite(tex: Texture2D, region: Rect2, scale_px: float) -> void:
	if tex == sprite and region == sprite_region and is_equal_approx(scale_px, sprite_scale):
		return
	sprite = tex
	sprite_region = region
	sprite_scale = scale_px
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			queue_redraw()
			accept_event()
		elif _down:
			_down = false
			queue_redraw()
			accept_event()
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				pressed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _down:
		_down = false
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var ink := UiStyle.INK_SOFT
	_fill = UiStyle.HUD_BG
	var round := look == "round"
	var rad := minf(size.x, size.y) * 0.5 if round else radius
	if selected:
		_box(r.grow(3.0), Color(UiStyle.GOLD, 0.35), Color(0, 0, 0, 0), 0, rad + 3.0)
	elif glow:
		_box(r.grow(3.0), Color(UiStyle.GEM_GOLD, 0.3), Color(0, 0, 0, 0), 0, rad + 3.0)
	match look:
		"tile", "round":
			var bg := Color("fff3dc") if selected else UiStyle.HUD_BG
			_box(r, bg.darkened(0.08) if _down else bg, UiStyle.GOLD if selected else UiStyle.HUD_BORDER, 2, rad, 4)
		"primary":
			var bg := Color("ffe7be")
			_box(r, bg.darkened(0.08) if _down else bg, UiStyle.INK, 2, rad, 4)
		"quiet":
			_box(r, UiStyle.PILL_BG.darkened(0.06) if _down else UiStyle.PILL_BG, UiStyle.PILL_BORDER, 2, rad)
		"dark":
			_box(r, UiStyle.INK.lightened(0.12) if _down else UiStyle.INK, Color(0, 0, 0, 0), 0, rad)
			ink = UiStyle.PAPER
		"danger":
			_box(r, UiStyle.PILL_BG.darkened(0.06) if _down else UiStyle.PILL_BG, UiStyle.ACCENT_RUST, 2, rad)
			ink = UiStyle.ACCENT_RUST
		"gold":
			_fill = UiStyle.GOLD.darkened(0.08) if _down else UiStyle.GOLD
			_box(r, _fill, UiStyle.INK, 2, rad, 4)
			ink = UiStyle.INK
		"ghost":
			if _down:
				_box(r, Color(UiStyle.INK, 0.08), Color(0, 0, 0, 0), 0, rad)
	if selected and look != "dark":
		ink = UiStyle.INK

	var font := UiFonts.grotesk(700)
	var has_text := text != "" and font != null
	var has_art := sprite != null or icon != ""
	var c := r.get_center()
	if has_text and has_art and size.y >= size.x * 0.7:
		# Stacked: the picture above, its name below (the menu's tiles).
		var art_c := Vector2(c.x, c.y - font_size * 0.6)
		_draw_art(art_c, ink)
		_text(font, Vector2(0, art_c.y + icon_size * 0.5 + font_size + 2.0), size.x, HORIZONTAL_ALIGNMENT_CENTER, ink)
	elif has_text and has_art:
		# In a row: the picture on the left, the words after it (the menu's wide rows).
		var pad := 10.0
		_draw_art(Vector2(pad + icon_size * 0.5, c.y), ink)
		_text(font, Vector2(pad * 1.6 + icon_size, c.y + font_size * 0.36), size.x, HORIZONTAL_ALIGNMENT_LEFT, ink)
	elif has_art:
		_draw_art(c, ink)
	elif has_text:
		_text(font, Vector2(0, c.y + font_size * 0.36), size.x, HORIZONTAL_ALIGNMENT_CENTER, ink)


func _draw_art(at: Vector2, ink: Color) -> void:
	if sprite != null:
		var s := sprite_region.size * sprite_scale
		# Pal frames stand their feet near the bottom of the cell: lift a little so the body sits centred.
		draw_texture_rect_region(sprite, Rect2(at - s * 0.5 - Vector2(0, s.y * 0.08), s), sprite_region)
	elif icon != "":
		HudIcons.draw(self, icon, at, icon_size, ink, 2.0, _fill)


func _text(font: Font, baseline: Vector2, width: float, align: HorizontalAlignment, ink: Color) -> void:
	draw_string(font, baseline, text, align, width if align == HORIZONTAL_ALIGNMENT_CENTER else -1, font_size, ink)


func _box(r: Rect2, bg: Color, border: Color, bw: int, rad: float, bottom := -1) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(bw)
	if bottom >= 0 and bw > 0:
		sb.border_width_bottom = bottom
	sb.border_color = border
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	draw_style_box(sb, r)
