// The rack's BEADS module: Mutable Instruments' Beads firmware (MIT), pinned as vendor/mutable-eurorack and compiled
// from there, never copied (its source list is native/rack/libs/beads.txt). A granular texture synthesizer: the input
// is recorded into a ring of 4 seconds and played back as a cloud of grains, or (SIZE all the way up) as a multitap
// delay, then reverb.
//
// Media: the firmware runs its four media at their own codec rates: DIRTY TAPE 24 kHz, CLEAN TAPE 48 kHz (it
// decimates by two inside), VINTAGE 32 kHz, DIGITAL 48 kHz. The rack is 48 kHz, so the two 24 and 32 kHz media are
// run at their rate behind a small resampler pair (a 4th-order low-pass and linear interpolation each way, 24 frames
// becoming 12 or 16): approximate, but the lo-fi alias is part of the character. Changing media clears the buffer.
//
// Parameters: each of TIME/SIZE/SHAPE/PITCH is a RandomizedParameter; here each has CV present and attenuverter 1,
// so the value is the knob plus the CV and nothing is randomised (PITCH is in semitones, TIME/SIZE/SHAPE 0..1).
// SEED: unpatched the grains free-run (the hardware's locked seed button); patched, grains are made while the gate
// is high (at the DENSITY rate) and each rising edge starts one. DENSITY near the middle (0.48..0.52) is the
// hardware's "manual taps" zone and makes no grains unless SEED is patched.
#include "rack.h"
#include <algorithm>
#include "beads/dsp/processor.h"
#include "stmlib/utils/gate_flags.h"

namespace rack {
using K = Knob;

namespace {
struct Biquad {  // RBJ low-pass, Q = 0.7071
  float b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, z1 = 0, z2 = 0;
  void set(float fc, float fs) {
    float w = 2.0f * 3.14159265f * fc / fs, c = std::cos(w), al = std::sin(w) / (2.0f * 0.7071f);
    float a0 = 1.0f + al;
    b0 = (1.0f - c) * 0.5f / a0; b1 = (1.0f - c) / a0; b2 = b0;
    a1 = -2.0f * c / a0; a2 = (1.0f - al) / a0;
  }
  float run(float x) {
    float y = b0 * x + z1;
    z1 = b1 * x - a1 * y + z2;
    z2 = b2 * x - a2 * y;
    return y;
  }
  void reset() { z1 = z2 = 0; }
};
// Rate converter between the rack's rate and a slower one, `ratio` = 48000 / target (2 or 1.5), 24 frames <-> 24/ratio.
struct Conv {
  Biquad d[2], u[2];
  float prev_in = 0, prev_out = 0;
  void init(float target) {
    float fc = 0.42f * target;
    for (int i = 0; i < 2; ++i) { d[i].set(fc, RATE); u[i].set(fc, RATE); d[i].reset(); u[i].reset(); }
    prev_in = prev_out = 0;
  }
  int down(const float* x, float ratio, float* y) {
    float e[BLOCK + 1];
    e[0] = prev_in;
    for (int s = 0; s < BLOCK; ++s) e[s + 1] = d[1].run(d[0].run(x[s]));
    prev_in = e[BLOCK];
    int n = (int)(BLOCK / ratio + 0.001f);
    for (int k = 0; k < n; ++k) {
      float p = 1.0f + k * ratio;
      int i = (int)p; float f = p - i;
      y[k] = e[i] + f * (e[std::min(i + 1, BLOCK)] - e[i]);
    }
    return n;
  }
  void up(const float* y, int n, float ratio, float* x) {
    float e[BLOCK + 1];
    e[0] = prev_out;
    for (int k = 0; k < n; ++k) e[k + 1] = y[k];
    prev_out = e[n];
    for (int s = 0; s < BLOCK; ++s) {
      float p = s / ratio;
      int i = (int)p; float f = p - i;
      float v = e[i] + f * (e[std::min(i + 1, n)] - e[i]);
      x[s] = u[1].run(u[0].run(v));
    }
  }
};
}  // namespace

struct Beads_ : Module {
  beads::Processor* proc_;
  uint8_t* buf1_;
  uint8_t* buf2_;
  uint16_t* reverb_;
  Conv conv_[2];
  int media_ = -1;
  stmlib::GateFlags seed_prev_ = stmlib::GATE_FLAG_LOW;
  Beads_() {
    proc_ = new beads::Processor;
    buf1_ = new uint8_t[512 * 1024]();
    buf2_ = new uint8_t[256 * 1024]();
    reverb_ = new uint16_t[32768]();
  }
  ~Beads_() { delete proc_; delete[] buf1_; delete[] buf2_; delete[] reverb_; }
  void init() override {
    uint8_t* b[3] = {buf1_, buf1_ + 256 * 1024, buf2_};
    proc_->Init(b, reverb_);
  }
  static float cvk(float v) { return std::isfinite(v) ? v : 0.0f; }
  void process() override {
    using beads::Processor;
    int m = choice(8);
    if (m != media_) {
      media_ = m;
      proc_->Configure((Processor::Media)m, false);
      float sr = proc_->sample_rate();
      for (int c = 0; c < 2; ++c) conv_[c].init(sr);
    }
    const float sr = proc_->sample_rate();
    const bool resample = sr < 47000.0f;
    const float ratio = RATE / sr;

    float tcv = 0, pcv = 0;
    if (has(4)) { for (int s = 0; s < BLOCK; ++s) tcv += cvk(in[4][s]); tcv /= BLOCK; }
    if (has(5)) { for (int s = 0; s < BLOCK; ++s) pcv += cvk(in[5][s]); pcv /= BLOCK; }

    beads::Parameters p;
    p.time.base = real(0);       p.time.attenuverter = 1.0f;  p.time.has_cv = true;  p.time.cv = clampf(tcv, -1, 1);
    p.size.base = real(1);       p.size.attenuverter = 1.0f;  p.size.has_cv = true;  p.size.cv = 0.0f;
    p.shape.base = real(2);      p.shape.attenuverter = 1.0f; p.shape.has_cv = true; p.shape.cv = 0.0f;
    p.pitch.base = real(3);      p.pitch.attenuverter = 1.0f; p.pitch.has_cv = true;
    p.pitch.cv = clampf(pcv, -4, 4) * 12.0f;
    p.monophonic_mode = false;
    beads::ModulatedParameter d;
    d.base = real(4);
    d.cv = 0.0f;
    Processor::MixParameters mp;
    mp.feedback = real(5);
    mp.dry_wet = real(6);
    mp.reverb_amount = real(7);
    mp.output_gate = false;

    float inl[BLOCK], inr[BLOCK];
    for (int s = 0; s < BLOCK; ++s) {
      float l = cvk(in[0][s]), r = has(1) ? cvk(in[1][s]) : l;
      inl[s] = clampf(l, -2.0f, 2.0f);
      inr[s] = clampf(r, -2.0f, 2.0f);
    }
    const bool frz_knob = choice(9) == 1;
    bool frz[BLOCK];
    stmlib::GateFlags seed[BLOCK];
    for (int s = 0; s < BLOCK; ++s) {
      frz[s] = frz_knob || (has(3) && in[3][s] > 0.5f);
      seed_prev_ = stmlib::ExtractGateFlags(seed_prev_, has(2) && in[2][s] > 0.5f);
      seed[s] = seed_prev_;
    }

    beads::FloatFrame fi[BLOCK], fo[BLOCK];
    int n = BLOCK;
    if (resample) {
      float a[BLOCK], b[BLOCK];
      n = conv_[0].down(inl, ratio, a);
      conv_[1].down(inr, ratio, b);
      for (int s = 0; s < n; ++s) { fi[s].l = a[s]; fi[s].r = b[s]; }
      // Gates and seed pulses are decimated by taking any-high over each group of frames.
      bool df[BLOCK]; stmlib::GateFlags ds[BLOCK];
      for (int k = 0; k < n; ++k) {
        int lo = (int)(k * ratio), hi = std::min(BLOCK, (int)((k + 1) * ratio + 0.001f));
        bool f = false; bool hi_g = false, rise = false;
        for (int s = lo; s < hi; ++s) { f |= frz[s]; hi_g |= (seed[s] & stmlib::GATE_FLAG_HIGH) != 0; rise |= (seed[s] & stmlib::GATE_FLAG_RISING) != 0; }
        df[k] = f;
        ds[k] = (hi_g ? stmlib::GATE_FLAG_HIGH : 0) | (rise ? stmlib::GATE_FLAG_RISING : 0);
      }
      proc_->Process(has(2) ? beads::SEED_BUTTON_STATE_OFF : beads::SEED_BUTTON_STATE_LOCKED, has(2) ? ds : NULL, df,
                     d, p, mp, fi, fo, n);
      float a2[BLOCK], b2[BLOCK], ua[BLOCK], ub[BLOCK];
      for (int s = 0; s < n; ++s) { a2[s] = fo[s].l; b2[s] = fo[s].r; }
      conv_[0].up(a2, n, ratio, ua);
      conv_[1].up(b2, n, ratio, ub);
      for (int s = 0; s < BLOCK; ++s) { o(0)[s] = ua[s]; o(1)[s] = ub[s]; }
    } else {
      for (int s = 0; s < BLOCK; ++s) { fi[s].l = inl[s]; fi[s].r = inr[s]; }
      proc_->Process(has(2) ? beads::SEED_BUTTON_STATE_OFF : beads::SEED_BUTTON_STATE_LOCKED, has(2) ? seed : NULL,
                     frz, d, p, mp, fi, fo, n);
      for (int s = 0; s < BLOCK; ++s) { o(0)[s] = fo[s].l; o(1)[s] = fo[s].r; }
    }
    for (int c = 0; c < 2; ++c)
      for (int s = 0; s < BLOCK; ++s) {
        float v = o(c)[s];
        o(c)[s] = std::isfinite(v) ? clampf(v, -1.0f, 1.0f) : 0.0f;
      }
  }
};

static Registrar r_beads({"beads", "BEADS", "Time",
    "Mutable Instruments' Beads: a granular texture synthesizer that records what comes in and scatters it as grains, or as a pitch-shifting multitap delay.",
    {"l", "r", "seed", "freeze", "time", "pitch"}, {"l", "r"},
    {{"time", "TIME", 0, 1, 0.5f, K::LIN, ""}, {"size", "SIZE", 0, 1, 0.5f, K::LIN, ""},
     {"shape", "SHAPE", 0, 1, 0.5f, K::LIN, ""}, {"pitch", "PITCH", -24, 24, 0, K::LIN, "st"},
     {"density", "DENSITY", 0, 1, 0.75f, K::LIN, ""}, {"feedback", "FEEDBACK", 0, 1, 0, K::LIN, ""},
     {"mix", "MIX", 0, 1, 0.5f, K::LIN, ""}, {"reverb", "REVERB", 0, 1, 0.2f, K::LIN, ""},
     {"media", "MEDIA", 0, 3, 3, K::STEP, "DIRTY TAPE|CLEAN TAPE|VINTAGE|DIGITAL"},
     {"freeze", "FREEZE", 0, 1, 0, K::STEP, "OFF|ON"}},
    []() -> Module* { return new Beads_; }});

}  // namespace rack
