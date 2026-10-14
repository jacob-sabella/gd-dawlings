shader_type spatial;
// The glowworm lake: black, still water. It cannot reflect anything on a headset's renderer, so
// the cave builds its own reflection -- the roof, the glowworms and the shore drawn upside down
// under the surface (cave_rock / cave_glowworm with `clip_above`) -- and this is a dark film
// laid over it, clearer looking straight down and closing up toward the far shore as a real
// surface does (Fresnel the other way round: there the sky's reflection would win, and the sky
// here is rock). Now and then a drip falls from the roof: a ring spreads from where it lands and
// the lanterns' highlights wobble in it.

render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 colour : source_color = vec3(0.004, 0.012, 0.016);
// How much of the reflection under it shows through, straight down and at a glance.
uniform float clear_down = 0.55;
uniform float clear_glance = 0.75;
uniform float ripple = 1.0;

varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Drips: a few landing spots at once, each a ring that grows and fades over four seconds
	// and then moves somewhere else, on a grid of 6 m cells so they spread over the lake.
	vec2 slope = vec2(0.0);
	vec2 cell = floor(world.xz / 6.0);
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2 c = cell + vec2(float(i), float(j));
			float phase = hash(c);
			float t = TIME * 0.25 + phase;
			float round_no = floor(t);
			float age = fract(t) * 4.0;
			vec2 at = (c + vec2(hash(c + round_no), hash(c * 1.7 + round_no))) * 6.0;
			vec2 d = world.xz - at;
			float r = length(d);
			float front = age * 0.45;
			float ring = exp(-pow((r - front) * 9.0, 2.0)) * exp(-age * 0.9) * step(0.001, r);
			slope += normalize(d + 1e-4) * ring * sin((r - front) * 30.0);
		}
	}
	// And a slow breath across the whole surface, so it is never quite glass.
	slope += vec2(sin(world.x * 0.7 + TIME * 0.3), cos(world.z * 0.6 - TIME * 0.23)) * 0.03;
	vec3 n = normalize(vec3(-slope.x * 0.25 * ripple, 1.0, -slope.y * 0.25 * ripple));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = colour;
	ROUGHNESS = 0.04;
	SPECULAR = 0.6;
	METALLIC = 0.0;
	ALPHA = 1.0 - mix(clear_glance, clear_down, facing);
}
