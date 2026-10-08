shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// One chalk line. The mesh is a polyline, not a ribbon: every point appears twice, and the
// vertex shader pushes the pair apart sideways here, so a stroke has the same width from any
// angle and never turns edge-on to show you it was flat.
//   NORMAL   the stroke's direction at this point (model space)
//   UV.x     distance along the whole drawing in metres, line after line, so a drawing
//            can be drawn on in the order it was drawn
//   UV.y     -1 or +1: which side of the line this vertex is
//   UV2.x    half-width in metres
//   UV2.y    1 for a stroke drawn ON the floor (widened along the ground, not toward you)
//   COLOR    the chalk

uniform float energy = 2.4;
uniform float pulse = 0.0;
uniform float grain_scale = 38.0;
// How many metres of this drawing are on the board yet. Huge means all of it.
instance uniform float ink = 1e6;
// And how much of it has been wiped off again from the start: a comet's tail.
instance uniform float tail = -1.0;

varying vec4 chalk;
varying vec2 along;
varying float model_ink;
varying float model_tail;

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
	model_ink = ink;
	model_tail = tail;
}

void fragment() {
	// Chalk is not a line, it is dust caught on the high points of the board: dense in the
	// middle of a stroke, broken at its edges, and streaked along the direction it was drawn.
	if (along.x > model_ink || along.x < model_tail) {
		discard;
	}
	float across = abs(along.y);
	float streak = noise(vec2(along.x * grain_scale * 0.25, along.y * 9.0));
	float speck = noise(vec2(along.x, along.y * 0.2) * grain_scale);
	float body = streak * 0.55 + speck * 0.45;
	float edge = smoothstep(0.35, 1.0, across);
	if (body < 0.22 + edge * 0.55) {
		discard;
	}
	float glow = energy * (1.0 + pulse * 0.9);
	// The chalk tip is hot: the last few centimetres down glow brighter, so you can see
	// where the hand is.
	float tip = smoothstep(0.25, 0.0, model_ink - along.x) * step(model_ink, 1e5);
	// A tail fades into the dark rather than ending on a cut.
	float fade = model_tail < 0.0 ? 1.0 : smoothstep(model_tail, model_tail + 1.5, along.x);
	ALBEDO = chalk.rgb * glow * (0.75 + 0.35 * body + tip * 1.5) * fade;
}
