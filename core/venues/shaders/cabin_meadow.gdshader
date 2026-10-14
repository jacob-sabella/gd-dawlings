shader_type spatial;

// The ground round the cabin in late summer: a clearing of meadow grass, patchy -- lush where it
// is damp, gone to straw in the dry places, bare earth and needle litter under the firs -- seen
// from far enough that it is a colour, not blades (the blades near the walls are a MultiMesh).

uniform vec4 lush : source_color = vec4(0.12, 0.2, 0.05, 1.0);
uniform vec4 straw : source_color = vec4(0.38, 0.34, 0.16, 1.0);
uniform vec4 earth : source_color = vec4(0.12, 0.09, 0.06, 1.0);
// The clearing's middle and how far it reaches before the woods' floor takes over.
uniform vec2 centre = vec2(0.0, 2.5);
uniform float clearing = 24.0;

varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.1 + 5.3;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float dry = smoothstep(0.4, 0.7, fbm(p * 0.09));
	vec3 c = mix(lush.rgb, straw.rgb, dry);
	// Close detail: the texture of the sward, a darker fleck in it.
	c *= 0.75 + 0.5 * fbm(p * 2.5);
	// Under the trees, out past the clearing: earth and needles.
	float woods = smoothstep(clearing * 0.8, clearing * 1.4, length(p - centre) + fbm(p * 0.05) * 10.0);
	c = mix(c, earth.rgb * (0.8 + 0.4 * noise(p * 1.3)), woods * 0.7);
	ALBEDO = c;
	ROUGHNESS = 0.92;
}
