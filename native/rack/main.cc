// rack: the modular room's engine as a process. Text commands on stdin, one per line:
//   add ID TYPE | remove ID | clear | cable MOD.OUT MOD.IN | uncable MOD.IN | cut MOD.OUT
//   knob MOD.KNOB V01 | bpm N | play BEATS | sync BEATS | stop | note_on P V | note_off P | bend V | cc K V
//   run SECONDS (offline only) | patch (prints the patch) | quit
//   text MOD.KEY WORDS... (words for a module: the voice's lyrics, a line to say, a beat pattern)
// Modes: --describe prints the module catalogue as JSON; --render OUT.wav [SCRIPT] runs the script (a file, or stdin)
// and writes a stereo 16-bit WAV (and a line of peak/rms); --live streams float32 stereo to stdout,
// paced by the reader, while stderr carries "meter ID PEAK ..." lines for the room's lights.
#include <fcntl.h>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <sstream>
#include <thread>
#ifdef _WIN32
#include <io.h>
#include <mutex>
#else
#include <poll.h>
#include <unistd.h>
#endif
#include "rack.h"

using namespace rack;

static std::string esc(const char* s) {
  std::string o;
  for (; *s; ++s) {
    if (*s == '"' || *s == '\\') o += '\\';
    o += *s;
  }
  return o;
}

static int describe() {
  printf("{\"rate\":%d,\"block\":%d,\"modules\":[", (int)RATE, BLOCK);
  bool first = true;
  for (auto& s : registry()) {
    printf("%s{\"type\":\"%s\",\"title\":\"%s\",\"group\":\"%s\",\"blurb\":\"%s\",\"ins\":[", first ? "" : ",", s.type,
           esc(s.title).c_str(), s.group, esc(s.blurb).c_str());
    first = false;
    for (size_t i = 0; i < s.ins.size(); ++i) printf("%s\"%s\"", i ? "," : "", s.ins[i]);
    printf("],\"outs\":[");
    for (size_t i = 0; i < s.outs.size(); ++i) printf("%s\"%s\"", i ? "," : "", s.outs[i]);
    printf("],\"knobs\":[");
    for (size_t i = 0; i < s.knobs.size(); ++i) {
      const Knob& k = s.knobs[i];
      const char* curve = k.curve == Knob::LIN ? "lin" : (k.curve == Knob::EXP ? "exp" : "step");
      printf("%s{\"id\":\"%s\",\"label\":\"%s\",\"lo\":%g,\"hi\":%g,\"def\":%g,\"curve\":\"%s\",\"names\":\"%s\"}",
             i ? "," : "", k.id, esc(k.label).c_str(), k.lo, k.hi, k.def, curve, esc(k.names).c_str());
    }
    printf("]}");
  }
  printf("]}\n");
  return 0;
}

// Applies a module's default knob positions (a freshly added module sounds as its spec says).
static void run_line(Rack& r, const std::string& line, double* run_s) {
  std::istringstream in(line);
  std::string c, a, b;
  in >> c;
  if (c == "add") { in >> a >> b; r.add(a, b); }
  else if (c == "remove") { in >> a; r.remove(a); }
  else if (c == "clear") r.clear();
  else if (c == "cable") { in >> a >> b; r.connect(a, b); }
  else if (c == "uncable") { in >> a; r.disconnect(a); }
  else if (c == "cut") { in >> a; r.cut(a); }
  else if (c == "knob") { float v; in >> a >> v; r.knob(a, v); }
  else if (c == "bpm") { double v; in >> v; r.ctx.tp.bpm = v < 20 ? 20 : v; }
  else if (c == "play") { double v = 0; in >> v; r.ctx.tp.beats = v; r.ctx.tp.playing = true; }
  else if (c == "stop") r.ctx.tp.playing = false;
  // sync BEATS: where the song is now. A small difference is slewed away; a big one (a seek) is jumped.
  else if (c == "sync") {
    double v = 0; in >> v;
    double err = v - r.ctx.tp.beats;
    if (!r.ctx.tp.playing) return;
    if (err > 0.25 || err < -0.25) { r.ctx.tp.beats = v; r.ctx.tp.slew = 0; }
    else r.ctx.tp.slew = err;
  }
  else if (c == "note_on") { int p, v; in >> p >> v; r.note_on(p, v); }
  else if (c == "note_off") { int p; in >> p; r.note_off(p); }
  else if (c == "bend") { float v; in >> v; r.bend(v); }
  else if (c == "cc") { int k, v; in >> k >> v; r.cc(k, v); }
  else if (c == "world") { int k; float v; in >> k >> v; if (k >= 0 && k < Ctx::WORLD_N) r.ctx.world[k] = v < 0 ? 0 : (v > 1 ? 1 : v); }
  else if (c == "hand") { int k; float v; in >> k >> v; if (k >= 0 && k < Ctx::HAND_N) r.ctx.hand[k] = v < 0 ? 0 : (v > 1 ? 1 : v); }
  else if (c == "trig") { int k; in >> k; if (k >= 0 && k < Ctx::WORLD_N) r.ctx.world_gate[k] = (int)(0.048 * RATE); }
  else if (c == "run") { in >> *run_s; }
  else if (c == "text") {
    in >> a;
    std::string rest;
    std::getline(in, rest);
    size_t b0 = rest.find_first_not_of(' ');
    size_t e = rest.find_last_not_of(" \r\n");
    r.text(a, b0 == std::string::npos ? std::string() : rest.substr(b0, e - b0 + 1));
  }
  else if (c == "patch") { printf("%s", r.patch_lines().c_str()); fflush(stdout); }
}

static void put16(FILE* f, int v) { fputc(v & 255, f); fputc((v >> 8) & 255, f); }
static void put32(FILE* f, uint32_t v) { put16(f, v & 0xFFFF); put16(f, v >> 16); }

// RACK_TAP=MOD.OUT renders that one output (mono, as it is, no OUT stage) instead of the speakers;
// RACK_FLOAT=1 writes 32-bit float samples (what a sample-for-sample comparison wants).
static int render(const char* path, const char* script) {
  Rack r;
  r.ctx.offline = true;
  const char* tap = getenv("RACK_TAP");
  bool flt = getenv("RACK_FLOAT") && std::string(getenv("RACK_FLOAT")) == "1";
  FILE* src = script ? fopen(script, "r") : stdin;
  if (!src) return 1;
  std::vector<float> L, R;
  std::string line;
  char buf[4096];
  while (fgets(buf, sizeof buf, src)) {
    line = buf;
    double secs = 0;
    run_line(r, line, &secs);
    if (secs > 0) {
      int n = (int)(secs * RATE);
      size_t at = L.size();
      L.resize(at + n); R.resize(at + n);
      if (!tap) r.render(&L[at], &R[at], n);
      else {
        // one block at a time, so the tap is read after each block
        for (int done = 0; done < n;) {
          int take = std::min(BLOCK, n - done);
          float l[BLOCK], rr[BLOCK];
          r.render(l, rr, take);
          const std::vector<float>* t = r.tap(tap);
          for (int i = 0; i < take; ++i) L[at + done + i] = R[at + done + i] = t ? (*t)[i] : 0.0f;
          done += take;
        }
      }
    }
  }
  FILE* f = fopen(path, "wb");
  if (!f) return 1;
  int ch = tap ? 1 : 2, bytes = flt ? 4 : 2;
  uint32_t data = (uint32_t)L.size() * ch * bytes;
  fwrite("RIFF", 1, 4, f); put32(f, 36 + data); fwrite("WAVEfmt ", 1, 8, f);
  put32(f, 16); put16(f, flt ? 3 : 1); put16(f, ch); put32(f, (uint32_t)RATE); put32(f, (uint32_t)RATE * ch * bytes);
  put16(f, ch * bytes); put16(f, bytes * 8);
  fwrite("data", 1, 4, f); put32(f, data);
  double e = 0; float peak = 0;
  for (size_t i = 0; i < L.size(); ++i) {
    for (int k = 0; k < ch; ++k) {
      float v = k ? R[i] : L[i];
      float c = clampf(v, -1.0f, 1.0f);
      if (flt) fwrite(&v, 4, 1, f);
      else put16(f, (int)(c * 32767.0f));
      peak = std::max(peak, std::fabs(c)); e += c * c;
    }
  }
  fclose(f);
  printf("rendered %zu frames, peak %.3f, rms %.4f\n", L.size(), peak, std::sqrt(e / std::max<size_t>(1, L.size() * 2)));
  return 0;
}

// The live stream's three ends, the one place the platforms differ. Linux reads stdin without blocking
// and waits on stdout with poll; Windows cannot poll a pipe, so a thread of its own reads stdin and the
// loop takes what it has, and stdout is written in binary (no newline translation in the samples).
#ifdef _WIN32
static std::mutex in_lock;
static std::string in_got;
static bool in_closed = false;

static void open_ends() {
  _setmode(0, _O_BINARY);
  _setmode(1, _O_BINARY);
  _setmode(2, _O_BINARY);
  std::thread([]() {
    char buf[4096];
    for (;;) {
      int n = _read(0, buf, sizeof buf);
      std::lock_guard<std::mutex> hold(in_lock);
      if (n <= 0) { in_closed = true; return; }
      in_got.append(buf, n);
    }
  }).detach();
}

// What has arrived on stdin, added to `pending`; false once the room has closed it.
static bool read_commands(std::string& pending) {
  std::lock_guard<std::mutex> hold(in_lock);
  pending += in_got;
  in_got.clear();
  return !in_closed;
}

// All of `p` to stdout; false when the reader has gone.
static bool write_out(const char* p, size_t left) {
  while (left > 0) {
    int w = _write(1, p, (unsigned)left);
    if (w <= 0) return false;
    p += w; left -= w;
  }
  return true;
}

static void write_err(const char* p, size_t n) { if (_write(2, p, (unsigned)n) < 0) {} }
#else
static void open_ends() {
  fcntl(0, F_SETFL, fcntl(0, F_GETFL) | O_NONBLOCK);
#ifdef F_SETPIPE_SZ
  fcntl(1, F_SETPIPE_SZ, 4096);
#endif
}

static bool read_commands(std::string& pending) {
  char buf[4096];
  for (;;) {
    ssize_t n = read(0, buf, sizeof buf);
    if (n > 0) pending.append(buf, n);
    else if (n == 0) return false;  // the room closed
    else return true;
  }
}

static bool write_out(const char* p, size_t left) {
  while (left > 0) {
    struct pollfd pf = {1, POLLOUT, 0};
    poll(&pf, 1, 50);
    ssize_t w = write(1, p, left);
    if (w > 0) { p += w; left -= w; }
    else if (w < 0 && errno != EAGAIN && errno != EINTR) return false;
  }
  return true;
}

static void write_err(const char* p, size_t n) { if (write(2, p, n) < 0) {} }
#endif

static int live(int chunk) {
  Rack r;
  open_ends();
  std::string pending;
  std::vector<float> L(chunk), R(chunk), inter(chunk * 2);
  int tick = 0;
  // Paced by the clock, not by the reader: a chunk is due every chunk/RATE seconds, so the stream is
  // real time however fast the reader drains the pipe. Behind by more than 60 ms (a stall), it
  // starts again from now rather than racing to catch up.
  auto now_ns = []() {
    return (long long)std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
  };
  long long due = now_ns();
  const long long step_ns = (long long)(chunk * 1e9 / RATE);
  for (;;) {
    if (!read_commands(pending)) return 0;  // the room closed
    size_t nl;
    while ((nl = pending.find('\n')) != std::string::npos) {
      std::string line = pending.substr(0, nl);
      pending.erase(0, nl + 1);
      if (line == "quit") return 0;
      double ignore = 0;
      run_line(r, line, &ignore);
    }
    r.render(L.data(), R.data(), chunk);
    for (int i = 0; i < chunk; ++i) { inter[2 * i] = L[i]; inter[2 * i + 1] = R[i]; }
    if (!write_out((const char*)inter.data(), inter.size() * sizeof(float))) return 0;
    due += step_ns;
    long long t = now_ns();
    if (due < t - 60000000LL) due = t;
    else if (due > t) std::this_thread::sleep_for(std::chrono::nanoseconds(due - t));
    if (++tick % 8 == 0) {
      std::string m = "meter";
      char t[64];
      for (auto& kv : r.modules()) { snprintf(t, sizeof t, " %s %.3f", kv.first.c_str(), kv.second->peak); m += t; }
      snprintf(t, sizeof t, " @beat %.3f\n", r.ctx.tp.beats);
      m += t;
      write_err(m.data(), m.size());
    }
    if (tick % 3 == 0) {
      std::string heads;
      for (auto& kv : r.modules()) {
        int h = kv.second->playhead();
        if (h >= 0) heads += "step " + kv.first + " " + std::to_string(h) + "\n";
      }
      if (!heads.empty()) write_err(heads.data(), heads.size());
      std::vector<float> pts(96);
      std::string m;
      char t[16];
      for (auto& kv : r.modules()) {
        if (!kv.second->scope(pts)) continue;
        m += "scope " + kv.first;
        for (float v : pts) { snprintf(t, sizeof t, " %.2f", v); m += t; }
        m += "\n";
      }
      if (!m.empty()) write_err(m.data(), m.size());
      // modules with more to say (the voice's insides), a line per write so no line is torn
      std::string rep;
      for (auto& kv : r.modules()) {
        rep.clear();
        if (!kv.second->report(kv.first, rep)) continue;
        size_t at = 0;
        while (at < rep.size()) {
          size_t nl = rep.find('\n', at);
          if (nl == std::string::npos) nl = rep.size() - 1;
          write_err(rep.data() + at, nl + 1 - at);
          at = nl + 1;
        }
      }
    }
  }
}

#ifdef _WIN32
int aw_describe();  // PE has no undefined weak symbols: a Windows build always has the Airwindows module
#else
int aw_describe() __attribute__((weak));  // present when the Airwindows module is built in
#endif

int main(int argc, char** argv) {
  if (argc > 1 && std::string(argv[1]) == "--describe-airwindows" && aw_describe) return aw_describe();
  if (argc > 1 && std::string(argv[1]) == "--describe") return describe();
  if (argc > 2 && std::string(argv[1]) == "--render") return render(argv[2], argc > 3 ? argv[3] : nullptr);
  if (argc > 1 && std::string(argv[1]) == "--live") return live(argc > 2 ? atoi(argv[2]) : 240);
  fprintf(stderr, "usage: rack --describe | --describe-airwindows | --render OUT.wav < script | --live [frames]\n");
  return 2;
}
