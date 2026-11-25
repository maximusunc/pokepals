shader_type canvas_item;
//
// Ohmstead's ground: a glowing grid on the dark, one shader over one quad (scripts/presentation/grid_ground.gd).
// No textures, no render target, no screen read: every fragment is a handful of arithmetic and one short loop.
//
//   * thin lines every `cell` world units, bright ones every `major` cells, a soft halo along the bright ones;
//   * slow packets of light travelling along the bright lines (the worlds being kept alive);
//   * PULSES: where someone stepped, a ring runs outward along the lines and the cell under the foot lights;
//   * SECTORS: rectangles with their own power level (0 dead .. 1 live). A dead one shows only faint, cold lines;
//   * past the world's bounds the lines fade into the dark, so the grid runs off into nothing.
//
// Everything is in world units (the node sits at the origin, unscaled).

uniform vec4 void_color : source_color = vec4(0.02, 0.012, 0.05, 1.0);
uniform vec4 line_color : source_color = vec4(0.37, 0.95, 1.0, 1.0);
uniform vec4 dead_color : source_color = vec4(0.24, 0.18, 0.43, 1.0);
uniform vec4 step_color : source_color = vec4(1.0, 0.31, 0.85, 1.0);
uniform vec4 paw_color : source_color = vec4(1.0, 0.71, 0.28, 1.0);
uniform float cell = 40.0;
uniform float major = 4.0;
uniform float minor_alpha = 0.20;
uniform float major_alpha = 0.78;
uniform float halo = 0.22;
uniform vec4 bounds = vec4(-1600.0, -1200.0, 3200.0, 2400.0);
uniform float fade = 220.0;
uniform float now = 0.0;
uniform float pulse_speed = 70.0;
uniform float pulse_life = 2.4;
// x, y, start time, kind (0 a person, 1 a companion)
uniform vec4 pulses[12];
// x, y, w, h of each sector; power 0..1 in sector_power
uniform vec4 sectors[4];
uniform float sector_power[4];

varying vec2 wpos;

void vertex() {
	wpos = VERTEX;
}

float hash1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// distance (world units) to the nearest line of a grid with the given spacing, per axis
vec2 line_dist(vec2 p, float spacing) {
	return abs(fract(p / spacing + 0.5) - 0.5) * spacing;
}

void fragment() {
	vec2 dm = line_dist(wpos, cell);
	float big = cell * major;
	vec2 dM = line_dist(wpos, big);
	float minor_line = step(min(dm.x, dm.y), 0.5);
	float major_line = step(min(dM.x, dM.y), 0.75);
	float near_major = exp(-min(dM.x, dM.y) * 0.45);

	// packets of light running along the bright lines: each line has its own phase and direction
	float row = floor(wpos.y / big + 0.5);
	float col = floor(wpos.x / big + 0.5);
	float along_h = fract(wpos.x / 520.0 + (hash1(row) - 0.5) * 2.0 * now * 0.11 + hash1(row + 7.0));
	float along_v = fract(wpos.y / 520.0 + (hash1(col + 31.0) - 0.5) * 2.0 * now * 0.11 + hash1(col + 3.0));
	float packet = 0.0;
	if (dM.y <= 0.75) { packet = max(packet, smoothstep(0.94, 1.0, along_h)); }
	if (dM.x <= 0.75) { packet = max(packet, smoothstep(0.94, 1.0, along_v)); }

	// how live this ground is: fades past the bounds, and drops inside a sector with no power
	vec2 lo = bounds.xy;
	vec2 hi = bounds.xy + bounds.zw;
	vec2 out_d = max(max(lo - wpos, wpos - hi), vec2(0.0));
	float outside = length(out_d);
	float live = exp(-outside / fade);
	float power = 1.0;
	for (int i = 0; i < 4; i++) {
		vec4 s = sectors[i];
		if (s.z > 0.0 && wpos.x > s.x && wpos.x < s.x + s.z && wpos.y > s.y && wpos.y < s.y + s.w) {
			power = min(power, sector_power[i]);
		}
	}

	float breathe = 0.9 + 0.1 * sin(now * 0.7 + wpos.x * 0.003 + wpos.y * 0.004);
	float a = max(minor_line * minor_alpha, major_line * major_alpha) * breathe;
	vec3 rgb = line_color.rgb;
	float glow = near_major * halo * breathe;
	a = max(a, glow);
	a += packet * 0.55;
	rgb = mix(rgb, vec3(1.0), packet * 0.7);
	// no power: the lines go faint and cold, and nothing travels along them
	vec3 dead_rgb = dead_color.rgb;
	float dead_a = max(minor_line * 0.16, major_line * 0.34);
	rgb = mix(dead_rgb, rgb, power);
	a = mix(dead_a, a, power);

	// footsteps
	float on_line = max(minor_line, major_line);
	for (int i = 0; i < 12; i++) {
		vec4 p = pulses[i];
		float age = now - p.z;
		if (age < 0.0 || age > pulse_life) { continue; }
		float t = age / pulse_life;
		float d = distance(wpos, p.xy);
		float ring = exp(-pow((d - age * pulse_speed) / 5.0, 2.0)) * (1.0 - t) * (1.0 - t);
		// the cell under the foot: its outline flares for a moment
		vec2 c0 = (floor(p.xy / cell) + 0.5) * cell;
		vec2 dc = abs(wpos - c0);
		float in_cell = step(max(dc.x, dc.y), cell * 0.5 + 0.5) * exp(-age * 2.4);
		vec3 pc = mix(step_color.rgb, paw_color.rgb, p.w);
		float k = ring * (on_line * 0.95 + 0.07) + in_cell * (on_line * 0.9 + 0.05);
		rgb = mix(rgb, pc, clamp(k, 0.0, 1.0));
		a = max(a, k);
	}

	a *= live;
	// the edge of the world: one bright line, then the dark
	float edge = step(abs(max(max(lo.x - wpos.x, wpos.x - hi.x), max(lo.y - wpos.y, wpos.y - hi.y))), 1.0);
	a = max(a, edge * 0.9);
	rgb = mix(rgb, line_color.rgb, edge);
	a = clamp(a, 0.0, 1.0);
	COLOR = vec4(mix(void_color.rgb, rgb, a), 1.0);
}
