shader_type spatial;
render_mode cull_disabled;

// Sandstone in beds. The colour comes from the height in the world, not from the mesh, so every
// wall, butte and boulder in the place is cut from the same layer cake: bands of brick red, rust,
// cream and a mauve shale, the boundaries wavering a little, streaked down the cliffs with desert
// varnish where water ran. Ledges (anything facing up) carry the pale sand blown onto them.

uniform vec4 red_bed : source_color = vec4(0.55, 0.22, 0.12, 1.0);
uniform vec4 rust_bed : source_color = vec4(0.68, 0.36, 0.18, 1.0);
uniform vec4 pale_bed : source_color = vec4(0.74, 0.52, 0.36, 1.0);
uniform vec4 shale_bed : source_color = vec4(0.42, 0.26, 0.24, 1.0);
uniform vec4 sand : source_color = vec4(0.62, 0.42, 0.28, 1.0);
uniform vec4 varnish : source_color = vec4(0.12, 0.07, 0.05, 1.0);
// How thick a bed is, on average, in metres; and the height of the bed at y = 0.
uniform float bed = 3.2;
// (Shifted four beds up so the foot of every wall, and the boulders fallen from it, is in the red
// and the rust; the pale beds that grey out under the moon are left out of reach.)
uniform float bed_offset = 12.8;
// Over everything: how bright (the night's walls are the same stone, seen by less light).
uniform float brightness = 1.0;
// How much of the blown sand lies on what faces up: ledges hold it, round boulders shed it.
uniform float ledge_sand = 0.85;

varying vec3 world;
varying vec3 world_normal;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	// Quintic easing: no creases at the lattice, so no grid of squares shows in the stone.
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	// Each octave turned against the last, so their lattices never line up into steps.
	mat3 turn = mat3(vec3(0.0, 0.8, 0.6), vec3(-0.8, 0.36, -0.48), vec3(-0.6, -0.48, 0.64));
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p = turn * p * 2.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 bed_colour(float which) {
	float pick = hash3(vec3(which, 3.0, 7.0));
	return pick < 0.3 ? red_bed.rgb : (pick < 0.6 ? rust_bed.rgb : (pick < 0.82 ? pale_bed.rgb : shale_bed.rgb));
}

void fragment() {
	// The beds: which one this height is in, the boundaries wavering over tens of metres and
	// rippling over a few, and each bed fading into the next over a hand's breadth or two.
	float y = world.y + bed_offset + (fbm(world * 0.03) - 0.5) * 3.0
			+ (fbm(world * 0.22 + 11.0) - 0.5) * 0.9;
	float k = y / bed;
	float which = floor(k);
	float f = fract(k);
	vec3 c = bed_colour(which);
	c = mix(c, bed_colour(which - 1.0), smoothstep(0.14, 0.0, f) * 0.5);
	c = mix(c, bed_colour(which + 1.0), smoothstep(0.86, 1.0, f) * 0.5);
	// Within a bed, fine laminations and cross-bedding.
	float lam = sin((y + fbm(world * 0.4) * 1.5) * 9.0) * 0.5 + 0.5;
	c *= 0.86 + 0.14 * lam;
	// Grain and blotch.
	float grain = fbm(world * 2.3);
	c *= 0.88 + 0.24 * grain;
	// Varnish: dark streaks hanging down the faces from the rims of ledges.
	float steep = 1.0 - abs(world_normal.y);
	float streak = smoothstep(0.55, 0.85, fbm(vec3(world.x * 0.35, world.y * 0.025, world.z * 0.35)));
	c = mix(c, varnish.rgb, streak * steep * 0.55);
	// Sand lying on whatever faces up.
	float ledge = smoothstep(0.55, 0.85, world_normal.y);
	c = mix(c, sand.rgb * (0.9 + 0.2 * grain), ledge * ledge_sand);
	ALBEDO = c * brightness;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
