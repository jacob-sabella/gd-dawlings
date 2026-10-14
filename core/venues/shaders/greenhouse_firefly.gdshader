shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Fireflies drifting among the planting at night. Each is a small quad, always facing the eye,
// wandering lazily round where it was put (INSTANCE_CUSTOM: its own phase, how far it roams, how
// often it lights); it glows yellow-green for a second or two, goes dark for a few, and lights
// again somewhere else along its wander. `pulse`, the music, lights more of them at once and
// brighter.

uniform vec4 colour : source_color = vec4(0.75, 1.0, 0.35, 1.0);
uniform float strength = 2.2;
uniform float pulse = 0.0;

varying float lit;

void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2831853;
	float roam = INSTANCE_CUSTOM.y;
	float t = TIME * 0.11;
	vec3 at = MODEL_MATRIX[3].xyz + vec3(sin(t * 1.3 + ph) + 0.5 * sin(t * 2.9 + ph * 3.0),
			0.5 * sin(t * 0.9 + ph * 2.0) + 0.25 * sin(t * 2.3 + ph),
			cos(t * 1.1 + ph * 1.7) + 0.5 * cos(t * 2.7 + ph * 5.0)) * roam;
	// A slow blink: on for a little of each cycle, more of it when the music is up.
	float cycle = fract(TIME / (2.5 + INSTANCE_CUSTOM.z * 4.0) + INSTANCE_CUSTOM.x);
	float on = mix(0.3, 0.6, pulse);
	lit = smoothstep(0.0, 0.08, cycle) * smoothstep(on, on - 0.15, cycle);
	lit *= 1.0 + pulse * 1.2;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(at, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.0, 0.35, d);
	float halo = (1.0 - smoothstep(0.2, 1.0, d)) * 0.35;
	// One right at the eye would be a blot, not a spark: those fade.
	float near = smoothstep(0.3, 1.2, -VERTEX.z);
	ALBEDO = colour.rgb * strength * lit * near * (core + halo);
}
