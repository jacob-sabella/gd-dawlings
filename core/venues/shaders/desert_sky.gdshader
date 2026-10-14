shader_type sky;

// The desert's sky, at any of its hours. Bands from the horizon to the zenith, brighter and
// lifted toward the sun (or where it went, or where it is coming); the sun's disc when it is up;
// a moon; stars, and the Milky Way as a band of light round a great circle, clotted with star
// clouds and split along its middle by the dark rift of its dust lanes. Below the horizon the sky
// is its own reflection, dimmed: the ground hides it everywhere but in still water, which is
// where it is seen (the oasis's pool).
//
// No TIME: the sky is still, so its radiance is worked out once rather than every frame.

uniform vec4 zenith : source_color = vec4(0.01, 0.012, 0.03, 1.0);
uniform vec4 upper : source_color = vec4(0.02, 0.025, 0.06, 1.0);
uniform vec4 horizon : source_color = vec4(0.05, 0.05, 0.09, 1.0);
// The glow toward the sun, on the horizon and up from it.
uniform vec4 glow_colour : source_color = vec4(1.0, 0.6, 0.3, 1.0);
uniform float glow = 0.0;
uniform vec3 sun_dir = vec3(0.0, -0.2, -1.0);
uniform float sun_radius = 0.0;
uniform vec4 sun_colour : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform vec3 moon_dir = vec3(0.3, 0.5, -0.8);
uniform float moon_radius = 0.0;
// How much of the moon's disc is lit: 1 full, small a thin crescent (lit on the sun's side).
uniform float moon_phase = 1.0;
uniform float stars = 0.0;
// The Milky Way: how bright, the normal of its great circle, and its colour.
uniform float milky_way = 0.0;
uniform vec3 galaxy_pole = vec3(0.9, 0.25, 0.35);
uniform vec4 galaxy_colour : source_color = vec4(0.75, 0.72, 0.85, 1.0);
// The heart of the galaxy, a brighter bulge on the band, in this direction.
uniform vec3 galaxy_core = vec3(-0.2, 0.35, -0.9);
// How bright the sky below the horizon is, as a reflection of the sky above it.
uniform float mirror = 0.55;
uniform float energy = 1.0;

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
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

// One layer of stars: each cell of a grid over the sphere holds at most one, at a random spot in
// it; `keep` is the share of cells that have one. Returns brightness, and its tint in `tint`.
float star_layer(vec3 d, float scale, float keep, out vec3 tint) {
	vec3 p = d * scale;
	vec3 cell = floor(p);
	float r = hash3(cell + 11.0);
	tint = mix(vec3(1.0, 0.8, 0.62), vec3(0.72, 0.82, 1.0), hash3(cell + 5.3));
	if (r < 1.0 - keep) {
		return 0.0;
	}
	vec3 at = cell + vec3(hash3(cell + 1.7), hash3(cell + 2.9), hash3(cell + 4.1));
	float dist = length(p - at);
	return smoothstep(0.16, 0.0, dist) * (0.4 + 0.6 * hash3(cell + 8.8));
}

vec3 above(vec3 d) {
	float h = max(d.y, 0.0);
	vec3 sd = normalize(sun_dir);
	// How much this way faces the sun, round the horizon and overall.
	float toward = clamp(dot(normalize(d.xz + 1e-5), normalize(sd.xz + 1e-5)) * 0.5 + 0.5, 0.0, 1.0);
	float lift = mix(0.7, 1.5, toward * glow);
	vec3 col = mix(horizon.rgb, upper.rgb, smoothstep(0.0, 0.22 * lift, h));
	col = mix(col, zenith.rgb, smoothstep(0.18 * lift, 0.85, h));
	// The glow: a wide band on the horizon toward the sun, fading up and round.
	float band = pow(toward, 4.0) * exp(-h * 5.0 / lift);
	col += glow_colour.rgb * band * glow;
	// A softer warmth all along the horizon, so the far side is not dead.
	col += glow_colour.rgb * exp(-h * 9.0) * glow * 0.12;
	float ang = acos(clamp(dot(d, sd), -1.0, 1.0));
	col += glow_colour.rgb * exp(-ang * 6.0) * glow * 0.6;
	if (sun_radius > 0.0) {
		col = mix(col, sun_colour.rgb * 4.0, smoothstep(sun_radius, sun_radius * 0.85, ang));
		col += sun_colour.rgb * exp(-max(ang - sun_radius, 0.0) * 18.0) * 0.6;
	}

	// The night: the stars and the galaxy, kept out of the bright part of the sky.
	float dark = clamp(1.0 - dot(col, vec3(0.33)) * 4.0, 0.0, 1.0) * smoothstep(0.0, 0.12, h);
	if (stars > 0.0 || milky_way > 0.0) {
		vec3 n = normalize(galaxy_pole);
		float off = dot(d, n);
		// Warp the band's centre line, so it wanders a little as the real one does.
		float wander = (fbm(d * 3.0) - 0.5) * 0.12;
		float lane = off + wander;
		float band_w = 0.17;
		float in_band = exp(-pow(lane / band_w, 2.0));
		// Star clouds: clumpy brightness along the band.
		float clouds = fbm(d * 7.0 + 3.0);
		float core = exp(-pow(acos(clamp(dot(d, normalize(galaxy_core)), -1.0, 1.0)) / 0.45, 2.0));
		float light = in_band * (0.35 + 1.1 * clouds * clouds) + core * 1.1 * in_band;
		// The dark rift down the middle: dust, ragged, a little to one side.
		float rift = exp(-pow((lane - 0.025) / 0.04, 2.0)) * smoothstep(0.35, 0.65, fbm(d * 11.0 + 7.0));
		light *= 1.0 - 0.85 * rift;
		vec3 glow_mw = galaxy_colour.rgb * light * 0.09 * milky_way;
		glow_mw += vec3(1.0, 0.82, 0.62) * core * in_band * 0.05 * milky_way;
		col += glow_mw * dark;
		// Stars: thick in the band, thinner off it; a few bright ones everywhere.
		vec3 tint;
		float s = star_layer(d, 260.0, 0.05 + 0.25 * in_band * milky_way, tint);
		col += tint * s * 0.9 * stars * dark;
		s = star_layer(d, 110.0, 0.035, tint);
		col += tint * s * 2.2 * stars * dark;
		s = star_layer(d, 45.0, 0.04, tint);
		col += tint * s * 4.0 * stars * dark;
	}

	// The moon: a disc, lit on the side toward the sun, earthshine on the rest.
	if (moon_radius > 0.0) {
		vec3 md = normalize(moon_dir);
		float mang = acos(clamp(dot(d, md), -1.0, 1.0));
		if (mang < moon_radius * 1.05) {
			// Where on the disc this is, and how the light falls across it.
			vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
			vec3 up = cross(right, md);
			vec2 q = vec2(dot(d - md, right), dot(d - md, up)) / moon_radius;
			float z = sqrt(max(1.0 - dot(q, q), 0.0));
			vec3 normal = q.x * right + q.y * up + z * md;
			vec3 lit_from = normalize(mix(-md, normalize(sun_dir - md * dot(sun_dir, md)), moon_phase));
			float lit = smoothstep(-0.05, 0.1, dot(normal, lit_from));
			float maria = 0.8 + 0.2 * noise3(vec3(q * 4.0, 1.0));
			vec3 face = vec3(1.0, 0.97, 0.9) * (lit * 2.4 * maria + 0.035);
			col = mix(col, face, smoothstep(moon_radius, moon_radius * 0.93, mang));
		}
		col += vec3(0.6, 0.65, 0.8) * exp(-mang * 9.0) * 0.08 * moon_phase;
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col;
	if (d.y >= 0.0) {
		col = above(d);
	} else {
		// Below the horizon: the sky above, as still water gives it back, a little darker the
		// further down you look into it.
		col = above(vec3(d.x, -d.y, d.z)) * mirror * mix(1.0, 0.7, smoothstep(0.0, 0.6, -d.y));
	}
	COLOR = col * energy;
}
