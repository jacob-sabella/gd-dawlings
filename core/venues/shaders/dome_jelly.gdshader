shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// The deep's jellyfish (tools/blender/dome_jelly.py), lit by their own light: a translucent bell
// that pulses -- squeezing in and pushing up, then opening slowly as it sinks back -- trailing
// its arms and tentacles, which lag the bell and sway. Each rises slowly through the water and
// comes back round from below when it has gone out of sight above; where it is, its phase and
// its colour come from its INSTANCE_CUSTOM: (phase 0..1, rise in metres a second, how far it
// has to go before it comes round, hue: 0 cyan to 1 violet).
//
// Added light, so a jelly over a dark sea floor glows and one over nothing is only its own
// colour; the rim of the bell, seen edge on, brightest, as a real one is.
//
// The mesh's UV: u is 0 on the bell and 1 on what hangs from it; v how far down the animal.

uniform vec4 cyan : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform vec4 violet : source_color = vec4(0.75, 0.35, 1.0, 1.0);
uniform float strength = 1.0;

varying float hang;
varying float down;
varying float beat;
varying vec3 tint;

void vertex() {
	hang = UV.x;
	// glTF turns V over on the way out of Blender.
	down = 1.0 - UV.y;
	float phase = INSTANCE_CUSTOM.x;
	float t = TIME * 0.55 + phase * 6.2831853;
	// The beat: a quick squeeze, then a long slow relax.
	float cycle = fract(t / 6.2831853);
	beat = cycle < 0.25 ? smoothstep(0.0, 0.25, cycle) : 1.0 - smoothstep(0.25, 1.0, cycle);
	// The bell squeezes in at its margin and stretches up.
	float bell = 1.0 - hang;
	float margin = smoothstep(0.0, 0.13, down) * bell;
	VERTEX.xz *= 1.0 - 0.22 * beat * margin;
	VERTEX.y += 0.03 * beat * bell * (1.0 - margin);
	// What hangs lags behind and sways, more the further down.
	float lag = hang * down;
	VERTEX.x += sin(t * 0.7 + down * 7.0 + phase * 9.0) * 0.12 * lag;
	VERTEX.z += cos(t * 0.6 + down * 6.0 + phase * 5.0) * 0.1 * lag;
	VERTEX.y += beat * 0.05 * lag;
	// Up through the water, and round again from below.
	float span = INSTANCE_CUSTOM.z;
	float rise = mod(TIME * INSTANCE_CUSTOM.y + phase * span, span) - span * 0.5;
	// A slow wander as it goes.
	vec3 drift = vec3(sin(TIME * 0.05 + phase * 20.0), 0.0, cos(TIME * 0.04 + phase * 13.0)) * 0.8;
	VERTEX += drift + vec3(0.0, rise, 0.0);
	tint = mix(cyan.rgb, violet.rgb, INSTANCE_CUSTOM.w);
	// Fade out as it nears either end of its rise, so it never pops.
	tint *= smoothstep(0.5, 0.4, abs(rise / span));
}

void fragment() {
	float edge = 1.0 - abs(dot(NORMAL, VIEW));
	float bell = 1.0 - hang;
	float glow = bell * (0.12 + 0.6 * pow(edge, 2.0) + 0.35 * beat * smoothstep(0.12, 0.0, down))
			+ hang * (0.35 * (1.0 - down) + 0.08);
	ALBEDO = tint * glow * strength;
}
