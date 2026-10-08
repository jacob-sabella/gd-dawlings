shader_type spatial;
render_mode unshaded, shadows_disabled;

// A car's lights at speed: just colour, bright enough to bloom.
uniform float energy = 5.0;

void fragment() {
	ALBEDO = COLOR.rgb * energy;
}
