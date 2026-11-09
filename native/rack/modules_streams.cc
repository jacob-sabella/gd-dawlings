// STREAMS: Mutable Instruments' dual dynamics gate (STM32 firmware, MIT, pinned as the submodule
// vendor/mutable-eurorack and compiled from there, never copied). One channel of it: an envelope, a
// vactrol / low-pass gate, a compressor, an envelope follower or a Lorenz generator, each turning the
// control signal on EXCITE into a gain and a cutoff. On the hardware an analogue VCA and filter apply
// them; here they are a digital VCA and a 2-pole low-pass (a TPT state-variable filter) applied below.
//
// Time: the firmware runs one sample at a time at 31.089 kHz (drivers/adc.cc; its lookup tables are
// built for that rate in resources/lookup_tables.py). The rack runs 48 kHz in 24-frame blocks, so a
// phase accumulator steps the firmware 31089/48000 times per rack frame: every stated time (attack,
// decay, a Lorenz period) is true at 48 kHz. The firmware's input at each step is the mean of the
// two rack frames around it, and its gain and cutoff outputs are interpolated linearly between steps.
#include "rack.h"
#include <algorithm>
#include "streams/processor.h"

namespace rack {
using K = Knob;

struct Streams_ : Module {
  static constexpr double kFwRate = 31089.0;
  streams::Processor proc_;
  int function_ = -1, alt_ = -1;
  int32_t shape_ = -1, resp_ = -1;
  double phase_ = 0.0;
  float prev_a_ = 0, prev_e_ = 0;
  float g0_ = 0, g1_ = 0, f0_ = 1, f1_ = 1;  // firmware outputs: gain (0..1 = unity) and cutoff 0..1, last two steps
  float db0_ = 0, db1_ = 0;                    // the compressor's gain in dB
  float s1_ = 0, s2_ = 0;                      // state-variable filter

  // The firmware expects the zeroed .bss of the chip (its smoothed amounts are not set by Init).
  Streams_() { std::memset((void*)&proc_, 0, sizeof(proc_)); }
  void init() override {
    std::memset((void*)&proc_, 0, sizeof(proc_));
    proc_.Init(0);
  }

  static int32_t to16(float v01) { return (int32_t)(clampf(v01, 0.0f, 1.0f) * 65535.0f + 0.5f); }

  void process() override {
    int fn = choice(0);
    static const streams::ProcessorFunction kFn[5] = {
        streams::PROCESSOR_FUNCTION_ENVELOPE, streams::PROCESSOR_FUNCTION_VACTROL,
        streams::PROCESSOR_FUNCTION_FOLLOWER, streams::PROCESSOR_FUNCTION_COMPRESSOR,
        streams::PROCESSOR_FUNCTION_LORENZ_GENERATOR};
    fn = std::max(0, std::min(4, fn));
    int mode = std::max(0, std::min(2, choice(1)));
    int alt = choice(4);
    float amount = clampf(real(5), 0, 1), offset = clampf(real(6), 0, 1);
    float xgain = clampf(real(7), 0, 4), level = clampf(real(8), 0, 1.5f);

    if (fn != function_) { proc_.set_function(kFn[fn]); function_ = fn; }
    if (alt != alt_) { proc_.set_alternate(alt != 0); alt_ = alt; }
    int32_t sh = to16(real(2) + in[2][0]), rs = to16(real(3) + in[3][0]);
    if (sh != shape_) { proc_.set_parameter(0, (uint16_t)sh); shape_ = sh; }
    if (rs != resp_) { proc_.set_parameter(1, (uint16_t)rs); resp_ = rs; }
    proc_.Configure();

    const double step = kFwRate / (double)RATE;
    const bool follower_filter_only = fn == 2 && alt;  // the firmware then puts the cutoff in "gain"
    for (int n = 0; n < BLOCK; ++n) {
      float a = clampf(in[0][n], -1, 1), e = clampf(in[1][n] * xgain, -1, 1);
      phase_ += step;
      if (phase_ >= 1.0) {
        phase_ -= 1.0;
        int16_t ia = (int16_t)(0.5f * (a + prev_a_) * 32767.0f), ie = (int16_t)(0.5f * (e + prev_e_) * 32767.0f);
        uint16_t g = 0, f = 65535;
        proc_.Process(ia, ie, &g, &f);
        g0_ = g1_; f0_ = f1_; db0_ = db1_;
        if (fn == 3) {
          // The compressor's code is logarithmic: 256 LSB are 1.55 dB around unity (compressor.cc).
          db1_ = clampf(1.55f * ((float)g - 32767.0f) / 256.0f, -90.0f, 24.0f);
          g1_ = std::pow(10.0f, db1_ / 20.0f);
        } else if (follower_filter_only) {
          g1_ = 1.0f;
          f1_ = (float)g / 65535.0f;
        } else {
          g1_ = clampf((float)g / 32767.0f, 0.0f, 2.0f);
          f1_ = (float)f / 65535.0f;
        }
      }
      prev_a_ = a; prev_e_ = e;
      float t = (float)phase_;
      float g = g0_ + (g1_ - g0_) * t, f = f0_ + (f1_ - f0_) * t;
      // AMOUNT scales the control, OFFSET is the level it idles at. The compressor works in dB: AMOUNT
      // scales its reduction, OFFSET adds up to 12 dB of makeup.
      if (fn == 3) {
        float db = (db0_ + (db1_ - db0_) * t) * amount + offset * 12.0f;
        g = std::pow(10.0f, db / 20.0f);
        f = 1.0f;
      } else {
        g = offset + amount * (1.0f - offset) * g;
        f = offset + amount * (1.0f - offset) * f;
      }
      g = clampf(g, 0.0f, 16.0f);
      f = clampf(f, 0.0f, 1.0f);

      float x = a, y = x;
      if (mode != 0) {  // low-pass: 20 Hz to 20 kHz over the cutoff range, 12 dB per octave
        float hz = std::min(20.0f * std::exp2(10.0f * f), 20000.0f);
        float gk = std::tan(3.14159265f * hz / RATE), k = 1.4142f;
        // Zavalishin's TPT state-variable filter: stable under fast cutoff changes.
        float hp = (x - (k + gk) * s1_ - s2_) / (1.0f + k * gk + gk * gk);
        float bp = gk * hp + s1_;
        float lp = gk * bp + s2_;
        s1_ = gk * hp + bp;
        s2_ = gk * bp + lp;
        y = lp;
      }
      if (mode != 1) y *= g;
      if (!(y == y)) { y = 0; s1_ = s2_ = 0; }
      y = clampf(y * level, -2.0f, 2.0f);
      o(0)[n] = y;
      // CV: the control that is acting, 0..1.
      float cv = mode == 1 ? f : std::min(g, 1.0f);
      o(1)[n] = clampf(cv, 0.0f, 1.0f);
    }
    peak = 0;
    for (int n = 0; n < BLOCK; ++n) peak = std::max(peak, std::fabs(o(0)[n]));
  }
};
static Registrar r_streams({"streams", "STREAMS", "Shape",
    "Mutable Instruments' dual dynamics gate: an envelope, vactrol, follower, compressor or Lorenz generator shaping a signal as a VCA, a low-pass or both.",
    {"in", "excite", "shape_cv", "resp_cv"}, {"out", "cv"},
    {{"function", "FUNCTION", 0, 4, 0, K::STEP, "ENVELOPE|VACTROL|FOLLOWER|COMPRESSOR|LORENZ"},
     {"mode", "MODE", 0, 2, 2, K::STEP, "GAIN|FILTER|GAIN+FILTER"},
     {"shape", "SHAPE", 0, 1, 0.5f, K::LIN, ""}, {"resp", "RESPONSE", 0, 1, 0.5f, K::LIN, ""},
     {"alt", "ALT", 0, 1, 0, K::STEP, "A|B"},
     {"amount", "AMOUNT", 0, 1, 1, K::LIN, ""}, {"offset", "OFFSET", 0, 1, 0, K::LIN, ""},
     {"excite", "EXCITE", 0, 4, 1, K::LIN, ""}, {"level", "LEVEL", 0, 1.5f, 1, K::LIN, ""}},
    []() -> Module* { return new Streams_; }});

}  // namespace rack
