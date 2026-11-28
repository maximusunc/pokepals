class_name LinkRedeem
extends RefCounted
## LinkRedeem — bringing your companion onto THIS device with a code, as a small state machine. Pure:
## the clock and the server's answers are handed in, and it says when to ask again and what to tell the
## player. Net does the asking (POST /link/redeem) and the remembering; panels only show `message()`.
##
## The server answers each ask with:
##   202 { status: "pending" }  the other device hasn't answered yet: ask again in POLL_MS
##   200 { status: "linked" }   let in: this device is now that player
##   403 denied / 404 invalid / 429 slow_down: stop, and say so kindly
## A code lives 10 minutes, so after that we stop asking and say it ran out. A blip (no answer, or an
## answer we don't understand) while waiting is forgiven a few times before we give up.

const POLL_MS := 2000
const LIFETIME_MS := 600000
const BLIPS_ALLOWED := 3

## idle: not asking. sending: an ask is out. waiting: between asks. The rest are where it ends.
const IDLE := "idle"
const SENDING := "sending"
const WAITING := "waiting"
const LINKED := "linked"
const DENIED := "denied"
const INVALID := "invalid"
const SLOW_DOWN := "slow_down"
const EXPIRED := "expired"
const FAILED := "failed"
const CANCELLED := "cancelled"

var state := IDLE
var code := ""
var _deadline_ms := 0
var _next_ask_ms := 0
var _blips := 0


## Start asking with `typed_code` (kept as typed: the server reads it its own way). The first ask is
## due at once.
func start(typed_code: String, now_ms: int) -> void:
	code = typed_code
	state = WAITING
	_deadline_ms = now_ms + LIFETIME_MS
	_next_ask_ms = now_ms
	_blips = 0


func cancel() -> void:
	if is_active():
		state = CANCELLED


## Still going (an ask out, or waiting for the next one).
func is_active() -> bool:
	return state == SENDING or state == WAITING


## Call every so often: true when an ask should go out now (and marks it as out). Also notices when
## the code has run out.
func should_ask(now_ms: int) -> bool:
	if state != WAITING:
		return false
	if now_ms >= _deadline_ms:
		state = EXPIRED
		return false
	if now_ms < _next_ask_ms:
		return false
	state = SENDING
	return true


## The server answered an ask: `status` is the HTTP status (0 = no answer at all), `body` the parsed
## JSON (anything else if it wasn't). Returns the new state.
func on_answer(status: int, body: Variant, now_ms: int) -> String:
	if state != SENDING:
		return state   # cancelled (or finished) while the ask was out: its answer means nothing now
	var b: Dictionary = body if body is Dictionary else {}
	if status == 200 and String(b.get("status", "")) == "linked":
		state = LINKED
	elif status == 202:
		_blips = 0
		_wait(now_ms)
	elif status == 403:
		state = DENIED
	elif status == 404:
		state = INVALID
	elif status == 429:
		state = SLOW_DOWN
	else:
		_blips += 1
		if _blips > BLIPS_ALLOWED:
			state = FAILED
		else:
			_wait(now_ms)
	return state


func _wait(now_ms: int) -> void:
	if now_ms >= _deadline_ms:
		state = EXPIRED
		return
	state = WAITING
	_next_ask_ms = now_ms + POLL_MS


## What to tell the player in each state. Plain words: "device" and "code", nothing technical.
static func message(s: String) -> String:
	match s:
		SENDING, WAITING:
			return "Waiting for your other device to let you in…"
		LINKED:
			return "You're in! Bringing your companion here…"
		DENIED:
			return "Your other device said not now. You can ask again with a new code."
		INVALID:
			return "That code didn't work. Check it on your other device and try again."
		SLOW_DOWN:
			return "That's a lot of tries. Have a little rest, then try again."
		EXPIRED:
			return "That code has run out. Ask your other device for a new one."
		FAILED:
			return "Couldn't reach the server just now. Try again in a moment."
	return ""
