shader_type sky;

// Orbit. Stars, thick and steady (no air to make them twinkle), a faint band of the galaxy, and
// a planet below and in front: its night side turned toward the station, cities lit on the
// land, a thin crescent of day along one edge and the atmosphere a blue line round the limb.
// The planet is traced as a sphere from the eye, so the window shows its curve and the glass
// floor looks straight down onto it. No TIME here: the sky is drawn once, not every frame.

// The planet, in units where its radius is `radius`: its centre relative to the eye.
uniform vec3 centre = vec3(0.0, -2900.0, -1700.0);
uniform float radius = 3000.0;
// How thick the air is, in the same units.
uniform float air = 60.0;
uniform vec3 sun_dir = vec3(-0.85, 0.15, -0.5);
uniform vec4 ocean : source_color = vec4(0.02, 0.06, 0.14, 1.0);
uniform vec4 land : source_color = vec4(0.12, 0.12, 0.07, 1.0);
uniform vec4 cloud : source_color = vec4(0.85, 0.88, 0.92, 1.0);
uniform vec4 atmosphere : source_color = vec4(0.3, 0.55, 1.0, 1.0);
uniform vec4 city : source_color = vec4(1.0, 0.68, 0.32, 1.0);
uniform float day = 1.0;
uniform float stars = 1.0;

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

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	vec3 col = vec3(0.0);

	// The stars: two layers, many faint and a few bright, some warm and some blue.
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 160.0 : 60.0;
		vec2 uv = vec2(atan(d.x, d.z), asin(clamp(d.y, -1.0, 1.0))) * scale;
		vec2 cell = floor(uv);
		float r = hash2(cell + float(layer) * 31.0);
		float keep = layer == 0 ? 0.94 : 0.985;
		if (r > keep) {
			vec2 at = vec2(hash2(cell + 7.1), hash2(cell + 3.3));
			float s = smoothstep(0.09, 0.0, length(fract(uv) - at));
			vec3 tint = mix(vec3(1.0, 0.82, 0.65), vec3(0.7, 0.8, 1.0), hash2(cell + 5.7));
			col += tint * s * (layer == 0 ? 0.7 : 1.6) * stars;
		}
	}
	// The galaxy: a soft band across the sky, mottled.
	vec3 band_axis = normalize(vec3(0.3, 0.85, 0.42));
	float band = exp(-pow(dot(d, band_axis) * 4.0, 2.0));
	col += vec3(0.03, 0.028, 0.04) * band * (0.4 + fbm(d * 6.0)) * stars;

	// The planet: where the ray from the eye meets the sphere, if it does.
	vec3 oc = -centre;
	float b = dot(oc, d);
	float c = dot(oc, oc) - radius * radius;
	float disc = b * b - c;
	// How close the ray passes to the centre, for the air round the limb.
	float closest = length(oc - d * b);
	if (disc > 0.0 && -b - sqrt(disc) > 0.0) {
		float t = -b - sqrt(disc);
		vec3 n = normalize(d * t - centre);
		float light = dot(n, sd);
		float lit = smoothstep(-0.05, 0.25, light) * day;
		// Continents and oceans from noise on the sphere, clouds over them.
		float h = fbm(n * 7.0);
		float is_land = smoothstep(0.52, 0.56, h);
		vec3 ground = mix(ocean.rgb, land.rgb * (0.7 + fbm(n * 30.0) * 0.6), is_land);
		float clouds = smoothstep(0.5, 0.75, fbm(n * 11.0 + vec3(4.0)));
		vec3 surface = mix(ground, cloud.rgb, clouds * 0.85);
		vec3 dayside = surface * lit * 1.4;
		// The night side: cities on the land, dimmed under cloud.
		// Each town a point: a fine grid of cells on the sphere, a few lit, more where the
		// coarse noise says the land is settled.
		float settled = smoothstep(0.45, 0.7, fbm(n * 18.0 + vec3(9.0)));
		float town = step(1.0 - 0.06 * settled, hash3(floor(n * 2200.0))) * is_land * (1.0 - clouds * 0.8);
		vec3 nightside = city.rgb * town * 0.7 * (1.0 - smoothstep(-0.1, 0.05, light));
		// Looking through more air toward the limb: the surface goes blue.
		float rim = pow(1.0 - clamp(dot(n, -d), 0.0, 1.0), 3.0);
		col = dayside + nightside + atmosphere.rgb * rim * (0.15 + lit * 0.8);
	} else if (closest < radius + air * 3.0 && b < 0.0) {
		// The air beyond the limb: a thin glowing line, brightest where the sun is behind it.
		float above = (closest - radius) / air;
		vec3 limb = normalize(oc - d * b);
		float sunward = smoothstep(-0.2, 0.5, dot(limb, sd));
		col += atmosphere.rgb * exp(-max(above, 0.0) * 1.6) * (0.25 + sunward * 1.2 * day);
	}
	COLOR = col;
}
