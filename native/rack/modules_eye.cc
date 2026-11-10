// The rack's eye candy: modules that make nothing of their own, only a picture of what is patched in, drawn on a
// screen on the wall (the same path as SCOPE: the engine hands the room a row of numbers, `Module::scope`, every few
// ticks, and the wall's ScopeScreen draws it in the module's mode). Each passes its input through, so one can sit
// in the middle of any cable.
#include "rack.h"
#include <algorithm>
#include <complex>

namespace rack {
using K = Knob;

namespace {
// A radix-2 FFT in place, n a power of two.
void fft(std::vector<std::complex<float>>& a) {
  const size_t n = a.size();
  for (size_t i = 1, j = 0; i < n; ++i) {
    size_t bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) std::swap(a[i], a[j]);
  }
  for (size_t len = 2; len <= n; len <<= 1) {
    float ang = -6.2831853f / (float)len;
    std::complex<float> wl(std::cos(ang), std::sin(ang));
    for (size_t i = 0; i < n; i += len) {
      std::complex<float> w(1, 0);
      for (size_t j = 0; j < len / 2; ++j) {
        std::complex<float> u = a[i + j], v = a[i + j + len / 2] * w;
        a[i + j] = u + v;
        a[i + j + len / 2] = u - v;
        w *= wl;
      }
    }
  }
}
}  // namespace

// ---- SPECTRUM: bars, low to high -----------------------------------------------------------------
struct Spectrum_ : Module {
  static const int N = 2048;
  std::vector<float> h_;
  int head_ = 0;
  std::vector<float> bars_;
  void init() override { h_.assign(N, 0.0f); bars_.assign(96, 0.0f); }
  void process() override {
    for (int s = 0; s < BLOCK; ++s) {
      o(0)[s] = in[0][s];
      h_[head_] = in[0][s];
      head_ = (head_ + 1) % N;
    }
  }
  bool scope(std::vector<float>& pts) override {
    std::vector<std::complex<float>> a(N);
    for (int i = 0; i < N; ++i) {
      float w = 0.5f - 0.5f * std::cos(6.2831853f * i / (N - 1));
      a[i] = h_[(head_ + i) % N] * w;
    }
    fft(a);
    const int B = (int)pts.size();
    const float range = real(0), decay = real(1);
    const float lo = 30.0f, hi = 16000.0f;
    for (int b = 0; b < B; ++b) {
      float f0 = lo * std::pow(hi / lo, (float)b / B), f1 = lo * std::pow(hi / lo, (float)(b + 1) / B);
      int k0 = std::max(1, (int)(f0 * N / RATE)), k1 = std::max(k0, (int)(f1 * N / RATE));
      float m = 0.0f;
      for (int k = k0; k <= k1 && k < N / 2; ++k) m = std::max(m, std::abs(a[k]));
      float db = 20.0f * std::log10(m / (N * 0.25f) + 1e-9f);
      float v = clampf(1.0f + db / range, 0.0f, 1.0f);
      bars_[b] = std::max(v, bars_[b] * decay);
      pts[b] = bars_[b];
    }
    return true;
  }
};
static Registrar r_spectrum({"spectrum", "SPECTRUM", "Mix", "A screen of glowing bars, low notes on the left to high on the right: what is in a sound, as it plays.", {"in"}, {"out"},
    {{"range", "RANGE", 30, 96, 60, K::LIN, "dB"}, {"fall", "FALL", 0.5f, 0.98f, 0.85f, K::LIN, ""}},
    []() -> Module* { return new Spectrum_; }});

// ---- VECTOR: a vectorscope (one signal drawn against another) -----------------------------------
struct Vector_ : Module {
  static const int N = 4096;
  std::vector<float> hx_, hy_;
  int head_ = 0;
  void init() override { hx_.assign(N, 0.0f); hy_.assign(N, 0.0f); }
  void process() override {
    bool y = has(1);
    for (int s = 0; s < BLOCK; ++s) {
      float x = in[0][s], yy = y ? in[1][s] : x;
      o(0)[s] = x;
      o(1)[s] = yy;
      hx_[head_] = x;
      hy_[head_] = yy;
      head_ = (head_ + 1) % N;
    }
  }
  bool scope(std::vector<float>& pts) override {
    const int P = (int)pts.size() / 2;
    const bool turn = choice(1) == 1;
    const float g = real(0);
    const int span = std::max(P, (int)(0.02f * RATE));
    for (int i = 0; i < P; ++i) {
      int back = (int)((long long)(P - 1 - i) * span / P);
      int idx = ((head_ - 1 - back) % N + N) % N;
      float x = hx_[idx], y = hy_[idx];
      if (turn) { float m = (x + y) * 0.7071f, s = (x - y) * 0.7071f; x = s; y = m; }
      pts[i * 2] = clampf(x * g, -1.0f, 1.0f);
      pts[i * 2 + 1] = clampf(y * g, -1.0f, 1.0f);
    }
    return true;
  }
};
static Registrar r_vector({"vector", "VECTOR", "Mix", "Draws one signal against another: a mono sound is a line, a wide stereo sound a cloud, two sines a loop.", {"x", "y"}, {"x", "y"},
    {{"gain", "GAIN", 0.25f, 4, 1, K::EXP, ""}, {"turn", "VIEW", 0, 1, 1, K::STEP, "X-Y|L-R"}},
    []() -> Module* { return new Vector_; }});

// ---- METER: two bars with peak ticks -------------------------------------------------------------
struct Meter_ : Module {
  float rms_[2] = {}, pk_[2] = {}, hold_[2] = {}, holdt_[2] = {};
  void process() override {
    float sq[2] = {}, mx[2] = {};
    for (int s = 0; s < BLOCK; ++s) {
      for (int c = 0; c < 2; ++c) {
        float v = in[c][s];
        o(c)[s] = v;
        sq[c] += v * v;
        mx[c] = std::max(mx[c], std::fabs(v));
      }
    }
    for (int c = 0; c < 2; ++c) {
      float r = std::sqrt(sq[c] / BLOCK);
      rms_[c] = r > rms_[c] ? r : rms_[c] + (r - rms_[c]) * 0.04f;
      pk_[c] = mx[c] > pk_[c] ? mx[c] : pk_[c] * 0.995f;
      if (mx[c] >= hold_[c]) { hold_[c] = mx[c]; holdt_[c] = 1.5f; }
      else { holdt_[c] -= (float)BLOCK / RATE; if (holdt_[c] < 0.0f) hold_[c] *= 0.98f; }
    }
  }
  bool scope(std::vector<float>& pts) override {
    const float range = real(0);
    auto lvl = [&](float v) { return clampf(1.0f + 20.0f * std::log10(v + 1e-6f) / range, 0.0f, 1.0f); };
    std::fill(pts.begin(), pts.end(), 0.0f);
    pts[0] = lvl(rms_[0]); pts[1] = lvl(pk_[0]); pts[2] = lvl(hold_[0]);
    pts[3] = lvl(rms_[1]); pts[4] = lvl(pk_[1]); pts[5] = lvl(hold_[1]);
    return true;
  }
};
static Registrar r_meter({"meter", "METER", "Mix", "Two level bars with a peak tick that lingers: how loud, and how close to clipping.", {"l", "r"}, {"l", "r"},
    {{"range", "RANGE", 24, 72, 48, K::LIN, "dB"}},
    []() -> Module* { return new Meter_; }});

// ---- PLASMA: a glowing, flowing picture moved by three signals ----------------------------------
struct Plasma_ : Module {
  float env_[3] = {};
  float t_ = 0.0f;
  void process() override {
    float sq[3] = {};
    for (int s = 0; s < BLOCK; ++s) {
      float sum = 0.0f;
      for (int c = 0; c < 3; ++c) {
        float v = in[c][s];
        sq[c] += v * v;
        sum += v;
      }
      o(0)[s] = sum;
    }
    for (int c = 0; c < 3; ++c) {
      float r = std::sqrt(sq[c] / BLOCK) * 2.0f;
      env_[c] += (r - env_[c]) * (r > env_[c] ? 0.3f : 0.03f);
    }
    t_ += (float)BLOCK / RATE * real(0) * 4.0f;
  }
  bool scope(std::vector<float>& pts) override {
    std::fill(pts.begin(), pts.end(), 0.0f);
    pts[0] = clampf(env_[0], 0.0f, 1.0f);
    pts[1] = clampf(env_[1], 0.0f, 1.0f);
    pts[2] = clampf(env_[2], 0.0f, 1.0f);
    pts[3] = std::fmod(t_, 1000.0f);
    pts[4] = real(1);
    return true;
  }
};
static Registrar r_plasma({"plasma", "PLASMA", "Mix", "A lava lamp for your patch: three signals stir the colours, the glow and the flow of a liquid picture.", {"red", "green", "blue"}, {"out"},
    {{"flow", "FLOW", 0.05f, 4, 0.6f, K::EXP, ""}, {"hue", "HUE", 0, 1, 0.5f, K::LIN, ""}},
    []() -> Module* { return new Plasma_; }});

}  // namespace rack
