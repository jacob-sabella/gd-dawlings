shader_type spatial;

// The pavilion's and the hall's tiled roofs (garden_roof.glb's "tiles"): smoked grey tiles laid
// in rows of round caps over channels, drawn from the roof's UVs (U along the eave, V up the
// slope, in metres; tools/blender/garden_roof.py), so the slope needs no geometry for them. Each
// course a little darker at its lower lip; each tile a shade of its own. In winter `snow` lays a
// blanket over the slopes, the caps' lines still showing through it.

uniform vec4 tile : source_color = vec4(0.25, 0.27, 0.3, 1.0);
uniform vec4 snow_colour : source_color = vec4(0.86, 0.9, 0.98, 1.0);
uniform float snow = 0.0;
// The round tiles' pitch along the eave (the model's), and a course's length up the slope.
uniform float pitch = 0.3;
uniform float course = 0.32;

varying vec3 world_normal;

float hash(vec2 p) {
	// Not sin(): on a GPU its precision runs out far from zero and the noise breaks into blocks.
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float u = UV.x / pitch;
	float v = UV.y / course;
	float cell = floor(u);
	float f = fract(u) - 0.5;
	// A cap is round over the middle 45% of the pitch; a channel is shallow and concave between.
	float cap = 0.22;
	float on_cap = step(abs(f), cap);
	float hx = on_cap > 0.5 ? sqrt(max(1.0 - (f / cap) * (f / cap), 0.0)) : -0.15 * (1.0 - pow((abs(f) - cap) / (0.5 - cap) * 2.0 - 1.0, 2.0));
	float dh = on_cap > 0.5 ? -(f / cap) / max(sqrt(max(1.0 - (f / cap) * (f / cap), 0.01)), 0.1) : 0.0;
	float lip = fract(v);
	// Toward a course's lower edge the next one's overlap shades it.
	float overlap = smoothstep(0.0, 0.12, lip);
	float shade = (0.7 + 0.3 * hx) * (0.75 + 0.25 * overlap);
	float own = 0.9 + 0.2 * hash(vec2(cell, floor(v)));
	vec3 col = tile.rgb * shade * own;
	float up = smoothstep(0.25, 0.6, world_normal.y);
	float cover = clamp(snow * up * (0.82 + 0.18 * (1.0 - on_cap * (1.0 - hx))), 0.0, 1.0);
	col = mix(col, snow_colour.rgb * (0.86 + 0.14 * hx), cover);
	ALBEDO = col;
	ROUGHNESS = mix(0.42 + 0.25 * (1.0 - hx), 0.75, cover);
	METALLIC = mix(0.15, 0.0, cover);
	SPECULAR = 0.5;
	// The caps' roundness, across the slope (tangent X is along U).
	vec2 tilt = vec2(clamp(dh, -2.5, 2.5) * 0.25 * on_cap, (1.0 - overlap) * 0.35) * (1.0 - cover * 0.7);
	NORMAL_MAP = normalize(vec3(-tilt.x, tilt.y, 1.0)) * 0.5 + 0.5;
}
