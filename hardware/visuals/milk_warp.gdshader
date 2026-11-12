// The warp pass of a MilkScreen (hardware/visuals/milk_screen.gd): last frame's picture, sampled a
// little zoomed, turned, shifted, stretched and wobbled about a centre, blurred a touch, its hue turned
// and faded. Drawn over the whole of one of the screen's two buffers; the wave and shapes go on top of
// it, and next frame the other buffer warps this one. That loop is what turns a line into trails,
// tunnels and spirals. Every term is worked out per pixel, analytically: no mesh of warp points.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

// The other buffer: last frame's picture.
uniform sampler2D prev : filter_linear, repeat_disable;
// Width over height, so a turn is round and not an ellipse.
uniform float aspect = 1.8;
uniform float time = 0.0;
// One texel, for the blur taps.
uniform vec2 texel = vec2(0.002, 0.0037);

uniform float zoom = 1.0;
uniform float zoom_curve = 0.0;
uniform float rot = 0.0;
uniform float warp = 0.0;
uniform float warp_speed = 1.0;
uniform float warp_scale = 1.0;
uniform vec2 center = vec2(0.5);
uniform vec2 shift = vec2(0.0);
uniform vec2 stretch = vec2(1.0);
uniform float ripple = 0.0;
uniform float ripple_freq = 14.0;
uniform float fold = 0.0;
uniform float sides = 6.0;
uniform float wrap = 1.0;
uniform float blur = 0.3;
uniform float hue_drift = 0.0;
uniform float decay = 0.97;

// Turns a colour's hue by `a` radians about the grey axis.
vec3 hue_turn(vec3 c, float a) {
	const vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

// A coordinate brought back inside 0..1: folded back like a mirror, or left out (for the black edge).
vec2 edge(vec2 s) {
	vec2 m = 1.0 - abs(1.0 - mod(s, 2.0));
	return mix(s, m, step(0.5, wrap));
}

void fragment() {
	vec2 a = vec2(aspect, 1.0);
	vec2 p = (UV - center) * a;
	float radius = length(p) / (0.5 * length(a));

	// The kaleidoscope: the angle folded into `sides` mirrored segments.
	if (fold > 0.001) {
		float seg = TAU / max(sides, 1.0);
		float ang = atan(p.y, p.x);
		float folded = abs(mod(ang, seg) - seg * 0.5);
		vec2 k = vec2(cos(folded), sin(folded)) * length(p);
		p = mix(p, k, fold);
	}

	// Zoom: even, or stronger toward the edges (a tunnel), with rings running outward.
	float z = pow(max(zoom, 0.01), mix(1.0, pow(radius * 1.4 + 0.05, 1.5), zoom_curve));
	z *= 1.0 + ripple * 0.012 * sin(radius * ripple_freq - time * 3.0);
	vec2 q = p / z;
	float cr = cos(rot);
	float sr = sin(rot);
	q = vec2(q.x * cr - q.y * sr, q.x * sr + q.y * cr);
	q /= stretch;

	// The liquid wobble: a few crossing sine fields, slow and smooth.
	float wt = time * warp_speed;
	vec2 ws = q * warp_scale;
	q += warp * 0.0045 * vec2(
		sin(ws.y * 4.3 + wt * 0.93) + 0.6 * sin(ws.x * 2.9 - wt * 1.31),
		cos(ws.x * 3.7 - wt * 1.07) + 0.6 * cos(ws.y * 5.1 + wt * 0.71));

	vec2 src = q / a + center - shift;
	float inside = step(0.0, src.x) * step(src.x, 1.0) * step(0.0, src.y) * step(src.y, 1.0);
	inside = max(inside, step(0.5, wrap));
	src = edge(src);

	vec3 c = texture(prev, src).rgb;
	if (blur > 0.001) {
		vec3 b = texture(prev, edge(src + vec2(texel.x, texel.y) * 1.5)).rgb
				+ texture(prev, edge(src + vec2(-texel.x, texel.y) * 1.5)).rgb
				+ texture(prev, edge(src + vec2(texel.x, -texel.y) * 1.5)).rgb
				+ texture(prev, edge(src + vec2(-texel.x, -texel.y) * 1.5)).rgb;
		c = mix(c, b * 0.25, blur);
	}
	if (abs(hue_drift) > 0.00001) {
		c = max(hue_turn(c, hue_drift * TAU), vec3(0.0));
	}
	// Faded, and a hair more, so a long decay still reaches black rather than leaving a haze.
	c = clamp(c * decay - vec3(0.0004), vec3(0.0), vec3(1.5)) * inside;
	COLOR = vec4(c, 1.0);
}
