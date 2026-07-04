class_name PixelPanelStyle
extends StyleBox
## A gritty pixel-art panel used for the HUD buttons, so they read as hand-hewn tiles rather than
## clean flat web rectangles. On top of a flat fill it paints:
##   • a chiselled 2-tone bevel — a light strip along the top + left interior, a dark one along the
##     bottom + right — so the tile looks raised and worn rather than perfectly flat;
##   • a sparse scatter of single-pixel darker/lighter specks for a mottled, grimy texture;
##   • a hard inked outline on all four edges.
##
## The speckle is hashed from pixel position, so it's stable across redraws (never flickers) and
## consistent on same-size panels. Painted with RenderingServer canvas calls, so the same style works
## both as a Button theme stylebox AND when invoked directly via StyleBox.draw() (the gear tile does
## that). No anti-aliasing anywhere — every edge is a hard pixel boundary.

var fill := Color(0.96, 0.94, 0.87)
var outline := Color(0.20, 0.20, 0.22)
var border_w := 3


## Build a panel with content padding, so a Button using it sizes and pads its label correctly.
static func make(fill_c: Color, outline_c: Color, bw: int, cmargin_h := 14.0, cmargin_v := 7.0) -> PixelPanelStyle:
	var s := PixelPanelStyle.new()
	s.fill = fill_c
	s.outline = outline_c
	s.border_w = bw
	s.content_margin_left = cmargin_h
	s.content_margin_right = cmargin_h
	s.content_margin_top = cmargin_v
	s.content_margin_bottom = cmargin_v
	return s


func _draw(ci: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	var b := float(border_w)
	var hi := fill.lightened(0.16)
	var lo := fill.darkened(0.18)
	var p := rect.position
	var s := rect.size

	# Base fill.
	rs.canvas_item_add_rect(ci, rect, fill)

	# Chiselled bevel: light along the top + left interior, dark along the bottom + right.
	rs.canvas_item_add_rect(ci, Rect2(p.x + b, p.y + b, s.x - 2.0 * b, 2.0), hi)
	rs.canvas_item_add_rect(ci, Rect2(p.x + b, p.y + b, 2.0, s.y - 2.0 * b), hi)
	rs.canvas_item_add_rect(ci, Rect2(p.x + b, p.y + s.y - b - 2.0, s.x - 2.0 * b, 2.0), lo)
	rs.canvas_item_add_rect(ci, Rect2(p.x + s.x - b - 2.0, p.y + b, 2.0, s.y - 2.0 * b), lo)

	# Grit: a sparse, deterministic speckle of darker/lighter single pixels across the interior.
	_speckle(ci, rect, lo, hi)

	# Hard inked outline (four edges), drawn last so nothing bleeds over it.
	rs.canvas_item_add_rect(ci, Rect2(p.x, p.y, s.x, b), outline)
	rs.canvas_item_add_rect(ci, Rect2(p.x, p.y + s.y - b, s.x, b), outline)
	rs.canvas_item_add_rect(ci, Rect2(p.x, p.y, b, s.y), outline)
	rs.canvas_item_add_rect(ci, Rect2(p.x + s.x - b, p.y, b, s.y), outline)


## Scatter grime specks over the interior. Deterministic (hashed on pixel position) so the pattern is
## stable frame-to-frame — no crawling noise — and identical across same-size tiles.
func _speckle(ci: RID, rect: Rect2, lo: Color, hi: Color) -> void:
	var rs := RenderingServer
	var inset := border_w + 2
	var x0 := int(rect.position.x) + inset
	var y0 := int(rect.position.y) + inset
	var x1 := int(rect.position.x + rect.size.x) - inset
	var y1 := int(rect.position.y + rect.size.y) - inset
	var y := y0
	while y < y1:
		var x := x0
		while x < x1:
			var h := _hash(x, y)
			if h % 18 == 0:
				rs.canvas_item_add_rect(ci, Rect2(x, y, 1.0, 1.0), lo)
			elif h % 27 == 0:
				rs.canvas_item_add_rect(ci, Rect2(x, y, 1.0, 1.0), hi)
			x += 3
		y += 3


## A cheap deterministic 2D hash — the classic spatial-hash primes, folded to non-negative.
func _hash(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663))
