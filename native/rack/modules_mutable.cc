// The rack's modules built on Mutable Instruments' STM32 firmware (MIT), pinned as the submodule
// vendor/mutable-eurorack and compiled from there, never copied: Plaits (macro oscillator), Rings
// (resonator) and the Clouds reverb.
#include "rack.h"
#include <algorithm>
#include "plaits/dsp/voice.h"
#include "rings/dsp/part.h"
#include "clouds/dsp/frame.h"
#include "clouds/dsp/granular_processor.h"
#include "clouds/dsp/fx/reverb.h"
#include "stmlib/utils/buffer_allocator.h"

namespace rack {
using K = Knob;

struct Edge2 {
  bool high = false;
  bool operator()(float v) { bool was = high; high = high ? v > 0.2f : v > 0.5f; return high && !was; }
};

// ---- PLAITS ------------------------------------------------------------------------------------
struct Plaits_ : Module {
  plaits::Voice voice_;
  char* memory_ = nullptr;
  // The voice keeps a pointer to its allocator (to re-init an engine when it changes): it must live as long.
  stmlib::BufferAllocator alloc_;
  // Zeroed: the engines expect the .bss they have on hardware.
  Plaits_() { memory_ = new char[256 * 1024](); }
  ~Plaits_() { delete[] memory_; }
  void init() override {
    alloc_.Init(memory_, 256 * 1024);
    voice_.Init(&alloc_);
  }
  void process() override {
    plaits::Patch p = {};
    p.note = 60.0f + (real(1) + real(2) / 100.0f);
    p.harmonics = real(3);
    p.timbre = real(4);
    p.morph = real(5);
    p.engine = (int)real(0);  // an index over the voice's 24 engines
    p.decay = real(6);
    p.lpg_colour = real(7);
    p.frequency_modulation_amount = real(8);
    p.timbre_modulation_amount = real(9);
    p.morph_modulation_amount = real(10);
    plaits::Modulations m = {};
    // The pitch input is in octaves from C4; the voice takes it as an offset from patch.note.
    m.note = in[0][0] * 12.0f;
    m.engine = 0;
    m.frequency = in[1][0] * 6.0f;
    m.timbre = in[2][0];
    m.morph = in[3][0];
    m.trigger = in[4][0] > 0.5f ? 1.0f : 0.0f;
    m.level = in[5][0];
    m.frequency_patched = has(1);
    m.timbre_patched = has(2);
    m.morph_patched = has(3);
    m.trigger_patched = has(4);
    m.level_patched = has(5);
    // The voice renders plaits::kBlockSize frames at a time (12), the rack BLOCK (24): so twice a block.
    static_assert(BLOCK % plaits::kBlockSize == 0, "the rack's block is whole voice blocks");
    plaits::Voice::Frame f[plaits::kBlockSize];
    for (int at = 0; at < BLOCK; at += plaits::kBlockSize) {
      voice_.Render(p, m, f, plaits::kBlockSize);
      for (int s = 0; s < (int)plaits::kBlockSize; ++s) {
        o(0)[at + s] = f[s].out / 32768.0f;
        o(1)[at + s] = f[s].aux / 32768.0f;
      }
    }
  }
};
static Registrar r_plaits({"plaits", "PLAITS", "Voice",
    "Mutable Instruments' macro oscillator: 24 engines from virtual analogue to modal, granular, drums and speech.",
    {"pitch", "fm", "timbre", "morph", "trig", "level"}, {"out", "aux"},
    {{"engine", "ENGINE", 0, 23, 8, K::STEP,
      "VA+VCF|PHASE DIST|SIX-OP A|SIX-OP B|SIX-OP C|TERRAIN|STRING MACH|CHIPTUNE|VA|WAVESHAPE|FM|GRAIN|ADDITIVE|WAVETABLE|CHORD|SPEECH|SWARM|NOISE|PARTICLE|STRING|MODAL|KICK|SNARE|HAT"},
     {"note", "NOTE", -24, 24, 0, K::LIN, "st"}, {"fine", "FINE", -100, 100, 0, K::LIN, "ct"},
     {"harm", "HARMONICS", 0, 1, 0.5f, K::LIN, ""}, {"timbre", "TIMBRE", 0, 1, 0.5f, K::LIN, ""},
     {"morph", "MORPH", 0, 1, 0.5f, K::LIN, ""}, {"decay", "DECAY", 0, 1, 0.5f, K::LIN, ""},
     {"lpg", "LPG", 0, 1, 0.5f, K::LIN, ""}, {"fma", "FM AMT", -1, 1, 0, K::LIN, ""},
     {"tma", "TIMB AMT", -1, 1, 0, K::LIN, ""}, {"mma", "MORPH AMT", -1, 1, 0, K::LIN, ""}},
    []() -> Module* { return new Plaits_; }});

// ---- RINGS -------------------------------------------------------------------------------------
struct Rings_ : Module {
  rings::Part part_;
  uint16_t reverb_[32768];
  Edge2 strum_;
  bool primed_ = false;
  void init() override {
    std::memset(reverb_, 0, sizeof(reverb_));
    part_.Init(reverb_);
    part_.set_polyphony(2);
  }
  void process() override {
    part_.set_model((rings::ResonatorModel)(int)real(0));
    part_.set_polyphony(1 << (int)real(1));
    rings::Patch p;
    p.structure = real(2);
    p.brightness = real(3);
    p.damping = real(4);
    p.position = real(5);
    rings::PerformanceState st = {};
    st.internal_exciter = !has(0);
    st.internal_strum = false;
    st.internal_note = false;
    st.tonic = 12.0f;
    st.note = 12.0f * (has(1) ? in[1][0] : 0.0f) + 48.0f + real(6);
    st.fm = 0.0f;
    st.chord = 0;
    st.strum = false;
    for (int s = 0; s < BLOCK; ++s) if (strum_(in[2][s])) st.strum = true;
    float input[BLOCK], out[BLOCK], aux[BLOCK];
    for (int s = 0; s < BLOCK; ++s) input[s] = in[0][s];
    part_.Process(st, p, input, out, aux, BLOCK);
    for (int s = 0; s < BLOCK; ++s) { o(0)[s] = out[s]; o(1)[s] = aux[s]; }
  }
};
static Registrar r_rings({"rings", "RINGS", "Voice",
    "Mutable Instruments' resonator: strike it with a trigger and hear modal bodies, strings and bells.",
    {"in", "pitch", "strum"}, {"odd", "even"},
    {{"model", "MODEL", 0, 5, 0, K::STEP, "MODAL|SYMPATH|STRING|FM|SYMP-Q|STR+REV"},
     {"poly", "VOICES", 0, 2, 0, K::STEP, "1|2|4"},
     {"structure", "STRUCTURE", 0, 1, 0.4f, K::LIN, ""}, {"bright", "BRIGHT", 0, 1, 0.6f, K::LIN, ""},
     {"damping", "DAMPING", 0, 1, 0.6f, K::LIN, ""}, {"position", "POSITION", 0, 1, 0.4f, K::LIN, ""},
     {"note", "NOTE", -12, 36, 0, K::LIN, "st"}},
    []() -> Module* { return new Rings_; }});

// ---- REVERB (Clouds') -------------------------------------------------------------------------
struct Reverb_ : Module {
  clouds::Reverb rv_;
  uint16_t buf_[32768];
  void init() override { std::memset(buf_, 0, sizeof(buf_)); rv_.Init(buf_); }
  void process() override {
    rv_.set_amount(real(3));
    rv_.set_diffusion(real(2));
    rv_.set_time(real(0));
    rv_.set_input_gain(0.2f);
    rv_.set_lp(real(1));
    clouds::FloatFrame f[BLOCK];
    for (int s = 0; s < BLOCK; ++s) { f[s].l = in[0][s]; f[s].r = has(1) ? in[1][s] : in[0][s]; }
    rv_.Process(f, BLOCK);
    for (int s = 0; s < BLOCK; ++s) { o(0)[s] = f[s].l; o(1)[s] = f[s].r; }
  }
};
static Registrar r_reverb({"reverb", "REVERB", "Time",
    "A lush plate-like reverb from Mutable Instruments' Clouds.", {"l", "r"}, {"l", "r"},
    {{"time", "TIME", 0, 1, 0.6f, K::LIN, ""}, {"damp", "DAMP", 0, 1, 0.7f, K::LIN, ""},
     {"diff", "DIFFUSE", 0, 1, 0.7f, K::LIN, ""}, {"mix", "MIX", 0, 1, 0.35f, K::LIN, ""}},
    []() -> Module* { return new Reverb_; }});

// ---- CLOUDS (granular) ---------------------------------------------------------------------------
// The granular processor from the same firmware: the input is recorded into a buffer and played back as a
// cloud of grains, with a reverb and feedback after.
struct Clouds_ : Module {
  clouds::GranularProcessor proc_;
  uint8_t* large_ = nullptr;
  uint8_t* small_ = nullptr;
  static const size_t kLarge = 118784, kSmall = 65536 - 128;
  Clouds_() { large_ = new uint8_t[kLarge](); small_ = new uint8_t[kSmall](); }
  ~Clouds_() { delete[] large_; delete[] small_; }
  void init() override {
    proc_.Init(large_, kLarge, small_, kSmall);
    proc_.set_playback_mode(clouds::PLAYBACK_MODE_GRANULAR);
    proc_.set_quality(0);
    proc_.set_silence(false);
    proc_.set_bypass(false);
  }
  void process() override {
    clouds::Parameters* p = proc_.mutable_parameters();
    p->position = real(0);
    p->size = real(1);
    p->pitch = real(2);
    p->density = real(3);
    p->texture = real(4);
    p->dry_wet = real(5);
    p->stereo_spread = real(6);
    p->feedback = real(7);
    p->reverb = real(8);
    p->freeze = choice(9) == 1 || in[2][0] > 0.5f;
    p->trigger = false;
    p->gate = false;
    p->granular.overlap = 0.5f;
    p->granular.window_shape = 0.5f;
    p->granular.stereo_spread = false;
    p->granular.use_deterministic_seed = false;
    proc_.Prepare();
    clouds::ShortFrame inp[BLOCK], outp[BLOCK];
    for (int s = 0; s < BLOCK; ++s) {
      float l = in[0][s], r = has(1) ? in[1][s] : in[0][s];
      inp[s].l = (short)(std::max(-1.0f, std::min(1.0f, l)) * 32760.0f);
      inp[s].r = (short)(std::max(-1.0f, std::min(1.0f, r)) * 32760.0f);
    }
    proc_.Process(inp, outp, BLOCK);
    for (int s = 0; s < BLOCK; ++s) { o(0)[s] = outp[s].l / 32768.0f; o(1)[s] = outp[s].r / 32768.0f; }
  }
};
static Registrar r_clouds({"clouds", "CLOUDS", "Time",
    "Mutable Instruments' granular processor: listens to what comes in and plays it back as a cloud of grains.",
    {"l", "r", "freeze"}, {"l", "r"},
    {{"position", "POSITION", 0, 1, 0.5f, K::LIN, ""}, {"size", "SIZE", 0, 1, 0.5f, K::LIN, ""},
     {"pitch", "PITCH", -24, 24, 0, K::LIN, "st"}, {"density", "DENSITY", 0, 1, 0.8f, K::LIN, ""},
     {"texture", "TEXTURE", 0, 1, 0.5f, K::LIN, ""}, {"mix", "MIX", 0, 1, 0.5f, K::LIN, ""},
     {"spread", "SPREAD", 0, 1, 0.5f, K::LIN, ""}, {"feedback", "FEEDBACK", 0, 1, 0, K::LIN, ""},
     {"reverb", "REVERB", 0, 1, 0.2f, K::LIN, ""}, {"freeze", "FREEZE", 0, 1, 0, K::STEP, "OFF|ON"}},
    []() -> Module* { return new Clouds_; }});

}  // namespace rack
