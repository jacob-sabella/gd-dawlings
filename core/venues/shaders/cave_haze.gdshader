shader_type spatial;
// Heat haze over the lava tube's river: a tall pane standing over the channel that bends what
// is behind it -- the far wall, the glow -- with a rising, wavering ripple. Strongest low down
// over the lava, gone by head height over the room. Turned to face you about its upright, so it
// never shows as a sheet edge on. Invisible itself: it only moves the picture.

render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.006;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	// Turned about its own upright to face the eye.
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_eye = INV_VIEW_MATRIX[3].xyz - origin;
	to_eye = normalize(to_eye - up * dot(to_eye, up));
	vec3 across = normalize(cross(up, to_eye));
	vec3 at = origin + across * VERTEX.x * length(MODEL_MATRIX[0].xyz) + up * VERTEX.y * length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX;
	VERTEX = at;
}

void fragment() {
	vec2 p = UV * vec2(6.0, 4.0) + vec2(0.0, TIME * 0.9);
	vec2 wobble = vec2(vnoise(p) - 0.5, vnoise(p + 5.3) - 0.5);
	// Strongest at the foot over the lava, nothing at the top or the ends.
	float fade = smoothstep(0.0, 0.5, UV.y) * smoothstep(0.0, 0.2, UV.x) * smoothstep(0.0, 0.2, 1.0 - UV.x);
	vec2 shift = wobble * strength * fade;
	ALBEDO = textureLod(screen, SCREEN_UV + shift, 0.0).rgb;
	ALPHA = fade;
}
