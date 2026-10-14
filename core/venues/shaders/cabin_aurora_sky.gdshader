shader_type sky;

// A clear, bitter night in the north with the aurora out. A black-blue sky thick with stars and
// the Milky Way's haze across it, and over the trees the aurora: curtains of green light hanging
// from violet tops, folding and rippling as they drift, brightest at their lower hems. The
// curtains are found the way they are seen -- a few layers of sky at rising heights, each sampled
// along the eye's line, the bands in each one a wavy line that moves -- so they lean away into
// the distance and crowd toward the horizon.
//
// `glow` (0..1 and a little over) is the display's strength, which the venue breathes slowly and
// matches with the green in the room's key light.

uniform vec4 zenith : source_color = vec4(0.004, 0.007, 0.02, 1.0);
uniform vec4 horizon : source_color = vec4(0.02, 0.04, 0.06, 1.0);
uniform vec4 green : source_color = vec4(0.2, 1.0, 0.45, 1.0);
uniform vec4 violet : source_color = vec4(0.55, 0.2, 0.9, 1.0);
uniform float glow = 1.0;
uniform float stars = 1.0;
// Where the display is centred, as a bearing (radians round from -Z): in front of the cabin.
uniform float bearing = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// One layer of curtain at sky-plane coordinates `p`: bright along a few wandering lines.
float curtain(vec2 p, float t) {
	float wave = sin(p.x * 0.35 + t * 0.21) * 1.6 + sin(p.x * 0.9 - t * 0.33 + 1.3) * 0.6
			+ (noise(vec2(p.x * 0.6, t * 0.15)) - 0.5) * 2.4;
	float band = exp(-pow(p.y - wave, 2.0) * 1.8);
	float band2 = exp(-pow(p.y - wave * 0.7 - 3.2, 2.0) * 2.6) * 0.55;
	// The fine vertical rays the curtain is made of, flickering along it.
	float rays = 0.55 + 0.45 * noise(vec2(p.x * 7.0 + wave * 2.0, t * 0.9));
	return (band + band2) * rays;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon.rgb, zenith.rgb, smoothstep(0.0, 0.6, h));
	// The Milky Way: a faint band across the sky, mottled.
	vec3 gal = normalize(vec3(0.6, 0.35, 0.72));
	float band = exp(-pow(dot(d, gal), 2.0) * 22.0);
	col += vec3(0.03, 0.035, 0.05) * band * (0.5 + noise(d.xz * 18.0 + d.y * 7.0)) * smoothstep(0.0, 0.3, h);
	// Stars: two sizes, many, twinkling, fewer down in the haze.
	for (int k = 0; k < 2; k++) {
		float scale = k == 0 ? 90.0 : 190.0;
		vec2 uv = vec2(atan(d.x, d.z), asin(clamp(h, -1.0, 1.0))) * scale;
		vec2 cell = floor(uv);
		float r = hash(cell + float(k) * 17.0);
		float density = (k == 0 ? 0.03 : 0.08) * (1.0 + band * 2.0);
		if (r > 1.0 - density * stars) {
			vec2 at = vec2(hash(cell + 7.1), hash(cell + 3.3)) * 0.6 + 0.2;
			float s = smoothstep(k == 0 ? 0.11 : 0.07, 0.0, length(fract(uv) - at));
			float twinkle = 0.65 + 0.35 * sin(TIME * (2.0 + r * 5.0) + r * 60.0);
			float bright = k == 0 ? 1.6 : 0.8;
			col += mix(vec3(1.0, 0.9, 0.8), vec3(0.8, 0.88, 1.0), hash(cell)) * s * twinkle * bright * smoothstep(0.02, 0.25, h);
		}
	}
	// The aurora: layers of sky from 1 unit up to 2.4, each read where the eye's line meets it.
	if (h > 0.0) {
		vec3 aur = vec3(0.0);
		float turn = atan(d.x, -d.z) - bearing;
		vec2 dir = vec2(sin(turn), cos(turn));
		float t = TIME;
		for (int i = 0; i < 14; i++) {
			float fi = float(i) / 13.0;
			float layer = 1.0 + fi * 1.4;
			vec2 p = dir * layer / max(h, 0.035) * 1.6;
			// Out ahead of the cabin: p.y is distance toward the display, p.x across it.
			float c = curtain(vec2(p.x, p.y - 7.0), t + fi * 0.6);
			// Green at the hem (low layers), violet up the curtain (high).
			vec3 hue = mix(green.rgb, violet.rgb, smoothstep(0.25, 1.0, fi));
			aur += hue * c * (1.0 - fi * 0.55) * 0.13;
		}
		// Fade it down into the haze over the horizon and off the far side of the sky.
		aur *= smoothstep(0.0, 0.08, h) * smoothstep(-0.2, 0.4, dir.y);
		col += aur * glow;
	}
	COLOR = col;
}
