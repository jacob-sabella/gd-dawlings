// Caustics: the web of bright lines sunlight makes on the bottom under a rippled surface. The
// warped-sine pattern after Dave Hoskins's tileable water caustic: `p` in cells, `t` in seconds.
// Returns about 0 between the lines and up to 1 on them.
float caustic(vec2 p, float t) {
	vec2 q = mod(p * 6.2831853, 6.2831853) - 250.0;
	vec2 i = q;
	float c = 1.0;
	float inten = 0.005;
	for (int n = 0; n < 5; n++) {
		float tt = t * (1.0 - (3.5 / float(n + 1)));
		i = q + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(q.x / (sin(i.x + tt) / inten), q.y / (cos(i.y + tt) / inten)));
	}
	c /= 5.0;
	c = 1.17 - pow(c, 1.4);
	return clamp(pow(abs(c), 8.0), 0.0, 1.5);
}
