shader_type spatial;

// The temple garden's ground: one mesh, painted by its vertex colours -- red for gravel, green
// for moss, blue for the bare earth of the paths and the pond's bed -- and lit here.
//
// The gravel is raked: in straight furrows across the garden, and in rings round each of the
// placed stones (`stones`: x, z, radius, how far the rings run out), the lines where the two
// patterns meet left as the rake left them. The furrows are only in the shading (a ridge and a
// groove every `rake` metres); the mesh is flat. In winter `snow` lays a blanket over all of it,
// thinnest in the furrows' grooves and under the trees.

uniform sampler2D gravel_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 gravel_tint : source_color = vec4(0.8, 0.79, 0.76, 1.0);
uniform vec4 moss : source_color = vec4(0.18, 0.3, 0.1, 1.0);
uniform vec4 moss_dry : source_color = vec4(0.32, 0.34, 0.14, 1.0);
uniform vec4 earth : source_color = vec4(0.22, 0.18, 0.14, 1.0);
uniform vec4 snow_colour : source_color = vec4(0.86, 0.9, 0.98, 1.0);
uniform float snow = 0.0;
// What lies scattered on the moss and the earth: fallen petals or leaves, tinted, this much.
uniform vec4 litter_colour : source_color = vec4(1.0, 0.8, 0.85, 1.0);
uniform float litter = 0.0;
uniform float rake = 0.16;
uniform vec4 stones[10];
uniform int stone_count = 0;

varying vec3 world;
varying vec3 world_normal;

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

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world.xz;
	// White river gravel: the scan's pebbles for their shape and shading, its brown left out.
	vec3 scan = texture(gravel_tex, p / 0.9).rgb;
	float luma = dot(scan, vec3(0.3, 0.59, 0.11));
	vec3 g = gravel_tint.rgb * (0.45 + 1.1 * luma);
	vec3 gn = texture(gravel_nor, p / 1.1).rgb;

	// The rake: distance across the furrows, and which way across is (for the ridges' slope).
	float across = p.y + sin(p.x * 0.35) * 0.12;
	vec2 dir = vec2(0.0, 1.0);
	for (int i = 0; i < stone_count; i++) {
		vec4 s = stones[i];
		vec2 off = p - s.xy;
		float r = length(off);
		// Inside its rings, a stone's pattern wins: concentric furrows round it.
		if (r > s.z && r < s.z + s.w) {
			across = r - s.z;
			dir = off / max(r, 1e-4);
		}
	}
	float phase = across / rake * 6.2831853;
	float ridge = sin(phase);
	float slope = cos(phase);
	// A groove's floor is shadowed; a ridge's crest catches the light.
	float gravel_shade = 0.82 + 0.18 * ridge;

	vec3 gravel = g * gravel_shade;
	float mn = vnoise(p * 1.7) * 0.6 + vnoise(p * 6.0) * 0.4;
	vec3 moss_col = mix(moss.rgb, moss_dry.rgb, smoothstep(0.35, 0.8, mn));
	vec3 earth_col = earth.rgb * (0.8 + 0.4 * vnoise(p * 3.0));

	vec3 w = COLOR.rgb;
	float total = max(w.r + w.g + w.b, 1e-4);
	w /= total;
	vec3 col = gravel * w.r + moss_col * w.g + earth_col * w.b;

	// Fallen petals or leaves, in drifts on the moss and the paths; few on the raked gravel,
	// which is swept.
	float drift = smoothstep(0.55, 0.85, vnoise(p * 0.9) * 0.5 + vnoise(p * 7.0) * 0.5);
	// Single ones: a small round fleck at a point of its own in some of the cells, not the cell.
	vec2 cell = floor(p * 9.0);
	vec2 at = vec2(hash(cell + 3.7), hash(cell + 9.1)) * 0.6 + 0.2;
	float fleck = smoothstep(0.2, 0.12, length(fract(p * 9.0) - at));
	float speck = step(0.7, hash(cell)) * fleck * smoothstep(0.3, 0.6, vnoise(p * 1.3));
	col = mix(col, litter_colour.rgb, litter * (drift * 0.55 + speck * 0.75) * (1.0 - w.r * 0.85));

	// Snow: a blanket, thinner in the grooves, piling where the ground faces up.
	float lie = snow * smoothstep(0.3, 0.8, world_normal.y);
	float cover = clamp(lie * (0.88 + 0.12 * ridge * w.r) * (0.85 + 0.15 * vnoise(p * 2.3)), 0.0, 1.0);
	col = mix(col, snow_colour.rgb * (0.94 + 0.06 * vnoise(p * 9.0)), cover);

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.9, 0.95, w.g), 0.7, cover);
	SPECULAR = mix(0.3, 0.45, cover);
	// The gravel's own grain, and the furrows' ridges tilting it, in tangent space (the ground
	// is laid with its tangent along +X, so +Y in the map is -Z in the world).
	vec2 tilt = -dir * slope * 0.45 * w.r * (1.0 - cover * 0.6);
	vec3 n = mix(vec3(0.5, 0.5, 1.0), gn, 0.6 * w.r + 0.25 * w.g);
	n.xy += vec2(tilt.x, -tilt.y) * 0.5;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 1.0;
}
