// The rack's MARBLES module: Mutable Instruments' Marbles firmware (MIT), pinned as vendor/mutable-eurorack and compiled
// from there, never copied (its source list is native/rack/libs/marbles.txt). A random sampler: a T section that makes
// related random gates (three of them), and an X/Y section that samples random voltages in a scale on those clocks, with
// a "deja vu" loop that repeats what it just did.
//
// The hardware runs at 32 kHz in blocks of 5; every rate in the firmware is per sample or in cycles per sample, and it is
// handed RATE at Init, so the module gives it a whole rack block at a time and a stated frequency is true at 48 kHz.
// Pitch outputs are in octaves from C4 (a volt is an octave, as on the hardware).
#include "rack.h"
#include <algorithm>
#include <cstdlib>
#include <new>
#include "marbles/random/random_generator.h"
#include "marbles/random/random_stream.h"
#include "marbles/random/t_generator.h"
#include "marbles/random/x_y_generator.h"
#include "stmlib/dsp/hysteresis_quantizer.h"
#include "stmlib/utils/gate_flags.h"

namespace rack {
using K = Knob;

namespace {
// The scales the module offers (the hardware's six presets, as semitone lists with a weight for each degree).
struct Preset { int n; float semis[12]; uint8_t w[12]; };
const Preset kScales[6] = {
  {12, {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}, {255, 16, 96, 24, 128, 64, 8, 192, 16, 96, 24, 128}},  // major
  {12, {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}, {255, 16, 96, 128, 8, 64, 4, 192, 96, 16, 128, 16}},     // minor
  {5, {0, 2, 4, 7, 9}, {255, 96, 128, 192, 96}},                                                         // pentatonic
  {7, {0, 1, 4, 5, 7, 8, 11}, {255, 128, 128, 128, 192, 96, 96}},                                        // phrygian-ish (Gypsy)
  {12, {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}, {255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},  // chromatic
  {6, {0, 2, 4, 6, 8, 10}, {255, 255, 255, 255, 255, 255}},                                              // whole tone
};
marbles::Scale make_scale(const Preset& p) {
  marbles::Scale s;
  s.base_interval = 1.0f;
  s.num_degrees = p.n;
  for (int i = 0; i < p.n; ++i) { s.degree[i].voltage = p.semis[i] / 12.0f; s.degree[i].weight = p.w[i]; }
  return s;
}
const int kLoopLength[] = {1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16};
const marbles::Ratio kYRatios[] = {{1, 64}, {1, 48}, {1, 32}, {1, 24}, {1, 16}, {1, 12}, {1, 8}, {1, 6}, {1, 4}, {1, 3}, {1, 2}, {1, 1}};
}  // namespace

struct Marbles_ : Module {
  struct Core {
    marbles::RandomGenerator rg;
    marbles::RandomStream rs;
    marbles::TGenerator tg;
    marbles::XYGenerator xy;
  };
  Core* core_;
  Marbles_() { core_ = new (calloc(1, sizeof(Core))) Core; }
  ~Marbles_() { core_->~Core(); free(core_); }
  stmlib::GateFlags tprev_ = 0, xprev_ = 0;
  float prev_t_ = 0, prev_x_ = 0;
  float ramp_[BLOCK * 4] = {};
  bool gates_[BLOCK * 2] = {};
  float volts_[BLOCK * 4] = {};
  stmlib::GateFlags tflags_[BLOCK], xflags_[BLOCK];

  void init() override {
    core_->rg.Init(1);
    core_->rs.Init(&core_->rg);
    core_->tg.Init(&core_->rs, RATE);
    core_->xy.Init(&core_->rs, RATE);
    for (int i = 0; i < 6; ++i) core_->xy.LoadScale(i, make_scale(kScales[i]));
  }

  void process() override {
    using namespace marbles;
    // knobs: 0 model 1 range 2 rate 3 bias 4 jitter 5 deja 6 length 7 pw 8 xrange 9 spread 10 xbias 11 steps 12 scale 13 xmode 14 ydiv
    const bool ext_t = has(0), ext_xy = has(1);
    for (int s = 0; s < BLOCK; ++s) {
      bool t = in[0][s] > 0.5f, x = in[1][s] > 0.5f;
      tflags_[s] = stmlib::ExtractGateFlags(tprev_, t);
      xflags_[s] = stmlib::ExtractGateFlags(xprev_, x);
      tprev_ = tflags_[s];
      xprev_ = xflags_[s];
    }
    float deja = real(5);
    // a dead band around the middle locks the loop, as on the hardware
    float lockable = deja < 0.47f ? deja * 1.06382978723f : (deja > 0.53f ? 0.5f + (deja - 0.53f) * 1.06382978723f : 0.5f);
    int length = kLoopLength[std::max(0, std::min(11, choice(6)))];

    Ramps ramps;
    ramps.master = &ramp_[0];
    ramps.external = &ramp_[BLOCK];
    ramps.slave[0] = &ramp_[BLOCK * 2];
    ramps.slave[1] = &ramp_[BLOCK * 3];

    bool reset = false;
    core_->tg.set_model(TGeneratorModel(std::max(0, std::min(6, choice(0)))));
    core_->tg.set_range(TGeneratorRange(std::max(0, std::min(2, choice(1)))));
    core_->tg.set_rate(real(2));
    core_->tg.set_bias(real(3));
    core_->tg.set_jitter(real(4));
    core_->tg.set_deja_vu(lockable);
    core_->tg.set_length(length);
    core_->tg.set_pulse_width_mean(real(7) * 0.5f + 0.25f);
    core_->tg.set_pulse_width_std(0.1f);
    core_->tg.Process(ext_t, &reset, tflags_, ramps, gates_, BLOCK);

    GroupSettings xs, ys;
    xs.control_mode = ControlMode(std::max(0, std::min(2, choice(13))));
    xs.voltage_range = VoltageRange(std::max(0, std::min(2, choice(8))));
    xs.register_mode = false;
    xs.register_value = 0.0f;
    xs.spread = real(9);
    xs.bias = real(10);
    xs.steps = real(11);
    xs.deja_vu = lockable;
    xs.length = length;
    xs.ratio.p = 1;
    xs.ratio.q = 1;
    xs.scale_index = std::max(0, std::min(5, choice(12)));
    ys.control_mode = CONTROL_MODE_IDENTICAL;
    ys.voltage_range = VOLTAGE_RANGE_FULL;
    ys.register_mode = false;
    ys.register_value = 0.0f;
    ys.spread = 0.5f;
    ys.bias = 0.5f;
    ys.steps = 0.5f;
    ys.deja_vu = 0.0f;
    ys.length = 1;
    ys.ratio = kYRatios[std::max(0, std::min(11, choice(14)))];
    ys.scale_index = xs.scale_index;
    bool xreset = false;
    ClockSource src = ext_xy ? CLOCK_SOURCE_EXTERNAL : CLOCK_SOURCE_INTERNAL_T1_T2_T3;
    core_->xy.Process(src, xs, ys, &xreset, xflags_, ramps, volts_, BLOCK);

    for (int s = 0; s < BLOCK; ++s) {
      o(0)[s] = gates_[s * 2] ? 1.0f : 0.0f;
      o(1)[s] = ramps.master[s] < 0.5f ? 1.0f : 0.0f;
      o(2)[s] = gates_[s * 2 + 1] ? 1.0f : 0.0f;
      o(3)[s] = volts_[s * 4 + 0];
      o(4)[s] = volts_[s * 4 + 1];
      o(5)[s] = volts_[s * 4 + 2];
      o(6)[s] = volts_[s * 4 + 3];
    }
  }
};
static Registrar r_marbles({"marbles", "MARBLES", "Control",
    "Mutable Instruments' random sampler: three related random gates, and random notes in a scale that can loop what they just did.",
    {"clock", "xclock"}, {"t1", "t2", "t3", "x1", "x2", "x3", "y"},
    {{"model", "MODEL", 0, 6, 0, K::STEP, "BERNOULLI|CLUSTERS|DRUMS|INDEPENDENT|DIVIDER|THREE|MARKOV"},
     {"range", "RANGE", 0, 2, 1, K::STEP, "0.25X|1X|4X"}, {"rate", "RATE", 0, 1, 0.5f, K::LIN, ""},
     {"bias", "T BIAS", 0, 1, 0.5f, K::LIN, ""}, {"jitter", "JITTER", 0, 1, 0, K::LIN, ""},
     {"deja", "DEJA VU", 0, 1, 0.5f, K::LIN, ""}, {"length", "LENGTH", 0, 11, 3, K::STEP, "1|2|3|4|5|6|7|8|10|12|14|16"},
     {"width", "WIDTH", 0, 1, 0.5f, K::LIN, ""},
     {"xrange", "X RANGE", 0, 2, 0, K::STEP, "NARROW|POSITIVE|FULL"}, {"spread", "SPREAD", 0, 1, 0.5f, K::LIN, ""},
     {"xbias", "X BIAS", 0, 1, 0.5f, K::LIN, ""}, {"steps", "STEPS", 0, 1, 0.5f, K::LIN, ""},
     {"scale", "SCALE", 0, 5, 0, K::STEP, "MAJOR|MINOR|PENTA|GYPSY|CHROMATIC|WHOLE"},
     {"xmode", "X MODE", 0, 2, 0, K::STEP, "SAME|BUMP|TILT"}, {"ydiv", "Y DIV", 0, 11, 6, K::STEP, "1/64|1/48|1/32|1/24|1/16|1/12|1/8|1/6|1/4|1/3|1/2|1"}},
    []() -> Module* { return new Marbles_; }});

}  // namespace rack
