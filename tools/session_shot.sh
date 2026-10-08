#!/usr/bin/env bash
# Photograph a two-person session from both sides at once.
#
#   tools/session_shot.sh shots/session            # writes shots/session_host.png, _guest.png
#
# Two real windows, out of sight: a host ("Ada") that takes hold of the kick fader and drags it,
# and a guest ("Grace") standing behind and to the left of her. The guest's picture is the
# evidence for presence -- Ada's avatar, her beam, her colour round the fader she holds -- and
# the host's is the evidence that the guest is in her room too.
#
# Timing is in physics ticks (60 a second, whatever the frame rate), because the two windows
# draw at different speeds and a frame count means a different moment in each.
#
# HOST_ARGS / GUEST_ARGS add to either side, e.g. GUEST_ARGS="--aim SNARE__PAN".
set -uo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-shots/session}"
RES="${SHOT_RES:-1600x900}"
mkdir -p "$(dirname "$OUT")"
BASE="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

OVERRIDE=override.cfg
if [ -e "$OVERRIDE" ]; then
  echo "$OVERRIDE already exists; refusing to overwrite it." >&2
  exit 4
fi
HOST_LOG="$(mktemp)"; GUEST_LOG="$(mktemp)"
trap 'rm -f "$OVERRIDE" "$HOST_LOG" "$GUEST_LOG"' EXIT
printf '[display]\n\nwindow/size/resizable=false\nwindow/vsync/vsync_mode=0\n' >"$OVERRIDE"
# shellcheck source=offscreen.sh
. tools/offscreen.sh

# shellcheck disable=SC2206
H_EXTRA=(${HOST_ARGS:-})
# shellcheck disable=SC2206
G_EXTRA=(${GUEST_ARGS:-})

offscreen_run godot --path . --resolution "$RES" -- --fresh-layout --host --name Ada \
  --pull "${HOST_PULL:-KICK__LEVEL}:0,-${HOST_PULL_PX:-110}@${HOST_PULL_AT:-240-1500}" \
  --shot "${BASE}_host.png" --shot-tick "${HOST_TICK:-700}" --shot-res "$RES" \
  "${H_EXTRA[@]}" >"$HOST_LOG" 2>&1 &
HOST=$!
sleep 1.5
offscreen_run godot --path . --resolution "$RES" -- --fresh-layout --join 127.0.0.1 --name Grace \
  --walk "${GUEST_WALK:--1.75,0.25,-1.45,-0.08}" --aim "${GUEST_AIM:-SNARE__LEVEL}" \
  --shot "${BASE}_guest.png" --shot-tick "${GUEST_TICK:-480}" --quit-tick 900 --shot-res "$RES" \
  "${G_EXTRA[@]}" >"$GUEST_LOG" 2>&1 &
GUEST=$!
wait "$GUEST"
wait "$HOST"
grep -h 'SHOT_SAVED\|SHOT_CLICK' "$HOST_LOG" "$GUEST_LOG"
for log in "$HOST_LOG" "$GUEST_LOG"; do grep -m3 -A7 'SCRIPT ERROR' "$log"; done
