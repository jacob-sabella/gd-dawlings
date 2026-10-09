shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// A shaft of sunlight coming down through the water: a soft vertical band, brightest at the
// top and gone by the bottom, its edges feathered, slowly breathing as the surface moves. Drawn
// on two tall quads crossed at right angles, each fading as it turns edge-on to the eye.

uniform vec4 colour : source_color = vec4(0.45, 0.8, 0.75, 1.0);
uniform float strength = 0.12;
uniform float seed = 0.0;

varying float h;

void vertex() {
	// 0 at the shaft's foot, 1 at its top, whichever way the quad's UVs run.
	h = VERTEX.y + 0.5;
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float a = smoothstep(0.0, 0.8, across) * pow(clamp(h, 0.0, 1.0), 1.6) * smoothstep(0.0, 0.15, 1.0 - h);
	a *= smoothstep(0.1, 0.6, abs(dot(NORMAL, VIEW)));
	float breathe = 0.65 + 0.35 * sin(TIME * 0.4 + seed * 6.0) * sin(TIME * 0.23 + seed * 3.0);
	ALBEDO = colour.rgb * a * strength * breathe;
}
