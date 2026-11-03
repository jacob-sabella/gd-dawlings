#!/usr/bin/env bash
# Builds native/rack_probe.cc against the pinned Mutable Instruments submodule and renders a Plaits
# note: tools/rack_probe.sh [engine] [note]. Build products stay in build/rack_probe, untracked.
set -euo pipefail
cd "$(dirname "$0")/.."
MI=vendor/mutable-eurorack
[ -f "$MI/stmlib/stmlib.h" ] || { echo "run: git submodule update --init vendor/mutable-eurorack && git -C $MI submodule update --init stmlib"; exit 1; }
OUT=build/rack_probe
mkdir -p "$OUT"
SRC=$(ls $MI/plaits/dsp/*.cc $MI/plaits/dsp/*/*.cc $MI/plaits/resources.cc $MI/stmlib/dsp/*.cc $MI/stmlib/utils/*.cc 2>/dev/null)
c++ -O2 -std=c++14 -DTEST -include cstdio -I"$MI" -o "$OUT/rack_probe" native/rack_probe.cc $SRC
"$OUT/rack_probe" "$OUT/plaits.wav" "${1:-0}" "${2:-60}"
