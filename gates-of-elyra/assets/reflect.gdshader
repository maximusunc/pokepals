shader_type canvas_item;
// Stillglass's reflections. Every mirrored sprite (an actor, a shore tree, a phantom) is drawn flipped
// top to bottom by its own node or draw transform; this shader only decides WHERE it shows and HOW:
//   * clipped to the water, by sampling the lake's baked bitmap (WaterMask) at the fragment's world
//     position, so an image never spills onto the bank and the edge matches the water that is drawn;
//   * cooled and silvered a little (desaturated, mixed toward the lake's silver), as water does;
//   * a faint horizontal ripple, a whole texel at a time so it stays pixel-crisp, growing with depth;
//   * faded with depth below the reflection's axis (the waterline) when `axis_y` is given.
// Cheap by design: one extra texture read, only on the pixels of the reflected sprites themselves; no
// screen read, no render target. Per-draw fades come in on the vertex colour's alpha (trees use a gradient).

uniform sampler2D water_mask : filter_linear, repeat_disable;
uniform vec2 mask_origin = vec2(0.0);
uniform vec2 mask_size = vec2(1.0);
uniform vec4 silver : source_color = vec4(0.8, 0.88, 0.94, 1.0);
uniform vec4 tint_mul : source_color = vec4(1.0);
uniform float silver_mix = 0.28;
uniform float strength = 0.8;
uniform float wobble = 1.0;        // ripple amplitude in texels
uniform float wobble_speed = 1.0;
uniform float axis_y = 0.0;        // the waterline this image hangs from (world y)
uniform float fade_len = 96.0;     // px below the axis over which it fades; <= 0 disables the depth fade
uniform float boost = 0.0;         // extra shimmer (0..1): an image changing shape

varying highp vec2 wpos;
varying vec4 vmod;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vmod = COLOR;
}

void fragment() {
	vec2 muv = (wpos - mask_origin) / mask_size;
	float m = texture(water_mask, muv).r;
	float inside = smoothstep(0.4, 0.6, m);
	float amp = wobble * (1.0 + 2.2 * boost);
	float s = sin(wpos.y * 0.55 + TIME * 1.6 * wobble_speed) * amp + sin(wpos.y * 0.21 - TIME * 0.9 * wobble_speed) * amp * 0.6;
	vec2 uv = UV + vec2(floor(s + 0.5) * TEXTURE_PIXEL_SIZE.x, 0.0);
	vec4 t = texture(TEXTURE, uv);
	vec3 c = t.rgb * vmod.rgb * tint_mul.rgb;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(lum), 0.3);
	c = mix(c, silver.rgb, silver_mix + 0.25 * boost);
	float fade = 1.0;
	if (fade_len > 0.0) {
		fade = 1.0 - 0.85 * smoothstep(0.0, fade_len, wpos.y - axis_y);
	}
	COLOR = vec4(c, t.a * vmod.a * strength * inside * fade);
}
