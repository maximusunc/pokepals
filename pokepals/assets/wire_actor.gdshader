shader_type canvas_item;
//
// The WIRE look: how a visiting player + companion are drawn in Ohmstead, the machine behind the Gateway.
// Applied as a ShaderMaterial on the PlayerView / CompanionView node (scripts/presentation/otherworld_look.gd,
// a look with a "wire" block), so it redraws EVERYTHING the node draws -- every wardrobe layer, every daemon
// form -- as glowing linework, with no new art:
//
//   * the dark outline every sprite carries, and its silhouette's edge, light up in `line_color`
//     (magenta for a person, amber for a companion);
//   * wherever the colour changes sharply INSIDE the shape (a hat brim, a scarf, a stripe, an eye), an
//     `inner_color` line is drawn, so what you wear and which animal it is stay readable;
//   * everything else becomes a dark, nearly opaque fill with a breath of the original colour in it.
//
// Five texture reads a fragment on sprites a few dozen pixels wide: cheap.

uniform vec4 line_color : source_color = vec4(1.0, 0.55, 0.9, 1.0);
uniform vec4 inner_color : source_color = vec4(0.93, 0.98, 1.0, 1.0);
uniform vec4 fill_color : source_color = vec4(0.03, 0.02, 0.08, 0.86);
uniform float line_cut : hint_range(0.0, 0.6) = 0.20;
uniform float edge : hint_range(0.02, 1.0) = 0.20;
uniform float keep : hint_range(0.0, 1.0) = 0.16;
uniform float pulse_speed = 1.6;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec4 c = COLOR;  // the texture sample x vertex colour (incl. modulate): what the node drew
	if (c.a > 0.01) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		vec4 t0 = texture(TEXTURE, UV);
		vec4 tl = texture(TEXTURE, UV + vec2(-px.x, 0.0));
		vec4 tr = texture(TEXTURE, UV + vec2(px.x, 0.0));
		vec4 tu = texture(TEXTURE, UV + vec2(0.0, -px.y));
		vec4 td = texture(TEXTURE, UV + vec2(0.0, px.y));
		float l = luma(t0.rgb);
		float min_a = min(min(tl.a, tr.a), min(tu.a, td.a));
		// a sharp change of colour to an opaque neighbour on the right or below: an inner line (one side only,
		// so a boundary is one pixel wide, not two)
		float d = 0.0;
		if (tr.a > 0.5) { d = max(d, distance(t0.rgb, tr.rgb)); }
		if (td.a > 0.5) { d = max(d, distance(t0.rgb, td.rgb)); }
		vec3 o = mix(fill_color.rgb, c.rgb * 0.55, keep);
		float a = fill_color.a;
		float breathe = 0.86 + 0.14 * sin(TIME * pulse_speed);
		if (d > edge && l >= line_cut) {
			o = inner_color.rgb * (0.82 + 0.18 * breathe);
			a = 1.0;
		}
		if (l < line_cut || min_a < 0.5) {
			o = line_color.rgb * breathe + vec3(0.12) * (1.0 - breathe);
			a = 1.0;
		}
		COLOR = vec4(clamp(o, 0.0, 1.0), c.a * a);
	}
}
