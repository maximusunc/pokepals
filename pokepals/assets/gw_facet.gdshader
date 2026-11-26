shader_type canvas_item;
//
// Glintwold's ground: a field of flat triangles (glints), one shader over one quad
// (scripts/presentation/facet_ground.gd). No render target and no screen read; one small mask texture,
// baked once per world.
//
//   * THE FACETS: a triangle grid computed here, `cell` world units a side, each cell split on an
//     alternating diagonal, its corners nudged by a hash (`jitter`) so it never reads as a grid. Every corner
//     has a height (a slow roll of hills plus a hashed bump), so every triangle has a slope, and it takes ONE
//     colour from its ramp by how that slope faces the light.
//   * THE LIGHT turns (`light_angle`, pushed from FacetLight each frame), so the shades shift slowly all over
//     the world. Nothing here ever looks quite the same twice.
//   * THE MASK (built once on the CPU, linearly filtered), read at each triangle's CENTROID, so every edge
//     between kinds is a sharp zig-zag of whole triangles:
//       R = paths  (1 on the centre line, fading out)            -> sand
//       G = water  (> 0.5 in the water, fading to 0 inland)      -> water, then a band of shore sand
//       B = where across its pond a point lies (0 north .. 1 south): the water holds the sky in bands
//   * FOOTSTEPS: the triangle underfoot flashes brighter and settles; the ones round it catch a faint ring.
//   * Past the world's edge: the island's stone rim to the south, then sky (wide bands, a few slow clouds).
//
// Everything is in world units (the node sits at the origin, unscaled). Ramps are darkest first.

uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(-1700.0, -1300.0, 3400.0, 2600.0);  // x, y, w, h the mask covers
uniform vec4 bounds = vec4(-1700.0, -1300.0, 3400.0, 2600.0);
uniform float cell = 34.0;
uniform float jitter = 0.3;          // how far a corner wanders, as a share of a cell (kept under 0.45)
uniform float relief = 0.55;         // how steep the facets are
uniform float hills = 0.65;          // the share of a corner's height that is the slow roll of hills
uniform float hill_scale = 380.0;    // how wide the hills are
uniform float light_angle = -2.356;  // the direction TOWARD the light, on the ground (radians, y down)
uniform float light_height = 0.85;   // the light's height (lower = a raking light, more contrast)
uniform float contrast = 1.6;        // how far a slope moves a facet along its ramp
uniform float grain = 0.18;          // a little per-facet scatter, so a flat field isn't one colour
uniform float now = 0.0;

uniform vec3 grass[6];
uniform int grass_n = 5;
uniform vec3 sand[6];
uniform int sand_n = 3;
uniform vec3 shore[6];
uniform int shore_n = 3;
uniform vec3 water[6];               // far (north) first .. near (south) last
uniform int water_n = 4;
uniform vec3 stone[6];
uniform int stone_n = 3;
uniform vec3 sky[6];                 // top first
uniform int sky_n = 5;
uniform vec4 cloud_color : source_color = vec4(1.0, 0.98, 0.95, 0.85);
uniform vec4 cloud_shade : source_color = vec4(0.93, 0.9, 0.95, 0.85);
uniform vec4 step_color : source_color = vec4(1.0, 0.98, 0.88, 1.0);

uniform float path_cut = 0.42;       // mask R over this: a path facet
uniform float shore_cut = 0.18;      // mask G over this (and under 0.5): shore sand
uniform float water_relief = 0.25;   // how much the slope still shows on the water
uniform float lip_cut = 0.75;        // mask G under this (and over 0.5): a waterline facet
uniform float lip_dark = 0.14;       // how much deeper a waterline facet is
uniform float band_wobble = 0.05;    // how much the bands sway, slowly
uniform float glint_share = 0.06;    // how many water facets ever catch a glint
uniform float glint_period = 7.0;    // seconds between one facet's glints
uniform float glint_alpha = 0.6;
uniform float cliff = 70.0;          // how deep the island's stone rim shows below its south edge
uniform float sky_reach = 900.0;     // the sky's bands run from this far above the world to this far below
uniform float cloud_cell = 560.0;
uniform float cloud_speed = 6.0;

// regions: x, y, w, h; tints: rgb + how much
uniform vec4 regions[12];
uniform vec4 region_tints[12];
uniform int region_n = 0;
uniform float region_feather = 140.0;

uniform float step_life = 1.6;
uniform float step_amount = 0.55;
uniform float ring_speed = 60.0;
// x, y, start time, unused
uniform vec4 pulses[12];

varying vec2 wpos;

void vertex() {
	wpos = VERTEX;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// a lattice corner: where it sits (xy, world units) and how high it stands (z, 0..1)
vec3 corner(vec2 ij) {
	vec2 pos = (ij + (hash2(ij) - 0.5) * 2.0 * jitter) * cell;
	vec2 q = pos / hill_scale;
	float roll = 0.5 + 0.22 * sin(q.x * 1.7 + 1.3) * cos(q.y * 1.3 - 0.4) + 0.16 * sin((q.x + q.y) * 0.9 + 2.1)
		+ 0.12 * cos(q.x * 0.6 - q.y * 1.1);
	float h = mix(hash1(ij + 17.31), roll, hills);
	return vec3(pos, h);
}

float edge_side(vec2 p, vec2 a, vec2 b) {
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

bool in_tri(vec2 p, vec2 a, vec2 b, vec2 c) {
	float d1 = edge_side(p, a, b);
	float d2 = edge_side(p, b, c);
	float d3 = edge_side(p, c, a);
	bool has_neg = (d1 < -0.001) || (d2 < -0.001) || (d3 < -0.001);
	bool has_pos = (d1 > 0.001) || (d2 > 0.001) || (d3 > 0.001);
	return !(has_neg && has_pos);
}

// one colour from a ramp (darkest first) for a 0..1 shade
#define RAMP(r, n, s) r[clamp(int(floor((s) * float(n))), 0, (n) - 1)]

// sky beyond the world: wide bands, top to bottom, and a few big flat clouds drifting east
vec3 sky_at(vec2 p) {
	float k = clamp((p.y - (bounds.y - sky_reach)) / (bounds.w + 2.0 * sky_reach), 0.0, 0.999);
	vec3 col = RAMP(sky, sky_n, k);
	vec2 q = vec2(p.x - now * cloud_speed, p.y);
	vec2 cid = floor(q / cloud_cell);
	if (hash1(cid + 3.7) > 0.55) {
		vec2 cc = (cid + 0.5) * cloud_cell + (hash2(cid + 9.1) - 0.5) * cloud_cell * 0.3;
		float r = cloud_cell * (0.24 + 0.14 * hash1(cid + 1.9));
		float a0 = hash1(cid + 4.4) * 6.2832;
		vec2 c0 = cc + vec2(cos(a0), sin(a0) * 0.45) * r;
		vec2 c1 = cc + vec2(cos(a0 + 2.3), sin(a0 + 2.3) * 0.45) * r;
		vec2 c2 = cc + vec2(cos(a0 + 4.1), sin(a0 + 4.1) * 0.45) * r;
		if (in_tri(q, c0, c1, c2)) {
			vec2 L = vec2(cos(light_angle), sin(light_angle));
			vec4 cl = dot(q - (c0 + c1 + c2) / 3.0, L) > 0.0 ? cloud_color : cloud_shade;
			col = mix(col, cl.rgb, cl.a);
		}
	}
	return col;
}

void fragment() {
	// which triangle is this point in? With corners wandering under half a cell, only the 2x2 cells on this
	// side of the cell's middle can hold it
	vec2 g = wpos / cell;
	vec2 home = floor(g);
	vec2 f = g - home;
	vec2 base = home + vec2(f.x < 0.5 ? -1.0 : 0.0, f.y < 0.5 ? -1.0 : 0.0);
	vec3 v[9];
	for (int y = 0; y < 3; y++) {
		for (int x = 0; x < 3; x++) {
			v[y * 3 + x] = corner(base + vec2(float(x), float(y)));
		}
	}
	vec3 t0 = v[0];
	vec3 t1 = v[1];
	vec3 t2 = v[4];
	vec3 fid = vec3(base, 0.0);
	bool found = false;
	for (int cy = 0; cy < 2 && !found; cy++) {
		for (int cx = 0; cx < 2 && !found; cx++) {
			vec3 a = v[cy * 3 + cx];
			vec3 b = v[cy * 3 + cx + 1];
			vec3 c = v[(cy + 1) * 3 + cx];
			vec3 d = v[(cy + 1) * 3 + cx + 1];
			vec2 cid = base + vec2(float(cx), float(cy));
			bool even = mod(cid.x + cid.y, 2.0) < 0.5;
			vec3 p0 = a;
			vec3 p1 = b;
			vec3 p2 = even ? d : c;
			vec3 q0 = even ? a : b;
			vec3 q1 = d;
			vec3 q2 = c;
			if (in_tri(wpos, p0.xy, p1.xy, p2.xy)) {
				t0 = p0; t1 = p1; t2 = p2; fid = vec3(cid, 0.0); found = true;
			} else if (in_tri(wpos, q0.xy, q1.xy, q2.xy)) {
				t0 = q0; t1 = q1; t2 = q2; fid = vec3(cid, 1.0); found = true;
			}
		}
	}
	vec2 cen = (t0.xy + t1.xy + t2.xy) / 3.0;
	float fh = hash1(fid.xy * 1.37 + fid.z * 5.71);

	// the slope, against the light
	vec3 e1 = vec3(t1.xy - t0.xy, (t1.z - t0.z) * relief * cell);
	vec3 e2 = vec3(t2.xy - t0.xy, (t2.z - t0.z) * relief * cell);
	vec3 n = normalize(cross(e1, e2));
	n *= sign(n.z);
	vec3 L = normalize(vec3(cos(light_angle), sin(light_angle), light_height));
	float flat_l = L.z;
	float lit = dot(n, L) - flat_l;   // 0 for a flat facet, + facing the light, - turned away

	vec2 lo = bounds.xy;
	vec2 hi = bounds.xy + bounds.zw;
	bool in_world = all(greaterThanEqual(wpos, lo)) && all(lessThanEqual(wpos, hi));
	bool cen_in = all(greaterThanEqual(cen, lo)) && all(lessThanEqual(cen, hi));

	vec3 col;
	if (!in_world && !cen_in) {
		// beyond the edge: the island's stone rim to the south, then the sky
		if (cen.y > hi.y && cen.y < hi.y + cliff && cen.x > lo.x - cell && cen.x < hi.x + cell) {
			col = RAMP(stone, stone_n, clamp(0.5 + lit * contrast + (fh - 0.5) * grain, 0.0, 0.999));
		} else {
			col = sky_at(wpos);
		}
		COLOR = vec4(col, 1.0);
	} else {
		vec4 m = texture(mask, (cen - mask_rect.xy) / mask_rect.zw);
		float s = 0.5 + lit * contrast + (fh - 0.5) * grain;
		if (m.g > 0.5) {
			// water: the sky, in bands across the pond, far side warm; a slope only just shows
			float t = m.b + band_wobble * sin(now * 0.21 + cen.x * 0.006 + cen.y * 0.002) + (fh - 0.5) * 0.04;
			col = RAMP(water, water_n, clamp(t, 0.0, 0.999));
			col *= 1.0 + lit * water_relief * contrast;
			// the facets along the waterline sit a shade deeper, so the bright far bands never melt into the sand
			col *= 1.0 - lip_dark * step(m.g, lip_cut);
			float gh = hash1(fid.xy * 2.11 + fid.z * 3.3 + 41.0);
			if (gh < glint_share) {
				float ph = fract(now / glint_period + hash1(fid.xy + fid.z + 7.7));
				float gl = smoothstep(0.0, 0.025, ph) * (1.0 - smoothstep(0.025, 0.08, ph));
				col = mix(col, vec3(1.0), gl * glint_alpha);
			}
		} else if (m.g > shore_cut) {
			col = RAMP(shore, shore_n, clamp(0.5 + (s - 0.5) * 0.7, 0.0, 0.999));
		} else if (m.r > path_cut) {
			col = RAMP(sand, sand_n, clamp(0.5 + (s - 0.5) * 0.8, 0.0, 0.999));
		} else {
			col = RAMP(grass, grass_n, clamp(s, 0.0, 0.999));
		}
		// each region's own soft tint, by the facet's centroid (feathered, so a region fades in facet by facet)
		for (int i = 0; i < 12; i++) {
			if (i >= region_n) { break; }
			vec4 r = regions[i];
			vec2 dlo = cen - r.xy;
			vec2 dhi = r.xy + r.zw - cen;
			float inside = min(min(dlo.x, dlo.y), min(dhi.x, dhi.y));
			if (inside > 0.0) {
				float w = clamp(inside / region_feather, 0.0, 1.0);
				col = mix(col, region_tints[i].rgb, region_tints[i].a * w);
			}
		}
		// footsteps: the facet underfoot flashes and settles; a faint ring runs out over the facets round it
		float k = 0.0;
		for (int i = 0; i < 12; i++) {
			vec4 p = pulses[i];
			float age = now - p.z;
			if (age < 0.0 || age > step_life) { continue; }
			float fade = 1.0 - age / step_life;
			if (in_tri(p.xy, t0.xy, t1.xy, t2.xy)) {
				k = max(k, exp(-age * 2.2));
			}
			float d = distance(cen, p.xy);
			float ring = exp(-pow((d - age * ring_speed) / (cell * 0.6), 2.0)) * fade * fade * 0.35;
			k = max(k, ring);
		}
		col = mix(col, step_color.rgb, clamp(k, 0.0, 1.0) * step_amount);
		COLOR = vec4(col, 1.0);
	}
}
