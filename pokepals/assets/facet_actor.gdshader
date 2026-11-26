shader_type canvas_item;
//
// The FACET look: how a visiting player and companion are drawn in Glintwold, the world that was cut, not grown.
// Applied as a ShaderMaterial on the PlayerView / CompanionView node (scripts/presentation/otherworld_look.gd, a
// look with a "facet" block), so it redraws EVERYTHING the node draws from a sheet (every wardrobe layer, every
// animal) as low-poly, with no new art:
//
//   * the sheet is cut, in texel space, into cells `cell` texels a side, each split on an alternating diagonal
//     into two triangles. This runs per SCREEN pixel, so the diagonals are crisp even though the sheet is tiny;
//   * each triangle takes ONE colour: the average of a few taps inside it (its centroid and towards each corner).
//     It is drawn only if enough taps land on the figure. The sheet's dark outline is left out of the average
//     when there is any colour to take instead, and a triangle that is all outline is lifted to a soft slate,
//     so nothing turns into black triangles;
//   * each triangle then turns a little lighter or darker by its own slant against the same turning light as
//     the ground (`light_angle`, written each frame by FacetGround), in a few hard steps, so it reads as cut
//     planes;
//   * a lone dark texel with colour all round it (an eye) is kept as it was drawn.
//
// Anything drawn without a sheet (a shadow, an emote) passes through as drawn. Laid layers line up: every layer
// of a paper-doll avatar is the same size, so their triangles are the same triangles.

uniform float cell = 3.0;
uniform float light_angle = -2.356;
uniform float light_height = 0.9;
uniform float shade = 0.22;            // how much lighter or darker a facet can turn
uniform float steps = 2.0;             // posterise: this many steps each way
uniform float tilt = 0.9;              // how slanted the facets are
uniform float outline_cut = 0.2;       // luma under this: an outline texel
uniform vec4 outline_color : source_color = vec4(0.36, 0.33, 0.44, 1.0);
uniform float outline_lift = 0.55;     // how far an all-outline facet moves toward outline_color
uniform float rim = 0.12;              // how much darker an edge facet is (a hint of the outline)
uniform float min_taps = 2.0;          // of 4: how many must land on the figure for the facet to be drawn
uniform float keep_eyes = 1.0;
uniform float saturation = 1.06;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;   // vertex colour times the node's modulate
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

vec4 tap(sampler2D tex, vec2 texel, vec2 px) {
	return texture(tex, (floor(texel) + 0.5) * px);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	if (px.x < 0.2) {
		vec2 tp = UV / px;
		vec2 g = tp / cell;
		vec2 id = floor(g);
		vec2 f = g - id;
		bool even = mod(id.x + id.y, 2.0) < 0.5;
		vec2 a = vec2(0.0);
		vec2 b = vec2(1.0, 0.0);
		vec2 c = vec2(1.0, 1.0);
		float k = 0.0;
		if (even) {
			if (f.x <= f.y) { b = vec2(1.0, 1.0); c = vec2(0.0, 1.0); k = 1.0; }
		} else {
			if (f.x + f.y < 1.0) { c = vec2(0.0, 1.0); }
			else { a = vec2(1.0, 0.0); b = vec2(1.0, 1.0); c = vec2(0.0, 1.0); k = 1.0; }
		}
		vec2 cen = (a + b + c) / 3.0;
		vec4 s0 = tap(TEXTURE, (id + cen) * cell, px);
		vec4 s1 = tap(TEXTURE, (id + mix(cen, a, 0.6)) * cell, px);
		vec4 s2 = tap(TEXTURE, (id + mix(cen, b, 0.6)) * cell, px);
		vec4 s3 = tap(TEXTURE, (id + mix(cen, c, 0.6)) * cell, px);
		float n_op = 0.0;
		float n_lit = 0.0;
		vec3 sum_lit = vec3(0.0);
		vec3 sum_dark = vec3(0.0);
		float alpha = 0.0;
		vec4 ss[4] = vec4[4](s0, s1, s2, s3);
		for (int i = 0; i < 4; i++) {
			vec4 s = ss[i];
			if (s.a > 0.5) {
				n_op += 1.0;
				alpha = max(alpha, s.a);
				if (luma(s.rgb) >= outline_cut) {
					n_lit += 1.0;
					sum_lit += s.rgb;
				} else {
					sum_dark += s.rgb;
				}
			}
		}
		if (n_op < min_taps) {
			COLOR = vec4(0.0);
		} else {
			vec3 col;
			if (n_lit > 0.0) {
				col = sum_lit / n_lit;
				col *= 1.0 - rim * (1.0 - n_lit / 4.0);
			} else {
				col = mix(sum_dark / n_op, outline_color.rgb, outline_lift);
			}
			// the facet's slant against the turning light, in a few hard steps
			vec2 nh = (hash2(id * 1.31 + k * 7.7) - 0.5) * 2.0;
			vec2 ridge = (k > 0.5 ? vec2(-0.5, 0.5) : vec2(0.5, -0.5)) * (even ? 1.0 : -1.0);
			vec3 n = normalize(vec3((nh * 0.8 + ridge * 0.25) * tilt, 1.0));
			vec3 L = normalize(vec3(cos(light_angle), sin(light_angle), light_height));
			float lit = dot(n, L) - L.z;
			float v = clamp(lit * 3.0, -1.0, 1.0);
			v = floor(v * steps + 0.5) / steps;
			col *= 1.0 + v * shade;
			float l = luma(col);
			col = mix(vec3(l), col, saturation);
			// an eye: a dark texel here with colour on every side of it (an outline has dark along it)
			if (keep_eyes > 0.5) {
				vec4 t0 = tap(TEXTURE, tp, px);
				if (t0.a > 0.5 && luma(t0.rgb) < outline_cut) {
					vec4 nl = tap(TEXTURE, tp + vec2(-1.0, 0.0), px);
					vec4 nr = tap(TEXTURE, tp + vec2(1.0, 0.0), px);
					vec4 nu = tap(TEXTURE, tp + vec2(0.0, -1.0), px);
					vec4 nd = tap(TEXTURE, tp + vec2(0.0, 1.0), px);
					float all_op = step(0.5, nl.a) * step(0.5, nr.a) * step(0.5, nu.a) * step(0.5, nd.a);
					float dark_n = step(luma(nl.rgb), outline_cut) + step(luma(nr.rgb), outline_cut)
						+ step(luma(nu.rgb), outline_cut) + step(luma(nd.rgb), outline_cut);
					if (all_op > 0.5 && dark_n <= 1.0) {
						col = t0.rgb;
					}
				}
			}
			COLOR = vec4(clamp(col, 0.0, 1.0), alpha) * vcol;
		}
	}
}
