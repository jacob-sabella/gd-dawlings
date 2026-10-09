shader_type spatial;

// A stage curtain of velvet: deep folds hanging straight, drawn by bending a flat plane (one
// laid in X/Y, facing +Z) into a wave across it, a little irregular so the folds are not a
// corrugated sheet. Velvet catches light at a grazing angle and swallows it face on: a dark
// face, a bright sheen at the folds' turning edges.

uniform vec4 colour : source_color = vec4(0.32, 0.02, 0.04, 1.0);
uniform vec4 sheen : source_color = vec4(0.9, 0.25, 0.25, 1.0);
// Folds per metre across, and how deep they are.
uniform float folds = 2.2;
uniform float depth = 0.09;

varying float fold;

float wave(float x) {
	return sin(x * folds * 6.2831853) + 0.35 * sin(x * folds * 2.7 * 6.2831853 + 1.3);
}

void vertex() {
	float x = VERTEX.x;
	VERTEX.z += wave(x) * depth;
	// The slope across, for the normal: d/dx of the wave.
	float k = folds * 6.2831853;
	float slope = (cos(x * k) * k + 0.35 * cos(x * k * 2.7 + 1.3) * k * 2.7) * depth;
	NORMAL = normalize(vec3(-slope, 0.0, 1.0));
	fold = wave(x);
}

void fragment() {
	ALBEDO = colour.rgb * (0.75 + 0.25 * fold);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	RIM = 0.8;
	RIM_TINT = 0.6;
	// Velvet's sheen: brightest where the surface is seen edge on.
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	BACKLIGHT = vec3(0.0);
	ALBEDO += sheen.rgb * pow(edge, 3.0) * 0.12;
}
