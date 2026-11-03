// The rack's core modules: sources, control, filters, shapers, time effects and mix. Built on
// DaisySP (MIT, pinned as vendor/daisysp). Every module is one class and one registration.
#include "rack.h"
#include <algorithm>
#include <random>
#include "Control/adsr.h"
#include "Effects/chorus.h"
#include "Effects/decimator.h"
#include "Effects/overdrive.h"
#include "Effects/wavefolder.h"
#include "Drums/analogbassdrum.h"
#include "Drums/analogsnaredrum.h"
#include "Drums/hihat.h"
#include "Filters/ladder.h"
#include "Filters/svf.h"
#include "Synthesis/oscillator.h"
#include "Utility/dcblock.h"
#include "Utility/delayline.h"

namespace rack {
using K = Knob;

static float rnd01() {
  static std::minstd_rand rng(12345);
  return (rng() & 0xFFFFFF) / 16777215.0f;
}
static float rnd11() { return rnd01() * 2.0f - 1.0f; }
// A rising edge of a gate, with a little hysteresis.
struct Edge {
  bool high = false;
  bool operator()(float v) {
    bool was = high;
    high = high ? v > 0.2f : v > 0.5f;
    return high && !was;
  }
};

// ---- KEYS: the player's notes -----------------------------------------------------------------
struct Keys_ : Module {
  float pitch_ = 0;
  void process() override {
    const Keys& k = ctx->keys;
    float glide = real(1);
    float target = k.pitch + (float)((int)real(0)) + k.bend * 2.0f / 12.0f;
    float coef = glide <= 0.001f ? 1.0f : 1.0f - std::exp(-1.0f / (glide * RATE));
    for (int s = 0; s < BLOCK; ++s) {
      pitch_ += (target - pitch_) * coef;
      o(0)[s] = pitch_;
      o(1)[s] = k.gate;
      o(2)[s] = k.vel;
      o(3)[s] = k.mod;
      o(4)[s] = k.bend;
    }
  }
};
static Registrar r_keys({"keys", "KEYS", "Source", "Your notes: pitch, gate, velocity, the mod wheel and the bend.",
    {}, {"pitch", "gate", "vel", "mod", "bend"},
    {{"oct", "OCT", -3, 3, 0, K::STEP, "-3|-2|-1|0|+1|+2|+3"}, {"glide", "GLIDE", 0, 1, 0, K::LIN, "s"}},
    []() -> Module* { return new Keys_; }});

// ---- CLOCK: tempo, from the song or its own -----------------------------------------------------
struct Clock_ : Module {
  double phase_ = 0;  // in 16ths
  int left16_ = 0, left8_ = 0, leftb_ = 0, leftbar_ = 0, ticks_ = 0;
  bool running_ = true, was_playing_ = false;
  void process() override {
    bool host = choice(1) == 1;
    double bpm = host ? ctx->tp.bpm : real(0);
    bool run = host ? ctx->tp.playing : true;
    double per = 60.0 / bpm / 4.0;  // seconds per 16th
    double step = 1.0 / (per * RATE);
    if (host && run) phase_ = ctx->tp.beats * 4.0;
    bool reset = false;
    if (host && run && !was_playing_) { reset = true; }
    was_playing_ = run;
    int width = std::max(1, (int)(0.005 * RATE));
    for (int s = 0; s < BLOCK; ++s) {
      if (run) {
        double before = phase_;
        // swing delays every second 16th
        double sw = real(2);
        phase_ += host ? 0.0 : step;
        if (host) phase_ += step;  // sub-block position
        long a = (long)std::floor(before), b = (long)std::floor(phase_);
        if (b != a) {
          long t = b;
          bool odd = (t & 1) != 0;
          (void)sw; (void)odd;
          left16_ = width;
          if (t % 2 == 0) left8_ = width;
          if (t % 4 == 0) leftb_ = width;
          if (t % 16 == 0) leftbar_ = width;
        }
      }
      o(0)[s] = left16_ > 0 ? 1.0f : 0.0f;
      o(1)[s] = left8_ > 0 ? 1.0f : 0.0f;
      o(2)[s] = leftb_ > 0 ? 1.0f : 0.0f;
      o(3)[s] = leftbar_ > 0 ? 1.0f : 0.0f;
      o(4)[s] = (reset && s == 0) ? 1.0f : 0.0f;
      left16_ = std::max(0, left16_ - 1); left8_ = std::max(0, left8_ - 1);
      leftb_ = std::max(0, leftb_ - 1); leftbar_ = std::max(0, leftbar_ - 1);
    }
    if (host && run) phase_ = ctx->tp.beats * 4.0;  // stay locked to the song, not to our sum
  }
};
static Registrar r_clock({"clock", "CLOCK", "Control", "Tempo as pulses: 16ths, 8ths, beats and bars; locked to the song or free.",
    {}, {"16th", "8th", "beat", "bar", "reset"},
    {{"bpm", "TEMPO", 40, 240, 120, K::LIN, "bpm"}, {"sync", "SYNC", 0, 1, 1, K::STEP, "FREE|SONG"},
     {"swing", "SWING", 0, 0.6f, 0, K::LIN, ""}},
    []() -> Module* { return new Clock_; }});

// ---- SEQ: sixteen steps ------------------------------------------------------------------------
struct Seq_ : Module {
  Edge clk_, rst_;
  int step_ = -1;
  int gate_left_ = 0;
  int since_ = 0, period_ = (int)(0.125f * RATE);
  float pitch_ = 0;
  void process() override {
    int len = (int)real(16);
    float gate_len = real(17);
    for (int s = 0; s < BLOCK; ++s) {
      since_++;
      if (rst_(in[1][s])) step_ = -1;
      if (clk_(in[0][s])) {
        period_ = std::max(since_, 1);
        since_ = 0;
        step_ = (step_ + 1) % len;
        int v = choice(step_);  // 0 is a rest
        if (v > 0) {
          pitch_ = (v - 13) / 12.0f;
          gate_left_ = std::max(1, (int)(period_ * gate_len));
        } else {
          gate_left_ = 0;
        }
      }
      o(0)[s] = pitch_;
      o(1)[s] = gate_left_ > 0 ? 1.0f : 0.0f;
      o(2)[s] = step_ < 0 ? 0.0f : step_ / 15.0f;
      if (gate_left_ > 0) gate_left_--;
    }
  }
};
static Registrar r_seq([] {
  static std::vector<std::string> ids, labels;
  ids.clear(); labels.clear();
  std::vector<Knob> ks;
  for (int i = 0; i < 16; ++i) {
    ids.push_back("s" + std::to_string(i + 1));
    labels.push_back(std::to_string(i + 1));
  }
  for (int i = 0; i < 16; ++i)
    ks.push_back({ids[i].c_str(), labels[i].c_str(), 0, 37, 0, K::STEP, "REST|-12|-11|-10|-9|-8|-7|-6|-5|-4|-3|-2|-1|0|+1|+2|+3|+4|+5|+6|+7|+8|+9|+10|+11|+12|+13|+14|+15|+16|+17|+18|+19|+20|+21|+22|+23|+24"});
  ks.push_back({"len", "LENGTH", 1, 16, 16, K::STEP, "1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16"});
  ks.push_back({"gate", "GATE", 0.05f, 1.0f, 0.5f, K::LIN, ""});
  return Spec{"seq", "SEQ", "Control", "Sixteen steps of pitch (or rest) advanced by a clock.",
      {"clk", "rst"}, {"pitch", "gate", "step"}, ks, []() -> Module* { return new Seq_; }};
}());

// ---- LFO ---------------------------------------------------------------------------------------
struct Lfo_ : Module {
  float phase_ = 0, held_ = 0;
  Edge sync_;
  void process() override {
    float base = real(0);
    int shape = choice(1);
    float depth = real(2);
    for (int s = 0; s < BLOCK; ++s) {
      if (sync_(in[1][s])) phase_ = 0;
      float f = base * std::exp2(in[0][s]);
      phase_ += f / RATE;
      if (phase_ >= 1.0f) { phase_ -= 1.0f; held_ = rnd11(); }
      float v = 0;
      switch (shape) {
        case 0: v = std::sin(phase_ * 6.2831853f); break;
        case 1: v = 1.0f - 4.0f * std::fabs(phase_ - 0.5f); break;
        case 2: v = 2.0f * phase_ - 1.0f; break;
        case 3: v = phase_ < 0.5f ? 1.0f : -1.0f; break;
        default: v = held_; break;
      }
      o(0)[s] = v * depth;
      o(1)[s] = (v * depth) * 0.5f + 0.5f;
    }
  }
};
static Registrar r_lfo({"lfo", "LFO", "Control", "A slow oscillator for movement.",
    {"rate", "sync"}, {"out", "uni"},
    {{"rate", "RATE", 0.02f, 40, 2, K::EXP, "Hz"}, {"shape", "SHAPE", 0, 4, 0, K::STEP, "SINE|TRI|SAW|SQR|S&H"},
     {"depth", "DEPTH", 0, 1, 1, K::LIN, ""}},
    []() -> Module* { return new Lfo_; }});

// ---- NOISE -------------------------------------------------------------------------------------
struct Noise_ : Module {
  float b0 = 0, b1 = 0, b2 = 0;
  void process() override {
    for (int s = 0; s < BLOCK; ++s) {
      float w = rnd11();
      b0 = 0.99765f * b0 + w * 0.0990460f;
      b1 = 0.96300f * b1 + w * 0.2965164f;
      b2 = 0.57000f * b2 + w * 1.0526913f;
      o(0)[s] = w * 0.5f;
      o(1)[s] = (b0 + b1 + b2 + w * 0.1848f) * 0.12f;
    }
  }
};
static Registrar r_noise({"noise", "NOISE", "Source", "White and pink noise.", {}, {"white", "pink"}, {},
    []() -> Module* { return new Noise_; }});

// ---- S&H and SLEW and ATT ----------------------------------------------------------------------
struct Sh_ : Module {
  Edge trig_;
  float v_ = 0;
  void process() override {
    bool noise_in = !has(0);
    for (int s = 0; s < BLOCK; ++s) {
      if (trig_(in[1][s])) v_ = noise_in ? rnd11() : in[0][s];
      o(0)[s] = v_;
    }
  }
};
static Registrar r_sh({"sh", "S&H", "Control", "Samples its input on each trigger (noise when unpatched).",
    {"in", "trig"}, {"out"}, {}, []() -> Module* { return new Sh_; }});

struct Slew_ : Module {
  float v_ = 0;
  void process() override {
    float rise = real(0), fall = real(1);
    float cr = rise <= 0.0005f ? 1.0f : 1.0f - std::exp(-1.0f / (rise * RATE));
    float cf = fall <= 0.0005f ? 1.0f : 1.0f - std::exp(-1.0f / (fall * RATE));
    for (int s = 0; s < BLOCK; ++s) {
      float t = in[0][s];
      v_ += (t - v_) * (t > v_ ? cr : cf);
      o(0)[s] = v_;
    }
  }
};
static Registrar r_slew({"slew", "SLEW", "Control", "Smooths a signal: glide, lag and portamento.",
    {"in"}, {"out"}, {{"rise", "RISE", 0, 2, 0.05f, K::LIN, "s"}, {"fall", "FALL", 0, 2, 0.05f, K::LIN, "s"}},
    []() -> Module* { return new Slew_; }});

struct Att_ : Module {
  void process() override {
    float g = real(0), off = real(1);
    for (int s = 0; s < BLOCK; ++s) {
      o(0)[s] = in[0][s] * g + off;
      o(1)[s] = -(in[0][s] * g + off);
    }
  }
};
static Registrar r_att({"att", "ATT", "Control", "Scales, flips and offsets a signal.",
    {"in"}, {"out", "inv"}, {{"gain", "GAIN", -2, 2, 1, K::LIN, ""}, {"offset", "OFFSET", -1, 1, 0, K::LIN, ""}},
    []() -> Module* { return new Att_; }});

// ---- QUANT -------------------------------------------------------------------------------------
struct Quant_ : Module {
  void process() override {
    static const int scales[12][12] = {
      {0,1,2,3,4,5,6,7,8,9,10,11}, {0,2,4,5,7,9,11,-1}, {0,2,3,5,7,8,10,-1}, {0,2,3,5,7,9,10,-1},
      {0,1,3,5,7,8,10,-1}, {0,2,4,6,7,9,11,-1}, {0,2,4,5,7,9,10,-1}, {0,2,4,7,9,-1},
      {0,3,5,7,10,-1}, {0,3,5,6,7,10,-1}, {0,2,4,6,8,10,-1}, {0,2,3,5,7,8,11,-1}};
    const int* sc = scales[std::min(choice(0), 11)];
    int root = choice(1);
    for (int s = 0; s < BLOCK; ++s) {
      float semis = in[0][s] * 12.0f - root;
      float oct = std::floor(semis / 12.0f);
      float rel = semis - oct * 12.0f;
      float best = 0, bd = 99;
      for (int i = 0; i < 12 && sc[i] >= 0; ++i) {
        for (int w = -1; w <= 1; ++w) {
          float cand = sc[i] + 12 * w;
          float d = std::fabs(cand - rel);
          if (d < bd) { bd = d; best = cand; }
        }
      }
      o(0)[s] = (oct * 12.0f + best + root) / 12.0f;
    }
  }
};
static Registrar r_quant({"quant", "QUANT", "Control", "Snaps a pitch to a scale.", {"in"}, {"out"},
    {{"scale", "SCALE", 0, 11, 1, K::STEP, "CHROM|MAJOR|MINOR|DORIAN|PHRYG|LYDIAN|MIXO|PENT+|PENT-|BLUES|WHOLE|HARM-"},
     {"root", "ROOT", 0, 11, 0, K::STEP, "C|C#|D|D#|E|F|F#|G|G#|A|A#|B"}},
    []() -> Module* { return new Quant_; }});

// ---- ENV ---------------------------------------------------------------------------------------
struct Env_ : Module {
  daisysp::Adsr adsr_;
  void init() override { adsr_.Init(RATE); }
  void process() override {
    adsr_.SetAttackTime(real(0));
    adsr_.SetDecayTime(real(1));
    adsr_.SetSustainLevel(real(2));
    adsr_.SetReleaseTime(real(3));
    for (int s = 0; s < BLOCK; ++s) {
      float v = adsr_.Process(in[0][s] > 0.5f);
      o(0)[s] = v;
      o(1)[s] = 1.0f - v;
    }
  }
};
static Registrar r_env({"env", "ENV", "Control", "An ADSR envelope opened by a gate.", {"gate"}, {"out", "inv"},
    {{"a", "A", 0.001f, 4, 0.01f, K::EXP, "s"}, {"d", "D", 0.001f, 4, 0.3f, K::EXP, "s"},
     {"s", "S", 0, 1, 0.6f, K::LIN, ""}, {"r", "R", 0.001f, 8, 0.3f, K::EXP, "s"}},
    []() -> Module* { return new Env_; }});

// ---- VCO ---------------------------------------------------------------------------------------
struct Vco_ : Module {
  daisysp::Oscillator osc_, sub_;
  Edge sync_;
  void init() override { osc_.Init(RATE); sub_.Init(RATE); sub_.SetWaveform(daisysp::Oscillator::WAVE_SQUARE); }
  void process() override {
    static const int waves[] = {daisysp::Oscillator::WAVE_SIN, daisysp::Oscillator::WAVE_POLYBLEP_TRI,
        daisysp::Oscillator::WAVE_POLYBLEP_SAW, daisysp::Oscillator::WAVE_POLYBLEP_SQUARE};
    osc_.SetWaveform(waves[std::min(choice(0), 3)]);
    float tune = real(1) / 12.0f + real(2) / 1200.0f;
    float fma = real(3), pw = real(4);
    for (int s = 0; s < BLOCK; ++s) {
      if (sync_(in[3][s])) { osc_.Reset(); sub_.Reset(); }
      float p = in[0][s] + tune + in[1][s] * fma;
      float f = clampf(hz_of(p), 1.0f, 18000.0f);
      osc_.SetFreq(f);
      sub_.SetFreq(f * 0.5f);
      osc_.SetPw(clampf(pw + in[2][s] * 0.4f, 0.05f, 0.95f));
      o(0)[s] = osc_.Process() * 0.8f;
      o(1)[s] = sub_.Process() * 0.5f;
    }
  }
};
static Registrar r_vco({"vco", "VCO", "Source", "A band-limited oscillator: sine, triangle, saw, pulse.",
    {"pitch", "fm", "pwm", "sync"}, {"out", "sub"},
    {{"wave", "WAVE", 0, 3, 2, K::STEP, "SINE|TRI|SAW|PULSE"}, {"tune", "TUNE", -24, 24, 0, K::LIN, "st"},
     {"fine", "FINE", -100, 100, 0, K::LIN, "ct"}, {"fm", "FM", 0, 2, 0, K::LIN, ""}, {"pw", "PW", 0.05f, 0.95f, 0.5f, K::LIN, ""}},
    []() -> Module* { return new Vco_; }});

// ---- DRUM --------------------------------------------------------------------------------------
struct Drum_ : Module {
  daisysp::AnalogBassDrum bd_;
  daisysp::AnalogSnareDrum sd_;
  daisysp::HiHat<> hh_;
  Edge trig_;
  void init() override { bd_.Init(RATE); sd_.Init(RATE); hh_.Init(RATE); }
  void process() override {
    int kind = choice(0);
    float freq = real(1), tone = real(2), decay = real(3), accent = real(4);
    switch (kind) {
      case 0: bd_.SetFreq(freq); bd_.SetTone(tone); bd_.SetDecay(decay); bd_.SetAccent(accent); break;
      case 1: sd_.SetFreq(freq * 3.0f); sd_.SetTone(tone); sd_.SetDecay(decay); sd_.SetAccent(accent); sd_.SetSnappy(0.6f); break;
      default: hh_.SetFreq(freq * 100.0f); hh_.SetTone(tone); hh_.SetDecay(decay); hh_.SetAccent(accent); break;
    }
    for (int s = 0; s < BLOCK; ++s) {
      bool t = trig_(in[0][s]);
      float v = kind == 0 ? bd_.Process(t) : (kind == 1 ? sd_.Process(t) : hh_.Process(t));
      o(0)[s] = v * 0.9f;
    }
  }
};
static Registrar r_drum({"drum", "DRUM", "Source", "A kick, snare or hat voice, struck by a trigger.",
    {"trig"}, {"out"},
    {{"kind", "KIND", 0, 2, 0, K::STEP, "KICK|SNARE|HAT"}, {"freq", "FREQ", 0.05f, 0.6f, 0.2f, K::LIN, ""},
     {"tone", "TONE", 0, 1, 0.5f, K::LIN, ""}, {"decay", "DECAY", 0, 1, 0.5f, K::LIN, ""},
     {"accent", "ACCENT", 0, 1, 0.8f, K::LIN, ""}},
    []() -> Module* { return new Drum_; }});

// ---- SVF and LADDER ----------------------------------------------------------------------------
struct Svf_ : Module {
  daisysp::Svf f_;
  void init() override { f_.Init(RATE); }
  void process() override {
    float cut = real(0), res = real(1), drive = real(2), cv = real(3);
    for (int s = 0; s < BLOCK; ++s) {
      float fc = clampf(cut * std::exp2(in[1][s] * cv * 4.0f), 20.0f, 18000.0f);
      f_.SetFreq(fc);
      f_.SetRes(clampf(res + in[2][s] * 0.3f, 0.0f, 0.98f));
      f_.SetDrive(drive);
      f_.Process(in[0][s]);
      o(0)[s] = f_.Low(); o(1)[s] = f_.Band(); o(2)[s] = f_.High(); o(3)[s] = f_.Notch();
    }
  }
};
static Registrar r_svf({"svf", "SVF", "Filter", "A state-variable filter: low, band, high and notch together.",
    {"in", "cutoff", "res"}, {"lp", "bp", "hp", "notch"},
    {{"cutoff", "CUTOFF", 20, 18000, 1200, K::EXP, "Hz"}, {"res", "RES", 0, 0.98f, 0.3f, K::LIN, ""},
     {"drive", "DRIVE", 0, 1, 0.1f, K::LIN, ""}, {"cv", "CV", 0, 1, 0.5f, K::LIN, ""}},
    []() -> Module* { return new Svf_; }});

struct Ladder_ : Module {
  daisysp::LadderFilter f_;
  void init() override { f_.Init(RATE); }
  void process() override {
    using M = daisysp::LadderFilter::FilterMode;
    static const M modes[] = {M::LP24, M::LP12, M::BP24, M::BP12, M::HP24, M::HP12};
    f_.SetFilterMode(modes[std::min(choice(3), 5)]);
    f_.SetRes(real(1));
    f_.SetInputDrive(real(2));
    float cut = real(0), cv = real(4);
    for (int s = 0; s < BLOCK; ++s) {
      f_.SetFreq(clampf(cut * std::exp2(in[1][s] * cv * 4.0f), 20.0f, 18000.0f));
      o(0)[s] = f_.Process(in[0][s]);
    }
  }
};
static Registrar r_ladder({"ladder", "LADDER", "Filter", "A Moog-style ladder filter that sings when pushed.",
    {"in", "cutoff"}, {"out"},
    {{"cutoff", "CUTOFF", 20, 18000, 900, K::EXP, "Hz"}, {"res", "RES", 0, 1.8f, 0.4f, K::LIN, ""},
     {"drive", "DRIVE", 1, 4, 1.2f, K::LIN, ""}, {"mode", "MODE", 0, 5, 0, K::STEP, "LP24|LP12|BP24|BP12|HP24|HP12"},
     {"cv", "CV", 0, 1, 0.5f, K::LIN, ""}},
    []() -> Module* { return new Ladder_; }});

// ---- VCA, MIX, FOLD, DRIVE, CRUSH --------------------------------------------------------------
struct Vca_ : Module {
  void process() override {
    float lvl = real(0);
    bool exp = choice(1) == 1;
    bool cv = has(1);
    for (int s = 0; s < BLOCK; ++s) {
      float c = cv ? clampf(in[1][s], 0.0f, 1.5f) : 1.0f;
      if (exp) c *= c;
      o(0)[s] = in[0][s] * c * lvl;
    }
  }
};
static Registrar r_vca({"vca", "VCA", "Shape", "Amplifier: its level set by a control signal.", {"in", "cv"}, {"out"},
    {{"level", "LEVEL", 0, 2, 1, K::LIN, ""}, {"curve", "CURVE", 0, 1, 1, K::STEP, "LIN|EXP"}},
    []() -> Module* { return new Vca_; }});

struct Mix_ : Module {
  void process() override {
    float g[4] = {real(0), real(1), real(2), real(3)};
    float master = real(4);
    for (int s = 0; s < BLOCK; ++s) {
      float v = 0;
      for (int i = 0; i < 4; ++i) v += in[i][s] * g[i];
      o(0)[s] = v * master;
    }
  }
};
static Registrar r_mix({"mix", "MIX", "Mix", "Four inputs to one.", {"in1", "in2", "in3", "in4"}, {"out"},
    {{"l1", "1", 0, 1.5f, 0.7f, K::LIN, ""}, {"l2", "2", 0, 1.5f, 0.7f, K::LIN, ""}, {"l3", "3", 0, 1.5f, 0.7f, K::LIN, ""},
     {"l4", "4", 0, 1.5f, 0.7f, K::LIN, ""}, {"master", "OUT", 0, 1.5f, 1, K::LIN, ""}},
    []() -> Module* { return new Mix_; }});

struct Fold_ : Module {
  daisysp::Wavefolder wf_;
  void init() override { wf_.Init(); }
  void process() override {
    float gain = real(0), off = real(1);
    for (int s = 0; s < BLOCK; ++s) {
      wf_.SetGain(clampf(gain + in[1][s] * 4.0f, 1.0f, 12.0f));
      wf_.SetOffset(off);
      o(0)[s] = clampf(wf_.Process(in[0][s]) * 0.7f, -1.5f, 1.5f);
    }
  }
};
static Registrar r_fold({"fold", "FOLD", "Shape", "A wavefolder: harmonics from folding the wave back on itself.",
    {"in", "fold"}, {"out"}, {{"gain", "FOLD", 1, 12, 2, K::LIN, ""}, {"offset", "SYM", -1, 1, 0, K::LIN, ""}},
    []() -> Module* { return new Fold_; }});

struct Drive_ : Module {
  daisysp::Overdrive od_;
  void init() override { od_.Init(); }
  void process() override {
    od_.SetDrive(real(0));
    float lvl = real(1);
    for (int s = 0; s < BLOCK; ++s) o(0)[s] = od_.Process(in[0][s]) * lvl;
  }
};
static Registrar r_drive({"drive", "DRIVE", "Shape", "Soft overdrive.", {"in"}, {"out"},
    {{"drive", "DRIVE", 0, 1, 0.5f, K::LIN, ""}, {"level", "LEVEL", 0, 1.5f, 0.8f, K::LIN, ""}},
    []() -> Module* { return new Drive_; }});

struct Crush_ : Module {
  daisysp::Decimator dec_;
  void init() override { dec_.Init(); }
  void process() override {
    dec_.SetDownsampleFactor(real(0));
    dec_.SetBitsToCrush((uint8_t)real(1));
    float mix = real(2);
    for (int s = 0; s < BLOCK; ++s) o(0)[s] = in[0][s] * (1 - mix) + dec_.Process(in[0][s]) * mix;
  }
};
static Registrar r_crush({"crush", "CRUSH", "Shape", "Sample-rate and bit reduction.", {"in"}, {"out"},
    {{"rate", "RATE", 0, 0.95f, 0.3f, K::LIN, ""}, {"bits", "BITS", 2, 16, 8, K::STEP, "2|3|4|5|6|7|8|9|10|11|12|13|14|15|16"},
     {"mix", "MIX", 0, 1, 1, K::LIN, ""}},
    []() -> Module* { return new Crush_; }});

// ---- DELAY (stereo, synced or free) -----------------------------------------------------------
struct Delay_ : Module {
  daisysp::DelayLine<float, 96000> dl_, dr_;
  float lp_l = 0, lp_r = 0, time_ = 0.3f;
  void init() override { dl_.Init(); dr_.Init(); time_ = 0.3f; }
  void process() override {
    static const float mult[] = {0.0f, 0.25f, 0.5f, 0.75f, 1.0f, 1.5f, 2.0f};  // in beats; 0 = free
    int div = choice(1);
    float want = div == 0 ? real(0) : (float)(60.0 / ctx->tp.bpm * mult[div]);
    want = clampf(want, 0.005f, 1.9f);
    float fb = real(2), tone = real(3), mix = real(4);
    bool pp = choice(5) == 1;
    float a = 1.0f - std::exp(-6.2831853f * tone / RATE);
    for (int s = 0; s < BLOCK; ++s) {
      time_ += (want - time_) * 0.0005f;
      float d = time_ * RATE;
      float x = in[0][s];
      float l = dl_.ReadHermite(d), r = dr_.ReadHermite(pp ? d : d * 1.013f);
      lp_l += (l - lp_l) * a; lp_r += (r - lp_r) * a;
      if (pp) { dl_.Write(x + lp_r * fb); dr_.Write(lp_l * fb); }
      else { dl_.Write(x + lp_l * fb); dr_.Write(x + lp_r * fb); }
      o(0)[s] = x * (1 - mix) + l * mix;
      o(1)[s] = x * (1 - mix) + r * mix;
    }
  }
};
static Registrar r_delay({"delay", "DELAY", "Time", "A stereo echo: free or tied to the song's tempo, with a ping-pong.",
    {"in"}, {"l", "r"},
    {{"time", "TIME", 0.01f, 1.9f, 0.35f, K::EXP, "s"},
     {"sync", "SYNC", 0, 6, 0, K::STEP, "FREE|1/16|1/8|1/8.|1/4|1/4.|1/2"},
     {"fb", "FEEDBACK", 0, 0.95f, 0.4f, K::LIN, ""}, {"tone", "TONE", 200, 12000, 5000, K::EXP, "Hz"},
     {"mix", "MIX", 0, 1, 0.35f, K::LIN, ""}, {"pp", "MODE", 0, 1, 0, K::STEP, "STEREO|PING-PONG"}},
    []() -> Module* { return new Delay_; }});

// ---- CHORUS ------------------------------------------------------------------------------------
struct Chorus_ : Module {
  daisysp::Chorus ch_;
  void init() override { ch_.Init(RATE); }
  void process() override {
    ch_.SetLfoFreq(real(0));
    ch_.SetLfoDepth(real(1));
    ch_.SetDelayMs(real(2));
    ch_.SetFeedback(real(3));
    float mix = real(4);
    for (int s = 0; s < BLOCK; ++s) {
      float x = in[0][s];
      ch_.Process(x);
      o(0)[s] = x * (1 - mix) + ch_.GetLeft() * mix;
      o(1)[s] = x * (1 - mix) + ch_.GetRight() * mix;
    }
  }
};
static Registrar r_chorus({"chorus", "CHORUS", "Time", "Thickens a sound with a slow, swimming copy of itself.", {"in"}, {"l", "r"},
    {{"rate", "RATE", 0.05f, 6, 0.4f, K::EXP, "Hz"}, {"depth", "DEPTH", 0, 1, 0.6f, K::LIN, ""},
     {"delay", "DELAY", 1, 30, 8, K::LIN, "ms"}, {"fb", "FEEDBACK", 0, 0.9f, 0.2f, K::LIN, ""},
     {"mix", "MIX", 0, 1, 0.5f, K::LIN, ""}},
    []() -> Module* { return new Chorus_; }});

// ---- OUT: the room's output --------------------------------------------------------------------
struct Out_ : Module {
  daisysp::DcBlock dcl_, dcr_;
  bool ready_ = false;
  void init() override { dcl_.Init(RATE); dcr_.Init(RATE); }
  void process() override {
    float lvl = real(0);
    bool right = has(1);
    for (int s = 0; s < BLOCK; ++s) {
      float l = in[0][s], r = right ? in[1][s] : l;
      l = std::tanh(dcl_.Process(l) * lvl);
      r = std::tanh(dcr_.Process(r) * lvl);
      o(0)[s] = l; o(1)[s] = r;
    }
  }
};
static Registrar r_out({"out", "OUT", "Mix", "The output: to the speakers, and out of the room to a track.", {"l", "r"}, {"l", "r"},
    {{"level", "LEVEL", 0, 2, 0.7f, K::LIN, ""}},
    []() -> Module* { return new Out_; }});

}  // namespace rack
