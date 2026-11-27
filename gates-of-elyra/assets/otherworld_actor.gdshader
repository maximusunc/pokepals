shader_type canvas_item;
//
// The OTHERWORLD look: how a visiting player + companion are lit on a world that re-skins itself
// (Nocthollow, the night planet). Applied as a ShaderMaterial on the PlayerView / CompanionView node
// (see scripts/presentation/otherworld_look.gd), so it recolours EVERYTHING the node draws — every
// wardrobe layer, every daemon form — without new art. Still recognisably you:
//
//   * a SPLIT-TONE palette shift: shadows multiply toward `shadow_mult` (cool violet), lights toward
//     `light_mult`, a touch pulled toward the planet's `cast` colour — hues survive, the light changes;
//   * a little extra saturation so outfits don't go muddy in the night palette;
//   * GLOWING LINEWORK: the near-black outline every sprite carries (luminance under `line_cut`)
//     lights up in `line_glow`, gently breathing — your silhouette drawn in the planet's light.
//
// A procedural fallback (no texture) has no outline pixels, so it just gets the split-tone.

uniform vec4 shadow_mult : source_color = vec4(0.62, 0.55, 1.0, 1.0);
uniform vec4 light_mult : source_color = vec4(0.92, 1.0, 1.0, 1.0);
// The *_boost terms let a multiplier go above 1 (source_color clamps to 0..1): final mult = mult * boost.
uniform float shadow_boost = 1.15;
uniform float light_boost = 1.08;
uniform vec4 cast : source_color = vec4(0.30, 0.40, 0.85, 1.0);
uniform float cast_amount : hint_range(0.0, 1.0) = 0.12;
uniform float saturation = 1.1;
uniform vec4 line_glow : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform float line_amount : hint_range(0.0, 1.0) = 0.7;
uniform float line_cut : hint_range(0.0, 0.5) = 0.16;
uniform float pulse_speed = 1.6;

void fragment() {
	vec4 c = COLOR;  // the texture sample × vertex colour (incl. modulate) — what the node drew
	if (c.a > 0.01) {
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		vec3 s = mix(vec3(l), c.rgb, saturation);
		vec3 m = mix(shadow_mult.rgb * shadow_boost, light_mult.rgb * light_boost, smoothstep(0.0, 0.9, l));
		vec3 o = s * m;
		o = mix(o, cast.rgb * l * 1.4, cast_amount);
		if (l < line_cut) {
			float breathe = 0.8 + 0.2 * sin(TIME * pulse_speed);
			o = mix(o, line_glow.rgb, line_amount * breathe);
		}
		COLOR = vec4(clamp(o, 0.0, 1.0), c.a);
	}
}
