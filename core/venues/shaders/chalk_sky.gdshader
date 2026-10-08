shader_type sky;

// The far side of the chalkboard. Dark, never black: a slate dome with clouds of half-erased
// chalk drifting across it and the odd hard white speck someone dotted on and forgot.

uniform vec4 slate : source_color = vec4(0.012, 0.016, 0.030, 1.0);
uniform vec4 low : source_color = vec4(0.05, 0.03, 0.10, 1.0);
uniform vec4 smear : source_color = vec4(0.20, 0.16, 0.34, 1.0);
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
		p = p * 2.1 + vec2(3.1, 1.3);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	vec2 uv = vec2(atan(d.x, -d.z) * 1.6, d.y * 3.0);
	vec3 c = mix(low.rgb, slate.rgb, smoothstep(-0.05, 0.5, d.y));
	float clouds = smoothstep(0.5, 0.85, fbm(uv * 1.3 + vec2(TIME * 0.004, 0.0)));
	c = mix(c, smear.rgb, clouds * 0.35 * (1.0 + pulse * 0.5));
	vec2 cell = floor(uv * 60.0);
	float star = step(0.9975, hash(cell)) * smoothstep(0.0, 0.2, d.y);
	c += vec3(0.9, 0.95, 1.0) * star * (0.6 + 0.4 * sin(TIME * 2.0 + hash(cell + 3.0) * 30.0));
	COLOR = c;
}
