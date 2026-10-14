shader_type spatial;

// A festival field: grass in world space, uneven, gone straw-coloured in patches, and worn to
// bare earth down the middle where the crowd stands and along the walk out to the front-of-house
// tent. One shader, no texture: the field is a few hundred metres across.

uniform vec4 grass_a : source_color = vec4(0.16, 0.24, 0.08, 1.0);
uniform vec4 grass_b : source_color = vec4(0.26, 0.31, 0.12, 1.0);
uniform vec4 straw : source_color = vec4(0.42, 0.38, 0.2, 1.0);
uniform vec4 earth : source_color = vec4(0.22, 0.17, 0.11, 1.0);
// Where the crowd's floor is worn (x half-width, z from, z to), in world space.
uniform vec4 worn = vec4(16.0, -8.0, -60.0, 0.0);
uniform float brightness = 1.0;
// How worn the crowd's floor is: 1 after a weekend of it.
uniform float wear = 1.0;

varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float big = fbm(p * 0.05);
	float fine = noise(p * 3.0);
	vec3 col = mix(grass_a.rgb, grass_b.rgb, smoothstep(0.3, 0.7, big));
	col = mix(col, straw.rgb, smoothstep(0.58, 0.75, fbm(p * 0.09 + 7.0)) * 0.7);
	// Trodden: inside the crowd's box, more so toward the stage and the middle.
	float inside = smoothstep(worn.x, worn.x * 0.6, abs(p.x)) * smoothstep(worn.z - 4.0, worn.z + 6.0, p.y)
			* smoothstep(worn.y + 1.0, worn.y - 3.0, p.y);
	// The walk out to the desk tent: a strip down the middle.
	float walk = smoothstep(2.2, 1.2, abs(p.x)) * step(p.y, worn.y);
	float worn_by = clamp(max(inside * 0.75 * wear, walk * 0.6) * (0.6 + 0.6 * fbm(p * 0.4)), 0.0, 1.0);
	col = mix(col, earth.rgb, worn_by);
	col *= 0.85 + 0.3 * fine;
	ALBEDO = col * brightness;
	ROUGHNESS = 0.95;
}
