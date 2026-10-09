shader_type sky;

// The sky a quarter of an hour after sunset: the sun gone under the horizon in front, a band of
// orange where it went, rose and violet above that, deep blue overhead with the first stars out,
// and the haze over the city a dull rust below the horizon line.

uniform vec4 zenith : source_color = vec4(0.03, 0.04, 0.12, 1.0);
uniform vec4 upper : source_color = vec4(0.16, 0.12, 0.3, 1.0);
uniform vec4 rose : source_color = vec4(0.55, 0.24, 0.32, 1.0);
uniform vec4 horizon : source_color = vec4(1.0, 0.48, 0.2, 1.0);
uniform vec4 haze : source_color = vec4(0.16, 0.09, 0.1, 1.0);
// Where the sun went down: the glow is strongest toward it and fades round the horizon.
uniform vec3 sun_dir = vec3(0.0, -0.06, -1.0);
uniform float energy = 1.0;
// The sun's disc, when it is still up (golden hour): its angular radius, 0 for none.
uniform float sun_radius = 0.0;
uniform vec4 sun_colour : source_color = vec4(1.0, 0.8, 0.5, 1.0);
// How many stars are out, and how bright: a few at dusk, all of them at night.
uniform float stars = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 sd = normalize(sun_dir);
	// How near the sunset this way is, round the horizon: 1 toward it, 0 behind.
	float toward = clamp(dot(normalize(d.xz + 1e-5), normalize(sd.xz)) * 0.5 + 0.5, 0.0, 1.0);
	float glow = pow(toward, 3.0);
	// The bands, lifted higher in the sun's direction and pressed down behind.
	float lift = mix(0.55, 1.3, glow);
	vec3 col = mix(horizon.rgb * mix(0.35, 1.0, glow), rose.rgb * mix(0.5, 1.0, glow),
			smoothstep(0.0, 0.1 * lift, h));
	col = mix(col, upper.rgb, smoothstep(0.08 * lift, 0.3 * lift, h));
	col = mix(col, zenith.rgb, smoothstep(0.3, 0.85, h));
	// Under the horizon line: the haze over the city, a little warmer toward the sunset.
	// It starts from the horizon's own colour, so there is no line where the one meets the other.
	vec3 at_horizon = horizon.rgb * mix(0.35, 1.0, glow);
	col = h < 0.0 ? mix(at_horizon, haze.rgb, smoothstep(0.0, -0.06, h)) : col;
	// The afterglow right where the sun went: a soft bright spot sitting on the horizon.
	float ang = acos(clamp(dot(d, sd), -1.0, 1.0));
	col += horizon.rgb * exp(-ang * 7.0) * 0.45 * smoothstep(-0.05, 0.0, h);

	// The first stars, only high and away from the glow.
	vec2 uv = vec2(atan(d.x, d.z), asin(clamp(h, -1.0, 1.0))) * 80.0;
	vec2 cell = floor(uv);
	float r = hash(cell);
	if (r > 1.0 - 0.008 * stars && h > 0.25 - 0.15 * step(1.5, stars)) {
		vec2 at = vec2(hash(cell + 7.1), hash(cell + 3.3));
		float s = smoothstep(0.07, 0.0, length(fract(uv) - at));
		float twinkle = 0.7 + 0.3 * sin(TIME * (1.0 + r * 3.0) + r * 40.0);
		col += vec3(0.9, 0.88, 1.0) * s * twinkle * smoothstep(0.1, 0.6, h) * (1.0 - glow * 0.7) * 1.4;
	}
	// The sun itself, a soft-edged disc, with a halo round it.
	if (sun_radius > 0.0) {
		col = mix(col, sun_colour.rgb * 3.0, smoothstep(sun_radius, sun_radius * 0.8, ang));
		col += sun_colour.rgb * exp(-max(ang - sun_radius, 0.0) * 14.0) * 0.5;
	}
	COLOR = col * energy;
}
