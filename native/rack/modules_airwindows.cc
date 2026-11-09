// AIRWINDOWS: Chris Johnson's effects (github.com/airwindows/airwindows, MIT), the whole suite in one module.
//
// One knob chooses the effect and twelve are its parameters (A..L, 0..1 as the plugins have them; the effects
// that have more than twelve, the Console X family, get the first twelve). The plugins are compiled in as they
// are, against a small host stand-in (aw/audioeffectx.h); tools/airwindows_gen.py writes the wrappers and the
// table. `rack --describe-airwindows` lists every effect with its parameters' names and its own starting
// values, which is what the studio reads to label the knobs and to set them when the effect is changed.
#include <cmath>
#include <cstdio>
#include <memory>
#include <string>

#include "aw_table.h"
#include "rack.h"

namespace rack {
namespace {
using K = Knob;
constexpr int NPARAM = 12;

struct Airwindows_ : Module {
  std::unique_ptr<AudioEffectX> fx_;
  int which_ = -1;
  int nparam_ = 0;
  float sent_[NPARAM];
  float inl_[BLOCK], inr_[BLOCK], outl_[BLOCK], outr_[BLOCK];

  void load(int w) {
    which_ = w;
    fx_.reset(static_cast<AudioEffectX*>(aw_entries[w].make()));
    fx_->setSampleRate(RATE);
    nparam_ = fx_->numParams();
    for (int p = 0; p < NPARAM; ++p) sent_[p] = -1.0f;  // none sent yet: every knob is applied
  }
  void process() override {
    int w = choice(0);
    if (w < 0) w = 0;
    if (w >= aw_count) w = aw_count - 1;
    if (w != which_) load(w);
    for (int p = 0; p < NPARAM && p < nparam_; ++p) {
      float v = real(p + 1);
      if (v != sent_[p]) { fx_->setParameter(p, v); sent_[p] = v; }
    }
    bool two = has(1);
    for (int s = 0; s < BLOCK; ++s) { inl_[s] = in[0][s]; inr_[s] = two ? in[1][s] : in[0][s]; }
    float* ins[2] = {inl_, inr_};
    float* outs[2] = {outl_, outr_};
    fx_->processReplacing(ins, outs, BLOCK);
    bool bad = false;
    for (int s = 0; s < BLOCK; ++s) {
      float l = outl_[s], r = outr_[s];
      if (!std::isfinite(l) || !std::isfinite(r)) { bad = true; l = r = 0.0f; }
      o(0)[s] = std::fmax(-8.0f, std::fmin(8.0f, l));
      o(1)[s] = std::fmax(-8.0f, std::fmin(8.0f, r));
    }
    if (bad) load(which_);  // a filter that blew up starts again from silence
  }
};

std::string& effect_names() {
  static std::string s = [] {
    std::string t;
    for (int i = 0; i < aw_count; ++i) { if (i) t += '|'; t += aw_entries[i].name; }
    return t;
  }();
  return s;
}
int default_effect() {
  for (int i = 0; i < aw_count; ++i) if (std::string(aw_entries[i].name) == "Galactic") return i;
  return 0;
}

Spec make_spec() {
  Spec sp{"airwindows", "AIRWINDOWS", "Shape",
          "Chris Johnson's Airwindows effects, all of them: reverbs, saturators, compressors, filters, dithers and "
          "more. Pick one and the knobs become its parameters.",
          {"l", "r"}, {"l", "r"}, {}, []() -> Module* { return new Airwindows_; }};
  sp.knobs.push_back({"effect", "EFFECT", 0, (float)(aw_count - 1), (float)default_effect(), K::STEP,
                      effect_names().c_str()});
  static const char* ids[NPARAM] = {"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"};
  static const char* labels[NPARAM] = {"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"};
  for (int p = 0; p < NPARAM; ++p) sp.knobs.push_back({ids[p], labels[p], 0, 1, 0.5f, K::LIN, ""});
  return sp;
}
Registrar r_airwindows(make_spec());
}  // namespace

std::string esc(const char* s) {
  std::string o;
  for (; *s; ++s) { if (*s == '"' || *s == '\\') o += '\\'; o += *s; }
  return o;
}
}  // namespace rack

// `rack --describe-airwindows`: every effect, its parameters' names and starting values.
int aw_describe() {
  printf("{\"effects\":[");
  for (int i = 0; i < aw_count; ++i) {
    std::unique_ptr<AudioEffectX> fx(static_cast<AudioEffectX*>(aw_entries[i].make()));
    char title[kVstMaxNameLen + 1] = {0};
    if (!fx->getEffectName(title) || !title[0]) snprintf(title, sizeof title, "%s", aw_entries[i].name);
    printf("%s{\"id\":\"%s\",\"title\":\"%s\",\"params\":[", i ? "," : "", aw_entries[i].name, rack::esc(title).c_str());
    for (int p = 0; p < fx->numParams(); ++p) {
      char name[kVstMaxNameLen + 1] = {0};
      fx->getParameterName(p, name);
      printf("%s{\"name\":\"%s\",\"default\":%.4f}", p ? "," : "", rack::esc(name).c_str(), fx->getParameter(p));
    }
    printf("]}");
  }
  printf("]}\n");
  return 0;
}
