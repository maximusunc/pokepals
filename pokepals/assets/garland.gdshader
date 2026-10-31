shader_type canvas_item;
// What hangs over a souk's lane (Garlands), animated on the GPU so the script draws nothing per frame.
// Every piece is one MultiMesh instance; INSTANCE_CUSTOM.x is its own phase, so no two twinkle,
// flutter or sway in step. `kind` picks the behaviour:
//   0 bulb:     a tiny light, twinkling: a soft glow plus a bright core (computed here, no texture)
//   1 glow:     a lantern's pool of light, flickering
//   2 lantern:  the lantern itself on its cord, swaying from the cord point (its local origin)
//   3 bunting:  a pennant whose tip flutters

uniform int kind = 0;

varying float v_amp;

void vertex() {
	float ph = INSTANCE_CUSTOM.x;
	if (kind == 0) {
		v_amp = 0.6 + 0.4 * sin(TIME * 3.0 + ph);
	} else if (kind == 1) {
		v_amp = 0.85 + 0.15 * sin(TIME * 5.0 + ph);
		VERTEX *= v_amp;
	} else if (kind == 2) {
		// hanging from the cord: the bottom swings, the top stays put
		float sway = sin(TIME * 1.3 + ph) * 2.0;
		VERTEX.x += sway * clamp(VERTEX.y / 16.0, 0.0, 1.5);
		v_amp = 0.85 + 0.15 * sin(TIME * 5.0 + ph * 1.3);
	} else {
		if (VERTEX.y > 1.0) {
			VERTEX.x += sin(TIME * 2.2 + ph) * 1.5;
		}
		v_amp = 1.0;
	}
}

// The same soft falloff as SoftGlow's texture: bright centre, a knee at 0.35, a long gentle fade.
float falloff(float d) {
	if (d < 0.35) {
		return mix(1.0, 0.42, d / 0.35);
	}
	return mix(0.42, 0.0, clamp((d - 0.35) / 0.65, 0.0, 1.0));
}

void fragment() {
	if (kind == 0) {
		float d = length(UV - vec2(0.5)) * 2.0;   // 0 at the centre, 1 at the quad's rim (5 px)
		vec4 glow = vec4(1.0, 0.82, 0.48, 0.35 * v_amp * falloff(d));
		float core = 1.0 - smoothstep(0.24, 0.32, d);   // a ~1.4 px bright bead
		vec4 bead = vec4(1.0, 0.92, 0.66, 0.6 + 0.4 * v_amp);
		COLOR = mix(glow, bead, core * bead.a);
		COLOR.a = max(glow.a, core * bead.a);
	} else if (kind == 1) {
		float d = length(UV - vec2(0.5)) * 2.0;
		COLOR = vec4(COLOR.rgb, COLOR.a * falloff(d));
	} else if (kind == 2) {
		// the bright heart of the lantern (UV.x = 1 on its vertices) flickers; the brass doesn't
		COLOR.rgb *= mix(1.0, v_amp + 0.1, UV.x);
	}
}
