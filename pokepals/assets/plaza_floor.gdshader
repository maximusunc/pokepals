shader_type canvas_item;
//
// Lingerlong's ground: a marble plaza floating in a pastel sky, one shader over one quad
// (scripts/presentation/plaza_ground.gd). No render target and no screen read: three small tileable
// textures and a handful of arithmetic per fragment. By world position it draws
//
//   * the FLOORS (up to 8 rectangles): a polished marble checkerboard, each tile its own slab of veining
//     (ll_marble.png), thin grout, a slow sheen and a faint picture of the sky in the polish; a soft darker lip
//     where a floor meets the sky, and under every edge that faces south, the slab's THICKNESS (a lit rim, then
//     a shaded face), so the plaza reads as a slab in the air;
//   * the POOL: still, shallow, aqua, caustics drifting slowly (ll_caustics.png), glints, a marble coping down
//     its sides, rings where someone wades, and toward its north edge it loses the coping and fades into the
//     sky's horizon gold;
//   * everywhere else, the SKY: a pastel gradient anchored to the SCREEN (so it is infinitely far and the plaza
//     seems to float past it as you walk), a horizon glow beyond the pool, a low pale sun, and two layers of
//     slow cloud (ll_clouds.png) drifting below with a little parallax.
//
// `evening` (0..1) eases the sky to the evening colours, brings out a few stars, and cools the floor.
// Everything is in world units (the node sits at the origin, unscaled). A missing texture is simply skipped.

uniform vec4 floors[8];                 // x0, y0, x1, y1
uniform vec4 floor_b[8] : source_color; // each floor's second tile colour
uniform int floor_count = 0;
uniform vec4 pool = vec4(0.0);          // x0, y0, x1, y1 (all zero: no pool)
uniform float tile = 40.0;
uniform vec4 tile_a : source_color = vec4(0.984, 0.957, 0.925, 1.0);
uniform vec4 vein : source_color = vec4(0.902, 0.847, 0.812, 1.0);
uniform vec4 grout : source_color = vec4(0.890, 0.812, 0.824, 1.0);
uniform vec4 rim_lit : source_color = vec4(1.0, 0.973, 0.941, 1.0);
uniform vec4 rim_shade : source_color = vec4(0.725, 0.655, 0.839, 1.0);
uniform float thickness = 14.0;

uniform vec4 sky[5] : source_color;       // zenith (top of the screen) .. horizon (bottom)
uniform vec4 evening_sky[5] : source_color;
uniform vec4 sun_color : source_color = vec4(1.0, 0.965, 0.863, 1.0);
uniform vec2 sun_at = vec2(-240.0, -1240.0);
uniform float sun_radius = 46.0;
uniform vec4 water_deep : source_color = vec4(0.498, 0.839, 0.847, 1.0);
uniform vec4 water_shallow : source_color = vec4(0.663, 0.902, 0.937, 1.0);
uniform vec4 cloud_color : source_color = vec4(1.0, 0.957, 0.918, 1.0);
uniform float horizon_fade = 220.0;

uniform sampler2D marble_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D caustics_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_tex : filter_linear_mipmap, repeat_enable;
uniform float has_marble = 0.0;
uniform float has_caustics = 0.0;
uniform float has_clouds = 0.0;

uniform float now = 0.0;
uniform float evening = 0.0;
uniform vec2 view_center = vec2(0.0);
// x, y, start time, strength (0: an empty slot)
uniform vec4 ripples[10];
uniform float ripple_speed = 26.0;
uniform float ripple_life = 2.2;

varying vec2 wpos;

void vertex() {
	wpos = VERTEX;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

bool in_rect(vec2 p, vec4 r) {
	return p.x >= r.x && p.x <= r.z && p.y >= r.y && p.y <= r.w;
}

int floor_at(vec2 p) {
	for (int i = 0; i < 8; i++) {
		if (i >= floor_count) {
			break;
		}
		if (in_rect(p, floors[i])) {
			return i;
		}
	}
	return -1;
}

bool on_ground(vec2 p) {
	return floor_at(p) >= 0 || in_rect(p, pool);
}

// five stops down the screen: 0, .3, .55, .78, 1
vec3 gradient(float g, vec4 c0, vec4 c1, vec4 c2, vec4 c3, vec4 c4) {
	vec3 c = mix(c0.rgb, c1.rgb, smoothstep(0.0, 0.3, g));
	c = mix(c, c2.rgb, smoothstep(0.3, 0.55, g));
	c = mix(c, c3.rgb, smoothstep(0.55, 0.78, g));
	return mix(c, c4.rgb, smoothstep(0.78, 1.0, g));
}

vec3 horizon_color() {
	return mix(sky[4].rgb, evening_sky[4].rgb, evening);
}

// the plain gradient down the screen (what the polish and the water hold a faint picture of)
vec3 sky_gradient(vec2 suv) {
	float g = clamp(suv.y, 0.0, 1.0);
	vec3 day = gradient(g, sky[0], sky[1], sky[2], sky[3], sky[4]);
	vec3 eve = gradient(g, evening_sky[0], evening_sky[1], evening_sky[2], evening_sky[3], evening_sky[4]);
	return mix(day, eve, evening);
}

// the horizon glow beyond the pool's far edge: how much of it reaches p (0 .. 1), and its colour there
float horizon_amount(vec2 p) {
	if (pool.z <= pool.x) {
		return 0.0;
	}
	// beyond the far edge it thins out slowly; level with the pool's top, out to either side, it fades quicker,
	// so the horizon runs on past the pool's sides instead of stopping at its corners
	float beyond = max(0.0, pool.y - p.y);
	float before = max(0.0, p.y - pool.y);
	float side = max(0.0, max(pool.x - p.x, p.x - pool.z));
	return exp(-beyond / (horizon_fade * 1.8)) * exp(-before / (horizon_fade * 0.7)) * exp(-side / 520.0) * 0.92;
}

vec3 horizon_at(vec2 p) {
	float beyond = max(0.0, pool.y - p.y);
	return mix(horizon_color(), mix(sky[3].rgb, evening_sky[3].rgb, evening), smoothstep(0.0, horizon_fade * 2.5, beyond));
}

// where the low pale sun is: far away, so it slides with you most of the way, but always above the horizon
vec2 sun_pos() {
	vec2 sp = sun_at + (view_center - sun_at) * 0.72;
	if (pool.z > pool.x) {
		sp.y = min(sp.y, pool.y - sun_radius * 1.5);
	}
	return sp;
}

vec3 sun_tint() {
	return mix(sun_color.rgb, vec3(1.0, 0.72, 0.62), evening);
}

// the sky behind (and below) the plaza at world point p, seen at screen point suv
vec3 sky_at(vec2 p, vec2 suv) {
	float g = clamp(suv.y, 0.0, 1.0);
	vec3 c = sky_gradient(suv);
	// beyond the pool's far edge the sky warms toward the horizon, so water and sky meet in the same gold
	float hz = horizon_amount(p);
	c = mix(c, horizon_at(p), hz);
	vec2 sp = sun_pos();
	float sd = length(p - sp);
	vec3 sun = sun_tint();
	float sun_k = 1.0 - evening * 0.5;
	c = mix(c, sun, (1.0 - smoothstep(sun_radius - 1.5, sun_radius + 1.5, sd)) * 0.9 * sun_k);
	c += sun * exp(-sd / (sun_radius * 1.6)) * 0.22 * sun_k;
	// clouds drifting below, two layers at two depths (the nearer one slides a little more as you walk)
	if (has_clouds > 0.5) {
		vec2 s = p - view_center;
		float a1 = texture(clouds_tex, (s + view_center * 0.18 + vec2(now * 4.0, 0.0)) / vec2(820.0, 410.0)).a;
		float a2 = texture(clouds_tex, (s + view_center * 0.34 + vec2(now * 7.0 + 300.0, 140.0)) / vec2(560.0, 280.0)).a;
		vec3 cc = mix(cloud_color.rgb, vec3(0.55, 0.48, 0.78), evening * 0.7);
		vec3 under = mix(rim_shade.rgb, vec3(0.30, 0.26, 0.52), evening);
		// (the haze right over the horizon is clear of cloud, so the water runs straight into it)
		float clear = 1.0 - hz;
		c = mix(c, mix(cc, under, 0.28), a1 * 0.34 * clear);
		c = mix(c, cc, a2 * 0.5 * clear);
	}
	// a few stars in the evening, high on the screen
	if (evening > 0.01) {
		vec2 cell = floor(suv * vec2(96.0, 54.0));
		float h = hash2(cell);
		vec2 f = fract(suv * vec2(96.0, 54.0)) - 0.5;
		float star = step(0.965, h) * smoothstep(0.12, 0.0, length(f)) * (0.6 + 0.4 * sin(now * 1.7 + h * 40.0));
		c += vec3(1.0, 0.95, 0.88) * star * evening * (1.0 - smoothstep(0.3, 0.75, g));
	}
	return c;
}

vec3 marble_floor(vec2 p, int fi, vec2 suv) {
	vec2 cell = floor(p / tile);
	bool b_tile = mod(cell.x + cell.y, 2.0) > 0.5;
	vec3 base = b_tile ? floor_b[fi].rgb : tile_a.rgb;
	// each tile is cut from a different part of the slab
	if (has_marble > 0.5) {
		vec2 off = vec2(hash2(cell), hash2(cell + 17.0));
		float m = texture(marble_tex, p / 256.0 + off).r;
		vec3 vc = b_tile ? base * vec3(0.86, 0.84, 0.9) : vein.rgb;
		base = mix(base, vc, m * 0.55);
	}
	// a slab's own soft gloss: lighter toward its upper left (the light), a touch darker at its lower right
	vec2 f = fract(p / tile);
	base *= 1.0 + 0.035 * (0.5 - (f.x + f.y) * 0.5);
	// thin grout between the tiles
	float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * tile;
	base = mix(grout.rgb, base, smoothstep(0.35, 1.1, e));
	// the polish holds a faint picture of the sky, and a slow sheen walks across it
	base = mix(base, sky_gradient(suv), 0.07);
	float s = sin((p.x * 0.6 + p.y * 0.8) / 170.0 - now * 0.22);
	base += vec3(1.0, 0.97, 0.94) * pow(max(s, 0.0), 10.0) * 0.07;
	return base;
}

// near an edge of the ground that faces the sky: x = how near (0 far .. 1 at it), for a soft darker lip;
// y = a bevel (+1 a lit edge facing the light, up and left; -1 a shaded one facing away)
vec2 edge_lip(vec2 p, vec4 r) {
	float d = min(min(p.x - r.x, r.z - p.x), min(p.y - r.y, r.w - p.y));
	if (d > 10.0) {
		return vec2(0.0);
	}
	float near = 10.0;
	float bevel = 0.0;
	for (int k = 0; k < 4; k++) {
		vec2 dir = k == 0 ? vec2(1.0, 0.0) : (k == 1 ? vec2(-1.0, 0.0) : (k == 2 ? vec2(0.0, 1.0) : vec2(0.0, -1.0)));
		for (int j = 1; j <= 5; j++) {
			float dist = float(j) * 2.0;
			if (!on_ground(p + dir * dist)) {
				near = min(near, dist);
				if (j == 1) {
					bevel = (k == 1 || k == 3) ? 1.0 : -1.0;
				}
				break;
			}
		}
	}
	return vec2(1.0 - smoothstep(0.0, 10.0, near), bevel);
}

vec3 water(vec2 p, vec2 suv) {
	// a little deeper in the middle, as shallow as a footbath at the sides
	float mid = 1.0 - abs((p.x - (pool.x + pool.z) * 0.5) / max(1.0, (pool.z - pool.x) * 0.5));
	vec3 c = mix(water_shallow.rgb, water_deep.rgb, 0.35 + 0.45 * mid);
	if (has_caustics > 0.5) {
		float c1 = texture(caustics_tex, p / 230.0 + vec2(now * 0.010, now * 0.004)).r;
		float c2 = texture(caustics_tex, p / 310.0 + vec2(-now * 0.006, now * 0.009) + 0.37).r;
		c += vec3(1.0, 1.0, 0.96) * pow(c1 * c2, 1.4) * 0.34;
	}
	// a stillness that holds the sky
	c = mix(c, sky_gradient(suv), 0.16);
	// glints: a few cells catch the sun, slowly
	vec2 gc = floor(p / 14.0);
	float gh = hash2(gc);
	float gl = step(0.93, gh) * pow(max(0.0, sin(now * (0.6 + gh) + gh * 30.0)), 12.0);
	vec2 gf = fract(p / 14.0) - 0.5;
	c += vec3(1.0) * gl * smoothstep(0.22, 0.0, length(gf * vec2(1.0, 2.2))) * 0.8;
	// rings where someone wades
	for (int i = 0; i < 10; i++) {
		vec4 r = ripples[i];
		if (r.w <= 0.0) {
			continue;
		}
		float age = now - r.z;
		if (age < 0.0 || age > ripple_life) {
			continue;
		}
		float rad = 3.0 + age * ripple_speed;
		vec2 q = (p - r.xy) * vec2(1.0, 1.7);   // a ring on the water, seen at a slant
		float d = length(q) - rad;
		float fade = (1.0 - age / ripple_life) * r.w;
		c += vec3(1.0) * exp(-d * d / 1.6) * 0.32 * fade;
		c -= vec3(0.06, 0.04, 0.0) * exp(-(d + 2.5) * (d + 2.5) / 2.0) * fade;
	}
	// a marble coping down the sides, which runs out toward the far edge
	float side = min(p.x - pool.x, pool.z - p.x);
	float keep = smoothstep(pool.y + 40.0, pool.y + horizon_fade * 1.6, p.y);
	float cope = (1.0 - smoothstep(6.0, 8.0, side)) * keep;
	vec3 coping = mix(tile_a.rgb, rim_shade.rgb, smoothstep(5.0, 8.0, side) * 0.6);
	c = mix(c, coping, cope);
	float far = 1.0 - smoothstep(0.0, horizon_fade, p.y - pool.y);
	// the sun's path on the water, glittering in small soft sparks, strongest toward the horizon
	vec2 sp = sun_pos();
	float path = exp(-abs(p.x - sp.x) / (sun_radius * 0.8)) * exp(-(p.y - pool.y) / 360.0);
	if (path > 0.01) {
		vec2 pc = floor(p / vec2(9.0, 4.0));
		vec2 pf = (fract(p / vec2(9.0, 4.0)) - 0.5) * vec2(1.0, 0.6);
		float tw = pow(max(0.0, sin(now * (1.2 + hash2(pc) * 2.0) + hash2(pc + 3.0) * 30.0)), 6.0);
		float spark = tw * step(0.5, hash2(pc + 9.0)) * smoothstep(0.3, 0.0, length(pf));
		c += sun_tint() * path * (0.12 + 0.7 * spark) * (1.0 - evening * 0.5);
	}
	// and the water itself thins into the horizon at the far edge: no rim, just the sky's gold
	if (far > 0.0) {
		vec2 edge = vec2(p.x, pool.y - 0.5);
		vec3 meet = mix(sky_gradient(suv), horizon_at(edge), horizon_amount(edge));
		meet += sun_tint() * exp(-length(edge - sp) / (sun_radius * 1.6)) * 0.22 * (1.0 - evening * 0.5);
		c = mix(c, meet, far * far * (3.0 - 2.0 * far));
	}
	return c;
}

// a soft-edged box, 1 inside r and fading to 0 over `w` either side of its edges
float soft_box(vec2 q, vec4 r, float w) {
	return smoothstep(r.x - w, r.x + w, q.x) * (1.0 - smoothstep(r.z - w, r.z + w, q.x))
		* smoothstep(r.y - w, r.y + w, q.y) * (1.0 - smoothstep(r.w - w, r.w + w, q.y));
}

// how much of the plaza's shadow falls at q (the plaza itself, blurred)
float slab_shadow(vec2 q) {
	float sh = soft_box(q, pool, 26.0);
	for (int i = 0; i < 8; i++) {
		if (i >= floor_count) {
			break;
		}
		sh = max(sh, soft_box(q, floors[i], 26.0));
	}
	return sh;
}

void fragment() {
	vec2 p = wpos;
	int fi = floor_at(p);
	vec3 c;
	if (fi >= 0) {
		c = marble_floor(p, fi, SCREEN_UV);
		vec2 lip = edge_lip(p, floors[fi]);
		c = mix(c, c * rim_shade.rgb, lip.x * 0.22);
		c = mix(c, lip.y > 0.0 ? rim_lit.rgb : c * 0.9, abs(lip.y) * 0.7);
		c = mix(c, c * vec3(0.64, 0.62, 0.86), evening * 0.55);
	} else if (in_rect(p, pool)) {
		c = water(p, SCREEN_UV);
		c = mix(c, c * vec3(0.62, 0.62, 0.9), evening * 0.5);
	} else {
		c = sky_at(p, SCREEN_UV);
		// under a south-facing edge, the slab's thickness: a lit rim, then the shaded face, then a soft shadow
		for (int i = 0; i < 8; i++) {
			if (i >= floor_count) {
				break;
			}
			vec4 r = floors[i];
			float k = p.y - r.w;
			if (p.x >= r.x && p.x <= r.z && k > 0.0 && k <= thickness + 10.0) {
				if (k <= thickness) {
					vec3 face = k < 2.0 ? rim_lit.rgb : mix(mix(tile_a.rgb, rim_shade.rgb, 0.55), rim_shade.rgb * 0.82, (k - 2.0) / thickness);
					if (has_marble > 0.5) {
						face *= 1.0 - texture(marble_tex, vec2(p.x / 256.0, k / 64.0)).r * 0.08;
					}
					face = mix(face, face * vec3(0.6, 0.58, 0.85), evening * 0.55);
					// rounded ends, so the slab's corners don't read as cut paper
					float end = min(p.x - r.x, r.z - p.x);
					c = mix(c, face, smoothstep(0.0, 1.5, end));
				} else {
					c *= 1.0 - 0.10 * (1.0 - (k - thickness) / 10.0);
				}
				break;
			}
		}
		// the slab's soft shadow, far below on the clouds, down and to the right of it
		c = mix(c, c * rim_shade.rgb, slab_shadow(p - vec2(22.0, 40.0)) * 0.16);
	}
	COLOR = vec4(c, 1.0);
}
