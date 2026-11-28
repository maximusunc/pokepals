shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// A drifting, world-anchored MIST laid over the whole view (Steamhollow, the bathhouse village lost in
// fog). Clear around the player, thickening to a soft wall a few steps out; lanterns, windows, your
// companion and friends each thin it into a small pocket so they still read through it. Drawn on a
// ColorRect inside MistVeil's small off-screen render, which feeds every uniform below. Presentation only.
//
// Everything here is in WORLD px: the rect sits in the world (its layer follows the camera), covering the
// view plus a margin, so the clear patch is drawn with exactly the same transform as the player sprite.
//
// Cheap on purpose, since it runs for every pixel on screen (it matters most on phones and the web):
//   * it is rendered SMALL (one texel per few world px) into an off-screen SubViewport and stretched over
//     the view, since mist is soft: it runs per fog texel, not per screen pixel;
//   * every STATIC light (lanterns, lit doors) is baked once into a low-res LIGHT MASK over the whole
//     world (one lookup), so any number of them show, all the time: none pop in as you approach;
//   * only the few MOVING pockets (your companion, friends, the bell) run through the short loop.

const int MAX_LIGHTS = 8;

uniform vec2 rect_origin = vec2(0.0);          // the rect's top-left, world px
uniform vec2 rect_size = vec2(640.0, 360.0);   // the rect's size, world px
uniform vec2 center = vec2(0.0);               // the player, world px
uniform float clear_r = 60.0;                  // world px of clear view round the player...
uniform float fade_r = 210.0;                  // ...and where the mist is at full density
uniform vec4 fog_color : source_color = vec4(0.84, 0.84, 0.91, 1.0);
uniform vec4 warm_color : source_color = vec4(1.0, 0.80, 0.52, 1.0);
uniform float density = 0.92;                  // the mist's strongest opacity
uniform float swirl = 0.35;                    // how much the noise billows the edge and mottles the mist
uniform float noise_scale = 0.011;             // noise cycles per world px
uniform vec2 drift = vec2(0.0);                // the mist's slow slide, world px (accumulated by the script)
uniform float time = 0.0;
uniform float strength = 1.0;                  // 0..1, fades the whole veil in on arrival
uniform float light_clear = 0.9;               // how much a pocket's centre thins the mist
uniform sampler2D light_mask : filter_linear;  // r: how much a static light thins the mist, g: its warmth
uniform vec2 mask_origin = vec2(0.0);          // the mask's top-left, world px
uniform vec2 mask_size = vec2(1.0);            // the mask's extent, world px
uniform float lamp = 0.0;                      // 0..1: the player is carrying a lit lantern (widens clear_r/fade_r, set by the script)...
uniform vec4 lamp_color : source_color = vec4(1.0, 0.82, 0.50, 1.0);   // ...and lights the mist round them this warm colour
uniform int light_count = 0;
uniform vec4 lights[MAX_LIGHTS];               // moving pockets: xy world px, z radius, w warmth 0..1

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 world = rect_origin + UV * rect_size;
	vec2 wp = world + drift;
	float n = vnoise(wp * noise_scale) * 0.62 + vnoise(wp * noise_scale * 2.4 + vec2(time * 0.035, -time * 0.025)) * 0.38;
	float d = distance(world, center);
	d += (n - 0.5) * 90.0 * swirl;   // the edge of the clear patch billows
	float a = smoothstep(clear_r, fade_r, d);
	a *= density * mix(1.0, 0.62 + 0.76 * n, swirl);

	// The static lights, baked: one lookup however many lanterns there are.
	vec2 m = texture(light_mask, (world - mask_origin) / mask_size).rg;
	a *= 1.0 - m.r * light_clear;
	float warm = m.g;

	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) {
			break;
		}
		vec4 l = lights[i];
		float k = 1.0 - smoothstep(0.0, l.z, distance(world, l.xy));
		k = k * k;
		a *= 1.0 - k * light_clear;
		warm = max(warm, k * l.w);
	}
	// mist lit from within by a lamp: warmer, and never quite vanishing right round it
	vec3 col = mix(fog_color.rgb, warm_color.rgb, clamp(warm * 1.4, 0.0, 1.0));
	// the player's own lantern: the mist round them glows the lamp's colour, strongest at the edge of the light
	float lampk = lamp * (1.0 - smoothstep(clear_r * 0.6, fade_r * 1.15, d));
	col = mix(col, lamp_color.rgb, clamp(lampk * 0.85, 0.0, 1.0));
	a = max(a, warm * 0.16);
	float alpha = clamp(a, 0.0, 1.0) * strength;
	COLOR = vec4(col * alpha, alpha);   // premultiplied: MistVeil composites the small render that way
}
