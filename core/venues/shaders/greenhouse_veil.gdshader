shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// The fountain's falling water: thin round veils pouring off the bowls' rims, streaked and
// rippling as they fall, clearest at the lip and breaking up toward the basin. Worked out in the
// model's own space (round its axis and up it), so the veil needs no UVs.

uniform vec4 colour : source_color = vec4(0.82, 0.88, 0.9, 1.0);
uniform float opacity = 0.16;
uniform float speed = 1.6;
uniform float shine = 0.0;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float around = atan(local.z, local.x) * 24.0;
	float y = local.y;
	float streak = vnoise(vec2(around, y * 3.0 + TIME * speed * 3.0));
	streak = streak * 0.7 + vnoise(vec2(around * 3.0, y * 9.0 + TIME * speed * 9.0)) * 0.3;
	// Whole near the lip, in ribbons by the time it lands.
	float ribbons = mix(0.35, 0.0, smoothstep(0.2, 0.75, streak)) * smoothstep(1.2, 0.5, y);
	float a = opacity * (0.4 + 0.9 * streak) - ribbons;
	ALBEDO = colour.rgb;
	ALPHA = clamp(a, 0.0, 0.9);
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	EMISSION = colour.rgb * shine * streak;
}
