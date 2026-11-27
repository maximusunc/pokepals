class_name DrawProxy
extends Node2D
## A tiny canvas item that draws by calling back into its owner (`draw_fn.call(self)`). Lets a node
## paint one part of itself with a different texture filter: WorldArt keeps linear filtering for its
## soft glows, but its pixel-art litter goes through a NEAREST proxy so it stays crisp when the 640x360
## view is scaled up to the window. Pure presentation.

var draw_fn: Callable


func _draw() -> void:
	if draw_fn.is_valid():
		draw_fn.call(self)
