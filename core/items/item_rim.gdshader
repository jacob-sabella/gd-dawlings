shader_type spatial;
// The colour of whoever holds an item, round its edge: a second pass over its own materials
// (Item.set_rim), brightest where the surface turns away from you. Narrow and not too bright: a
// long flat face held edge-on (a keytar's neck) is all edge, and at full strength it blew out
// to white in the other person's colour.
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform vec4 colour : source_color = vec4(1.0);

void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.5);
	ALBEDO = colour.rgb * edge * 0.75;
}
