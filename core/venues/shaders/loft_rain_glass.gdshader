shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;

// The loft's old glass in a downpour. Rain beads on it and runs: fixed beads, scattered and
// trembling, and runnels that slide down in fits, each leaving a wet trail. Every bead is a
// small lens -- what is behind the glass is seen through it bent and upside down a little, and
// the room's lights catch on its top as a highlight -- so a city at night past streaming glass is
// a blur of points. When the lightning goes (`flash`), the glass lights from outside.
//
// Laid out in world space on the pane's own plane (a wall pane stands at one x or one z), so
// every pane can share the one material and the drops still differ from bay to bay.

uniform vec4 tint : source_color = vec4(0.5, 0.58, 0.6, 1.0);
uniform float clear_alpha = 0.06;
uniform float flash = 0.0;
uniform sampler2D behind : hint_screen_texture, filter_linear_mipmap;

varying vec3 world;
varying vec3 wnormal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Beads sitting on the glass: one per cell, some cells empty. Returns the bead's slope (xy) and
// how much of it is here (z).
vec3 beads(vec2 p, float scale) {
	vec2 q = p * scale;
	vec2 cell = floor(q);
	vec2 f = fract(q) - 0.5;
	float h = hash(cell);
	vec2 at = (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.6;
	// A bead trembles when a gust hits the glass.
	at.y += sin(TIME * 7.0 + h * 50.0) * 0.015 * step(0.7, h);
	float r = mix(0.08, 0.26, hash(cell + 11.3)) * step(0.35, h);
	vec2 d = f - at;
	d.y *= 1.25;
	float in_bead = smoothstep(r, r * 0.8, length(d));
	return vec3(d / max(r, 1e-3) * in_bead, in_bead);
}

// Runnels: in columns, a drop sliding down in jerks and the wet trail it leaves above it.
vec3 runnels(vec2 p) {
	float col_w = 0.07;
	float col = floor(p.x / col_w);
	float h = hash(vec2(col, 1.7));
	if (h < 0.45) {
		return vec3(0.0);
	}
	float x = (fract(p.x / col_w) - 0.5) * col_w;
	// The runnel wanders a little across its column as it goes down.
	x -= sin(p.y * (3.0 + h * 5.0) + h * 20.0) * col_w * 0.18;
	float speed = mix(0.25, 0.7, hash(vec2(col, 5.3)));
	float t = TIME * speed + h * 13.0;
	// Down in fits: it hangs, then slips.
	float jerk = floor(t) + smoothstep(0.55, 1.0, fract(t));
	float period = 3.4;
	float y_drop = period - mod(jerk * 0.6, period);
	float y = mod(p.y + h * 3.0, period);
	float dy = y - y_drop;
	float drop_r = 0.012 + 0.008 * h;
	vec2 d = vec2(x, dy * 0.8);
	float head = smoothstep(drop_r, drop_r * 0.6, length(d));
	// The trail: above the drop, thin, beading up as it dries.
	float trail_w = 0.0035 * (1.0 + 0.6 * sin(dy * 90.0 + h * 9.0));
	float trail = smoothstep(trail_w, trail_w * 0.4, abs(x)) * step(0.0, dy) * smoothstep(1.4, 0.0, dy);
	return vec3(d / drop_r * head + vec2(x / 0.004, 0.0) * trail * 0.3, max(head, trail * 0.7));
}

void fragment() {
	// The pane's plane: a wall along x (normal z) or along z (normal x).
	vec2 p = abs(wnormal.z) > abs(wnormal.x) ? vec2(world.x, world.y) : vec2(world.z, world.y);
	vec3 a = beads(p, 22.0);
	vec3 b = beads(p + 3.7, 38.0);
	vec3 r = runnels(p);
	vec2 slope = a.xy * a.z + b.xy * b.z * 0.7 + r.xy;
	float wet = clamp(a.z + b.z + r.z, 0.0, 1.0);
	// Through the water: what is behind, bent by each bead's curve.
	vec2 bent = SCREEN_UV - slope * vec2(0.012, -0.018);
	vec3 seen = textureLod(behind, bent, 1.5).rgb;
	vec3 sky_lit = vec3(0.75, 0.82, 1.0) * flash * 0.6;
	ALBEDO = mix(tint.rgb * 0.08, seen * 1.1 + sky_lit, wet);
	ALPHA = mix(clear_alpha + flash * 0.25, 0.92, wet);
	// The bead's surface for the room's lights to catch: tipped by its slope (near enough in
	// view space, since glass is looked at more or less face on).
	NORMAL = normalize(NORMAL + vec3(slope.x, slope.y, 0.0) * 0.35);
	ROUGHNESS = mix(0.08, 0.02, wet);
	SPECULAR = 0.6;
	EMISSION = sky_lit * (1.0 - wet) * 0.5;
}
