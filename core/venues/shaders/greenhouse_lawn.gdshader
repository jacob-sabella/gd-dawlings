shader_type spatial;

// The garden's lawns: close-mown grass in the broad stripes the mower leaves, a paler and a
// darker green turn about, patched with clover and the odd worn place, and going a deeper,
// glossier green when it is wet. World space, so it runs on under everything without UVs.

uniform vec4 light_green : source_color = vec4(0.27, 0.42, 0.15, 1.0);
uniform vec4 dark_green : source_color = vec4(0.17, 0.3, 0.1, 1.0);
uniform vec4 worn : source_color = vec4(0.38, 0.36, 0.2, 1.0);
uniform float stripe = 1.4;
uniform float wet = 0.0;
uniform float dew = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = wpos.xz;
	float s = step(0.5, fract(p.x / (stripe * 2.0)));
	vec3 col = mix(dark_green.rgb, light_green.rgb, 0.35 + 0.4 * s);
	float n = vnoise(p * 0.3) * 0.6 + vnoise(p * 1.7) * 0.3 + vnoise(p * 9.0) * 0.1;
	col *= 0.8 + 0.4 * n;
	col = mix(col, worn.rgb, smoothstep(0.72, 0.9, vnoise(p * 0.12 + 4.0)) * 0.5);
	// The blades: a fine speckle so it is grass up close and not felt.
	col *= 0.85 + 0.3 * hash(floor(p * 60.0));
	col *= mix(1.0, 0.7, wet);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.45, max(wet, dew * 0.6));
	SPECULAR = 0.3 + 0.3 * dew * step(0.97, hash(floor(p * 90.0)));
}
