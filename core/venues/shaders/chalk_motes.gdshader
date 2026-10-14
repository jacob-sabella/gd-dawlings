shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Chalk dust in the classroom's moonlight. Each mote is a small quad facing the eye that wanders
// round where it was put (INSTANCE_CUSTOM.x is its phase), and it shows only while it is in the
// light: traced back along the light to the window wall, it has to come through the glass of one
// of the windows. Out of the light it is dark air, the way dust is.

uniform vec3 light_way = vec3(0.8, -0.5, -0.24);
uniform float wall_x = -7.1;
uniform float sill = 1.0;
uniform float head = 4.4;
// Each window's z extent, (from, to); unused ones are (0, 0).
uniform vec2 windows[6];
uniform float drift = 0.12;
uniform vec4 colour : source_color = vec4(0.82, 0.88, 1.0, 1.0);
uniform float strength = 0.6;

varying float lit;

void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2831853;
	float t = TIME * 0.05;
	vec3 at = MODEL_MATRIX[3].xyz + vec3(sin(t * 1.3 + ph) * cos(t * 0.7 + ph * 2.0),
			sin(t * 0.9 + ph * 3.0) * 0.8 - mod(TIME * 0.006 + INSTANCE_CUSTOM.x, 1.0) * 0.3,
			cos(t * 1.1 + ph)) * drift;
	// Back along the light to the wall.
	float back = (at.x - wall_x) / max(light_way.x, 0.001);
	vec3 through = at - light_way * back;
	float inside = 0.0;
	for (int i = 0; i < 6; i++) {
		vec2 w = windows[i];
		inside = max(inside, smoothstep(w.x, w.x + 0.12, through.z) * smoothstep(w.y, w.y - 0.12, through.z));
	}
	inside *= smoothstep(sill, sill + 0.15, through.y) * smoothstep(head, head - 0.15, through.y);
	lit = inside * step(0.0, back) * (0.5 + 0.5 * sin(TIME * 0.5 + ph * 5.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(at, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float near = smoothstep(0.5, 1.4, -VERTEX.z);
	ALBEDO = colour.rgb * strength * lit * near * (1.0 - smoothstep(0.15, 1.0, d));
}
