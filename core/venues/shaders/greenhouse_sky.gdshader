shader_type sky;

// The sky over the botanical garden, in all three of the glasshouse's weathers: a soft morning
// with a low sun and a few high clouds, an afternoon gone grey with rain, and a clear night with
// the moon high and the stars out. Clouds are drawn on a plane overhead (fbm, drifting), so they
// crowd toward the horizon the way real ones do.

uniform vec4 zenith : source_color = vec4(0.3, 0.48, 0.75, 1.0);
uniform vec4 horizon : source_color = vec4(0.85, 0.82, 0.74, 1.0);
// Under the horizon: what the garden's haze looks like where the ground does not reach.
uniform vec4 below : source_color = vec4(0.4, 0.42, 0.36, 1.0);
uniform vec3 sun_dir = vec3(-0.5, 0.3, -0.8);
uniform vec4 sun_colour : source_color = vec4(1.0, 0.85, 0.62, 1.0);
// The disc's angular radius (0 for none) and how far its glow reaches into the haze.
uniform float sun_radius = 0.0;
uniform float sun_glow = 0.0;
// The moon: where, how big, and its light.
uniform vec3 moon_dir = vec3(0.35, 0.75, -0.55);
uniform float moon_radius = 0.0;
uniform vec4 moon_colour : source_color = vec4(0.9, 0.93, 1.0, 1.0);
uniform float stars = 0.0;
// How much of the sky the clouds cover (0 clear, 1 overcast), their lit and shaded colours, and
// how fast they go.
uniform float cover = 0.3;
uniform vec4 cloud_lit : source_color = vec4(1.0, 0.96, 0.9, 1.0);
uniform vec4 cloud_dark : source_color = vec4(0.62, 0.64, 0.7, 1.0);
uniform float drift = 0.004;
uniform float energy = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
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

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon.rgb, zenith.rgb, smoothstep(-0.02, 0.6, h));
	vec3 sd = normalize(sun_dir);
	float sun_ang = acos(clamp(dot(d, sd), -1.0, 1.0));
	// The haze is brighter toward the sun.
	col += sun_colour.rgb * sun_glow * exp(-sun_ang * 2.5) * smoothstep(-0.1, 0.2, h + 0.1);

	// Stars, then the moon over them.
	vec2 suv = vec2(atan(d.x, d.z), asin(clamp(h, -1.0, 1.0))) * 90.0;
	vec2 cell = floor(suv);
	float r = hash(cell);
	if (stars > 0.0 && r > 1.0 - 0.01 * stars && h > 0.05) {
		vec2 at = vec2(hash(cell + 7.1), hash(cell + 3.3));
		float s = smoothstep(0.08, 0.0, length(fract(suv) - at));
		float twinkle = 0.7 + 0.3 * sin(TIME * (1.0 + r * 3.0) + r * 40.0);
		col += vec3(0.85, 0.88, 1.0) * s * twinkle * smoothstep(0.05, 0.4, h) * 1.2;
	}
	vec3 md = normalize(moon_dir);
	float moon_ang = acos(clamp(dot(d, md), -1.0, 1.0));
	if (moon_radius > 0.0) {
		// The maria: darker patches on the disc, from noise in the disc's own plane.
		vec3 mside = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
		vec3 mup = cross(mside, md);
		vec2 m = vec2(dot(d, mside), dot(d, mup)) / moon_radius;
		float maria = smoothstep(0.45, 0.7, fbm(m * 2.2 + 3.0)) * 0.35;
		float disc = smoothstep(moon_radius, moon_radius * 0.9, moon_ang);
		col = mix(col, moon_colour.rgb * (2.2 - maria * 2.0), disc);
		col += moon_colour.rgb * exp(-max(moon_ang - moon_radius, 0.0) * 9.0) * 0.12;
	}
	if (sun_radius > 0.0) {
		col = mix(col, sun_colour.rgb * 4.0, smoothstep(sun_radius, sun_radius * 0.8, sun_ang));
		col += sun_colour.rgb * exp(-max(sun_ang - sun_radius, 0.0) * 18.0) * 0.4;
	}

	// The clouds, on a plane: squashed toward the horizon, faded into the haze down there.
	if (h > 0.0 && cover > 0.0) {
		vec2 p = d.xz / (h + 0.12) * 1.3 + vec2(TIME * drift, TIME * drift * 0.4);
		float n = fbm(p);
		float density = smoothstep(1.0 - cover - 0.15, 1.0 - cover + 0.25, n);
		// Lit on their sun side, dark on their bellies; the thick ones darkest.
		float shade = clamp(fbm(p * 1.7 + 4.0) * 1.3 - 0.2, 0.0, 1.0);
		vec3 cloud = mix(cloud_dark.rgb, cloud_lit.rgb, shade * (1.0 - cover * 0.5));
		cloud += sun_colour.rgb * sun_glow * 0.5 * exp(-sun_ang * 3.0);
		float fade = smoothstep(0.0, 0.12, h);
		col = mix(col, cloud, density * fade);
		// Overcast: the whole sky is cloud, the brightest where the sun is behind it.
		col = mix(col, cloud_dark.rgb * (0.9 + 0.2 * n), smoothstep(0.7, 1.0, cover) * (1.0 - density * 0.5));
	}
	col = h < 0.0 ? mix(horizon.rgb * 0.9, below.rgb, smoothstep(0.0, -0.08, h)) : col;
	COLOR = col * energy;
}
