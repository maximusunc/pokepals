class_name SoundPanel
extends CozySheet
## The SOUND sheet (gear menu): one slider for the background music's volume. The music follows the
## slider while you drag, so you set it by ear; the choice is saved on this device when you let go
## (the Music autoload keeps it, see music_player.gd).
##
## HSlider is Godot's built-in horizontal slider Control: it holds a value between min_value and
## max_value and emits value_changed as it moves, and drag_ended when the finger or mouse lets go.

var _amount: Label


func _build() -> void:
	width = 260.0
	eyebrow("Sound")
	heading("Music")
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Music.volume
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 22)
	_style(slider)
	r.add_child(slider)
	_amount = UiStyle.label("", 10, UiStyle.INK_STRONG, 700)
	_amount.custom_minimum_size = Vector2(34, 0)
	_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(_amount)
	body.add_child(r)
	_show(slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		Music.set_volume(v, false)
		_show(v))
	slider.drag_ended.connect(func(_changed: bool) -> void: Music.set_volume(slider.value))
	note("The middle is the quiet background level each world is made for.")
	var done := CozySheet.pill("Close", close, false, 10)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(done)
	# A tap on the track (not a drag) still saves: drag_ended doesn't fire for it, so save on close too.
	closed.connect(func() -> void: Music.set_volume(slider.value))


func _show(v: float) -> void:
	_amount.text = "Off" if v <= 0.0 else "%d%%" % roundi(v * 100.0)


## The slider in the cream-card palette: a soft tan track, gold where it's filled, an ink grabber.
static func _style(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = UiStyle.TOGGLE_TRACK
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = UiStyle.GOLD
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	for y in 14:
		for x in 14:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(7, 7))
			knob.set_pixel(x, y, UiStyle.INK if d <= 6.0 else (UiStyle.PILL_BG if d <= 7.0 else Color(0, 0, 0, 0)))
	var tex := ImageTexture.create_from_image(knob)
	s.add_theme_icon_override("grabber", tex)
	s.add_theme_icon_override("grabber_highlight", tex)
