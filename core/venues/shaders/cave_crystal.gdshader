shader_type spatial;
// The crystal grotto's crystals: amethyst and ice-blue quartz, lit from within.
//
// One material for every crystal, the colour each one's own (the MultiMesh's custom data: rgb
// the tint, a how brightly it glows). The glow is strongest in the crystal's heart -- its root,
// where it is thickest (cave_crystals.glb's UV runs root to point) -- and where you look into a
// face straight on, falling off to a dark glassy edge where a face turns away. Inside, clouds of
// inclusions: noise looked up a little way INTO the stone along your line of sight, so they
// drift against the faces as you move, which is what reads as depth in a clear stone rather than
// paint on its skin. Every facet takes the light a little differently (the faces are flat, so a
// face's normal is its own). Each crystal breathes on its own slow beat, and all swell together
// on a loud bar (`pulse`).

render_mode cull_back;

uniform float glow = 1.0;
uniform float pulse = 0.0;

varying vec4 tint;
varying float seed;
varying vec3 world;
varying vec3 world_normal;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	tint = INSTANCE_CUSTOM;
	seed = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float along = 1.0 - UV.y;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float facet = fract(sin(dot(floor(world_normal * 4.0 + 0.5), vec3(12.9898, 78.233, 37.719)) + seed * 7.0) * 43758.5453);
	vec3 ray = normalize(world - CAMERA_POSITION_WORLD);
	float cloud = vnoise((world + ray * 0.12) * 5.0 + seed * 9.0) * 0.6 + vnoise((world + ray * 0.35) * 2.2 + seed * 3.0) * 0.6;
	float bands = 0.92 + 0.08 * sin(along * 60.0 + seed * 20.0);
	float heart = mix(1.0, 0.3, along) * bands;
	float inner = pow(facing, 1.4) * (0.5 + 0.7 * facet) * (0.35 + cloud);
	float breathe = 0.82 + 0.18 * sin(TIME * (0.4 + seed * 0.5) + seed * 40.0);
	float lift = 1.0 + pulse * 1.6;
	// Deepened: a gem's colour is richest looking into it, never a pastel.
	vec3 deep = pow(tint.rgb, vec3(1.5));
	ALBEDO = deep * 0.2;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = deep * tint.a * glow * (0.05 + inner * heart) * breathe * lift;
}
