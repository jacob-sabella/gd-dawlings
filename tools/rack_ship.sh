#!/usr/bin/env bash
# Puts the modular room's engine beside an exported game, as a release ships it: DEST/rack/ holds the engine
# (rack, or rack.exe for windows), the voice's pronouncing dictionary (CMUdict, read at run time) and the
# licence of everything compiled into the engine. RackEngine finds it there (RackEngine.SHIPPED).
#
#   tools/rack_ship.sh linux build/linux       # builds build/rack/rack if need be
#   tools/rack_ship.sh windows build/windows   # builds build/rack-windows/rack.exe (MinGW, Rust's windows-gnu target)
set -euo pipefail
cd "$(dirname "$0")/.."
OS=${1:?linux or windows}
DEST=${2:?the folder the game was exported to}
case "$OS" in
  linux) BIN=$(tools/rack_build.sh | tail -1) ;;
  windows) BIN=$(RACK_TARGET=windows tools/rack_build.sh | tail -1) ;;
  *) echo "linux or windows, not $OS" >&2; exit 2 ;;
esac
OUT="$DEST/rack"
LIC="$OUT/licences"
mkdir -p "$LIC"
cp "$BIN" "$OUT/"
cp vendor/chimera/public/data/cmudict.txt.gz "$OUT/cmudict.txt.gz"
cp THIRD_PARTY_NOTICES.md "$OUT/"
cp vendor/chimera/LICENSE "$LIC/chimera.txt"
cp vendor/chimera/public/data/CMUDICT-LICENSE.txt "$LIC/cmudict.txt"
cp vendor/daisysp/LICENSE "$LIC/daisysp.txt"
cp vendor/airwindows/LICENSE "$LIC/airwindows.txt"
cp vendor/mutable-eurorack/stmlib/LICENSE "$LIC/stmlib.txt"
# Mutable Instruments' MIT notice is in each source file's header (the repository has no LICENSE file).
sed -n '1,/^\/\/ See http/p' vendor/mutable-eurorack/plaits/dsp/voice.cc | sed 's|^// \{0,1\}||' > "$LIC/mutable-instruments.txt"
# The crates linked into the voice, each under its own MIT licence (THIRD_PARTY_NOTICES.md lists them).
CARGO_HOME=${CARGO_HOME:-$HOME/.cargo}
for dir in "$CARGO_HOME"/registry/src/*/; do
  for crate in $(awk '/^name = /{gsub(/"/,"",$3); n=$3} /^version = /{gsub(/"/,"",$3); print n"-"$3}' native/voice/Cargo.lock); do
    for f in LICENSE-MIT LICENSE-MIT.md LICENSE-MIT.txt LICENSE.md LICENSE.txt LICENSE COPYING; do
      if [ -f "$dir$crate/$f" ] && [ ! -f "$LIC/crate-$crate.txt" ]; then cp "$dir$crate/$f" "$LIC/crate-$crate.txt"; fi
    done
  done
done
test -s "$OUT/$(basename "$BIN")" && test -s "$OUT/cmudict.txt.gz"
echo "$OUT: $(ls "$OUT" | tr '\n' ' ')($(ls "$LIC" | wc -l) licences)"
