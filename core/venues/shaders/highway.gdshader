shader_type spatial;
render_mode specular_schlick_ggx;

// The road to the sun: black glass, neon kerbs, and a dashed centre line running away from
// you. Ruled in world space, so the quad can be any length without the dashes stretching.

uniform vec4 asphalt : source_color = vec4(0.006, 0.002, 0.016, 1.0);
uniform vec4 kerb : source_color = vec4(1.0, 0.15, 0.75, 1.0);
uniform vec4 dash : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform float half_width = 5.0;
uniform float energy = 3.0;
uniform float travel = 0.0;
uniform float pulse = 0.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float rule(float d, float w) {
	float fw = max(fwidth(d), 1e-4);
	return 1.0 - smoothstep(w - fw, w + fw, abs(d));
}

void fragment() {
	float x = world.x;
	float z = world.z + travel * 30.0;
	float kerbs = rule(abs(x) - half_width, 0.06);
	float lanes = rule(abs(abs(x) - half_width * 0.5), 0.025) * step(0.5, fract(z / 6.0));
	float centre = rule(abs(x) - 0.12, 0.035) * step(0.45, fract(z / 9.0));
	float far = smoothstep(220.0, 10.0, -world.z);
	vec3 glow = (kerb.rgb * kerbs + vec3(0.5, 0.9, 1.0) * lanes * 0.6 + dash.rgb * centre)
			* energy * (1.0 + pulse * 0.8) * far;
	ALBEDO = asphalt.rgb;
	EMISSION = glow;
	ROUGHNESS = 0.32;
	SPECULAR = 0.25;
}
