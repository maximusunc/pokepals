shader_type canvas_item;
render_mode unshaded;
// A drifting, world-anchored MIST laid over the whole view (Steamhollow, the bathhouse village lost in
// fog). Clear around the player, thickening to a soft wall a few steps out; lanterns, windows, your
// companion and friends each thin it into a small pocket so they still read through it. Cheap on purpose
// (two octaves of hash noise and a short fixed light loop) so it holds up on a phone. Drawn on a
// ColorRect by MistVeil, which feeds every uniform below. Presentation only.
//
// Everything here is in WORLD px: the rect sits in the world (its layer follows the camera), covering the
// view plus a margin, so the clear patch is drawn with exactly the same transform as the player sprite.
// (It used to be screen-space with the player's position converted through the camera each frame, which
// could be a frame stale and made the clear patch jitter behind the player.)

const int MAX_LIGHTS = 12;

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
uniform int light_count = 0;
uniform vec4 lights[MAX_LIGHTS];               // xy world px, z radius (world px), w warmth 0..1

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
	float warm = 0.0;
	float glow = 0.0;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) {
			break;
		}
		vec4 l = lights[i];
		float k = 1.0 - smoothstep(0.0, l.z, distance(world, l.xy));
		k = k * k;
		a *= 1.0 - k * light_clear;
		warm = max(warm, k * l.w);
		glow = max(glow, k * l.w);
	}
	// mist lit from within by a lamp: warmer, and never quite vanishing right round it
	vec3 col = mix(fog_color.rgb, warm_color.rgb, clamp(warm * 1.4, 0.0, 1.0));
	a = max(a, glow * 0.16);
	COLOR = vec4(col, clamp(a, 0.0, 1.0) * strength);
}
