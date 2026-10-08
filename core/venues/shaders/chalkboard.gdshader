shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// A blackboard that has been drawn on and wiped a hundred times: deep slate with the ghosts of
// old erasing swept across it in arcs. Lit, so the neon lamps land on it as pools of colour.

uniform vec4 slate : source_color = vec4(0.020, 0.028, 0.034, 1.0);
uniform vec4 dust : source_color = vec4(0.30, 0.34, 0.42, 1.0);
uniform float smudge = 0.16;
uniform float pulse = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
			mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	// Wiping strokes: noise smeared along arcs around a few centres, the way an arm swings.
	float ang = atan(p.y + 7.0, p.x - 3.0);
	float rad = length(p - vec2(3.0, -7.0));
	float sweep = fbm(vec2(ang * 3.0, rad * 0.35));
	float cloud = fbm(p * 0.18);
	float fine = noise(p * 40.0);
	float m = smoothstep(0.42, 0.85, sweep * 0.6 + cloud * 0.5) * smudge;
	vec3 c = mix(slate.rgb, dust.rgb, m + fine * 0.012);
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
