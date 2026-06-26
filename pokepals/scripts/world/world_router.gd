extends Node
## Tracks which world to load and where to arrive, and performs the actual scene swap.
## All worlds share the same scenes/world.tscn — only the spec (and the arrival portal)
## differ — so "travelling" is just: remember the target, then reload that one scene.
##
## A world is identified by its platform WORLD_ID (a server-canonical UUID). The spec itself comes
## from the server (fetched + cached by Net); world_controller resolves the id to a spec on _ready().
## Portals carry their target world's id. Kept deliberately small: this is the seam that grows as the
## world catalog does — not world_controller.
##
## No class_name: it's an autoload (singleton) named WorldRouter, matching the SaveStore
## convention so the global name and a class name can't clash.

## The seed worlds' fixed ids (must match the server's world_definitions seeds). Brand-new boots start
## in the Vale.
const VALE_ID := "11111111-1111-1111-1111-111111111111"
const RIVERBANK_ID := "22222222-2222-2222-2222-222222222222"

## The world the next (or current) load should enter. Defaults to the Vale for a fresh boot.
var current_world := VALE_ID

## On arrival, set the player down beside the portal with this id (so you step OUT of the
## portal you travelled to, not back into the one you came from). Empty = use the world's
## own player_spawn/companion_spawn (a fresh boot).
var arrival_portal_id := ""

## True from the moment go_to() is called until world_controller consumes it on _ready(),
## so the arriving world knows to fade in from black rather than pop into view.
var pending_transition := false


## Travel to another world: remember the destination (its world_id) + which portal to arrive at,
## then reload the shared world scene. world_controller._ready() does the rest.
func go_to(world_id: String, portal_id: String) -> void:
	current_world = world_id
	arrival_portal_id = portal_id
	pending_transition = true
	get_tree().change_scene_to_file("res://scenes/world.tscn")


## Consume the one-shot transition flag (returns whether this load arrived via a portal).
func take_pending_transition() -> bool:
	var was := pending_transition
	pending_transition = false
	return was
