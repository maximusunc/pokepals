shader_type canvas_item;
// EBBMERE's tide. One quad over the flats; the fragment reads the world's baked seabed (one byte per cell,
// elevation 0..1) and compares it with the tide `level`, so where the water is is a function of those two
// numbers and nothing else: no geometry to rebuild, no render target, no per-frame allocation. Open sea
// (elevation under deep_elev) is always water; over that, the water covers whatever is lower than `level`.
// Past the waterline the sand is darkened and glossed as wet (it reflects the sky) for a short band, which
// is why the flats shine most right behind the retreating edge.
// The CPU reads the very same grid (TideField), so what you see is what you wade.

uniform sampler2D seabed : filter_linear, repeat_disable;
uniform vec4 field_rect;          // x, y, w, h of the grid, world px
uniform float level = 0.5;
uniform float deep_elev = 0.26;
uniform float time = 0.0;
uniform vec3 deep_col : source_color = vec3(0.14, 0.30, 0.40);
uniform vec3 shallow_col : source_color = vec3(0.52, 0.76, 0.80);
uniform vec3 foam_col : source_color = vec3(0.97, 0.99, 0.97);
uniform vec3 wet_col : source_color = vec3(0.36, 0.32, 0.27);
uniform vec3 sheen_col : source_color = vec3(0.88, 0.93, 0.96);
uniform float wet_band = 0.10;
uniform float foam_band = 0.012;
uniform float shallow_alpha = 0.46;
uniform float deep_alpha = 0.9;

varying vec2 wpos;

void vertex() {
	wpos = VERTEX;
}

void fragment() {
	vec2 uv = (wpos - field_rect.xy) / field_rect.zw;
	float e = texture(seabed, uv).r;
	// a slow wobble of the waterline, so the edge breathes instead of tracing a contour line
	float wob = 0.010 * sin(wpos.x * 0.05 + time * 0.5 + sin(wpos.y * 0.03) * 2.0) * sin(wpos.y * 0.043 - time * 0.35)
		+ 0.005 * sin((wpos.x + wpos.y) * 0.11 + time * 0.9);
	vec4 col = vec4(0.0);
	if (e < deep_elev) {
		float g = 0.5 + 0.5 * sin(wpos.x * 0.04 + time * 0.6 + sin(wpos.y * 0.06) * 1.5);
		col = vec4(mix(deep_col, shallow_col, g * 0.14), deep_alpha);
	} else {
		float depth = level - e + wob;
		if (depth > 0.0) {
			float k = smoothstep(0.0, 0.30, depth);
			vec3 c = mix(shallow_col, deep_col, k * 0.8);
			float r = sin(wpos.x * 0.09 + time * 0.8 + sin(wpos.y * 0.05) * 2.0) * sin(wpos.y * 0.11 - time * 0.6);
			c += 0.04 * r;
			float a = mix(shallow_alpha, deep_alpha * 0.9, k);
			float f = 1.0 - smoothstep(0.0, foam_band, depth);
			float lace = 0.5 + 0.5 * sin(wpos.x * 0.35 + wpos.y * 0.2 + time * 1.4);
			c = mix(c, foam_col, f * (0.55 + 0.4 * lace));
			a = max(a, f * 0.9);
			col = vec4(c, a);
		} else {
			float w = smoothstep(-wet_band, 0.0, depth);
			float gloss = w * (0.5 + 0.5 * sin(wpos.x * 0.013 + wpos.y * 0.021 + time * 0.2));
			col = vec4(mix(wet_col, sheen_col, gloss * 0.7), w * 0.42 + gloss * 0.1);
		}
	}
	COLOR = col;
}
