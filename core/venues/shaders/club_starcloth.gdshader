shader_type spatial;
// The stars sewn into a show cloth: tiny warm points on camera-facing quads (one MultiMesh),
// each twinkling to its own slow beat (its seed in the instance's custom data, r), and all of
// them a little brighter on a loud bar (`pulse`).

render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 colour : source_color = vec3(1.0, 0.86, 0.66);
uniform float strength = 2.2;
uniform float pulse = 0.0;

varying float seed;

void vertex() {
	seed = INSTANCE_CUSTOM.r;
	vec3 centre = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 world = centre + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float point = clamp(1.0 - length(c), 0.0, 1.0);
	point *= point;
	float twinkle = 0.3 + 0.7 * pow(0.5 + 0.5 * sin(TIME * (0.8 + seed * 1.7) + seed * 40.0), 6.0);
	ALBEDO = colour * point * twinkle * strength * (1.0 + pulse);
}
