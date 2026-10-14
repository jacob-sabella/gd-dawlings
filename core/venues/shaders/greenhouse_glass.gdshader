shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// The glasshouse's glass: old, thin, a little green, with whatever the weather has put on it.
// `rain`: drops beading on every pane and running down the steep ones in wavering runs, each
// leaving a wet trail behind it, fresh drops landing as the old ones go. `dew`: a fine mist of
// condensation, thickest low on the panes where the beds keep the air wet. Worked out in world
// space, so every pane -- the walls, the curved roof, the gable ends -- runs downhill the same
// way and none of them needs UVs.

uniform vec4 tint : source_color = vec4(0.6, 0.68, 0.64, 0.07);
uniform float rain = 0.0;
uniform float dew = 0.0;
uniform vec4 water : source_color = vec4(0.78, 0.82, 0.86, 1.0);
uniform float glint = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Beads: one drop or none in each little cell, renewed now and then as more rain lands.
float beads(vec2 p, float cell, float chance, float renew) {
	vec2 g = p / cell;
	vec2 id = floor(g);
	float epoch = floor(TIME * renew + hash(id) * 7.0);
	float h = hash(id + epoch * 1.37);
	if (h > chance) {
		return 0.0;
	}
	vec2 at = vec2(hash(id + 3.1 + epoch), hash(id + 5.7 + epoch)) * 0.6 + 0.2;
	float r = 0.12 + 0.25 * hash(id + 9.3);
	return smoothstep(r, r * 0.55, length(fract(g) - at));
}

// Runs: a drop sliding down each narrow column of the pane, wavering side to side, its trail
// above it. Returns (drop, trail).
vec2 runs(vec2 p) {
	float col_w = 0.07;
	float id = floor(p.x / col_w);
	float speed = mix(0.25, 0.9, hash(vec2(id, 1.0)));
	float period = 3.0 + hash(vec2(id, 2.0)) * 3.0;
	float head = -fract(TIME * speed / period + hash(vec2(id, 3.0))) * period;
	float local_y = mod(p.y - head, period * 3.0);
	float wobble = sin(p.y * 9.0 + id * 1.7) * 0.18 + sin(p.y * 23.0 + id) * 0.06;
	float x = fract(p.x / col_w) - 0.5 - wobble;
	float drop = smoothstep(0.22, 0.08, length(vec2(x * col_w, (local_y - 0.012) * 0.6)) / 0.01 * 0.1);
	float trail = smoothstep(0.08, 0.02, abs(x)) * smoothstep(0.0, 0.02, local_y) * smoothstep(0.9, 0.0, local_y);
	// Not every column has a run going at once.
	float live = step(0.45, hash(vec2(id, floor(TIME * speed / period + hash(vec2(id, 3.0))))));
	return vec2(drop, trail * 0.6) * live;
}

void fragment() {
	vec3 n = normalize(wnorm);
	float steep = 1.0 - abs(n.y);
	vec3 across = abs(n.y) < 0.98 ? normalize(cross(vec3(0.0, 1.0, 0.0), n)) : vec3(1.0, 0.0, 0.0);
	vec2 p = vec2(dot(wpos, across), wpos.y + (1.0 - steep) * dot(wpos, cross(across, n)));

	float wet = 0.0;
	float trail = 0.0;
	if (rain > 0.0) {
		wet = max(beads(p, 0.03, 0.55, 0.35), beads(p + 0.013, 0.017, 0.4, 0.5) * 0.8);
		vec2 r = runs(p) * smoothstep(0.15, 0.5, steep);
		wet = max(wet, r.x);
		trail = r.y;
		wet *= rain;
		trail *= rain;
	}
	float mist = 0.0;
	if (dew > 0.0) {
		float fine = beads(p, 0.008, 0.6, 0.0);
		float low = 1.0 - smoothstep(0.8, 3.2, wpos.y);
		mist = dew * (0.05 + 0.1 * low + fine * (0.12 + 0.2 * low));
	}
	ALBEDO = mix(tint.rgb, water.rgb, clamp(wet * 0.8 + mist * 1.5, 0.0, 1.0));
	ALPHA = clamp(tint.a + wet * 0.3 + trail * 0.07 + mist, 0.0, 0.85);
	ROUGHNESS = mix(0.05, 0.25, mist * 2.0);
	SPECULAR = 0.35 + wet * 0.4;
	EMISSION = water.rgb * glint * wet;
}
