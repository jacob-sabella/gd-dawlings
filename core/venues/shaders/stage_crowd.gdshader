shader_type spatial;
render_mode cull_back;

// A crowd of silhouettes in front of a stage: near-black bodies, picked out at their edges by
// the colour the stage is throwing at them, swaying and, when the music is loud, jumping.
// One MultiMesh a pose; each instance moves on its own phase (stage_sway.gdshaderinc).

#include "res://core/venues/shaders/stage_sway.gdshaderinc"

uniform vec4 body : source_color = vec4(0.02, 0.02, 0.025, 1.0);
uniform vec4 rim_colour : source_color = vec4(0.45, 0.3, 1.0, 1.0);
// The other wash, from the other side of the rig: the crowd's left half catches the one, its
// right half the other, blending across the middle.
uniform vec4 rim_colour_b : source_color = vec4(0.25, 0.4, 1.0, 1.0);
uniform float rim = 1.0;
uniform float roughness_body = 0.85;

void vertex() {
	VERTEX += crowd_move(VERTEX, MODEL_MATRIX[3].xyz, TIME);
}

void fragment() {
	ALBEDO = body.rgb;
	ROUGHNESS = roughness_body;
	// Lit by the stage, which is up the field (+Z) from every one of them: what faces it catches
	// its colour, so from the stage the crowd is a sea of lit faces and from behind, black
	// shapes against it; and a thin edge all round where the haze wraps them.
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float toward = max(world_n.z, 0.0) * (0.6 + 0.4 * max(world_n.y, 0.0));
	float edge = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 5.0);
	// Lit harder on the beat, as the rig flashes.
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wash = mix(rim_colour.rgb, rim_colour_b.rgb, smoothstep(-12.0, 12.0, world.x));
	EMISSION = wash * (toward * 0.07 + edge * 0.08) * rim * (0.5 + pulse * 0.9);
}
