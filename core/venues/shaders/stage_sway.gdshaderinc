// How a festival crowd moves, shared by the people and the phones they hold up, so a phone
// stays in its hand: every body sways on its own slow beat, and when the music is loud
// (`pulse`) it bounces, each to its own phase. `origin` is the instance's place in the world,
// which is what makes each one its own.

uniform float pulse = 0.0;
// How much this crowd moves at all: 0 for crew standing about at a soundcheck.
uniform float liveliness = 1.0;

float crowd_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 crowd_move(vec3 v, vec3 origin, float time) {
	float ph = crowd_hash(origin.xz);
	// Sway grows up the body: the feet stay put.
	float up = clamp(v.y / 1.8, 0.0, 1.2);
	float sway = sin(time * (1.0 + ph * 0.7) + ph * 6.283) * 0.07 * up;
	// A jump: the whole body, on the half of each beat it is in the air.
	float jump = max(0.0, sin(time * (4.4 + ph * 0.8) + ph * 11.0)) * 0.22 * pulse;
	return vec3(sway, jump, 0.0) * liveliness;
}
