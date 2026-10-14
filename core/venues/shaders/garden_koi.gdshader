shader_type spatial;
render_mode cull_disabled;

// The koi, swimming slow loops under the pond's surface. Each instance's transform puts its loop's
// centre in the pond (and scales the fish); where on the loop it is comes from here, from its
// INSTANCE_CUSTOM: (half the loop's length across X, half across Z -- both in the fish's own
// scaled units -- how fast round, negative for the other way, and where it starts). The loop
// wanders in and out a little so the fish do not run on rails, each faces the way it swims, and
// its tail sweeps. Its pattern -- kohaku, sanke, showa, ogon, chagoi -- comes from its start.
// GardenVenue.koi_point() is the same loop, for its tests.

uniform float pace = 1.0;
uniform vec4 white : source_color = vec4(0.95, 0.93, 0.88, 1.0);
uniform vec4 red : source_color = vec4(0.9, 0.25, 0.08, 1.0);
uniform vec4 black : source_color = vec4(0.05, 0.05, 0.06, 1.0);
uniform vec4 gold : source_color = vec4(0.95, 0.65, 0.2, 1.0);

varying vec3 body;
varying float kind;

vec3 loop(float a, vec4 c) {
	return vec3(cos(a) * c.x * (1.0 + 0.15 * sin(a * 3.0 + c.w)), 0.0,
			sin(a) * c.y * (1.0 + 0.12 * sin(a * 2.0 + c.w * 1.7)));
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float a = TIME * c.z * pace + c.w;
	vec3 here = loop(a, c);
	vec3 fwd = normalize(loop(a + 0.01 * sign(c.z), c) - here);
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec3 v = VERTEX;
	body = v;
	// The tail sweeps, more toward its tip; the head barely.
	float tail = smoothstep(0.15, -0.5, v.x);
	v.z += sin(TIME * 4.0 * pace + c.w * 13.0 + v.x * 6.0) * 0.07 * tail;
	// A slow rise and fall as it swims.
	here.y += sin(a * 2.0 + c.w) * 0.2;
	mat3 turn = mat3(fwd, vec3(0.0, 1.0, 0.0), -side);
	VERTEX = here + turn * v;
	NORMAL = turn * NORMAL;
	kind = fract(c.w * 7.31);
}

float hash(vec2 p) {
	// Not sin(): on a GPU its precision runs out far from zero and the noise breaks into blocks.
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), u.x), u.y);
}

void fragment() {
	// Patches over the back, from the fish's own shape and a seed of its own.
	vec2 q = body.xz * 7.0 + vec2(kind * 31.0, kind * 17.0);
	float patch = vnoise(q) * 0.7 + vnoise(q * 2.3) * 0.3;
	float spots = vnoise(q * 1.7 + 5.0);
	float belly = smoothstep(0.0, -0.06, body.y);
	vec3 col;
	if (kind < 0.35) {
		// Kohaku: white, red over the back.
		col = mix(white.rgb, red.rgb, smoothstep(0.48, 0.55, patch));
	} else if (kind < 0.55) {
		// Sanke: kohaku with black spots.
		col = mix(white.rgb, red.rgb, smoothstep(0.5, 0.56, patch));
		col = mix(col, black.rgb, smoothstep(0.72, 0.76, spots));
	} else if (kind < 0.7) {
		// Showa: black, with red and white.
		col = mix(black.rgb, red.rgb, smoothstep(0.5, 0.56, patch));
		col = mix(col, white.rgb, smoothstep(0.66, 0.7, spots));
	} else if (kind < 0.88) {
		// Ogon: all gold, metallic.
		col = gold.rgb;
	} else {
		// Chagoi: a big plain brown one.
		col = vec3(0.45, 0.32, 0.18);
	}
	col = mix(col, white.rgb * 0.9, belly * 0.6);
	ALBEDO = col;
	METALLIC = kind >= 0.7 && kind < 0.88 ? 0.55 : 0.05;
	ROUGHNESS = 0.35;
	// Seen through the water they lose some of the light; give a little back so the colours read.
	EMISSION = col * 0.12;
}
