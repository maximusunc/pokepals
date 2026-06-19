extends Node
## Tracks which world to load and where to arrive, and performs the actual scene swap.
## Both worlds share the same scenes/world.tscn — only the data (and the arrival portal)
## differ — so "travelling" is just: remember the target, then reload that one scene.
##
## This is the world layer's tiny bit of cross-scene state. It holds no game rules and no
## presentation; world_controller reads it on _ready() to decide which world.json to load
## and where to set the player down. Kept deliberately small: when there are many worlds
## (and, far later, a server), this is the seam that grows — not world_controller.
##
## No class_name: it's an autoload (singleton) named WorldRouter, matching the SaveStore
## convention so the global name and a class name can't clash.

## The world the next (or current) load should read. Defaults to the Vale for a fresh boot.
var current_world := "res://data/world.json"

## On arrival, set the player down beside the portal with this id (so you step OUT of the
## portal you travelled to, not back into the one you came from). Empty = use the world's
## own player_spawn/companion_spawn (a fresh boot).
var arrival_portal_id := ""

## True from the moment go_to() is called until world_controller consumes it on _ready(),
## so the arriving world knows to fade in from black rather than pop into view.
var pending_transition := false


## Travel to another world: remember the destination + which portal to arrive at, then
## reload the shared world scene. world_controller._ready() does the rest.
func go_to(world_path: String, portal_id: String) -> void:
	current_world = world_path
	arrival_portal_id = portal_id
	pending_transition = true
	get_tree().change_scene_to_file("res://scenes/world.tscn")


## Consume the one-shot transition flag (returns whether this load arrived via a portal).
func take_pending_transition() -> bool:
	var was := pending_transition
	pending_transition = false
	return was
