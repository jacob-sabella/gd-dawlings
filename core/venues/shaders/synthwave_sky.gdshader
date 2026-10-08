shader_type sky;

// Dusk over the grid: a purple-to-magenta gradient, a striped sun sitting on the horizon, a
// band of haze where they meet and stars overhead.

uniform vec4 zenith : source_color = vec4(0.02, 0.0, 0.07, 1.0);
uniform vec4 upper : source_color = vec4(0.16, 0.02, 0.32, 1.0);
uniform vec4 horizon : source_color = vec4(0.95, 0.18, 0.55, 1.0);
uniform vec4 sun_top : source_color = vec4(1.0, 0.92, 0.25, 1.0);
uniform vec4 sun_bottom : source_color = vec4(1.0, 0.15, 0.55, 1.0);
uniform vec3 sun_dir = vec3(0.0, 0.11, -1.0);
uniform float sun_radius = 0.16;
uniform float sun_energy = 1.35;
uniform float pulse = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon.rgb, upper.rgb, smoothstep(0.0, 0.22, h));
	col = mix(col, zenith.rgb, smoothstep(0.22, 0.75, h));
	col = h < 0.0 ? horizon.rgb * 0.25 : col;

	// Stars, above the haze.
	vec2 uv = vec2(atan(d.x, d.z), asin(clamp(h, -1.0, 1.0))) * 70.0;
	vec2 cell = floor(uv);
	float r = hash(cell);
	if (r > 0.985 && h > 0.12) {
		vec2 at = vec2(hash(cell + 7.1), hash(cell + 3.3));
		float s = smoothstep(0.08, 0.0, length(fract(uv) - at));
		float twinkle = 0.6 + 0.4 * sin(TIME * (1.0 + r * 3.0) + r * 40.0);
		col += vec3(0.9, 0.85, 1.0) * s * twinkle * smoothstep(0.12, 0.4, h) * 2.0;
	}

	// The sun: a vertical gradient disc cut by bands that thicken toward its foot.
	vec3 sd = normalize(sun_dir);
	float ang = acos(clamp(dot(d, sd), -1.0, 1.0));
	float y = (h - sd.y) / sun_radius;
	float bands = 1.0;
	if (y < 0.1) {
		float k = fract((y - 0.1) * 7.0);
		float cut = clamp((0.1 - y) * 0.55, 0.0, 0.6);
		bands = step(cut, k);
	}
	float disc = smoothstep(sun_radius, sun_radius - 0.004, ang) * bands * step(0.0, h);
	vec3 sun = mix(sun_bottom.rgb, sun_top.rgb, smoothstep(-1.0, 1.0, y));
	col = mix(col, sun * sun_energy * (1.0 + pulse * 0.4), disc);
	// Halo.
	col += sun_bottom.rgb * exp(-max(ang - sun_radius, 0.0) * 9.0) * 0.35 * step(0.0, h);
	COLOR = col;
}
