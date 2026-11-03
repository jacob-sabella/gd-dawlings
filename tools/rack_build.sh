#!/usr/bin/env bash
# Builds the modular room's engine, native/rack, from the pinned submodules (vendor/daisysp,
# vendor/mutable-eurorack) into build/rack/rack. Objects are cached per source file; an unchanged
# one is not rebuilt. Needs a C++14 compiler (c++). Prints the binary's path.
set -euo pipefail
cd "$(dirname "$0")/.."
MI=vendor/mutable-eurorack
DS=vendor/daisysp/Source
[ -f "$MI/stmlib/stmlib.h" ] && [ -d "$DS" ] || { echo "run: git submodule update --init --recursive vendor/daisysp vendor/mutable-eurorack && git -C $MI submodule update --init stmlib" >&2; exit 1; }
OUT=build/rack
mkdir -p "$OUT/obj"
CXX=${CXX:-c++}
FLAGS="-O2 -std=c++14 -DTEST -include cstdio -I$MI -I$DS -I$DS/Utility -Inative/rack -w"
SRC="native/rack/rack.cc native/rack/main.cc native/rack/modules_core.cc native/rack/modules_mutable.cc
 $(ls $MI/plaits/dsp/*.cc $MI/plaits/dsp/*/*.cc $MI/plaits/resources.cc $MI/rings/dsp/*.cc $MI/rings/resources.cc $MI/stmlib/dsp/*.cc $MI/stmlib/utils/*.cc 2>/dev/null)
 $(ls $DS/Control/adsr.cpp $DS/Effects/chorus.cpp $DS/Effects/decimator.cpp $DS/Effects/overdrive.cpp $DS/Effects/wavefolder.cpp $DS/Drums/analogbassdrum.cpp $DS/Drums/analogsnaredrum.cpp $DS/Drums/hihat.cpp $DS/Filters/ladder.cpp $DS/Filters/svf.cpp $DS/Synthesis/oscillator.cpp $DS/Utility/dcblock.cpp 2>/dev/null)"
OBJS=()
pids=()
for f in $SRC; do
  o="$OUT/obj/$(echo "$f" | tr '/' '_').o"
  OBJS+=("$o")
  if [ ! -f "$o" ] || [ "$f" -nt "$o" ] || [ -n "$(find native/rack -name '*.h' -newer "$o" | head -1)" ]; then
    $CXX $FLAGS -c "$f" -o "$o" &
    pids+=($!)
    if [ ${#pids[@]} -ge $(nproc) ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); fi
  fi
done
for p in "${pids[@]:-}"; do [ -n "$p" ] && wait "$p"; done
$CXX -o "$OUT/rack" "${OBJS[@]}"
echo "$OUT/rack"
