shader_type spatial;

// The city in daylight, seen from the loft on a Sunday morning: towers of stone, brick and
// glass, lit by the low sun (a real light, so the faces turned to it are bright and the others
// in shade). Each tower picks its own facade from where it stands: pale limestone, brick, a
// curtain wall of blue-grey glass, or concrete. Windows are a grid in world space, as on the
// night towers (tower.gdshader): dark glass with the sky in it on a masonry tower, the mullions
// of a curtain wall on a glass one.

uniform vec4 stone : source_color = vec4(0.72, 0.66, 0.56, 1.0);
uniform vec4 brick : source_color = vec4(0.52, 0.3, 0.22, 1.0);
uniform vec4 concrete : source_color = vec4(0.55, 0.55, 0.54, 1.0);
uniform vec4 curtain : source_color = vec4(0.26, 0.34, 0.42, 1.0);
uniform vec4 glass : source_color = vec4(0.16, 0.22, 0.3, 1.0);
uniform vec4 roof : source_color = vec4(0.32, 0.31, 0.3, 1.0);

varying vec3 world;
varying vec3 wnormal;
varying float pick;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// One pick per tower: from its centre, which every vertex of it shares.
	pick = hash(floor(MODEL_MATRIX[3].xz * 0.37) + 0.5);
}

void fragment() {
	vec3 base = pick < 0.35 ? stone.rgb : (pick < 0.6 ? brick.rgb : (pick < 0.8 ? concrete.rgb : curtain.rgb));
	bool is_glass = pick >= 0.8;
	float rough = is_glass ? 0.25 : 0.85;
	float metal = 0.0;
	vec3 c = base * (0.9 + 0.2 * hash(vec2(pick * 91.0, 3.0)));
	if (abs(wnormal.y) < 0.5) {
		float u = abs(wnormal.x) > abs(wnormal.z) ? world.z : world.x;
		vec2 cell = vec2(floor(u / 1.6), floor(world.y / 3.2));
		vec2 f = vec2(fract(u / 1.6), fract(world.y / 3.2));
		if (is_glass) {
			// A curtain wall: glass from floor to floor, thin mullions, a spandrel at each slab.
			float mull = step(0.06, f.x) * step(f.x, 0.94) * step(0.18, f.y);
			c = mix(c * 0.7, glass.rgb * (0.85 + 0.3 * hash(cell)), mull);
			rough = mix(0.6, 0.08, mull);
			metal = mull * 0.4;
		} else {
			float window = step(0.22, f.x) * step(f.x, 0.78) * step(0.28, f.y) * step(f.y, 0.78);
			// Some blinds down, some sky in the glass.
			float blind = step(0.8, hash(cell + floor(world.xz * 0.05) * 13.0));
			vec3 pane = mix(glass.rgb, vec3(0.62, 0.6, 0.55), blind * 0.6);
			c = mix(c, pane, window);
			rough = mix(rough, 0.12, window * (1.0 - blind));
			metal = window * (1.0 - blind) * 0.3;
		}
	} else {
		c = roof.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
}
