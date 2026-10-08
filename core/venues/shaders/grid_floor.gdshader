shader_type spatial;
render_mode specular_schlick_ggx;

// The synthwave floor: a black mirror ruled in neon. Lines are drawn in screen space with
// fwidth so they stay one crisp line wide at any distance, and fade out before the grid gets
// finer than a pixel -- which is where a ruled floor turns into moire.

uniform vec4 base_colour : source_color = vec4(0.010, 0.004, 0.028, 1.0);
uniform vec4 near_colour : source_color = vec4(0.05, 0.95, 1.0, 1.0);
uniform vec4 far_colour : source_color = vec4(1.0, 0.12, 0.78, 1.0);
uniform float cell = 1.0;
uniform float energy = 3.2;
// 0..1, how loud the mix is. The grid breathes with it.
uniform float pulse = 0.0;
// The working footprint, outlined brighter: xy = min corner, zw = max corner.
uniform vec4 footprint = vec4(-3.15, -2.15, 3.15, 2.75);
uniform float travel = 0.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float ruled(vec2 p, float px) {
	vec2 w = fwidth(p);
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(w, vec2(1e-5));
	float line = 1.0 - clamp(min(g.x, g.y) - px * 0.5, 0.0, 1.0);
	// Gone before a cell is smaller than a few pixels.
	float fine = clamp(1.0 - max(w.x, w.y) * 2.5, 0.0, 1.0);
	return line * fine;
}

float edge(vec2 p, vec4 r, float px) {
	vec2 w = fwidth(p);
	float dx = min(abs(p.x - r.x), abs(p.x - r.z)) / max(w.x, 1e-5);
	float dz = min(abs(p.y - r.y), abs(p.y - r.w)) / max(w.y, 1e-5);
	bool in_x = p.x > r.x - 0.02 && p.x < r.z + 0.02;
	bool in_z = p.y > r.y - 0.02 && p.y < r.w + 0.02;
	float a = in_z ? 1.0 - clamp(dx - px, 0.0, 1.0) : 0.0;
	float b = in_x ? 1.0 - clamp(dz - px, 0.0, 1.0) : 0.0;
	return max(a, b);
}

void fragment() {
	vec2 p = world.xz;
	float dist = length(p);
	vec2 q = p / cell + vec2(0.0, travel);
	float major = ruled(q, 1.4);
	float minor = ruled(q * 4.0, 0.7) * 0.22;
	float lines = max(major, minor) * exp(-dist * 0.018);
	float border = edge(p, footprint, 2.0);
	// A ripple out from the middle on every beat, riding the pulse.
	float ring = smoothstep(0.35, 0.0, abs(fract(dist * 0.08 - TIME * 0.35) - 0.5)) * pulse * 0.6;
	vec3 tint = mix(near_colour.rgb, far_colour.rgb, smoothstep(3.0, 45.0, dist));
	ALBEDO = base_colour.rgb;
	ROUGHNESS = 0.28;
	SPECULAR = 0.35;
	METALLIC = 0.0;
	EMISSION = tint * lines * energy * (0.75 + pulse * 0.9 + ring)
			+ far_colour.rgb * border * energy * 1.4;
}
