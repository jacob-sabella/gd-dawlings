shader_type spatial;
render_mode cull_disabled;

// Most things standing out in the temple garden: stone, wood, lacquer, bark, the crowns of the
// trees. A colour (and a scanned texture laid on in world space, when there is one), with in
// winter `snow` lying on whatever faces up. For a MultiMesh of trees or stones, INSTANCE_CUSTOM's
// rgb tints each one and its alpha scales how much snow it holds, so a forest is not one colour.
// Leaves and needles let the light through from behind and stir in the wind (`sway`, in metres
// at a crown's height, by how high above the origin a vertex is).

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform float tex_metres = 1.0;
uniform bool use_custom = false;
uniform float roughness = 0.8;
uniform float metallic = 0.0;
uniform vec4 snow_colour : source_color = vec4(0.86, 0.9, 0.98, 1.0);
uniform float snow = 0.0;
uniform vec4 backlight : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float sway = 0.0;
uniform float sway_height = 5.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);

varying vec3 world;
varying vec3 world_normal;
varying vec4 custom;

void vertex() {
	custom = use_custom ? INSTANCE_CUSTOM : vec4(1.0);
	if (sway > 0.0) {
		vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float k = clamp(VERTEX.y / sway_height, 0.0, 1.5);
		k *= k;
		float t = TIME * 0.8 + root.x * 0.3 + root.z * 0.21;
		VERTEX.x += (sin(t) * 0.7 + sin(t * 2.7 + VERTEX.y) * 0.3) * sway * k;
		VERTEX.z += sin(t * 0.7 + 1.3) * 0.5 * sway * k;
	}
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

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

void fragment() {
	vec3 col = albedo.rgb * custom.rgb;
	if (use_tex) {
		// Triplanar, in world space: blend the three projections by the normal.
		vec3 b = pow(abs(world_normal), vec3(4.0));
		b /= (b.x + b.y + b.z);
		vec3 t = texture(tex, world.zy / tex_metres).rgb * b.x + texture(tex, world.xz / tex_metres).rgb * b.y
				+ texture(tex, world.xy / tex_metres).rgb * b.z;
		col *= t * 1.6;
	}
	vec3 n = FRONT_FACING ? world_normal : -world_normal;
	float lie = snow * custom.a * smoothstep(0.15, 0.6, n.y) * (0.75 + 0.25 * vnoise(world.xz * 4.0 + world.y));
	float cover = clamp(lie * 1.4, 0.0, 1.0);
	ALBEDO = mix(col, snow_colour.rgb, cover);
	ROUGHNESS = mix(roughness, 0.7, cover);
	METALLIC = mix(metallic, 0.0, cover);
	BACKLIGHT = backlight.rgb * custom.rgb * (1.0 - cover);
	EMISSION = emission.rgb;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
