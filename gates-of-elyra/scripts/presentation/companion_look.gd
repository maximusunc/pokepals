class_name CompanionLook
extends RefCounted
## The companion's RESTING LOOK — a pure, deterministic mapping from WHO IT HAS BECOME
## (its crystallized `identity` traits) plus the strength of the `bond` into a handful of
## small pose offsets the body rig already understands. This is the presentation-side
## reading of the companion's evolution: over a bond arc its resting posture shifts to
## mirror how you play, and it grows from a little smaller to its full size as the bond
## locks in — so you can SEE this companion has become yours, with no meters or numbers.
##
## Pure data in, plain dict out — no nodes, no scene tree, no CompanionSelf. That keeps the
## logic/presentation split clean (the mind is untouched; the view just reads identity+bond)
## and makes the whole mapping trivially unit-testable.
##
## Read IDENTITY, never the live `traits`: identity is the slow, persistent ANCHOR, so the
## resting look stays steady; the live disposition wobbles with mood and would make it twitch.
##
## All amplitudes are deliberately SMALL relative to the mood ranges in `expression` — mood
## stays the dominant, fast body-language signal; identity is a quiet bias underneath. And
## every identity-driven offset is scaled by a bond CRYSTALLIZATION gate, ~0 when fresh and
## full as bond -> 1, dovetailing with the identity literally locking in as you bond: you
## can't read its grown self until it has actually grown into one.

## identity + bond -> resting-look offsets. `identity` is read-only (never mutated). `cfg` is
## the companion config; the tuning lives under cfg["identity_look"]. A missing block yields a
## neutral look (all zero offsets, full size, no coat), so an old config is a silent no-op.
static func resting_look(identity: Dictionary, bond: float, cfg: Dictionary) -> Dictionary:
	var look := {
		"ear_rest": 0.0,    # px to SUBTRACT from ear_offset (+ perks ears up/forward, - softens/relaxes)
		"bounce_base": 0.0, # added to the idle bounce gain (a livelier resting fidget)
		"wag_life": 0.0,    # a resting tail-wag amplitude FLOOR (a little life even when calm)
		"eye_lift": 0.0,    # px of upward gaze bias (alert, carried head)
		"coat_warm": 0.0,   # 0..1 emergent coat warming, only past a high bond
		"body_scale": 1.0,  # body size multiplier: grows from scale_floor -> 1.0 over the bond
	}
	var il: Dictionary = cfg.get("identity_look", {})
	var b := clampf(bond, 0.0, 1.0)

	# Size grows with the BOND alone (not identity): a young companion starts a touch smaller and
	# reaches full size as the bond crystallizes. Its own gentle mapping, independent of the
	# identity gate below. Defaults to no scaling (1.0) when unconfigured, so it's a safe no-op.
	var size: Dictionary = il.get("size", {})
	var scale_floor := float(size.get("scale_floor", 1.0))
	look["body_scale"] = lerpf(scale_floor, 1.0, pow(b, float(size.get("scale_exp", 1.0))))

	# Emergent coat warmth: holds at 0 until a high bond, then ramps to full by bond 1 — the
	# "fully bonded, fully itself" tint. Independent of identity (it's about the relationship).
	var coat: Dictionary = il.get("coat", {})
	var coat_start := float(coat.get("bond_start", 1.0))
	if b > coat_start and coat_start < 1.0:
		look["coat_warm"] = clampf((b - coat_start) / (1.0 - coat_start), 0.0, 1.0)

	if il.is_empty():
		return look

	# Crystallization gate: the identity-driven pose only reads in as the bond deepens (and the
	# identity itself locks). pow(.., bond_exp) shapes how late it comes on; ~0 at/below bond_floor.
	var bond_floor := float(il.get("bond_floor", 0.0))
	var gate := pow(clampf((b - bond_floor) / maxf(1.0 - bond_floor, 0.0001), 0.0, 1.0), float(il.get("bond_exp", 1.0)))
	if gate <= 0.0:
		return look

	# Ears: curiosity PERKS them up/forward (a positive value, subtracted from ear_offset to
	# raise), clinginess RELAXES them (softer, slightly lowered) — a curious companion carries
	# its ears alert, a clingy one softer. Net, so a curious-but-clingy one lands in between.
	var ear := _axis(il.get("ear_curiosity", {}), identity, "curiosity") - _axis(il.get("ear_clinginess", {}), identity, "clinginess")
	# Idle liveliness: energy lifts the resting bounce and gives the tail a little life even when
	# standing; clinginess trims the fidget a touch (a calmer, closer presence). Floored at 0.
	var bounce := _axis(il.get("bounce_energy", {}), identity, "energy") - _axis(il.get("bounce_clinginess", {}), identity, "clinginess")
	var wag := _axis(il.get("wag_energy", {}), identity, "energy")
	# Gaze: a curious companion carries its eyes a touch higher (alert, taking the world in).
	var eye := _axis(il.get("eye_curiosity", {}), identity, "curiosity")

	look["ear_rest"] = ear * gate
	look["bounce_base"] = maxf(0.0, bounce) * gate
	look["wag_life"] = maxf(0.0, wag) * gate
	look["eye_lift"] = maxf(0.0, eye) * gate
	return look


# One trait axis -> px/amount via a plain lerp(lo, hi, trait). Returns 0 for an absent spec, so
# each contribution is opt-in from config. `identity` is read-only (never mutated).
static func _axis(spec: Dictionary, identity: Dictionary, default_trait: String) -> float:
	if spec.is_empty():
		return 0.0
	var key := String(spec.get("trait", default_trait))
	var tv := clampf(float(identity.get(key, 0.5)), 0.0, 1.0)
	return lerpf(float(spec.get("lo", 0.0)), float(spec.get("hi", 0.0)), tv)
