shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// A tongue of flame on a quad: narrow at the top, licking, white-gold at its root and going to
// orange and red as it rises, noise climbing through it. Several quads crossed make a fire; each
// has its own `phase` so they never lick together. `level` is how hard the fire is burning
// (the venue breathes it with the music).

instance uniform float phase = 0.0;
uniform float level = 1.0;
uniform vec4 root : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform vec4 body : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform vec4 tip : source_color = vec4(0.7, 0.12, 0.03, 1.0);

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	// UV.y is 0 at the top of a QuadMesh; the flame grows from the bottom.
	float h = 1.0 - UV.y;
	float x = (UV.x - 0.5) * 2.0;
	float t = TIME * 1.6 + phase * 10.0;
	float n = noise2(vec2(x * 2.5 + phase * 3.0, h * 3.0 - t * 1.8)) * 0.6 + noise2(vec2(x * 6.0, h * 7.0 - t * 3.1)) * 0.4;
	// The flame's sides lean and lick with the noise; it thins to a point.
	float sway = (noise2(vec2(t * 0.7, phase * 5.0)) - 0.5) * 0.5 * h;
	float width = (1.0 - pow(h, 0.8)) * (0.55 + 0.45 * n) * mix(0.75, 1.1, level);
	float shape = smoothstep(width, width * 0.4, abs(x - sway)) * smoothstep(0.0, 0.08, h);
	// Breaks up toward the tip.
	shape *= smoothstep(0.15, 0.5, n + (1.0 - h) * 0.6);
	vec3 c = mix(root.rgb, body.rgb, smoothstep(0.05, 0.4, h));
	c = mix(c, tip.rgb, smoothstep(0.4, 0.85, h));
	ALBEDO = c * shape * (1.6 + 0.6 * level);
}
