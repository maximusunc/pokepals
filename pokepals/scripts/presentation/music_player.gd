extends Node
## Background music: one looping track per world, crossfaded as you travel.
##
## A world asks for its music in its spec: `"music": { "track": "res://assets/music/vale.ogg",
## "volume_db": -12 }`. world_controller hands that block over on every build (play_world); a world
## with none fades to quiet. The tracks themselves are rendered from text scores by
## tools/gen_music.py (see tools/music/README.md).
##
## Why an autoload: travelling reloads the world scene, which frees every node in it. An autoload
## (a node Godot keeps at the root for the whole run, reachable by its name, `Music`) lives through
## that, so a track keeps playing across a reload and can crossfade into the next world's instead of
## cutting off. If the next world asks for the same track it simply carries on.
##
## Two AudioStreamPlayers take turns: the incoming one fades up while the outgoing one fades down.
## AudioStreamPlayer is Godot's non-positional sound node (it plays at the same level wherever the
## camera is), which is what background music wants. Streaming an .ogg costs next to nothing per
## frame, even on the web build; nothing here runs in _process.
##
## The player's on/off choice is a device preference, not game state, so it lives in
## user://settings.json beside the identity token, not on the server.
##
## Registered as the "Music" autoload; no class_name, so the global name and a class can't clash.

const SETTINGS_PATH := "user://settings.json"
const FADE_IN := 3.0
const FADE_OUT := 2.0
const SILENT_DB := -60.0
const DEFAULT_DB := -12.0

var enabled := true

var _players: Array[AudioStreamPlayer] = []
var _active := 0  # index into _players of the one playing (or fading in) the current track
var _track := ""  # the current world's track path ("" = none)
var _target_db := DEFAULT_DB
var _tweens: Array = [null, null]


func _ready() -> void:
	# Keep playing while the tree is paused (the connection gate pauses it).
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Track%d" % i
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)
	enabled = bool(SaveStore.load_json(SETTINGS_PATH).get("music", true))


## Play this world's music (its spec's "music" block; {} or no track = fade to quiet).
func play_world(cfg: Dictionary) -> void:
	var track := String(cfg.get("track", ""))
	_target_db = float(cfg.get("volume_db", DEFAULT_DB))
	if track == _track:
		# Same music in the next world (or the same world rebuilt): carry on, just settle the level.
		if enabled and track != "" and _players[_active].playing:
			_fade(_active, _target_db, FADE_IN)
		elif enabled and track != "":
			_start(track)
		return
	_track = track
	_fade(_active, SILENT_DB, FADE_OUT, true)
	if enabled and track != "":
		_start(track)


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	var settings := SaveStore.load_json(SETTINGS_PATH)
	settings["music"] = on
	SaveStore.save_json(SETTINGS_PATH, settings)
	if on:
		if _track != "":
			_start(_track)
	else:
		_fade(_active, SILENT_DB, 1.0, true)


func toggle() -> void:
	set_enabled(not enabled)


## Fade the current track in on the other player, from the top.
func _start(track: String) -> void:
	if not ResourceLoader.exists(track):
		push_warning("Music: no track at %s" % track)
		return
	var stream: Resource = load(track)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true  # the scores are rendered to loop seamlessly
	_active = 1 - _active
	var p := _players[_active]
	p.stream = stream as AudioStream
	p.volume_db = SILENT_DB
	p.play()
	_fade(_active, _target_db, FADE_IN)


## Tween one player's level. Tweened in decibels, which is roughly how loudness is heard, so a straight
## line in dB sounds like an even fade.
func _fade(i: int, to_db: float, seconds: float, stop_after := false) -> void:
	var p := _players[i]
	if _tweens[i] != null:
		(_tweens[i] as Tween).kill()
	if not p.playing:
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, seconds)
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[i] = tw
