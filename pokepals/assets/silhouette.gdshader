shader_type canvas_item;
//
// A SHADOW: whatever a node draws (a player, an animal sheet, the mural's birds) is painted as one flat
// cut-paper colour, keeping only its shape (its alpha), then clipped to the cliff-face screen it falls on.
// Used by Lanternfold's ShadowScreenView. Cheap by design (no screen reads, no render targets): one texture
// sample and a rectangle test per pixel the sprite covers, so a phone pays nothing for it.
//
// `clip` is the face's rectangle in WORLD pixels (x0, y0, x1, y1); a fragment outside it is dropped, which is
// how a too-big shadow ends at the screen's edge instead of spilling into the sky.

uniform vec4 shadow_color : source_color = vec4(0.16, 0.07, 0.06, 1.0);
uniform vec4 clip = vec4(-100000.0, -100000.0, 100000.0, 100000.0);

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (world_pos.x < clip.x || world_pos.y < clip.y || world_pos.x > clip.z || world_pos.y > clip.w) {
		discard;
	}
	// COLOR is the texture sample x the node's modulate: keep only its alpha, so the shape is all that shows
	COLOR = vec4(shadow_color.rgb, COLOR.a * shadow_color.a);
}
