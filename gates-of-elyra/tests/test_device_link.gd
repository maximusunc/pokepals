class_name TestDeviceLink
## Tests for DeviceLink and LinkRedeem (issue 175): the code typed on a new device, where the server's
## HTTP lives, what the ticket answer means, the device's friendly name and last-seen words, and the
## redeem wait. All pure, so they're driven with hand-made answers and a hand-wound clock.

static func run_all() -> int:
	var fails := 0
	print("TestDeviceLink")
	fails += _test_normalize()
	fails += _test_complete_and_format()
	fails += _test_http_base()
	fails += _test_socket_url()
	fails += _test_ticket_outcome()
	fails += _test_friendly_name()
	fails += _test_seen_text()
	fails += _test_countdown()
	fails += _test_redeem_polls_until_linked()
	fails += _test_redeem_endings()
	fails += _test_redeem_runs_out()
	fails += _test_redeem_forgives_a_blip()
	fails += _test_redeem_cancel_ignores_late_answer()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _test_normalize() -> int:
	var fails := 0
	fails += _ok(DeviceLink.normalize("abcd-efgh") == "ABCDEFGH", "a code is read in any case, the dash ignored")
	fails += _ok(DeviceLink.normalize(" ab cd\tef-gh ") == "ABCDEFGH", "spaces and tabs are ignored too")
	fails += _ok(DeviceLink.normalize("ab!cd") == "ABCD", "stray punctuation is dropped")
	return fails


static func _test_complete_and_format() -> int:
	var fails := 0
	fails += _ok(DeviceLink.is_complete("abcd efgh"), "8 letters, however typed, make a whole code")
	fails += _ok(not DeviceLink.is_complete("ABCD-EFG"), "7 don't")
	fails += _ok(not DeviceLink.is_complete("ABCD-EFGHJ"), "9 don't")
	fails += _ok(DeviceLink.format("abcdefgh") == "ABCD-EFGH", "a code is shown as ABCD-EFGH")
	fails += _ok(DeviceLink.format("ABCD-EFGH") == "ABCD-EFGH", "formatting a formatted code changes nothing")
	fails += _ok(DeviceLink.format("abc") == "ABC", "a partial code is shown as typed, upper case")
	return fails


static func _test_http_base() -> int:
	var fails := 0
	fails += _ok(DeviceLink.http_base("ws://127.0.0.1:4000/ws") == "http://127.0.0.1:4000", "ws with a port")
	fails += _ok(DeviceLink.http_base("wss://game.example.ts.net/ws") == "https://game.example.ts.net", "wss is https")
	fails += _ok(DeviceLink.http_base("wss://h/ws/") == "https://h", "a trailing slash")
	fails += _ok(DeviceLink.http_base("ws://h:4000/ws/websocket?vsn=2.0.0") == "http://h:4000", "the full socket address")
	fails += _ok(DeviceLink.http_base("wss://h/game/ws") == "https://h/game", "a path before the mount is kept")
	fails += _ok(DeviceLink.http_base("ws://h:4000") == "http://h:4000", "no mount at all")
	fails += _ok(DeviceLink.http_base("http://h/ws") == "", "not a socket address")
	return fails


static func _test_socket_url() -> int:
	var fails := 0
	var net := preload("res://scripts/net/net.gd")
	fails += _ok(net._socket_url("ws://h:4000/ws", "t+k/1") == "ws://h:4000/ws/websocket?vsn=2.0.0&ticket=t%2Bk%2F1",
		"the socket opens with the ticket, encoded, and no token")
	fails += _ok(net._held_from_close(1000, "superseded") == "superseded", "a close whose reason says superseded")
	fails += _ok(net._held_from_close(4002, "") == "signed_out", "or whose code says signed out")
	fails += _ok(net._held_from_close(1000, "") == "", "a plain close is just a drop")
	fails += _ok(net._socket_url("wss://h/ws/", "abc") == "wss://h/ws/websocket?vsn=2.0.0&ticket=abc", "a trailing slash")
	return fails


static func _test_ticket_outcome() -> int:
	var fails := 0
	var t := DeviceLink.ticket_outcome(200, { "ticket": "abc", "expires_in": 60 })
	fails += _ok(t["kind"] == "ticket" and t["ticket"] == "abc", "200 with a ticket: connect with it")
	fails += _ok(DeviceLink.ticket_outcome(200, {})["kind"] == "failed", "200 without one is a failure")
	fails += _ok(DeviceLink.ticket_outcome(401, { "error": "revoked" })["kind"] == "revoked", "401 revoked: signed out")
	fails += _ok(DeviceLink.ticket_outcome(401, null)["kind"] == "failed", "any other 401 is the usual failure")
	fails += _ok(DeviceLink.ticket_outcome(0, null)["kind"] == "failed", "no answer is a failure")
	fails += _ok(DeviceLink.ticket_outcome(500, "oops")["kind"] == "failed", "a server error is a failure")
	return fails


static func _test_friendly_name() -> int:
	var fails := 0
	var android_chrome := "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"
	var iphone_safari := "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
	var win_edge := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36 Edg/124.0"
	var mac_firefox := "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.4; rv:125.0) Gecko/20100101 Firefox/125.0"
	fails += _ok(DeviceLink.friendly_name("Web", "", android_chrome) == "Chrome on Android", "Chrome on Android")
	fails += _ok(DeviceLink.friendly_name("Web", "", iphone_safari) == "Safari on iPhone", "Safari on iPhone")
	fails += _ok(DeviceLink.friendly_name("Web", "", win_edge) == "Edge on Windows", "Edge is not taken for Chrome")
	fails += _ok(DeviceLink.friendly_name("Web", "", mac_firefox) == "Firefox on Mac", "Firefox on Mac")
	fails += _ok(DeviceLink.friendly_name("Web", "", "") == "Web browser", "a browser that says nothing")
	fails += _ok(DeviceLink.friendly_name("iOS", "iPhone14,2") == "iPhone", "an iPhone")
	fails += _ok(DeviceLink.friendly_name("iOS", "iPad13,1") == "iPad", "an iPad")
	fails += _ok(DeviceLink.friendly_name("Windows", "GenericDevice") == "Windows PC", "a Windows PC")
	fails += _ok(DeviceLink.friendly_name("Android", "Pixel 8") == "Android phone", "no model names leak out")
	fails += _ok(DeviceLink.friendly_name("Haiku", "") == "Device", "something unknown")
	return fails


static func _test_seen_text() -> int:
	var fails := 0
	var now := 1_800_000_000_000
	fails += _ok(DeviceLink.seen_text(null, now) == "Not seen yet", "never seen")
	fails += _ok(DeviceLink.seen_text(now - 30_000, now) == "Here now", "seconds ago is here now")
	fails += _ok(DeviceLink.seen_text(now - 5 * 60_000, now) == "Seen 5 minutes ago", "minutes")
	fails += _ok(DeviceLink.seen_text(float(now - 60 * 60_000), now) == "Seen an hour ago", "an hour (a float from JSON)")
	fails += _ok(DeviceLink.seen_text(now - 3 * 3_600_000, now) == "Seen 3 hours ago", "hours")
	fails += _ok(DeviceLink.seen_text(now - 30 * 3_600_000, now) == "Seen yesterday", "yesterday")
	fails += _ok(DeviceLink.seen_text(now - 4 * 86_400_000, now) == "Seen 4 days ago", "days")
	fails += _ok(DeviceLink.seen_text(now - 90 * 86_400_000, now) == "Seen a while ago", "a while ago")
	fails += _ok(DeviceLink.seen_text(now + 60_000, now) == "Here now", "a clock a little ahead never goes negative")
	return fails


static func _test_countdown() -> int:
	var fails := 0
	fails += _ok(DeviceLink.countdown_text(600.0) == "10:00", "ten minutes")
	fails += _ok(DeviceLink.countdown_text(65.2) == "1:06", "rounds up to the second")
	fails += _ok(DeviceLink.countdown_text(-3.0) == "0:00", "never below zero")
	return fails


static func _test_redeem_polls_until_linked() -> int:
	var fails := 0
	var r := LinkRedeem.new()
	r.start("abcd-efgh", 1000)
	fails += _ok(r.code == "abcd-efgh", "the code is kept as typed")
	fails += _ok(r.should_ask(1000), "the first ask goes at once")
	fails += _ok(not r.should_ask(1000), "and only once while it's out")
	fails += _ok(r.on_answer(202, { "status": "pending" }, 1200) == LinkRedeem.WAITING, "pending: wait")
	fails += _ok(not r.should_ask(2000), "not again before two seconds")
	fails += _ok(r.should_ask(3200), "again after two seconds")
	fails += _ok(r.on_answer(200, { "status": "linked" }, 3300) == LinkRedeem.LINKED, "linked")
	fails += _ok(not r.is_active() and not r.should_ask(9000), "and then it stops")
	return fails


static func _test_redeem_endings() -> int:
	var fails := 0
	var cases := { 403: LinkRedeem.DENIED, 404: LinkRedeem.INVALID, 429: LinkRedeem.SLOW_DOWN }
	for status in cases:
		var r := LinkRedeem.new()
		r.start("ABCDEFGH", 0)
		r.should_ask(0)
		fails += _ok(r.on_answer(status, {}, 10) == cases[status] and not r.is_active(), "%d stops: %s" % [status, cases[status]])
		fails += _ok(LinkRedeem.message(cases[status]) != "", "and says something kind")
	return fails


static func _test_redeem_runs_out() -> int:
	var fails := 0
	var r := LinkRedeem.new()
	r.start("ABCDEFGH", 0)
	r.should_ask(0)
	r.on_answer(202, {}, 100)
	fails += _ok(not r.should_ask(LinkRedeem.LIFETIME_MS) and r.state == LinkRedeem.EXPIRED, "after ten minutes it gives up")
	return fails


static func _test_redeem_forgives_a_blip() -> int:
	var fails := 0
	var r := LinkRedeem.new()
	r.start("ABCDEFGH", 0)
	r.should_ask(0)
	fails += _ok(r.on_answer(0, null, 100) == LinkRedeem.WAITING, "one lost answer is forgiven")
	var t := 100
	for i in LinkRedeem.BLIPS_ALLOWED:
		t += LinkRedeem.POLL_MS
		r.should_ask(t)
		r.on_answer(502, null, t)
	fails += _ok(r.state == LinkRedeem.FAILED, "but not forever")
	return fails


static func _test_redeem_cancel_ignores_late_answer() -> int:
	var fails := 0
	var r := LinkRedeem.new()
	r.start("ABCDEFGH", 0)
	r.should_ask(0)
	r.cancel()
	fails += _ok(r.state == LinkRedeem.CANCELLED, "Cancel stops it")
	fails += _ok(r.on_answer(200, { "status": "linked" }, 50) == LinkRedeem.CANCELLED, "an answer arriving after Cancel means nothing")
	return fails
