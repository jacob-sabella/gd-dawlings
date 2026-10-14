shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Moonlight coming in through a tall window, as the dust in the air shows it: a sheared prism
// from the glass down to the patch it lays on the floor, faint, strongest near the window and
// gone before the floor, its faces fading as they turn edge-on so it reads as a volume and not as
// a pane. UV.y runs 0 at the glass to 1 on the floor; UV.x across each face.

uniform vec4 colour : source_color = vec4(0.62, 0.72, 1.0, 1.0);
uniform float strength = 0.035;
uniform float pulse = 0.0;

void fragment() {
	float along = UV.y;
	float a = smoothstep(0.0, 0.08, along) * (1.0 - smoothstep(0.35, 1.0, along));
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	a *= smoothstep(0.0, 0.35, across);
	a *= smoothstep(0.05, 0.5, abs(dot(NORMAL, VIEW)));
	float breathe = 0.85 + 0.15 * sin(TIME * 0.3 + UV.x * 2.0);
	ALBEDO = colour.rgb * a * strength * breathe * (1.0 + pulse * 0.4);
}
