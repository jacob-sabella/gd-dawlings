shader_type spatial;

// Solar cells, for the station's arrays and the docked ship's wings: a blanket of dark blue cells
// in a fine silver grid, laid out in bays, and glassy enough to take the sun's glint. The
// blanket's UV runs 0..1 across its face (tools/blender/station_array.py, station_ship.py).

uniform vec2 cells = vec2(16.0, 48.0);
uniform vec2 bays = vec2(2.0, 6.0);
uniform vec4 cell : source_color = vec4(0.03, 0.05, 0.14, 1.0);
uniform vec4 grid : source_color = vec4(0.5, 0.52, 0.56, 1.0);

void fragment() {
	vec2 at = UV * cells;
	vec2 f = abs(fract(at) - 0.5);
	float line = smoothstep(0.42, 0.47, max(f.x, f.y));
	vec2 b = abs(fract(UV * bays) - 0.5);
	float gap = smoothstep(0.485, 0.495, max(b.x, b.y));
	// Each cell a shade apart, so a blanket in the sun is not one flat colour.
	float tone = fract(sin(dot(floor(at), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 c = cell.rgb * (0.85 + tone * 0.3);
	ALBEDO = mix(mix(c, grid.rgb, line * 0.7), grid.rgb * 0.6, gap);
	METALLIC = mix(0.3, 0.8, max(line, gap));
	ROUGHNESS = mix(0.12, 0.4, max(line, gap));
	SPECULAR = 0.8;
}
