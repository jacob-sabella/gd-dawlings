shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// The grid's sea: black water ruled in neon, swelling in from the sun. The swell is a handful of
// travelling sines summed in the vertex shader (with their slope, for the normal); the grid is
// ruled on the undisplaced plan with fwidth, like the floor's, so it rides the swell and stays
// one crisp line wide however far off. Crests glow. The sun lies on it as a broken column of its
// own stripes, found by reflecting the eye off the swell, so the column wobbles as the water does.
// A little see-through, so what stands in it (the pier's piles, the islands' reflections, hung
// upside down under the waterline) shows dimly through.

uniform vec4 water : source_color = vec4(0.006, 0.002, 0.02, 1.0);
uniform vec4 near_colour : source_color = vec4(0.05, 0.95, 1.0, 1.0);
uniform vec4 far_colour : source_color = vec4(1.0, 0.12, 0.78, 1.0);
uniform vec4 sun_top : source_color = vec4(1.0, 0.92, 0.25, 1.0);
uniform vec4 sun_bottom : source_color = vec4(1.0, 0.15, 0.55, 1.0);
uniform vec3 sun_dir = vec3(0.0, 0.06, -1.0);
uniform float cell = 2.0;
uniform float energy = 1.6;
uniform float swell = 1.0;
uniform float opacity = 0.86;
// 0..1, how loud the mix is: rings run out from the pier, and the lines brighten.
uniform float pulse = 0.0;

varying vec3 world;
varying float crest;
varying float fade;

// Direction (xz), wavelength, height, speed.
const vec4 WAVES[4] = vec4[](
	vec4(0.05, 1.0, 17.0, 0.22),
	vec4(-0.45, 0.89, 11.0, 0.13),
	vec4(0.6, 0.8, 7.5, 0.08),
	vec4(-0.15, 0.99, 29.0, 0.16)
);

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(w.xz);
	// The swell dies away before it is finer than the mesh out there.
	fade = swell * (1.0 - smoothstep(70.0, 160.0, dist));
	float h = 0.0;
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec2 dir = normalize(WAVES[i].xy);
		float k = 6.2831853 / WAVES[i].z;
		float speed = sqrt(9.8 / k);
		// Toward +Z, in from the horizon the sun is on.
		float ph = k * dot(dir, w.xz) - k * speed * TIME * 0.35;
		h += WAVES[i].w * sin(ph);
		slope += WAVES[i].w * k * cos(ph) * dir;
	}
	// The beat: a ring out from the pier on every hit.
	float ring = pulse * 0.16 * sin(dist * 0.7 - TIME * 4.0) * exp(-dist * 0.035);
	h = h * fade + ring;
	slope *= fade;
	crest = h;
	VERTEX.y += h;
	world = w + vec3(0.0, h, 0.0);
	NORMAL = normalize(vec3(-slope.x, 1.0, -slope.y));
}

float ruled(vec2 p, float px) {
	vec2 w = fwidth(p);
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(w, vec2(1e-5));
	float line = 1.0 - clamp(min(g.x, g.y) - px * 0.5, 0.0, 1.0);
	float fine = clamp(1.0 - max(w.x, w.y) * 2.2, 0.0, 1.0);
	return line * fine;
}

void fragment() {
	vec2 p = world.xz;
	float dist = length(p);
	// The grid flows in with the water.
	vec2 q = p / cell + vec2(0.0, -TIME * 0.12);
	float lines = ruled(q, 1.3) * exp(-dist * 0.012);
	float lift = clamp(crest * 2.2 + 0.35, 0.0, 1.6);
	vec3 tint = mix(near_colour.rgb, far_colour.rgb, smoothstep(6.0, 70.0, dist));

	// The sun's column: the eye reflected off the swell, near the sun's bearing and below it.
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 eye = normalize(world - CAMERA_POSITION_WORLD);
	vec3 r = reflect(eye, n);
	vec3 sd = normalize(sun_dir);
	float bearing = abs(atan(r.x, -r.z) - atan(sd.x, -sd.z));
	float column = smoothstep(0.17, 0.08, bearing) * step(0.0, r.y) * smoothstep(0.42, 0.02, r.y);
	// Broken into the sun's own bands, thickest toward the horizon, drifting in.
	float band = step(0.42 - 0.3 * smoothstep(10.0, 90.0, dist), fract(p.y * 0.18 + sin(p.x * 0.6) * 0.25 + TIME * 0.25));
	vec3 sun = mix(sun_bottom.rgb, sun_top.rgb, smoothstep(30.0, 140.0, dist));

	ALBEDO = water.rgb;
	// Glossy enough to carry the sky's colour, not so glossy the sun is a white hole in it: the
	// column below draws the sun's light on the water itself.
	ROUGHNESS = 0.22;
	SPECULAR = 0.25;
	METALLIC = 0.0;
	EMISSION = tint * lines * energy * lift * (0.8 + pulse * 0.8)
			+ sun * column * band * 1.1;
	ALPHA = opacity;
}
