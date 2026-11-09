shader_type spatial;
render_mode cull_back;

// A lit patch cable that shows which way its signal goes: a stipple of small comets runs along it from the
// plug the signal leaves (V = distance along the cable, growing toward the input), each a sharp bright head
// with a fading speckled tail. A quiet source leaves the cable dim with a slow, faint drift; a loud one runs
// fast and hot. A rim of light at the cable's edge keeps it round against the black board.

uniform vec4 tint : source_color = vec4(0.9, 0.7, 0.3, 1.0);
// 0..1: how much the source is putting out.
uniform float level = 0.0;
// 0 (ergonomics: no motion, the stipple stands still and its brightness carries the level) .. 1.
uniform float motion = 1.0;
// The texture's V per metre of cable (CableSweep.tube's uv_repeat).
uniform float uv_per_metre = 40.0;
// Metres from the head of one comet to the next.
uniform float period = 0.055;
// The share of that taken by the comet's tail.
uniform float tail = 0.7;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float along = UV.y / uv_per_metre;
	float speed = (0.03 + level * 0.22) * motion;
	float x = along / period - TIME * speed / period;
	float cell = floor(x);
	float f = fract(x);
	// A comet: sharp at its head (the larger V, the side it travels toward), thinning behind it.
	float body = f < tail ? pow(f / tail, 2.5) : 0.0;
	// The stipple: each comet is a handful of dots round the cable, different from its neighbours.
	float dots = step(0.45, hash(vec2(floor(UV.x * 5.0), cell)));
	float spark = body * mix(0.35, 1.0, dots);
	vec3 base = tint.rgb;
	vec3 hot = mix(base, vec3(1.0), 0.65);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = base * 0.55;
	ROUGHNESS = 0.4;
	CLEARCOAT = 0.6;
	CLEARCOAT_ROUGHNESS = 0.15;
	EMISSION = base * (0.35 + 0.9 * level) + hot * spark * (0.5 + 2.2 * level) + base * rim * (0.5 + 0.8 * level);
}
