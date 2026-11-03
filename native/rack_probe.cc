// rack_probe: renders a note of Mutable Instruments' Plaits (the pinned submodule, MIT) to a 16-bit
// mono WAV, to prove the modular room's DSP builds and sounds from upstream's own code.
// Usage: rack_probe OUT.wav [engine 0-15] [midi note]
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include "plaits/dsp/voice.h"
#include "stmlib/utils/buffer_allocator.h"

int main(int argc, char **argv) {
  const char *path = argc > 1 ? argv[1] : "plaits.wav";
  int engine = argc > 2 ? atoi(argv[2]) : 0;
  float note = argc > 3 ? (float)atof(argv[3]) : 60.0f;
  static char memory[256 * 1024];
  stmlib::BufferAllocator allocator(memory, sizeof(memory));
  plaits::Voice voice;
  voice.Init(&allocator);
  plaits::Patch patch = {};
  patch.note = note;
  patch.harmonics = 0.5f;
  patch.timbre = 0.5f;
  patch.morph = 0.5f;
  patch.engine = engine;
  patch.decay = 0.5f;
  patch.lpg_colour = 0.5f;
  plaits::Modulations mod = {};
  const size_t block = plaits::kBlockSize;
  const int frames = 48000 * 2;
  std::vector<int16_t> out;
  plaits::Voice::Frame f[plaits::kBlockSize];
  for (int i = 0; i < frames; i += block) {
    mod.trigger = (i < 24000) ? 1.0f : 0.0f;
    mod.trigger_patched = true;
    voice.Render(patch, mod, f, block);
    for (size_t k = 0; k < block; ++k) out.push_back(f[k].out);
  }
  FILE *fp = fopen(path, "wb");
  uint32_t data = out.size() * 2, rate = 48000, riff = 36 + data, byterate = rate * 2;
  uint16_t fmt = 1, ch = 1, align = 2, bits = 16; uint32_t sixteen = 16;
  fwrite("RIFF", 1, 4, fp); fwrite(&riff, 4, 1, fp); fwrite("WAVEfmt ", 1, 8, fp);
  fwrite(&sixteen, 4, 1, fp); fwrite(&fmt, 2, 1, fp); fwrite(&ch, 2, 1, fp);
  fwrite(&rate, 4, 1, fp); fwrite(&byterate, 4, 1, fp); fwrite(&align, 2, 1, fp);
  fwrite(&bits, 2, 1, fp); fwrite("data", 1, 4, fp); fwrite(&data, 4, 1, fp);
  fwrite(out.data(), 2, out.size(), fp);
  fclose(fp);
  int peak = 0;
  for (auto s : out) peak = std::max(peak, abs((int)s));
  printf("engine %d note %.0f: %zu frames, peak %d of 32767\n", engine, note, out.size(), peak);
  return 0;
}
