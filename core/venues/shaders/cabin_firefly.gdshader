shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// A firefly over the summer grass: a soft yellow-green point, always facing the eye, that glows
// up and goes out on its own slow beat. Drawn on a GPU particle's quad; how bright it is over
// its life comes from the particle's colour (the process material's ramp), and each one's beat
// from its own index, so neighbours never flash together.

uniform vec4 colour : source_color = vec4(0.75, 1.0, 0.35, 1.0);
uniform float strength = 2.4;

varying float beat;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float h = hash(float(INSTANCE_ID) + 0.37);
	// A slow glow and fade, three or four seconds round, and dark most of the time.
	float t = TIME * (0.22 + h * 0.12) + h * 17.0;
	beat = pow(max(sin(t * 6.2831853), 0.0), 6.0);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float point = exp(-r * r * 14.0) + exp(-r * 5.0) * 0.12;
	ALBEDO = colour.rgb * COLOR.rgb * point * beat * strength;
}
