#[compute]
#version 450

// The fluid tank's stable-fluids solver (FluidTank), every pass in one shader chosen by `mode`, so one
// pipeline and one uniform set serve the whole step. Velocity is in sim texels a second; image y runs
// down, so "up" is -y. The dye is twice the sim's resolution and is advected by its velocity.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform image2D vel_a;
layout(set = 0, binding = 1, rgba16f) uniform image2D vel_b;
layout(set = 0, binding = 2, r32f) uniform image2D curl_img;
layout(set = 0, binding = 3, r32f) uniform image2D div_img;
layout(set = 0, binding = 4, r32f) uniform image2D p_a;
layout(set = 0, binding = 5, r32f) uniform image2D p_b;
layout(set = 0, binding = 6, rgba16f) uniform image2D dye_a;
layout(set = 0, binding = 7, rgba16f) uniform image2D dye_b;
layout(set = 0, binding = 8, rgba16f) uniform image2D display_img;

#define MAX_SPLATS 8
// Each splat: where (sim texels) and how wide (texels), the push it gives (texels/s), its dye.
layout(set = 0, binding = 9, std140) uniform Splats {
	vec4 at[MAX_SPLATS];
	vec4 force[MAX_SPLATS];
	vec4 colour[MAX_SPLATS];
} splats;

layout(push_constant, std430) uniform Params {
	float mode;
	float dt;
	float w;
	float h;
	float count;
	float curl_strength;
	float vel_keep;
	float dye_keep;
	float buoyancy;
	float exposure;
	float time;
	float pad;
	vec4 base;
} pc;

const int ADVECT_VEL = 0;
const int CURL = 1;
const int VORTICITY = 2;
const int DIVERGENCE = 3;
const int JACOBI_AB = 4;
const int JACOBI_BA = 5;
const int GRADIENT = 6;
const int ADVECT_DYE = 7;
const int SHOW = 8;

ivec2 sim_size() {
	return ivec2(pc.w, pc.h);
}

ivec2 clampi(ivec2 c, ivec2 size) {
	return clamp(c, ivec2(0), size - 1);
}

// Bilinear reads by hand (imageLoad has no filtering), centres at +0.5.
#define BILERP(IMG, P, SIZE, OUT) { \
	vec2 q = (P) - 0.5; \
	ivec2 i0 = ivec2(floor(q)); \
	vec2 f = q - vec2(i0); \
	vec4 a = imageLoad(IMG, clampi(i0, SIZE)); \
	vec4 b = imageLoad(IMG, clampi(i0 + ivec2(1, 0), SIZE)); \
	vec4 c = imageLoad(IMG, clampi(i0 + ivec2(0, 1), SIZE)); \
	vec4 d = imageLoad(IMG, clampi(i0 + ivec2(1, 1), SIZE)); \
	OUT = mix(mix(a, b, f.x), mix(c, d, f.x), f.y); \
}

float luma(vec3 c) {
	return dot(c, vec3(0.3, 0.5, 0.2));
}

void main() {
	int mode = int(pc.mode + 0.5);
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = sim_size();
	ivec2 dsize = size * 2;
	if (mode == ADVECT_DYE || mode == SHOW) {
		if (c.x >= dsize.x || c.y >= dsize.y) {
			return;
		}
	} else if (c.x >= size.x || c.y >= size.y) {
		return;
	}
	vec2 p = vec2(c) + 0.5;

	if (mode == ADVECT_VEL) {
		vec2 v = imageLoad(vel_a, c).xy;
		vec4 back;
		BILERP(vel_a, p - pc.dt * v, size, back);
		vec2 nv = back.xy * pc.vel_keep;
		// Dye is warm: it rises, the more of it the faster.
		vec4 dye;
		BILERP(dye_a, p * 2.0, dsize, dye);
		nv.y -= pc.buoyancy * min(luma(dye.rgb), 2.0) * pc.dt;
		for (int k = 0; k < int(pc.count); k++) {
			vec2 d = p - splats.at[k].xy;
			float r = splats.at[k].z;
			nv += splats.force[k].xy * exp(-dot(d, d) / (r * r));
		}
		// The walls hold the water.
		if (c.x == 0 || c.y == 0 || c.x == size.x - 1 || c.y == size.y - 1) {
			nv = vec2(0.0);
		}
		imageStore(vel_b, c, vec4(nv, 0.0, 0.0));
	} else if (mode == CURL) {
		float l = imageLoad(vel_b, clampi(c - ivec2(1, 0), size)).y;
		float r = imageLoad(vel_b, clampi(c + ivec2(1, 0), size)).y;
		float b = imageLoad(vel_b, clampi(c - ivec2(0, 1), size)).x;
		float t = imageLoad(vel_b, clampi(c + ivec2(0, 1), size)).x;
		imageStore(curl_img, c, vec4(0.5 * ((r - l) - (t - b))));
	} else if (mode == VORTICITY) {
		float cl = imageLoad(curl_img, clampi(c - ivec2(1, 0), size)).x;
		float cr = imageLoad(curl_img, clampi(c + ivec2(1, 0), size)).x;
		float cb = imageLoad(curl_img, clampi(c - ivec2(0, 1), size)).x;
		float ct = imageLoad(curl_img, clampi(c + ivec2(0, 1), size)).x;
		float w = imageLoad(curl_img, c).x;
		vec2 n = 0.5 * vec2(abs(cr) - abs(cl), abs(ct) - abs(cb));
		n /= length(n) + 0.0001;
		vec2 force = pc.curl_strength * vec2(n.y * w, -n.x * w);
		vec2 v = imageLoad(vel_b, c).xy + force * pc.dt;
		imageStore(vel_a, c, vec4(clamp(v, vec2(-2000.0), vec2(2000.0)), 0.0, 0.0));
	} else if (mode == DIVERGENCE) {
		vec2 v = imageLoad(vel_a, c).xy;
		float l = c.x > 0 ? imageLoad(vel_a, c - ivec2(1, 0)).x : -v.x;
		float r = c.x < size.x - 1 ? imageLoad(vel_a, c + ivec2(1, 0)).x : -v.x;
		float b = c.y > 0 ? imageLoad(vel_a, c - ivec2(0, 1)).y : -v.y;
		float t = c.y < size.y - 1 ? imageLoad(vel_a, c + ivec2(0, 1)).y : -v.y;
		imageStore(div_img, c, vec4(0.5 * (r - l + t - b)));
		// The last step's pressure, eased, is where this one's solve starts.
		imageStore(p_a, c, vec4(imageLoad(p_a, c).x * 0.8));
	} else if (mode == JACOBI_AB || mode == JACOBI_BA) {
		float div = imageLoad(div_img, c).x;
		float s;
		if (mode == JACOBI_AB) {
			s = imageLoad(p_a, clampi(c - ivec2(1, 0), size)).x + imageLoad(p_a, clampi(c + ivec2(1, 0), size)).x
					+ imageLoad(p_a, clampi(c - ivec2(0, 1), size)).x + imageLoad(p_a, clampi(c + ivec2(0, 1), size)).x;
			imageStore(p_b, c, vec4((s - div) * 0.25));
		} else {
			s = imageLoad(p_b, clampi(c - ivec2(1, 0), size)).x + imageLoad(p_b, clampi(c + ivec2(1, 0), size)).x
					+ imageLoad(p_b, clampi(c - ivec2(0, 1), size)).x + imageLoad(p_b, clampi(c + ivec2(0, 1), size)).x;
			imageStore(p_a, c, vec4((s - div) * 0.25));
		}
	} else if (mode == GRADIENT) {
		float l = imageLoad(p_a, clampi(c - ivec2(1, 0), size)).x;
		float r = imageLoad(p_a, clampi(c + ivec2(1, 0), size)).x;
		float b = imageLoad(p_a, clampi(c - ivec2(0, 1), size)).x;
		float t = imageLoad(p_a, clampi(c + ivec2(0, 1), size)).x;
		vec2 v = imageLoad(vel_a, c).xy - 0.5 * vec2(r - l, t - b);
		if (c.x == 0 || c.x == size.x - 1) {
			v.x = 0.0;
		}
		if (c.y == 0 || c.y == size.y - 1) {
			v.y = 0.0;
		}
		imageStore(vel_a, c, vec4(v, 0.0, 0.0));
	} else if (mode == ADVECT_DYE) {
		vec2 sp = p * 0.5;
		vec4 v;
		BILERP(vel_a, sp, size, v);
		vec4 dye;
		BILERP(dye_a, (sp - pc.dt * v.xy) * 2.0, dsize, dye);
		// Faded by a share and, a little, outright, so the thin haze clears and the plumes stand out.
		vec3 col = max(dye.rgb * pc.dye_keep - 0.18 * pc.dt, vec3(0.0));
		for (int k = 0; k < int(pc.count); k++) {
			vec2 d = sp - splats.at[k].xy;
			float r = splats.at[k].z * 0.8;
			col += splats.colour[k].rgb * exp(-dot(d, d) / (r * r));
		}
		imageStore(dye_b, c, vec4(min(col, vec3(8.0)), 1.0));
	} else if (mode == SHOW) {
		vec3 dye = imageLoad(dye_b, c).rgb;
		imageStore(dye_a, c, vec4(dye, 1.0));
		// Soft-clipped by its brightest channel, so a thick plume keeps its colour rather than burning
		// white, then lifted past 1 where it is thick, for the glow.
		vec3 e = dye * pc.exposure;
		float peak = max(max(e.r, e.g), e.b);
		vec3 col = e / (1.0 + peak) * (1.0 + 0.9 * smoothstep(0.4, 2.5, peak));
		vec2 uv = p / vec2(dsize);
		// The water itself, faintly the room's colour, darker at the edges.
		float edge = smoothstep(0.0, 0.12, min(min(uv.x, 1.0 - uv.x) * 2.0, min(uv.y, 1.0 - uv.y)));
		col += pc.base.rgb * (0.35 + 0.65 * (1.0 - uv.y)) * edge;
		imageStore(display_img, c, vec4(col, 1.0));
	}
}
