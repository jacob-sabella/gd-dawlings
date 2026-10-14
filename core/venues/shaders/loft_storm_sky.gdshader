shader_type sky;

// A thunderstorm over the city at night. Low cloud, heavy and moving, lit from beneath by the
// streets (a dull sodium glow that is strongest at the horizon); curtains of rain hanging out of
// it toward the ground; and, when the lightning goes, the whole underside of the cloud lighting
// up, brightest round the strike, with the bolt itself forking down to the skyline.
//
// `flash` (0..1) is driven by the venue, which also flashes the room's key light in step.
// `bolt` is the strike's bearing (radians round from -Z) and `bolt_seed` its shape.

uniform vec4 zenith : source_color = vec4(0.012, 0.014, 0.022, 1.0);
uniform vec4 cloud_dark : source_color = vec4(0.05, 0.055, 0.07, 1.0);
uniform vec4 cloud_lit : source_color = vec4(0.16, 0.12, 0.1, 1.0);
uniform vec4 city_glow : source_color = vec4(0.36, 0.2, 0.1, 1.0);
uniform vec4 flash_colour : source_color = vec4(0.75, 0.8, 1.0, 1.0);
uniform float flash = 0.0;
uniform float bolt = 0.4;
uniform float bolt_seed = 0.0;
uniform float wind = 0.035;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	float bearing = atan(d.x, -d.z);
	// The cloud deck as a plane overhead: further toward the horizon, and moving with the wind.
	vec2 at = d.xz / max(h + 0.12, 0.02) * 1.4 + vec2(TIME * wind, TIME * wind * 0.4);
	float thick = fbm(at);
	float billow = fbm(at * 2.3 + thick * 1.5);
	float cloud = smoothstep(0.3, 0.75, thick * 0.65 + billow * 0.45);
	// Lit from below by the city, most at the horizon.
	float near_ground = exp(-max(h, 0.0) * 3.5);
	vec3 col = mix(zenith.rgb, cloud_dark.rgb, cloud);
	col += city_glow.rgb * near_ground * (0.35 + 0.65 * cloud);
	col += cloud_lit.rgb * cloud * near_ground * 0.6;
	// Rain hanging out of the cloud: dim vertical streaks, densest near the horizon.
	float streak = noise(vec2(bearing * 60.0, h * 3.0 - TIME * 0.8));
	col *= 1.0 - 0.18 * smoothstep(0.55, 0.9, streak) * near_ground;
	// Lightning: the cloud's underside goes white, brightest round the strike and through the
	// thickest cloud; then the bolt.
	float off = abs(mod(bearing - bolt + PI, TAU) - PI);
	float round_strike = exp(-off * 2.2) * 0.8 + 0.2;
	col += flash_colour.rgb * flash * round_strike * (0.25 + cloud * 1.1) * smoothstep(-0.05, 0.1, h) * 1.6;
	if (flash > 0.05 && h > -0.02 && h < 0.42) {
		// The bolt's path: down from the cloud base at its bearing, jagging side to side.
		float y = h / 0.42;
		float jag = (noise(vec2(y * 9.0, bolt_seed * 13.0)) - 0.5) * 0.09 + (noise(vec2(y * 31.0, bolt_seed * 7.0)) - 0.5) * 0.025;
		float x = bearing - bolt - jag * (1.0 - y * 0.6);
		float core = smoothstep(0.0035, 0.0, abs(x)) + exp(-abs(x) * 160.0) * 0.4;
		// A fork, off the main stroke from halfway down.
		float fork_x = bearing - bolt - jag - (0.55 - y) * 0.12 * step(y, 0.55);
		core += smoothstep(0.0025, 0.0, abs(fork_x)) * step(y, 0.55) * smoothstep(0.0, 0.25, y) * 0.7;
		col += flash_colour.rgb * core * flash * 6.0;
	}
	// Under the horizon: the haze over the streets.
	col = h < 0.0 ? mix(col, city_glow.rgb * 0.6 + flash_colour.rgb * flash * 0.15, smoothstep(0.0, -0.08, h)) : col;
	COLOR = col;
}
