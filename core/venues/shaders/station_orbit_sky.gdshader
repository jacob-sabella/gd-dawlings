shader_type sky;

// Orbit, with the sun up: the station's day and its sunrise (space_sky.gdshader is its night).
//
// The planet is traced as a sphere from the eye, as at night, and the stars and the surface turn
// past by `spin`. By day the side below is lit: deep blue oceans going turquoise on the shelves,
// continents in greens and ochres with white ice at the poles, the sun's glint smeared across
// the water, and clouds over all of it -- sheets and streets of them, wound into storms -- each
// laying its shadow a little off itself. At `dawn` the sun is at the limb: the planet below is
// still night, cities lit, but the air round its edge is a thin layered band -- red at the
// ground, orange, gold, white, then blue into black -- blazing toward the sun and fading away
// round the curve from it, with the sun itself a white bead on the band and a streak across.
// No TIME: the sky is redrawn only when `spin` moves.

uniform vec3 centre = vec3(0.0, -2900.0, -1700.0);
uniform float radius = 3000.0;
uniform float air = 60.0;
uniform vec3 sun_dir = vec3(-0.75, 0.5, -0.45);
uniform float spin = 0.0;
// 0 for day, 1 for the sunrise: how much of the planet below is night, and how hard the limb
// burns.
uniform float dawn = 0.0;
uniform float stars = 0.25;
uniform float energy = 1.0;

vec3 turned(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

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

float fbm(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// A storm: the point `g` wound round the storm's eye at `eye`, more the nearer it is, so the
// cloud noise read through it spirals in.
vec3 wind(vec3 g, vec3 eye, float size, float turns) {
	vec3 e = normalize(eye);
	float d = distance(g, e);
	float k = turns * exp(-d / size);
	// Rotate g about the eye's axis by k.
	float c = cos(k);
	float s = sin(k);
	return g * c + cross(e, g) * s + e * dot(e, g) * (1.0 - c);
}

// How much cloud there is at `g` on the turning sphere.
float clouds_at(vec3 g) {
	// Storms, and the bands of the trades: latitude decides how the clouds run.
	// Two storms where the orbit starts out over them, more round the rest of the world.
	g = wind(g, vec3(0.16, 0.82, 0.52), 0.05, 7.0);
	g = wind(g, vec3(-0.22, 0.7, 0.66), 0.04, -6.0);
	g = wind(g, vec3(0.25, -0.5, 0.8), 0.05, 6.0);
	g = wind(g, vec3(-0.2, 0.2, -0.95), 0.05, -7.0);
	vec3 warp = vec3(fbm(g * 9.0, 4), fbm(g * 9.0 + vec3(5.2), 4), fbm(g * 9.0 + vec3(1.7, 9.2, 3.3), 4));
	// Drawn out along the lines of latitude (the axis is x), the way the trade winds lay them.
	vec3 q = g * vec3(34.0, 20.0, 20.0) + warp * 2.6;
	float c = fbm(q, 5);
	// Clear over the subtropics, cloudier at the equator and in the storm tracks.
	float lat = abs(g.x);
	float cover = 0.46 + 0.08 * smoothstep(0.15, 0.0, lat) - 0.07 * smoothstep(0.15, 0.35, lat) * smoothstep(0.6, 0.35, lat);
	return smoothstep(cover, cover + 0.2, c);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	vec3 col = vec3(0.0);

	// The stars, faint beside the sun-lit planet.
	vec3 sd_sky = turned(d, spin);
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 160.0 : 60.0;
		vec2 uv = vec2(atan(sd_sky.x, sd_sky.z), asin(clamp(sd_sky.y, -1.0, 1.0))) * scale;
		vec2 cell = floor(uv);
		float r = hash2(cell + float(layer) * 31.0);
		if (r > (layer == 0 ? 0.94 : 0.985)) {
			vec2 at = vec2(hash2(cell + 7.1), hash2(cell + 3.3));
			float s = smoothstep(0.09, 0.0, length(fract(uv) - at));
			vec3 tint = mix(vec3(1.0, 0.82, 0.65), vec3(0.7, 0.8, 1.0), hash2(cell + 5.7));
			col += tint * s * (layer == 0 ? 0.7 : 1.6) * stars;
		}
	}

	vec3 oc = -centre;
	float b = dot(oc, d);
	float c = dot(oc, oc) - radius * radius;
	float disc = b * b - c;
	float closest = length(oc - d * b);
	bool ground = disc > 0.0 && -b - sqrt(disc) > 0.0;
	if (ground) {
		float t = -b - sqrt(disc);
		vec3 n = normalize(d * t - centre);
		float light = dot(n, sd);
		vec3 g = turned(n, spin);
		float lit = smoothstep(-0.08, 0.2, light);
		// The land: continents from warped noise, a coast, and what grows by latitude.
		vec3 w = vec3(fbm(g * 5.0, 4), fbm(g * 5.0 + vec3(7.1), 4), fbm(g * 5.0 + vec3(3.9, 1.3, 8.8), 4));
		float h = fbm(g * 9.0 + w * 1.6, 6);
		float is_land = smoothstep(0.58, 0.59, h);
		float shelf = smoothstep(0.52, 0.58, h) * (1.0 - is_land);
		// The planet's axis is the orbit's (x): the station passes over the tropics and the
		// ice is off to either side.
		float lat = abs(g.x);
		float dry = smoothstep(0.45, 0.65, fbm(g * 16.0 + vec3(2.0), 4)) * smoothstep(0.55, 0.2, abs(lat - 0.33) * 2.0);
		float detail = fbm(g * 90.0, 4);
		vec3 green = mix(vec3(0.06, 0.14, 0.05), vec3(0.12, 0.17, 0.07), detail);
		vec3 desert = mix(vec3(0.42, 0.3, 0.17), vec3(0.55, 0.42, 0.26), detail);
		vec3 land = mix(green, desert, dry);
		// High ground goes brown and grey.
		land = mix(land, vec3(0.24, 0.22, 0.2), smoothstep(0.68, 0.74, h));
		vec3 ocean = mix(vec3(0.01, 0.04, 0.13), vec3(0.03, 0.2, 0.27), shelf);
		vec3 surface = mix(ocean, land, is_land);
		// Ice at the poles.
		float ice = smoothstep(0.82, 0.86, lat + (fbm(g * 12.0, 3) - 0.5) * 0.12);
		surface = mix(surface, vec3(0.8, 0.85, 0.9), ice);
		// Clouds, and their shadows: the cloud cover read again a step toward the sun.
		float cl = clouds_at(g);
		vec3 toward_sun = normalize(sd - n * dot(sd, n));
		float shade = clouds_at(turned(normalize(n + toward_sun * 0.006), spin));
		surface *= 1.0 - shade * 0.45;
		// The sun's glint on open water, smeared by the waves.
		vec3 refl = reflect(d, n);
		float glint = pow(max(dot(refl, sd), 0.0), 60.0) * 2.5 + pow(max(dot(refl, sd), 0.0), 8.0) * 0.12;
		surface += vec3(1.0, 0.95, 0.85) * glint * (1.0 - is_land) * (1.0 - ice) * (1.0 - cl);
		vec3 cloud_col = mix(vec3(0.5, 0.54, 0.6), vec3(0.85, 0.87, 0.9), smoothstep(0.0, 0.6, cl));
		surface = mix(surface, cloud_col, cl * 0.92);
		vec3 dayside = surface * lit * 0.85;
		// The terminator's own colour: where the sun is low on the ground, the light is red.
		dayside *= mix(vec3(1.0, 0.55, 0.3), vec3(1.0), smoothstep(0.0, 0.3, light));
		// The night: cities, where it is dark.
		float settled = smoothstep(0.45, 0.7, fbm(g * 18.0 + vec3(9.0), 4));
		float town = step(1.0 - 0.06 * settled, hash3(floor(g * 2200.0))) * is_land * (1.0 - cl * 0.8);
		vec3 nightside = vec3(1.0, 0.68, 0.32) * town * 0.7 * (1.0 - smoothstep(-0.12, 0.02, light));
		// Through more air toward the limb: haze, blue in the light, the dawn's colours at its edge.
		float rim = pow(1.0 - clamp(dot(n, -d), 0.0, 1.0), 5.0);
		vec3 haze = vec3(0.3, 0.52, 1.0) * rim * (0.1 + lit * 0.55);
		float edge_sun = pow(max(dot(normalize(n - d * dot(n, d)), sd), 0.0), 3.0);
		haze += vec3(1.0, 0.4, 0.15) * pow(rim, 2.0) * edge_sun * dawn * 0.8;
		col = dayside + nightside + haze;
	} else if (closest < radius + air * 4.0 && b < 0.0) {
		// The air beyond the limb, in layers by height: by day a soft blue line, at dawn a
		// rainbow -- red low, then orange, gold, white and blue -- strongest toward the sun.
		float above = max(closest - radius, 0.0) / air;
		vec3 limb = normalize(oc - d * b);
		float sunward = max(dot(limb, sd), 0.0);
		vec3 day_air = vec3(0.35, 0.6, 1.0) * exp(-above * 1.4) * (0.35 + 1.1 * smoothstep(-0.2, 0.6, dot(limb, sd)));
		float h = above;
		vec3 band = vec3(0.9, 0.12, 0.03) * exp(-pow((h - 0.05) / 0.12, 2.0))
				+ vec3(1.0, 0.42, 0.06) * exp(-pow((h - 0.22) / 0.14, 2.0))
				+ vec3(1.0, 0.8, 0.35) * exp(-pow((h - 0.42) / 0.16, 2.0))
				+ vec3(0.85, 0.9, 1.0) * exp(-pow((h - 0.65) / 0.2, 2.0)) * 0.7
				+ vec3(0.15, 0.35, 1.0) * exp(-pow((h - 1.1) / 0.45, 2.0)) * 0.8
				+ vec3(0.04, 0.06, 0.25) * exp(-h * 0.6) * 0.5;
		float blaze = 0.12 + 2.6 * pow(sunward, 6.0) + 0.6 * pow(sunward, 1.5);
		col += mix(day_air, band * blaze, dawn);
	}

	// The sun: a disc, white-hot, with a glow round it, wherever the planet does not cover it.
	// At dawn a flat streak across it, the way the bead of a sunrise flares.
	float sun = dot(d, sd);
	float bead = smoothstep(0.99996, 0.99999, sun);
	float halo = pow(max(sun, 0.0), 900.0) * 1.5 + pow(max(sun, 0.0), 60.0) * 0.12 * (1.0 + dawn);
	vec3 across = normalize(cross(sd, vec3(0.0, 1.0, 0.0)));
	vec3 upward = cross(across, sd);
	float streak = exp(-pow(dot(d, upward) * 140.0, 2.0)) * pow(max(sun, 0.0), 30.0) * 1.2 * dawn;
	if (!ground) {
		col += vec3(1.0, 0.97, 0.9) * bead * 30.0;
	}
	col += vec3(1.0, 0.86, 0.62) * (halo + streak) * (ground ? 0.35 : 1.0);
	COLOR = col * energy;
}
