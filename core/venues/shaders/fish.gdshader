shader_type spatial;
render_mode cull_disabled;

// A school of small fish wheeling round the dome. Each instance's transform is left at the
// origin; where it is comes from here, from its INSTANCE_CUSTOM: (when in its sweep it starts,
// how far in or out of the path, height, how fast it sweeps -- negative starts the other way).
// The path runs round the vault's nose and down both its sides, squared off to keep clear of the
// glass; a school sweeps out along it, slows, turns outward, and comes back, never reaching the
// bulkhead. Each fish faces the way it is going, and its tail (the model's -X end) swings.
// DomeVenue.school_point() is the same path, for its tests.

uniform vec3 centre = vec3(0.0, 0.0, -1.4);
uniform vec2 radii = vec2(8.8, 9.8);
uniform float square = 0.3;
uniform float sweep = 2.1;
uniform vec4 colour : source_color = vec4(0.8, 0.86, 0.88, 1.0);
uniform vec4 back : source_color = vec4(0.28, 0.38, 0.44, 1.0);

varying float belly;

vec3 path(float a, float out_by, float h) {
	float c = cos(a);
	float s = sin(a);
	return centre + vec3(sign(c) * pow(abs(c), square) * (radii.x + out_by), h + sin(a * 3.0) * 0.35,
			sign(s) * pow(abs(s), square) * (radii.y + out_by));
}

void vertex() {
	float t = TIME * INSTANCE_CUSTOM.w + INSTANCE_CUSTOM.x;
	float a = -1.5707963 + sweep * sin(t);
	vec3 here = path(a, INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.z);
	vec3 along = normalize(path(a + 0.01, INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.z) - here);
	// How fast along the sweep, and which way: at the ends, where it stops, it turns outward
	// and round rather than flipping on the spot.
	float pace = cos(t) * sign(INSTANCE_CUSTOM.w);
	vec3 outward = normalize(vec3(here.x - centre.x, 0.0, here.z - centre.z));
	vec3 fwd = normalize(along * pace + outward * 0.35 * (1.0 - abs(pace)));
	vec3 side = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(side, fwd);
	vec3 v = VERTEX;
	// The tail swings, more toward its tip; the body barely.
	float tail = smoothstep(0.03, -0.1, v.x);
	v.z += sin(TIME * 11.0 + INSTANCE_CUSTOM.x * 13.0 + v.x * 30.0) * 0.022 * tail;
	belly = clamp(-v.y / 0.015, 0.0, 1.0);
	mat3 turn = mat3(fwd, up, side);
	VERTEX = here + turn * v;
	NORMAL = turn * NORMAL;
}

void fragment() {
	// Dark backs, silver bellies, the way fish are lit from above and seen from below.
	ALBEDO = mix(back.rgb, colour.rgb, belly);
	METALLIC = 0.15;
	ROUGHNESS = 0.3;
	// The flash of a turning flank, catching the light from above.
	RIM = 0.7;
	RIM_TINT = 0.4;
	// Silver holds its own in the murk: a little of the light it catches, given back.
	EMISSION = mix(back.rgb, colour.rgb, belly) * 0.3;
}
