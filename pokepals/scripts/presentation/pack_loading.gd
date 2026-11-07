class_name PackLoading
extends Control
## The short loading moment between worlds, while a world's art pack downloads (see AssetPacks).
## The same dark backdrop, wordmark and little trotting fox as the connection gate (Lobby), so it reads
## as the same quiet place; under the fox, "Gathering <world>…" and a thin gold progress line.
##
## It stays out of sight for a beat (a small pack arrives before you'd notice, and a flash of a screen
## is worse than none), and once it HAS appeared it stays long enough to read. Pure presentation:
## whoever owns it calls begin() / set_progress() / finish().

const BG := Color("1b1510")         # the loading screens' backdrop (Lobby.BG, tools/gen_loading.py)
const APPEAR_AFTER := 0.30          # seconds of waiting before the screen fades in
const FADE := 0.20
const MIN_VISIBLE := 0.60           # once shown, at least this long
# The connection gate's layout (Lobby), mirrored here so the two screens line up exactly.
const WORDMARK_SIZE := 16
const BOX_TOP := 99.0 - 180.0
const GAP := 12.0
const BAR_W := 140.0
const BAR_H := 3.0

var _fox: TrottingFox
var _label: Label
var _bar_back: ColorRect
var _bar_fill: ColorRect
var _shown_at := -1.0
var _t := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # it runs while the connection gate has the tree paused
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0

	var back := ColorRect.new()
	back.color = BG
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_top = BOX_TOP
	box.offset_bottom = BOX_TOP + 156.0
	box.add_theme_constant_override("separation", int(GAP))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var title := Label.new()
	title.text = "KITHBOUND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var wordmark := UiFonts.pixel(false, 1)
	if wordmark != null:
		title.add_theme_font_override("font", wordmark)
	title.add_theme_font_size_override("font_size", WORDMARK_SIZE)
	title.add_theme_color_override("font_color", Color(0.97, 0.97, 0.93))
	box.add_child(title)

	_fox = TrottingFox.new(2)
	_fox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_fox)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.set_font(_label, 500, 10)
	_label.add_theme_color_override("font_color", UiStyle.PAPER)
	box.add_child(_label)

	var bar_row := CenterContainer.new()
	box.add_child(bar_row)
	_bar_back = ColorRect.new()
	_bar_back.custom_minimum_size = Vector2(BAR_W, BAR_H)
	_bar_back.color = Color(1, 1, 1, 0.12)
	bar_row.add_child(_bar_back)
	_bar_fill = ColorRect.new()
	_bar_fill.color = UiStyle.GOLD
	_bar_fill.size = Vector2(0.0, BAR_H)
	_bar_back.add_child(_bar_fill)


## Start waiting for `world_name`'s art. The screen appears after APPEAR_AFTER if it's still going.
func begin(world_name: String) -> void:
	_label.text = ("Gathering %s…" % world_name) if world_name != "" else "Gathering the scenery…"
	set_progress(0, 1)
	_t = 0.0
	_shown_at = -1.0
	set_process(true)


func set_progress(done: int, total: int) -> void:
	_bar_fill.size.x = BAR_W * clampf(float(done) / float(maxi(total, 1)), 0.0, 1.0)


## Say it didn't work, briefly (we go in with the plainer fallback look).
func show_failure() -> void:
	_label.text = "The scenery is slow to arrive. Going in anyway…"
	_fox.trotting = false
	_show()


## Done. If the screen ever appeared, hold it for MIN_VISIBLE, then fade it out and free it. Awaitable.
func finish() -> void:
	set_process(false)
	if _shown_at >= 0.0:
		var left := MIN_VISIBLE - (Time.get_ticks_msec() / 1000.0 - _shown_at)
		if left > 0.0:
			await get_tree().create_timer(left).timeout
	queue_free()


func _process(delta: float) -> void:
	_t += delta
	if _shown_at < 0.0 and _t >= APPEAR_AFTER:
		_show()


func _show() -> void:
	if _shown_at >= 0.0:
		return
	_shown_at = Time.get_ticks_msec() / 1000.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE)
