// STAGES: Mutable Instruments' segment generator (MIT), pinned as the submodule
// vendor/mutable-eurorack and compiled from there. One module is one group of up to four segments,
// shaped by knobs, that a gate runs: an envelope, a looping ramp, a small step sequencer, a chain
// of timed levels or an LFO, chosen by PRESET. The firmware's own SegmentGenerator does the work
// (Configure with a segment list, set_segment_parameters, Process with GateFlags per sample).
//
// Rates. The firmware runs at 31.25 kHz (stages::kSampleRate) and its times are tables of
// per-sample increments for that rate; the rack runs at 48 kHz. Rather than bend the time tables,
// the generator is run at its own rate and resampled: a fractional clock (31.25/48 ticks per rack
// frame) decides on which rack frames the firmware takes a step; the gate it sees at a step is
// high if the rack gate was high on any frame since the last step (a one-frame trigger is never
// lost); the output is the line between the last two firmware samples. So 1 s is 1 s at 48 kHz,
// the LFO's Hz are real Hz, and the cost is about one firmware sample (32 us) of delay.
#include "rack.h"
#include <algorithm>
#include "stages/segment_generator.h"
#include "stmlib/utils/gate_flags.h"

namespace rack {
using K = Knob;

struct Stages_ : Module {
  enum Preset { AD, AHD, ADSR, ASR, CYCLE, SEQ, TIMER, DECAY, PULSE, LFO, N_PRESETS };
  stages::SegmentGenerator* gen_ = nullptr;
  int configured_ = -1;
  int nseg_ = 0;
  bool multi_ = false, single_ = false, seq_ = false;
  float acc_ = 0.0f;            // fractional firmware tick position, 0..1
  float v_prev_ = 0.0f, v_cur_ = 0.0f;
  float done_ = 0.0f;
  bool gate_seen_ = false;      // some rack frame since the last firmware tick was high
  stmlib::GateFlags flags_ = stmlib::GATE_FLAG_LOW;

  Stages_() {
    // Zeroed first: Init leaves a few members (the delay's phase) to the .bss of the hardware.
    void* mem = ::operator new(sizeof(stages::SegmentGenerator));
    std::memset(mem, 0, sizeof(stages::SegmentGenerator));
    gen_ = new (mem) stages::SegmentGenerator();
    gen_->Init();
  }
  ~Stages_() { gen_->~SegmentGenerator(); ::operator delete(gen_); }

  void configure(int p) {
    using namespace stages::segment;
    const Configuration R = {TYPE_RAMP, false}, H = {TYPE_HOLD, false}, S = {TYPE_STEP, false};
    const Configuration Rl = {TYPE_RAMP, true}, Hl = {TYPE_HOLD, true};
    multi_ = single_ = seq_ = false;
    switch (p) {
      case AD:     { Configuration c[] = {R, R};         gen_->Configure(true, c, 2); nseg_ = 2; multi_ = true; break; }
      case AHD:    { Configuration c[] = {R, H, R};      gen_->Configure(true, c, 3); nseg_ = 3; multi_ = true; break; }
      // attack, decay to the sustain level, hold while the gate is high, release when it falls.
      case ADSR:   { Configuration c[] = {R, R, Hl, R};  gen_->Configure(true, c, 4); nseg_ = 4; multi_ = true; break; }
      case ASR:    { Configuration c[] = {R, Hl, R};     gen_->Configure(true, c, 3); nseg_ = 3; multi_ = true; break; }
      case CYCLE:  { Configuration c[] = {Rl, Rl};       gen_->Configure(true, c, 2); nseg_ = 2; multi_ = true; break; }
      // segment 0 sets the direction; the three steps after it are advanced by the gate.
      case SEQ:    { Configuration c[] = {H, S, S, S};   gen_->Configure(true, c, 4); nseg_ = 4; seq_ = true; break; }
      case TIMER:  { Configuration c[] = {H, H, H, H};   gen_->Configure(true, c, 4); nseg_ = 4; multi_ = true; break; }
      case DECAY:  { gen_->Configure(true, &R, 1); nseg_ = 1; single_ = true; break; }
      case PULSE:  { gen_->Configure(true, &H, 1); nseg_ = 1; single_ = true; break; }
      default:     { gen_->Configure(false, &Rl, 1); nseg_ = 1; single_ = true; break; }  // free-running LFO
    }
    // DECAY and PULSE start out mid-segment in the firmware (the hardware has a power-up to ignore
    // it): run them at their fastest time on a low gate until they sit idle, output unheard.
    if (p == DECAY || p == PULSE) {
      gen_->set_segment_parameters(0, 0.0f, 0.0f);
      stmlib::GateFlags low[64];
      stages::SegmentGenerator::Output junk[64];
      for (int i = 0; i < 64; ++i) low[i] = stmlib::GATE_FLAG_LOW;
      gen_->Process(low, junk, 64);
    }
    flags_ = stmlib::GATE_FLAG_LOW;
    configured_ = p;
    v_prev_ = v_cur_ = 0.0f;
  }

  // Knob k (level, time, shape) of segment slot s (0..3), with the CVs in.
  float lvl(int s, float cv) const { return clampf(knob[1 + s * 3] + cv, 0.0f, 1.0f); }
  float tim(int s, float cv) const { return clampf(knob[2 + s * 3] + cv * 0.3f, 0.0f, 1.0f); }
  float shp(int s) const { return clampf(knob[3 + s * 3], 0.0f, 1.0f); }

  void process() override {
    const int p = clamp_int(choice(0), 0, N_PRESETS - 1);
    if (p != configured_) configure(p);
    const float tcv = clampf(has(1) ? in[1][0] : 0.0f, -1.0f, 1.0f);
    const float lcv = clampf(has(2) ? in[2][0] : 0.0f, -1.0f, 1.0f);
    const bool reset = has(3) && in[3][0] > 0.5f;
    const bool free_gate = !has(0) && (p == CYCLE);  // a cycle with no gate patched just runs
    // Parameters as the firmware reads them off the sliders and pots (0..1).
    auto set = [&](int i, float a, float b) { gen_->set_segment_parameters(i, a, b); };
    switch (p) {
      case AD:    set(0, tim(0, tcv), shp(0)); set(1, tim(1, tcv), shp(1)); break;
      case AHD:   set(0, tim(0, tcv), shp(0)); set(1, lvl(1, lcv), tim(1, tcv)); set(2, tim(2, tcv), shp(2)); break;
      case ADSR:  set(0, tim(0, tcv), shp(0)); set(1, tim(1, tcv), shp(1)); set(2, lvl(2, lcv), 0.0f);
                  set(3, tim(3, tcv), shp(3)); break;
      case ASR:   set(0, tim(0, tcv), shp(0)); set(1, lvl(1, lcv), 0.0f); set(2, tim(2, tcv), shp(2)); break;
      case CYCLE: set(0, tim(0, tcv), shp(0)); set(1, tim(1, tcv), shp(1)); break;
      case SEQ:   set(0, reset ? 1.0f : 0.0f, shp(0));
                  for (int i = 1; i < 4; ++i) set(i, lvl(i, lcv), shp(i));
                  break;
      case TIMER: for (int i = 0; i < 4; ++i) set(i, lvl(i, lcv), tim(i, tcv)); break;
      case DECAY: set(0, tim(0, tcv), shp(0)); break;
      case PULSE: set(0, lvl(1, lcv), tim(1, tcv)); break;
      default:    set(0, tim(0, tcv), shp(0)); break;  // LFO: rate (0.5 = 2 Hz, 96 semitones across), shape
    }

    // Pass 1: where the firmware ticks fall among the 24 frames, and the gate it sees at each.
    const float kRatio = stages::kSampleRate / RATE;
    constexpr int MAXT = BLOCK;  // kRatio < 1, so never more ticks than frames
    stmlib::GateFlags gf[MAXT];
    int tick_of[BLOCK];          // ticks completed at the end of this frame
    float frac[BLOCK];           // position between the last tick and the next
    int nt = 0;
    for (int f = 0; f < BLOCK; ++f) {
      if (free_gate || (has(0) && in[0][f] > 0.5f)) gate_seen_ = true;
      acc_ += kRatio;
      if (acc_ >= 1.0f) {
        acc_ -= 1.0f;
        flags_ = stmlib::ExtractGateFlags(flags_, gate_seen_);
        gf[nt++] = flags_;
        gate_seen_ = free_gate || (has(0) && in[0][f] > 0.5f);
      }
      tick_of[f] = nt;
      frac[f] = acc_;
    }
    // Pass 2: the firmware, once per block, on exactly the ticks that fell in it.
    stages::SegmentGenerator::Output so[MAXT];
    if (nt > 0) gen_->Process(gf, so, nt);
    // Pass 3: the line between the last two firmware samples, at each frame.
    float* out0 = o(0);
    float* out1 = o(1);
    int used = 0;
    for (int f = 0; f < BLOCK; ++f) {
      while (used < tick_of[f]) {
        v_prev_ = v_cur_;
        v_cur_ = so[used].value;
        if (!std::isfinite(v_cur_)) v_cur_ = 0.0f;
        const int sg = so[used].segment;
        done_ = single_ ? (sg == 1 ? 1.0f : 0.0f)
                        : (multi_ ? (sg >= nseg_ ? 1.0f : 0.0f) : 0.0f);
        ++used;
      }
      const float v = v_prev_ + (v_cur_ - v_prev_) * frac[f];
      out0[f] = clampf(std::isfinite(v) ? v : 0.0f, 0.0f, 1.0f);
      out1[f] = done_;
    }
    peak = 0.0f;
    for (int f = 0; f < BLOCK; ++f) peak = std::max(peak, out0[f]);
  }
  int playhead() const override { return -1; }
  static int clamp_int(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
};

static Registrar r_stages({"stages", "STAGES", "Shape",
    "Mutable Instruments' segment generator: a gate runs up to four segments of level, time and shape as an envelope, a looping ramp, a small step sequencer, a timer chain or an LFO.",
    {"gate", "time", "level", "reset"}, {"out", "end"},
    {{"preset", "PRESET", 0, 9, 2, K::STEP, "AD|AHD|ADSR|ASR|CYCLE|SEQ|TIMER|DECAY|PULSE|LFO"},
     {"l1", "LEVEL 1", 0, 1, 0, K::LIN, ""}, {"t1", "TIME 1", 0, 1, 0.3f, K::LIN, ""}, {"s1", "SHAPE 1", 0, 1, 0.5f, K::LIN, ""},
     {"l2", "LEVEL 2", 0, 1, 1, K::LIN, ""}, {"t2", "TIME 2", 0, 1, 0.4f, K::LIN, ""}, {"s2", "SHAPE 2", 0, 1, 0.5f, K::LIN, ""},
     {"l3", "LEVEL 3", 0, 1, 0.6f, K::LIN, ""}, {"t3", "TIME 3", 0, 1, 0.4f, K::LIN, ""}, {"s3", "SHAPE 3", 0, 1, 0.5f, K::LIN, ""},
     {"l4", "LEVEL 4", 0, 1, 0, K::LIN, ""}, {"t4", "TIME 4", 0, 1, 0.5f, K::LIN, ""}, {"s4", "SHAPE 4", 0, 1, 0.5f, K::LIN, ""}},
    [] () -> Module* { return new Stages_(); }});

}  // namespace rack
