shader_type spatial;
render_mode cull_disabled;

// Water standing in the fountain's bowls: dark and glassy, rippled in rings spreading out from
// where the veils fall into it. In the model's own space, centred on the fountain's axis.

uniform vec4 colour : source_color = vec4(0.06, 0.09, 0.09, 1.0);
// Where the falling water lands in this pool, out from the axis.
uniform float fall_at = 0.78;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	float r = length(local.xz);
	float d = abs(r - fall_at);
	float ripples = sin(d * 70.0 - TIME * 7.0) * exp(-d * 6.0) + 0.3 * sin(r * 41.0 + TIME * 3.0);
	vec2 dir = local.xz / max(r, 0.001);
	// Tilted in the view's own space: the bowls' water has no UVs to hang a normal map on.
	vec3 tilt = (VIEW_MATRIX * MODEL_MATRIX * vec4(dir.x, 0.0, dir.y, 0.0)).xyz * ripples * 0.12;
	NORMAL = normalize(NORMAL + tilt);
	ALBEDO = colour.rgb;
	ROUGHNESS = 0.04;
	SPECULAR = 0.6;
}
