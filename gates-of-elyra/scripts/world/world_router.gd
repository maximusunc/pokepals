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
const BAZAAR_ID := "33333333-3333-3333-3333-333333333333"
const RUIN_ID := "44444444-4444-4444-4444-444444444444"
const MAZE_ID := "55555555-5555-5555-5555-555555555555"

## The hub: the one world with a Gateway (its door to the whole catalog), and that gateway's id — the
## default "Return to the Vale" target for any world that declares no return of its own.
const HUB_ID := VALE_ID
const HUB_GATEWAY_ID := "vale_gateway"

## A player's HOME WORLD isn't in the catalog: its id is this prefix + the owner's user_id, and the
## server builds its spec from what they've discovered (Server.HomeWorld).
const HOME_PREFIX := "home:"

## The world the next (or current) load should enter. Defaults to the Vale for a fresh boot.
var current_world := VALE_ID

## On arrival, set the player down beside the portal with this id (so you step OUT of the
## portal you travelled to, not back into the one you came from). Empty = use the world's
## own player_spawn/companion_spawn (a fresh boot).
var arrival_portal_id := ""

## A line to show when the next world finishes loading ("That home is closed…", "You head home…"),
## consumed by world_controller on arrival. Empty = the world's own greeting.
var arrival_hint := ""

## True from the moment go_to() is called until world_controller consumes it on _ready(),
## so the arriving world knows to fade in from black rather than pop into view.
var pending_transition := false


## Where a Gateway trip set out from: { "world": world_id, "portal": gateway_id }, or {} if the last trip
## wasn't through a gateway. The next trip BACK to that world arrives at the gateway (whichever portal
## or Return item took you there), so "home" means where you actually left from — no destination world
## has to know the hub's layout. Consumed by that return trip; any other trip leaves it standing.
var gateway_departure: Dictionary = {}


## Travel to another world: remember the destination (its world_id) + which portal to arrive at,
## then reload the shared world scene. world_controller._ready() does the rest.
func go_to(world_id: String, portal_id: String) -> void:
	current_world = world_id
	arrival_portal_id = resolve_arrival(world_id, portal_id)
	pending_transition = true
	get_tree().change_scene_to_file("res://scenes/world.tscn")


## Where a trip to `world_id` should really arrive: back at the gateway we set out from, if this is the
## trip home after a Gateway journey (consuming that memory), else the `portal_id` the caller asked for.
func resolve_arrival(world_id: String, portal_id: String) -> String:
	if not gateway_departure.is_empty() and world_id == String(gateway_departure["world"]):
		var gateway_id := String(gateway_departure["portal"])
		gateway_departure = {}
		return gateway_id
	return portal_id


## The home world id for a player (our own, from Net.local_id(); a friend's, later).
static func home_id(owner_id: String) -> String:
	return HOME_PREFIX + owner_id


## Consume the one-shot transition flag (returns whether this load arrived via a portal).
func take_pending_transition() -> bool:
	var was := pending_transition
	pending_transition = false
	return was


## Travel through a Gateway: set out from `gateway_id` in the current world to `world_id`, arriving at
## that world's own spawn (a catalog world needn't have a portal pointing back at us). Remembered so
## the way home sets you back down at the gateway.
func go_via_gateway(world_id: String, gateway_id: String) -> void:
	gateway_departure = { "world": current_world, "portal": gateway_id }
	go_to(world_id, "")
