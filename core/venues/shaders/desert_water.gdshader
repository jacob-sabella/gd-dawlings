shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, specular_schlick_ggx;

// The oasis's pool: still, dark water. It is a window more than a surface: under it the venue
// hangs the world upside down (the palms, the lanterns' light) and the sky shader's underside is
// the sky reflected (desert_sky.gdshader), so looking into the pool shows the evening given back.
// The water itself only darkens that and tints it, more so looking straight down, where you see
// into it rather than off it; a slow breath of ripple runs over it, the odd ring where something
// touched it (an insect, a falling date).

uniform vec4 deep : source_color = vec4(0.01, 0.025, 0.03, 1.0);
// How much of the upside-down world comes through, looking along the water and looking down.
uniform float glancing = 0.82;
uniform float straight_down = 0.45;
uniform float ripple = 0.03;
// Where the pool is, and how far the rings may start from its middle.
uniform vec2 centre = vec2(0.0, -9.5);
uniform vec2 extent = vec2(5.0, 3.0);

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float t = TIME;
	// A slow swell of tiny ripples, and rings spreading from a few points that come and go.
	float sx = noise2(p * 1.3 + vec2(t * 0.11, 0.0)) - noise2(p * 1.3 + vec2(t * 0.11 + 0.1, 0.0));
	float sz = noise2(p * 1.3 + vec2(0.0, t * 0.09)) - noise2(p * 1.3 + vec2(0.1, t * 0.09));
	vec2 tilt = vec2(sx, sz) * 6.0 * ripple;
	for (int i = 0; i < 3; i++) {
		float cycle = 7.0 + float(i) * 2.3;
		float k = floor((t + float(i) * 3.1) / cycle);
		float age = fract((t + float(i) * 3.1) / cycle) * cycle;
		vec2 at = vec2(hash2(vec2(k, float(i))), hash2(vec2(float(i), k + 5.0))) * 2.0 - 1.0;
		vec2 off = p - (at * extent + centre);
		float r = length(off);
		float ring = sin((r - age * 0.35) * 30.0) * exp(-age * 0.7) * smoothstep(age * 0.35 + 0.2, age * 0.35, r);
		tilt += normalize(off + 1e-4) * ring * 0.05;
	}
	vec3 n = normalize(vec3(-tilt.x, 1.0, -tilt.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 to_eye = normalize(CAMERA_POSITION_WORLD - world);
	float down = clamp(to_eye.y, 0.0, 1.0);
	ALBEDO = deep.rgb;
	ALPHA = 1.0 - mix(glancing, straight_down, down);
	ROUGHNESS = 0.08;
	SPECULAR = 0.15;
}
