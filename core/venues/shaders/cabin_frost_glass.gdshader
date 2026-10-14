shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

// Frost on the cabin's panes on a bitter night: fine feathers of ice grown in from the frame,
// longest out of the corners and along the bottom where the cold settles, and clear glass in the
// middle so you can still see out. The ice is white where the room's warm light catches it and
// takes a little of the aurora's green from outside (`outside`).
//
// The pane is a box (ShellKit.glazed); its half-size (along, up) and the size of its small panes
// come in per pane as instance uniforms, so each one's frost is grown from its own edges.

uniform vec4 ice : source_color = vec4(0.82, 0.88, 0.95, 1.0);
uniform vec4 outside : source_color = vec4(0.25, 0.6, 0.45, 1.0);
uniform float clear_alpha = 0.06;
instance uniform vec2 half_size = vec2(0.65, 0.75);
// The size of the small panes between the window's bars (ShellKit.glazed's uprights and rows),
// so each one frosts from its own corners too.
instance uniform vec2 cell = vec2(0.65, 0.375);

varying vec2 local;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Ice needles: ridged noise sharpened until only its ridges are left, a thin branching line where
// each one runs -- the feathers frost grows in. `grain` stretches it along the way they grow.
float needles(vec2 p, float sharp) {
	float n = 1.0 - abs(noise(p) * 2.0 - 1.0);
	return pow(n, sharp);
}

void vertex() {
	// The pane's own along-and-up, whichever way it faces: the box's widest horizontal axis.
	local = abs(VERTEX.x) > abs(VERTEX.z) ? vec2(VERTEX.x, VERTEX.y) : vec2(VERTEX.z, VERTEX.y);
}

void fragment() {
	// Where this point is in the small pane between the bars, in metres from its sides.
	vec2 q = fract((local + half_size) / cell) * cell;
	vec2 m = min(q, cell - q);
	float side = min(m.x, m.y);
	// Toward which corner: the feathers grow out of the corners, so they run away from it.
	vec2 corner_at = vec2(q.x < cell.x * 0.5 ? 0.0 : cell.x, q.y < cell.y * 0.5 ? 0.0 : cell.y);
	vec2 from_corner = q - corner_at;
	float corner = length(m);
	// Thicker low down, where the cold settles.
	float low = smoothstep(0.4, -0.9, local.y / half_size.y);
	// How far it has grown in: a little way along every side, much further out of the corners.
	float wobble = noise(local * 9.0);
	float from_side = smoothstep(0.04 + 0.05 * low + 0.02 * wobble, 0.004, side);
	float from_corners = smoothstep(0.13 + 0.12 * low + 0.05 * wobble, 0.0, corner);
	float grown = max(from_side, from_corners);
	// The feathers: needles laid along the way out of the corner, at two sizes, the fine ones
	// only where the coarse ones run (barbs on a stem).
	float ang = atan(from_corner.y, from_corner.x);
	// Stems: straight needles fanning out of the corner, each its own length.
	float fan = ang * 16.0 + (noise(local * 5.0) - 0.5) * 0.8;
	float stem_line = 1.0 - abs(fract(fan) - 0.5) * 2.0;
	float stem_len = 0.06 + 0.16 * hash(vec2(floor(fan), floor(local.x / cell.x) + floor(local.y / cell.y) * 7.0));
	float stems = pow(stem_line, 10.0) * smoothstep(stem_len, stem_len * 0.5, length(from_corner));
	vec2 polar = vec2(ang * 9.0, length(from_corner) * 14.0);
	float barbs = needles(local * vec2(70.0, 55.0) + vec2(ang * 3.0), 10.0);
	float lace = max(stems, barbs * smoothstep(0.1, 0.6, needles(polar * 0.7 + 1.3, 3.0)));
	// A hairline of solid ice right against the wood.
	float crust = smoothstep(0.009, 0.002, side);
	float frost = clamp(grown * lace * 1.3 + crust * 0.8, 0.0, 1.0);
	ALBEDO = mix(vec3(0.05, 0.06, 0.08), ice.rgb, frost) + outside.rgb * frost * 0.12;
	ALPHA = mix(clear_alpha, 0.8, frost);
	ROUGHNESS = mix(0.05, 0.55, frost);
	SPECULAR = 0.5;
	// Ice scatters what light there is: a glint here and there along the needles.
	// And holds a little of the night's light even where the room's does not reach it.
	EMISSION = (ice.rgb * 0.09 + outside.rgb * 0.08) * frost + vec3(0.9, 0.95, 1.0) * step(0.99, hash(floor(local * 300.0))) * frost * 0.5;
}
