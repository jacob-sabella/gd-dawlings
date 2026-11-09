#!/usr/bin/env bash
# Builds the modular room's engine, native/rack, from the pinned submodules (vendor/daisysp,
# vendor/mutable-eurorack) into build/rack/rack. Objects are cached per source file; an unchanged
# one is not rebuilt. Needs a C++14 compiler (c++). Prints the binary's path.
# RACK_ONLY="warps braids" builds the core and just those second-batch modules (each is native/rack/modules_<name>.cc
# with its source list in native/rack/libs/<name>.txt); RACK_BUILD_DIR and RACK_BIN give a build a place and a name of its own.
set -euo pipefail
cd "$(dirname "$0")/.."
MI=vendor/mutable-eurorack
DS=vendor/daisysp/Source
[ -f "$MI/stmlib/stmlib.h" ] && [ -d "$DS" ] || { echo "run: git submodule update --init --recursive vendor/daisysp vendor/mutable-eurorack && git -C $MI submodule update --init stmlib" >&2; exit 1; }
OUT=${RACK_BUILD_DIR:-build/rack}
BIN=${RACK_BIN:-rack}   # a private name lets two builds share the object cache and link side by side
mkdir -p "$OUT/obj"
CXX=${CXX:-c++}
FLAGS="-O2 -std=c++14 -DTEST -include cstdio -I$MI -I$DS -I$DS/Utility -Inative/rack -Inative/rack/aw -w"
SRC="native/rack/rack.cc native/rack/main.cc $(ls native/rack/modules_core.cc native/rack/modules_mutable.cc $(for m in ${RACK_ONLY:-$(cd native/rack/libs && ls *.txt | sed s/.txt//)}; do echo native/rack/modules_$m.cc; done))
 $(for l in $(for m in ${RACK_ONLY:-$(cd native/rack/libs && ls *.txt | sed s/.txt//)}; do echo native/rack/libs/$m.txt; done); do [ -f "$l" ] && sed -e "s|^|$MI/|" "$l" | tr '\n' ' '; done | xargs -n1 sh -c 'ls $0' 2>/dev/null)
 $(ls $MI/plaits/dsp/*.cc $MI/plaits/dsp/*/*.cc $MI/plaits/resources.cc $MI/rings/dsp/*.cc $MI/rings/resources.cc $MI/clouds/dsp/*.cc $MI/clouds/dsp/pvoc/*.cc $MI/clouds/resources.cc $MI/stmlib/dsp/*.cc $MI/stmlib/utils/*.cc 2>/dev/null)
 $(ls $DS/Control/adsr.cpp $DS/Effects/chorus.cpp $DS/Effects/decimator.cpp $DS/Effects/overdrive.cpp $DS/Effects/wavefolder.cpp $DS/Drums/analogbassdrum.cpp $DS/Drums/analogsnaredrum.cpp $DS/Drums/hihat.cpp $DS/Filters/ladder.cpp $DS/Filters/svf.cpp $DS/Synthesis/oscillator.cpp $DS/Utility/dcblock.cpp 2>/dev/null)"
# The Airwindows plugins are compiled from the pinned submodule, through wrappers written into the build folder.
GEN=""
case " ${RACK_ONLY:-$(cd native/rack/libs && ls *.txt | sed s/.txt// | tr "\n" " ")} " in *" airwindows "*)
  [ -d vendor/airwindows/plugins ] || { echo "run: git submodule update --init vendor/airwindows" >&2; exit 1; }
  python3 tools/airwindows_gen.py "$OUT/gen" && GEN=$(ls "$OUT"/gen/*.cc) ;;
esac
SRC="$SRC $GEN"
OBJS=()
pids=()
for f in $(printf "%s\n" $SRC | awk "!seen[\$0]++"); do
  o="$OUT/obj/$(echo "$f" | tr '/' '_').o"
  OBJS+=("$o")
  if [ ! -f "$o" ] || [ "$f" -nt "$o" ] || [ -n "$(find native/rack -name '*.h' -newer "$o" | head -1)" ]; then
    ( $CXX $FLAGS -c "$f" -o "$o.part" && mv "$o.part" "$o" ) &
    pids+=($!)
    if [ ${#pids[@]} -ge $(nproc) ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); fi
  fi
done
for p in "${pids[@]:-}"; do [ -n "$p" ] && wait "$p"; done
$CXX -o "$OUT/$BIN" "${OBJS[@]}"
echo "$OUT/$BIN"
