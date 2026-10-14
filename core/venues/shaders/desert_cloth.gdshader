shader_type spatial;
render_mode cull_disabled;

// The tent's cloth: strips of goat-hair weave, each about two-thirds of a metre wide, sewn edge
// to edge -- the way a Bedouin tent is made -- most of them near-black, some the undyed brown of
// the camel-hair ones, and down the seams thin bands of cream and madder. UV is the cloth's plan
// (or, on the back wall, along and up it) in metres; the strips run across UV's y.
//
// Sun behind it comes through it a little (BACKLIGHT), the way woven hair lets the day in.

uniform vec4 hair : source_color = vec4(0.07, 0.05, 0.04, 1.0);
uniform vec4 camel : source_color = vec4(0.36, 0.25, 0.16, 1.0);
uniform vec4 cream : source_color = vec4(0.6, 0.52, 0.4, 1.0);
uniform vec4 madder : source_color = vec4(0.5, 0.11, 0.07, 1.0);
uniform float strip = 0.68;
// The share of strips with bands woven in at their edges.
uniform float banded = 0.34;
uniform vec4 backlight : source_color = vec4(0.25, 0.15, 0.08, 1.0);

float hash1(float n) {
	return fract(sin(n * 91.3458) * 47453.5453);
}

void fragment() {
	float y = UV.y / strip;
	float which = floor(y);
	float f = fract(y);
	float kind = hash1(which);
	vec3 c = kind < 0.72 ? hair.rgb : camel.rgb;
	// Bands near the strip's edges, on some of the strips: a cream pair, a madder line.
	float edge = min(f, 1.0 - f) * strip;
	if (hash1(which + 17.0) > 1.0 - banded) {
		float b1 = step(0.05, edge) * step(edge, 0.075);
		float b2 = step(0.1, edge) * step(edge, 0.115);
		float b3 = step(0.135, edge) * step(edge, 0.16);
		c = mix(c, cream.rgb, max(b1, b2) * 0.85);
		c = mix(c, madder.rgb, b3 * 0.9);
	}
	// The seam itself, a darker line where the strips are stitched.
	c *= mix(0.55, 1.0, smoothstep(0.0, 0.012, edge));
	// The weave: a fine twill in the hair, and the slubs of hand-spun yarn.
	// Both fade out where they are finer than a pixel, where they would only shimmer.
	float twill_phase = (UV.x + UV.y) * 380.0;
	float fine = 1.0 - smoothstep(0.5, 2.0, fwidth(twill_phase));
	float twill = (sin(twill_phase) * 0.5 + 0.5 - 0.5) * fine + 0.5;
	float slub_phase = UV.y * 90.0;
	float slub = mix(0.5, hash1(floor(slub_phase) + which * 13.0), 1.0 - smoothstep(0.3, 1.0, fwidth(slub_phase)));
	c *= 0.82 + 0.12 * twill + 0.12 * slub;
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
	BACKLIGHT = backlight.rgb;
}
