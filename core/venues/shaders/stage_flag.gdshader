shader_type spatial;
render_mode cull_disabled;

// A festival flag on a pole, flying: a subdivided quad whose fly end ripples in the wind, more
// the further from the pole. Its colour is the instance's (MultiMesh use_colors).

uniform float wind = 1.0;
uniform float size_x = 1.2;

varying vec3 tint;

void vertex() {
	tint = COLOR.rgb;
	// Distance from the pole, which is the quad's -X edge.
	float out_from = clamp(VERTEX.x / size_x + 0.5, 0.0, 1.0);
	float ph = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(4.1, 9.3))) * 4375.5);
	float t = TIME * 4.0 * wind + ph * 6.283;
	VERTEX.z += sin(VERTEX.x * 4.5 - t) * 0.09 * out_from * wind;
	VERTEX.y -= out_from * out_from * 0.06;
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.85;
	BACKLIGHT = tint * 0.35;
}
