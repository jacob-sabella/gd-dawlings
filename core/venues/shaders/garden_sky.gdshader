shader_type sky;

// The temple garden's sky: a gradient from the horizon up, the sun's glow (and its disc when it
// is up), soft clouds, the first stars at dusk, and round the horizon three ranges of hills one
// behind another, each paler with the mist between them, the way an ink painting does distance.
// The nearer hills are real ground (GardenVenue); these are the ones past them.

uniform vec4 zenith : source_color = vec4(0.3, 0.45, 0.7, 1.0);
uniform vec4 upper : source_color = vec4(0.55, 0.65, 0.8, 1.0);
uniform vec4 horizon : source_color = vec4(0.85, 0.82, 0.78, 1.0);
// The air down among the far hills: what each range fades into toward its foot.
uniform vec4 mist : source_color = vec4(0.75, 0.75, 0.75, 1.0);
// The nearest range's colour; the far ones are this, drowned in more of the mist.
uniform vec4 hills : source_color = vec4(0.2, 0.26, 0.24, 1.0);
uniform vec3 sun_dir = vec3(0.3, 0.3, -1.0);
uniform vec4 sun_colour : source_color = vec4(1.0, 0.9, 0.75, 1.0);
// The sun's disc (angular radius, 0 for none), and how far its glow reaches round the sky.
uniform float sun_radius = 0.02;
uniform float glow = 0.6;
uniform vec4 cloud_colour : source_color = vec4(1.0, 0.97, 0.94, 1.0);
uniform float clouds = 0.5;
uniform float stars = 0.0;
uniform float energy = 1.0;

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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

// A range of hills' skyline, as an elevation (sin of the angle above the horizon) by azimuth.
float ridge(float az, float seed, float base, float amp) {
	// Round the circle without a seam: sample the noise on a circle, not along a line.
	vec2 p = vec2(cos(az), sin(az)) * (2.2 + seed * 0.4) + vec2(seed * 7.1, seed * 3.3);
	float n = fbm(p);
	float peaks = pow(fbm(p * 0.6 + 3.0), 2.0);
	return base + amp * (n * 0.7 + peaks * 0.9);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 sd = normalize(sun_dir);
	float ang = acos(clamp(dot(d, sd), -1.0, 1.0));
	float toward = clamp(dot(normalize(d.xz + 1e-5), normalize(sd.xz + 1e-5)) * 0.5 + 0.5, 0.0, 1.0);

	vec3 col = mix(horizon.rgb, upper.rgb, smoothstep(0.0, 0.25, h));
	col = mix(col, zenith.rgb, smoothstep(0.2, 0.9, h));
	// The sun's side of the sky warmer and brighter, most of all low down.
	col += sun_colour.rgb * glow * pow(toward, 4.0) * exp(-max(h, 0.0) * 4.0) * 0.35;
	col += sun_colour.rgb * glow * exp(-ang * 5.0) * 0.4;

	// Stars, for the dusk: only high, only where the glow is not.
	vec2 suv = vec2(atan(d.x, d.z), asin(clamp(h, -1.0, 1.0))) * 90.0;
	vec2 cell = floor(suv);
	float r = hash(cell);
	if (stars > 0.0 && r > 1.0 - 0.01 * stars && h > 0.2) {
		vec2 at = vec2(hash(cell + 7.1), hash(cell + 3.3));
		float s = smoothstep(0.08, 0.0, length(fract(suv) - at));
		col += vec3(0.9, 0.9, 1.0) * s * (0.7 + 0.3 * sin(TIME * (1.0 + r * 3.0) + r * 40.0)) * smoothstep(0.2, 0.6, h)
				* stars;
	}

	// The sun's disc and a halo round it.
	if (sun_radius > 0.0) {
		col = mix(col, sun_colour.rgb * 2.6, smoothstep(sun_radius, sun_radius * 0.75, ang));
	}

	// Clouds: soft, drifting very slowly, flattened into a layer overhead.
	if (h > 0.0 && clouds > 0.0) {
		vec2 cp = d.xz / (h + 0.12) * 1.3 + vec2(TIME * 0.004, TIME * 0.0015);
		float c = fbm(cp);
		float cover = smoothstep(0.62 - clouds * 0.3, 0.95, c) * smoothstep(0.0, 0.18, h);
		// Lit from the sun's side, a little greyer underneath.
		vec3 lit = mix(cloud_colour.rgb * 0.78, cloud_colour.rgb, toward);
		lit += sun_colour.rgb * exp(-ang * 3.0) * 0.4;
		col = mix(col, lit, cover * 0.85);
	}

	// The far hills, three ranges, the furthest first, each laid over the last: the nearer, the
	// darker and the more of its own colour; mist pooling toward the foot of each.
	float az = atan(d.x, -d.z);
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		// High enough that the far ones stand over the wooded hills round the garden.
		float top = ridge(az, 3.0 - fk, 0.12 - fk * 0.035, 0.15 - fk * 0.04);
		if (h < top) {
			float far = 1.0 - fk / 2.0;
			vec3 hill = mix(hills.rgb, mist.rgb, 0.25 + far * 0.55);
			// Toward its foot the range goes into the mist in the valley before it.
			float sink = smoothstep(top, top - 0.06 - fk * 0.02, h);
			hill = mix(hill, mist.rgb, sink * (0.55 - fk * 0.12));
			// The sun's side of each range a little lit.
			hill += sun_colour.rgb * pow(toward, 6.0) * 0.06 * glow;
			col = hill;
		}
	}
	// Under everything, the haze the near ground stands in.
	col = h < -0.02 ? mix(col, mist.rgb * 0.7, smoothstep(-0.02, -0.2, h)) : col;
	COLOR = col * energy;
}
