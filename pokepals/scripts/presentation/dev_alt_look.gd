class_name DevAltLook
extends RefCounted
## ⚠️ DEV-ONLY, THROWAWAY hook for the Rung-3 shared-presence FEEL TEST. DELETE after.
##
## Two debug instances on one machine share the same user:// save, so they load the
## IDENTICAL companion + avatar — which makes "that's mine vs that's theirs" impossible to
## feel locally. This lets you flag ONE instance to wear a visibly DISTINCT identity (a cool
## blue avatar; a bigger, warmer-coated companion), so you can stand the two pairs side by
## side and feel the difference without needing a second device. The look it makes is real,
## not faked: the companion override only sets resting-look floats the rig already renders
## AND already broadcasts, so a friend's instance shows the alternate on the puppet too.
##
## ACTIVATE ON ONE INSTANCE ONLY. Easiest in the Godot editor:
##   Debug ▸ Customize Run Instances… ▸ enable, set 2 instances, and give instance #2 the
##   Feature Tag:  alt
## Or from a command line:  godot … -- alt      (a user arg, after the `--`)
## Or via environment:      POKEPALS_ALT=1 godot …
##
## TO REMOVE (one unit): delete this file, then delete the few `DevAltLook.` call sites —
## world_controller.gd (_setup_net, _local_identity, _apply_remote_identity) and
## companion_view.gd (_apply_look). Nothing else depends on it.

# A distinctly COOL, bright avatar tint vs the warm default body — reads instantly as
# "a different person". modulate multiplies the avatar's pixels; >1 channels brighten.
const PLAYER_TINT := Color(0.58, 0.72, 1.28)


## True only on the instance the developer flagged. Checked once per call (cheap); accepts a
## run-instance feature tag, a post-`--` user cmdline arg, or an env var so it's easy to set
## from whatever launch path you use.
static func active() -> bool:
	return OS.has_feature("alt") \
		or ("alt" in OS.get_cmdline_user_args()) \
		or (OS.get_environment("POKEPALS_ALT") != "")


static func player_tint() -> Color:
	return PLAYER_TINT


## A more SUBTLE companion difference (per the ask — different, but not as loud as the
## avatar): noticeably bigger, a warmed coat, and ears carried a touch more forward. Every
## field here is one the resting-look rig already renders (_apply_look/_draw) and already
## sends over the wire (resting_look_payload → apply_remote_look), so the alternate is a
## genuine grown-look, layered on top of whatever this companion had become.
static func companion_look_override(base: Dictionary) -> Dictionary:
	var look := base.duplicate(true)
	look["body_scale"] = clampf(float(base.get("body_scale", 1.0)) + 0.35, 0.25, 4.0)
	look["coat_warm"] = 1.0
	look["ear_rest"] = float(base.get("ear_rest", 0.0)) + 6.0
	look["wag_life"] = maxf(float(base.get("wag_life", 0.0)), 4.0)
	return look
