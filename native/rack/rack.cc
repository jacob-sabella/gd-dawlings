#include "rack.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <set>
#include <sstream>

namespace rack {

std::vector<Spec>& registry() {
  static std::vector<Spec> r;
  return r;
}
const Spec* find_spec(const std::string& type) {
  for (auto& s : registry()) if (type == s.type) return &s;
  return nullptr;
}

float Module::real(int k) const {
  const Knob& d = spec->knobs[k];
  float v = clampf(knob[k], 0.0f, 1.0f);
  switch (d.curve) {
    case Knob::LIN: return d.lo + (d.hi - d.lo) * v;
    case Knob::EXP: return d.lo * std::pow(d.hi / d.lo, v);
    case Knob::STEP: {
      int n = (int)(d.hi - d.lo) + 1;
      int s = (int)(v * n);
      if (s >= n) s = n - 1;
      return d.lo + s;
    }
  }
  return d.def;
}

static float to01(const Knob& d, float real) {
  switch (d.curve) {
    case Knob::LIN: return (real - d.lo) / (d.hi - d.lo);
    case Knob::EXP: return std::log(real / d.lo) / std::log(d.hi / d.lo);
    case Knob::STEP: {
      int n = (int)(d.hi - d.lo) + 1;
      return ((real - d.lo) + 0.5f) / n;
    }
  }
  return 0.0f;
}

Rack::Rack() { outl_.assign(BLOCK, 0); outr_.assign(BLOCK, 0); }

static int index_of(const std::vector<const char*>& names, const std::string& n) {
  for (size_t i = 0; i < names.size(); ++i) if (n == names[i]) return (int)i;
  return -1;
}
static bool split_path(const std::string& p, std::string& mod, std::string& port) {
  size_t d = p.find('.');
  if (d == std::string::npos || d == 0 || d + 1 >= p.size()) return false;
  mod = p.substr(0, d);
  port = p.substr(d + 1);
  return true;
}

bool Rack::add(const std::string& id, const std::string& type) {
  if (mods_.count(id)) return false;
  const Spec* s = find_spec(type);
  if (!s) return false;
  std::unique_ptr<Module> m(s->make());
  m->spec = s;
  m->ctx = &ctx;
  m->in.assign(s->ins.size(), std::vector<float>(BLOCK, 0.0f));
  m->out.assign(s->outs.size(), std::vector<float>(BLOCK, 0.0f));
  m->patched.assign(s->ins.size(), false);
  m->knob.resize(s->knobs.size());
  for (size_t k = 0; k < s->knobs.size(); ++k) m->knob[k] = to01(s->knobs[k], s->knobs[k].def);
  m->init();
  mods_[id] = std::move(m);
  dirty_ = true;
  return true;
}

void Rack::remove(const std::string& id) {
  mods_.erase(id);
  cables_.erase(std::remove_if(cables_.begin(), cables_.end(),
      [&](const Cable& c) { return c.from == id || c.to == id; }), cables_.end());
  dirty_ = true;
}

bool Rack::connect(const std::string& from, const std::string& to) {
  std::string fm, fo, tm, ti;
  if (!split_path(from, fm, fo) || !split_path(to, tm, ti)) return false;
  auto f = mods_.find(fm), t = mods_.find(tm);
  if (f == mods_.end() || t == mods_.end()) return false;
  if (index_of(f->second->spec->outs, fo) < 0 || index_of(t->second->spec->ins, ti) < 0) return false;
  for (auto& c : cables_) if (c.from == fm && c.out == fo && c.to == tm && c.in == ti) return true;
  cables_.push_back({fm, fo, tm, ti});
  dirty_ = true;
  return true;
}

void Rack::disconnect(const std::string& to) {
  std::string tm, ti;
  if (!split_path(to, tm, ti)) return;
  cables_.erase(std::remove_if(cables_.begin(), cables_.end(),
      [&](const Cable& c) { return c.to == tm && c.in == ti; }), cables_.end());
  dirty_ = true;
}

void Rack::cut(const std::string& from) {
  std::string fm, fo;
  if (!split_path(from, fm, fo)) return;
  cables_.erase(std::remove_if(cables_.begin(), cables_.end(),
      [&](const Cable& c) { return c.from == fm && c.out == fo; }), cables_.end());
  dirty_ = true;
}

bool Rack::knob(const std::string& path, float v) {
  std::string mm, kk;
  if (!split_path(path, mm, kk)) return false;
  auto m = mods_.find(mm);
  if (m == mods_.end()) return false;
  int k = -1;
  for (size_t i = 0; i < m->second->spec->knobs.size(); ++i)
    if (kk == m->second->spec->knobs[i].id) k = (int)i;
  if (k < 0) return false;
  m->second->knob[k] = clampf(v, 0.0f, 1.0f);
  return true;
}

void Rack::clear() { cables_.clear(); mods_.clear(); order_.clear(); edges_.clear(); sink_ = nullptr; dirty_ = true; }

// Edges, then an order that runs a module after what feeds it, ignoring cables that close a loop
// (those carry last block), and only the modules that reach OUT.
void Rack::rebuild() {
  edges_.clear();
  for (auto& c : cables_) {
    Module* f = mods_[c.from].get();
    Module* t = mods_[c.to].get();
    edges_.push_back({f, index_of(f->spec->outs, c.out), t, index_of(t->spec->ins, c.in)});
  }
  for (auto& kv : mods_) {
    std::fill(kv.second->patched.begin(), kv.second->patched.end(), false);
    for (auto& v : kv.second->in) std::fill(v.begin(), v.end(), 0.0f);
  }
  for (auto& e : edges_) e.to->patched[e.in] = true;
  sink_ = nullptr;
  for (auto& kv : mods_) if (std::string(kv.second->spec->type) == "out") sink_ = kv.second.get();
  // Which modules reach the sink.
  std::set<Module*> live;
  std::function<void(Module*)> reach = [&](Module* m) {
    if (!live.insert(m).second) return;
    for (auto& e : edges_) if (e.to == m) reach(e.from);
  };
  if (sink_) reach(sink_);
  // A screen (SCOPE, SPECTRUM, VECTOR, METER, PLASMA) watches whatever feeds it, heard or not.
  for (auto& kv : mods_) {
    const std::string ty = kv.second->spec->type;
    if (ty == "scope" || ty == "spectrum" || ty == "vector" || ty == "meter" || ty == "plasma") reach(kv.second.get());
  }
  order_.clear();
  std::set<Module*> done, onstack;
  std::function<void(Module*)> visit = [&](Module* m) {
    if (done.count(m) || onstack.count(m)) return;
    onstack.insert(m);
    for (auto& e : edges_) if (e.to == m && live.count(e.from)) visit(e.from);
    onstack.erase(m);
    done.insert(m);
    order_.push_back(m);
  };
  for (auto& kv : mods_) if (live.count(kv.second.get())) visit(kv.second.get());
  // Modules that make sound for nobody still get their gates and keys read, so they are kept out.
  dirty_ = false;
}

void Rack::block() {
  if (dirty_) rebuild();
  for (Module* m : order_) {
    for (auto& v : m->in) std::fill(v.begin(), v.end(), 0.0f);
  }
  for (Module* m : order_) {
    for (auto& e : edges_) {
      if (e.to != m) continue;
      const std::vector<float>& src = e.from->out[e.out];
      std::vector<float>& dst = m->in[e.in];
      for (int i = 0; i < BLOCK; ++i) dst[i] += src[i];
    }
    m->process();
    float p = 0;
    for (auto& v : m->out) for (float s : v) p = std::max(p, std::fabs(s));
    m->peak = p;
  }
  ctx.block++;
  if (ctx.tp.playing) {
    double per_block = (double)BLOCK / RATE * ctx.tp.bpm / 60.0;
    ctx.tp.beats += per_block;
    // A drift told by `sync` is taken up smoothly, at most 2% of the tempo, so no pulse is cut or doubled.
    double room = per_block * 0.02;
    double take = ctx.tp.slew > room ? room : (ctx.tp.slew < -room ? -room : ctx.tp.slew);
    ctx.tp.beats += take;
    ctx.tp.slew -= take;
  }
}

void Rack::render(float* l, float* r, int n) {
  for (int done = 0; done < n;) {
    block();
    int take = std::min(BLOCK, n - done);
    if (sink_ && !sink_->out.empty()) {
      for (int i = 0; i < take; ++i) {
        l[done + i] = sink_->out[0][i];
        r[done + i] = sink_->out.size() > 1 ? sink_->out[1][i] : sink_->out[0][i];
      }
    } else {
      for (int i = 0; i < take; ++i) l[done + i] = r[done + i] = 0.0f;
    }
    done += take;
  }
}

std::string Rack::patch_lines() const {
  std::ostringstream s;
  for (auto& kv : mods_) s << "module " << kv.first << " " << kv.second->spec->type << "\n";
  for (auto& c : cables_) s << "cable " << c.from << "." << c.out << " " << c.to << "." << c.in << "\n";
  return s.str();
}

void Rack::note_on(int pitch, int vel) {
  Keys& k = ctx.keys;
  for (int i = 0; i < k.n_held; ++i) if (k.held[i] == pitch) {
    for (int j = i; j + 1 < k.n_held; ++j) k.held[j] = k.held[j + 1];
    k.n_held--;
    break;
  }
  if (k.n_held < 16) k.held[k.n_held++] = pitch;
  k.last_note = pitch;
  k.pitch = (pitch - 60) / 12.0f;
  k.vel = clampf(vel / 127.0f, 0, 1);
  k.gate = 1.0f;
}
void Rack::note_off(int pitch) {
  Keys& k = ctx.keys;
  for (int i = 0; i < k.n_held; ++i) if (k.held[i] == pitch) {
    for (int j = i; j + 1 < k.n_held; ++j) k.held[j] = k.held[j + 1];
    k.n_held--;
    break;
  }
  if (k.n_held > 0) {
    k.last_note = k.held[k.n_held - 1];
    k.pitch = (k.last_note - 60) / 12.0f;
  } else {
    k.gate = 0.0f;
  }
}
void Rack::bend(float v) { ctx.keys.bend = clampf(v, -1, 1); }
void Rack::cc(int k, int v) {
  if (k == 1) ctx.keys.mod = v / 127.0f;
  else if (k == 11) ctx.keys.expr = v / 127.0f;
}

bool Rack::text(const std::string& path, const std::string& value) {
  std::string m, k;
  if (!split_path(path, m, k)) return false;
  auto it = mods_.find(m);
  if (it == mods_.end()) return false;
  it->second->text(k, value);
  return true;
}

const std::vector<float>* Rack::tap(const std::string& path) const {
  std::string m, k;
  if (!split_path(path, m, k)) return nullptr;
  auto it = mods_.find(m);
  if (it == mods_.end()) return nullptr;
  int o = index_of(it->second->spec->outs, k);
  return o < 0 ? nullptr : &it->second->out[o];
}

}  // namespace rack
