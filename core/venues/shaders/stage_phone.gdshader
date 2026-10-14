shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// The phones held up in a crowd: a small cold screen in a raised hand, moving with the body
// that holds it (the same sway, from the same origin). Not every phone is up: some instances
// are thrown away, and the rest flicker a little as their screens change.

#include "res://core/venues/shaders/stage_sway.gdshaderinc"

uniform vec4 screen : source_color = vec4(0.75, 0.85, 1.0, 1.0);
uniform float strength = 2.0;
// The share of the raised hands with a phone lit in them.
uniform float lit_share = 0.45;

varying float which;

void vertex() {
	which = crowd_hash(MODEL_MATRIX[3].xz + vec2(3.1, 7.7));
	VERTEX += crowd_move(VERTEX, MODEL_MATRIX[3].xyz, TIME);
}

void fragment() {
	if (which > lit_share) {
		discard;
	}
	float flicker = 0.75 + 0.25 * sin(TIME * (1.5 + which * 4.0) + which * 30.0);
	ALBEDO = screen.rgb * strength * flicker * (0.85 + pulse * 0.4);
}
