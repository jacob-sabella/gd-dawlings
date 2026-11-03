// rack: the modular room's engine as a process. Text commands on stdin, one per line:
//   add ID TYPE | remove ID | clear | cable MOD.OUT MOD.IN | uncable MOD.IN | cut MOD.OUT
//   knob MOD.KNOB V01 | bpm N | play BEATS | stop | note_on P V | note_off P | bend V | cc K V
//   run SECONDS (offline only) | patch (prints the patch) | quit
// Modes: --describe prints the module catalogue as JSON; --render OUT.wav runs the script on stdin
// and writes a stereo 16-bit WAV (and a line of peak/rms); --live streams float32 stereo to stdout,
// paced by the reader, while stderr carries "meter ID PEAK ..." lines for the room's lights.
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <sstream>
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
  else if (c == "note_on") { int p, v; in >> p >> v; r.note_on(p, v); }
  else if (c == "note_off") { int p; in >> p; r.note_off(p); }
  else if (c == "bend") { float v; in >> v; r.bend(v); }
  else if (c == "cc") { int k, v; in >> k >> v; r.cc(k, v); }
  else if (c == "run") { in >> *run_s; }
  else if (c == "patch") { printf("%s", r.patch_lines().c_str()); fflush(stdout); }
}

static void put16(FILE* f, int v) { fputc(v & 255, f); fputc((v >> 8) & 255, f); }
static void put32(FILE* f, uint32_t v) { put16(f, v & 0xFFFF); put16(f, v >> 16); }

static int render(const char* path) {
  Rack r;
  std::vector<float> L, R;
  std::string line;
  char buf[4096];
  while (fgets(buf, sizeof buf, stdin)) {
    line = buf;
    double secs = 0;
    run_line(r, line, &secs);
    if (secs > 0) {
      int n = (int)(secs * RATE);
      size_t at = L.size();
      L.resize(at + n); R.resize(at + n);
      r.render(&L[at], &R[at], n);
    }
  }
  FILE* f = fopen(path, "wb");
  if (!f) return 1;
  uint32_t data = (uint32_t)L.size() * 4;
  fwrite("RIFF", 1, 4, f); put32(f, 36 + data); fwrite("WAVEfmt ", 1, 8, f);
  put32(f, 16); put16(f, 1); put16(f, 2); put32(f, (uint32_t)RATE); put32(f, (uint32_t)RATE * 4); put16(f, 4); put16(f, 16);
  fwrite("data", 1, 4, f); put32(f, data);
  double e = 0; float peak = 0;
  for (size_t i = 0; i < L.size(); ++i) {
    for (float v : {L[i], R[i]}) {
      float c = clampf(v, -1.0f, 1.0f);
      put16(f, (int)(c * 32767.0f));
      peak = std::max(peak, std::fabs(c)); e += c * c;
    }
  }
  fclose(f);
  printf("rendered %zu frames, peak %.3f, rms %.4f\n", L.size(), peak, std::sqrt(e / std::max<size_t>(1, L.size() * 2)));
  return 0;
}

static int live(int chunk) {
  Rack r;
  fcntl(0, F_SETFL, fcntl(0, F_GETFL) | O_NONBLOCK);
#ifdef F_SETPIPE_SZ
  fcntl(1, F_SETPIPE_SZ, 4096);
#endif
  std::string pending;
  std::vector<float> L(chunk), R(chunk), inter(chunk * 2);
  int tick = 0;
  for (;;) {
    char buf[4096];
    for (;;) {
      ssize_t n = read(0, buf, sizeof buf);
      if (n > 0) pending.append(buf, n);
      else if (n == 0) return 0;  // the room closed
      else break;
    }
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
    const char* p = (const char*)inter.data();
    size_t left = inter.size() * sizeof(float);
    while (left > 0) {
      struct pollfd pf = {1, POLLOUT, 0};
      poll(&pf, 1, 50);
      ssize_t w = write(1, p, left);
      if (w > 0) { p += w; left -= w; }
      else if (w < 0 && errno != EAGAIN && errno != EINTR) return 0;
      // Between waits, a command may have arrived.
    }
    if (++tick % 8 == 0) {
      std::string m = "meter";
      char t[64];
      for (auto& kv : r.modules()) { snprintf(t, sizeof t, " %s %.3f", kv.first.c_str(), kv.second->peak); m += t; }
      snprintf(t, sizeof t, " @beat %.3f\n", r.ctx.tp.beats);
      m += t;
      if (write(2, m.data(), m.size()) < 0) {}
    }
  }
}

int main(int argc, char** argv) {
  if (argc > 1 && std::string(argv[1]) == "--describe") return describe();
  if (argc > 2 && std::string(argv[1]) == "--render") return render(argv[2]);
  if (argc > 1 && std::string(argv[1]) == "--live") return live(argc > 2 ? atoi(argv[2]) : 240);
  fprintf(stderr, "usage: rack --describe | --render OUT.wav < script | --live [frames]\n");
  return 2;
}
