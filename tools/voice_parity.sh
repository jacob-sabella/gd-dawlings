#!/usr/bin/env bash
# The voice in dawlings is CHIMERA's own, sample for sample: renders tests/fixtures/voice/parity_melody.json with
# CHIMERA's CLI (`chimera render notes`, built from the pinned vendor/chimera) and the same melody through the rack's
# VOICE module (parity_melody.rack, its raw output tapped: RACK_TAP), both as 32-bit float, and compares every sample.
# Prints "parity: N samples, M differ, max |d| X" and exits 0 only when none differ. VOICE_PARITY_OUT keeps the WAVs.
set -euo pipefail
cd "$(dirname "$0")/.."
RACK=$(tools/rack_build.sh 2>/dev/null | tail -1)
OUT=${VOICE_PARITY_OUT:-$(mktemp -d)}
mkdir -p "$OUT"
( cd vendor/chimera && cargo build --quiet --release --locked -p chimera-cli --target-dir ../../build/chimera-cli >&2 )
FIX=$PWD/tests/fixtures/voice
( cd vendor/chimera && ../../build/chimera-cli/release/chimera render notes "$FIX/parity_melody.json" "$OUT/cli" male --float >/dev/null )
RACK_TAP=v.out RACK_FLOAT=1 "$RACK" --render "$OUT/rack.wav" "$FIX/parity_melody.rack" >/dev/null
python3 -I - "$OUT/cli.wav" "$OUT/rack.wav" <<'PY'
import struct, sys
def samples(path):
    b = open(path, "rb").read()
    i = b.index(b"data")
    n = struct.unpack("<I", b[i + 4:i + 8])[0]
    return struct.unpack("<%df" % (n // 4), b[i + 8:i + 8 + n])
a, r = samples(sys.argv[1]), samples(sys.argv[2])
n = min(len(a), len(r))
bad = sum(1 for i in range(n) if a[i] != r[i])
mx = max((abs(a[i] - r[i]) for i in range(n)), default=0.0)
loud = max((abs(x) for x in a), default=0.0)
print("parity: %d samples, %d differ, max |d| %g, peak %.3f" % (n, bad, mx, loud))
sys.exit(0 if bad == 0 and n > 48000 and loud > 0.05 else 1)
PY
