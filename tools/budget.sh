#!/usr/bin/env bash
# Measure what the studio costs to draw, across session sizes.
#
#   tools/budget.sh                # 13, 24, 48, 90
#   tools/budget.sh 13 90          # just those two
#   VENUE=cabin tools/budget.sh 13 # in a venue other than the default
#
# The target is a standalone passthrough headset: this whole room, twice (once per eye), at
# 72Hz, on a mobile GPU. The numbers below are from a desktop GPU and are NOT that budget --
# what they are good for is the SLOPE and the BREAKDOWN, which are hardware-independent. A draw
# call is a draw call on any GPU, and whether the cost grows with the track count is a fact
# about this code rather than about the machine measuring it.
#
# It ends with a verdict and exits 1 on a FAIL. Judged are what is deterministic (docs/performance.md): each row's
# draws and primitives against the reference rows in docs/performance.md ("Numbers at HEAD", REF below), at most
# REF_GROWTH percent (5) over; and the singer's voice (CHIMERA through the rack, rendered from
# tests/fixtures/voice/parity_melody.rack five times over) at most VOICE_SHARE_MOST percent of one core (25), since
# it plays on a thread of its own. Frame times are printed, not judged: a desktop's are not the headset's budget, and
# one run of them moves by 3 ms. A size with no reference row is measured, not judged. `tools/budget.sh voice` runs
# only the voice.
set -uo pipefail
cd "$(dirname "$0")/.."

SIZES=("$@")
[ ${#SIZES[@]} -eq 0 ] && SIZES=(13 24 48 90)
[ "${SIZES[0]}" = voice ] && SIZES=()
# tracks:pose:draws:prims, from docs/performance.md; update both together when the room changes on purpose. 48 fitted
# is remeasured at 0a32bba (2026-11-12): a run settles on one of two flat levels, 3950 or 4114 draws (a light's
# shadow cached or redrawn from the start), and the table's 3869 was the lower one before the room grew.
# 90 is measured at 0a32bba too (2026-11-12; the table has no 90 rows): fitted one run, wide the highest of three.
REF="13:fitted:3388:403548 13:wide:6052:887580 48:fitted:4116:458155 48:wide:5673:994128 90:fitted:3785:483048 90:wide:6222:1124590"
REF_GROWTH="${REF_GROWTH:-5}"
VOICE_SHARE_MOST="${VOICE_SHARE_MOST:-25}"
failed=0

OVERRIDE=override.cfg
if [ -e "$OVERRIDE" ]; then
  echo "$OVERRIDE already exists; refusing to overwrite it." >&2
  exit 4
fi
# vsync off, or every sample is pinned to the monitor's refresh and the frame time measured is
# the time spent waiting rather than the time spent working.
trap 'rm -f "$OVERRIDE"' EXIT
printf '[display]\n\nwindow/vsync/vsync_mode=0\n' >"$OVERRIDE"

# Two poses, because one camera angle is not a measurement of a scene -- it is a measurement of
# what that angle happened to see. The default framing fits the console to the viewport, so a
# 90-track desk runs off both edges and a third of it is culled; the numbers come back flattering
# and the headset, where you can turn your head, never gets that discount. WIDE stands far enough
# back to hold the whole room and is the worst case.
POSE_WIDE="0,-0.35,7.0,0,1.0,0"

# shellcheck source=offscreen.sh
. tools/offscreen.sh

run() {
  local n="$1"
  local pose="${2:-}"
  local cmd=(godot --path . --resolution 1600x900 -- --budget --tracks "$n" --quit-after 200)
  [ -n "$pose" ] && cmd+=(--cam "$pose")
  [ -n "${VENUE:-}" ] && cmd+=(--venue "$VENUE")
  if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    offscreen_run "${cmd[@]}" 2>&1
  else
    xvfb-run -a --server-args="-screen 0 1600x900x24" "${cmd[@]}" 2>&1
  fi
}

rows=$(mktemp)
[ ${#SIZES[@]} -gt 0 ] && printf '%6s %6s %12s %8s %9s %9s %9s %7s %9s %7s\n' tracks pose prims draws objects frame_ms worst_ms nodes start_ms mem_mb
for n in "${SIZES[@]}"; do
 for pose in fitted wide; do
  [ "$pose" = wide ] && arg="$POSE_WIDE" || arg=""
  run "$n" "$arg" | awk -v n="$n" -v pose="$pose" -v ref="$REF" -v growth="$REF_GROWTH" '
    /^BUDGET tracks=/ {
      for (i = 2; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
      printf "%6d %6s %12d %8d %9d %9.2f %9.2f %7d %9d %7.1f\n",
             v["tracks"], pose, v["prims"], v["draws"], v["objects"],
             v["frame_ms"], v["worst_ms"], v["nodes"], v["start_ms"], v["mem_mb"]
      nr = split(ref, rows, " ")
      for (r = 1; r <= nr; r++) {
        split(rows[r], f, ":")
        if (f[1] + 0 != v["tracks"] + 0 || f[2] != pose) continue
        top = 1 + growth / 100
        if (v["draws"] + 0 > f[3] * top) printf "budget: FAIL draws %d over %d (+%d%%) at %d tracks (%s)\n", v["draws"], f[3], growth, v["tracks"], pose
        if (v["prims"] + 0 > f[4] * top) printf "budget: FAIL prims %d over %d (+%d%%) at %d tracks (%s)\n", v["prims"], f[4], growth, v["tracks"], pose
      }
    }
    /^BUDGET.surface/ { if (pose == "wide") surf[++s] = $0 }
    END { for (i = 1; i <= s; i++) print "              " surf[i] }
  ' | tee -a "$rows"
 done
done
# a size that printed no row (the game failed to start or to measure) is a FAIL too, not a pass by silence
[ "$(grep -c '^ *[0-9]' "$rows")" -lt $((${#SIZES[@]} * 2)) ] && { echo "budget: FAIL a size measured nothing"; failed=1; }
grep -q "^budget: FAIL" "$rows" && failed=1
rm -f "$rows"

# The singer's voice: what CHIMERA costs a core, rendered as fast as it goes. The rack plays it on its own thread,
# so a share of one core is the measure, not the frame.
RACK=$(tools/rack_build.sh 2>/dev/null | tail -1)
fix=tests/fixtures/voice/parity_melody.rack
voice=$(mktemp -d)
for i in 1 2 3 4 5; do cat "$fix"; done >"$voice/five.rack"
start=$(date +%s%N)
"$RACK" --render "$voice/five.wav" "$voice/five.rack" >/dev/null 2>&1
end=$(date +%s%N)
share=$(python3 -I - "$voice/five.wav" "$start" "$end" <<'PY'
import sys, wave
w = wave.open(sys.argv[1])
heard = w.getnframes() / w.getframerate()
spent = (int(sys.argv[3]) - int(sys.argv[2])) / 1e9
print(f"{100 * spent / heard:.1f} {heard:.1f} {spent:.2f}")
PY
)
rm -rf "$voice"
read -r pct heard spent <<<"$share"
echo "voice: ${heard} s sung in ${spent} s of one core, ${pct}% of a core (most ${VOICE_SHARE_MOST}%)"
python3 -c "import sys; sys.exit(0 if float('$pct') <= float('$VOICE_SHARE_MOST') else 1)" \
  || { echo "budget: FAIL voice ${pct}% of a core"; failed=1; }
[ "$failed" -eq 0 ] && echo "budget: PASS" || echo "budget: FAIL"
exit "$failed"
