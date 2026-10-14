shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// The koi pond's surface: dark, still water that gives back the sky at a glance and lets you see
// down into it where you look straight in -- the koi under it -- with slow ripples crossing it
// and, when it is falling, the rain of petals or snow ringing it.

uniform vec4 deep : source_color = vec4(0.03, 0.06, 0.05, 1.0);
uniform vec4 shallow : source_color = vec4(0.1, 0.16, 0.12, 1.0);
uniform float clarity = 0.45;
uniform float ripple = 1.0;

float hash(vec2 p) {
	// Not sin(): on a GPU its precision runs out far from zero and the noise breaks into blocks.
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), u.x), u.y);
}

float waves(vec2 p) {
	return vnoise(p * 0.45 + vec2(TIME * 0.05, TIME * 0.02)) * 0.6
			+ vnoise(p * 1.1 - vec2(TIME * 0.04, -TIME * 0.06)) * 0.3
			+ vnoise(p * 2.6 + vec2(-TIME * 0.08, TIME * 0.07)) * 0.1;
}

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float e = 0.05;
	float h = waves(p);
	vec2 grad = vec2(waves(p + vec2(e, 0.0)) - h, waves(p + vec2(0.0, e)) - h) / e;
	// Rings where something has just touched the water: a few at a time, each spreading and
	// fading over two seconds, at places that change every ring.
	float rings = 0.0;
	for (int i = 0; i < 3; i++) {
		float t = TIME * 0.5 + float(i) * 0.33;
		float n = floor(t);
		vec2 at = vec2(hash(vec2(n, float(i))), hash(vec2(float(i), n + 3.0))) * 24.0 - 12.0;
		float age = fract(t);
		float d = length(fract((p - at) / 24.0 + 0.5) * 24.0 - 12.0);
		rings += sin((d - age * 1.6) * 18.0) * smoothstep(0.25, 0.0, abs(d - age * 1.6)) * (1.0 - age);
	}
	vec3 n = normalize(vec3(-grad.x * 0.035 * ripple, 1.0, -grad.y * 0.035 * ripple) + vec3(rings * 0.02, 0.0, rings * 0.02));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);
	ALBEDO = mix(shallow.rgb, deep.rgb, 0.4 + 0.6 * fresnel);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.55;
	// Straight down you see into it; at a glance it is a mirror.
	ALPHA = mix(1.0 - clarity, 0.97, fresnel);
}
