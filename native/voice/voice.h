// dawlings' voice: the C side of native/voice (a shim over the pinned CHIMERA engine, vendor/chimera).
// See native/voice/src/lib.rs for what each call does. RT calls do not allocate; dv_plan_*,
// dv_lyrics_*, dv_init, dv_body and dv_creature do.
#pragma once
#include <cstddef>
#include <cstdint>

extern "C" {
typedef struct DvVoice DvVoice;
typedef struct DvPlan DvPlan;
typedef struct DvLyrics DvLyrics;

enum { DV_N_ARTIC = 17, DV_TELE_HEADER = 16 };

int32_t dv_init(const char* cmudict_gz);
DvVoice* dv_new(double sample_rate);
void dv_free(DvVoice*);
void dv_render(DvVoice*, float* out, size_t n);
void dv_gate(DvVoice*, double level);
void dv_artic(DvVoice*, const double* values);
void dv_source(DvVoice*, const double* values);
void dv_sing_source(DvVoice*, double midi);
void dv_release(DvVoice*, double tag);
void dv_stop(DvVoice*);
double dv_clock(DvVoice*);
void dv_body(DvVoice*, double female, double child);
int32_t dv_creature(DvVoice*, const char* id);
void dv_creature_param(DvVoice*, const char* key, double value);
void dv_call(DvVoice*, size_t index, double midi, double amp);
void dv_stop_call(DvVoice*);
int32_t dv_beat_hit(DvVoice*, const char* id, double midi, double accent);
void dv_beat_play(DvVoice*, int32_t playing);
void dv_beat_tempo(DvVoice*, double bpm, double swing);
int64_t dv_beat_step(DvVoice*);
size_t dv_telemetry(DvVoice*, double* out, size_t cap);
int32_t dv_vowel(const char* ipa, double female, double child, double* out);
void dv_artic_range(double* lo, double* hi, double* rest);

DvLyrics* dv_lyrics_new(const char* text, int32_t ipa);
void dv_lyrics_free(DvLyrics*);
size_t dv_lyrics_len(const DvLyrics*);
size_t dv_lyrics_text(const DvLyrics*, size_t i, char* buf, size_t cap);

DvPlan* dv_plan_note_on(const DvLyrics*, int64_t idx, double midi, double female, double child, double vibrato, double tag, int64_t legato_idx, double legato_midi);
DvPlan* dv_plan_note_off(const DvLyrics*, int64_t idx, double midi, double female, double child);
DvPlan* dv_plan_melisma(double midi, double vibrato, double tag);
DvPlan* dv_plan_song(const DvLyrics*, int64_t first, const double* notes, size_t n, double bpm, double t0, double vibrato, double female, double child);
DvPlan* dv_plan_say(const char* text, int32_t ipa, double female, double child);
DvPlan* dv_plan_beat(const char* text, double bpm, double swing);
double dv_plan_end(const DvPlan*);
size_t dv_plan_len(const DvPlan*);
double dv_schedule(DvVoice*, const DvPlan*, double lead, int32_t replace);
void dv_plan_free(DvPlan*);
size_t dv_catalog(char* buf, size_t cap);
size_t dv_frame(DvVoice*, double* out, size_t cap, size_t per);
}
