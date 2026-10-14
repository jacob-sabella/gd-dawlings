shader_type spatial;
// Mist lying low on a cave floor: a sheet a hand or two off the ground, its density a slow-moving
// noise, thinning toward the edges of the sheet and to nothing over the working floor, so it
// gathers round the room rather than over the desk. Lit by nothing but the room's own light
// (`tint` is the colour it takes on), a little brighter on a loud bar.

render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.3, 0.3, 0.4);
uniform float density = 0.25;
uniform float drift = 0.05;
uniform float pulse = 0.0;
// The working floor, in world xz (x0, z0, x1, z1): kept clear, the mist feathering in past it.
uniform vec4 keep_clear = vec4(-6.0, -3.0, 6.0, 7.0);
uniform float feather = 1.5;

varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz * 0.35;
	float t = TIME * drift;
	float n = vnoise(p + vec2(t, t * 0.6)) * 0.6 + vnoise(p * 2.3 - vec2(t * 1.4, 0.0)) * 0.4;
	n = smoothstep(0.3, 0.85, n);
	vec2 out_x = max(keep_clear.xy - world.xz, world.xz - keep_clear.zw);
	float outside = clamp(max(out_x.x, out_x.y) / feather, 0.0, 1.0);
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(0.0, 0.25, 1.0 - UV.x)
			* smoothstep(0.0, 0.25, UV.y) * smoothstep(0.0, 0.25, 1.0 - UV.y);
	// Fades where you look along it edge on, or the sheet shows as a line.
	float facing = abs(dot(NORMAL, VIEW));
	ALBEDO = tint * (1.0 + pulse * 0.4);
	ALPHA = n * density * outside * edge * smoothstep(0.05, 0.35, facing);
}
