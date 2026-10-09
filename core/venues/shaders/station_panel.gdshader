shader_type spatial;

// The station's skin: flush panels in a grid, a dark seam between each, a fastener near every
// corner, and the odd panel a shade off its neighbours where it was replaced. Panels come from
// world position, so one material does the walls, the ceiling and the deck and every piece
// lines up with the next. A few wall panels carry a small status light.

uniform vec4 base : source_color = vec4(0.62, 0.64, 0.66, 1.0);
uniform vec4 seam : source_color = vec4(0.08, 0.085, 0.09, 1.0);
// A panel's size along the surface (across, up -- or x, z on a floor), and its seam's width.
uniform vec2 panel = vec2(1.2, 0.6);
uniform float seam_width = 0.008;
uniform float roughness_base = 0.55;
uniform float metal = 0.2;
// How much one panel's shade differs from the next.
uniform float mottle = 0.06;
// Status lights: the share of panels with one, and its colour.
uniform float lights = 0.0;
uniform vec4 light_colour : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float light_energy = 2.0;

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
	vec2 uv;
	if (abs(wnormal.y) > 0.5) {
		uv = world.xz;
	} else {
		uv = vec2(abs(wnormal.x) > abs(wnormal.z) ? world.z : world.x, world.y);
	}
	vec2 cell = floor(uv / panel);
	vec2 f = fract(uv / panel) * panel;
	// Distance to the nearest seam, in metres.
	vec2 edge = min(f, panel - f);
	float line = 1.0 - smoothstep(seam_width * 0.5, seam_width, min(edge.x, edge.y));
	float h = hash(cell);
	vec3 c = base.rgb * (1.0 + (h - 0.5) * 2.0 * mottle);
	// Fasteners, 4 cm in from each corner.
	vec2 bolt = abs(edge - vec2(0.04));
	float b = 1.0 - smoothstep(0.006, 0.009, length(bolt));
	c = mix(c, seam.rgb * 2.0, b * 0.7);
	c = mix(c, seam.rgb, line);
	vec3 glow = vec3(0.0);
	if (abs(wnormal.y) < 0.5 && h > 1.0 - lights) {
		// A small rectangle near the panel's upper right.
		vec2 at = f - panel * vec2(0.82, 0.78);
		float lamp = (1.0 - smoothstep(0.012, 0.016, abs(at.x))) * (1.0 - smoothstep(0.006, 0.01, abs(at.y)));
		// A quarter of them amber, the rest the station's colour.
		vec3 tint = h > 1.0 - lights * 0.25 ? vec3(1.0, 0.35, 0.2) : light_colour.rgb;
		glow = tint * lamp * light_energy;
	}
	ALBEDO = c;
	ROUGHNESS = roughness_base + line * 0.3 + (h - 0.5) * 0.1;
	METALLIC = metal;
	EMISSION = glow;
}
