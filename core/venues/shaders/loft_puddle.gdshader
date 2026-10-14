shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

// Rainwater on the concrete under the windows, where the old frames let it in. Drawn on a flat
// quad a hair over the floor: an irregular pool (its outline from noise, so no two are the same
// shape), still water in the middle that mirrors the room and the windows, a dark wet margin
// round it where the concrete has soaked it up, and rings spreading where drips land in it.
//
// The mirror is traced here rather than left to the renderer, so it holds on the headset too
// (no SSR there): the eye's ray, bounced off the water, is walked up through the picture already
// drawn until it passes behind something, and what is there is what the water shows -- the
// window over it with the rain on it, a pendant, a column. Rippled by the drips. `flash` is the
// lightning, which the water throws back.

uniform vec4 wet : source_color = vec4(0.015, 0.016, 0.02, 1.0);
uniform float drips = 1.0;
uniform float flash = 0.0;
uniform float seed = 0.0;
uniform float mirror = 1.0;
uniform sampler2D seen : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth : hint_depth_texture, filter_nearest;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	// The pool's edge: a circle pushed in and out by noise round it.
	float wobble = noise(c * 2.2 + seed * 5.0) * 0.55 + noise(c * 5.0 + seed * 3.0) * 0.25 - 0.4;
	float r = length(c) + wobble * 0.5;
	float water = smoothstep(0.82, 0.7, r);
	float damp = smoothstep(1.02, 0.82, r);
	if (damp <= 0.001) {
		discard;
	}
	// Drips: rings spreading from a few spots, each on its own beat.
	vec2 n = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float period = 1.3 + hash(vec2(fi, seed)) * 1.7;
		float t = mod(TIME + hash(vec2(seed, fi)) * 9.0, period) / period;
		vec2 at = (vec2(hash(vec2(fi, seed + 1.0)), hash(vec2(fi, seed + 2.0))) - 0.5) * 0.9;
		vec2 d = c - at;
		float dist = length(d);
		float ring = sin((dist - t * 0.6) * 60.0) * exp(-abs(dist - t * 0.6) * 18.0) * (1.0 - t);
		n += normalize(d + 1e-4) * ring * 0.12 * drips;
	}
	// The water's surface, tipped by the rings, in view space. The quad's own normal is up.
	vec3 up = normalize(NORMAL + (VIEW_MATRIX * vec4(n.x, 0.0, n.y, 0.0)).xyz * water);
	// The mirror: march the bounced ray through what is already on screen.
	vec3 ray = reflect(normalize(VERTEX), up);
	vec3 shown = vec3(0.0);
	float found = 0.0;
	vec3 p = VERTEX;
	float stride = 0.08;
	for (int i = 0; i < 28; i++) {
		p += ray * stride;
		stride *= 1.12;
		vec4 clip = PROJECTION_MATRIX * vec4(p, 1.0);
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;
		}
		float z = texture(depth, uv).r;
		vec4 at = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, z, 1.0);
		at.xyz /= at.w;
		float behind = at.z - p.z;
		if (behind > 0.0 && behind < 0.6 + stride) {
			shown = textureLod(seen, uv, 1.0).rgb;
			// Fade toward the picture's edges, where the trace runs out of picture.
			vec2 e = min(uv, 1.0 - uv);
			found = smoothstep(0.0, 0.08, min(e.x, e.y));
			break;
		}
	}
	float fresnel = 0.3 + 0.7 * pow(1.0 - clamp(dot(-normalize(VERTEX), up), 0.0, 1.0), 4.0);
	ALBEDO = wet.rgb;
	ALPHA = mix(damp * 0.6, 0.97, water);
	ROUGHNESS = mix(0.45, 0.03, water);
	SPECULAR = mix(0.4, 0.6, water);
	NORMAL = up;
	EMISSION = (shown * found * fresnel * mirror + vec3(0.7, 0.78, 1.0) * flash * 0.08) * water;
}
