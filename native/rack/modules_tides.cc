// The rack's TIDES module: Mutable Instruments' Tides 2 firmware (MIT), pinned as vendor/mutable-eurorack and compiled
// from there, never copied (its source list is native/rack/libs/tides.txt). A tidal modulator: a ramp generator that
// is an envelope, an LFO or an oscillator, with four related outputs.
//
// Sample rate: the hardware renders at 62.5 kHz in blocks of 8. Everything in the generator is expressed per sample
// (phase increments, filter coefficients), so nothing is resampled: the module hands the firmware a whole rack block
// (24 frames at 48 kHz, i.e. three firmware blocks' worth at once) and simply computes every frequency in cycles per
// *rack* sample (hz / 48000 where the firmware divides by its 62500). A stated frequency is then true at 48 kHz.
// Likewise a clock-derived period is measured by the ramp extractor in rack samples, so it is true at 48 kHz.
// SLOPE PHASE and FREQUENCY output modes run the firmware at half rate (every other frame; the output is held), as
// the hardware does, and double the per-step frequency to compensate.
#include "rack.h"
#include <algorithm>
#include <cstdlib>
#include <new>
#include "tides2/poly_slope_generator.h"
#include "tides2/ramp/ramp_extractor.h"
#include "stmlib/dsp/hysteresis_quantizer.h"
#include "stmlib/utils/gate_flags.h"

namespace rack {
using K = Knob;

struct Tides_ : Module {
  // The firmware's state lives in .bss on hardware (zero); here it is calloc'd, so nothing it leaves unset is garbage.
  struct Core {
    tides::PolySlopeGenerator gen;
    tides::RampExtractor extractor;
    stmlib::HysteresisQuantizer2 ratio_q;
  };
  Core* core_;
  Tides_() { core_ = new (calloc(1, sizeof(Core))) Core; }
  ~Tides_() { core_->~Core(); free(core_); }
  stmlib::GateFlags trig_prev_ = 0, clk_prev_ = 0;
  bool must_reset_ = true;
  int prev_output_mode_ = 0;
  float ramp_[BLOCK] = {};
  stmlib::GateFlags tf_[BLOCK], cf_[BLOCK], none_[BLOCK];
  tides::PolySlopeGenerator::OutputSample os_[BLOCK];
  float held_[4] = {};

  void init() override {
    core_->gen.Init();
    core_->ratio_q.Init(20, 0.05f, false);
    core_->extractor.Init(RATE, 40.0f / RATE);
    for (int i = 0; i < BLOCK; ++i) none_[i] = stmlib::GATE_FLAG_LOW;
  }

  void process() override {
    using namespace tides;
    const int rm = choice(2);   // 0 AD, 1 LOOPING, 2 AR
    const int om = choice(3);   // output mode
    const int rg = choice(4);   // 0 LOW, 1 CONTROL, 2 AUDIO
    const RampMode ramp_mode = RampMode(std::max(0, std::min(2, rm)));
    const OutputMode output_mode = OutputMode(std::max(0, std::min(3, om)));
    const Range range = rg < 2 ? RANGE_CONTROL : RANGE_AUDIO;
    const bool half = output_mode >= OUTPUT_MODE_SLOPE_PHASE;
    const int n = half ? BLOCK / 2 : BLOCK;
    const int step = half ? 2 : 1;

    // Gate flags (the firmware's edge detector), seeing a high on either frame of a decimated pair.
    for (int i = 0; i < n; ++i) {
      bool g = false, c = false;
      for (int k = 0; k < step; ++k) {
        g = g || in[0][i * step + k] > 0.5f;
        c = c || in[1][i * step + k] > 0.5f;
      }
      trig_prev_ = stmlib::ExtractGateFlags(trig_prev_, g);
      clk_prev_ = stmlib::ExtractGateFlags(clk_prev_, c);
      tf_[i] = trig_prev_;
      cf_[i] = clk_prev_;
    }

    // Pitch: the knob and the CV are in octaves; the firmware works in semitones.
    float oct = clampf(real(0) + clampf(in[2][0], -8.0f, 8.0f), -10.0f, 10.0f);
    float transposition = clampf(oct * 12.0f, -128.0f, 127.0f);

    float frequency;
    if (has(1)) {
      if (must_reset_) core_->extractor.Reset();
      static const Ratio kRatios[20] = {
        {0.0625f, 16}, {0.125f, 8}, {0.1666666f, 6}, {0.25f, 4}, {0.3333333f, 3}, {0.5f, 2}, {0.6666666f, 3},
        {0.75f, 4}, {0.8f, 5}, {1.0f, 1}, {1.0f, 1}, {1.25f, 4}, {1.3333333f, 3}, {1.5f, 2}, {2.0f, 1},
        {3.0f, 1}, {4.0f, 1}, {6.0f, 1}, {8.0f, 1}, {16.0f, 1}};
      Ratio r = core_->ratio_q.Lookup(kRatios, 0.5f + transposition * 0.0105f);
      frequency = core_->extractor.Process(range == RANGE_AUDIO, range == RANGE_AUDIO && ramp_mode == RAMP_MODE_AR,
                                     r, cf_, ramp_, n);
      must_reset_ = false;
    } else {
      // Roots: LOW 0.125 Hz, CONTROL 2 Hz, AUDIO C4 (261.63 Hz, so the pitch input is in the rack's octaves from C4).
      static const float kRoot[3] = {0.125f, 2.0f, C4_HZ};
      frequency = kRoot[std::max(0, std::min(2, rg))] / RATE * std::exp2(transposition / 12.0f);
      if (half) frequency *= 2.0f;
      must_reset_ = true;
    }
    if (!(frequency >= 0.0f)) frequency = 0.0f;
    if (output_mode != prev_output_mode_) { core_->gen.Reset(); prev_output_mode_ = output_mode; }

    float shape = clampf(real(1) + 0.5f * in[3][0], 0.0f, 1.0f);
    float slope = clampf(real(5) + 0.5f * in[4][0], 0.0f, 1.0f);
    float smooth = clampf(real(6), 0.0f, 1.0f);
    float shift = clampf(real(7), 0.0f, 1.0f);
    // knob order: 0 freq, 1 shape, 2 mode, 3 out, 4 range, 5 slope, 6 smooth, 7 shift
    core_->gen.Render(ramp_mode, output_mode, range, frequency, slope, shape, smooth, shift,
                has(0) ? tf_ : none_, (!has(0) && has(1)) ? ramp_ : nullptr, os_, n);

    const float unit = ramp_mode == RAMP_MODE_LOOPING ? 0.2f : 0.125f;  // firmware volts -> -1..1 / 0..1
    peak = 0.0f;
    for (int i = 0; i < n; ++i) {
      for (int j = 0; j < 4; ++j) {
        float u = (output_mode == OUTPUT_MODE_GATES && j >= 2) ? 0.125f : unit;
        float v = os_[i].channel[j] * u;
        if (!(v == v)) v = 0.0f;
        held_[j] = clampf(v, -1.0f, 1.0f);
        for (int k = 0; k < step; ++k) o(j)[i * step + k] = held_[j];
      }
    }
    for (int j = 0; j < 4; ++j) {
      for (int i = 0; i < BLOCK; ++i) peak = std::max(peak, std::fabs(o(j)[i]));
    }
  }
};

static Registrar r_tides({"tides", "TIDES", "Control",
    "Mutable Instruments' tidal modulator: a gate or clock in, four related slopes out, from an envelope to an LFO to an oscillator.",
    {"gate", "clock", "freq", "shape", "slope"}, {"out1", "out2", "out3", "out4"},
    {{"freq", "FREQUENCY", -4, 4, 0, K::LIN, "oct"}, {"shape", "SHAPE", 0, 1, 0.5f, K::LIN, ""},
     {"mode", "RAMP", 0, 2, 1, K::STEP, "AD|LOOPING|AR"},
     {"omode", "OUTPUT", 0, 3, 0, K::STEP, "GATES|AMPLITUDE|SLOPE PHASE|FREQUENCY"},
     {"range", "RANGE", 0, 2, 1, K::STEP, "LOW|CONTROL|AUDIO"},
     {"slope", "SLOPE", 0, 1, 0.5f, K::LIN, ""}, {"smooth", "SMOOTHNESS", 0, 1, 0.5f, K::LIN, ""},
     {"shift", "SHIFT", 0, 1, 1.0f, K::LIN, ""}},
    []() -> Module* { return new Tides_; }});

}  // namespace rack
