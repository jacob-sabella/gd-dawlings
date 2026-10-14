shader_type spatial;

// The classroom's desk globe: an old school map, its seas a faded teal and its land a worn
// parchment with darker coasts, ruled in a faint graticule, under a coat of varnish. The land is
// noise on the sphere, not a real atlas: from across a room a globe is two colours and a shine.

uniform vec4 sea : source_color = vec4(0.16, 0.34, 0.38, 1.0);
uniform vec4 shallows : source_color = vec4(0.30, 0.50, 0.50, 1.0);
uniform vec4 land : source_color = vec4(0.72, 0.62, 0.42, 1.0);
uniform vec4 hills : source_color = vec4(0.55, 0.42, 0.26, 1.0);

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float lon = UV.x * 6.2831853;
	float lat = (0.5 - UV.y) * 3.1415927;
	vec3 s = vec3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon));
	float h = fbm3(s * 2.2 + vec3(4.0, 1.0, 7.0));
	float is_land = smoothstep(0.515, 0.53, h);
	float coast = smoothstep(0.50, 0.515, h) * (1.0 - is_land);
	vec3 c = mix(sea.rgb, shallows.rgb, coast);
	c = mix(c, mix(land.rgb, hills.rgb, smoothstep(0.56, 0.68, h)), is_land);
	// The coast inked in.
	c *= 1.0 - 0.45 * (smoothstep(0.51, 0.522, h) - smoothstep(0.522, 0.535, h));
	// The ice caps, white.
	c = mix(c, vec3(0.86, 0.86, 0.82), smoothstep(1.25, 1.4, abs(lat)));
	// A graticule every fifteen degrees, faint.
	float g = min(abs(fract(lon / 0.2617994 + 0.5) - 0.5), abs(fract(lat / 0.2617994 + 0.5) - 0.5));
	c *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.04, g));
	ALBEDO = c;
	ROUGHNESS = 0.32;
	SPECULAR = 0.6;
}
