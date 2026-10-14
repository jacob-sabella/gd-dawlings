shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Dust turning in the Sunday sun. Each mote is a GPU particle's quad, always facing the eye,
// drifting on the room's air; it shows only while it is in the sun -- traced back along the
// sun's line to the left-hand wall, it must come through one of the window openings and between
// the glazing bars. Out of the beam it is dark air like the rest of the room.

uniform vec3 travel = vec3(1.0, -0.46, -0.36);
// The window wall's plane (its x), the openings' centres along it (z) and their half-size
// (along, up) about the height of their middles.
uniform float wall_x = -6.5;
uniform vec2 opening_a = vec2(-0.9, 2.775);
uniform vec2 opening_b = vec2(1.25, 2.775);
uniform vec2 half_size = vec2(0.85, 1.825);
uniform float uprights = 5.0;
uniform float rows = 8.0;
uniform vec4 colour : source_color = vec4(1.0, 0.88, 0.66, 1.0);
uniform float strength = 1.6;

varying float lit;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float between(float u, float count) {
	float k = u * (count - 1.0);
	return step(0.06, abs(k - round(k)));
}

float through(vec2 at, vec2 centre) {
	vec2 q = (at - centre) / half_size;
	if (abs(q.x) > 1.0 || abs(q.y) > 1.0) {
		return 0.0;
	}
	vec2 u = q * 0.5 + 0.5;
	return between(u.x, uprights) * between(u.y, rows + 1.0);
}

void vertex() {
	vec3 p = MODEL_MATRIX[3].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	vec3 d = normalize(travel);
	// Back along the sun to the wall.
	float t = (p.x - wall_x) / d.x;
	vec3 at = p - d * t;
	float sun = max(through(at.zy, opening_a), through(at.zy, opening_b)) * step(0.0, t);
	float h = hash(float(INSTANCE_ID) + 0.5);
	// A mote catches the light as it turns.
	lit = sun * (0.4 + 0.6 * pow(0.5 + 0.5 * sin(TIME * (0.6 + h * 1.4) + h * 40.0), 3.0));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	ALBEDO = colour.rgb * exp(-r * r * 6.0) * lit * strength;
}
