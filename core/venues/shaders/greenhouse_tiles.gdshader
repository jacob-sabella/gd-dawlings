shader_type spatial;

// The palm house's floor: Victorian encaustic tiles, six inches square, laid as buff and
// terracotta octagons with a black square dot where four meet, every other octagon inlaid with a
// four-petalled flower in the other clay. Round the edge of the walk, against the kerb, a border:
// a row of black, a row of terracotta and buff in a rope of diagonals, and black again. Worn
// paler where feet go, the glaze long gone. `wet` darkens it and takes the roughness out, with
// standing puddles where the floor dips; the rain's drips ring them.

uniform float tile = 0.1524;
uniform vec4 buff : source_color = vec4(0.6, 0.5, 0.36, 1.0);
uniform vec4 terracotta : source_color = vec4(0.46, 0.2, 0.12, 1.0);
uniform vec4 black : source_color = vec4(0.07, 0.065, 0.06, 1.0);
uniform vec4 blue : source_color = vec4(0.26, 0.33, 0.38, 1.0);
uniform vec4 grout : source_color = vec4(0.4, 0.38, 0.34, 1.0);
// The walk's rectangle, in world x and z: the border runs round inside its edge.
uniform vec4 walk = vec4(-7.0, -3.2, 14.0, 10.5);
uniform float wet = 0.0;
uniform float brightness = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.1 + 3.3) * 0.25 + vnoise(p * 4.3 + 7.1) * 0.125;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 g = p / tile;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	// How far in from the walk's edge, in tiles.
	vec2 lo = walk.xy;
	vec2 hi = walk.xy + walk.zw;
	float in_from = min(min(p.x - lo.x, hi.x - p.x), min(p.y - lo.y, hi.y - p.y)) / tile;
	vec3 col;
	float line;
	if (in_from < 3.0) {
		// The border, three rows. Laid square to whichever edge is nearest.
		float row = floor(in_from);
		bool along_x = min(p.y - lo.y, hi.y - p.y) < min(p.x - lo.x, hi.x - p.x);
		float a = along_x ? g.x : g.y;
		float b = in_from - row;
		if (row == 1.0) {
			// The rope: diagonal bands of terracotta and buff.
			float band = fract((a + b) * 1.0);
			col = band < 0.5 ? terracotta.rgb : buff.rgb;
			line = min(abs(band - 0.5), min(band, 1.0 - band)) * 4.0;
		} else {
			col = black.rgb;
			line = 1.0;
		}
		line = min(line, min(min(b, 1.0 - b), min(fract(a), 1.0 - fract(a))) * 18.0);
	} else {
		// The field: an octagon in each tile, a black dot where four corners meet.
		bool odd = mod(id.x + id.y, 2.0) > 0.5;
		vec2 af = abs(f);
		float corner = af.x + af.y;
		float cut = 0.72;
		if (corner > cut) {
			col = black.rgb;
		} else {
			col = odd ? terracotta.rgb : buff.rgb;
			// The inlay in every other one: a four-petalled flower in the other clay, a blue
			// eye at its middle.
			if (odd) {
				float ang = atan(f.y, f.x);
				float rr = length(f);
				float petal = 0.21 + 0.11 * abs(cos(ang * 2.0));
				if (rr < petal && rr > 0.05) {
					col = buff.rgb;
				}
				if (rr < 0.06) {
					col = blue.rgb;
				}
			}
		}
		line = min(abs(corner - cut) * 20.0, min(0.5 - af.x, 0.5 - af.y) * 22.0);
	}
	// Each tile's clay fired a shade different; worn and grubby in drifts; grout between.
	float own = hash(id);
	col *= 0.88 + 0.2 * own;
	float wear = fbm(p * 0.9);
	col = mix(col, col * 0.7 + vec3(0.06, 0.05, 0.04), smoothstep(0.55, 0.85, wear) * 0.5);
	col = mix(col, vec3(dot(col, vec3(0.33))) * 1.1, smoothstep(0.35, 0.75, fbm(p * 0.35 + 9.0)) * 0.25);
	float g_line = 1.0 - smoothstep(0.0, 0.8, line);
	col = mix(col, grout.rgb, g_line * 0.8);
	float rough = mix(0.62, 0.85, g_line) - own * 0.06;

	// Wet: darker, glossy; puddles where the old floor has sunk a little.
	float puddle = smoothstep(0.5, 0.6, fbm(p * 0.45 + 2.0)) * wet;
	float damp = wet * (0.6 + 0.4 * smoothstep(0.3, 0.7, fbm(p * 1.3 + 5.0)));
	col *= mix(1.0, 0.5, damp);
	col *= mix(1.0, 0.7, puddle);
	rough = mix(rough, 0.1, damp);
	rough = mix(rough, 0.03, puddle);
	// The drips ring the puddles: a few rings spreading and fading, each from its own spot.
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	if (puddle > 0.01) {
		vec2 cell = floor(p / 0.6);
		vec2 at = (cell + vec2(hash(cell), hash(cell + 2.3))) * 0.6;
		float t = fract(TIME * 0.5 + hash(cell + 4.1));
		float d = length(p - at);
		float ring = sin((d - t * 0.4) * 60.0) * smoothstep(0.05, 0.0, abs(d - t * 0.4)) * (1.0 - t);
		vec2 dir = (p - at) / max(d, 0.001);
		nmap.xy += dir * ring * 0.4 * puddle;
	}
	ALBEDO = col * brightness;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	NORMAL_MAP = nmap;
}
