shader_type canvas_item;
//
// Palette-swap dye for one grayscale layer -> any color, at runtime.
// Author the dyeable layer (hair, a garment, skin) in GRAYSCALE: paint the shading
// ramp in shades of gray, keep the dark outline. Assign this as a ShaderMaterial on
// that layer's Sprite2D and set `base_color`. One PNG -> infinite dyes, no re-export.
//
// If you prefer, skip this entirely and just export pre-colored layers (simpler, but
// one file per color).

uniform vec4 base_color : source_color = vec4(0.71, 0.38, 0.23, 1.0);
uniform float shade_amount : hint_range(0.0, 1.0) = 0.30;   // how dark the shadow ramp is
uniform float light_amount : hint_range(0.0, 1.0) = 0.22;   // how bright the highlight is
uniform float outline_cut  : hint_range(0.0, 0.5) = 0.12;   // luminance below this = outline

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	if (t.a < 0.01) {
		COLOR = vec4(0.0);
	} else {
		float l = dot(t.rgb, vec3(0.299, 0.587, 0.114)); // luminance of the gray source
		vec3 outc;
		if (l < outline_cut) {
			outc = vec3(0.14, 0.09, 0.07);               // preserve the outline
		} else {
			vec3 shadow    = base_color.rgb * (1.0 - shade_amount);
			vec3 highlight = mix(base_color.rgb, vec3(1.0), light_amount);
			outc = mix(shadow, highlight, smoothstep(outline_cut, 0.95, l));
		}
		COLOR = vec4(outc, t.a);
	}
}
