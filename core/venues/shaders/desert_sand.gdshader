shader_type spatial;

// Sand, laid in world space so the floor under the tent, the dunes and the canyon floor are one
// ground. The scanned sand gives the grain close up; over it the wind's ripples, a ridge every
// few centimetres across the wind, bent and broken by the lie of the ground, drawn in the normal
// so a low sun rakes them into lines of shadow. They fade with distance, where they would only
// shimmer, and on steep slip faces, where sand slides rather than ripples.

uniform sampler2D grain_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.82, 0.62, 0.42, 1.0);
// A second colour the ground drifts to in broad patches (darker gravel, paler drift sand).
uniform vec4 patch_tint : source_color = vec4(0.7, 0.5, 0.34, 1.0);
uniform float grain_metres = 1.6;
// The wind, toward which the ripples' steep side faces; their spacing; their depth in the normal.
uniform vec2 wind = vec2(0.8, -0.6);
uniform float ripple_metres = 0.08;
uniform float ripple_depth = 0.55;
// Where the ripples give out, in metres from the eye.
uniform float ripple_reach = 22.0;

varying vec3 world;
varying vec3 world_normal;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise2(p);
		p *= 2.13;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world.xz;
	vec3 grain = texture(grain_tex, p / grain_metres).rgb;
	float patches = smoothstep(0.35, 0.7, fbm2(p * 0.05));
	vec3 c = mix(tint.rgb, patch_tint.rgb, patches) * (0.72 + 0.45 * grain);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;

	// Ripples: a sawtooth across the wind, its phase warped by noise so the crests wander and fork.
	vec2 w = normalize(wind);
	vec2 across = vec2(-w.y, w.x);
	float warp = fbm2(p * 0.35) * 2.2 + fbm2(p * 1.7) * 0.4;
	float phase = (dot(p, w) + warp * ripple_metres * 4.0) / ripple_metres;
	float f = fract(phase);
	// Gentle up the windward side, steep down the lee: the slope of the ripple at this point.
	float slope = f < 0.75 ? 1.0 / 0.75 : -1.0 / 0.25;
	float dist = length(world - CAMERA_POSITION_WORLD);
	float flat_ground = smoothstep(0.55, 0.9, world_normal.y);
	float fade = (1.0 - smoothstep(ripple_reach * 0.4, ripple_reach, dist)) * flat_ground;
	vec2 tilt = w * slope * ripple_depth * 0.25 * fade;
	vec3 nmap = texture(grain_normal, p / grain_metres).xyz * 2.0 - 1.0;
	// The grain's own normal and the ripple tipping it, worked in the world (the ground is lying
	// down, so its texture's x and y are the world's x and z) and handed over in view space: the
	// ground is built in code and has no tangents to map by.
	vec3 n = normalize(world_normal + vec3(nmap.x * 0.35 - tilt.x, 0.0, -nmap.y * 0.35 - tilt.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
