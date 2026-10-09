// keys_latency: how long from a MIDI key going down to its sound reaching a sink, measured.
//
//   keys_latency --sink reaper3d_null --to CLIENT:PORT [--notes 20]
//
// Sends note-ons through the ALSA sequencer to CLIENT:PORT (the keys helper's "keys in"), and
// records the sink's monitor with a PipeWire capture stream, timing every buffer by the graph's
// own clock (pw_stream_get_time_n's `now`, the cycle it was made in). The time from a note being
// sent to the first sample of its sound arriving at the sink is the latency; a real card adds its
// own output latency after that. Run by tools/keys_latency.sh.
//
//   cc -O2 -o keys_latency keys_latency.c $(pkg-config --cflags --libs libpipewire-0.3 alsa) -lm
#include <alsa/asoundlib.h>
#include <math.h>
#include <pipewire/pipewire.h>
#include <pthread.h>
#include <spa/param/audio/format-utils.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define RATE 48000
#define MAX 256

static struct pw_thread_loop *loop;
static struct pw_stream *stream;
static _Atomic int quiet_frames;
static _Atomic int listening;
static uint64_t onsets[MAX];
static _Atomic int onset_count;
static _Atomic uint32_t quantum;

static uint64_t now_ns(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static void on_process(void *data) {
	(void)data;
	struct pw_buffer *b = pw_stream_dequeue_buffer(stream);
	if (b == NULL)
		return;
	struct spa_buffer *buf = b->buffer;
	float *in = buf->datas[0].data;
	uint32_t n = buf->datas[0].chunk->size / (2 * sizeof(float));
	struct pw_time t;
	pw_stream_get_time_n(stream, &t, sizeof(t));
	quantum = n;
	for (uint32_t i = 0; in != NULL && i < n; i++) {
		float s = fabsf(in[i * 2]);
		if (s > 0.01f) {
			// The first sound after a quiet stretch: a key's onset.
			if (quiet_frames > RATE / 20 && listening && onset_count < MAX) {
				onsets[onset_count] = (uint64_t)t.now + (uint64_t)i * 1000000000ull / RATE;
				onset_count++;
				listening = 0;
			}
			quiet_frames = 0;
		} else {
			quiet_frames++;
		}
	}
	pw_stream_queue_buffer(stream, b);
}

static const struct pw_stream_events events = {PW_VERSION_STREAM_EVENTS, .process = on_process};

static int cmp(const void *a, const void *b) {
	double x = *(const double *)a, y = *(const double *)b;
	return x < y ? -1 : x > y;
}

int main(int argc, char **argv) {
	const char *sink = "reaper3d_null", *to = NULL;
	int notes = 20;
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--sink") && i + 1 < argc)
			sink = argv[++i];
		else if (!strcmp(argv[i], "--to") && i + 1 < argc)
			to = argv[++i];
		else if (!strcmp(argv[i], "--notes") && i + 1 < argc)
			notes = atoi(argv[++i]);
	}
	if (to == NULL || notes > MAX) {
		fprintf(stderr, "keys_latency --sink SINK --to CLIENT:PORT [--notes N]\n");
		return 2;
	}
	snd_seq_t *seq;
	if (snd_seq_open(&seq, "default", SND_SEQ_OPEN_OUTPUT, 0) < 0)
		return 1;
	snd_seq_set_client_name(seq, "keys_latency");
	int port = snd_seq_create_simple_port(seq, "out", SND_SEQ_PORT_CAP_READ | SND_SEQ_PORT_CAP_SUBS_READ,
			SND_SEQ_PORT_TYPE_MIDI_GENERIC | SND_SEQ_PORT_TYPE_APPLICATION);
	snd_seq_addr_t dest;
	if (snd_seq_parse_address(seq, &dest, to) < 0 || snd_seq_connect_to(seq, port, dest.client, dest.port) < 0) {
		fprintf(stderr, "keys_latency: cannot reach %s\n", to);
		return 1;
	}

	pw_init(&argc, &argv);
	loop = pw_thread_loop_new("keys_latency", NULL);
	stream = pw_stream_new_simple(pw_thread_loop_get_loop(loop), "keys_latency",
			pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Capture",
					PW_KEY_TARGET_OBJECT, sink, PW_KEY_STREAM_CAPTURE_SINK, "true",
					PW_KEY_NODE_NAME, "keys_latency", NULL),
			&events, NULL);
	uint8_t pod[1024];
	struct spa_pod_builder builder = SPA_POD_BUILDER_INIT(pod, sizeof(pod));
	const struct spa_pod *params[1] = {spa_format_audio_raw_build(&builder, SPA_PARAM_EnumFormat,
			&SPA_AUDIO_INFO_RAW_INIT(.format = SPA_AUDIO_FORMAT_F32, .channels = 2, .rate = RATE))};
	pw_stream_connect(stream, PW_DIRECTION_INPUT, PW_ID_ANY,
			PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS, params, 1);
	pw_thread_loop_start(loop);
	usleep(1500000);

	uint64_t sent[MAX];
	double lat[MAX];
	int got = 0;
	for (int k = 0; k < notes; k++) {
		int before = onset_count;
		listening = 1;
		snd_seq_event_t ev;
		snd_seq_ev_clear(&ev);
		snd_seq_ev_set_source(&ev, port);
		snd_seq_ev_set_subs(&ev);
		snd_seq_ev_set_direct(&ev);
		snd_seq_ev_set_noteon(&ev, 0, 72, 110);
		sent[k] = now_ns();
		snd_seq_event_output_direct(seq, &ev);
		usleep(80000);
		snd_seq_ev_set_noteoff(&ev, 0, 72, 0);
		snd_seq_event_output_direct(seq, &ev);
		// Long enough for the damped note to fall silent and the meter to call it quiet again.
		usleep(520000);
		if (onset_count > before) {
			lat[got++] = ((int64_t)onsets[before] - (int64_t)sent[k]) / 1e6;
		}
	}
	pw_thread_loop_stop(loop);
	if (got == 0) {
		printf("keys_latency: no notes heard at %s\n", sink);
		return 1;
	}
	qsort(lat, got, sizeof(double), cmp);
	printf("keys_latency: %d/%d notes, key to sink median %.2f ms, best %.2f, worst %.2f (graph quantum %u)\n",
			got, notes, lat[got / 2], lat[0], lat[got - 1], (unsigned)quantum);
	return 0;
}
