// modular: the modular synth wall's arithmetic (docs/spatial_loop.md part two, slice 51), in the keys'
// helper so a player's own modular is on the fast path. Included by keys.c, which runs it in the same
// realtime callback as the tine and the hits.
//
// The same arithmetic as core/music/modular/modular.gd, step for step and in double precision with
// the C library's own sin, tan, exp and pow, so `keys --render` of a patch and notes is
// Modular.render of them within 1e-4 (the suite checks it). The rules both keep:
//   - Every input reads its source as it was one sample before: the order the modules run in
//     changes nothing, and a patch may loop back on itself.
//   - Only the modules whose sound reaches OUT run (mod_live); the rest are frozen where they were.
//   - Events land at the start of a block of MOD_BLOCK frames. What a knob sets that does not move
//     within a block is worked out once a block; the filter's coefficients every sample when its CV
//     input is patched.
// The jacks' and knobs' names, and their order, are Modular.OUTS, INS and KNOBS.
//
// The world's sockets (slice 53) are outputs too, after the modules' (WORLD_NAMES, Modular.WORLD), out
// in the room rather than on the wall. Each has a level (`mod world NAME V`) and a gate (`mod trig
// NAME`, open for MOD_GATE_BLOCKS blocks, shut for one first if it was open): an ENV's gate input reads
// its gate, every other input its level. Every input's source is a slot: a module's output, MOD_ZERO,
// a world socket's level or its gate.

#define MOD_BLOCK 64
#define MOD_OUTS 12
#define MOD_INS 15
#define MOD_KNOBS 25
#define MOD_MODULES 11
#define MOD_WORLD 12
#define MOD_GATE_BLOCKS 36
// The slot every unpatched input reads: always 0. After it, each world socket's level, then each one's
// gate.
#define MOD_ZERO MOD_OUTS
#define MOD_WORLD_LEVEL (MOD_ZERO + 1)
#define MOD_WORLD_GATE (MOD_ZERO + 1 + MOD_WORLD)
#define MOD_SLOTS (MOD_WORLD_GATE + MOD_WORLD)

static const char *OUT_NAMES[MOD_OUTS] = {"keys.pitch", "keys.gate", "keys.vel", "lfo.out", "noise.out",
		"vco1.out", "vco2.out", "mix.out", "vcf.out", "env1.out", "env2.out", "vca.out"};
static const char *WORLD_NAMES[MOD_WORLD] = {"world:weather", "world:drips", "world:venue", "world:ring_1",
		"world:ring_2", "world:ring_3", "world:ring_4", "world:ring_5", "world:ring_6", "world:ring_7",
		"world:ring_8", "world:marbles"};
static const char *IN_NAMES[MOD_INS] = {"vco1.pitch", "vco1.fm", "vco2.pitch", "vco2.fm", "mix.in1", "mix.in2",
		"mix.in3", "mix.in4", "vcf.in", "vcf.cv", "env1.gate", "env2.gate", "vca.in", "vca.cv", "out.in"};
static const char *KNOB_NAMES[MOD_KNOBS] = {"lfo.rate", "lfo.shape", "vco1.wave", "vco1.tune", "vco1.fm",
		"vco2.wave", "vco2.tune", "vco2.fm", "mix.l1", "mix.l2", "mix.l3", "mix.l4", "vcf.cutoff",
		"vcf.res", "vcf.cv", "env1.a", "env1.d", "env1.s", "env1.r", "env2.a", "env2.d", "env2.s",
		"env2.r", "vca.level", "out.level"};
static const double KNOB_REST[MOD_KNOBS] = {0.5, 0.0, 0.0, 0.5, 0.0, 0.5, 0.5, 0.0, 0.5, 0.5, 0.5, 0.5, 0.55,
		0.3, 0.7, 0.1, 0.4, 0.6, 0.35, 0.1, 0.4, 0.6, 0.35, 1.0, 0.7};
// The module each output and each input is on, by its place in Modular.MODULES.
static const int MODULE_OF_OUT[MOD_OUTS] = {0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
static const int MODULE_OF_IN[MOD_INS] = {3, 3, 4, 4, 5, 5, 5, 5, 6, 6, 7, 8, 9, 9, 10};
#define MOD_OUT_MODULE 10
#define C4_HZ 261.6255653005986
#define MOD_RATE 48000.0

enum { O_PITCH, O_GATE, O_VEL, O_LFO, O_NOISE, O_VCO1, O_VCO2, O_MIX, O_VCF, O_ENV1, O_ENV2, O_VCA };

// Whether the keys play the modular (`mod on 1`) rather than the tine.
static int mod_on;
static int mod_src[MOD_INS];
static unsigned char mod_live[MOD_MODULES];
static double mod_o[MOD_SLOTS];
static int gate_left[MOD_WORLD];
static unsigned char gate_rest[MOD_WORLD];
static double mod_k[MOD_KNOBS];
static int mod_held[128], mod_held_n;
static int mod_last_pitch = 60;
static double mod_velocity, mod_bend;
static double lfo_phase;
static uint32_t noise_state = 22222;
static double vco_phase[2];
static int env_stage[2], env_gate[2];
static double env_level[2];
static double vcf_ic1, vcf_ic2;
// One block rendered ahead, and how much of it has been read.
static float mod_block_buf[MOD_BLOCK];
static int mod_block_at = MOD_BLOCK;

static int mod_find(const char **names, int n, const char *name) {
	for (int i = 0; i < n; i++)
		if (!strcmp(names[i], name))
			return i;
	return -1;
}

static void mod_relive(void) {
	memset(mod_live, 0, sizeof(mod_live));
	mod_live[MOD_OUT_MODULE] = 1;
	int grew = 1;
	while (grew) {
		grew = 0;
		for (int i = 0; i < MOD_INS; i++) {
			if (mod_src[i] >= MOD_ZERO || !mod_live[MODULE_OF_IN[i]])
				continue;
			int m = MODULE_OF_OUT[mod_src[i]];
			if (!mod_live[m]) {
				mod_live[m] = 1;
				grew = 1;
			}
		}
	}
}

static void mod_init(void) {
	for (int i = 0; i < MOD_INS; i++)
		mod_src[i] = MOD_ZERO;
	for (int i = 0; i < MOD_KNOBS; i++)
		mod_k[i] = KNOB_REST[i];
	mod_relive();
}

static void mod_clear(void) {
	for (int i = 0; i < MOD_INS; i++)
		mod_src[i] = MOD_ZERO;
	mod_relive();
}

// An output by name: a module's (0 to MOD_OUTS - 1), or a world socket's (MOD_OUTS on), or -1.
static int mod_find_out(const char *name) {
	int at = mod_find(OUT_NAMES, MOD_OUTS, name);
	if (at >= 0)
		return at;
	at = mod_find(WORLD_NAMES, MOD_WORLD, name);
	return at >= 0 ? MOD_OUTS + at : -1;
}

static const char *mod_out_name(int out) {
	return out < MOD_OUTS ? OUT_NAMES[out] : WORLD_NAMES[out - MOD_OUTS];
}

// The slot input `to` reads output `from` at (Modular._slot): a world socket's gate into an ENV's
// gate (inputs 10 and 11), its level into anything else.
static int mod_slot(int from, int to) {
	if (from < MOD_OUTS)
		return from;
	int w = from - MOD_OUTS;
	return (to == 10 || to == 11) ? MOD_WORLD_GATE + w : MOD_WORLD_LEVEL + w;
}

static int mod_reads(int slot, int out) {
	if (out < MOD_OUTS)
		return slot == out;
	int w = out - MOD_OUTS;
	return slot == MOD_WORLD_LEVEL + w || slot == MOD_WORLD_GATE + w;
}

static void mod_cable(int from, int to) {
	if (from >= 0 && from < MOD_OUTS + MOD_WORLD && to >= 0 && to < MOD_INS)
		mod_src[to] = mod_slot(from, to);
	mod_relive();
}

// The cable at a jack out: an input's one (`in` >= 0), or every one from an output (`out` >= 0).
static void mod_cut(int in, int out) {
	for (int i = 0; i < MOD_INS; i++)
		if (i == in || (out >= 0 && mod_reads(mod_src[i], out)))
			mod_src[i] = MOD_ZERO;
	mod_relive();
}

// A world socket's level now (Modular.world).
static void mod_world(int w, double v) {
	if (w >= 0 && w < MOD_WORLD && isfinite(v))
		mod_o[MOD_WORLD_LEVEL + w] = fmin(fmax(v, -1.0), 1.0);
}

// A world socket's gate opened (Modular.trig).
static void mod_trig(int w) {
	if (w < 0 || w >= MOD_WORLD)
		return;
	if (gate_left[w] > 0)
		gate_rest[w] = 1;
	gate_left[w] = MOD_GATE_BLOCKS;
}

static void mod_knob(int k, double v) {
	if (k >= 0 && k < MOD_KNOBS)
		mod_k[k] = fmin(fmax(v, 0.0), 1.0);
}

static void mod_note_off(int pitch) {
	for (int i = 0; i < mod_held_n; i++)
		if (mod_held[i] == pitch) {
			memmove(&mod_held[i], &mod_held[i + 1], (mod_held_n - i - 1) * sizeof(int));
			mod_held_n--;
			break;
		}
	if (mod_held_n > 0)
		mod_last_pitch = mod_held[mod_held_n - 1];
}

static void mod_note_on(int pitch, int velocity) {
	mod_note_off(pitch);
	if (mod_held_n < 128)
		mod_held[mod_held_n++] = pitch;
	mod_last_pitch = pitch;
	mod_velocity = fmin(fmax(velocity / 127.0, 0.0), 1.0);
}

static void mod_wheel(int value) {
	double v = fmin(fmax((double)value, -8192.0), 8191.0);
	mod_bend = v / 8192.0 * 2.0 / 12.0;
}

static double mod_wave(int kind, double phase) {
	if (kind == 0)
		return 2.0 * phase - 1.0;
	if (kind == 1)
		return phase < 0.5 ? 1.0 : -1.0;
	return sin((2.0 * M_PI) * phase);
}

static double env_coef(double v) {
	return 1.0 - exp(-1.0 / (0.001 * pow(5000.0, v) * MOD_RATE));
}

static int mini_i(int a, int b) {
	return a < b ? a : b;
}

static void env_step(int e, int gate, double ca, double cd, double s, double cr) {
	if (gate && !env_gate[e])
		env_stage[e] = 1;
	else if (!gate && env_gate[e])
		env_stage[e] = 3;
	env_gate[e] = gate;
	if (env_stage[e] == 1) {
		env_level[e] += (1.3 - env_level[e]) * ca;
		if (env_level[e] >= 1.0) {
			env_level[e] = 1.0;
			env_stage[e] = 2;
		}
	} else if (env_stage[e] == 2) {
		env_level[e] += (s - env_level[e]) * cd;
	} else if (env_stage[e] == 3) {
		env_level[e] -= env_level[e] * cr;
	}
}

// One block of the patch into `out`: Modular._block.
static void mod_run_block(float *out) {
	double *o = mod_o, *k = mod_k;
	int *src = mod_src;
	o[O_PITCH] = (mod_last_pitch - 60) / 12.0 + mod_bend;
	o[O_GATE] = mod_held_n > 0 ? 1.0 : 0.0;
	o[O_VEL] = mod_velocity;
	for (int w = 0; w < MOD_WORLD; w++) {
		if (gate_rest[w]) {
			gate_rest[w] = 0;
			o[MOD_WORLD_GATE + w] = 0.0;
		} else if (gate_left[w] > 0) {
			gate_left[w]--;
			o[MOD_WORLD_GATE + w] = 1.0;
		} else {
			o[MOD_WORLD_GATE + w] = 0.0;
		}
	}
	double lfo_inc = 0.05 * pow(400.0, k[0]) / MOD_RATE;
	int lfo_shape = mini_i((int)(k[1] * 4.0), 3);
	int w1 = mini_i((int)(k[2] * 3.0), 2);
	double t1 = (k[3] - 0.5) * 2.0, f1 = k[4] * 2.0;
	int w2 = mini_i((int)(k[5] * 3.0), 2);
	double t2 = (k[6] - 0.5) * 2.0, f2 = k[7] * 2.0;
	double cutoff = 20.0 * pow(1000.0, k[12]);
	double damp = 2.0 - 1.96 * k[13];
	double cv_oct = (k[14] - 0.5) * 2.0 * 5.0;
	double ca1 = env_coef(k[15]), cd1 = env_coef(k[16]), s1 = k[17], cr1 = env_coef(k[18]);
	double ca2 = env_coef(k[19]), cd2 = env_coef(k[20]), s2 = k[21], cr2 = env_coef(k[22]);
	double vca_level = k[23], out_level = k[24];
	double a1 = 0.0, a2 = 0.0, a3 = 0.0;
	if (src[9] == MOD_ZERO) {
		double g = tan(M_PI * fmin(fmax(cutoff, 10.0), 0.45 * MOD_RATE) / MOD_RATE);
		a1 = 1.0 / (1.0 + g * (g + damp));
		a2 = g * a1;
		a3 = g * a2;
	}
	for (int i = 0; i < MOD_BLOCK; i++) {
		double n_lfo = o[O_LFO], n_noise = o[O_NOISE], n_v1 = o[O_VCO1], n_v2 = o[O_VCO2],
				n_mix = o[O_MIX], n_vcf = o[O_VCF], n_e1 = o[O_ENV1], n_e2 = o[O_ENV2], n_vca = o[O_VCA];
		if (mod_live[1]) {
			switch (lfo_shape) {
			case 0: n_lfo = sin((2.0 * M_PI) * lfo_phase); break;
			case 1: n_lfo = 4.0 * fabs(lfo_phase - 0.5) - 1.0; break;
			case 2: n_lfo = lfo_phase < 0.5 ? 1.0 : -1.0; break;
			default: n_lfo = 2.0 * lfo_phase - 1.0; break;
			}
			lfo_phase += lfo_inc;
			lfo_phase -= floor(lfo_phase);
		}
		if (mod_live[2]) {
			noise_state = noise_state * 1664525u + 1013904223u;
			n_noise = noise_state / 2147483648.0 - 1.0;
		}
		if (mod_live[3]) {
			n_v1 = mod_wave(w1, vco_phase[0]);
			double hz = fmin(C4_HZ * pow(2.0, o[src[0]] + t1 + o[src[1]] * f1), 20000.0);
			vco_phase[0] += hz / MOD_RATE;
			vco_phase[0] -= floor(vco_phase[0]);
		}
		if (mod_live[4]) {
			n_v2 = mod_wave(w2, vco_phase[1]);
			double hz = fmin(C4_HZ * pow(2.0, o[src[2]] + t2 + o[src[3]] * f2), 20000.0);
			vco_phase[1] += hz / MOD_RATE;
			vco_phase[1] -= floor(vco_phase[1]);
		}
		if (mod_live[5])
			n_mix = o[src[4]] * k[8] + o[src[5]] * k[9] + o[src[6]] * k[10] + o[src[7]] * k[11];
		if (mod_live[6]) {
			if (src[9] != MOD_ZERO) {
				double fc = fmin(fmax(cutoff * pow(2.0, o[src[9]] * cv_oct), 10.0), 0.45 * MOD_RATE);
				double g = tan(M_PI * fc / MOD_RATE);
				a1 = 1.0 / (1.0 + g * (g + damp));
				a2 = g * a1;
				a3 = g * a2;
			}
			double v3 = o[src[8]] - vcf_ic2;
			double v1 = a1 * vcf_ic1 + a2 * v3;
			double v2 = vcf_ic2 + a2 * vcf_ic1 + a3 * v3;
			vcf_ic1 = 2.0 * v1 - vcf_ic1;
			vcf_ic2 = 2.0 * v2 - vcf_ic2;
			n_vcf = v2;
		}
		if (mod_live[7]) {
			env_step(0, o[src[10]] > 0.5, ca1, cd1, s1, cr1);
			n_e1 = env_level[0];
		}
		if (mod_live[8]) {
			env_step(1, o[src[11]] > 0.5, ca2, cd2, s2, cr2);
			n_e2 = env_level[1];
		}
		if (mod_live[9]) {
			double gain = vca_level;
			if (src[13] != MOD_ZERO)
				gain = vca_level * fmax(o[src[13]], 0.0);
			n_vca = o[src[12]] * gain;
		}
		double x = o[src[14]] * out_level;
		out[i] = (float)(x / (1.0 + fabs(x)));
		o[O_LFO] = n_lfo;
		o[O_NOISE] = n_noise;
		o[O_VCO1] = n_v1;
		o[O_VCO2] = n_v2;
		o[O_MIX] = n_mix;
		o[O_VCF] = n_vcf;
		o[O_ENV1] = n_e1;
		o[O_ENV2] = n_e2;
		o[O_VCA] = n_vca;
	}
}

// `count` frames of the modular, each times `level`, added to the stereo `out`: whole blocks run as
// they are needed, so a callback of any length reads them on from where the last one stopped.
static void mod_render(float *out, uint32_t count, float level) {
	for (uint32_t i = 0; i < count; i++) {
		if (mod_block_at >= MOD_BLOCK) {
			mod_run_block(mod_block_buf);
			mod_block_at = 0;
		}
		float s = mod_block_buf[mod_block_at++] * level;
		out[i * 2] += s;
		out[i * 2 + 1] += s;
	}
}
