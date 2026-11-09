// The rack's BRAIDS module: Mutable Instruments' braids firmware (MIT), pinned as vendor/mutable-eurorack and
// compiled from there, never copied. One of the second batch of Mutable modules (the first is modules_mutable.cc);
// its source list is native/rack/libs/braids.txt. The rack runs at 48 kHz: see docs/rack.md for how a firmware tuned
// for another rate is corrected.
#include "rack.h"
#include <algorithm>
#include "braids/macro_oscillator.h"

namespace rack {
using K = Knob;
static inline short to_short(float v) { return (short)(std::max(-1.0f, std::min(1.0f, v)) * 32760.0f); }

// ---- BRAIDS ------------------------------------------------------------------------------------
// The macro oscillator that came before Plaits: 47 shapes from analogue-style saws to digital filters, vowels,
// FM, plucks, drums, wavetables and noise, with two parameters (timbre, colour) that mean something per shape.
struct Braids_ : Module {
  braids::MacroOscillator osc_;
  bool trig_high_ = false;
  void init() override { osc_.Init(); }
  void process() override {
    osc_.set_shape((braids::MacroOscillatorShape)(int)real(0));
    int16_t t = (int16_t)(clampf(real(1) + in[2][0], 0.0f, 1.0f) * 32767.0f);
    int16_t c = (int16_t)(clampf(real(2) + in[3][0], 0.0f, 1.0f) * 32767.0f);
    osc_.set_parameters(t, c);
    // 128 steps to a semitone, MIDI 60 at C4; the firmware is tuned for 96 kHz, so an octave is added at 48.
    float note = 60.0f + 12.0f * in[0][0] + real(3) + 12.0f + 0.01f * real(4);
    int32_t pitch = (int32_t)(clampf(note, 0.0f, 127.0f) * 128.0f);
    osc_.set_pitch((int16_t)pitch);
    bool high = in[1][0] > 0.5f;
    if (high && !trig_high_) osc_.Strike();
    trig_high_ = high;
    uint8_t sync[BLOCK] = {};
    int16_t buf[BLOCK];
    osc_.Render(sync, buf, BLOCK);
    for (int s = 0; s < BLOCK; ++s) { o(0)[s] = buf[s] / 32768.0f; }
  }
};
static Registrar r_braids({"braids", "BRAIDS", "Voice",
    "Mutable Instruments' macro oscillator: 47 digital and analogue-style shapes, two parameters, a pitch and a trigger.",
    {"pitch", "trig", "timbre", "color"}, {"out"},
    {{"shape", "SHAPE", 0, 46, 0, K::STEP,
      "CSAW|MORPH|SAW SQR|SIN TRI|BUZZ|SQR SUB|SAW SUB|SQR SYNC|SAW SYNC|TRI SAW|TRI SQR|TRI TRI|TRI SIN|TRI RING|SWARM|COMB|TOY|FLT LP|FLT PK|FLT BP|FLT HP|VOSIM|VOWEL|FOF|HARM|FM|FBK FM|CHAOS FM|PLUCK|BOW|BLOWN|FLUTE|BELL|DRUM|KICK|CYMBAL|SNARE|WTABLES|WMAP|WLINE|WPARA|F-NOISE|TWIN|CLK NOISE|GRANULAR|PARTICLE|DIGMOD"},
     {"timbre", "TIMBRE", 0, 1, 0.5f, K::LIN, ""}, {"color", "COLOR", 0, 1, 0.5f, K::LIN, ""},
     {"note", "NOTE", -24, 24, 0, K::LIN, "st"}, {"fine", "FINE", -100, 100, 0, K::LIN, "ct"}},
    []() -> Module* { return new Braids_; }});


}  // namespace rack
