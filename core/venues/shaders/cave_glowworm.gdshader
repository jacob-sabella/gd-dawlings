shader_type spatial;
// One glowworm: a point of blue-green light on the roof of the glowworm lake, always turned to
// face you. Thousands of them in one MultiMesh, each twinkling on its own slow beat (its seed
// from its instance), brighter together on a loud bar (`pulse`). Drawn twice: on the roof, and
// in the lake, upside down and dimmer (`dim`), cut off at the water (`clip_above`).

render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(0.3, 1.0, 0.85);
uniform float energy = 3.0;
uniform float dim = 1.0;
uniform float pulse = 0.0;
uniform float clip_above = 1000.0;

varying float seed;
varying float world_y;

void vertex() {
	seed = fract(sin(float(INSTANCE_ID) * 78.233) * 43758.5453);
	world_y = MODEL_MATRIX[3].y;
	// A billboard: the quad's corners laid out across the view, at the instance's place and size.
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size,
			INV_VIEW_MATRIX[2] * size, MODEL_MATRIX[3]);
}

void fragment() {
	if (world_y > clip_above) {
		discard;
	}
	vec2 d = UV * 2.0 - 1.0;
	float r = dot(d, d);
	float core = exp(-r * 9.0);
	float halo = exp(-r * 2.5) * 0.25;
	float twinkle = 0.55 + 0.45 * sin(TIME * (0.3 + seed * 0.9) + seed * 60.0);
	twinkle *= 0.85 + 0.15 * sin(TIME * 2.3 + seed * 13.0);
	float lift = 1.0 + pulse * (0.6 + seed * 1.2);
	ALBEDO = colour * (core + halo) * energy * twinkle * lift * dim * mix(0.6, 1.2, seed);
}
