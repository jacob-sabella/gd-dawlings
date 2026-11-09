// The rack's WARPS module: Mutable Instruments' warps firmware (MIT), pinned as vendor/mutable-eurorack and
// compiled from there, never copied. One of the second batch of Mutable modules (the first is modules_mutable.cc);
// its source list is native/rack/libs/warps.txt. The rack runs at 48 kHz: see docs/rack.md for how a firmware tuned
// for another rate is corrected.
#include "rack.h"
#include <algorithm>
#include <cstring>
#include "warps/dsp/modulator.h"

namespace rack {
using K = Knob;
static inline short to_short(float v) { return (short)(std::max(-1.0f, std::min(1.0f, v)) * 32760.0f); }

// ---- WARPS -------------------------------------------------------------------------------------
// Two audio inputs go in, one signal comes out: cross-fade, fold, ring-modulate, XOR, compare, spectral,
// morph and vocoder. With no carrier patched its own oscillator is the carrier.
struct Warps_ : Module {
  warps::Modulator mod_;
  void init() override {
    memset((void*)&mod_, 0, sizeof(mod_));  // the firmware leaves its gate/gain state uninitialised
    mod_.Init(RATE);
    warps::Parameters* p = mod_.mutable_parameters();
    memset((void*)p, 0, sizeof(*p));
  }
  void process() override {
    warps::Parameters* p = mod_.mutable_parameters();
    p->channel_drive[0] = real(1) * real(1);
    p->channel_drive[1] = real(2) * real(2);
    p->modulation_algorithm = clampf(real(0) + in[2][0], 0.0f, 1.0f);
    p->modulation_parameter = clampf(real(3) + in[3][0], 0.0f, 1.0f);
    p->frequency_shift_pot = 0.0f;
    p->frequency_shift_cv = 0.0f;
    p->phase_shift = 0.0f;
    // The oscillator's pitch table is tuned for the hardware's 96 kHz, so at 48 kHz it runs an octave low: add 12.
    p->note = clampf(60.0f + 12.0f * in[4][0] + real(5), 0.0f, 120.0f) + 12.0f;
    p->carrier_shape = has(0) ? 0 : 1 + choice(4);  // external carrier, or the internal oscillator
    warps::ShortFrame inp[BLOCK], outp[BLOCK];
    for (int s = 0; s < BLOCK; ++s) { inp[s].l = to_short(in[0][s]); inp[s].r = to_short(in[1][s]); }
    mod_.Process(inp, outp, BLOCK);
    for (int s = 0; s < BLOCK; ++s) { o(0)[s] = outp[s].l / 32768.0f; o(1)[s] = outp[s].r / 32768.0f; }
  }
};
static Registrar r_warps({"warps", "WARPS", "Shape",
    "Mutable Instruments' meta-modulator: two signals in, one out, from ring modulation and folding to a vocoder.",
    {"carrier", "mod", "algo", "param", "pitch"}, {"out", "aux"},
    {{"algo", "ALGORITHM", 0, 1, 0.0f, K::LIN, ""}, {"drive1", "CARRIER LVL", 0, 1, 0.8f, K::LIN, ""},
     {"drive2", "MOD LVL", 0, 1, 0.8f, K::LIN, ""}, {"param", "PARAMETER", 0, 1, 0.5f, K::LIN, ""},
     {"osc", "INT OSC", 0, 2, 2, K::STEP, "SINE/SAW|TRI/PULSE|SAW/NOISE"}, {"note", "NOTE", -24, 24, 0, K::LIN, "st"}},
    []() -> Module* { return new Warps_; }});


}  // namespace rack
