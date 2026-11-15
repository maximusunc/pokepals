shader_type canvas_item;
// SPIKE (Horizon): the flat layer of the world (ground, paths, ponds, props) is rendered top-down into a
// texture around the camera; this full-screen quad looks at it through a tilted perspective, so the ground
// runs off to a horizon. For each screen pixel we invert the projection to find the ground point it shows
// (see PerspectiveView.project for the forward maths) and sample the texture there.

uniform sampler2D flat_tex : filter_nearest, repeat_disable;
uniform vec2 view_size;      // the viewport in canvas units
uniform vec2 cam_center;     // the ground point at the focus (world)
uniform float zoom = 1.0;
uniform vec2 focus;          // where cam_center lands, offset from the screen centre (world units at the focus)
uniform float k = 0.55;      // foreshortening at the focus (screen px per world unit of depth)
uniform float z0 = 340.0;    // eye-to-focus distance (world units)
uniform vec2 flat_center;    // world rect the texture covers
uniform vec2 flat_size;
uniform float s_far = 0.3;   // draw distance, as a scale
uniform float s_haze = 0.55; // haze starts here
uniform vec4 haze : source_color = vec4(0.80, 0.86, 0.90, 1.0);
uniform vec4 sky_top : source_color = vec4(0.45, 0.66, 0.90, 1.0);
uniform vec4 sky_low : source_color = vec4(0.86, 0.90, 0.92, 1.0);

void fragment() {
	vec2 v = (UV * view_size - view_size * 0.5) / zoom - focus;
	float s = 1.0 + v.y / (k * z0);
	if (s <= s_far) {
		// sky: from the haze at the horizon line up to blue
		float horizon_y = k * z0 * (s_far - 1.0);
		float t = clamp((horizon_y - v.y) / (view_size.y / zoom * 0.6), 0.0, 1.0);
		COLOR = mix(sky_low, sky_top, sqrt(t));
	} else {
		vec2 d = vec2(v.x / s, z0 - z0 / s);
		vec2 uv = (cam_center + d - flat_center) / flat_size + 0.5;
		vec4 c = texture(flat_tex, uv);
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			c = vec4(0.0);
		}
		c.rgb = mix(haze.rgb, c.rgb, c.a);
		float h = smoothstep(s_haze, s_far, s);
		COLOR = vec4(mix(c.rgb, sky_low.rgb, h), 1.0);
	}
}
