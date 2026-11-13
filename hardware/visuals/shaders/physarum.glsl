#[compute]
#version 450

// The physarum sheet (PhysarumSheet): agents that sense the trail ahead of them, turn toward the most
// of it, step and lay more down; then the trail spreads and fades. Two passes a step, chosen by `mode`,
// and the trail ping-pongs between two maps by `parity`, so no pass has to copy one into the other.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// Each agent: x, y (trail texels), heading (radians), a per-agent wobble.
layout(set = 0, binding = 0, std430) restrict buffer Agents {
	vec4 a[];
} agents;
layout(set = 0, binding = 1, r32f) uniform image2D trail_a;
layout(set = 0, binding = 2, r32f) uniform image2D trail_b;
layout(set = 0, binding = 3, rgba16f) uniform image2D display_img;

layout(push_constant, std430) uniform Params {
	float mode;
	float parity;
	float w;
	float h;
	float count;
	float speed;
	float sense_angle;
	float sense_dist;
	float turn;
	float deposit;
	float decay;
	float diffuse;
	float seed;
	float burst_frac;
	float burst_x;
	float burst_y;
	vec4 low;
	vec4 high;
	// x: a clock (s); y: how far (radians) the faint colour's hue drifts across the sheet.
	vec4 extra;
} pc;

// A colour turned `a` radians round the grey axis: the faint veins drift through neighbouring hues.
vec3 hue_turn(vec3 c, float a) {
	const vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

uint hash(uint x) {
	x ^= x >> 16;
	x *= 0x7feb352du;
	x ^= x >> 15;
	x *= 0x846ca68bu;
	x ^= x >> 16;
	return x;
}

float rand(uint x) {
	return float(hash(x)) / 4294967295.0;
}

ivec2 wrap(ivec2 c) {
	ivec2 size = ivec2(pc.w, pc.h);
	return (c % size + size) % size;
}

float sense(vec2 p) {
	ivec2 c = wrap(ivec2(floor(p)));
	return pc.parity < 0.5 ? imageLoad(trail_a, c).x : imageLoad(trail_b, c).x;
}

void main() {
	int mode = int(pc.mode + 0.5);
	uint id = gl_GlobalInvocationID.x;
	vec2 size = vec2(pc.w, pc.h);
	if (mode == 2) {
		// The first step: agents scattered over the sheet, a denser knot in the middle, headed anywhere.
		if (id >= uint(pc.count)) {
			return;
		}
		uint s = hash(id * 7919u + 17u);
		vec2 p = vec2(rand(s), rand(s + 1u)) * size;
		if (rand(s + 2u) < 0.4) {
			float t = rand(s + 3u) * 6.2831853;
			p = size * 0.5 + vec2(cos(t), sin(t)) * sqrt(rand(s + 4u)) * min(size.x, size.y) * 0.3;
		}
		agents.a[id] = vec4(p, rand(s + 5u) * 6.2831853, rand(s + 6u));
		return;
	}
	if (mode == 0) {
		if (id >= uint(pc.count)) {
			return;
		}
		vec4 ag = agents.a[id];
		vec2 p = ag.xy;
		float ang = ag.z;
		uint s = hash(id * 1973u + uint(pc.seed));
		// A hit: some agents are thrown out of a point in a ring.
		if (pc.burst_frac > 0.0 && rand(s) < pc.burst_frac) {
			float t = rand(s ^ 0x9e3779b9u) * 6.2831853;
			p = vec2(pc.burst_x, pc.burst_y) * size + vec2(cos(t), sin(t)) * (2.0 + rand(s + 7u) * 6.0);
			ang = t;
		} else {
			float sa = pc.sense_angle * (0.85 + 0.3 * ag.w);
			float f = sense(p + vec2(cos(ang), sin(ang)) * pc.sense_dist);
			float l = sense(p + vec2(cos(ang + sa), sin(ang + sa)) * pc.sense_dist);
			float r = sense(p + vec2(cos(ang - sa), sin(ang - sa)) * pc.sense_dist);
			float jitter = rand(s + 3u);
			if (f > l && f > r) {
				ang += (jitter - 0.5) * 0.1;
			} else if (f < l && f < r) {
				ang += (jitter < 0.5 ? -1.0 : 1.0) * pc.turn;
			} else if (l > r) {
				ang += pc.turn * (0.5 + jitter * 0.5);
			} else if (r > l) {
				ang -= pc.turn * (0.5 + jitter * 0.5);
			}
			p += vec2(cos(ang), sin(ang)) * pc.speed * (0.8 + 0.4 * ag.w);
		}
		p = mod(p, size);
		agents.a[id] = vec4(p, mod(ang, 6.2831853), ag.w);
		ivec2 c = ivec2(floor(p));
		// Laid down where it stands; two agents on one cell may race, and one of them loses a little: unseen.
		if (pc.parity < 0.5) {
			imageStore(trail_a, c, vec4(min(imageLoad(trail_a, c).x + pc.deposit, 40.0)));
		} else {
			imageStore(trail_b, c, vec4(min(imageLoad(trail_b, c).x + pc.deposit, 40.0)));
		}
		return;
	}
	// The spread: one invocation a texel, the map read as rows of `w`.
	uint W = uint(pc.w);
	ivec2 c = ivec2(id % W, id / W);
	if (c.y >= int(pc.h)) {
		return;
	}
	float sum = 0.0;
	float self_v = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 q = wrap(c + ivec2(dx, dy));
			float v = pc.parity < 0.5 ? imageLoad(trail_a, q).x : imageLoad(trail_b, q).x;
			sum += v;
			if (dx == 0 && dy == 0) {
				self_v = v;
			}
		}
	}
	float v = mix(self_v, sum / 9.0, pc.diffuse) * pc.decay;
	if (pc.parity < 0.5) {
		imageStore(trail_b, c, vec4(v));
	} else {
		imageStore(trail_a, c, vec4(v));
	}
	// The picture: the faint trail in the low colour, the thick veins running to the high one and past white.
	float x = 1.0 - exp(-v * 0.02);
	vec2 uv = vec2(c) / vec2(pc.w, pc.h);
	float drift = sin(uv.x * 5.0 + pc.extra.x * 0.11) + sin(uv.y * 4.0 - pc.extra.x * 0.07 + 1.3);
	vec3 low = max(hue_turn(pc.low.rgb, pc.extra.y * 0.5 * drift), vec3(0.0));
	vec3 col = low * pow(x, 1.4) * 1.1 + pc.high.rgb * pow(x, 4.0) * 2.8;
	col *= pc.low.a;
	imageStore(display_img, c, vec4(col, 1.0));
}
