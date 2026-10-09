shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// The beam of a stage spot in a room's haze: a cone of light, brightest down its middle (where
// the eye looks through the most lit air) and at the lamp, fading to nothing by the stage.
// Drawn on an open cone (a CylinderMesh, narrow end up at the lamp).

uniform vec4 colour : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float strength = 0.08;

varying float along;

void vertex() {
	// 0 at the lamp (the top), 1 at the far end.
	along = clamp(0.5 - VERTEX.y, 0.0, 1.0);
}

void fragment() {
	float through = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float a = pow(through, 2.0) * (1.0 - along * 0.8) * smoothstep(1.0, 0.85, along);
	ALBEDO = colour.rgb * a * strength;
}
