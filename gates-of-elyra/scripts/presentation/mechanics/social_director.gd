class_name SocialDirector
extends Node
## Friends and visiting, in the world (FR-0..FR-5; docs/home-world-and-secrets-design.md). Owns the
## small social windows and what the server tells us about other people:
##
##   * tapping another player opens their card: Befriend (or Accept, if they asked), Invite home (a
##     one-off visit for someone who isn't a friend), Send home (if they're visiting your home), Block;
##   * a friend request arriving is a soft line, not a popup; you answer it in Friends;
##   * an invite home IS a question (Go / Not now), since it's about right now. If you go, you travel
##     to their home, and they're brought home to meet you;
##   * being sent out of a home (or finding it closed) walks you gently back to the Vale's Gateway.
##
## Presentation only: every decision (who may visit, what a request does) is the server's. Reports back
## to the host (the World) through its small seam: show_hint, open_sheet, travel_to.

var _host: Node
var _presence: PresenceDirector
var _card: ChoiceCard


func setup(host: Node, presence: PresenceDirector) -> void:
	_host = host
	_presence = presence
	Net.friend_request_received.connect(_on_friend_request)
	Net.home_invite_received.connect(_on_home_invite)
	Net.invite_answered.connect(_on_invite_answered)
	Net.invite_result.connect(_on_invite_result)
	Net.sent_home.connect(_on_sent_home)
	Net.world_join_failed.connect(_on_join_failed)


## The player tapped another player: open their card.
func tap_player(peer_id: String) -> void:
	var relation := Net.relation(peer_id)
	var choices: Array = []
	match relation:
		"friend": choices.append({ "id": "", "label": "Friends", "disabled": true })
		"incoming": choices.append({ "id": "accept", "label": "Accept friend request", "gold": true })
		"requested": choices.append({ "id": "", "label": "Friend request sent", "disabled": true })
		"none": choices.append({ "id": "befriend", "label": "Befriend", "gold": true })
	if relation != "friend" and relation != "blocked":
		choices.append({ "id": "invite", "label": "Invite home" })
	if _host.is_in_own_home():
		choices.append({ "id": "send_home", "label": "Send home" })
	if relation != "blocked":
		choices.append({ "id": "block", "label": "Block" })
	var card := ChoiceCard.new()
	card.title = _presence.peer_name(peer_id)
	card.text = SocialDirector.relation_text(relation)
	card.choices = choices
	card.chosen.connect(_on_player_choice.bind(peer_id))
	_host.open_sheet(card)


## The words under a player's name on their card.
static func relation_text(relation: String) -> String:
	match relation:
		"friend": return "Your friend. They can visit your home any time."
		"incoming": return "They'd like to be friends."
		"requested": return "You've asked to be friends."
		"blocked": return "You've blocked them."
		_: return "Someone you've met here."


func open_friends() -> void:
	_host.open_sheet(FriendsPanel.new())


## Open a journal: our own ("" owner) or a home owner's.
func open_journal(owner_id := "") -> void:
	var panel := JournalPanel.new()
	panel.owner_id = owner_id
	panel.travel_requested.connect(func(world_id: String, world_name: String) -> void:
		_host.travel_to(world_id, "", "You set off for %s…" % world_name))
	_host.open_sheet(panel)


func _on_player_choice(id: String, peer_id: String) -> void:
	var who := _presence.peer_name(peer_id)
	match id:
		"befriend":
			Net.request_friend(peer_id)
			_host.show_hint("You ask %s to be friends." % who)
		"accept":
			Net.accept_friend(peer_id)
			_host.show_hint("You and %s are friends now." % who)
		"invite":
			Net.invite_home(peer_id)
			_host.show_hint("You invite %s home." % who)
		"send_home":
			Net.send_visitor_home(peer_id)
			_host.show_hint("You gently see %s off to the Gateway." % who)
		"block":
			Net.block_player(peer_id)
			_host.show_hint("You won't hear from %s again." % who)


func _on_friend_request(_from_id: String, from_name: String) -> void:
	_host.show_hint("%s would like to be friends. (Friends, in the menu.)" % from_name)


## An invite is about right now, so it's a question. Only one at a time.
func _on_home_invite(from_id: String, from_name: String) -> void:
	if is_instance_valid(_card):
		Net.answer_invite(from_id, false)
		return
	_card = ChoiceCard.new()
	_card.modal = true
	_card.title = "%s invites you home" % from_name
	_card.text = "Just for this visit. You'll travel there now."
	_card.choices = [{ "id": "go", "label": "Go", "gold": true }, { "id": "no", "label": "Not now" }]
	_card.chosen.connect(func(id: String) -> void: Net.answer_invite(from_id, id == "go"))
	_host.open_sheet(_card)


## They answered our invite. If they're coming, go home to meet them.
func _on_invite_answered(_guest_id: String, guest_name: String, accepted: bool) -> void:
	if not accepted:
		_host.show_hint("%s can't come right now." % guest_name)
		return
	if _host.is_in_own_home():
		_host.show_hint("%s is on their way." % guest_name)
	else:
		_host.travel_to(WorldRouter.home_id(Net.local_id()), "", "You head home to meet %s." % guest_name)


func _on_invite_result(r: Dictionary) -> void:
	if not bool(r.get("ok", false)):
		_host.show_hint("That invitation has lapsed.")
	elif bool(r.get("accepted", false)):
		_host.travel_to(WorldRouter.home_id(String(r.get("owner", ""))), "", "You set off to visit…")


func _on_sent_home() -> void:
	_host.travel_to(WorldRouter.HUB_ID, WorldRouter.HUB_GATEWAY_ID, "You find yourself back at the great gate.")


## A home that wouldn't have us (closed, or we're no longer welcome): back to the Gateway, gently.
func _on_join_failed(reason: String) -> void:
	if WorldRouter.current_world.begins_with(WorldRouter.HOME_PREFIX) and reason == "not_allowed":
		_host.travel_to(WorldRouter.HUB_ID, WorldRouter.HUB_GATEWAY_ID, "That home is closed to visitors right now.")
