// PEAKS: Mutable Instruments' dual function generator (STM32 firmware, MIT), compiled from the pinned
// submodule vendor/mutable-eurorack and never copied. One channel of it: a function chosen by a step knob
// (envelope, LFO, tap LFO, bouncing ball, mini sequencer, pulse shaper, pulse randomiser, four drums), the
// four 16-bit parameters of the firmware's full control mode, a trigger and a reset input. The firmware
// runs at 48 kHz like the rack; its processors are used directly (the hardware Processors table also holds
// the number station, which is a radio toy not wanted here).
#include "rack.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include "peaks/drums/bass_drum.h"
#include "peaks/drums/fm_drum.h"
#include "peaks/drums/high_hat.h"
#include "peaks/drums/snare_drum.h"
#include "peaks/modulations/bouncing_ball.h"
#include "peaks/modulations/lfo.h"
#include "peaks/modulations/mini_sequencer.h"
#include "peaks/modulations/multistage_envelope.h"
#include "peaks/pulse_processor/pulse_randomizer.h"
#include "peaks/pulse_processor/pulse_shaper.h"

namespace rack {
using K = Knob;

struct Peaks_ : Module {
  enum Fn { ENV, LFO, TAP, BALL, SEQ, SHAPER, RANDOM, BD, SD, HH, FM, N_FN };
  peaks::MultistageEnvelope env_;
  peaks::Lfo lfo_, tap_;
  peaks::BouncingBall ball_;
  peaks::MiniSequencer seq_;
  peaks::PulseShaper shaper_;
  peaks::PulseRandomizer random_;
  peaks::BassDrum bd_;
  peaks::SnareDrum sd_;
  peaks::HighHat hh_;
  peaks::FmDrum fm_;
  int fn_ = -1;
  bool gate_ = false, reset_ = false;

  void init() override {
    env_.Init(); lfo_.Init(); tap_.Init(); tap_.set_sync(true); ball_.Init(); seq_.Init();
    shaper_.Init(); random_.Init(); bd_.Init(); sd_.Init(); hh_.Init(); fm_.Init();
    fn_ = -1;
    gate_ = reset_ = false;
  }
  void start(int f) {
    switch (f) {
      case ENV: env_.Init(); break;
      case LFO: lfo_.Init(); break;
      case TAP: tap_.Init(); tap_.set_sync(true); break;
      case BALL: ball_.Init(); break;
      case SEQ: seq_.Init(); break;
      case SHAPER: shaper_.Init(); break;
      case RANDOM: random_.Init(); break;
      case BD: bd_.Init(); break;
      case SD: sd_.Init(); break;
      case HH: hh_.Init(); break;
      case FM: fm_.Init(); break;
    }
  }
  static float clamp01(float v) { return !(v > 0.0f) ? 0.0f : (v > 1.0f ? 1.0f : v); }
  static float finite(float v) { return std::isfinite(v) ? v : 0.0f; }

  void process() override {
    int f = std::min(std::max((int)real(0), 0), (int)N_FN - 1);
    if (f != fn_) { start(f); fn_ = f; }
    // The four parameters, 0..1 each (the first two take the CV inputs), as the firmware's 16-bit values.
    float pv[4];
    for (int k = 0; k < 4; ++k) pv[k] = real(1 + k);
    if (has(2)) pv[0] += 0.5f * finite(in[2][0]);
    if (has(3)) pv[1] += 0.5f * finite(in[3][0]);
    uint16_t p[4];
    for (int k = 0; k < 4; ++k) p[k] = (uint16_t)(clamp01(pv[k]) * 65535.0f + 0.5f);

    peaks::GateFlags g[BLOCK];
    for (int s = 0; s < BLOCK; ++s) {
      float t = finite(in[0][s]), r = finite(in[1][s]);
      bool gate = gate_ ? t > 0.2f : t > 0.5f;
      bool rst = reset_ ? r > 0.2f : r > 0.5f;
      peaks::GateFlags fl = peaks::ExtractGateFlags(gate_ ? peaks::GATE_FLAG_HIGH : peaks::GATE_FLAG_LOW, gate);
      if (rst && !reset_) fl |= peaks::GATE_FLAG_AUXILIARY_RISING;
      if (rst) fl |= peaks::GATE_FLAG_AUXILIARY_HIGH;
      g[s] = fl;
      gate_ = gate; reset_ = rst;
    }

    int16_t y[BLOCK];
    std::memset(y, 0, sizeof(y));
    const auto F = peaks::CONTROL_MODE_FULL;
    float scale = 1.0f / 32768.0f;
    bool audio = false;
    switch (f) {
      case ENV: env_.Configure(p, F); env_.Process(g, y, BLOCK); break;
      case LFO: lfo_.Configure(p, F); lfo_.Process(g, y, BLOCK); scale = 1.0f / 20480.0f; break;
      case TAP: tap_.Configure(p, F); tap_.Process(g, y, BLOCK); scale = 1.0f / 20480.0f; break;
      case BALL: ball_.Configure(p, F); ball_.Process(g, y, BLOCK); break;
      case SEQ: seq_.Configure(p, F); seq_.Process(g, y, BLOCK); scale = 1.0f / 20480.0f; break;
      case SHAPER: shaper_.Configure(p, F); shaper_.Process(g, y, BLOCK); break;
      case RANDOM: random_.Configure(p, F); random_.Process(g, y, BLOCK); break;
      case BD: bd_.Configure(p, F); bd_.Process(g, y, BLOCK); audio = true; break;
      case SD: sd_.Configure(p, F); sd_.Process(g, y, BLOCK); audio = true; break;
      case HH: hh_.Process(g, y, BLOCK); audio = true; break;
      case FM: fm_.Configure(p, F); fm_.Process(g, y, BLOCK); audio = true; break;
    }
    float* a = o(0);
    float* c = o(1);
    for (int s = 0; s < BLOCK; ++s) {
      float v = std::min(1.0f, std::max(-1.0f, (float)y[s] * scale));
      a[s] = audio ? v : 0.0f;
      c[s] = audio ? 0.0f : v;
    }
  }
};
static Registrar r_peaks({"peaks", "PEAKS", "Source",
    "Mutable Instruments' dual function generator: an envelope, LFO, tap LFO, bouncing ball, mini sequencer, "
    "pulse shaper or randomiser, or a bass, snare, hat or FM drum. P1..P4 mean: ENV attack/decay/sustain/release; "
    "LFO rate/shape/shape param/phase; TAP LFO level/shape/param/phase; BALL gravity/bounce/height/speed; "
    "SEQ the four steps (reset input restarts); SHAPER delay/length/gap/repeats; RANDOM accept/repeat/delay/jitter; "
    "BASS pitch/punch/tone/decay; SNARE pitch/tone/snap/decay; HAT none; FM pitch/fm/decay/noise. Drums play on "
    "out, the rest on cv.",
    {"trig", "reset", "mod1", "mod2"}, {"out", "cv"},
    {{"function", "FUNCTION", 0, 10, 0, K::STEP,
      "ENVELOPE|LFO|TAP LFO|BOUNCING BALL|MINI SEQ|PULSE SHAPER|PULSE RANDOM|BASS DRUM|SNARE|HIGH HAT|FM DRUM"},
     {"p1", "P1", 0, 1, 0.5f, K::LIN, ""}, {"p2", "P2", 0, 1, 0.5f, K::LIN, ""},
     {"p3", "P3", 0, 1, 0.5f, K::LIN, ""}, {"p4", "P4", 0, 1, 0.5f, K::LIN, ""}},
    []() -> Module* { return new Peaks_; }});
}  // namespace rack
