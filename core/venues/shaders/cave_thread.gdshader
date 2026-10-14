shader_type spatial;
// A glowworm's fishing line: a thread of silk hanging from the roof, beaded with droplets of
// mucus that catch its glow. A thin quad turned about its own length to face you (the thread
// hangs straight down from the instance's origin, its length the instance's Y scale); the beads
// are bright dots along it, brightest near the worm at its top. It sways a hair in the air.

render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(0.3, 1.0, 0.85);
uniform float energy = 1.1;
uniform float pulse = 0.0;
uniform float clip_above = 1000.0;
uniform float dim = 1.0;

varying float seed;
varying float world_y;

void vertex() {
	seed = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	world_y = MODEL_MATRIX[3].y;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float length_y = length(MODEL_MATRIX[1].xyz);
	float width = length(MODEL_MATRIX[0].xyz);
	vec3 down = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_eye = normalize(INV_VIEW_MATRIX[3].xyz - origin);
	vec3 across = normalize(cross(down, to_eye));
	// The quad runs from y 0 at the top to -1 at the bottom (the cave offsets it so).
	float t = -VERTEX.y;
	vec3 sway = vec3(sin(TIME * 0.7 + seed * 30.0), 0.0, cos(TIME * 0.6 + seed * 17.0)) * 0.015 * t * t;
	vec3 at = origin + down * VERTEX.y * length_y + across * VERTEX.x * width + sway;
	MODELVIEW_MATRIX = VIEW_MATRIX;
	VERTEX = at;
}

void fragment() {
	if (world_y > clip_above) {
		discard;
	}
	float t = UV.y;
	float line = exp(-pow((UV.x - 0.5) * 6.0, 2.0));
	float beads = pow(max(0.0, sin(t * 60.0 + seed * 20.0)), 24.0);
	float fade = exp(-t * 2.6);
	float lift = 1.0 + pulse * 0.8;
	ALBEDO = colour * line * (0.05 + beads * 1.2) * fade * energy * lift * dim;
}
