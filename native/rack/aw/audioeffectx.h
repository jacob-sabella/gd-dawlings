// A stand-in for the part of the VST2 host interface that Airwindows' plugins are written against.
//
// Airwindows' effects (vendor/airwindows, MIT) are each a class derived from `AudioEffectX` that keeps its
// parameters as 0..1 floats and processes a block in `processReplacing`. They use nothing else of the SDK, so
// this header gives them just that surface, written here (it is not Steinberg's header and carries none of
// its terms), and the rack calls the classes directly. Same approach as the Airwin2Rack port.
#pragma once
#define __audioeffect__ 1

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <algorithm>
#include <cstdint>
#include <set>
#include <string>

typedef int32_t VstInt32;
typedef intptr_t VstIntPtr;
typedef intptr_t (*audioMasterCallback)(void*, VstInt32, VstInt32, VstIntPtr, void*, float);

enum {
  kVstMaxNameLen = 64,
  kVstMaxLabelLen = 64,
  kVstMaxShortLabelLen = 8,
  kVstMaxCategLabelLen = 24,
  kVstMaxFileNameLen = 100,
  kVstMaxParamStrLen = 32,
  kVstMaxProgNameLen = 24,
  kVstMaxEffectNameLen = 32,
  kVstMaxVendorStrLen = 64,
  kVstMaxProductStrLen = 64,
};
enum VstPlugCategory {
  kPlugCategUnknown = 0, kPlugCategEffect, kPlugCategSynth, kPlugCategAnalysis, kPlugCategMastering,
  kPlugCategSpacializer, kPlugCategRoomFx, kPlugSurroundFx, kPlugCategRestoration, kPlugCategOfflineProcess,
  kPlugCategShell, kPlugCategGenerator
};

inline char* vst_strncpy(char* dst, const char* src, size_t n) {
  if (!dst) return dst;
  strncpy(dst, src ? src : "", n);
  dst[n] = 0;  // the SDK's own contract: room for n characters plus the terminator
  return dst;
}

class AudioEffect {
 public:
  virtual ~AudioEffect() {}
};

class AudioEffectX : public AudioEffect {
 public:
  AudioEffectX(audioMasterCallback, VstInt32, VstInt32 nparams) : nparams_(nparams) {}
  virtual ~AudioEffectX() {}

  virtual bool getEffectName(char*) { return false; }
  virtual VstPlugCategory getPlugCategory() { return kPlugCategEffect; }
  virtual bool getProductString(char*) { return false; }
  virtual bool getVendorString(char*) { return false; }
  virtual VstInt32 getVendorVersion() { return 1000; }
  virtual void processReplacing(float**, float**, VstInt32) {}
  virtual void processDoubleReplacing(double**, double**, VstInt32) {}
  virtual void getProgramName(char*) {}
  virtual void setProgramName(char*) {}
  virtual VstInt32 getChunk(void**, bool) { return 0; }
  virtual VstInt32 setChunk(void*, VstInt32, bool) { return 0; }
  virtual float getParameter(VstInt32) { return 0.0f; }
  virtual void setParameter(VstInt32, float) {}
  virtual void getParameterLabel(VstInt32, char* t) { *t = 0; }
  virtual void getParameterName(VstInt32, char* t) { *t = 0; }
  virtual void getParameterDisplay(VstInt32, char* t) { *t = 0; }
  virtual VstInt32 canDo(char*) { return 0; }

  // What the plugins call on their host.
  float getSampleRate() const { return rate_; }
  void setSampleRate(float r) { rate_ = r; }
  void setNumInputs(VstInt32) {}
  void setNumOutputs(VstInt32) {}
  void setUniqueID(VstInt32) {}
  void canProcessReplacing(bool = true) {}
  void canDoubleReplacing(bool = true) {}
  void programsAreChunks(bool = true) {}
  void noTail(bool = true) {}
  void isSynth(bool = true) {}
  void setInitialDelay(VstInt32) {}
  VstInt32 numParams() const { return nparams_; }

  // Text helpers the display functions use.
  static void float2string(float v, char* t, VstInt32 n) { snprintf(t, n > 0 ? n : 8, "%.2f", v); }
  static void dB2string(float v, char* t, VstInt32 n) {
    if (v <= 0.0f) snprintf(t, n > 0 ? n : 8, "-inf");
    else snprintf(t, n > 0 ? n : 8, "%.1f", 20.0 * log10((double)v));
  }
  static void int2string(VstInt32 v, char* t, VstInt32 n) { snprintf(t, n > 0 ? n : 8, "%d", (int)v); }

 private:
  VstInt32 nparams_ = 0;
  float rate_ = 48000.0f;
};
