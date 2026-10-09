shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Dust turning slowly in a spot's beam. Each mote is a small quad, always facing the eye, that
// wanders round where it was put (INSTANCE_CUSTOM.x is its own phase); it shows only while it
// is inside the cone of light -- out of it, it is dark air like the rest of the room.

uniform vec3 lamp;
uniform vec3 aim = vec3(0.0, -1.0, 0.0);
// The cone: its radius at the lamp, and how much wider it gets for each metre along.
uniform float near_radius = 0.1;
uniform float spread = 0.2;
uniform float reach = 4.0;
uniform float drift = 0.14;
uniform vec4 colour : source_color = vec4(1.0, 0.88, 0.7, 1.0);
uniform float strength = 0.8;

varying float lit;

void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2831853;
	float t = TIME * 0.06;
	vec3 at = MODEL_MATRIX[3].xyz + vec3(sin(t * 1.3 + ph) * cos(t * 0.7 + ph * 2.0),
			sin(t * 0.9 + ph * 3.0) * 0.6, cos(t * 1.1 + ph)) * drift;
	vec3 v = at - lamp;
	float along = dot(v, aim);
	float off = length(v - aim * along);
	float cone = near_radius + along * spread;
	lit = smoothstep(cone, cone * 0.6, off) * smoothstep(0.0, 0.5, along) * smoothstep(reach, reach - 0.4, along)
			* (0.55 + 0.45 * sin(TIME * 0.4 + ph * 5.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(at, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	// A mote right in front of the eye would be a blot, not a speck: those fade away.
	float near = smoothstep(0.6, 1.6, -VERTEX.z);
	ALBEDO = colour.rgb * strength * lit * near * (1.0 - smoothstep(0.2, 1.0, d));
}
