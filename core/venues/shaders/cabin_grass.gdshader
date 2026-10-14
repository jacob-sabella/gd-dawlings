shader_type spatial;
render_mode cull_disabled;

// Meadow grass round the cabin on a summer evening, a tuft at a time (tools/blender/cabin_porch.py's
// "grass", drawn as MultiMeshes): dark at the root, going to a dry gold at the tips, each tuft a
// little different in its green, and all of it leaning and swaying in a light wind that comes
// through in slow gusts.

uniform vec4 root : source_color = vec4(0.05, 0.1, 0.03, 1.0);
uniform vec4 blade : source_color = vec4(0.22, 0.34, 0.08, 1.0);
uniform vec4 tip : source_color = vec4(0.55, 0.5, 0.22, 1.0);
uniform float wind = 1.0;

varying float up;
varying float pick;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 at = MODEL_MATRIX[3].xyz;
	pick = hash(at.xz);
	// How far up its blade a vertex is, in the tuft's own units (0.35 tall).
	up = clamp(VERTEX.y / 0.35, 0.0, 1.0);
	float gust = sin(TIME * 0.6 + at.x * 0.15 + at.z * 0.1) * 0.5 + 0.5;
	float sway = sin(TIME * 1.9 + pick * 6.0 + at.x * 0.7) * (0.3 + 0.7 * gust);
	VERTEX.x += sway * 0.05 * up * up * wind;
	VERTEX.z += sway * 0.02 * up * up * wind;
}

void fragment() {
	vec3 c = mix(root.rgb, blade.rgb * (0.8 + 0.4 * pick), smoothstep(0.0, 0.4, up));
	c = mix(c, tip.rgb, smoothstep(0.55, 1.0, up) * (0.4 + 0.6 * pick));
	ALBEDO = c;
	ROUGHNESS = 0.8;
	// Thin blades: the low sun shows through them.
	BACKLIGHT = vec3(0.3, 0.35, 0.1) * up;
}
