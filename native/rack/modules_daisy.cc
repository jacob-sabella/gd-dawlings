// The rack's second DaisySP batch (MIT, pinned as vendor/daisysp, compiled from there, never copied): the effects,
// oscillators, noise sources, physical models, drums and small controls of the library that the core batch did not
// take. Every module is one class and one registration, like modules_core.cc.
#include "rack.h"
#include <algorithm>
#include <cstdlib>
#include "Control/adenv.h"
#include "Drums/synthbassdrum.h"
#include "Drums/synthsnaredrum.h"
#include "Dynamics/limiter.h"
#include "Effects/autowah.h"
#include "Effects/flanger.h"
#include "Effects/phaser.h"
#include "Effects/pitchshifter.h"
#include "Effects/tremolo.h"
#include "Filters/soap.h"
#include "Noise/clockednoise.h"
#include "Noise/dust.h"
#include "Noise/fractal_noise.h"
#include "Noise/grainlet.h"
#include "Noise/particle.h"
#include "PhysicalModeling/KarplusString.h"
#include "PhysicalModeling/drip.h"
#include "PhysicalModeling/modalvoice.h"
#include "PhysicalModeling/resonator.h"
#include "PhysicalModeling/stringvoice.h"
#include "Synthesis/fm2.h"
#include "Synthesis/formantosc.h"
#include "Synthesis/harmonic_osc.h"
#include "Synthesis/oscillatorbank.h"
#include "Synthesis/variablesawosc.h"
#include "Synthesis/variableshapeosc.h"
#include "Synthesis/vosim.h"
#include "Synthesis/zoscillator.h"
#include "Utility/maytrig.h"
#include "Utility/smooth_random.h"

namespace rack {
using K = Knob;

namespace {
// A rising edge of a gate, with a little hysteresis (the same as the core batch's).
struct Edge2 {
  bool high = false;
  bool operator()(float v) {
    bool was = high;
    high = high ? v > 0.2f : v > 0.5f;
    return high && !was;
  }
};
// A pitch input (octaves from C4) plus a tune in semitones, as Hz.
inline float hz_at(float pitch, float semis, float lo = 8.0f, float hi = 16000.0f) {
  return clampf(hz_of(pitch + semis / 12.0f), lo, hi);
}
// A trigger that stays high for 1 ms so a one-sample event is seen by every module.
struct Pulse {
  int left = 0;
  float next(bool fire) {
    if (fire) left = 48;
    if (left > 0) { --left; return 1.0f; }
    return 0.0f;
  }
};
}  // namespace

// ================================================================== EFFECTS
// ---- PHASER ------------------------------------------------------------------------------------
struct Phaser_ : Module {
  daisysp::Phaser ph_;
  void init() override { ph_.Init(RATE); }
  void process() override {
    ph_.SetPoles(std::max(1, std::min(8, choice(4) + 1)));
    ph_.SetLfoFreq(real(0));
    ph_.SetLfoDepth(real(1));
    ph_.SetFreq(real(2));
    ph_.SetFeedback(real(3));
    float mix = real(5);
    for (int s = 0; s < BLOCK; ++s) {
      float x = in[0][s];
      o(0)[s] = x * (1 - mix) + ph_.Process(x) * mix;
    }
  }
};
static Registrar r_phaser({"phaser", "PHASER", "Time", "Sweeps notches through a sound for a slow, swirling whoosh.", {"in"}, {"out"},
    {{"rate", "RATE", 0.02f, 8, 0.3f, K::EXP, "Hz"}, {"depth", "DEPTH", 0, 1, 0.7f, K::LIN, ""},
     {"freq", "FREQ", 100, 6000, 1000, K::EXP, "Hz"}, {"fb", "FEEDBACK", 0, 0.75f, 0.3f, K::LIN, ""},
     {"poles", "POLES", 0, 7, 3, K::STEP, "1|2|3|4|5|6|7|8"}, {"mix", "MIX", 0, 1, 0.5f, K::LIN, ""}},
    []() -> Module* { return new Phaser_; }});

// ---- FLANGER -----------------------------------------------------------------------------------
struct Flanger_ : Module {
  daisysp::Flanger fl_;
  void init() override { fl_.Init(RATE); }
  void process() override {
    fl_.SetLfoFreq(real(0));
    fl_.SetLfoDepth(real(1));
    fl_.SetDelayMs(real(2));
    fl_.SetFeedback(real(3));
    float mix = real(4);
    for (int s = 0; s < BLOCK; ++s) {
      float x = in[0][s];
      o(0)[s] = x * (1 - mix) + fl_.Process(x) * mix;
    }
  }
};
static Registrar r_flanger({"flanger", "FLANGER", "Time", "A short, swept delay that sounds like a jet passing: combs sliding through a sound.", {"in"}, {"out"},
    {{"rate", "RATE", 0.02f, 6, 0.2f, K::EXP, "Hz"}, {"depth", "DEPTH", 0, 0.93f, 0.6f, K::LIN, ""},
     {"delay", "DELAY", 0.1f, 7, 1.5f, K::LIN, "ms"}, {"fb", "FEEDBACK", 0, 0.95f, 0.5f, K::LIN, ""},
     {"mix", "MIX", 0, 1, 0.5f, K::LIN, ""}},
    []() -> Module* { return new Flanger_; }});

// ---- TREMOLO -----------------------------------------------------------------------------------
struct Tremolo_ : Module {
  daisysp::Tremolo tr_;
  void init() override { tr_.Init(RATE); }
  void process() override {
    static const int waves[] = {daisysp::Oscillator::WAVE_SIN, daisysp::Oscillator::WAVE_TRI,
                                daisysp::Oscillator::WAVE_SAW, daisysp::Oscillator::WAVE_SQUARE};
    tr_.SetWaveform(waves[std::max(0, std::min(3, choice(2)))]);
    tr_.SetDepth(real(1));
    for (int s = 0; s < BLOCK; ++s) {
      tr_.SetFreq(clampf(real(0) * std::exp2(in[1][s]), 0.05f, 40.0f));
      o(0)[s] = tr_.Process(in[0][s]);
    }
  }
};
static Registrar r_tremolo({"tremolo", "TREMOLO", "Time", "Makes a sound swell and dip in volume, steadily.", {"in", "rate"}, {"out"},
    {{"rate", "RATE", 0.1f, 20, 4, K::EXP, "Hz"}, {"depth", "DEPTH", 0, 1, 0.6f, K::LIN, ""},
     {"wave", "WAVE", 0, 3, 0, K::STEP, "SINE|TRI|SAW|SQUARE"}},
    []() -> Module* { return new Tremolo_; }});

// ---- AUTOWAH -----------------------------------------------------------------------------------
struct Autowah_ : Module {
  daisysp::Autowah aw_;
  void init() override { aw_.Init(RATE); }
  void process() override {
    aw_.SetWah(real(0));
    aw_.SetDryWet(real(1) * 100.0f);
    aw_.SetLevel(real(2));
    for (int s = 0; s < BLOCK; ++s) o(0)[s] = aw_.Process(in[0][s]);
  }
};
static Registrar r_autowah({"autowah", "AUTOWAH", "Shape", "A filter that opens and closes with how loudly you play: wah-wah without a pedal.", {"in"}, {"out"},
    {{"wah", "WAH", 0, 1, 0.5f, K::LIN, ""}, {"mix", "MIX", 0, 1, 1, K::LIN, ""}, {"level", "LEVEL", 0, 1, 0.5f, K::LIN, ""}},
    []() -> Module* { return new Autowah_; }});

// ---- PITCH: the pitch shifter ------------------------------------------------------------------
struct Pitch_ : Module {
  daisysp::PitchShifter ps_;
  void init() override { ps_.Init(RATE); }
  void process() override {
    ps_.SetDelSize((uint32_t)real(2));
    ps_.SetFun(real(3));
    float mix = real(4);
    for (int s = 0; s < BLOCK; ++s) {
      ps_.SetTransposition(real(0) + in[1][s] * 12.0f);
      float x = in[0][s];
      o(0)[s] = x * (1 - mix) + ps_.Process(x) * mix;
    }
  }
};
static Registrar r_pitch({"pitch", "PITCH", "Shape", "Moves a sound up or down in pitch without changing its speed.", {"in", "shift"}, {"out"},
    {{"shift", "SHIFT", -24, 24, 0, K::LIN, "st"}, {"fine", "FINE", -1, 1, 0, K::LIN, ""},
     {"size", "SIZE", 256, 16384, 4096, K::EXP, ""}, {"fun", "FUN", 0, 1, 0, K::LIN, ""}, {"mix", "MIX", 0, 1, 1, K::LIN, ""}},
    []() -> Module* { return new Pitch_; }});

// ---- LIMIT: the peak limiter -------------------------------------------------------------------
struct Limit_ : Module {
  daisysp::Limiter lim_;
  void init() override { lim_.Init(); }
  void process() override {
    float buf[BLOCK];
    for (int s = 0; s < BLOCK; ++s) buf[s] = in[0][s];
    lim_.ProcessBlock(buf, BLOCK, std::pow(10.0f, real(0) / 20.0f));
    for (int s = 0; s < BLOCK; ++s) o(0)[s] = buf[s];
  }
};
static Registrar r_limit({"limit", "LIMIT", "Shape", "Pushes a sound up and stops its peaks from going over: louder without clipping.", {"in"}, {"out"},
    {{"gain", "GAIN", 0, 24, 6, K::LIN, "dB"}},
    []() -> Module* { return new Limit_; }});

// ================================================================== FILTER
// ---- SOAP: a band pass and band reject --------------------------------------------------------
struct Soap_ : Module {
  daisysp::Soap sp_;
  void init() override { sp_.Init(RATE); }
  void process() override {
    sp_.SetFilterBandwidth(real(1));
    for (int s = 0; s < BLOCK; ++s) {
      sp_.SetCenterFreq(clampf(real(0) * std::exp2(in[1][s]), 20.0f, 16000.0f));
      sp_.Process(in[0][s]);
      o(0)[s] = sp_.Bandpass();
      o(1)[s] = sp_.Bandreject();
    }
  }
};
static Registrar r_soap({"soap", "SOAP", "Filter", "A band filter with a pass output and a reject output: keep one band, or cut it out.", {"in", "cutoff"}, {"pass", "reject"},
    {{"freq", "FREQ", 40, 12000, 1000, K::EXP, "Hz"}, {"width", "WIDTH", 10, 6000, 300, K::EXP, "Hz"}},
    []() -> Module* { return new Soap_; }});

// ================================================================== CONTROL
// ---- AD: an attack/decay envelope -------------------------------------------------------------
struct Ad_ : Module {
  daisysp::AdEnv env_;
  Edge2 trig_;
  void init() override {
    env_.Init(RATE);
    env_.SetMin(0.0f);
    env_.SetMax(1.0f);
  }
  void process() override {
    env_.SetTime(daisysp::ADENV_SEG_ATTACK, real(0));
    env_.SetTime(daisysp::ADENV_SEG_DECAY, real(1));
    env_.SetCurve(real(2));
    for (int s = 0; s < BLOCK; ++s) {
      if (trig_(in[0][s])) env_.Trigger();
      o(0)[s] = env_.Process();
    }
  }
};
static Registrar r_ad({"ad", "AD", "Control", "A one-shot envelope: up in the attack time, down in the decay time, each trigger.", {"trig"}, {"out"},
    {{"attack", "ATTACK", 0.001f, 4, 0.005f, K::EXP, "s"}, {"decay", "DECAY", 0.005f, 8, 0.4f, K::EXP, "s"},
     {"curve", "CURVE", -10, 10, 0, K::LIN, ""}},
    []() -> Module* { return new Ad_; }});

// ---- COIN: a probability gate -----------------------------------------------------------------
struct Coin_ : Module {
  daisysp::Maytrig dice_;
  Edge2 trig_;
  bool pass_ = false;
  void process() override {
    float base = real(0);
    for (int s = 0; s < BLOCK; ++s) {
      if (trig_(in[0][s])) pass_ = dice_.Process(clampf(base + in[1][s], 0.0f, 1.0f));
      bool open = trig_.high;
      o(0)[s] = (pass_ && open) ? 1.0f : 0.0f;
      o(1)[s] = (!pass_ && open) ? 1.0f : 0.0f;
    }
  }
};
static Registrar r_coin({"coin", "COIN", "Control", "A coin toss for every trigger: it lets a gate through or holds it back, by chance.", {"gate", "chance"}, {"heads", "tails"},
    {{"chance", "CHANCE", 0, 1, 0.5f, K::LIN, ""}},
    []() -> Module* { return new Coin_; }});

// ---- WANDER: smooth random --------------------------------------------------------------------
struct Wander_ : Module {
  daisysp::SmoothRandomGenerator rnd_;
  void init() override { rnd_.Init(RATE); }
  void process() override {
    float depth = real(1);
    for (int s = 0; s < BLOCK; ++s) {
      rnd_.SetFreq(clampf(real(0) * std::exp2(in[0][s]), 0.005f, 200.0f));
      float v = rnd_.Process() * depth;
      o(0)[s] = v;
      o(1)[s] = v * 0.5f + 0.5f;
    }
  }
};
static Registrar r_wander({"wander", "WANDER", "Control", "A smoothly wandering random level: a slow, drifting change that never repeats.", {"rate"}, {"out", "uni"},
    {{"rate", "RATE", 0.01f, 40, 0.5f, K::EXP, "Hz"}, {"depth", "DEPTH", 0, 1, 1, K::LIN, ""}},
    []() -> Module* { return new Wander_; }});

// ================================================================== SOURCES
// ---- FM: a two-operator FM oscillator ---------------------------------------------------------
struct Fm_ : Module {
  daisysp::Fm2 fm_;
  void init() override { fm_.Init(RATE); }
  void process() override {
    static const float ratios[] = {0.25f, 0.5f, 1.0f, 1.5f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f, 7.0f, 8.0f};
    fm_.SetRatio(ratios[std::max(0, std::min(10, choice(0)))]);
    float tune = real(1);
    float idx = real(2);
    for (int s = 0; s < BLOCK; ++s) {
      fm_.SetFrequency(hz_at(in[0][s], tune));
      fm_.SetIndex(clampf(idx + in[1][s] * 4.0f, 0.0f, 12.0f));
      o(0)[s] = fm_.Process() * 0.8f;
    }
  }
};
static Registrar r_fm({"fm", "FM", "Source", "Two sine waves, one bending the pitch of the other: bells, basses and metal.", {"pitch", "index"}, {"out"},
    {{"ratio", "RATIO", 0, 10, 2, K::STEP, "1/4|1/2|1|3/2|2|3|4|5|6|7|8"}, {"tune", "TUNE", -24, 24, 0, K::LIN, "st"},
     {"index", "INDEX", 0, 8, 1.5f, K::LIN, ""}},
    []() -> Module* { return new Fm_; }});

// ---- FORMANT: a formant oscillator ------------------------------------------------------------
struct Formant_ : Module {
  daisysp::FormantOscillator fo_;
  void init() override { fo_.Init(RATE); }
  void process() override {
    float tune = real(1), form = real(0), ph = real(2);
    for (int s = 0; s < BLOCK; ++s) {
      float f = hz_at(in[0][s], tune, 20.0f, 6000.0f);
      fo_.SetCarrierFreq(f);
      fo_.SetFormantFreq(clampf(form * std::exp2(in[1][s]), 50.0f, 12000.0f));
      fo_.SetPhaseShift(ph);
      o(0)[s] = fo_.Process() * 0.8f;
    }
  }
};
static Registrar r_formant({"formant", "FORMANT", "Source", "A voice-like oscillator: a resonant peak you can slide, as in vowels.", {"pitch", "formant"}, {"out"},
    {{"formant", "FORMANT", 100, 5000, 900, K::EXP, "Hz"}, {"tune", "TUNE", -24, 24, 0, K::LIN, "st"},
     {"shift", "SHIFT", 0, 1, 0, K::LIN, ""}},
    []() -> Module* { return new Formant_; }});

// ---- VOSIM -------------------------------------------------------------------------------------
struct Vosim_ : Module {
  daisysp::VosimOscillator vo_;
  void init() override { vo_.Init(RATE); }
  void process() override {
    float tune = real(3);
    vo_.SetShape(real(2));
    for (int s = 0; s < BLOCK; ++s) {
      vo_.SetFreq(hz_at(in[0][s], tune, 20.0f, 6000.0f));
      vo_.SetForm1Freq(clampf(real(0) * std::exp2(in[1][s]), 50.0f, 12000.0f));
      vo_.SetForm2Freq(clampf(real(1), 50.0f, 12000.0f));
      o(0)[s] = vo_.Process() * 0.8f;
    }
  }
};
static Registrar r_vosim({"vosim", "VOSIM", "Source", "A buzzy, vocal oscillator made of squared sine pulses: robot voices and throaty basses.", {"pitch", "form1"}, {"out"},
    {{"form1", "FORM 1", 100, 5000, 600, K::EXP, "Hz"}, {"form2", "FORM 2", 100, 5000, 1500, K::EXP, "Hz"},
     {"shape", "SHAPE", -1, 1, 0, K::LIN, ""}, {"tune", "TUNE", -24, 24, 0, K::LIN, "st"}},
    []() -> Module* { return new Vosim_; }});

// ---- SHAPER: the variable-shape oscillator ----------------------------------------------------
struct Shaper_ : Module {
  daisysp::VariableShapeOscillator vs_;
  Edge2 reset_;
  void init() override { vs_.Init(RATE); }
  void process() override {
    float tune = real(2), ratio = real(4);
    bool sync = choice(3) == 1;
    vs_.SetSync(sync);
    for (int s = 0; s < BLOCK; ++s) {
      float f = hz_at(in[0][s], tune, 8.0f, 12000.0f);
      vs_.SetFreq(f);
      vs_.SetSyncFreq(clampf(f * ratio, 8.0f, 16000.0f));
      vs_.SetWaveshape(clampf(real(0) + in[1][s] * 0.5f, 0.0f, 1.0f));
      vs_.SetPW(clampf(real(1) + in[2][s] * 0.4f, 0.01f, 0.99f));
      o(0)[s] = vs_.Process() * 0.8f;
    }
  }
};
static Registrar r_shaper({"shaper", "SHAPER", "Source", "One oscillator that slides from a saw, through a triangle, to a pulse as you turn the shape.", {"pitch", "shape", "pwm"}, {"out"},
    {{"shape", "SHAPE", 0, 1, 0.3f, K::LIN, ""}, {"pw", "PW", 0, 1, 0.5f, K::LIN, ""}, {"tune", "TUNE", -24, 24, 0, K::LIN, "st"},
     {"sync", "SYNC", 0, 1, 0, K::STEP, "OFF|ON"}, {"ratio", "RATIO", 0.5f, 8, 2, K::EXP, ""}},
    []() -> Module* { return new Shaper_; }});

// ---- VARISAW -----------------------------------------------------------------------------------
struct VariSaw_ : Module {
  daisysp::VariableSawOscillator vs_;
  void init() override { vs_.Init(RATE); }
  void process() override {
    float tune = real(2);
    for (int s = 0; s < BLOCK; ++s) {
      vs_.SetFreq(hz_at(in[0][s], tune, 8.0f, 12000.0f));
      vs_.SetWaveshape(clampf(real(0) + in[1][s] * 0.5f, 0.0f, 1.0f));
      vs_.SetPW(clampf(real(1), 0.0f, 1.0f));
      o(0)[s] = vs_.Process() * 0.8f;
    }
  }
};
static Registrar r_varisaw({"varisaw", "VARISAW", "Source", "A saw with a notch and a ramp you can bend: bright, hollow and in between.", {"pitch", "shape"}, {"out"},
    {{"shape", "SHAPE", 0, 1, 0.5f, K::LIN, ""}, {"notch", "NOTCH", 0, 1, 0.5f, K::LIN, ""}, {"tune", "TUNE", -24, 24, 0, K::LIN, "st"}},
    []() -> Module* { return new VariSaw_; }});

// ---- ZOSC -------------------------------------------------------------------------------------
struct ZOsc_ : Module {
  daisysp::ZOscillator z_;
  void init() override { z_.Init(RATE); }
  void process() override {
    float tune = real(3);
    z_.SetMode(real(2));
    for (int s = 0; s < BLOCK; ++s) {
      z_.SetFreq(hz_at(in[0][s], tune, 20.0f, 6000.0f));
      z_.SetFormantFreq(clampf(real(0) * std::exp2(in[1][s]), 50.0f, 12000.0f));
      z_.SetShape(real(1));
      o(0)[s] = z_.Process() * 0.8f;
    }
  }
};
static Registrar r_zosc({"zosc", "ZOSC", "Source", "A windowed-sine oscillator with a sweepable formant: sharp, nasal and synthetic.", {"pitch", "formant"}, {"out"},
    {{"formant", "FORMANT", 100, 5000, 1200, K::EXP, "Hz"}, {"shape", "SHAPE", -1, 1, 0, K::LIN, ""},
     {"mode", "MODE", -1, 1, 0, K::LIN, ""}, {"tune", "TUNE", -24, 24, 0, K::LIN, "st"}},
    []() -> Module* { return new ZOsc_; }});

// ---- ADDITIVE: sixteen harmonics --------------------------------------------------------------
struct Additive_ : Module {
  daisysp::HarmonicOscillator<16> ho_;
  void init() override { ho_.Init(RATE); }
  void process() override {
    float amps[16];
    float tilt = real(1), odd = real(2), comb = real(3), tune = real(0);
    float total = 0.0f;
    for (int k = 0; k < 16; ++k) {
      float n = (float)(k + 1);
      float a = std::pow(n, -(1.0f + tilt * 1.5f));
      // odd above 0 thins the even harmonics, below 0 thins the odd ones
      bool is_odd = (k % 2) == 0;
      if (!is_odd && odd > 0) a *= (1.0f - odd);
      if (is_odd && odd < 0) a *= (1.0f + odd);
      // a comb: harmonics far from a chosen one fade
      if (comb > 0.0f) a *= std::exp(-comb * 3.0f * std::fabs(n - 1.0f - comb * 6.0f) / 8.0f);
      amps[k] = a;
      total += a;
    }
    if (total > 0.0f) for (int k = 0; k < 16; ++k) amps[k] /= total * 0.6f;
    ho_.SetAmplitudes(amps);
    for (int s = 0; s < BLOCK; ++s) {
      ho_.SetFreq(hz_at(in[0][s], tune, 8.0f, 3000.0f));
      o(0)[s] = ho_.Process() * 0.8f;
    }
  }
};
static Registrar r_additive({"additive", "ADDITIVE", "Source", "Sixteen sine harmonics added together: sculpt a tone by choosing which overtones ring.", {"pitch"}, {"out"},
    {{"tune", "TUNE", -24, 24, 0, K::LIN, "st"}, {"tilt", "TILT", -1, 1, 0, K::LIN, ""},
     {"oddeven", "ODD/EVEN", -1, 1, 0, K::LIN, ""}, {"comb", "COMB", 0, 1, 0, K::LIN, ""}},
    []() -> Module* { return new Additive_; }});

// ---- ORGAN: seven stacked oscillators ---------------------------------------------------------
struct Organ_ : Module {
  daisysp::OscillatorBank bank_;
  void init() override { bank_.Init(RATE); }
  void process() override {
    float amps[7];
    for (int k = 0; k < 7; ++k) amps[k] = real(k + 1);
    bank_.SetAmplitudes(amps);
    float tune = real(0);
    for (int s = 0; s < BLOCK; ++s) {
      bank_.SetFreq(hz_at(in[0][s], tune, 8.0f, 3000.0f));
      o(0)[s] = bank_.Process() * 0.5f;
    }
  }
};
static Registrar r_organ({"organ", "ORGAN", "Source", "Seven saw and square waves an octave apart, mixed by hand: strings and organ pads.", {"pitch"}, {"out"},
    {{"tune", "TUNE", -24, 24, 0, K::LIN, "st"}, {"saw8", "SAW 8'", 0, 1, 0.8f, K::LIN, ""}, {"sq8", "SQ 8'", 0, 1, 0, K::LIN, ""},
     {"saw4", "SAW 4'", 0, 1, 0.4f, K::LIN, ""}, {"sq4", "SQ 4'", 0, 1, 0, K::LIN, ""}, {"saw2", "SAW 2'", 0, 1, 0.2f, K::LIN, ""},
     {"sq2", "SQ 2'", 0, 1, 0, K::LIN, ""}, {"saw1", "SAW 1'", 0, 1, 0, K::LIN, ""}},
    []() -> Module* { return new Organ_; }});

// ---- DUST: random impulses --------------------------------------------------------------------
struct Dust_ : Module {
  daisysp::Dust dust_;
  Pulse pulse_;
  void init() override { dust_.Init(); }
  void process() override {
    float hz = real(0);
    for (int s = 0; s < BLOCK; ++s) {
      // the engine's Dust takes a density that it scales by 0.3, so ask for hz/(0.3*RATE)
      dust_.SetDensity(clampf(hz * std::exp2(in[0][s]) / (0.3f * RATE), 0.0f, 1.0f));
      float v = dust_.Process();
      o(0)[s] = v * real(1);
      o(1)[s] = pulse_.next(v > 0.0f);
    }
  }
};
static Registrar r_dust({"dust", "DUST", "Source", "Random clicks, some loud and some soft, as often as you ask: crackle, rain and random triggers.", {"rate"}, {"out", "trig"},
    {{"density", "DENSITY", 0.2f, 400, 8, K::EXP, "Hz"}, {"level", "LEVEL", 0, 1, 0.8f, K::LIN, ""}},
    []() -> Module* { return new Dust_; }});

// ---- STEPNOISE: noise held between ticks ------------------------------------------------------
struct StepNoise_ : Module {
  daisysp::ClockedNoise cn_;
  Edge2 sync_;
  void init() override { cn_.Init(RATE); }
  void process() override {
    for (int s = 0; s < BLOCK; ++s) {
      cn_.SetFreq(clampf(real(0) * std::exp2(in[0][s]), 0.05f, 20000.0f));
      if (sync_(in[1][s])) cn_.Sync();
      o(0)[s] = cn_.Process() * real(1);
    }
  }
};
static Registrar r_stepnoise({"stepnoise", "STEPNOISE", "Source", "Noise that changes only at a set rate: stepped random levels, or a buzzy, gritty tone when fast.", {"rate", "sync"}, {"out"},
    {{"rate", "RATE", 0.1f, 20000, 8, K::EXP, "Hz"}, {"level", "LEVEL", 0, 1, 0.8f, K::LIN, ""}},
    []() -> Module* { return new StepNoise_; }});

// ---- PARTICLE: a cloud of tiny resonant grains ------------------------------------------------
struct Particle_ : Module {
  daisysp::Particle pt_;
  void init() override { pt_.Init(RATE); }
  void process() override {
    pt_.SetResonance(real(2));
    pt_.SetDensity(real(3));
    pt_.SetGain(real(4));
    pt_.SetSpread(real(5));
    pt_.SetRandomFreq(real(6));
    for (int s = 0; s < BLOCK; ++s) {
      pt_.SetFreq(hz_at(in[0][s], real(1), 20.0f, 12000.0f) * (real(0) / 1000.0f));
      o(0)[s] = pt_.Process();
    }
  }
};
static Registrar r_particle({"particle", "PARTICLE", "Source", "A shower of tiny pings: dripping, sparkling, rattling, from a few to a swarm.", {"pitch"}, {"out"},
    {{"freq", "FREQ", 100, 4000, 1000, K::EXP, "Hz"}, {"tune", "TUNE", -24, 24, 0, K::LIN, "st"},
     {"res", "RESONANCE", 0, 1, 0.6f, K::LIN, ""}, {"density", "DENSITY", 0, 1, 0.4f, K::LIN, ""},
     {"gain", "GAIN", 0, 1, 0.5f, K::LIN, ""}, {"spread", "SPREAD", 0, 1, 0.5f, K::LIN, ""}, {"scatter", "SCATTER", 2, 4000, 1000, K::EXP, "Hz"}},
    []() -> Module* { return new Particle_; }});

// ---- GRAINLET: a grain oscillator -------------------------------------------------------------
struct Grainlet_ : Module {
  daisysp::GrainletOscillator gr_;
  void init() override { gr_.Init(RATE); }
  void process() override {
    gr_.SetShape(real(1));
    gr_.SetBleed(real(2));
    for (int s = 0; s < BLOCK; ++s) {
      gr_.SetFreq(hz_at(in[0][s], real(3), 20.0f, 6000.0f));
      gr_.SetFormantFreq(clampf(real(0) * std::exp2(in[1][s]), 50.0f, 12000.0f));
      o(0)[s] = gr_.Process() * 0.8f;
    }
  }
};
static Registrar r_grainlet({"grainlet", "GRAINLET", "Source", "A pitched, formant oscillator made of sine grains: vocal, plucky and smeared.", {"pitch", "formant"}, {"out"},
    {{"formant", "FORMANT", 100, 5000, 1000, K::EXP, "Hz"}, {"shape", "SHAPE", 0, 1, 0.5f, K::LIN, ""},
     {"bleed", "BLEED", 0, 1, 0.3f, K::LIN, ""}, {"tune", "TUNE", -24, 24, 0, K::LIN, "st"}},
    []() -> Module* { return new Grainlet_; }});

// ---- FRACTAL: coloured noise ------------------------------------------------------------------
struct Fractal_ : Module {
  daisysp::FractalRandomGenerator<daisysp::ClockedNoise, 5> fr_;
  void init() override { fr_.Init(RATE); }
  void process() override {
    fr_.SetColor(real(1));
    for (int s = 0; s < BLOCK; ++s) {
      fr_.SetFreq(clampf(real(0) * std::exp2(in[0][s]), 1.0f, 12000.0f));
      o(0)[s] = clampf(fr_.Process() * real(2), -1.0f, 1.0f);
    }
  }
};
static Registrar r_fractal({"fractal", "FRACTAL", "Source", "Layered noise from slow to fast: wind, rumble and hiss, with a colour that goes dark to bright.", {"rate"}, {"out"},
    {{"freq", "LOWEST", 1, 4000, 60, K::EXP, "Hz"}, {"color", "COLOUR", 0, 1, 0.5f, K::LIN, ""}, {"level", "LEVEL", 0, 2, 0.8f, K::LIN, ""}},
    []() -> Module* { return new Fractal_; }});

// ---- SYNKICK and SYNSNARE: the other drums ----------------------------------------------------
struct SynKick_ : Module {
  daisysp::SyntheticBassDrum bd_;
  Edge2 trig_;
  void init() override { bd_.Init(RATE); }
  void process() override {
    bd_.SetFreq(real(0));
    bd_.SetTone(real(1));
    bd_.SetDecay(real(2));
    bd_.SetDirtiness(real(3));
    bd_.SetFmEnvelopeAmount(real(4));
    bd_.SetFmEnvelopeDecay(real(5));
    bd_.SetAccent(real(6));
    for (int s = 0; s < BLOCK; ++s) o(0)[s] = bd_.Process(trig_(in[0][s])) * 0.8f;
  }
};
static Registrar r_synkick({"synkick", "SYNKICK", "Source", "A kick drum built from a falling sine, a click and a dab of noise: punchy and tuneable.", {"trig"}, {"out"},
    {{"freq", "FREQ", 25, 140, 50, K::LIN, "Hz"}, {"tone", "TONE", 0, 1, 0.5f, K::LIN, ""}, {"decay", "DECAY", 0, 1, 0.5f, K::LIN, ""},
     {"dirt", "DIRT", 0, 1, 0.3f, K::LIN, ""}, {"fmamt", "FM AMT", 0, 1, 0.5f, K::LIN, ""}, {"fmdec", "FM DECAY", 0, 1, 0.5f, K::LIN, ""},
     {"accent", "ACCENT", 0, 1, 0.8f, K::LIN, ""}},
    []() -> Module* { return new SynKick_; }});

struct SynSnare_ : Module {
  daisysp::SyntheticSnareDrum sd_;
  Edge2 trig_;
  void init() override { sd_.Init(RATE); }
  void process() override {
    sd_.SetFreq(real(0) * 1000.0f);
    sd_.SetFmAmount(real(1));
    sd_.SetDecay(real(2));
    sd_.SetSnappy(real(3));
    sd_.SetAccent(real(4));
    for (int s = 0; s < BLOCK; ++s) o(0)[s] = sd_.Process(trig_(in[0][s])) * 0.8f;
  }
};
static Registrar r_synsnare({"synsnare", "SYNSNARE", "Source", "A snare from a pitched shell and a rattle of noise: crack, snap and body.", {"trig"}, {"out"},
    {{"freq", "FREQ", 0.1f, 0.4f, 0.2f, K::LIN, ""}, {"fm", "FM", 0, 1, 0.3f, K::LIN, ""}, {"decay", "DECAY", 0, 1, 0.5f, K::LIN, ""},
     {"snappy", "SNAPPY", 0, 1, 0.6f, K::LIN, ""}, {"accent", "ACCENT", 0, 1, 0.8f, K::LIN, ""}},
    []() -> Module* { return new SynSnare_; }});

// ================================================================== VOICES (physical models)
// ---- MODAL ------------------------------------------------------------------------------------
struct Modal_ : Module {
  daisysp::ModalVoice mv_;
  Edge2 trig_;
  void init() override { mv_.Init(RATE); }
  void process() override {
    mv_.SetStructure(real(1));
    mv_.SetBrightness(real(2));
    mv_.SetDamping(real(3));
    mv_.SetAccent(real(4));
    mv_.SetSustain(choice(5) == 1);
    float tune = real(0);
    for (int s = 0; s < BLOCK; ++s) {
      mv_.SetFreq(hz_at(in[0][s], tune, 20.0f, 6000.0f));
      bool t = trig_(in[1][s]);
      o(0)[s] = mv_.Process(t) * 0.8f;
      o(1)[s] = mv_.GetAux();
    }
  }
};
static Registrar r_modal({"modal", "MODAL", "Voice", "A struck bar, bell or glass: a voice built from a few ringing resonances.", {"pitch", "trig"}, {"out", "aux"},
    {{"tune", "TUNE", -24, 24, 0, K::LIN, "st"}, {"structure", "STRUCTURE", 0, 1, 0.5f, K::LIN, ""}, {"bright", "BRIGHT", 0, 1, 0.5f, K::LIN, ""},
     {"damp", "DAMPING", 0, 1, 0.5f, K::LIN, ""}, {"accent", "ACCENT", 0, 1, 0.8f, K::LIN, ""}, {"hold", "HOLD", 0, 1, 0, K::STEP, "OFF|ON"}},
    []() -> Module* { return new Modal_; }});

// ---- STRING: Karplus-Strong plucked string voice ----------------------------------------------
struct StringV_ : Module {
  daisysp::StringVoice sv_;
  Edge2 trig_;
  void init() override { sv_.Init(RATE); }
  void process() override {
    sv_.SetStructure(real(1));
    sv_.SetBrightness(real(2));
    sv_.SetDamping(real(3));
    sv_.SetAccent(real(4));
    sv_.SetSustain(choice(5) == 1);
    float tune = real(0);
    for (int s = 0; s < BLOCK; ++s) {
      sv_.SetFreq(hz_at(in[0][s], tune, 20.0f, 6000.0f));
      bool t = trig_(in[1][s]);
      o(0)[s] = sv_.Process(t) * 0.8f;
      o(1)[s] = sv_.GetAux();
    }
  }
};
static Registrar r_string({"string", "STRING", "Voice", "A plucked string: guitar, harp and zither, from a trigger and a pitch.", {"pitch", "trig"}, {"out", "aux"},
    {{"tune", "TUNE", -24, 24, 0, K::LIN, "st"}, {"structure", "STRUCTURE", 0, 1, 0.5f, K::LIN, ""}, {"bright", "BRIGHT", 0, 1, 0.5f, K::LIN, ""},
     {"damp", "DAMPING", 0, 1, 0.5f, K::LIN, ""}, {"accent", "ACCENT", 0, 1, 0.8f, K::LIN, ""}, {"hold", "HOLD", 0, 1, 0, K::STEP, "OFF|ON"}},
    []() -> Module* { return new StringV_; }});

// ---- KARPLUS: a string you excite with any sound ----------------------------------------------
struct Karplus_ : Module {
  daisysp::String st_;
  void init() override { st_.Init(RATE); st_.Reset(); }
  void process() override {
    st_.SetNonLinearity(real(1));
    st_.SetBrightness(real(2));
    st_.SetDamping(real(3));
    float tune = real(0), gain = real(4);
    for (int s = 0; s < BLOCK; ++s) {
      st_.SetFreq(hz_at(in[1][s], tune, 20.0f, 4000.0f));
      o(0)[s] = clampf(st_.Process(in[0][s] * gain), -1.0f, 1.0f) * 0.8f;
    }
  }
};
static Registrar r_karplus({"karplus", "KARPLUS", "Voice", "A string with no pluck: feed it a click, a burst of noise or a drum to make it ring at a pitch.", {"in", "pitch"}, {"out"},
    {{"tune", "TUNE", -24, 24, 0, K::LIN, "st"}, {"nonlin", "NONLIN", -1, 1, 0, K::LIN, ""}, {"bright", "BRIGHT", 0, 1, 0.5f, K::LIN, ""},
     {"damp", "DAMPING", 0, 1, 0.5f, K::LIN, ""}, {"drive", "DRIVE", 0, 2, 1, K::LIN, ""}},
    []() -> Module* { return new Karplus_; }});

// ---- RESON: a bank of resonances you excite with any sound ------------------------------------
struct Reson_ : Module {
  daisysp::Resonator rs_;
  void init() override { rs_.Init(0.015f, 24, RATE); }
  void process() override {
    rs_.SetStructure(real(1));
    rs_.SetBrightness(real(2));
    rs_.SetDamping(real(3));
    float tune = real(0), gain = real(4);
    for (int s = 0; s < BLOCK; ++s) {
      rs_.SetFreq(hz_at(in[1][s], tune, 20.0f, 4000.0f));
      o(0)[s] = clampf(rs_.Process(in[0][s] * gain), -1.0f, 1.0f) * 0.8f;
    }
  }
};
static Registrar r_reson({"reson", "RESON", "Voice", "Makes any sound ring like a struck object: a bar, a plate or a tube, at the pitch you give it.", {"in", "pitch"}, {"out"},
    {{"tune", "TUNE", -24, 24, 0, K::LIN, "st"}, {"structure", "STRUCTURE", 0, 1, 0.5f, K::LIN, ""}, {"bright", "BRIGHT", 0, 1, 0.5f, K::LIN, ""},
     {"damp", "DAMPING", 0, 1, 0.5f, K::LIN, ""}, {"drive", "DRIVE", 0, 2, 1, K::LIN, ""}},
    []() -> Module* { return new Reson_; }});

// ---- DRIP: a water drop -----------------------------------------------------------------------
struct Drip_ : Module {
  daisysp::Drip dr_;
  Edge2 trig_;
  void init() override { dr_.Init(RATE, 0.1f); }
  void process() override {
    for (int s = 0; s < BLOCK; ++s) o(0)[s] = dr_.Process(trig_(in[0][s])) * real(0);
  }
};
static Registrar r_drip({"drip", "DRIP", "Voice", "A bubbling water drop for every trigger.", {"trig"}, {"out"},
    {{"level", "LEVEL", 0, 1, 0.8f, K::LIN, ""}},
    []() -> Module* { return new Drip_; }});

}  // namespace rack
