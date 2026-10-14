shader_type spatial;
// Cigarette smoke hanging in a speakeasy: soft billows on camera-facing quads (one MultiMesh),
// each drifting slowly round where it was put and rolling over on itself in a moving noise.
// Lit by nothing (a lit transparent costs every light in the room on every billow): the
// instance's custom data carries a seed (r) and how near it hangs to a lamp (g), which
// warms and brightens it, so the smoke over the bulbs glows and the smoke in the corners does not.

render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 shadow : source_color = vec3(0.09, 0.08, 0.07);
uniform vec3 lit : source_color = vec3(0.42, 0.3, 0.17);
uniform float density = 0.2;
uniform float drift = 0.06;

varying float seed;
varying float glow;
varying float eye;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	seed = INSTANCE_CUSTOM.r;
	glow = INSTANCE_CUSTOM.g;
	vec3 centre = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	float t = TIME * drift;
	centre += vec3(sin(t + seed * 6.28) * 0.35, sin(t * 0.7 + seed * 3.1) * 0.08, cos(t * 0.8 + seed * 4.0) * 0.35);
	// Wider than tall: smoke lies in layers.
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = centre + right * VERTEX.x * size + up * VERTEX.y * size * 0.5;
	vec4 view = VIEW_MATRIX * vec4(world, 1.0);
	eye = -view.z;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	vec2 p = UV * vec2(2.2, 1.4) + seed * 17.0;
	float t = TIME * drift;
	float n = vnoise(p + vec2(t * 1.3, -t * 0.4)) * 0.6 + vnoise(p * 2.7 - vec2(t, t * 0.8)) * 0.4;
	vec2 c = UV * 2.0 - 1.0;
	float round_off = clamp(1.0 - dot(c, c), 0.0, 1.0);
	float body = smoothstep(0.2, 0.95, n) * pow(round_off, 1.6);
	// Gone right up close, so it never fills the eye.
	float near = smoothstep(0.6, 2.2, eye);
	ALBEDO = mix(shadow, lit, glow);
	ALPHA = body * density * near * (0.7 + 0.3 * glow);
}
