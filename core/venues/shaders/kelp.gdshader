shader_type spatial;
render_mode cull_disabled;

// Kelp: olive-brown, lit through from behind where the light comes down, swaying in the swell.
// The sway grows with height above the holdfast (the model's origin), so the foot stays on the
// sand; each stalk's phase comes from where it stands, so a forest does not move in step.

uniform vec4 colour : source_color = vec4(0.32, 0.27, 0.08, 1.0);
uniform vec4 through : source_color = vec4(0.55, 0.5, 0.12, 1.0);
uniform float sway = 0.5;
uniform float height = 7.0;

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = root.x * 0.37 + root.z * 0.23;
	float k = pow(clamp(VERTEX.y / height, 0.0, 1.5), 1.6);
	float t = TIME * 0.55 + phase;
	// The swell in one direction, a slower stir across it. Applied in the model's own space,
	// so the swell's direction turns with each stalk; across a forest that reads as current.
	VERTEX.x += (sin(t) * 0.8 + sin(t * 2.3 + 1.0) * 0.2) * sway * k;
	VERTEX.z += sin(t * 0.6 + 2.0) * 0.4 * sway * k;
}

void fragment() {
	ALBEDO = colour.rgb;
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
	BACKLIGHT = through.rgb;
}
