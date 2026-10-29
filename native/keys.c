// keys: a guest's own keys, heard the moment they go down -- the monitor synth, as a PipeWire
// node of its own, rendered in the graph's realtime callback rather than through Godot's mixer.
//
//   keys [--name "dawlings · monitor"] [--device SINK] [--quantum 128] [--no-midi]
//        [--render FRAMES | --parse]
//
// Why it is not GDScript. A note played through Godot waits for the next frame to be read (up to
// 17ms), then behind a generator queue deep enough to feed Godot's 512-frame mix (16ms), then
// behind Godot's output or a port's (another 10-20ms). Here a key read from the ALSA sequencer
// is in the very next buffer the graph asks for, and the graph is asked to run at `--quantum`
// frames (128 is 2.7ms at 48kHz), so key to sound is a few milliseconds plus the card's own.
//
// The synth is MonitorSynth's (core/session/monitor_synth.gd), the same arithmetic in C: a
// two-operator tine, sixteen voices, the sustain pedal, the pitch wheel and expression.
//
// Beside it, one-shot sample voices, for things struck (docs/spatial_loop.md part two, slice 39):
// the app renders Foley's sounds to 48 kHz WAVs, loads each into one of SLOTS slots once, and then
// fires one with a line, played on one of HIT_VOICES voices in the same callback as the notes. A
// hit is added after the tine's saturation and volume, so it sounds exactly as its WAV at the gain
// it was fired at, and the app's own level (InstrumentItem.level_db) is the whole of its level.
//
// Commands on stdin, one per line:
//   on P V        note P down at velocity V (from the app: the computer keys, the panel's keys)
//   off P         note P up
//   sus 0|1       the sustain pedal
//   bend V        the pitch wheel, -8192 to 8191: every sounding note bent, two semitones at the
//                 ends (DawKitTine.BEND_SEMITONES)
//   cc K V        controller K at V, 0 to 127: 11 (expression) scales the output; 1 (the mod
//                 wheel) and any other this tine has no use for are ignored
//   vol DB        volume, in dB
//   enable 0|1    whether anything is heard (off: monitoring through the player's own gear)
//   midi 0|1      take every hardware MIDI source's notes, or none (the port takes any others
//                 linked to it either way)
//   panic         every note off now
//   load SLOT PATH       a 48 kHz 16-bit mono WAV into slot SLOT (0 to SLOTS-1), read now, here,
//                        on the main loop; said back as `loaded SLOT FRAMES` or `refused SLOT WHY`
//   hit SLOT GAIN PAN [SPEED]
//                        play slot SLOT once: GAIN linear (0 to 4), PAN -1 (left) to 1 (right),
//                        both sides whole at 0; SPEED how fast it is read (0.25 to 4, 1 when left
//                        out), an AudioStreamPlayer's pitch_scale. An empty slot plays nothing
//   mod on 0|1           the keys play the modular wall's patch (native/modular.c) rather than the
//                        tine: the app's `on` and `off` and the sequencer's notes alike, and `bend`
//                        bends both (docs/spatial_loop.md part two, slice 51)
//   mod clear            every cable of the modular's out (its knobs stay as they are)
//   mod cable FROM TO    a cable from output FROM (`vco1.out`) into input TO (`vcf.in`)
//   mod cut JACK         the cable at JACK out: an input's one, or every one from an output
//   mod knob ID V        knob ID (`vcf.cutoff`) at V, 0 to 1
//   mod world NAME V     world socket NAME (`world:weather`) at level V (slice 53)
//   mod trig NAME        world socket NAME's gate opened
// EOF quits.
//
// Lines on stdout:
//   ready RATE QUANTUM       the stream is running
//   midi-from NAME           a hardware source now linked in
//   note 1|0 P V CH UNIX_US  a note from MIDI, for the app's takes; UNIX_US is when it arrived
//   sus 0|1 CH UNIX_US       the pedal, likewise
//   latency US               the last note's or hit's, key to the graph's sink: its wait for a
//                            buffer, what is queued ahead of it (pw_stream_get_time_n), and a cycle
//   loaded SLOT FRAMES       a `load` read, ready to hit
//   refused SLOT WHY         a `load` that could not be: no such file, not a 48 kHz 16-bit mono WAV
//
// --no-midi: no ALSA sequencer port, for a node that only plays the app's hits.
//
// --render FRAMES: no PipeWire, no MIDI. Reads all of stdin, plays its notes and hits from the
// first frame, and writes FRAMES of raw stereo float to stdout. For the suite. A line `wait N`
// writes the next N frames before the lines after it are played, so a knob turned or a note let go
// partway through lands where it should (on a modular block's edge when N is a multiple of 64).
//
// --parse: no PipeWire, no MIDI, no sound. Reads all of stdin and says what each line was taken
// as, one line each (`on 60 100`, `hit 3 0.500 -0.300 1.000`, `loaded 3 4800`, `mod cable vco1.out
// vcf.in`, `ignored ...`). For the suite: the line parser, headless.
//
// Built on demand by core/audio/native_keys.gd (modular.c, beside it, is included):
//   cc -O2 -o keys keys.c $(pkg-config --cflags --libs libpipewire-0.3 alsa) -lm
#include <alsa/asoundlib.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/utils/ringbuffer.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define RATE 48000
#define VOICES 16
#define TABLE 4096
// One-shot sample voices: how many sounds can be loaded (Foley.HIT_SLOTS mirrors it), and how many
// ring at once.
#define SLOTS 256
#define HIT_VOICES 16
// The longest a loaded sound may be: ten seconds.
#define SLOT_MOST (RATE * 10)

// --- The synth: MonitorSynth's, sample for sample. ----------------------------------------------

static float sine[TABLE];
static int v_pitch[VOICES];
static float v_phase[VOICES], v_tine[VOICES], v_inc[VOICES], v_amp[VOICES], v_index[VOICES],
		v_decay[VOICES], v_release[VOICES], v_attack[VOICES], v_pan[VOICES], v_strike[VOICES];
static int v_held[VOICES];
static long v_born[VOICES];
static long clock_n;
static int sustain;
static float gain = 0.5f;
// The pitch wheel, as the ratio every voice's increment is scaled by; and expression, 0-1.
static float bend = 1.0f;
static float expression = 1.0f;
#define BEND_SEMITONES 2.0f
static int enabled = 1;

static void synth_init(void) {
	for (int i = 0; i < TABLE; i++)
		sine[i] = sinf(2.0f * (float)M_PI * i / TABLE);
	for (int v = 0; v < VOICES; v++)
		v_pitch[v] = -1;
}

static void voice_on(int pitch, int velocity) {
	if (!enabled)
		return;
	int v = -1, oldest = 0;
	for (int i = 0; i < VOICES; i++) {
		if (v_amp[i] < 0.0005f) {
			v = i;
			break;
		}
		if (v_born[i] < v_born[oldest])
			oldest = i;
	}
	if (v < 0)
		v = oldest;
	float hz = 440.0f * powf(2.0f, (pitch - 69) / 12.0f);
	float vel = fminf(fmaxf(velocity / 127.0f, 0.0f), 1.0f);
	v_pitch[v] = pitch;
	v_inc[v] = hz * TABLE / RATE;
	v_phase[v] = 0.0f;
	v_tine[v] = 0.0f;
	v_amp[v] = 0.05f + 0.22f * vel * vel;
	v_index[v] = 0.6f + 2.2f * vel;
	v_attack[v] = 0.0f;
	float ring = fminf(fmaxf(6.0f * powf(0.5f, (pitch - 40) / 24.0f), 1.5f), 6.0f);
	v_decay[v] = powf(0.001f, 1.0f / (ring * RATE));
	v_release[v] = 1.0f;
	v_held[v] = 1;
	v_pan[v] = fminf(fmaxf((pitch - 64) / 90.0f, -0.35f), 0.35f);
	v_strike[v] = hz * 14.0f < 16000.0f ? v_amp[v] * 0.35f : 0.0f;
	v_born[v] = ++clock_n;
}

// Damper down: 60dB in about 150ms, quick enough to stop, slow enough not to click.
static void damp(int v) {
	v_release[v] = 0.99904f;
}

static void voice_off(int pitch) {
	for (int v = 0; v < VOICES; v++)
		if (v_pitch[v] == pitch && v_held[v]) {
			v_held[v] = 0;
			if (!sustain)
				damp(v);
		}
}

static void pedal(int down) {
	sustain = down;
	if (!down)
		for (int v = 0; v < VOICES; v++)
			if (v_pitch[v] >= 0 && !v_held[v])
				damp(v);
}

static void wheel(int value) {
	float v = fminf(fmaxf((float)value, -8192.0f), 8191.0f);
	bend = powf(2.0f, v / 8192.0f * BEND_SEMITONES / 12.0f);
}

static void controller(int kind, int value) {
	if (kind == 11)
		expression = fminf(fmaxf(value / 127.0f, 0.0f), 1.0f);
}

static void panic(void) {
	sustain = 0;
	for (int v = 0; v < VOICES; v++) {
		v_held[v] = 0;
		if (v_pitch[v] >= 0)
			damp(v);
	}
}

// --- One-shot sample voices: things struck. ---------------------------------------------------

// What each slot holds, as the realtime thread sees it: set only there (EV_LOAD), so a voice never
// reads a sound being swapped. A replaced one goes to `trash` for the main loop to free.
static float *slot_data[SLOTS];
static uint32_t slot_frames[SLOTS];
struct hit_voice {
	float *data;
	uint32_t frames;
	int slot;
	double at;
	float speed, left, right;
	long born;
};
static struct hit_voice hits[HIT_VOICES];

static void hit_on(int slot, float level, float pan, float speed) {
	if (slot < 0 || slot >= SLOTS || slot_data[slot] == NULL)
		return;
	int v = -1, oldest = 0;
	for (int i = 0; i < HIT_VOICES; i++) {
		if (hits[i].data == NULL) {
			v = i;
			break;
		}
		if (hits[i].born < hits[oldest].born)
			oldest = i;
	}
	if (v < 0)
		v = oldest;
	level = fminf(fmaxf(level, 0.0f), 4.0f);
	pan = fminf(fmaxf(pan, -1.0f), 1.0f);
	// Both sides whole in the middle, as a mono stream through Godot is; the far side falls away.
	hits[v] = (struct hit_voice){slot_data[slot], slot_frames[slot], slot, 0.0,
			fminf(fmaxf(speed, 0.25f), 4.0f), level * fminf(1.0f, 1.0f - pan), level * fminf(1.0f, 1.0f + pan),
			++clock_n};
}

// Every ringing hit, added to `out`. Read between samples in a straight line, as
// Foley.resampled does, so a hit at SPEED 1 is its samples exactly.
static void render_hits(float *out, uint32_t count) {
	for (int v = 0; v < HIT_VOICES; v++) {
		struct hit_voice *h = &hits[v];
		if (h->data == NULL)
			continue;
		for (uint32_t i = 0; i < count; i++) {
			uint32_t j = (uint32_t)h->at;
			if (j + 1 >= h->frames) {
				if (j < h->frames) {
					out[i * 2] += h->data[j] * h->left;
					out[i * 2 + 1] += h->data[j] * h->right;
				}
				h->data = NULL;
				break;
			}
			float k = (float)(h->at - j);
			float s = h->data[j] + (h->data[j + 1] - h->data[j]) * k;
			out[i * 2] += s * h->left;
			out[i * 2 + 1] += s * h->right;
			h->at += h->speed;
		}
	}
}

// --- The modular wall: native/modular.c. ------------------------------------------------------

#include "modular.c"

static void render(float *out, uint32_t count) {
	memset(out, 0, count * 2 * sizeof(float));
	float index_fall = powf(0.12f, 1.0f / (0.25f * RATE));
	for (int v = 0; v < VOICES; v++) {
		float amp = v_amp[v];
		if (amp < 0.0005f)
			continue;
		float phase = v_phase[v], tine = v_tine[v], inc = v_inc[v] * bend, index = v_index[v];
		float decay = v_decay[v] * v_release[v], attack = v_attack[v];
		float left = 0.5f - v_pan[v], right = 0.5f + v_pan[v], tine_amp = v_strike[v];
		for (uint32_t i = 0; i < count; i++) {
			float m = sine[(int)phase & (TABLE - 1)] * index * (TABLE * 0.159f);
			float strike = sine[(int)tine & (TABLE - 1)] * tine_amp;
			float s = (sine[(int)(phase + m) & (TABLE - 1)] * amp + strike) * attack;
			out[i * 2] += s * left * 2.0f;
			out[i * 2 + 1] += s * right * 2.0f;
			phase += inc;
			if (phase >= TABLE)
				phase -= TABLE;
			tine += inc * 14.0f;
			if (tine >= TABLE)
				tine -= TABLE * floorf(tine / TABLE);
			amp *= decay;
			tine_amp *= 0.9993f;
			index = index * index_fall + 0.12f * (1.0f - index_fall);
			attack = fminf(1.0f, attack + 1.0f / 96.0f);
		}
		v_amp[v] = amp;
		v_strike[v] = tine_amp;
		v_phase[v] = phase;
		v_tine[v] = tine;
		v_index[v] = index;
		v_attack[v] = attack;
		if (amp < 0.0005f)
			v_pitch[v] = -1;
	}
	// Expression, then gentle saturation, so a fistful of keys gets fuller rather than clipping;
	// then the volume.
	for (uint32_t i = 0; i < count * 2; i++) {
		float f = out[i] * expression;
		out[i] = f / (1.0f + fabsf(f)) * gain;
	}
	render_hits(out, count);
	// The modular, while the keys play it, at the keys' volume: after the tine's saturation, since
	// its OUT module has its own.
	if (mod_on && enabled)
		mod_render(out, count, gain);
}

// --- Events: from the main loop (stdin, the sequencer) to the realtime thread. ------------------

enum { EV_ON, EV_OFF, EV_SUS, EV_VOL, EV_ENABLE, EV_PANIC, EV_BEND, EV_CC, EV_LOAD, EV_HIT, EV_MOD_ON,
	EV_MOD_CLEAR, EV_MOD_CABLE, EV_MOD_CUT, EV_MOD_KNOB, EV_MOD_WORLD, EV_MOD_TRIG };
struct event {
	uint32_t kind, a, b;
	float f;
	uint64_t at_ns;
	// EV_LOAD's samples (b frames), EV_HIT's pan and speed.
	float *p;
	float g, h;
	// EV_MOD_KNOB's value, whole: a float would round the knob the app sends.
	double d;
};
#define EVENTS 1024
static struct event events[EVENTS];
static struct spa_ringbuffer event_ring = SPA_RINGBUFFER_INIT();

// What the realtime thread found, for the main loop to say: the last note's latency.
static _Atomic int64_t last_latency_us = -1;
static _Atomic int latency_fresh = 0;

static uint64_t now_ns(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static uint64_t unix_us(void) {
	struct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	return (uint64_t)ts.tv_sec * 1000000ull + ts.tv_nsec / 1000;
}

// Sounds the realtime thread let go of (a slot loaded again), for the main loop to free.
#define TRASH 256
static float *trash[TRASH];
static struct spa_ringbuffer trash_ring = SPA_RINGBUFFER_INIT();

static void throw_out(float *p) {
	uint32_t at;
	if (p == NULL || spa_ringbuffer_get_write_index(&trash_ring, &at) >= TRASH)
		return; // Full: kept rather than freed under a voice.
	trash[at & (TRASH - 1)] = p;
	spa_ringbuffer_write_update(&trash_ring, at + 1);
}

static void empty_trash(void) {
	uint32_t at;
	int32_t filled = spa_ringbuffer_get_read_index(&trash_ring, &at);
	for (int32_t i = 0; i < filled; i++)
		free(trash[(at + i) & (TRASH - 1)]);
	if (filled > 0)
		spa_ringbuffer_read_update(&trash_ring, at + filled);
}

// --parse: what each line was taken as, said rather than played.
static int parse_only;

static void say_event(const struct event *e) {
	switch (e->kind) {
	case EV_ON: printf("on %u %u\n", e->a, e->b); break;
	case EV_OFF: printf("off %u\n", e->a); break;
	case EV_SUS: printf("sus %u\n", e->a); break;
	case EV_VOL: printf("vol %.2f\n", e->f); break;
	case EV_ENABLE: printf("enable %u\n", e->a); break;
	case EV_PANIC: printf("panic\n"); break;
	case EV_BEND: printf("bend %d\n", (int)e->a - 8192); break;
	case EV_CC: printf("cc %u %u\n", e->a, e->b); break;
	case EV_LOAD: break; // Said as `loaded` where it was read.
	case EV_HIT: printf("hit %u %.3f %.3f %.3f\n", e->a, e->f, e->g, e->h); break;
	case EV_MOD_ON: printf("mod on %u\n", e->a); break;
	case EV_MOD_CLEAR: printf("mod clear\n"); break;
	case EV_MOD_CABLE: printf("mod cable %s %s\n", mod_out_name(e->a), IN_NAMES[e->b]); break;
	case EV_MOD_CUT: printf("mod cut %s\n", (int)e->a >= 0 ? IN_NAMES[e->a] : mod_out_name(e->b)); break;
	case EV_MOD_KNOB: printf("mod knob %s %.6f\n", KNOB_NAMES[e->a], e->d); break;
	case EV_MOD_WORLD: printf("mod world %s %.6f\n", WORLD_NAMES[e->a], e->d); break;
	case EV_MOD_TRIG: printf("mod trig %s\n", WORLD_NAMES[e->a]); break;
	}
}

static void push_full(struct event e) {
	e.at_ns = now_ns();
	if (parse_only) {
		say_event(&e);
		free(e.p);
		return;
	}
	uint32_t at;
	int32_t filled = spa_ringbuffer_get_write_index(&event_ring, &at);
	if (filled >= EVENTS) {
		free(e.p);
		return;
	}
	events[at & (EVENTS - 1)] = e;
	spa_ringbuffer_write_update(&event_ring, at + 1);
}

static void push(uint32_t kind, uint32_t a, uint32_t b, float f) {
	push_full((struct event){.kind = kind, .a = a, .b = b, .f = f});
}

// The waiting events, applied. Returns the arrival of the first note-on among them, or 0.
static uint64_t apply_events(void) {
	uint32_t at;
	int32_t filled = spa_ringbuffer_get_read_index(&event_ring, &at);
	uint64_t first_on = 0;
	for (int32_t i = 0; i < filled; i++) {
		struct event *e = &events[(at + i) & (EVENTS - 1)];
		switch (e->kind) {
		case EV_ON:
			if (mod_on) {
				if (enabled)
					mod_note_on(e->a, e->b);
			} else {
				voice_on(e->a, e->b);
			}
			if (!first_on)
				first_on = e->at_ns;
			break;
		case EV_OFF:
			// Both, so a key held across `mod on` still lets go of whichever it went down on.
			voice_off(e->a);
			mod_note_off(e->a);
			break;
		case EV_SUS: pedal(e->a); break;
		case EV_VOL: gain = 0.5f * powf(10.0f, e->f / 20.0f); break;
		case EV_ENABLE:
			enabled = e->a;
			if (!enabled)
				panic();
			break;
		case EV_PANIC:
			panic();
			mod_held_n = 0;
			break;
		case EV_BEND:
			wheel((int)e->a - 8192);
			mod_wheel((int)e->a - 8192);
			break;
		case EV_MOD_ON:
			mod_on = e->a;
			if (mod_on)
				panic();
			else
				mod_held_n = 0;
			break;
		case EV_MOD_CLEAR: mod_clear(); break;
		case EV_MOD_CABLE: mod_cable(e->a, e->b); break;
		case EV_MOD_CUT: mod_cut((int)e->a, (int)e->b); break;
		case EV_MOD_KNOB: mod_knob(e->a, e->d); break;
		case EV_MOD_WORLD: mod_world(e->a, e->d); break;
		case EV_MOD_TRIG: mod_trig(e->a); break;
		case EV_CC: controller(e->a, e->b); break;
		case EV_LOAD:
			// Every voice still on the old sound stops before it is let go of.
			for (int v = 0; v < HIT_VOICES; v++)
				if (hits[v].slot == (int)e->a)
					hits[v].data = NULL;
			throw_out(slot_data[e->a]);
			slot_data[e->a] = e->p;
			slot_frames[e->a] = e->b;
			break;
		case EV_HIT:
			hit_on(e->a, e->f, e->g, e->h);
			if (!first_on)
				first_on = e->at_ns;
			break;
		}
	}
	if (filled > 0)
		spa_ringbuffer_read_update(&event_ring, at + filled);
	return first_on;
}

// --- PipeWire. --------------------------------------------------------------------------------

static struct pw_main_loop *loop;
static struct pw_stream *stream;
static int said_ready;
static uint32_t quantum = 128;

static void on_process(void *data) {
	(void)data;
	struct pw_buffer *b = pw_stream_dequeue_buffer(stream);
	if (b == NULL)
		return;
	struct spa_buffer *buf = b->buffer;
	float *dst = buf->datas[0].data;
	if (dst == NULL)
		return;
	uint32_t stride = 2 * sizeof(float);
	uint32_t n = buf->datas[0].maxsize / stride;
	if (b->requested)
		n = SPA_MIN((uint32_t)b->requested, n);
	uint64_t first_on = apply_events();
	render(dst, n);
	buf->datas[0].chunk->offset = 0;
	buf->datas[0].chunk->stride = stride;
	buf->datas[0].chunk->size = n * stride;
	if (first_on) {
		// The note waited from its arrival until now, and is now behind whatever the stream
		// has already queued, the graph's own delay to the sink, and one cycle more: the graph
		// takes a stream's buffer in the cycle after the one it was made in. Checked against
		// tools/keys_latency.sh, which times the sound arriving.
		struct pw_time t;
		int64_t ahead_ns = (int64_t)n * 1000000000ll / RATE;
		if (pw_stream_get_time_n(stream, &t, sizeof(t)) == 0 && t.rate.denom > 0) {
			ahead_ns += t.delay * 1000000000ll * t.rate.num / t.rate.denom;
			ahead_ns += (int64_t)(t.buffered + t.queued / stride) * 1000000000ll / RATE;
		}
		atomic_store(&last_latency_us, ((int64_t)(now_ns() - first_on) + ahead_ns) / 1000);
		atomic_store(&latency_fresh, 1);
	}
	pw_stream_queue_buffer(stream, b);
}

static void on_state(void *data, enum pw_stream_state old, enum pw_stream_state state, const char *error) {
	(void)data;
	(void)old;
	if (state == PW_STREAM_STATE_STREAMING && !said_ready) {
		said_ready = 1;
		printf("ready %d %u\n", RATE, quantum);
	} else if (state == PW_STREAM_STATE_ERROR) {
		fprintf(stderr, "keys: stream error: %s\n", error ? error : "?");
		pw_main_loop_quit(loop);
	}
}

static const struct pw_stream_events stream_events = {
	PW_VERSION_STREAM_EVENTS,
	.state_changed = on_state,
	.process = on_process,
};

// --- MIDI: the ALSA sequencer, read the moment a message arrives. ----------------------------

static snd_seq_t *seq;
static int seq_port = -1;
static int take_hardware;

static int is_hardware_source(snd_seq_port_info_t *pi) {
	unsigned cap = snd_seq_port_info_get_capability(pi);
	unsigned type = snd_seq_port_info_get_type(pi);
	return (cap & SND_SEQ_PORT_CAP_READ) && (cap & SND_SEQ_PORT_CAP_SUBS_READ)
			&& !(cap & SND_SEQ_PORT_CAP_NO_EXPORT) && (type & SND_SEQ_PORT_TYPE_HARDWARE)
			&& snd_seq_port_info_get_client(pi) != snd_seq_client_id(seq);
}

static void link_source(snd_seq_port_info_t *pi, int on) {
	int client = snd_seq_port_info_get_client(pi), port = snd_seq_port_info_get_port(pi);
	if (on) {
		if (snd_seq_connect_from(seq, seq_port, client, port) == 0)
			printf("midi-from %s\n", snd_seq_port_info_get_name(pi));
	} else {
		snd_seq_disconnect_from(seq, seq_port, client, port);
	}
}

static void link_hardware(int on) {
	take_hardware = on;
	snd_seq_client_info_t *ci;
	snd_seq_port_info_t *pi;
	snd_seq_client_info_alloca(&ci);
	snd_seq_port_info_alloca(&pi);
	snd_seq_client_info_set_client(ci, -1);
	while (snd_seq_query_next_client(seq, ci) >= 0) {
		snd_seq_port_info_set_client(pi, snd_seq_client_info_get_client(ci));
		snd_seq_port_info_set_port(pi, -1);
		while (snd_seq_query_next_port(seq, pi) >= 0)
			if (is_hardware_source(pi))
				link_source(pi, on);
	}
}

static void on_seq(void *data, int fd, uint32_t mask) {
	(void)data;
	(void)fd;
	(void)mask;
	snd_seq_event_t *ev;
	while (snd_seq_event_input(seq, &ev) >= 0 && ev != NULL) {
		uint64_t when = unix_us();
		switch (ev->type) {
		case SND_SEQ_EVENT_NOTEON:
			if (ev->data.note.velocity > 0) {
				push(EV_ON, ev->data.note.note, ev->data.note.velocity, 0);
				printf("note 1 %d %d %d %llu\n", ev->data.note.note, ev->data.note.velocity,
						ev->data.note.channel, (unsigned long long)when);
				break;
			}
			// Running status: a note-on at velocity 0 is how most keyboards say note-off.
			// fallthrough
		case SND_SEQ_EVENT_NOTEOFF:
			push(EV_OFF, ev->data.note.note, 0, 0);
			printf("note 0 %d 0 %d %llu\n", ev->data.note.note, ev->data.note.channel,
					(unsigned long long)when);
			break;
		case SND_SEQ_EVENT_CONTROLLER:
			if (ev->data.control.param == 64) {
				int down = ev->data.control.value >= 64;
				push(EV_SUS, down, 0, 0);
				printf("sus %d %d %llu\n", down, ev->data.control.channel, (unsigned long long)when);
			} else if (ev->data.control.param == 1 || ev->data.control.param == 11) {
				// The mod wheel and expression: passed on, not played. Whose wheel it is is the
				// app's to say (GuestMidi.control), and it answers with a `cc` line.
				printf("ctl %u %d %d %llu\n", ev->data.control.param, ev->data.control.value,
						ev->data.control.channel, (unsigned long long)when);
			}
			break;
		case SND_SEQ_EVENT_PITCHBEND:
			// The pitch wheel, -8192 to 8191, passed on in the same way, answered with `bend`.
			printf("wheel %d %d %llu\n", ev->data.control.value, ev->data.control.channel,
					(unsigned long long)when);
			break;
		case SND_SEQ_EVENT_PORT_START:
			// A keyboard plugged in while the session runs.
			if (take_hardware) {
				snd_seq_port_info_t *pi;
				snd_seq_port_info_alloca(&pi);
				if (snd_seq_get_any_port_info(seq, ev->data.addr.client, ev->data.addr.port, pi) == 0
						&& is_hardware_source(pi))
					link_source(pi, 1);
			}
			break;
		}
	}
}

static int open_seq(struct pw_loop *l) {
	if (snd_seq_open(&seq, "default", SND_SEQ_OPEN_DUPLEX, SND_SEQ_NONBLOCK) < 0) {
		seq = NULL;
		return -1;
	}
	snd_seq_set_client_name(seq, "dawlings");
	seq_port = snd_seq_create_simple_port(seq, "keys in",
			SND_SEQ_PORT_CAP_WRITE | SND_SEQ_PORT_CAP_SUBS_WRITE,
			SND_SEQ_PORT_TYPE_MIDI_GENERIC | SND_SEQ_PORT_TYPE_APPLICATION);
	snd_seq_connect_from(seq, seq_port, SND_SEQ_CLIENT_SYSTEM, SND_SEQ_PORT_SYSTEM_ANNOUNCE);
	struct pollfd pfd;
	if (snd_seq_poll_descriptors(seq, &pfd, 1, POLLIN) == 1)
		pw_loop_add_io(l, pfd.fd, SPA_IO_IN, false, on_seq, NULL);
	printf("seq %d:%d\n", snd_seq_client_id(seq), seq_port);
	return 0;
}

// --- Loading a sound. ---------------------------------------------------------------------------

static uint32_t le32(const unsigned char *b) {
	return b[0] | b[1] << 8 | b[2] << 16 | (uint32_t)b[3] << 24;
}

static uint16_t le16(const unsigned char *b) {
	return (uint16_t)(b[0] | b[1] << 8);
}

// A WAV's samples, -1 to 1 (as Foley's own: a 16-bit sample over 32767), or NULL with `why` said.
// Only what Foley.hit_wav writes: RIFF, PCM, one channel, 16 bits, RATE.
static float *read_wav(const char *path, uint32_t *frames, const char **why) {
	FILE *f = fopen(path, "rb");
	if (f == NULL) {
		*why = "no such file";
		return NULL;
	}
	unsigned char head[12], chunk[8], fmt[16];
	float *out = NULL;
	int have_fmt = 0;
	*why = "not a WAV";
	if (fread(head, 1, 12, f) != 12 || memcmp(head, "RIFF", 4) || memcmp(head + 8, "WAVE", 4))
		goto done;
	while (fread(chunk, 1, 8, f) == 8) {
		uint32_t size = le32(chunk + 4);
		if (!memcmp(chunk, "fmt ", 4) && size >= 16) {
			if (fread(fmt, 1, 16, f) != 16)
				goto done;
			fseek(f, (long)(size - 16 + (size & 1)), SEEK_CUR);
			if (le16(fmt) != 1 || le16(fmt + 2) != 1 || le16(fmt + 14) != 16) {
				*why = "not 16-bit mono PCM";
				goto done;
			}
			if (le32(fmt + 4) != RATE) {
				*why = "not 48 kHz";
				goto done;
			}
			have_fmt = 1;
		} else if (!memcmp(chunk, "data", 4)) {
			if (!have_fmt)
				goto done;
			uint32_t n = size / 2;
			if (n == 0 || n > SLOT_MOST) {
				*why = n == 0 ? "empty" : "longer than ten seconds";
				goto done;
			}
			int16_t *raw = malloc(n * 2);
			out = malloc(n * sizeof(float));
			if (raw == NULL || out == NULL || fread(raw, 2, n, f) != n) {
				free(raw);
				free(out);
				out = NULL;
				*why = "short";
				goto done;
			}
			for (uint32_t i = 0; i < n; i++)
				out[i] = (int16_t)le16((unsigned char *)&raw[i]) / 32767.0f;
			free(raw);
			*frames = n;
			goto done;
		} else {
			fseek(f, (long)(size + (size & 1)), SEEK_CUR);
		}
	}
done:
	fclose(f);
	return out;
}

// Where `loaded` and `refused` are said: stdout, but stderr under --render, whose stdout is sound.
static FILE *news;

static void load(int slot, const char *path) {
	if (slot < 0 || slot >= SLOTS) {
		fprintf(news, "refused %d no such slot\n", slot);
		return;
	}
	uint32_t frames = 0;
	const char *why = "";
	float *data = read_wav(path, &frames, &why);
	if (data == NULL) {
		fprintf(news, "refused %d %s\n", slot, why);
		return;
	}
	fprintf(news, "loaded %d %u\n", slot, frames);
	push_full((struct event){.kind = EV_LOAD, .a = (uint32_t)slot, .b = frames, .p = data});
}

// --- Commands from the app. ---------------------------------------------------------------------

static char line[1024];
static size_t line_len;

// --render's frames still to write, or -1 when playing live.
static long offline_left = -1;

static void render_offline_frames(long frames);

// A `mod` line (the modular wall's patch, its knobs, and whether the keys play it): an event, or
// said to be ignored under --parse when a name is not one of its jacks or knobs.
static void mod_command(const char *s) {
	char x[32], y[32];
	int a = 0;
	double d = 0;
	if (sscanf(s, "mod on %d", &a) == 1) {
		push(EV_MOD_ON, a != 0, 0, 0);
	} else if (strncmp(s, "mod clear", 9) == 0) {
		push(EV_MOD_CLEAR, 0, 0, 0);
	} else if (sscanf(s, "mod cable %31s %31s", x, y) == 2) {
		int from = mod_find_out(x), to = mod_find(IN_NAMES, MOD_INS, y);
		if (from < 0 || to < 0) {
			// Carried from an input to an output, the same cable.
			from = mod_find_out(y);
			to = mod_find(IN_NAMES, MOD_INS, x);
		}
		if (from >= 0 && to >= 0)
			push(EV_MOD_CABLE, (uint32_t)from, (uint32_t)to, 0);
		else if (parse_only)
			printf("ignored %s\n", s);
	} else if (sscanf(s, "mod cut %31s", x) == 1) {
		int in = mod_find(IN_NAMES, MOD_INS, x), out = mod_find_out(x);
		if (in >= 0 || out >= 0)
			push(EV_MOD_CUT, (uint32_t)in, (uint32_t)out, 0);
		else if (parse_only)
			printf("ignored %s\n", s);
	} else if (sscanf(s, "mod world %31s %lf", x, &d) == 2) {
		int w = mod_find(WORLD_NAMES, MOD_WORLD, x);
		if (w >= 0 && isfinite(d))
			push_full((struct event){.kind = EV_MOD_WORLD, .a = (uint32_t)w, .d = d});
		else if (parse_only)
			printf("ignored %s\n", s);
	} else if (sscanf(s, "mod trig %31s", x) == 1) {
		int w = mod_find(WORLD_NAMES, MOD_WORLD, x);
		if (w >= 0)
			push(EV_MOD_TRIG, (uint32_t)w, 0, 0);
		else if (parse_only)
			printf("ignored %s\n", s);
	} else if (sscanf(s, "mod knob %31s %lf", x, &d) == 2) {
		int k = mod_find(KNOB_NAMES, MOD_KNOBS, x);
		if (k >= 0 && isfinite(d))
			push_full((struct event){.kind = EV_MOD_KNOB, .a = (uint32_t)k, .d = d});
		else if (parse_only)
			printf("ignored %s\n", s);
	} else if (parse_only) {
		printf("ignored %s\n", s);
	}
}

static void command(char *s) {
	int a = 0, b = 0;
	float f = 0, g = 0, h = 1;
	int used = 0;
	long n = 0;
	if (strncmp(s, "mod ", 4) == 0)
		mod_command(s);
	else if (sscanf(s, "wait %ld", &n) == 1) {
		if (offline_left >= 0)
			render_offline_frames(n < offline_left ? n : offline_left);
	} else if (sscanf(s, "load %d %n", &a, &used) == 1 && used > 0 && s[used] != 0)
		load(a, s + used);
	else if (sscanf(s, "hit %d %f %f %f", &a, &f, &g, &h) >= 3 && a >= 0 && a < SLOTS)
		push_full((struct event){.kind = EV_HIT, .a = (uint32_t)a, .f = f, .g = g, .h = h});
	else if (sscanf(s, "on %d %d", &a, &b) == 2)
		push(EV_ON, a, b, 0);
	else if (sscanf(s, "off %d", &a) == 1)
		push(EV_OFF, a, 0, 0);
	else if (sscanf(s, "sus %d", &a) == 1)
		push(EV_SUS, a != 0, 0, 0);
	else if (sscanf(s, "bend %d", &a) == 1)
		// Carried offset, as the event's fields are unsigned.
		push(EV_BEND, (uint32_t)((a < -8192 ? -8192 : a > 8191 ? 8191 : a) + 8192), 0, 0);
	else if (sscanf(s, "cc %d %d", &a, &b) == 2)
		push(EV_CC, a, b, 0);
	else if (sscanf(s, "vol %f", &f) == 1)
		push(EV_VOL, 0, 0, f);
	else if (sscanf(s, "enable %d", &a) == 1)
		push(EV_ENABLE, a != 0, 0, 0);
	else if (sscanf(s, "midi %d", &a) == 1) {
		if (seq != NULL)
			link_hardware(a != 0);
	} else if (strncmp(s, "panic", 5) == 0)
		push(EV_PANIC, 0, 0, 0);
	else if (parse_only && s[0] != 0)
		printf("ignored %s\n", s);
}

// Reads what stdin has; returns 0 at EOF.
static int read_commands(void) {
	char chunk[512];
	ssize_t got = read(STDIN_FILENO, chunk, sizeof(chunk));
	if (got == 0)
		return 0;
	for (ssize_t i = 0; i < got; i++) {
		if (chunk[i] == '\n') {
			line[line_len] = 0;
			command(line);
			line_len = 0;
		} else if (line_len < sizeof(line) - 1) {
			line[line_len++] = chunk[i];
		}
	}
	return 1;
}

static void on_stdin(void *data, int fd, uint32_t mask) {
	(void)data;
	(void)fd;
	if ((mask & SPA_IO_IN) && read_commands())
		return;
	if (mask & (SPA_IO_HUP | SPA_IO_ERR | SPA_IO_IN))
		pw_main_loop_quit(loop);
}

static void on_tick(void *data, uint64_t expirations) {
	(void)data;
	(void)expirations;
	if (atomic_exchange(&latency_fresh, 0))
		printf("latency %lld\n", (long long)atomic_load(&last_latency_us));
	empty_trash();
}

// --- Offline, for the suite. --------------------------------------------------------------------

// `frames` of what the lines so far have played, written; for `wait` and the end of the lines.
static void render_offline_frames(long frames) {
	apply_events();
	float buf[256 * 2];
	offline_left -= frames;
	while (frames > 0) {
		uint32_t n = frames < 256 ? (uint32_t)frames : 256;
		render(buf, n);
		fwrite(buf, sizeof(float), n * 2, stdout);
		frames -= n;
	}
}

static int render_offline(long frames) {
	news = stderr;
	offline_left = frames;
	while (read_commands())
		;
	render_offline_frames(offline_left);
	return 0;
}

int main(int argc, char **argv) {
	const char *name = "dawlings · monitor", *device = NULL;
	long offline = -1;
	int midi = 1;
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--name") && i + 1 < argc)
			name = argv[++i];
		else if (!strcmp(argv[i], "--device") && i + 1 < argc)
			device = argv[++i];
		else if (!strcmp(argv[i], "--quantum") && i + 1 < argc)
			quantum = (uint32_t)atoi(argv[++i]);
		else if (!strcmp(argv[i], "--render") && i + 1 < argc)
			offline = atol(argv[++i]);
		else if (!strcmp(argv[i], "--parse"))
			parse_only = 1;
		else if (!strcmp(argv[i], "--no-midi"))
			midi = 0;
	}
	synth_init();
	mod_init();
	news = stdout;
	if (parse_only) {
		setvbuf(stdout, NULL, _IOLBF, 0);
		while (read_commands())
			;
		return 0;
	}
	if (offline >= 0)
		return render_offline(offline);

	// Lines out as they happen; and never stuck behind an app that is not reading them.
	setvbuf(stdout, NULL, _IOLBF, 0);
	fcntl(STDOUT_FILENO, F_SETFL, fcntl(STDOUT_FILENO, F_GETFL) | O_NONBLOCK);
	fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);

	pw_init(&argc, &argv);
	loop = pw_main_loop_new(NULL);
	struct pw_loop *l = pw_main_loop_get_loop(loop);
	char latency[32], node_name[128];
	snprintf(latency, sizeof(latency), "%u/%d", quantum, RATE);
	snprintf(node_name, sizeof(node_name), "dawlings_%s", strstr(name, "· ") ? strstr(name, "· ") + 3 : name);
	for (char *c = node_name; *c; c++)
		if (*c == ' ')
			*c = '_';
	struct pw_properties *props = pw_properties_new(
			PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Playback", PW_KEY_MEDIA_ROLE, "Music",
			PW_KEY_APP_NAME, name, PW_KEY_NODE_NAME, node_name, PW_KEY_NODE_DESCRIPTION, name,
			PW_KEY_MEDIA_NAME, name, PW_KEY_NODE_LATENCY, latency, NULL);
	if (device != NULL)
		pw_properties_set(props, PW_KEY_TARGET_OBJECT, device);
	stream = pw_stream_new_simple(l, name, props, &stream_events, NULL);

	uint8_t pod[1024];
	struct spa_pod_builder builder = SPA_POD_BUILDER_INIT(pod, sizeof(pod));
	const struct spa_pod *params[1];
	params[0] = spa_format_audio_raw_build(&builder, SPA_PARAM_EnumFormat,
			&SPA_AUDIO_INFO_RAW_INIT(.format = SPA_AUDIO_FORMAT_F32, .channels = 2, .rate = RATE,
					.position = {SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR}));
	if (pw_stream_connect(stream, PW_DIRECTION_OUTPUT, PW_ID_ANY,
				PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS,
				params, 1) < 0) {
		fprintf(stderr, "keys: could not connect the stream\n");
		return 1;
	}
	if (midi && open_seq(l) < 0)
		fprintf(stderr, "keys: no ALSA sequencer; keys come only from the app\n");
	pw_loop_add_io(l, STDIN_FILENO, SPA_IO_IN | SPA_IO_HUP | SPA_IO_ERR, false, on_stdin, NULL);
	struct spa_source *tick = pw_loop_add_timer(l, on_tick, NULL);
	struct timespec every = {0, 20 * 1000000};
	pw_loop_update_timer(l, tick, &every, &every, false);

	pw_main_loop_run(loop);

	pw_stream_destroy(stream);
	pw_main_loop_destroy(loop);
	if (seq != NULL)
		snd_seq_close(seq);
	pw_deinit();
	return 0;
}
