shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Low sun coming in at a factory window, made visible by the dust in the air. The beam is the
// window's opening swept along the sun's direction, drawn as sheets inside that volume: some
// standing (each through one place across the opening, the window's full height, running on
// along the sun), some lying (each through one height, the opening's full width). Each sheet is one quad, sheared by its instance
// transform so its long side runs along the sun. Sheets are only laid between the bars, and the
// other set of bars is cut out of each sheet here, so the beam comes into the room striped with
// the glazing's shadows -- the same stripes the real sun lays on the concrete under it.
//
// UV.x runs along the beam (0 at the glass); UV.y across the opening. INSTANCE_CUSTOM.x says
// which bars to cut: 0 for a standing sheet (cut the crossbars), 1 for a lying one (cut the
// uprights); INSTANCE_CUSTOM.y is a seed.

uniform vec4 colour : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform float strength = 0.05;
// The opening's bars, as the window builds them (ShellKit.glazed): uprights including the jambs,
// rows of panes, and each bar's width as a share of the opening across and up.
uniform float uprights = 5.0;
uniform float rows = 8.0;
uniform vec2 bar = vec2(0.03, 0.014);
// Where the floor is: the beam thins out just above it rather than stopping in a hard line.
uniform float floor_y = 0.0;

varying float kind;
varying float seed;
varying vec3 world;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	kind = INSTANCE_CUSTOM.x;
	seed = INSTANCE_CUSTOM.y;
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 between the bars, 0 on one: `count` bars evenly from end to end, each `width` wide.
float between(float u, float count, float width) {
	float inset = width * 0.5;
	float span = 1.0 - 2.0 * inset;
	float k = (u - inset) / span * (count - 1.0);
	float d = abs(k - round(k)) * span / (count - 1.0);
	return smoothstep(width * 0.5, width * 0.5 + 0.006, d);
}

void fragment() {
	float along = UV.x;
	float across = UV.y;
	float pane = kind < 0.5 ? between(across, rows + 1.0, bar.y) : between(across, uprights, bar.x);
	float edge = smoothstep(0.0, 0.05, across) * smoothstep(1.0, 0.95, across);
	// Strongest just inside the glass, thinning as the beam goes into the room.
	float fade = pow(1.0 - along, 1.3) * smoothstep(0.0, 0.04, along);
	// Dust: the air is not even, and it turns slowly.
	float dust = 0.5 + 0.5 * noise(world * 1.8 + vec3(seed * 7.0, TIME * 0.06, TIME * 0.04));
	float ground = smoothstep(floor_y + 0.1, floor_y + 1.3, world.y);
	// A sheet seen edge on is a line: fade it as it turns away.
	float facing = smoothstep(0.08, 0.6, abs(dot(NORMAL, VIEW)));
	ALBEDO = colour.rgb * strength * pane * edge * fade * dust * ground * facing;
}
