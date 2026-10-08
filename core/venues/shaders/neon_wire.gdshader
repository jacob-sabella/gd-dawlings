shader_type spatial;
render_mode unshaded, cull_disabled;

// Solid dark faces with glowing edges. Each triangle's three corners carry (1,0,0), (0,1,0) and
// (0,0,1) in COLOR, so inside a face the smallest component is the distance to its nearest
// edge -- the classic wireframe without a line primitive, which on most GPUs is one pixel wide
// whatever you ask for.

uniform vec4 fill : source_color = vec4(0.02, 0.0, 0.05, 1.0);
uniform vec4 line_colour : source_color = vec4(1.0, 0.15, 0.8, 1.0);
uniform vec4 top_colour : source_color = vec4(0.1, 0.9, 1.0, 1.0);
uniform float energy = 3.0;
uniform float width = 1.3;
uniform float top = 12.0;
uniform float pulse = 0.0;

varying float height;

void vertex() {
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 b = COLOR.rgb;
	vec3 w = fwidth(b);
	vec3 e = smoothstep(vec3(0.0), w * width, b);
	float line = 1.0 - min(min(e.x, e.y), e.z);
	vec3 tint = mix(line_colour.rgb, top_colour.rgb, smoothstep(0.0, top, height));
	ALBEDO = mix(fill.rgb, tint * energy * (1.0 + pulse * 0.5), line);
}
