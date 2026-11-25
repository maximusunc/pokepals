shader_type canvas_item;
render_mode blend_disabled;
// The GLYPH look: how a visitor is told apart from the ground in Glyphfall, the world made of text. Applied as a
// ShaderMaterial on the PlayerView / CompanionView node (OtherworldLook, a look with a "glyph" block). It draws
// the node exactly as it is, but writes its pixels straight into the picture with a MARK in the alpha channel
// (blending off, so the alpha lands as written). The page shader (glyph_page.gdshader) reads the picture back
// and writes a marked pixel smaller and denser than the world round it, so a person is a figure made of small
// letters and not a smudge in the grass. Anything drawn over a visitor afterwards (a tree in front) blends
// normally and covers the mark. Soft pixels (a shadow under the feet) are dropped: there is no blending here.

uniform float mark : hint_range(0.0, 1.0) = 0.5;
uniform float lift : hint_range(0.0, 1.0) = 0.12;   // brightens the figure a little, so its letters carry

void fragment() {
	vec4 c = COLOR;
	if (c.a < 0.6) {
		discard;
	}
	COLOR = vec4(mix(c.rgb, vec3(1.0), lift * (1.0 - dot(c.rgb, vec3(0.299, 0.587, 0.114)))), mark);
}
