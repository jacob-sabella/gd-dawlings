#!/usr/bin/env bash
# Measure what the studio costs to draw, across session sizes.
#
#   tools/budget.sh                # 13, 24, 48, 90
#   tools/budget.sh 13 90          # just those two
#
# The target is a standalone passthrough headset: this whole room, twice (once per eye), at
# 72Hz, on a mobile GPU. The numbers below are from a desktop GPU and are NOT that budget --
# what they are good for is the SLOPE and the BREAKDOWN, which are hardware-independent. A draw
# call is a draw call on any GPU, and whether the cost grows with the track count is a fact
# about this code rather than about the machine measuring it.
set -uo pipefail
cd "$(dirname "$0")/.."

SIZES=("$@")
[ ${#SIZES[@]} -eq 0 ] && SIZES=(13 24 48 90)

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

run() {
  local n="$1"
  local pose="${2:-}"
  local cmd=(godot --path . --resolution 1600x900 -- --budget --tracks "$n" --quit-after 200)
  [ -n "$pose" ] && cmd+=(--cam "$pose")
  if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    "${cmd[@]}" 2>&1
  else
    xvfb-run -a --server-args="-screen 0 1600x900x24" "${cmd[@]}" 2>&1
  fi
}

printf '%6s %6s %12s %8s %9s %9s %9s %7s\n' tracks pose prims draws objects frame_ms worst_ms nodes
for n in "${SIZES[@]}"; do
 for pose in fitted wide; do
  [ "$pose" = wide ] && arg="$POSE_WIDE" || arg=""
  run "$n" "$arg" | awk -v n="$n" -v pose="$pose" '
    /^BUDGET tracks=/ {
      for (i = 2; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
      printf "%6d %6s %12d %8d %9d %9.2f %9.2f %7d\n",
             v["tracks"], pose, v["prims"], v["draws"], v["objects"],
             v["frame_ms"], v["worst_ms"], v["nodes"]
    }
    /^BUDGET.surface/ { if (pose == "wide") surf[++s] = $0 }
    END { for (i = 1; i <= s; i++) print "              " surf[i] }
  '
 done
done
