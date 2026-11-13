// The composite pass of a MilkScreen (hardware/visuals/milk_screen.gd): the buffer the warp pass just
// drew, as it is shown on the glass. Nothing here feeds back, so a flash or a flip is only for the eye:
// an echo (a zoomed, flipped second copy laid over it), gamma and brightness, a hue turn, saturation, a
// solarize and an invert for the hits, a vignette, and a faint wash of the room's colour so the glass is
// never quite black.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D buf : source_color, filter_linear, repeat_disable;
uniform float gamma = 1.0;
uniform float bright = 1.0;
uniform float hue = 0.0;
uniform float saturate = 1.0;
uniform float echo = 0.0;
uniform float echo_zoom = 1.0;
uniform int echo_orient = 0;
uniform float invert = 0.0;
uniform float solar = 0.0;
uniform float vignette = 0.35;
uniform vec3 wash = vec3(0.01, 0.012, 0.02);
// How far the screen is lit at all: 0 dark glass, 1 the picture (a fade in when it first runs).
uniform float power = 1.0;
// A MilkDrop preset file's composite (MilkPlayer) instead of the built-in looks': worked in gamma space as
// MilkDrop's 8-bit one, the echo mixed in, `bright` its gamma (a multiplier), and its four flags.
uniform float md = 0.0;
uniform float brighten = 0.0;
uniform float darken = 0.0;

vec3 hue_turn(vec3 c, float a) {
	const vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

vec2 echo_uv(vec2 uv) {
	vec2 e = (uv - 0.5) / max(echo_zoom, 0.05);
	if (echo_orient == 1 || echo_orient == 3) {
		e.x = -e.x;
	}
	if (echo_orient == 2 || echo_orient == 3) {
		e.y = -e.y;
	}
	return 1.0 - abs(1.0 - mod(e + 0.5, 2.0));
}

vec3 milkdrop(vec2 uv) {
	vec3 g = pow(clamp(texture(buf, uv).rgb, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2));
	if (echo > 0.001) {
		vec3 e = pow(clamp(texture(buf, echo_uv(uv)).rgb, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2));
		g = mix(g, e, echo);
	}
	g = clamp(g * bright, vec3(0.0), vec3(1.0));
	if (brighten > 0.5) {
		g = sqrt(g);
	}
	if (darken > 0.5) {
		g = g * g;
	}
	if (solar > 0.5) {
		g = g * (1.0 - g) * 4.0;
	}
	if (invert > 0.5) {
		g = 1.0 - g;
	}
	return pow(g, vec3(2.2));
}

void fragment() {
	vec2 uv = UV;
	if (md > 0.5) {
		vec3 m = milkdrop(uv);
		float l = dot(m, vec3(0.2126, 0.7152, 0.0722));
		m += wash * (1.0 - clamp(l * 3.0, 0.0, 1.0));
		ALBEDO = m * power + wash * (1.0 - power);
	} else {
		vec3 c = texture(buf, uv).rgb;
		if (echo > 0.001) {
			vec3 ec = texture(buf, echo_uv(uv)).rgb;
			// The brighter of the two shows through, so the echo adds rather than greys the picture.
			c = mix(c, max(c, ec), echo);
		}
		c = pow(max(c, vec3(0.0)), vec3(1.0 / max(gamma, 0.1)));
		if (abs(hue) > 0.0001) {
			c = max(hue_turn(c, hue * TAU), vec3(0.0));
		}
		float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
		c = max(mix(vec3(luma), c, saturate), vec3(0.0));
		c = mix(c, abs(c - 0.5) * 2.0, solar);
		c = mix(c, clamp(vec3(1.0) - c, 0.0, 1.0), invert);
		vec2 v = uv - 0.5;
		c *= 1.0 - vignette * dot(v, v) * 2.2;
		c += wash * (1.0 - clamp(luma * 3.0, 0.0, 1.0));
		ALBEDO = c * bright * power + wash * (1.0 - power);
	}
}
