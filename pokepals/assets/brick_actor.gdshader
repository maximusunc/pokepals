shader_type canvas_item;
//
// The BRICK look: how a visiting player + companion are drawn on Clickton, the city made entirely of
// small colourful bricks (see OtherworldLook's `brick` block). Applied as a ShaderMaterial on the
// PlayerView / CompanionView node, so it rebuilds EVERYTHING the node draws, every wardrobe layer and
// every daemon form, out of bricks, without any new art:
//
//   * the sprite is cut into square CELLS of `cell` texels (4 divides every 32 px frame, so the grid
//     sits still on the figure as its walk cycle plays); each cell that is mostly filled becomes ONE
//     brick, the average colour of what was under it, nudged toward the nearest stock brick colour;
//   * each brick is shaded like a real one: a lit top-left edge, a shaded bottom-right seam, and a stud
//     standing on the face. The silhouette steps in whole bricks, so you are a little brick figure.
//
// The sprite's own vertex colour (modulate: fades, flashes) is kept.

uniform float cell = 4.0;          // texels per brick
uniform float quantize : hint_range(0.0, 1.0) = 0.6;   // how far to pull toward the stock brick colours
uniform float stud_gain : hint_range(0.0, 1.0) = 1.0;

varying vec4 vmod;

void vertex() {
	vmod = COLOR;
}

const vec3 STOCK[20] = vec3[20](
	vec3(0.769, 0.157, 0.106), vec3(0.051, 0.412, 0.671), vec3(0.961, 0.804, 0.188), vec3(0.157, 0.498, 0.275),
	vec3(0.855, 0.522, 0.251), vec3(0.949, 0.953, 0.953), vec3(0.106, 0.165, 0.204), vec3(0.639, 0.635, 0.647),
	vec3(0.388, 0.373, 0.384), vec3(0.843, 0.773, 0.600), vec3(0.412, 0.251, 0.157), vec3(1.000, 0.596, 0.863),
	vec3(0.655, 0.514, 0.784), vec3(0.071, 0.616, 0.616), vec3(0.800, 0.557, 0.412), vec3(0.643, 0.741, 0.278),
	vec3(0.455, 0.722, 0.871), vec3(0.482, 0.180, 0.184), vec3(0.545, 0.373, 0.255), vec3(0.918, 0.718, 0.553));

void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE;
	vec2 px = UV / ps;                    // texel coordinates (fractional)
	vec2 ip = floor(px);
	vec2 org = floor(ip / cell) * cell;   // this cell's top-left texel
	vec2 q = ip - org;                    // which texel of the cell we are

	// the four texels near the cell's corners-in: what is under this brick
	vec4 s0 = texture(TEXTURE, (org + vec2(1.5, 1.5)) * ps);
	vec4 s1 = texture(TEXTURE, (org + vec2(cell - 1.5, 1.5)) * ps);
	vec4 s2 = texture(TEXTURE, (org + vec2(1.5, cell - 1.5)) * ps);
	vec4 s3 = texture(TEXTURE, (org + vec2(cell - 1.5, cell - 1.5)) * ps);
	float w0 = step(0.5, s0.a);
	float w1 = step(0.5, s1.a);
	float w2 = step(0.5, s2.a);
	float w3 = step(0.5, s3.a);
	float n = w0 + w1 + w2 + w3;
	if (n < 2.0) {
		COLOR = vec4(0.0);
	} else {
		vec3 avg = (s0.rgb * w0 + s1.rgb * w1 + s2.rgb * w2 + s3.rgb * w3) / n;
		// the nearest stock colour, by plain distance
		vec3 best = STOCK[0];
		float bd = 10.0;
		for (int i = 0; i < 20; i++) {
			vec3 d = STOCK[i] - avg;
			float dd = dot(d, d);
			if (dd < bd) {
				bd = dd;
				best = STOCK[i];
			}
		}
		vec3 c = mix(avg, best, quantize);
		float lastp = cell - 1.0;
		float shade = 1.0;
		if (q.x >= lastp || q.y >= lastp) {
			shade = 0.74;                      // the seam along the bottom and right
		} else if (q.x < 1.0 || q.y < 1.0) {
			shade = 1.13;                      // the lit top-left edge
		} else if (q.x < 2.0 && q.y < 2.0) {
			shade = 1.0 + 0.3 * stud_gain;     // the stud's highlight
		} else if (q.x >= lastp - 1.0 && q.y >= lastp - 1.0) {
			shade = 1.0 - 0.12 * stud_gain;    // the stud's shadow side
		} else {
			shade = 1.0 + 0.08 * stud_gain;    // the stud's face
		}
		COLOR = vec4(clamp(c * shade, 0.0, 1.0), vmod.a) ;
		COLOR.rgb *= vmod.rgb;
	}
}
