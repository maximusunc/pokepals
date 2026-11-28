shader_type canvas_item;
// GLYPHFALL's look: the world written as monospace characters. One quad over the view (GlyphPage, drawn in the
// world between the ground and everything that stands on it) writes the page a character cell at a time. The
// cells are pinned to the WORLD, so the text scrolls like a page as you walk.
//
// What a cell shows comes from the world's own data, never from a picture, so the landscape cannot flicker:
//   * a THING (a tree, a bench, the portal) is a small picture made of characters, laid into `cell_tex` once
//     by GlyphMap: its character, its ink and the tint behind it;
//   * otherwise the GROUND there (also in `cell_tex`): grass is sparse dim tufts, water is bands of waves on
//     blue, a shore is dots on sand, and a path is one of the writer's sentences, a line to each row.
// The page is opaque and covers the pixel world's ground and props. Visitors are drawn after it, on top, by
// their own shader (glyph_actor.gdshader). Three small lookups a pixel; nothing is read back from the screen.

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D cell_tex : filter_nearest, repeat_disable;     // r: a thing's character, g: ground, b: its ink, a: its tint
uniform sampler2D palette_tex : filter_nearest, repeat_disable;  // 256 x 1: the things' colours
uniform sampler2D text_tex : filter_nearest, repeat_disable;     // the sentences: one row a line, r = atlas place
uniform vec2 atlas_grid = vec2(16.0, 8.0);     // columns, rows of the atlas
uniform vec2 cell = vec2(8.0, 12.0);           // one character, in world px
uniform vec2 map_origin = vec2(0.0);           // the cell coordinates of cell_tex's first texel
uniform vec2 map_size = vec2(1.0);             // cell_tex's size, in cells
uniform vec2 text_size = vec2(64.0, 1.0);
uniform float text_on = 0.0;
uniform float px_scale = 2.0;                  // physical pixels per world px (camera zoom x window stretch)
uniform float lod = 1.0;                       // atlas mip for a full-size cell (GlyphPage works it out)
uniform vec3 page = vec3(0.035, 0.04, 0.06);   // the dark page

uniform float tufts[6];                        // atlas places of the grass's characters
uniform vec3 grass_ink[3];                     // its three dim inks
uniform float grass_gap = 0.62;                // the share of grass cells left empty
uniform float sway = 0.025;                    // how far grass leans (cell widths)
uniform float waves[2];                        // atlas places of the water's two characters
uniform vec3 water_ink = vec3(0.47, 0.72, 0.96);
uniform vec3 water_bg = vec3(0.06, 0.17, 0.30);
uniform float water_rate = 0.06;               // how fast the bands drift (radians a second)
uniform float dots[2];                         // atlas places of the shore's two characters
uniform vec3 shore_ink = vec3(0.79, 0.67, 0.42);
uniform vec3 shore_bg = vec3(0.17, 0.14, 0.08);
uniform vec3 path_ink = vec3(0.96, 0.85, 0.60);
uniform vec3 path_bg = vec3(0.17, 0.13, 0.07);


uniform vec2 wrong_cell = vec2(-99999.0);      // the cell holding the wrong glyph (cell coordinates)
uniform float wrong_index = 0.0;               // its place in the atlas
uniform vec3 wrong_color = vec3(1.0, 0.86, 0.42);   // the colour it shines
uniform float wrong_glow = 0.0;                // 0..1: it catches the light once you are close
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

vec3 pal(float place) {
	return texture(palette_tex, vec2((floor(place * 255.0 + 0.5) + 0.5) / 256.0, 0.5)).rgb;
}

float glyph_at(float idx, vec2 local, float level) {
	vec2 g = vec2(mod(idx, atlas_grid.x), floor(idx / atlas_grid.x));
	return textureLod(atlas, (g + clamp(local, vec2(0.02), vec2(0.98))) / atlas_grid, level).a;
}

void fragment() {
	vec2 w = world_pos;
	vec2 to_uv = px_scale * SCREEN_PIXEL_SIZE;

	vec3 ink;
	vec3 bg = page;
	float a = 0.0;
	{
		vec2 ci = floor(w / cell);
		vec2 local = (w - ci * cell) / cell;
		vec2 mc = ci - map_origin;
		vec4 t = vec4(0.0);
		if (mc.x >= 0.0 && mc.y >= 0.0 && mc.x < map_size.x && mc.y < map_size.y) {
			t = texture(cell_tex, (mc + 0.5) / map_size);
		}
		float thing = floor(t.r * 255.0 + 0.5);
		float ground = floor(t.g * 255.0 + 0.5);
		float h = hash(ci);
		float idx = 0.0;
		ink = vec3(1.0);
		// the ground first: it is what shows behind and between things
		if (ground == 1.0) {
			float band = 0.5 + 0.5 * sin(ci.x * 0.36 + ci.y * 1.3 - time * water_rate + h * 1.4);
			idx = waves[int(step(0.5, band))];
			ink = water_ink;
			bg = water_bg;
		} else if (ground == 2.0) {
			idx = dots[int(step(0.5, h))];
			ink = shore_ink;
			bg = shore_bg;
		} else if (ground == 3.0) {
			ink = path_ink;
			bg = path_bg;
			if (text_on > 0.5) {
				// a path is WRITTEN: every row of the page is one of the writer's sentences
				float ly = mod(ci.y, text_size.y);
				float lx = mod(ci.x + floor(hash(vec2(ly, 3.7)) * text_size.x), text_size.x);
				idx = floor(texture(text_tex, (vec2(lx, ly) + 0.5) / text_size).r * 255.0 + 0.5);
			}
		} else {
			float is_wrong = (ci == wrong_cell) ? 1.0 : 0.0;
			ink = grass_ink[int(floor(hash(ci + 5.1) * 2.999))];
			if (is_wrong > 0.5) {
				idx = wrong_index;
				ink = mix(ink, wrong_color * (0.8 + 0.2 * sin(time * 3.0)), wrong_glow);
				bg = page + wrong_color * 0.10 * wrong_glow;
			} else if (hash(ci + 17.3) >= grass_gap) {
				idx = tufts[int(floor(hash(ci + 9.7) * 5.999))];
				// grass leans a breath, from the foot of the character
				local.x += sin(time * 1.3 + w.x * 0.021 + w.y * 0.013) * sway * (1.0 - local.y);
			}
		}
		// a thing stands here: its character and ink, and its tint if it has one
		if (thing > 0.0) {
			idx = thing;
			ink = pal(t.b);
			if (t.a > 0.0) {
				bg = pal(t.a);
			}
		}
		if (idx > 0.0) {
			a = glyph_at(idx, local, lod);
		}
	}

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
