shader_type canvas_item;
// A soft, screen-space vignette: darkens the corners so the eye settles toward the
// middle of the frame and the world feels lit rather than evenly flat. Drawn on a
// full-screen ColorRect; UV runs 0..1 across the rect. Presentation-only.

uniform float strength : hint_range(0.0, 1.0) = 0.34;
uniform vec4 tint : source_color = vec4(0.06, 0.05, 0.10, 1.0);
// Scanlines (Ohmstead): one screen row in every `scan_px` is darkened by `scan_strength`. Off (0) everywhere else.
uniform float scan_strength : hint_range(0.0, 1.0) = 0.0;
uniform float scan_px = 3.0;

void fragment() {
	float dist = length(UV - vec2(0.5)) * 1.41421356;
	float v = smoothstep(0.45, 1.0, dist) * strength;
	float scan = step(fract(FRAGCOORD.y / scan_px), 1.0 / scan_px) * scan_strength;
	// two darkenings laid over each other: the corner tint, and a black line
	float a = v + scan - v * scan;
	COLOR = vec4(tint.rgb * (v / max(a, 0.0001)), a);
}
