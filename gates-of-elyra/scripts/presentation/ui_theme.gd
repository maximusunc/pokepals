extends Node
## Autoload that gives the whole game its typographic voice: sets Space Grotesk as the
## default font on the root window's theme, so every Label/Button — HUD, lobby, shop,
## battle, wardrobe — picks it up without touching each screen. Individual screens keep
## their per-label size/weight overrides (and reach for UiFonts.pixel() where they want
## the Silkscreen caps face).
##
## Done in code rather than a .tres theme so it degrades gracefully: if the font file
## isn't there (or isn't imported yet), we simply leave the engine default in place.


func _ready() -> void:
	var body := UiFonts.grotesk(500)
	if body == null:
		return
	var theme := get_window().theme
	if theme == null:
		theme = Theme.new()
	theme.default_font = body
	# The wardrobe screen's compact type scale, as the baseline for anything unstyled.
	theme.default_font_size = 12
	get_window().theme = theme
