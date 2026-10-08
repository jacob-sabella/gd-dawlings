#!/usr/bin/env bash
# Run the studio in a real window and capture a screenshot.
#
#   tools/shot.sh                               # shots/latest.png, default framing
#   tools/shot.sh shots/console.png             # explicit path
#   SHOT_CAM="0.5,-0.3,2.6,0,0.95,0" tools/shot.sh shots/wide.png
#   SHOT_RES=2560x1440 tools/shot.sh shots/hero.png
#   SHOT_ARGS="--reaper" tools/shot.sh          # photograph a live Reaper instead of the stand-in
#
# A real window and not --headless: the point is to see what the engine renders, which for this
# project is almost entirely glow, shadow and metal -- none of which headless produces. Falls back
# to an offscreen X server when there is no display, so this works over SSH and in a loop.
set -uo pipefail
cd "$(dirname "$0")/.."

SHOT_RES="${SHOT_RES:-1600x900}"
if ! printf '%s' "$SHOT_RES" | grep -qE '^[0-9]+x[0-9]+$'; then
  echo "SHOT_RES must be WIDTHxHEIGHT, got '$SHOT_RES'" >&2
  exit 2
fi

OUT="${1:-shots/latest.png}"
FRAME="${2:-30}"
QUIT="${3:-36}"
mkdir -p "$(dirname "$OUT")"
ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

CAM_ARGS=()
if [ -n "${SHOT_CAM:-}" ]; then
  CAM_ARGS=(--cam "$SHOT_CAM")
fi

# shellcheck disable=SC2206
EXTRA=(${SHOT_ARGS:-})
# The authored room, not whoever-ran-this-last's. A shot that depends on what someone clicked
# yesterday is not reproducible, and one that pushes furniture would save it. SHOT_LAYOUT=user
# photographs the real saved layout instead.
if [ "${SHOT_LAYOUT:-fresh}" != "user" ]; then
  EXTRA+=(--fresh-layout)
fi

RUNNER=(godot --path . --resolution "$SHOT_RES" --
  --shot "$ABS" --shot-frame "$FRAME" --quit-after "$QUIT" --shot-res "$SHOT_RES"
  "${CAM_ARGS[@]}" "${EXTRA[@]}")

LOG="$(mktemp)"
# shellcheck source=offscreen.sh
. tools/offscreen.sh

# The window must be the shape that was asked for. project.godot ships resizable=true, because a
# participant on a 32:9 monitor has to be able to hand the session the whole screen -- but a
# resizable window is one a tiling compositor is free to pack, and the PNG then silently comes out
# at whatever size it decided. Godot applies override.cfg on top of project.godot before the
# display server creates a window, so the capture pins the size there for the length of its own
# run. vsync goes off in the same file: a window on a workspace nobody is looking at is presented
# about once a second, which turns a 36-frame capture into half a minute.
OVERRIDE=override.cfg
if [ -e "$OVERRIDE" ]; then
  echo "$OVERRIDE already exists; refusing to overwrite it." >&2
  exit 4
fi
trap 'rm -f "$LOG" "$OVERRIDE"' EXIT
printf '[display]\n\nwindow/size/resizable=false\nwindow/vsync/vsync_mode=0\n' >"$OVERRIDE"

echo "asked for: ${SHOT_RES}"
if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  offscreen_run "${RUNNER[@]}" 2>&1 | tee "$LOG"
elif command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a --server-args="-screen 0 ${SHOT_RES}x24" "${RUNNER[@]}" 2>&1 | tee "$LOG"
else
  echo "no display and no xvfb-run; install xorg-server-xvfb for headless captures" >&2
  exit 3
fi

if [ -f "$ABS" ]; then
  GOT="$(grep -oE 'SHOT_SAVED .* [0-9]+x[0-9]+' "$LOG" | tail -1 | awk '{print $NF}')"
  if [ -n "$GOT" ] && [ "$GOT" != "$SHOT_RES" ]; then
    echo "RENDERED ${GOT}, NOT ${SHOT_RES} -- the engine did not draw the shape it was given." >&2
  fi
  echo "saved: $ABS ${GOT:-(size unreported)}"
else
  echo "NO SCREENSHOT PRODUCED" >&2
  exit 1
fi
