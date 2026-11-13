#[compute]
#version 450

// The particle-life pane (ParticleLifePane): six species, each pulled or pushed by each other one as a
// matrix says, in a space that wraps. Three passes chosen by `mode`: the forces (every pair, eight
// invocations sharing each particle) and the move; the particles splatted as soft points into an
// accumulator; the accumulator resolved into the picture, which keeps a fading trail of what was there.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

#define SPECIES 6
#define SLICES 8u
#define PER_GROUP 32u

// 2N particles: the half `parity` says is read, the other written. Each: x, y, vx, vy.
layout(set = 0, binding = 0, std430) restrict buffer Particles {
	vec4 p[];
} parts;
layout(set = 0, binding = 1, std140) uniform Rules {
	// Attraction of species i to species j at m[(i * 6 + j) / 4][(i * 6 + j) % 4].
	vec4 m[9];
	// Each species' force strength.
	vec4 strength[2];
	// Each species' colour.
	vec4 colour[SPECIES];
} rules;
layout(set = 0, binding = 2, std430) restrict buffer Accum {
	uint v[];
} accum;
layout(set = 0, binding = 3, rgba16f) uniform image2D display_img;

layout(push_constant, std430) uniform Params {
	float mode;
	float n;
	float parity;
	float dt;
	float world_w;
	float rmax;
	float friction;
	float force;
	float tex_w;
	float tex_h;
	float radius;
	float fade;
	float kick;
	float seed;
	float exposure;
	float pad;
} pc;

shared vec2 partial[256];
shared float rule_m[SPECIES * SPECIES];

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

float attraction(uint i, uint j) {
	uint k = i * SPECIES + j;
	return rules.m[k / 4u][k % 4u];
}

float strength_of(uint i) {
	return rules.strength[i / 4u][i % 4u];
}

// The classic rule: a hard push inside beta, then the matrix's pull peaking half way to rmax.
float rule(float r, float a) {
	const float beta = 0.3;
	if (r < beta) {
		return r / beta - 1.0;
	}
	if (r < 1.0) {
		return a * (1.0 - abs(2.0 * r - 1.0 - beta) / (1.0 - beta));
	}
	return 0.0;
}

void main() {
	int mode = int(pc.mode + 0.5);
	uint id = gl_GlobalInvocationID.x;
	uint n = uint(pc.n);
	uint src = pc.parity < 0.5 ? 0u : n;
	uint dst = pc.parity < 0.5 ? n : 0u;
	vec2 world = vec2(pc.world_w, 1.0);

	if (mode == 3) {
		// The first step: scattered over the pane, still.
		if (id < n) {
			parts.p[id] = vec4(rand(id * 3u + 1u) * world.x, rand(id * 3u + 2u), 0.0, 0.0);
			parts.p[id + n] = parts.p[id];
		}
		return;
	}

	if (mode == 0) {
		// SLICES invocations share a particle, each summing every SLICES-th other one, so a few thousand
		// particles still fill the card; their sums meet in shared memory. Dispatched n / PER_GROUP wide.
		uint local = gl_LocalInvocationID.x;
		uint slot = local / SLICES;
		uint slice = local % SLICES;
		uint i = gl_WorkGroupID.x * PER_GROUP + slot;
		if (local < SPECIES * SPECIES) {
			rule_m[local] = rules.m[local / 4u][local % 4u];
		}
		barrier();
		vec4 me = parts.p[src + i];
		uint sp = i % SPECIES;
		vec2 acc = vec2(0.0);
		float r2max = pc.rmax * pc.rmax;
		for (uint j = slice; j < n; j += SLICES) {
			vec2 d = parts.p[src + j].xy - me.xy;
			d -= round(d / world) * world;
			float r2 = dot(d, d);
			if (r2 > 0.0 && r2 < r2max) {
				float r = sqrt(r2);
				acc += d * (rule(r / pc.rmax, rule_m[sp * SPECIES + j % SPECIES]) / r);
			}
		}
		partial[local] = acc;
		barrier();
		if (slice != 0u) {
			return;
		}
		for (uint k = 1u; k < SLICES; k++) {
			acc += partial[local + k];
		}
		acc *= pc.rmax * pc.force * strength_of(sp);
		vec2 v = me.zw * pc.friction + acc * pc.dt;
		if (pc.kick > 0.0) {
			uint s = hash(i + uint(pc.seed) * 7919u);
			float a = rand(s) * 6.2831853;
			v += vec2(cos(a), sin(a)) * pc.kick * rand(s + 1u);
		}
		vec2 pos = mod(me.xy + v * pc.dt, world);
		parts.p[dst + i] = vec4(pos, v);
		return;
	}

	ivec2 tex = ivec2(pc.tex_w, pc.tex_h);
	uint texels = uint(tex.x * tex.y);
	if (mode == 1) {
		// Each particle a soft point: a few texels of a falling-off glow, added in fixed point.
		if (id >= n) {
			return;
		}
		vec4 me = parts.p[dst + id];
		vec3 col = rules.colour[id % SPECIES].rgb;
		float speed = clamp(length(me.zw) * 4.0, 0.0, 1.0);
		col *= 0.6 + 0.8 * speed;
		vec2 at = me.xy / world * vec2(tex);
		int rad = int(ceil(pc.radius));
		for (int dy = -rad; dy <= rad; dy++) {
			for (int dx = -rad; dx <= rad; dx++) {
				ivec2 c = ivec2(floor(at)) + ivec2(dx, dy);
				vec2 d = vec2(c) + 0.5 - at;
				float w = exp(-dot(d, d) / (pc.radius * pc.radius * 0.35));
				if (w < 0.02) {
					continue;
				}
				c = (c % tex + tex) % tex;
				uint i = uint(c.y * tex.x + c.x);
				uvec3 add = uvec3(col * w * 256.0);
				atomicAdd(accum.v[i], add.r);
				atomicAdd(accum.v[i + texels], add.g);
				atomicAdd(accum.v[i + texels * 2u], add.b);
			}
		}
		return;
	}

	// mode 2: the accumulator into the picture, the picture's old trail fading under it.
	if (id >= texels) {
		return;
	}
	ivec2 c = ivec2(id % uint(tex.x), id / uint(tex.x));
	vec3 add = vec3(accum.v[id], accum.v[id + texels], accum.v[id + texels * 2u]) / 256.0;
	accum.v[id] = 0u;
	accum.v[id + texels] = 0u;
	accum.v[id + texels * 2u] = 0u;
	vec3 old = imageLoad(display_img, c).rgb;
	// Soft-clipped by the brightest channel, so a crowd keeps its species' colour instead of going white.
	vec3 e = add * pc.exposure;
	vec3 fresh = e / (1.0 + max(max(e.r, e.g), e.b)) * 2.0;
	imageStore(display_img, c, vec4(max(old * pc.fade, fresh), 1.0));
}
