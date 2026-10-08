shader_type spatial;
render_mode unshaded;

// A tower in a city you will never reach: a black slab with lit windows in a grid, some on,
// most off, and a neon line around the roof. Windows come from world position so every tower
// can share one material and still differ.

uniform vec4 body : source_color = vec4(0.012, 0.004, 0.03, 1.0);
uniform vec4 lit_a : source_color = vec4(1.0, 0.25, 0.8, 1.0);
uniform vec4 lit_b : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform vec4 lit_c : source_color = vec4(1.0, 0.8, 0.35, 1.0);
uniform float energy = 2.2;
uniform float pulse = 0.0;
instance uniform float roof = 30.0;

varying vec3 world;
varying vec3 wnormal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = body.rgb;
	if (abs(wnormal.y) < 0.5) {
		float u = abs(wnormal.x) > abs(wnormal.z) ? world.z : world.x;
		vec2 cell = vec2(floor(u / 1.6), floor(world.y / 2.2));
		vec2 f = vec2(fract(u / 1.6), fract(world.y / 2.2));
		float window = step(0.25, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.75);
		float h = hash(cell + floor(world.xz * 0.05) * 13.0);
		float on = step(0.72, h);
		vec3 tint = h > 0.92 ? lit_c.rgb : (h > 0.82 ? lit_b.rgb : lit_a.rgb);
		c += tint * window * on * energy * (0.6 + 0.4 * sin(TIME * 0.3 + h * 40.0));
		// The roofline.
		float edge = 1.0 - smoothstep(0.0, 0.35, roof - world.y);
		c += lit_b.rgb * edge * energy * 1.5 * (1.0 + pulse);
	}
	ALBEDO = c;
}
