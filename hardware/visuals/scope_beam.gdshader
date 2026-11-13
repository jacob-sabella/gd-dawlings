shader_type spatial;
// An oscilloscope's beam, as an analogue scope draws it (the idea of m1el's woscope, MIT, re-done here):
// each segment of the trace is a quad a few sigmas wider than the line, and a point on it is lit by the
// beam's Gaussian spot swept along the segment, integrated in closed form (erf along, a Gaussian across).
// The beam crosses every segment in the same time, so a long segment (a fast swing) spreads that light
// thin and a short one (where the signal lingers) burns hot: the scope's own look, faint edges and bright
// turning points. Added onto what is behind it.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.4, 1.0, 0.7, 1.0);
// The spot's radius (one sigma), in the screen's own units (metres).
uniform float sigma = 0.004;
// How bright overall, and how much of it is this trace's (1 for the live one, less for the smears).
uniform float gain = 1.0;
uniform float fade = 1.0;

// erf, to about 1e-4 (Winitzki's approximation): plenty for light.
float erf_approx(float x) {
	float a = 0.147;
	float x2 = x * x;
	float r = sqrt(1.0 - exp(-x2 * (1.2732395 + a * x2) / (1.0 + a * x2)));
	return x < 0.0 ? -r : r;
}

void fragment() {
	// UV: where this point is, along the segment from its start (x) and across it (y). UV2.x: its length.
	float len = max(UV2.x, 1e-5);
	float s = max(sigma, 1e-5);
	float across = exp(-UV.y * UV.y / (2.0 * s * s));
	float k = 0.70710678 / s;
	float along = 0.5 * (erf_approx((len - UV.x) * k) - erf_approx(-UV.x * k));
	// The same light per segment, spread over its length: slow is bright, fast is faint.
	float dwell = clamp(2.5 * s / len, 0.12, 1.6);
	float i = across * along * dwell * gain * fade;
	// The hot core whitens, as phosphor does when driven hard.
	vec3 c = mix(tint.rgb, vec3(1.0), clamp(i - 0.75, 0.0, 0.6));
	// Additive: the light is all in the colour (ALPHA, which blend_add multiplies by, is kept whole).
	ALBEDO = c * min(i * 1.6, 2.4);
	ALPHA = 1.0;
}
