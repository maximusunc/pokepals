class_name UiStyle
extends RefCounted
## The game's shared UI voice — the wardrobe screen's design language, lifted out as tokens
## plus tiny factories so every surface (HUD chips, menus, dialogs, the wardrobe itself)
## reads as one hand: warm cream panels, hard ink lines, chunky bottom-drop buttons, gold
## for the one primary action, Space Grotesk text with Silkscreen for tiny pixel caps.
##
## Pure presentation helpers: no state, no scene assumptions. Screens call the factories
## and keep their own layout.

# ---- palette (from the wardrobe reference) ----
const INK := Color("2f2417")          # hard outlines, dark fills, primary text on gold
const INK_STRONG := Color("33281b")   # headings on cream
const INK_SOFT := Color("3a2c1c")     # text on the on-world (HUD) cream buttons
const MUTED := Color("9a8b76")        # secondary text on cream
const MUTED_2 := Color("b7a98f")      # captions on cream
const LABEL_BROWN := Color("7c6e5b")  # small section labels on cream
const LEGEND_TEXT := Color("8a7c65")  # legend / fine print on cream
const PANEL_TOP := Color("f8f2e5")    # cream panel gradient top
const PANEL_BOTTOM := Color("efe5d2") # cream panel gradient bottom
const PILL_BG := Color("fffdf7")      # idle pill fill
const PILL_BORDER := Color("dccca6")  # idle pill border
const PILL_TEXT := Color("5a4a34")    # idle pill text
const TAB_ON_BG := Color("2f2417")    # active pill / segment fill
const TAB_ON_TEXT := Color("f6efe0")  # active pill / segment text
const TOGGLE_TRACK := Color("e7d9bd")
const TOGGLE_IDLE_TEXT := Color("7a6a52")
const GOLD := Color("dfa53e")         # the primary-action button
const DIVIDER := Color("e2d6bd")
const ACCENT_RUST := Color("b5603a")  # tiny Silkscreen eyebrows (CUSTOMIZE)
const PAPER := Color("f4ecda")        # light text on dark pills
const GEM_GOLD := Color("f2c65a")
const BADGE_GOLD := Color("c2902f")
# On-world (HUD) button chrome: translucent cream over the grass, soft ink border.
const HUD_BG := Color(246.0 / 255.0, 240.0 / 255.0, 228.0 / 255.0, 0.92)
const HUD_BORDER := Color(20.0 / 255.0, 14.0 / 255.0, 8.0 / 255.0, 0.5)
# Dark translucent pills floating over the world (nameplates, badges).
const DARK_PILL_BG := Color(20.0 / 255.0, 15.0 / 255.0, 10.0 / 255.0, 0.72)
const DARK_PILL_BORDER := Color(1.0, 240.0 / 255.0, 215.0 / 255.0, 0.28)


# ---- text ----
static func label(text: String, size: int, color: Color, weight := 400) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var f := UiFonts.grotesk(weight)
	if f != null:
		l.add_theme_font_override("font", f)
	return l


static func pixel_label(text: String, size: int, color: Color, spacing := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var f := UiFonts.pixel(false, spacing)
	if f != null:
		l.add_theme_font_override("font", f)
	return l


## Give any Control the UI face at a weight (and optionally a size) — for nodes that
## already exist (scene labels, buttons) rather than ones built by the factories above.
static func set_font(c: Control, weight: int, size := -1) -> void:
	var f := UiFonts.grotesk(weight)
	if f != null:
		c.add_theme_font_override("font", f)
	if size > 0:
		c.add_theme_font_size_override("font_size", size)


static func set_button_text_color(b: Button, color: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, color)


## Apply styleboxes across a button's states (hover shares normal; pressed may differ).
static func set_button_boxes(b: Button, sb: StyleBox, pressed: StyleBox = null) -> void:
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", pressed if pressed != null else sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


# ---- boxes ----
## The on-world button chrome (the wardrobe's back chevron): translucent cream tile with a
## soft ink border and a chunky hard bottom drop. Also drawable directly for custom icons.
static func hud_box(radius := 10, pressed := false, pad_h := 0.0, pad_v := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var bg := HUD_BG
	if pressed:
		bg = Color(bg.r * 0.92, bg.g * 0.92, bg.b * 0.92, bg.a)
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_width_bottom = 4
	sb.border_color = HUD_BORDER
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb


## A centred cream dialog panel (the dock's cousin): cream fill, ink border, rounded.
static func panel_box(radius := 12, margin := 14.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_TOP
	sb.set_border_width_all(2)
	sb.border_color = INK
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


# ---- buttons ----
## An on-world (HUD) button: cream tile, soft ink border, hard bottom drop, brown text.
static func hud_button(b: Button, font_size := 11, weight := 600, radius := 10, pad_h := 12.0, pad_v := 5.0) -> void:
	b.focus_mode = Control.FOCUS_NONE
	set_font(b, weight, font_size)
	set_button_text_color(b, INK_SOFT)
	set_button_boxes(b, hud_box(radius, false, pad_h, pad_v), hud_box(radius, true, pad_h, pad_v))


## The primary-action button (the wardrobe's Equip look): gold fill inside a hard ink
## frame whose thick bottom edge is the drop shadow.
static func gold_button(b: Button, font_size := 10, radius := 8, pad_h := 12.0, pad_v := 7.0) -> void:
	b.focus_mode = Control.FOCUS_NONE
	set_font(b, 700, font_size)
	set_button_text_color(b, INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD
	sb.set_border_width_all(2)
	sb.border_width_bottom = 5
	sb.border_color = INK
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	var pressed := sb.duplicate() as StyleBoxFlat
	pressed.bg_color = GOLD.darkened(0.08)
	set_button_boxes(b, sb, pressed)
	# A disabled gold button greys toward the panel so it still reads but can't be pressed.
	var off := sb.duplicate() as StyleBoxFlat
	off.bg_color = Color("cbb98d")
	off.border_color = Color("8a7c65")
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_color_override("font_disabled_color", LEGEND_TEXT)


## A cream pill button (the wardrobe's idle category pill) — quiet actions on cream panels.
static func pill_button(b: Button, font_size := 10, weight := 600, radius := 999, pad_h := 12.0, pad_v := 5.0) -> void:
	b.focus_mode = Control.FOCUS_NONE
	set_font(b, weight, font_size)
	set_button_text_color(b, PILL_TEXT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PILL_BG
	sb.set_border_width_all(2)
	sb.border_color = PILL_BORDER
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	var pressed := sb.duplicate() as StyleBoxFlat
	pressed.bg_color = PILL_BG.darkened(0.06)
	set_button_boxes(b, sb, pressed)
