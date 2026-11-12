// VOICE: a physically modelled voice (CHIMERA, MIT, pinned as vendor/chimera and linked through
// dawlings' shim native/voice, never copied): lungs, vocal folds, a branched vocal tract, lips and
// nose simulated sample by sample. The modular room's VOICE module, and the vocal booth's singer
// (the same module in a rack of its own).
//
// Modes (MODE): SING sings the lyrics a syllable a note, from the keys or a gate and pitch, and the
// song's own vocal part when the host sends it (`text v.song ...`); VOWEL is the mouth played by
// hand: the VOWEL and OPEN controls (and any hand on an articulator) shape it, the gate breathes
// it; BEAT is a beatboxer: a gate hits the SOUND, SEQ plays a pattern locked to the song; BEAST
// plays a creature (songbird, seal, alligator, elephant), a gate sounding its CALL.
//
// Threads: planning (text to gestures) allocates, so it runs on the module's planner thread and the
// finished plan is only scheduled here. In an offline render (`--render`) plans are made at once,
// in order, so a render is the same every time. A body or creature switch builds a new airway
// (it allocates, CHIMERA's own rule) between blocks, once the knob has settled.
#include "rack.h"
#include <atomic>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <functional>
#include <mutex>
#include <sstream>
#include <thread>
#include "../voice/voice.h"

namespace rack {
using K = Knob;

namespace {

// The dictionary: CHIMERA's own copy, found from the binary's working directory (the project root)
// or DAWLINGS_CMUDICT. Without it English falls back to letter-to-sound rules.
void init_once() {
  static std::once_flag once;
  std::call_once(once, []() {
    const char* p = getenv("DAWLINGS_CMUDICT");
    if (!p) p = "vendor/chimera/public/data/cmudict.txt.gz";
    dv_init(p);
  });
}

// The vowel chain the VOWEL control runs along: front to back, i to u.
const char* const CHAIN[] = {"i", "e", "a", "o", "u"};
const int CHAIN_N = 5;

const char* const SOUNDS[] = {"B", "t", "tss", "Pf", "K", "^K", "!", "P!", "kch", "m"};
const char* const BEASTS[] = {"songbird", "seal", "alligator", "elephant"};

const char* const ARTIC_NAMES[DV_N_ARTIC] = {"jaw", "tbX", "tbY", "ttX", "ttY", "ttCurl", "root", "lipAp", "lipProt",
                                            "lipWidth", "labiodental", "velum", "larynx", "epilarynx", "ventricular",
                                            "lateral", "dorsum"};
int artic_index(const std::string& n) {
  for (int k = 0; k < DV_N_ARTIC; ++k) if (n == ARTIC_NAMES[k]) return k;
  return -1;
}

// How long before a song phrase's first beat its plan is put on the voice: room for the onset
// consonants (and the breath) that come before the beat.
const double PAD = 0.6;

}  // namespace

struct Voice_ : Module {
  enum Mode { SING, VOWEL, BEAT, BEAST };
  DvVoice* v_ = nullptr;
  // ---- the planner thread
  std::thread th_;
  std::mutex mu_;
  std::condition_variable cv_;
  std::deque<std::function<void()>> jobs_;  // run on the planner thread, in order
  bool quit_ = false;
  struct Ready { DvPlan* plan; int kind; double at_beat; int tag; };
  std::mutex ready_mu_;
  std::vector<Ready> ready_;    // finished plans, for process()
  std::vector<DvPlan*> trash_;  // scheduled plans, freed on the planner thread
  DvLyrics* lyrics_ = nullptr;  // the planner's (and an offline render's) only
  std::atomic<int> syl_n_{0};
  std::string syl_list_;        // the syllables' texts, '|' between, for the room's lyric board
  std::mutex syl_mu_;
  bool syl_dirty_ = false;
  enum { K_NOW = 0, K_SONG = 1, K_BEAT = 2 };
  // ---- the keys
  bool gate_ = false;
  double midi_ = 60, held_midi_ = 60;
  int keys_held_ = 0, keys_last_ = -1;
  int tag_ = 0;
  long next_syl_ = 0, held_syl_ = -1;
  // ---- the song's vocal part: (beat, midi, beats) per note, midi <= 0 a rest
  struct Note { double beat, midi, beats; };
  std::vector<Note> song_;
  long song_first_ = 0;
  double song_bpm_ = 120;
  bool song_pending_ = false;  // planned (or being planned), not yet on the voice
  bool song_on_ = false;       // on the voice
  int song_gen_ = 0;           // a newer song (or a seek) drops plans of older ones
  std::atomic<int> song_gen_seen_{0};
  long sung_syl_ = -1;
  double last_beats_ = 0;
  // ---- the body and the beast, applied once the knob has settled
  double body_f_ = 0, body_c_ = 0, want_f_ = 0, want_c_ = 0;
  int settle_ = 0;
  int beast_ = -1;  // -1 the human
  // ---- the mouth by hand
  double lo_[DV_N_ARTIC], hi_[DV_N_ARTIC], rest_[DV_N_ARTIC];
  double hand_[DV_N_ARTIC];  // NaN: no hand on it
  bool hand_any_ = false, vowel_was_ = false;
  // ---- the beat
  bool seq_started_ = false;
  bool beat_set_ = false;
  // ---- out
  float env_ = 0;
  std::vector<float> buf_;
  std::vector<double> tele_;
  int report_n_ = 0;

  void init() override {
    init_once();
    v_ = dv_new(RATE);
    dv_artic_range(lo_, hi_, rest_);
    for (double& h : hand_) h = NAN;
    buf_.assign(BLOCK, 0.0f);
    tele_.assign(4096, 0.0);
    th_ = std::thread([this]() { planner(); });
  }
  ~Voice_() override {
    {
      std::lock_guard<std::mutex> g(mu_);
      quit_ = true;
    }
    cv_.notify_all();
    if (th_.joinable()) th_.join();
    for (auto& r : ready_) dv_plan_free(r.plan);
    for (auto* p : trash_) dv_plan_free(p);
    dv_lyrics_free(lyrics_);
    dv_free(v_);
  }

  void planner() {
    for (;;) {
      std::function<void()> job;
      {
        std::unique_lock<std::mutex> g(mu_);
        cv_.wait(g, [this]() { return quit_ || !jobs_.empty(); });
        if (quit_) return;
        job = std::move(jobs_.front());
        jobs_.pop_front();
      }
      job();
      std::vector<DvPlan*> t;
      {
        std::lock_guard<std::mutex> g(ready_mu_);
        t.swap(trash_);
      }
      for (auto* p : t) dv_plan_free(p);
    }
  }
  // Runs a planning job: on the planner thread live, at once offline (so a render is repeatable).
  void plan(std::function<void()> job) {
    if (ctx->offline) { job(); return; }
    {
      std::lock_guard<std::mutex> g(mu_);
      jobs_.push_back(std::move(job));
    }
    cv_.notify_one();
  }
  void deliver(DvPlan* p, int kind, double at_beat, int tag) {
    std::lock_guard<std::mutex> g(ready_mu_);
    ready_.push_back({p, kind, at_beat, tag});
  }

  void set_lyrics(const std::string& text, int ipa) {
    plan([this, text, ipa]() {
      dv_lyrics_free(lyrics_);
      lyrics_ = dv_lyrics_new(text.c_str(), ipa);
      size_t n = dv_lyrics_len(lyrics_);
      std::string list;
      char b[128];
      for (size_t i = 0; i < n; ++i) {
        dv_lyrics_text(lyrics_, i, b, sizeof b);
        if (i) list += '|';
        list += b;
      }
      std::lock_guard<std::mutex> g(syl_mu_);
      syl_list_ = list;
      syl_n_ = (int)n;
      syl_dirty_ = true;
    });
  }

  // `text MOD.KEY VALUE`: what is not a number reaches the module this way.
  void text(const std::string& key, const std::string& val) override {
    std::istringstream in(val);
    double f = real(1), c = real(2);
    if (key == "lyrics" || key == "lyrics_ipa") {
      set_lyrics(val, key == "lyrics_ipa");
      next_syl_ = 0;
    } else if (key == "syl") {
      in >> next_syl_;
    } else if (key == "say" || key == "say_ipa") {
      int ipa = key == "say_ipa";
      plan([this, val, ipa, f, c]() { deliver(dv_plan_say(val.c_str(), ipa, f, c), K_NOW, 0, -1); });
    } else if (key == "song") {
      // song FIRST_SYL BPM BEAT MIDI BEATS [MIDI BEATS ...]: the vocal part from BEAT on.
      song_.clear();
      double bpm = 120, beat = 0, m, b;
      in >> song_first_ >> bpm >> beat;
      song_bpm_ = bpm > 1 ? bpm : 120;
      while (in >> m >> b) { song_.push_back({beat, m, b}); beat += b; }
      start_song();
    } else if (key == "song_stop") {
      // the part taken away: forgotten, not only stopped, or the next play or seek would plan it again
      song_.clear();
      drop_song();
    } else if (key == "beat") {
      double bpm = ctx->tp.bpm;
      plan([this, val, bpm]() { deliver(dv_plan_beat(val.c_str(), bpm, -1), K_BEAT, 0, -1); });
    } else if (key == "hit") {
      std::string id; double m = 0;
      in >> id >> m;
      dv_beat_hit(v_, id.c_str(), m, NAN);
    } else if (key == "artic") {
      // artic NAME V01 (a hand on it, 0..1 across its travel) | artic NAME =CM (where it is, in its own units)
      // | artic NAME off | artic off
      std::string n, x;
      in >> n >> x;
      if (n == "off") { for (double& h : hand_) h = NAN; hand_any_ = false; return; }
      int k = artic_index(n);
      if (k < 0) return;
      if (x == "off") hand_[k] = NAN;
      else if (!x.empty() && x[0] == '=') hand_[k] = std::min(hi_[k], std::max(lo_[k], atof(x.c_str() + 1)));
      else hand_[k] = lo_[k] + (hi_[k] - lo_[k]) * clampf((float)atof(x.c_str()), 0, 1);
      hand_any_ = false;
      for (double h : hand_) hand_any_ = hand_any_ || !std::isnan(h);
    } else if (key == "param") {
      std::string k; double x;
      if (in >> k >> x) dv_creature_param(v_, k.c_str(), x);
    } else if (key == "call") {
      int i = 0; double m = -1;
      in >> i >> m;
      dv_call(v_, (size_t)std::max(0, i), m, 1.0);
    }
  }

  void drop_song() {
    ++song_gen_;
    if (song_on_ || song_pending_) dv_stop(v_);
    song_on_ = song_pending_ = false;
    sung_syl_ = -1;
  }

  // Plans the song's notes from the next one to come. Live: planned with its first beat at PAD,
  // scheduled when that beat is PAD away. Offline: planned and scheduled here, at once.
  void start_song() {
    drop_song();
    if (song_.empty()) return;
    double now = ctx->tp.beats;
    size_t i = 0;
    long syl = song_first_;
    while (i < song_.size() && song_[i].beat + 1e-9 < now) { if (song_[i].midi > 0) ++syl; ++i; }
    if (i >= song_.size()) return;
    std::vector<double> pairs;
    for (size_t j = i; j < song_.size(); ++j) { pairs.push_back(song_[j].midi); pairs.push_back(song_[j].beats); }
    double at = song_[i].beat, bpm = song_bpm_, f = real(1), c = real(2), vib = real(6);
    double first_midi = 0;
    for (size_t j = i; j < song_.size() && first_midi <= 0; ++j) first_midi = song_[j].midi;
    int gen = song_gen_;
    song_pending_ = true;
    if (ctx->offline) {
      double until = (at - now) * 60.0 / bpm;
      if (first_midi > 0) dv_sing_source(v_, first_midi);
      DvPlan* p = dv_plan_song(lyrics_, syl, pairs.data(), pairs.size() / 2, bpm, until, vib, f, c);
      dv_schedule(v_, p, 0.0, 0);
      dv_plan_free(p);
      song_pending_ = false;
      song_on_ = true;
      return;
    }
    plan([this, pairs, syl, bpm, vib, f, c, at, gen]() {
      DvPlan* p = dv_plan_song(lyrics_, syl, pairs.data(), pairs.size() / 2, bpm, PAD, vib, f, c);
      deliver(p, K_SONG, at, gen);
    });
  }

  double pitch_midi() {
    float p = has(0) ? in[0][0] : ctx->keys.pitch;
    return 60.0 + 12.0 * (p + real(8)) + ctx->keys.bend * 2.0;
  }
  bool gate_in() { return has(1) ? in[1][0] > 0.5f : ctx->keys.gate > 0.5f; }
  float ctl(int knob, int input) { return clampf(real(knob) + (has(input) ? in[input][0] : 0.0f), 0, 1); }

  void key_down(double midi) {
    long idx = next_syl_++;
    int tag = tag_ += 2;
    long legato = held_syl_;
    double lm = held_midi_;
    if (held_syl_ >= 0) { dv_release(v_, tag - 2); dv_release(v_, tag - 1); }
    double f = real(1), c = real(2), vib = real(6);
    held_syl_ = idx;
    held_midi_ = midi;
    sung_syl_ = idx;
    plan([this, idx, midi, f, c, vib, tag, legato, lm]() {
      deliver(dv_plan_note_on(lyrics_, idx, midi, f, c, vib, tag, legato, lm), K_NOW, 0, tag);
    });
  }
  void key_up() {
    dv_release(v_, tag_);
    dv_release(v_, tag_ + 1);
    long idx = held_syl_;
    double midi = held_midi_, f = real(1), c = real(2);
    held_syl_ = -1;
    plan([this, idx, midi, f, c]() { deliver(dv_plan_note_off(lyrics_, idx, midi, f, c), K_NOW, 0, -1); });
  }

  void take_ready() {
    std::vector<Ready> got;
    if (ctx->offline) {
      std::lock_guard<std::mutex> g(ready_mu_);
      got.swap(ready_);
    } else {
      std::unique_lock<std::mutex> g(ready_mu_, std::try_to_lock);
      if (!g.owns_lock()) return;
      // A song plan waits on the list until its first beat is PAD away.
      std::vector<Ready> keep;
      for (auto& r : ready_) {
        if (r.kind == K_SONG && r.tag == song_gen_ && ctx->tp.playing) {
          double until = (r.at_beat - ctx->tp.beats) * 60.0 / song_bpm_;
          if (until > PAD) { keep.push_back(r); continue; }
        }
        got.push_back(r);
      }
      ready_.swap(keep);
    }
    std::vector<DvPlan*> used;
    for (auto& r : got) {
      if (r.kind == K_SONG) {
        if (r.tag == song_gen_ && ctx->tp.playing) {
          double until = (r.at_beat - ctx->tp.beats) * 60.0 / song_bpm_;
          for (auto& n : song_) if (n.midi > 0 && n.beat >= r.at_beat - 1e-9) { dv_sing_source(v_, n.midi); break; }
          dv_schedule(v_, r.plan, until - PAD, 0);
          song_on_ = true;
        }
        song_pending_ = song_pending_ && r.tag != song_gen_;
      } else if (r.kind == K_BEAT) {
        dv_schedule(v_, r.plan, 0, 0);
        beat_set_ = true;
        seq_started_ = false;
      } else if (r.tag < 0) {
        dv_schedule(v_, r.plan, 0, 0);
      } else if (r.tag == tag_) {
        // a key's note (or its pitch moving); one let go before its plan came is sung and let go
        dv_schedule(v_, r.plan, 0, 0);
        if (!gate_) { dv_release(v_, r.tag); dv_release(v_, r.tag + 1); }
      }  // an older key's: a newer one has taken the voice
      used.push_back(r.plan);
    }
    if (used.empty()) return;
    if (ctx->offline) { for (auto* p : used) dv_plan_free(p); return; }
    std::lock_guard<std::mutex> g(ready_mu_);
    trash_.insert(trash_.end(), used.begin(), used.end());
  }

  void apply_body_and_beast(int mode) {
    double f = real(1), c = real(2);
    if (std::fabs(f - want_f_) > 1e-3 || std::fabs(c - want_c_) > 1e-3) { want_f_ = f; want_c_ = c; settle_ = (int)(0.08 * RATE / BLOCK); }
    if (settle_ > 0 && --settle_ == 0 && (std::fabs(want_f_ - body_f_) > 0.01 || std::fabs(want_c_ - body_c_) > 0.01)) {
      body_f_ = want_f_; body_c_ = want_c_;
      dv_body(v_, body_f_, body_c_);
    }
    int want = mode == BEAST ? choice(9) : -1;
    if (want != beast_) {
      beast_ = want;
      dv_creature(v_, want < 0 ? "" : BEASTS[want]);
    }
  }

  void shape_mouth(int mode, bool gate) {
    bool by_hand = mode == VOWEL || hand_any_;
    if (!by_hand) { vowel_was_ = false; return; }
    double a[DV_N_ARTIC];
    for (double& x : a) x = NAN;
    if (mode == VOWEL) {
      double f = body_f_, c = body_c_;
      double x = ctl(3, 2) * (CHAIN_N - 1);
      int i = std::min(CHAIN_N - 2, (int)x);
      double t = x - i, va[DV_N_ARTIC], vb[DV_N_ARTIC];
      dv_vowel(CHAIN[i], f, c, va);
      dv_vowel(CHAIN[i + 1], f, c, vb);
      for (int k = 0; k < DV_N_ARTIC; ++k) {
        if (!std::isnan(va[k]) && !std::isnan(vb[k])) a[k] = va[k] + (vb[k] - va[k]) * t;
        else if (!std::isnan(va[k])) a[k] = va[k];
        else if (!std::isnan(vb[k])) a[k] = vb[k];
      }
      // OPEN: the jaw (and the lips with it) from nearly shut to wide.
      double open = ctl(4, 3);
      a[0] = lo_[0] + (hi_[0] - lo_[0]) * (0.15 + 0.85 * open) * 0.8;
      // The pitch and the breath: the keys or a gate breathe it, BREATH (and its input) drives it.
      double src[12];
      for (double& s : src) s = NAN;
      src[0] = 440.0 * std::pow(2.0, (midi_ - 69.0) / 12.0);
      src[1] = 0.04;
      src[2] = 2.0 + 10.0 * ctl(5, 4);
      src[4] = real(7);
      src[7] = real(6);
      src[10] = 1;
      dv_source(v_, src);
      dv_gate(v_, gate ? 1.0 : 0.0);
    }
    for (int k = 0; k < DV_N_ARTIC; ++k) if (!std::isnan(hand_[k])) a[k] = hand_[k];
    dv_artic(v_, a);
    vowel_was_ = true;
  }

  void beat_follow(bool on, bool jumped) {
    if (!beat_set_) return;
    bool run = on && ctx->tp.playing;
    // The song jumped (a seek, a loop): the pattern's phase is the old place's, so it stops and starts again
    // on the next bar (it kept its phase and every hit landed off the beat by the jump's fraction of a bar).
    if (jumped && seq_started_) { dv_beat_play(v_, 0); seq_started_ = false; }
    if (!run) {
      if (seq_started_) { dv_beat_play(v_, 0); seq_started_ = false; }
      return;
    }
    dv_beat_tempo(v_, ctx->tp.bpm, NAN);
    if (seq_started_) return;
    // The voice's sequencer starts its first step a horizon (0.2 s) after it is told: tell it that
    // long before the next bar, so its step 0 lands on the downbeat.
    double per_beat = 60.0 / ctx->tp.bpm;
    double to_bar = (4.0 - std::fmod(ctx->tp.beats, 4.0)) * per_beat;
    if (to_bar <= 0.2 && to_bar > 0.2 - (double)BLOCK / RATE * 2.0) {
      dv_beat_play(v_, 1);
      seq_started_ = true;
    }
  }

  void process() override {
    int mode = choice(0);
    apply_body_and_beast(mode);
    take_ready();
    // a song stopped or moved under the voice: drop it, plan it again from where it is now
    double moved = ctx->tp.beats - last_beats_;
    last_beats_ = ctx->tp.beats;
    bool jumped = ctx->tp.playing && (moved > 0.25 || moved < -0.01);
    if (!ctx->tp.playing && (song_on_ || song_pending_)) drop_song();
    else if (ctx->tp.playing && (song_on_ || song_pending_) && (moved > 0.25 || moved < -0.01)) drop_song();
    else if (ctx->tp.playing && !song_.empty() && !song_on_ && !song_pending_ && song_gen_seen_ != song_gen_) {
      song_gen_seen_ = song_gen_;
      start_song();
    }
    if (ctx->tp.playing && song_on_) {
      long s = song_first_ - 1;
      for (auto& n : song_) { if (n.beat > ctx->tp.beats) break; if (n.midi > 0) ++s; }
      sung_syl_ = s;
    }
    bool g = gate_in();
    double m = pitch_midi();
    if (mode == SING) {
      // From the keys, every key pressed is a syllable (a second key while one is held sings on,
      // legato); from a patched gate, a rise is one and the pitch moving while it is held is a melisma.
      bool fresh = g && !gate_;
      if (!has(1)) {
        const Keys& k = ctx->keys;
        fresh = fresh || (g && (k.n_held > keys_held_ || k.last_note != keys_last_));
        keys_held_ = k.n_held;
        keys_last_ = g ? k.last_note : -1;
      }
      if (fresh) key_down(m);
      else if (!g && gate_) key_up();
      else if (g && has(1) && std::fabs(m - held_midi_) > 0.5) {
        dv_release(v_, tag_ + 1);
        held_midi_ = m;
        double vib = real(6);
        int tag = tag_;
        plan([this, m, vib, tag]() { deliver(dv_plan_melisma(m, vib, tag), K_NOW, 0, tag); });
      }
    } else if (mode == BEAT) {
      if (g && !gate_) dv_beat_hit(v_, SOUNDS[choice(11)], SOUNDS[choice(11)][0] == 'm' ? m : 0, NAN);
    } else if (mode == BEAST) {
      if (g && !gate_) dv_call(v_, (size_t)choice(10), m, 1.0);
      if (!g && gate_) dv_stop_call(v_);
    }
    midi_ = m;
    gate_ = g;
    shape_mouth(mode, g);
    beat_follow(mode == BEAT && choice(12) == 1, jumped);
    dv_render(v_, buf_.data(), BLOCK);
    float lvl = real(13);
    float e = env_;
    for (int s = 0; s < BLOCK; ++s) {
      float x = buf_[s] * lvl;
      o(0)[s] = x;
      float a = std::fabs(x);
      e += (a - e) * (a > e ? 0.02f : 0.0008f);
      o(1)[s] = e;
    }
    env_ = e;
  }

  // The beat's step (for the booth's step lights) while its pattern plays with the song.
  int playhead() const override { return seq_started_ ? (int)(dv_beat_step(v_) % 16) : -1; }

  // The voice's insides for the room: the head's articulators and airway, which syllable is sung.
  bool report(const std::string& id, std::string& out) override {
    if (++report_n_ % 2) return false;
    size_t n = dv_telemetry(v_, tele_.data(), tele_.size());
    char t[32];
    out += "voice " + id;
    // header, the articulators and the areas; the pressure and flow; the vocal folds, 16 points
    int n_artic = (int)tele_[11], n_ph = (int)tele_[12], n_or = (int)tele_[13], n_scope = (int)tele_[14];
    size_t upto = std::min(n, (size_t)(DV_TELE_HEADER + n_artic + 3 * (n_ph + n_or)));
    for (size_t i = 0; i < upto; ++i) { snprintf(t, sizeof t, " %.4g", tele_[i]); out += t; }
    size_t g0 = DV_TELE_HEADER + n_artic + 3 * (n_ph + n_or);
    for (int i = 0; i < 16 && n_scope > 0; ++i) {
      size_t k = g0 + (size_t)(i * n_scope / 16);
      snprintf(t, sizeof t, " %.4g", k < n ? tele_[k] : 0.0);
      out += t;
    }
    snprintf(t, sizeof t, " @syl %ld", sung_syl_);
    out += t;
    out += "\n";
    // the head's outlines (cm), every other report: what the singer's head draws
    if (report_n_ % 4 == 0) {
      size_t fn = dv_frame(v_, tele_.data(), tele_.size(), 28);
      out += "voiceframe " + id;
      for (size_t i = 0; i < fn; ++i) { snprintf(t, sizeof t, " %.3g", tele_[i]); out += t; }
      out += "\n";
    }
    std::lock_guard<std::mutex> g(syl_mu_);
    if (syl_dirty_) {
      syl_dirty_ = false;
      // the lyric's syllables, at most ~3.5 KB a line (a pipe write of less than 4 KB is whole)
      size_t at = 0, start = 0;
      int idx = 0, first = 0;
      while (at <= syl_list_.size()) {
        if (at == syl_list_.size() || at - start > 3500) {
          std::string chunk = syl_list_.substr(start, at - start);
          out += "voicesyl " + id + " " + std::to_string(first) + " " + std::to_string(syl_n_.load()) + " " + chunk + "\n";
          start = at;
          first = idx;
          if (at == syl_list_.size()) break;
        }
        if (syl_list_[at] == '|') { ++idx; if (at - start > 3500) { start = at + 1; first = idx; } }
        ++at;
      }
    }
    return true;
  }
};

static Registrar r_voice({"voice", "VOICE", "Voice",
    "A human voice built from the body up: lungs, vocal folds, tongue, lips and nose. Sings the lyrics a syllable a note, "
    "speaks, beatboxes, or becomes a songbird, a seal, an alligator or an elephant.",
    {"pitch", "gate", "vowel", "open", "breath"}, {"out", "env"},
    {{"mode", "MODE", 0, 3, 0, K::STEP, "SING|VOWEL|BEAT|BEAST"},
     {"body", "BODY", 0, 1, 0, K::LIN, ""},
     {"child", "CHILD", 0, 1, 0, K::LIN, ""},
     {"vowel", "VOWEL", 0, 1, 0.5f, K::LIN, ""},
     {"open", "OPEN", 0, 1, 0.6f, K::LIN, ""},
     {"breath", "BREATH", 0, 1, 0.6f, K::LIN, ""},
     {"vibrato", "VIBRATO", 0, 100, 35, K::LIN, "cents"},
     {"tension", "TENSION", 0, 1, 0.55f, K::LIN, ""},
     {"oct", "OCT", -2, 2, 0, K::STEP, "-2|-1|0|+1|+2"},
     {"beast", "BEAST", 0, 3, 0, K::STEP, "SONGBIRD|SEAL|GATOR|ELEPHANT"},
     {"call", "CALL", 0, 3, 0, K::STEP, "1|2|3|4"},
     {"sound", "SOUND", 0, 9, 0, K::STEP, "KICK|HAT|OPEN HAT|SNARE|RIM|INWARD|CLICK|POP|CRASH|HUM"},
     {"seq", "SEQ", 0, 1, 0, K::STEP, "OFF|ON"},
     {"level", "LEVEL", 0, 2, 1, K::LIN, ""}},
    []() -> Module* { return new Voice_; }});

}  // namespace rack
