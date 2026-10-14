shader_type spatial;
// The lava tube's river: molten rock creeping down its channel. A crust of dark plates floats on
// it, drifting downstream and slowly turning, and between them the lava shows through in seams
// that run from orange to yellow-white where they are widest. The middle of the stream runs
// faster and hotter than its edges, where it drags on the channel and crusts over. The whole of
// it breathes: brighter and duller on a slow swell, and with the music (`pulse`).
//
// UV.x runs across the stream (0..1), UV.y along it in metres (the cave lays the ribbon so).

render_mode cull_back;

uniform float flow = 0.12;
uniform float energy = 1.15;
uniform float pulse = 0.0;
uniform vec3 hot : source_color = vec3(1.0, 0.7, 0.28);
uniform vec3 warm : source_color = vec3(1.0, 0.32, 0.04);
uniform vec3 crust : source_color = vec3(0.035, 0.022, 0.02);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Distance to the nearest seam between plates (a Voronoi cell's edge).
float seams(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			o = 0.5 + 0.4 * sin(TIME * 0.15 + 6.2831 * o);
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

void fragment() {
	float across = UV.x * 2.0 - 1.0;
	// Faster in the middle: the stream drags on its banks.
	float speed = flow * (1.0 - across * across * 0.7);
	vec2 p = vec2(UV.x * 2.6, UV.y - TIME * speed);
	vec2 warp = vec2(vnoise(p * 1.3), vnoise(p * 1.3 + 7.0)) * 0.3;
	float seam = seams(p * 1.1 + warp);
	float open = 1.0 - smoothstep(0.03, 0.3, seam);
	// The crust's rim glows where it is thin, next to a seam.
	float rim = 1.0 - smoothstep(0.05, 0.6, seam);
	// The middle is more seam than crust; the edges have crusted over.
	float middle = 1.0 - smoothstep(0.35, 1.0, abs(across));
	open = max(open, middle * 0.35 * smoothstep(0.45, 0.85, vnoise(p * 3.0 + 3.0)));
	// Down the middle the crust breaks up into rafts on open melt.
	open = max(open, middle * smoothstep(0.42, 0.62, vnoise(p * 1.2 + 11.0)) * smoothstep(0.08, 0.2, seam));
	open *= mix(0.45, 1.0, middle);
	float swell = 0.85 + 0.15 * sin(TIME * 0.5 + UV.y * 0.3) + pulse * 0.6;
	vec3 molten = mix(warm, hot, smoothstep(0.4, 1.0, open) * middle);
	float cool = vnoise(p * 6.0) * 0.5 + 0.5;
	ALBEDO = mix(crust * cool * 1.6, molten * 0.25, open);
	ROUGHNESS = mix(0.9, 0.4, open);
	// The crust glows a little too, dull red from the heat under it.
	EMISSION = molten * open * energy * swell + warm * (0.04 + rim * 0.35) * energy * (1.0 - open) * swell;
}
