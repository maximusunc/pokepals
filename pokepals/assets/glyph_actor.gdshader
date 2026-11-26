shader_type canvas_item;
// FINE PRINT: how a visitor is written in Glyphfall, the world made of text. Applied as one shared
// ShaderMaterial to every PlayerView, CompanionView and wild animal (OtherworldLook, a look with a "glyph"
// block), and to what they carry. It redraws whatever the node draws as small dense letters, each on a solid
// block of the visitor's own colour there: quarter-size character cells (half a page cell each way), pinned to
// the WORLD like the page's own cells, so a figure is a little coloured silhouette made of letters that keeps
// its outfit's colours and its animal's shape.
//
// For the quarter-cell under each pixel it reads the node's OWN texture round the cell's middle (four taps):
// two or more on the figure and the whole cell is a block of their colour with a letter in it; fewer and the
// cell is left to the page behind. Nothing is read back from the screen. A letter never follows brightness
// (each cell keeps one of four, by position), so a figure that breathes changes colour under still letters.
// Soft pixels (a shadow under the feet) are dropped.

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_grid = vec2(16.0, 8.0);
uniform vec2 cell = vec2(8.0, 12.0);          // one PAGE character in world px; fine print is half that each way
uniform float lod = 1.0;                      // atlas mip for a full-size cell (GlyphPage keeps it current)
uniform float print[4];                       // atlas places of the dense letters
uniform float vivid = 1.25;                   // how much more saturated than the sprite the blocks are
uniform float dark = 0.32;                    // a letter on a light block is the block's colour times this...
uniform float light = 0.72;                   // ...and on a dark block, the block's colour mixed this far to white

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	vec4 c = COLOR;   // the texture sample x vertex colour: what the node drew here
	vec2 w = world_pos;
	vec2 fs = cell * 0.5;
	vec2 fi = floor(w / fs);
	vec2 fc = (fi + 0.5) * fs;
	// how far the texture moves per world px (a flipped or scaled sprite is handled by the sign and size)
	vec2 uv_per_world = vec2(dFdx(UV.x) / dFdx(w.x), dFdy(UV.y) / dFdy(w.y));
	vec2 mid = UV + (fc - w) * uv_per_world;
	vec2 o = fs * 0.25 * uv_per_world;
	vec4 t0 = texture(TEXTURE, mid + o);
	vec4 t1 = texture(TEXTURE, mid - o);
	vec4 t2 = texture(TEXTURE, mid + vec2(o.x, -o.y));
	vec4 t3 = texture(TEXTURE, mid + vec2(-o.x, o.y));
	vec4 m = vec4(step(0.6, t0.a), step(0.6, t1.a), step(0.6, t2.a), step(0.6, t3.a));
	float hits = m.x + m.y + m.z + m.w;
	// the node's own colour and fade (modulate) ride in the vertex colour: keep them
	vec4 own = texture(TEXTURE, UV);
	vec3 tint = own.a > 0.01 ? c.rgb / max(own.rgb, vec3(0.004)) : vec3(1.0);
	float fade = own.a > 0.01 ? c.a / own.a : c.a;
	if (hits < 1.5 || fade < 0.05) {
		discard;
	}
	vec3 s = (t0.rgb * m.x + t1.rgb * m.y + t2.rgb * m.z + t3.rgb * m.w) / hits * clamp(tint, 0.0, 4.0);
	float lum = dot(s, vec3(0.299, 0.587, 0.114));
	s = clamp(mix(vec3(lum), s, vivid), 0.0, 1.0);
	float idx = print[int(floor(hash(fi) * 3.999))];
	vec2 g = vec2(mod(idx, atlas_grid.x), floor(idx / atlas_grid.x));
	vec2 local = clamp((w - fi * fs) / fs, vec2(0.02), vec2(0.98));
	float a = textureLod(atlas, (g + local) / atlas_grid, max(0.0, lod - 1.0)).a;
	vec3 ink = lum > 0.42 ? s * dark : mix(s, vec3(1.0), light);
	COLOR = vec4(mix(s, ink, a), clamp(fade, 0.0, 1.0));
}
