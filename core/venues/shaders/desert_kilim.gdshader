shader_type spatial;
// Both sides: the valance is a single sheet, seen from in and out.
render_mode cull_disabled;

// Flat-woven kilims, drawn rather than textured, so every rug in the camp is its own. Three ways
// of being drawn, one per material (`mode`):
//
//   0  a rug: in its own plan (the box's local x and z, metres), sized by `rug_size`: an outer
//      guard, a border of running zigzags, a thin line, and a field of stepped lozenges down
//      the long axis in rings of colour, little hooked motifs scattered round them. `seed` picks
//      one of four palettes and shifts the drawing, so two rugs of one size still differ.
//   1  a band, along UV.x in metres, UV.y down it 0..1: the tent's valance -- a cream stripe,
//      a row of hanging teeth, a line of small diamonds, a madder hem.
//   2  a cushion: plain cloth the instance's colour, with a woven stripe across it.

uniform int mode = 0;
instance uniform vec2 rug_size = vec2(2.0, 3.0);
instance uniform float seed = 0.0;
uniform float brightness = 1.0;

varying vec3 local;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void palette(float s, out vec3 field, out vec3 a, out vec3 b, out vec3 c, out vec3 d) {
	int p = int(mod(floor(s), 4.0));
	if (p == 0) {
		field = vec3(0.5, 0.1, 0.07); a = vec3(0.09, 0.11, 0.27); b = vec3(0.84, 0.76, 0.6);
		c = vec3(0.84, 0.54, 0.14); d = vec3(0.1, 0.06, 0.05);
	} else if (p == 1) {
		field = vec3(0.1, 0.13, 0.3); a = vec3(0.55, 0.12, 0.08); b = vec3(0.82, 0.74, 0.58);
		c = vec3(0.78, 0.6, 0.22); d = vec3(0.06, 0.05, 0.06);
	} else if (p == 2) {
		field = vec3(0.68, 0.32, 0.12); a = vec3(0.08, 0.32, 0.33); b = vec3(0.84, 0.77, 0.62);
		c = vec3(0.38, 0.08, 0.07); d = vec3(0.12, 0.07, 0.05);
	} else {
		field = vec3(0.7, 0.58, 0.4); a = vec3(0.08, 0.06, 0.05); b = vec3(0.56, 0.12, 0.08);
		c = vec3(0.12, 0.16, 0.34); d = vec3(0.24, 0.32, 0.14);
	}
}

void vertex() {
	local = VERTEX;
}

vec3 rug() {
	vec3 field, a, b, c, d;
	palette(seed, field, a, b, c, d);
	vec2 half_size = rug_size * 0.5;
	vec2 m = local.xz;
	// The long axis is the rug's own: the lozenges go down whichever way is longer.
	bool long_x = rug_size.x > rug_size.y;
	vec2 q = long_x ? m.yx : m;
	vec2 hs = long_x ? half_size.yx : half_size;
	float e = min(hs.x - abs(q.x), hs.y - abs(q.y));
	float along = abs(q.x) > abs(q.y) * hs.x / hs.y ? q.y : q.x;
	float guard = 0.05;
	float border = 0.2;
	vec3 col;
	if (e < guard) {
		col = d;
	} else if (e < border) {
		// Running zigzag: a triangle wave along the edge, one colour under it, another over.
		float v = (e - guard) / (border - guard);
		float tri = abs(fract(along / 0.16 + seed * 0.37) - 0.5) * 2.0;
		col = v < tri * 0.8 + 0.1 ? b : a;
		if (abs(v - (tri * 0.8 + 0.1)) < 0.12) {
			col = c;
		}
	} else if (e < border + 0.035) {
		col = b;
	} else {
		col = field;
		// Lozenges down the long axis, stepped in squares of a weaver's count.
		float count = max(1.0, floor((hs.y - border) * 2.0 / max(hs.x * 1.3, 0.5)));
		float pitch = (hs.y - border - 0.035) * 2.0 / count;
		float cy = (floor((q.y + hs.y - border - 0.035) / pitch) + 0.5) * pitch - (hs.y - border - 0.035);
		vec2 r = vec2(q.x, q.y - cy);
		float step_m = 0.045;
		vec2 cells = floor(abs(r) / step_m);
		float w = (hs.x - border - 0.035) * 0.85;
		float h = pitch * 0.45;
		float dist = cells.x * step_m / w + cells.y * step_m / h;
		if (dist < 1.0) {
			float ring = floor(dist * 5.0);
			int k = int(mod(ring + floor(seed * 3.0), 4.0));
			col = k == 0 ? b : (k == 1 ? a : (k == 2 ? c : d));
			if (ring == 0.0) {
				col = c;
			}
		} else {
			// Small hooked crosses scattered over the open field.
			vec2 g = floor(q / 0.22 + seed);
			vec2 gf = fract(q / 0.22 + seed) - 0.5;
			if (hash2(g) > 0.62) {
				float cross_arm = step(abs(gf.x), 0.05) * step(abs(gf.y), 0.2) + step(abs(gf.y), 0.05) * step(abs(gf.x), 0.2);
				col = mix(col, hash2(g + 3.0) > 0.5 ? b : d, clamp(cross_arm, 0.0, 1.0));
			}
		}
	}
	return col;
}

vec3 band(vec2 uv) {
	vec3 field, a, b, c, d;
	palette(0.0, field, a, b, c, d);
	float v = uv.y;
	float s = uv.x;
	if (v < 0.14) {
		return v < 0.04 ? d : b;
	} else if (v < 0.62) {
		// Hanging teeth: triangles pointing down, alternately madder and indigo.
		float u = fract(s / 0.18);
		float k = mod(floor(s / 0.18), 2.0);
		float depth = (v - 0.14) / 0.48;
		bool inside = abs(u - 0.5) * 2.0 < 1.0 - depth;
		return inside ? (k < 0.5 ? field : a) : c * 0.9;
	} else if (v < 0.8) {
		vec2 g = vec2(fract(s / 0.09) - 0.5, (v - 0.71) / 0.09);
		return abs(g.x) + abs(g.y) < 0.38 ? b : d;
	}
	return field;
}

void fragment() {
	vec3 col;
	if (mode == 0) {
		col = rug();
	} else if (mode == 1) {
		col = band(UV);
	} else {
		float stripe = step(0.82, fract(local.x * 6.0 + 0.5)) + step(0.9, fract(local.z * 6.0 + 0.2));
		col = COLOR.rgb * (1.0 - 0.35 * clamp(stripe, 0.0, 1.0));
	}
	// The weave: fine rows of weft across, a little uneven in tone.
	vec2 p = mode == 1 ? vec2(UV.x * 3.0, UV.y) : local.xz;
	// Fading out where finer than a pixel, where it would only shimmer.
	float weft_phase = p.y * 520.0;
	float weft = (sin(weft_phase) * 0.5) * (1.0 - smoothstep(0.5, 2.0, fwidth(weft_phase))) + 0.5;
	float tone = mix(0.5, hash2(floor(p * 40.0)), 1.0 - smoothstep(0.3, 1.0, fwidth(p.x * 40.0)));
	col *= 0.82 + 0.1 * weft + 0.12 * tone;
	ALBEDO = col * brightness;
	ROUGHNESS = 1.0;
	SPECULAR = 0.12;
}
