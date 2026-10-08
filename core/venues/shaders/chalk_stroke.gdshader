shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// One chalk line. The mesh is a polyline, not a ribbon: every point appears twice, and the
// vertex shader pushes the pair apart sideways here, so a stroke has the same width from any
// angle and never turns edge-on to show you it was flat.
//   NORMAL   the stroke's direction at this point (model space)
//   UV.x     distance along the stroke in metres, for the grain
//   UV.y     -1 or +1: which side of the line this vertex is
//   UV2.x    half-width in metres
//   UV2.y    1 for a stroke drawn ON the floor (widened along the ground, not toward you)
//   COLOR    the chalk

uniform float energy = 2.4;
uniform float pulse = 0.0;
uniform float grain_scale = 38.0;

varying vec4 chalk;
varying vec2 along;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
			mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tangent = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 side;
	if (UV2.y > 0.5) {
		side = normalize(cross(tangent, vec3(0.0, 1.0, 0.0)));
	} else {
		vec3 to_eye = INV_VIEW_MATRIX[3].xyz - world;
		side = normalize(cross(tangent, to_eye));
	}
	float scale = length(MODEL_MATRIX[0].xyz);
	world += side * UV.y * UV2.x * scale;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	chalk = COLOR;
	along = vec2(UV.x, UV.y);
}

void fragment() {
	// Chalk is not a line, it is dust caught on the high points of the board: dense in the
	// middle of a stroke, broken at its edges, and streaked along the direction it was drawn.
	float across = abs(along.y);
	float streak = noise(vec2(along.x * grain_scale * 0.25, along.y * 9.0));
	float speck = noise(vec2(along.x, along.y * 0.2) * grain_scale);
	float body = streak * 0.55 + speck * 0.45;
	float edge = smoothstep(0.35, 1.0, across);
	if (body < 0.22 + edge * 0.55) {
		discard;
	}
	float glow = energy * (1.0 + pulse * 0.9);
	ALBEDO = chalk.rgb * glow * (0.75 + 0.35 * body);
}
