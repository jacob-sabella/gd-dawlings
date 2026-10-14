shader_type spatial;
// The cave's rock, everywhere: its walls and roof, the ground, the formations. Nothing is a
// texture -- the rock is worked out from where it is in the world, so a wall twenty metres long
// and a stalactite twenty centimetres long have the same grain and no seams.
//
// Three things make the surface: craggy noise at a few scales (the bump, and the colour a
// little); strata, bands of lighter and darker stone laid down in level beds and warped; and,
// for the lava tube, ropes -- pahoehoe's folded skin on the floor and the "bathtub rings" a
// falling flow leaves on the walls. Wet where it is low. Near the lava its cracks glow dull red,
// more so on a loud bar (`pulse`).
//
// `clip_below` / `clip_above` cut it at the glowworm lake's surface: the cave as it is down to
// the water, and its reflection, which is the same cave drawn upside down beneath it.

render_mode cull_back, depth_draw_opaque;

uniform vec3 dark : source_color = vec3(0.05, 0.048, 0.055);
uniform vec3 light : source_color = vec3(0.2, 0.19, 0.21);
uniform vec3 strata_tint : source_color = vec3(0.16, 0.13, 0.12);
// The grain: features this many metres apart, and how hard the bump is.
uniform float scale = 1.6;
uniform float bump = 0.9;
uniform float strata = 0.5;
uniform float ropes = 0.0;
// Wet below this height: darker, glossier.
uniform float wet_below = 0.6;
uniform float roughness_dry = 0.86;
uniform float pulse = 0.0;
// Glows hot near the lava: in the lava tube the rock the channel runs through is lit dull red
// from inside, along its cracks. How near each vertex is to the lava is its colour's red (the
// cave writes it as it builds the rock); this is how hot that is.
uniform float heat = 0.0;
uniform float clip_below = -1000.0;
uniform float clip_above = 1000.0;

varying vec3 world;
varying vec3 world_normal;
varying float near_lava;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	near_lava = COLOR.r;
}

void fragment() {
	if (world.y < clip_below || world.y > clip_above) {
		discard;
	}
	vec3 p = world / scale;
	float n = fbm(p);
	float fine = vnoise(p * 7.0);
	// Beds of stone, level but warped, a few tens of centimetres thick.
	float bed = sin((world.y + n * 1.2) * 5.5);
	float beds = smoothstep(0.55, 0.95, bed) * strata;
	// The ropes: on the floor, folds across the flow (along z) bowed downstream; on the walls,
	// level rings where the flow stood. Both are ridges of a sine with its phase warped.
	float rope_floor = sin(world.z * 7.0 + sin(world.x * 1.3) * 2.2 + n * 3.0);
	float rope_wall = sin(world.y * 9.0 + n * 2.0);
	float floorish = smoothstep(0.4, 0.8, abs(world_normal.y));
	float rope = mix(rope_wall, rope_floor, floorish) * ropes;
	float h = n * 1.4 + fine * 0.25 + beds * 0.35 + rope * 0.25;
	// Bump from the height's screen-space slope: the surface-gradient method, in view space.
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * bump * 0.06 / max(scale, 0.01));

	vec3 col = mix(dark, light, smoothstep(0.25, 0.75, n + fine * 0.15));
	col = mix(col, strata_tint, beds * 0.6);
	col *= 0.85 + 0.3 * smoothstep(-1.0, 1.0, rope) * ropes;
	float wet = 1.0 - smoothstep(wet_below - 0.4, wet_below + 0.4, world.y);
	ALBEDO = col * (1.0 - wet * 0.35);
	ROUGHNESS = mix(roughness_dry, 0.3, wet);
	SPECULAR = 0.35 + wet * 0.2;

	vec3 glow = vec3(0.0);
	if (heat > 0.0) {
		float cracks = pow(1.0 - abs(vnoise(p * 3.1) * 2.0 - 1.0), 10.0);
		// Only some cracks run hot, and dull red: the rock is cooled, not molten.
		float live = smoothstep(0.45, 0.7, vnoise(p * 0.7 + 17.0));
		glow += vec3(1.0, 0.16, 0.02) * heat * near_lava * near_lava * (0.04 + cracks * live * 0.7) * (1.0 + pulse * 0.6);
	}
	EMISSION = glow;
}
