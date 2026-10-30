shader_type canvas_item;
// The pixel-art GROUND (see GroundLayer + tools/pixelart/ground.py). Drawn as one rect over the
// world's bounds; every fragment works out which kind of ground it is and shades it from a
// seamless pixel tile, one texel per world unit, so the floor is as crisp as the sprites on it.
//
//  * CLUMPING: the tiles hold only fine grain; broad light/dark patches come from world-space noise
//    here, so the 128-unit tile never shows as a repeating grid.
//  * TERRAIN: grass by default; lush clover, flower meadow and bare dirt show through where slow
//    noise fields cross their thresholds, so the ground has areas instead of a uniform wash.
//  * EDGES: every border (between kinds, at a path, at a shore) is pushed through a 4x4 Bayer
//    dither plus a little fine noise, so it breaks into ragged pixel steps, never a smooth line.
//  * MASK (built once per world on the CPU, low-res, linearly filtered):
//      R = paths   (1 on the centre line, fading out)  -> packed earth, with a rim of worn grass
//      G = shores  (1 at the waterline, fading inland) -> a band of sand around ponds and rivers
//      B = shade   (1 under a canopy, fading out)       -> the ground steps darker, dithered
//  * The terrain tiles hold SHADE ROLES (R = 0..3), not colours, and `ramps` colours them, so a
//    world recolours its ground from its art block without new textures.

uniform sampler2D terrain : filter_nearest, repeat_enable;
uniform sampler2D mask : filter_linear, repeat_disable;  // never wrap: edge paths mustn't bleed across
uniform vec4 bounds = vec4(-1000.0, -1000.0, 2000.0, 2000.0);  // x, y, w, h (world units)
uniform float tile = 128.0;
// 7 ramp slots x 4 shades, darkest first: grass, lush, meadow, dirt, sand, path, worn.
uniform vec3 ramps[28];
uniform vec3 accents[4];          // a meadow's flower colours
uniform vec2 lush = vec2(0.0045, 0.60);    // noise scale, threshold (higher = rarer)
uniform vec2 meadow = vec2(0.0060, 0.64);
uniform vec2 dirt = vec2(0.0090, 0.76);
uniform vec2 clump = vec2(0.03, 0.011);   // fine and broad scales of the light/dark clumping
uniform float seed = 0.0;
uniform float edge = 0.035;       // how wide the dithered band at a terrain border is

varying vec2 world;

void vertex() {
	world = VERTEX;  // the node sits at the world origin, so local = world
}

// Dave Hoskins' hash: stable on mobile GPUs (no big sin() arguments).
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v / 0.875;
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	vec2 p = floor(world);            // snap to the texel grid: crisp, never smeared
	float d = bayer4(p) - 0.5;        // -0.5 .. 0.5
	int slot = 0;                     // which ramp
	int kind = 0;                     // which terrain tile

	// fine noise that frays every border, plus a narrow dither band where it crosses over
	float jitter = (vnoise(p * 0.11 + seed + 5.0) - 0.5) * 0.34;
	float fray = d * edge + jitter * 0.12;
	if (fbm(p * lush.x + seed) + fray > lush.y) { slot = 1; kind = 1; }
	if (fbm(p * meadow.x + seed + 31.7) + fray > meadow.y) { slot = 2; kind = 2; }
	if (fbm(p * dirt.x + seed + 77.3) + fray > dirt.y) { slot = 3; kind = 3; }

	vec4 m = texture(mask, (world - bounds.xy) / bounds.zw);

	// a sandy band hugging the water
	if (m.g + jitter * 0.6 + d * 0.2 > 0.5) { slot = 4; kind = 4; }
	// paths: packed earth down the middle, a rim of trampled grass either side
	float pv = m.r + jitter + d * 0.18;
	if (pv > 0.5) {
		slot = 5; kind = 3;
	} else if (pv > 0.34 && slot != 4) {
		slot = 6; kind = 0;
	}

	ivec2 tc = ivec2(mod(p, vec2(tile))) + ivec2(kind * int(tile), 0);
	vec4 t = texelFetch(terrain, tc, 0);
	int shade = int(t.r * 3.0 + 0.5);

	// broad light/dark CLUMPING from world-space noise (the tiles carry only fine grain, so this
	// never repeats), dithered at its edges like everything else
	float cl = fbm(p * clump.x + seed + 11.0) * 0.65 + fbm(p * clump.y + seed + 23.0) * 0.35 + d * 0.07 + jitter * 0.1;
	if (cl > 0.62) { shade = min(shade + 1, 3); }
	else if (cl < 0.38) { shade = max(shade - 1, 0); }

	// canopy shade: one shade darker inside, darker still at the heart, each edge dithered
	float sv = m.b + d * 0.32;
	if (sv > 0.42) { shade = max(shade - 1, 0); }
	vec3 c = ramps[slot * 4 + shade];
	if (sv > 0.72) { c *= 0.86; }

	if (kind == 2 && t.g > 0.5) {
		c = accents[int(hash(floor(p / 3.0) + seed) * 4.0) % 4];
	}
	COLOR = vec4(c, 1.0);
}
