extends Node
## Background music: one looping track per world, crossfaded as you travel.
##
## A world asks for its music in its spec: `"music": { "track": "res://assets/music/vale.ogg",
## "volume_db": -22 }`. world_controller hands that block over on every build (play_world); a world
## with none fades to quiet. The tracks themselves are rendered from text scores by
## tools/gen_music.py (see tools/music/README.md), every file at the same loudness (-16 LUFS), so a
## spec's volume_db means the same thing in every world: -22 puts the music at about -38 LUFS, well
## under where a whole game's sound usually sits (-24 LUFS on consoles), because it's background.
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
## The player's VOLUME (the Sound sheet's slider) is a device preference, not game state, so it lives
## in user://settings.json beside the identity token, not on the server. The slider's middle (0.5, the
## default) is the level the world asks for; each end is 12 dB louder or silence. The curve is squared
## (40 * log10 rather than 20), so the slider's travel feels even to the ear and the quiet end is fine
## to set, not a cliff.
##
## Registered as the "Music" autoload; no class_name, so the global name and a class can't clash.

const SETTINGS_PATH := "user://settings.json"
const FADE_IN := 3.0
const FADE_OUT := 2.0
const SILENT_DB := -60.0
const DEFAULT_DB := -22.0
const DEFAULT_VOLUME := 0.5

## The slider: 0 (off) .. 1. DEFAULT_VOLUME plays a world's track at exactly its spec's volume_db.
var volume := DEFAULT_VOLUME

var _players: Array[AudioStreamPlayer] = []
var _active := 0  # index into _players of the one playing (or fading in) the current track
var _track := ""  # the current world's track path ("" = none)
var _world_db := DEFAULT_DB  # the current world's volume_db, before the slider
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
	var settings := SaveStore.load_json(SETTINGS_PATH)
	if settings.has("music_volume"):
		volume = clampf(float(settings["music_volume"]), 0.0, 1.0)
	elif settings.get("music", true) == false:
		volume = 0.0  # the earlier on/off switch, set to off


func is_on() -> bool:
	return volume > 0.0


## Play this world's music (its spec's "music" block; {} or no track = fade to quiet).
func play_world(cfg: Dictionary) -> void:
	var track := String(cfg.get("track", ""))
	_world_db = float(cfg.get("volume_db", DEFAULT_DB))
	if track == _track:
		# Same music in the next world (or the same world rebuilt): carry on, just settle the level.
		if is_on() and track != "" and _players[_active].playing:
			_fade(_active, _level_db(), FADE_IN)
		elif is_on() and track != "":
			_start(track)
		return
	_track = track
	_fade(_active, SILENT_DB, FADE_OUT, true)
	if is_on() and track != "":
		_start(track)


## Set the slider (0..1), applied at once and saved. `save` is false while a finger is still dragging.
func set_volume(v: float, save := true) -> void:
	var was_on := is_on()
	volume = clampf(v, 0.0, 1.0)
	if save:
		var settings := SaveStore.load_json(SETTINGS_PATH)
		settings["music_volume"] = volume
		settings.erase("music")
		SaveStore.save_json(SETTINGS_PATH, settings)
	if not is_on():
		if was_on:
			_fade(_active, SILENT_DB, 0.4, true)
	elif not was_on or not _players[_active].playing:
		if _track != "":
			_start(_track)
	else:
		# Mid-track: follow the slider straight away (cancelling any fade still in flight).
		if _tweens[_active] != null:
			(_tweens[_active] as Tween).kill()
		_players[_active].volume_db = _level_db()


## The level to play at: the world's volume_db shifted by the slider.
func _level_db() -> float:
	return _world_db + 40.0 * log(volume / DEFAULT_VOLUME) / log(10.0)


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
	_fade(_active, _level_db(), FADE_IN)


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
