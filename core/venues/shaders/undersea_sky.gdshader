shader_type sky;

// Under water, twenty metres down. No sky: the water itself, dark below, a deep teal round the
// horizon, brightening toward the surface; straight up, the surface seen from beneath -- a
// bright disc of the world above (Snell's window), its edge broken by ripples, outside it the
// surface a mirror of the dark below. A glint where the sun is.

uniform vec4 deep : source_color = vec4(0.003, 0.016, 0.03, 1.0);
uniform vec4 horizon : source_color = vec4(0.015, 0.075, 0.1, 1.0);
uniform vec4 high : source_color = vec4(0.05, 0.22, 0.26, 1.0);
uniform vec4 window : source_color = vec4(0.5, 0.85, 0.85, 1.0);
uniform vec3 sun_dir = vec3(0.2, 1.0, -0.35);
uniform float energy = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon.rgb, deep.rgb, smoothstep(0.0, -0.7, h));
	col = mix(col, high.rgb, smoothstep(0.0, 0.75, h));
	// Snell's window: about 48 degrees round straight up. Where the ray meets the surface, the
	// ripples move its edge and its light.
	vec2 at = d.xz / max(h, 0.05);
	float ripple = noise(at * 3.0 + vec2(TIME * 0.3, TIME * 0.2)) + 0.5 * noise(at * 7.0 - TIME * 0.4);
	float edge = cos(radians(48.6)) + (ripple - 0.75) * 0.03;
	float inside = smoothstep(edge - 0.02, edge + 0.04, h);
	col = mix(col, window.rgb * (0.7 + ripple * 0.4), inside);
	// The sun's glint through it, smeared by the ripples.
	float sun = max(dot(d, normalize(sun_dir)), 0.0);
	col += window.rgb * pow(sun, 60.0) * (0.6 + ripple) * 1.5 * inside;
	COLOR = col * energy;
}
