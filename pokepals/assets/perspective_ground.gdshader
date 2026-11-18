shader_type canvas_item;
// The perspective view's ground and sky (PerspectiveView). The flat layer of the world (ground, paths, ponds,
// props, footprints) is rendered top-down into two textures around the camera, both cut along the view's heading:
// a sharp one for the near ground and a wide one out to the draw distance. This full-screen quad looks at them
// in perspective: for each screen pixel it finds the ground point it shows, with the same pinhole camera as
// ViewProjection.unproject, and samples the texture there. Above the horizon (and past the draw distance) is sky.

uniform sampler2D near_tex : filter_nearest, repeat_disable;
uniform sampler2D far_tex : filter_nearest, repeat_disable;
uniform vec2 view_size;      // the viewport in canvas units
uniform float zoom = 1.0;
uniform vec4 cam;            // eye height, back (camera foot to focus), pitch (radians), lens shift
uniform float far = 1250.0;  // draw distance ahead of the focus
// The rects each texture covers, in the view's frame (x along screen-right, y toward the camera; focus at 0).
uniform vec2 near_center;
uniform vec2 near_size;
uniform vec2 far_center;
uniform vec2 far_size;
uniform vec4 beyond : source_color = vec4(0.27, 0.44, 0.21, 1.0);  // past the world's edge: plain ground on to the horizon
uniform vec4 sky_top : source_color = vec4(0.45, 0.66, 0.90, 1.0);
uniform vec4 sky_low : source_color = vec4(0.86, 0.90, 0.92, 1.0);
uniform vec4 tint = vec4(1.0);
// What the land fades into with distance: a greyed green, like far fields, not the pale sky, so the ground runs on
// visibly behind things to the hills (a white strip there makes everything in the middle distance look like it's
// standing on a cliff edge). The backdrop hills' foot fades into the same colour.
uniform vec4 land_haze : source_color = vec4(0.62, 0.70, 0.60, 1.0);
uniform float haze_from = 0.6;  // haze starts this share of the draw distance ahead
uniform float haze_max = 0.85;  // ...and reaches at most this much at the draw distance
// The backdrop (a world's view "backdrop"): panoramas wrapping 360 degrees round the horizon, column = bearing
// (0 = north, clockwise), one texel per screen pixel: distant hills standing on the far edge of the ground, and
// clouds above them, drifting.
uniform float yaw = 0.0;
uniform bool has_hills = false;
uniform sampler2D hills : filter_nearest, repeat_enable;
uniform bool has_clouds = false;
uniform sampler2D clouds : filter_nearest, repeat_enable;
uniform float cloud_drift = 0.0;  // how far the clouds have drifted, as a share of the full circle

vec4 over(vec4 base, vec4 top) {
	return vec4(mix(base.rgb, top.rgb, top.a), 1.0);
}  // the world's day tint (its CanvasModulate): the ground textures already carry it, the sky takes it here

bool inside01(vec2 uv) {
	return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

void fragment() {
	float h = cam.x;
	float back = cam.y;
	float cp = cos(cam.z);
	float sp = sin(cam.z);
	float f = back * cp + h * sp;
	vec2 v = (UV * view_size - view_size * 0.5) / zoom;
	float horizon_y = cam.w - f * sp / cp;
	vec4 sky = mix(sky_low, sky_top, sqrt(clamp((horizon_y - v.y) / (view_size.y / zoom * 0.6), 0.0, 1.0)));
	float q = (v.y - cam.w) / f;
	float den = q * cp + sp;
	float a = den > 1e-6 ? h * (cp - q * sp) / den : 1e9;
	float ahead = a - back;
	// the backdrop, looked up by bearing (the column's angle off the view's heading, plus the heading)
	float u = (yaw + atan(v.x, f)) / 6.28318530718;
	float a_edge = back + far;
	float y_edge = cam.w + f * (h * cp - a_edge * sp) / (a_edge * cp + h * sp);  // where the far ground ends
	if (has_clouds) {
		vec2 cs = vec2(textureSize(clouds, 0));
		float row = cs.y - (horizon_y - 14.0 - v.y);
		if (row >= 0.0 && row < cs.y) {
			sky = over(sky, texture(clouds, vec2(u + cloud_drift, (row + 0.5) / cs.y)));
		}
	}
	bool hill = false;
	if (has_hills) {
		vec2 hs = vec2(textureSize(hills, 0));
		float row = hs.y - (y_edge + 1.0 - v.y);
		if (row >= 0.0 && row < hs.y) {
			vec4 hc = texture(hills, vec2(u, (row + 0.5) / hs.y));
			hill = hc.a > 0.5;
			sky = over(sky, hc);
		}
	}
	sky.rgb *= tint.rgb;
	if (ahead > far || hill) {
		COLOR = sky;
	} else {
		float z = a * cp + h * sp;
		vec2 d = vec2(v.x * z / f, back - a);
		vec2 uvn = (d - near_center) / near_size + 0.5;
		vec4 c;
		if (inside01(uvn)) {
			c = texture(near_tex, uvn);
		} else {
			vec2 uvf = (d - far_center) / far_size + 0.5;
			c = inside01(uvf) ? texture(far_tex, uvf) : vec4(0.0);
		}
		c.rgb = mix(beyond.rgb * tint.rgb, c.rgb, c.a);
		float haze = smoothstep(far * haze_from, far, ahead) * haze_max;
		COLOR = vec4(mix(c.rgb, land_haze.rgb * tint.rgb, haze), 1.0);
	}
}
