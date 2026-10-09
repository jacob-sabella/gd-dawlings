shader_type spatial;

// Hazard paint: yellow and black diagonal stripes, worn. Stripes come from world position, so a
// curved reveal is striped without needing its UVs laid out for it.

uniform vec4 paint : source_color = vec4(0.85, 0.62, 0.05, 1.0);
uniform vec4 ink : source_color = vec4(0.03, 0.03, 0.03, 1.0);
uniform float width = 0.08;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float s = step(0.5, fract((world.x + world.y + world.z) / (width * 2.0)));
	ALBEDO = mix(paint.rgb, ink.rgb, s);
	ROUGHNESS = 0.6;
}
