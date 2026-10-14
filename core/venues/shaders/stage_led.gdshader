shader_type spatial;
render_mode unshaded, shadows_disabled;

// The LED wall behind the backline: a grid of round emitters (you can see the pixels when you
// stand at it), showing either the show -- rings breaking out from the middle on the beat over
// a slow sweep of colour, and a spectrum along the foot -- or the soundcheck's test card, or a
// screen turned down to nearly nothing between shows.

// 0 the show, 1 the test card.
uniform int mode = 0;
uniform float pulse = 0.0;
uniform float brightness = 1.0;
uniform vec4 colour_a : source_color = vec4(0.9, 0.1, 0.6, 1.0);
uniform vec4 colour_b : source_color = vec4(0.1, 0.35, 1.0, 1.0);
// Emitters across and up.
uniform vec2 cells = vec2(192.0, 96.0);

vec3 show(vec2 c, float t) {
	vec2 p = c * 2.0 - 1.0;
	p.x *= cells.x / cells.y;
	float r = length(p);
	float a = atan(p.y, p.x);
	vec3 sweep = mix(colour_a.rgb, colour_b.rgb, 0.5 + 0.5 * sin(c.x * 3.0 - t * 0.4 + sin(t * 0.17) * 2.0));
	// A tunnel of squares flying out of the middle, faster and sharper on the beat.
	float sq = max(abs(p.x) * 0.6, abs(p.y));
	float tunnel = pow(0.5 + 0.5 * sin(log(sq + 0.05) * 9.0 - t * 2.2 - pulse * 2.5), 10.0 - pulse * 5.0);
	// Spokes turning slowly through it.
	float spokes = pow(0.5 + 0.5 * sin(a * 8.0 + t * 0.5), 14.0) * smoothstep(0.15, 1.2, r);
	// A spectrum along the foot.
	float bar = floor(c.x * 48.0);
	float h = (0.05 + 0.22 * pulse) * (0.45 + 0.55 * abs(sin(bar * 1.37 + t * (3.0 + fract(bar * 0.31) * 3.0))));
	float spectrum = step(c.y, h) * step(0.2, fract(c.x * 48.0));
	vec3 col = sweep * (tunnel * 0.9 + spokes * 0.5) + mix(colour_b.rgb, vec3(1.0), 0.2) * spectrum * 0.45;
	// A hot flash across the whole wall on a big hit.
	col += sweep * smoothstep(0.75, 1.0, pulse) * 0.4;
	return col * (0.35 + pulse * 0.9);
}

vec3 test_card(vec2 c) {
	vec3 bars[7] = vec3[](vec3(0.75), vec3(0.75, 0.75, 0.0), vec3(0.0, 0.75, 0.75), vec3(0.0, 0.75, 0.0),
			vec3(0.75, 0.0, 0.75), vec3(0.75, 0.0, 0.0), vec3(0.0, 0.0, 0.75));
	vec3 col;
	if (c.y > 0.33) {
		col = bars[int(clamp(floor(c.x * 7.0), 0.0, 6.0))];
	} else if (c.y > 0.25) {
		col = vec3(0.1);
	} else {
		col = vec3(floor(c.x * 8.0) / 7.0);
	}
	// The ring and cross a crew lines a projector or a processor up with.
	vec2 p = c * 2.0 - 1.0;
	p.x *= cells.x / cells.y;
	float ring = smoothstep(0.03, 0.0, abs(length(p) - 0.8));
	float cross_ = smoothstep(0.012, 0.0, min(abs(p.x), abs(p.y)));
	return mix(col, vec3(1.0), max(ring, cross_));
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec2 cell = floor(uv * cells);
	vec2 c = (cell + 0.5) / cells;
	// Each emitter a soft dot with black between: the wall's grain from up close.
	float dot_ = smoothstep(0.5, 0.28, length(fract(uv * cells) - 0.5));
	// Far off, the emitters are smaller than a pixel: the grain averages out rather than
	// shimmering in moire.
	dot_ = mix(dot_, 0.55, smoothstep(0.25, 0.7, fwidth(uv.x * cells.x)));
	vec3 col = mode == 1 ? test_card(c) : show(c, TIME);
	ALBEDO = col * dot_ * brightness;
}
