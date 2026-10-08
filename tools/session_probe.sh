#!/usr/bin/env bash
# Run the two-process session probe: a headless host and a headless guest on one timeline.
# Exits non-zero if either half saw a failure. See tools/probe/session_probe.gd.
set -uo pipefail
cd "$(dirname "$0")/.."
#   tools/session_probe.sh --reaper    the host drives the rig's Reaper (tools/reaper_rig.sh up)
PORT="${PORT:-7342}"
H_ARGS=(); G_ARGS=()
if [ "${1:-}" = "--reaper" ]; then
  H_ARGS=(--reaper-resource "${REAPER_RIG:-$HOME/.cache/reaper-3d/rig}" --shift 3)
  G_ARGS=(--expect-tracks "${EXPECT_TRACKS:-40}" --shift 3)
fi
HOST_LOG="$(mktemp)"; GUEST_LOG="$(mktemp)"
godot --headless --path . tools/probe/session_probe.tscn -- --as host --port "$PORT" "${H_ARGS[@]}" >"$HOST_LOG" 2>&1 &
HOST=$!
godot --headless --path . tools/probe/session_probe.tscn -- --as guest --port "$PORT" "${G_ARGS[@]}" >"$GUEST_LOG" 2>&1 &
GUEST=$!
wait "$HOST"; H=$?
wait "$GUEST"; G=$?
echo "== host";  grep -E '^(PASS|FAIL|notices|take)|session checks|SCRIPT ERROR' "$HOST_LOG"
echo "== guest"; grep -E '^(PASS|FAIL|notices|audio)|session checks|SCRIPT ERROR' "$GUEST_LOG"
rm -f "$HOST_LOG" "$GUEST_LOG"
[ "$H" -eq 0 ] && [ "$G" -eq 0 ]
