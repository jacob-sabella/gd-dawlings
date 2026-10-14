shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// A moving head's beam in the haze: an open cone, brightest down its middle and near the lens,
// fading out along its reach. Where it meets anything -- the deck, the crowd, a truss -- it
// fades into it over the last metre (the depth behind it) instead of ending in a hard cut, and
// it thins out right in front of the eye so a beam swept through you is not a wall of light.
// Drawn on an open CylinderMesh, the narrow end up at the lens.

uniform vec4 colour : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float strength = 0.06;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying float along;

void vertex() {
	along = clamp(0.5 - VERTEX.y, 0.0, 1.0);
}

void fragment() {
	float through = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float a = pow(through, 2.0) * (1.0 - along * 0.85) * smoothstep(1.0, 0.7, along);
	// How far behind this fragment the scene is: soft where the beam meets a surface.
	float scene = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	float behind = -view.z / view.w;
	float here = -VERTEX.z;
	a *= smoothstep(0.0, 1.2, behind - here);
	// Near the eye: thin it out.
	a *= smoothstep(0.4, 3.0, here);
	ALBEDO = colour.rgb * a * strength;
}
