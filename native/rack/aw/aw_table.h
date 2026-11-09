// The Airwindows plugins the engine was built with (the table is generated: tools/airwindows_gen.py).
#pragma once
#include "audioeffectx.h"
struct AwEntry {
  const char* name;
  AudioEffect* (*make)();
};
extern const AwEntry aw_entries[];
extern const int aw_count;
