shader_type spatial;

// A floor under water: a scanned texture laid by world position, with caustics playing over it --
// the light through the rippled surface far overhead, focused into a moving web of lines. The
// lines are added as light the surface gives back, so they are its own colour, brighter.

#include "res://core/venues/shaders/caustics.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
// How many metres one repeat of the texture covers.
uniform float metres = 2.0;
uniform float metal = 0.0;
// The caustics: the size of one cell of the web in metres, how bright, what colour, how fast.
uniform float cell = 2.4;
uniform float strength = 0.6;
uniform vec4 light : source_color = vec4(0.75, 1.0, 0.95, 1.0);
uniform float speed = 0.45;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world.xz / metres;
	vec3 arm = texture(arm_tex, uv).rgb;
	ALBEDO = texture(albedo_tex, uv).rgb * tint.rgb;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	ROUGHNESS = arm.g;
	AO = arm.r;
	METALLIC = arm.b * metal;
	// Two webs at different sizes and speeds, multiplied, so the lines break up and wander
	// instead of tiling.
	float c = caustic(world.xz / cell, TIME * speed);
	c *= 0.4 + 0.9 * caustic(world.xz / (cell * 1.7) + vec2(0.37, 0.71), TIME * speed * 0.77);
	EMISSION = ALBEDO * light.rgb * c * strength;
}
