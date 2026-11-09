// The rack's ELEMENTS module: Mutable Instruments' elements firmware (MIT), pinned as vendor/mutable-eurorack and
// compiled from there, never copied. One of the second batch of Mutable modules (the first is modules_mutable.cc);
// its source list is native/rack/libs/elements.txt. The rack runs at 48 kHz: see docs/rack.md for how a firmware tuned
// for another rate is corrected.
#include "rack.h"
#include <algorithm>
#include "elements/dsp/part.h"

namespace rack {
using K = Knob;
static inline short to_short(float v) { return (short)(std::max(-1.0f, std::min(1.0f, v)) * 32760.0f); }

// ---- ELEMENTS ----------------------------------------------------------------------------------
// Exciters (bow, blow, strike) into a modal resonator, the voice from physical models of struck, bowed and
// blown things. A gate plays it; what is patched into the inputs is an exciter of its own.
//
// The firmware is tuned for 32 kHz in more places than its pitch table (envelope times, reverb delays, string decay
// and its noise delays are all counted in samples), so it is run at exactly that rate: the rack's block of 24 frames at
// 48 kHz is 16 frames at 32 kHz (one Part::Process, and kMaxBlockSize), converted each way by a windowed-sinc 3:2
// resampler (about 1 ms of delay, nothing above 14 kHz). Pitch, times and the reverb are then the hardware's own.
struct Elements_ : Module {
  static const int DT = 24, UT = 16;  // kernel half-widths: down (in 48 kHz samples), up (in 32 kHz samples)
  elements::Part part_;
  uint16_t reverb_[32768];
  float dn_[2][2 * DT + 1];  // 48k -> 32k: the kernel for output n at phase n&1 (centre at 1.5 n)
  float up_[3][2 * UT + 1];  // 32k -> 48k: phase m%3 (centre at 2m/3)
  float hist_in_[2][2 * DT + BLOCK];  // blow, strike at 48k
  float hist_out_[2][2 * UT + 16];    // main, aux at 32k
  static float kernel(float x, float half, float fc) {  // windowed-sinc low-pass, cutoff fc cycles per sample
    if (std::fabs(x) >= half) return 0.0f;
    float u = x / half, pix = 3.14159265f * 2.0f * fc * x;
    float sinc = std::fabs(pix) < 1e-6f ? 1.0f : std::sin(pix) / pix;
    float w = 0.42f + 0.5f * std::cos(3.14159265f * u) + 0.08f * std::cos(2.0f * 3.14159265f * u);
    return sinc * w;
  }
  void init() override {
    std::memset(reverb_, 0, sizeof(reverb_));
    std::memset((void*)&part_, 0, sizeof(part_));  // the firmware expects .bss (panic_, easter_egg_ and the voices)
    std::memset(hist_in_, 0, sizeof(hist_in_));
    std::memset(hist_out_, 0, sizeof(hist_out_));
    part_.Init(reverb_);
    part_.set_easter_egg(false);
    for (int ph = 0; ph < 2; ++ph) {  // centre at DT + 1.5 n: n even lands on a sample, n odd half-way
      float c = DT + 0.5f * ph, sum = 0;
      for (int k = 0; k <= 2 * DT; ++k) sum += (dn_[ph][k] = kernel(k - c, (float)DT, 0.30f));
      for (int k = 0; k <= 2 * DT; ++k) dn_[ph][k] /= sum;
    }
    for (int ph = 0; ph < 3; ++ph) {  // centre at UT + 2s/3, phase (2s)%3
      float c = UT + ph / 3.0f, sum = 0;
      for (int k = 0; k <= 2 * UT; ++k) sum += (up_[ph][k] = kernel(k - c, (float)UT, 0.45f));
      for (int k = 0; k <= 2 * UT; ++k) up_[ph][k] /= sum;
    }
  }
  void process() override {
    elements::Patch* p = part_.mutable_patch();
    p->exciter_envelope_shape = real(0);
    p->exciter_bow_level = real(1);
    p->exciter_bow_timbre = 0.5f;
    p->exciter_blow_level = real(2);
    p->exciter_blow_meta = real(4);
    p->exciter_blow_timbre = 0.5f;
    p->exciter_strike_level = real(3);
    p->exciter_strike_meta = real(5);
    p->exciter_strike_timbre = 0.5f;
    p->exciter_signature = 0.0f;
    p->resonator_geometry = real(6);
    p->resonator_brightness = real(7);
    p->resonator_damping = real(8);
    p->resonator_position = real(9);
    p->resonator_modulation_frequency = 0.5f / 32000.0f;  // the firmware's 0.5 Hz
    p->resonator_modulation_offset = 0.1f;
    p->reverb_diffusion = 0.625f;
    p->reverb_lp = 0.7f;
    p->space = real(10) * 1.5f;  // the firmware's range is 0..2; the top of it freezes the reverb, left out
    p->modulation_frequency = 0.0f;
    part_.set_resonator_model((elements::ResonatorModel)clampf((float)(int)real(12), 0.0f, 2.0f));
    elements::PerformanceState st;
    st.gate = in[1][0] > 0.5f;
    st.note = clampf(60.0f + 12.0f * clampf(in[0][0], -5.0f, 5.0f) + real(11), 0.0f, 126.0f);
    st.modulation = 0.0f;
    st.strength = has(2) ? clampf(in[2][0], 0.0f, 1.0f) : 0.5f;
    // 48 kHz -> 32 kHz: 24 frames become 16.
    for (int c = 0; c < 2; ++c) {
      float* h = hist_in_[c];
      std::memmove(h, h + BLOCK, 2 * DT * sizeof(float));
      for (int s = 0; s < BLOCK; ++s) h[2 * DT + s] = clampf(in[3 + c][s], -4.0f, 4.0f);
    }
    float blow[16], strike[16], main[16], aux[16];
    for (int n = 0; n < 16; ++n) {
      int base = (3 * n) / 2;  // the 48k sample at or before the centre 1.5 n, kernel window [base, base + 2 DT]
      const float* kd = dn_[n & 1];
      float b = 0, t = 0;
      for (int k = 0; k <= 2 * DT; ++k) { b += kd[k] * hist_in_[0][base + k]; t += kd[k] * hist_in_[1][base + k]; }
      blow[n] = b;
      strike[n] = t;
    }
    part_.Process(st, blow, strike, main, aux, 16);
    // 32 kHz -> 48 kHz.
    float* m = hist_out_[0];
    float* x = hist_out_[1];
    std::memmove(m, m + 16, 2 * UT * sizeof(float));
    std::memmove(x, x + 16, 2 * UT * sizeof(float));
    for (int n = 0; n < 16; ++n) { m[2 * UT + n] = main[n]; x[2 * UT + n] = aux[n]; }
    for (int s = 0; s < BLOCK; ++s) {
      int base = (2 * s) / 3, ph = (2 * s) % 3;  // centre at UT + 2s/3: whole part base, fraction ph/3
      const float* ku = up_[ph];
      float a = 0, b = 0;
      for (int k = 0; k <= 2 * UT; ++k) { a += ku[k] * m[base + k]; b += ku[k] * x[base + k]; }
      o(0)[s] = clampf(a, -2.0f, 2.0f);
      o(1)[s] = clampf(b, -2.0f, 2.0f);
    }
  }
};
static Registrar r_elements({"elements", "ELEMENTS", "Voice",
    "Mutable Instruments' modal synthesizer: bowed, blown and struck exciters into a resonator, then a reverb.",
    {"pitch", "gate", "level", "blow", "strike"}, {"out", "aux"},
    {{"contour", "CONTOUR", 0, 1, 0.5f, K::LIN, ""}, {"bow", "BOW", 0, 1, 0.0f, K::LIN, ""},
     {"blow", "BLOW", 0, 1, 0.0f, K::LIN, ""}, {"strike", "STRIKE", 0, 1, 0.6f, K::LIN, ""},
     {"flow", "FLOW", 0, 1, 0.5f, K::LIN, ""}, {"mallet", "MALLET", 0, 1, 0.5f, K::LIN, ""},
     {"geometry", "GEOMETRY", 0, 1, 0.4f, K::LIN, ""}, {"bright", "BRIGHT", 0, 1, 0.6f, K::LIN, ""},
     {"damping", "DAMPING", 0, 1, 0.5f, K::LIN, ""}, {"position", "POSITION", 0, 1, 0.3f, K::LIN, ""},
     {"space", "SPACE", 0, 1, 0.2f, K::LIN, ""}, {"note", "NOTE", -24, 24, 0, K::LIN, "st"},
     {"model", "MODEL", 0, 2, 0, K::STEP, "MODAL|STRING|STRINGS"}},
    []() -> Module* { return new Elements_; }});


}  // namespace rack
