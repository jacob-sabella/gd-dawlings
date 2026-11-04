// rack: the modular room's engine. A graph of modules joined by cables, run in blocks, built on
// upstream DSP that is pinned as submodules (vendor/daisysp, vendor/mutable-eurorack) and never
// copied here. One process, driven by text lines on stdin (see rack.cc), rendering offline to a
// WAV (--render) or live to a pipe of float32 stereo (--live).
//
// Signals are floats in blocks of BLOCK frames at RATE. Audio is -1..1. A pitch is in octaves from
// C4 (0), 1 per octave. A gate is 0 or 1. A control signal is -1..1 (or 0..1, as its module says).
// An input takes any number of cables and sums them; an output feeds any number of inputs. A cable
// from a module that has not run yet this block carries last block's sound, so a patch may loop.
#pragma once
#include <cmath>
#include <cstdint>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace rack {

constexpr int BLOCK = 24;  // Plaits' own block size; every module takes this.
constexpr float RATE = 48000.0f;
constexpr float C4_HZ = 261.6255653f;

struct Knob {
  const char* id;
  const char* label;
  float lo, hi, def;  // def is the real value, not 0..1
  enum Curve { LIN, EXP, STEP } curve;
  const char* names;  // STEP: choices separated by '|'; otherwise the unit ("Hz", "s", "dB", "")
};

struct Module;
struct Spec {
  const char* type;
  const char* title;
  const char* group;  // Source, Control, Voice, Filter, Shape, Time, Mix
  const char* blurb;
  std::vector<const char*> ins, outs;
  std::vector<Knob> knobs;
  Module* (*make)();
};

std::vector<Spec>& registry();
const Spec* find_spec(const std::string& type);
struct Registrar { explicit Registrar(Spec s) { registry().push_back(std::move(s)); } };

// What every module may read of the world.
struct Keys {
  int held[16];
  int n_held = 0;
  float pitch = 0, vel = 0, gate = 0, bend = 0, mod = 0, expr = 0;
  int last_note = 60;
};
struct Transport {
  double bpm = 120.0;
  double beats = 0.0;  // song position in beats when playing
  bool playing = false;
};
struct Ctx {
  Transport tp;
  Keys keys;
  uint64_t block = 0;
  // The room's world sockets (weather, drips, venue, rings, marbles): a level each, and a gate held
  // open for a few samples after a trigger. Set by the host (`world`, `trig`).
  static const int WORLD_N = 12;
  float world[WORLD_N] = {};
  int world_gate[WORLD_N] = {};
  // The room's CV bench: five boxes of two knobs and a slider, each 0..1 (`hand K V`).
  static const int HAND_N = 15;
  float hand[HAND_N] = {};
};

struct Module {
  const Spec* spec = nullptr;
  Ctx* ctx = nullptr;
  std::vector<std::vector<float>> in, out;  // in: already summed; out: this module's results
  std::vector<bool> patched;
  std::vector<float> knob;  // 0..1 as set on the wire
  float peak = 0.0f;        // loudest output this block, for the room's lights
  virtual ~Module() {}
  virtual void init() {}
  virtual void process() = 0;
  // A module that shows a waveform fills `pts` (what it saw, triggered, -1..1) and says so.
  virtual bool scope(std::vector<float>& pts) { return false; }
  // A module that steps through something says which step it is on (-1: none yet).
  virtual int playhead() const { return -1; }
  // A knob's real value.
  float real(int k) const;
  int choice(int k) const { return (int)real(k); }
  float* o(int i = 0) { return out[i].data(); }
  const float* i(int j) const { return in[j].data(); }
  bool has(int j) const { return patched[j]; }
};

struct Cable { std::string from, out, to, in; };

class Rack {
 public:
  Ctx ctx;
  Rack();
  bool add(const std::string& id, const std::string& type);
  void remove(const std::string& id);
  bool connect(const std::string& from, const std::string& to);  // "mod.out" "mod.in"
  void disconnect(const std::string& to);                         // pulls what feeds an input
  void cut(const std::string& from);                              // every cable out of an output
  bool knob(const std::string& path, float v01);
  void clear();
  // Renders n frames (any n), stereo.
  void render(float* l, float* r, int n);
  std::string patch_lines() const;
  const std::map<std::string, std::unique_ptr<Module>>& modules() const { return mods_; }
  void note_on(int pitch, int vel);
  void note_off(int pitch);
  void bend(float v);  // -1..1
  void cc(int k, int v);
 private:
  struct Edge { Module* from; int out; Module* to; int in; };
  std::map<std::string, std::unique_ptr<Module>> mods_;
  std::vector<Cable> cables_;
  std::vector<Edge> edges_;
  std::vector<Module*> order_;
  std::vector<float> outl_, outr_;
  bool dirty_ = true;
  void rebuild();
  void block();
  Module* sink_ = nullptr;
};

// Pitch (octaves from C4) to Hz.
inline float hz_of(float pitch) { return C4_HZ * std::exp2(pitch); }
inline float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

}  // namespace rack
