shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// The lake past the clearing in front of the cabin. Water that mirrors the sky (the reflection
// is the environment's own, off a surface this smooth), stirred by a little wind into long, slow
// ripples, darker where you look down into it and bright where you look along it. On a night of
// northern lights it is frozen: `ice` takes it to a dull sheet with snow blown across it in
// streaks, still holding a soft smear of what is overhead.

uniform vec4 deep : source_color = vec4(0.02, 0.035, 0.04, 1.0);
uniform vec4 snow : source_color = vec4(0.6, 0.66, 0.76, 1.0);
uniform float ice = 0.0;
// The lake's outline on the ground: an ellipse, its shore pushed in and out by noise.
uniform vec2 centre = vec2(0.0, -62.0);
uniform vec2 radii = vec2(58.0, 30.0);

varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float shore = length((p - centre) / radii) + (noise(p * 0.07) - 0.5) * 0.16;
	if (shore > 1.0) {
		discard;
	}
	float t = TIME * (1.0 - ice);
	// Ripples: long and slow across the wind, and a finer chop over them.
	float a = noise(p * vec2(0.18, 0.6) + vec2(t * 0.12, t * 0.05));
	float b = noise(p * vec2(0.7, 1.9) - vec2(t * 0.25, -t * 0.1));
	vec2 slope = vec2(a - 0.5, b - 0.5) * mix(0.25, 0.04, ice);
	// Blown snow on the ice, in streaks along the wind.
	float drift = smoothstep(0.45, 0.8, noise(p * vec2(0.08, 0.5)) * 0.7 + noise(p * 0.9) * 0.3) * ice;
	// Shallows at the shore: the bottom shows through, or the snow has piled at the ice's edge.
	float shallow = smoothstep(0.88, 1.0, shore);
	drift = max(drift, shallow * ice);
	ALBEDO = mix(mix(deep.rgb, deep.rgb * 2.5 + vec3(0.03, 0.025, 0.01), shallow * (1.0 - ice)), snow.rgb, drift);
	ROUGHNESS = mix(mix(0.04, 0.22, ice), 0.85, drift);
	SPECULAR = 0.5;
	NORMAL_MAP = normalize(vec3(slope, 1.0)) * 0.5 + 0.5;
}
