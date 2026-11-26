shader_type canvas_item;
// GLYPHFALL's look: the finished picture of the world, redrawn as monospace characters. One quad over the
// view (GlyphPage, a layer that follows the camera, under the vignette and the HUD) reads the screen behind
// it and, for each character cell, writes one glyph from the atlas in the colour that was there, on a dark
// page. The cells are pinned to the WORLD, not the screen: a tuft of grass keeps its character as you walk,
// and the text scrolls like a page. Which glyph: the colour's family picks the atlas row (green: grass or
// leaves, blue: water, brown: earth or wood, grey: stone, pink: bloom), its brightness picks a pair in the
// row, and a hash of the cell picks one of the pair. Visitors are written smaller (half-size cells, dense
// letters, a tinted cell behind) so a person stays a person. One screen read (with its mip chain), two or three taps a pixel, no loops
// beyond the handful of visitors. Tuned by the world's `atmosphere.glyphs` block.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_grid = vec2(8.0, 9.0);      // columns, rows of the atlas
uniform vec2 cell = vec2(8.0, 12.0);           // one character, in world px
uniform float px_scale = 2.0;                  // physical pixels per world px (camera zoom x window stretch)
uniform float lod = 1.0;                       // atlas mip for a full-size cell (GlyphPage works it out)
uniform vec3 page = vec3(0.035, 0.04, 0.06);   // the dark page
uniform float bg_tint = 0.10;                  // how much of what is under a cell tints the page there
uniform float actor_bg = 0.42;                 // ...and under a visitor's cells
uniform float ink_floor = 0.5;                 // the dimmest ink (as a fraction of full brightness)
uniform float lum_lo = 0.10;                   // brightness mapped to the first pair of a row...
uniform float lum_hi = 0.72;                   // ...and to the last
uniform float blank_under = 0.03;              // darker than this: no character at all
uniform float sway = 0.025;                    // how far grass and leaves lean in the wind (cell widths)
uniform float water_rate = 0.06;               // how fast the ripple bands drift across water (radians a second)
uniform float wood_under = 0.40;               // a brown darker than this is wood; lighter is earth
uniform float grass_gap = 0.3;                 // the share of grass cells left empty
uniform float mark_under = 0.8;                // a cell whose alpha averages under this holds a visitor
uniform sampler2D text_tex : filter_nearest, repeat_disable;   // the sentences: one row a line, r = atlas place
uniform vec2 text_size = vec2(64.0, 1.0);
uniform float text_on = 0.0;
uniform int actor_count = 0;
uniform vec4 actors[16];                       // world centre (xy), half size (zw) of each visitor's box
uniform vec2 wrong_cell = vec2(-99999.0);      // the cell holding the wrong glyph (cell coordinates)
uniform float wrong_index = 64.0;              // its place in the atlas
uniform vec3 wrong_color = vec3(1.0, 0.86, 0.42);   // the colour it shines
uniform float wrong_glow = 0.0;                // 0..1: it catches the light a little once you are close
uniform float typed = 1.0;                     // 0..1: how much of the page has been written (the arrival)
uniform float time = 0.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// What is under a cell: its whole area averaged, read from the picture's mip chain at the level where one
// texel is about half a cell (so the smooth filter spans the cell). Four point taps were tried first: each
// landed on a pixel or two of litter or dither, so the answer changed with every sub-pixel step of the camera
// and characters flickered as you walked.
vec4 under(vec2 centre, vec2 size, vec2 w, vec2 suv, vec2 to_uv) {
	vec2 uv = clamp(suv + (centre - w) * to_uv, vec2(0.001), vec2(0.999));
	float level = max(0.0, log2(size.x * px_scale * 0.5));
	return textureLod(screen_tex, uv, level);
}

void fragment() {
	vec2 w = world_pos;
	vec2 to_uv = px_scale * SCREEN_PIXEL_SIZE;
	vec2 cs = cell;
	vec2 ci = floor(w / cs);
	vec2 cc = (ci + 0.5) * cs;
	// Near a visitor the cell splits in four, and a quarter that holds the visitor's own pixels (marked in the
	// picture's alpha by glyph_actor.gdshader) is written as fine print. The rest stays the world's.
	bool boxed = false;
	for (int i = 0; i < actor_count; i++) {
		vec2 d = abs(cc - actors[i].xy);
		if (d.x < actors[i].z && d.y < actors[i].w) {
			boxed = true;
		}
	}
	float person = 0.0;
	vec4 u;
	if (boxed) {
		vec2 fs = cell * 0.5;
		vec2 fi = floor(w / fs);
		vec2 fc = (fi + 0.5) * fs;
		u = under(fc, fs, w, SCREEN_UV, to_uv);
		if (u.a < mark_under) {
			person = 1.0;
			cs = fs;
			ci = fi;
			cc = fc;
		}
	}
	if (person < 0.5) {
		u = under(cc, cs, w, SCREEN_UV, to_uv);
	}
	vec3 s = u.rgb;
	float is_wrong = (person < 0.5 && ci == wrong_cell) ? 1.0 : 0.0;
	vec2 local = (w - ci * cs) / cs;

	float mx = max(s.r, max(s.g, s.b));
	float mn = min(s.r, min(s.g, s.b));
	float lum = dot(s, vec3(0.299, 0.587, 0.114));
	float sat = mx > 0.0001 ? (mx - mn) / mx : 0.0;
	float hue = 0.0;   // 0..6
	float dlt = mx - mn;
	if (dlt > 0.0001) {
		if (mx == s.r) {
			hue = mod((s.g - s.b) / dlt, 6.0);
		} else if (mx == s.g) {
			hue = (s.b - s.r) / dlt + 2.0;
		} else {
			hue = (s.r - s.g) / dlt + 4.0;
		}
	}
	float row;
	if (person > 0.5) {
		row = 7.0;
	} else if (sat < 0.16) {
		row = 5.0;                                   // grey: stone
	} else if (hue < 0.42 || hue >= 5.75) {
		row = lum < wood_under ? 4.0 : 6.0;          // red: dark is wood, bright is a bloom
	} else if (hue < 0.95) {
		row = lum < wood_under ? 4.0 : 3.0;          // orange-brown: wood, or earth
	} else if (hue < 1.95) {
		row = 0.0;                                   // yellow-green: grass
	} else if (hue < 2.85) {
		row = 1.0;                                   // green to teal: leaves
	} else if (hue < 4.4) {
		row = 2.0;                                   // blue: water
	} else {
		row = 6.0;                                   // violet to pink: bloom
	}
	float level = floor(clamp((lum - lum_lo) / (lum_hi - lum_lo), 0.0, 0.999) * 4.0);
	float h = hash(ci);
	float pick = h;
	if (row == 2.0) {
		// water ripples: slow bands of the second character drift across it together (cells flipping one by
		// one at random made the whole pond twitch)
		pick = 0.5 + 0.5 * sin(cc.x * 0.045 + cc.y * 0.11 - time * water_rate + h * 1.4);
	}
	float idx = row * atlas_grid.x + level * 2.0 + step(0.5, pick);
	if (person > 0.5) {
		// a visitor's letters do not follow brightness: each small cell keeps one of the four dense letters,
		// so a figure that breathes or bobs changes colour under its letters and the letters hold still
		idx = row * atlas_grid.x + 4.0 + floor(h * 3.999);
	}
	float gap = 0.0;
	if (row == 0.0) {
		gap = step(hash(ci + 17.3), grass_gap);                  // the grass leaves room on the page
	}
	if (row == 3.0 && text_on > 0.5) {
		// earth is WRITTEN: every row of the page is one of the writer's sentences, so a path reads
		float ly = mod(ci.y, text_size.y);
		float lx = mod(ci.x + floor(hash(vec2(ly, 3.7)) * text_size.x), text_size.x);
		idx = floor(texture(text_tex, (vec2(lx, ly) + 0.5) / text_size).r * 255.0 + 0.5);
	}
	if (is_wrong > 0.5) {
		idx = wrong_index;
	}
	// grass and leaves lean with the wind, from the foot of the character
	if (row < 1.5 && is_wrong < 0.5) {
		local.x += sin(time * 1.3 + w.x * 0.021 + w.y * 0.013) * sway * (1.0 - local.y);
	}
	vec2 g = vec2(mod(idx, atlas_grid.x), floor(idx / atlas_grid.x));
	vec2 inner = clamp(local, vec2(0.02), vec2(0.98));
	float a = textureLod(atlas, (g + inner) / atlas_grid, lod - person).a;
	a *= step(blank_under, lum) * (1.0 - gap * (1.0 - is_wrong));

	vec3 ink = s / max(mx, 0.001) * mix(ink_floor, 1.0, smoothstep(lum_lo, lum_hi, lum));
	ink = mix(ink, wrong_color * (0.8 + 0.2 * sin(time * 3.0)), is_wrong * wrong_glow);
	vec3 bg = page + s * mix(bg_tint, actor_bg, person) + wrong_color * 0.10 * is_wrong * wrong_glow;

	// the arrival: the page is written in from the top, a line at a time, behind a cursor
	float rows_total = 1.0 / (cell.y * to_uv.y);
	float line = floor(SCREEN_UV.y * rows_total);
	float at = typed * (rows_total + 1.0);
	float written = step(line + SCREEN_UV.x, at);
	float cursor = step(abs(line + SCREEN_UV.x - at), 0.012) * step(typed, 0.999);
	vec3 col = mix(page, mix(bg, ink, a), written);
	col = mix(col, vec3(0.85, 0.9, 0.8), cursor);
	COLOR = vec4(col, 1.0);
}
