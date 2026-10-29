#!/usr/bin/env bash
# Run the two-process session probe: a headless host and a headless guest on one timeline.
# Exits non-zero if either half saw a failure. See tools/probe/session_probe.gd.
# Sibling: tools/tour_probe.sh runs a Tour run itself, with N players.
set -uo pipefail
cd "$(dirname "$0")/.."
#   tools/session_probe.sh --reaper    the host drives the rig's Reaper, started (and stopped
#                                      again) here if tools/reaper_rig.sh has not already
#   tools/session_probe.sh --built-in  the host plays the built-in engine's song to the guest, on
#                                      a real audio driver into the null sink (headless Godot's
#                                      dummy driver mixes in 85ms lumps, too coarse to time)
#   PROBE_NORAY=1 tools/session_probe.sh      the guest joins by the host's join code through a noray
#                                      on this machine, punched through (docs/multiplayer.md)
#   PROBE_NORAY=relay tools/session_probe.sh  the same, through noray's relay
PORT="${PORT:-7342}"
H_ARGS=(); G_ARGS=()
STARTED_RIG=0
if [ "${1:-}" = "--reaper" ]; then
  # The rig, up if it is not already: without it the host falls back to the stand-in and the
  # guest sees its 2 tracks instead of the rig's 40, which reads as a broken session rather
  # than as a Reaper nobody started. Taken down again only if this run started it.
  if ! tools/reaper_rig.sh status | grep -q running; then
    tools/reaper_rig.sh up || { echo "session_probe: the Reaper rig would not start" >&2; exit 3; }
    STARTED_RIG=1
  fi
  H_ARGS=(--reaper-resource "${REAPER_RIG:-$HOME/.cache/dawlings/rig}" --shift 3)
  G_ARGS=(--expect-tracks "${EXPECT_TRACKS:-40}" --shift 3 --reaper-host)
elif [ "${1:-}" = "--built-in" ]; then
  H_ARGS=(--built-in); G_ARGS=(--built-in)
fi
# PROBE_NORAY=1 (punch) or PROBE_NORAY=relay: the guest joins by the host's join code through a
# noray server on this machine (tools/noray_local.sh, started and stopped here if it is not up).
STARTED_NORAY=0
if [ -n "${PROBE_NORAY:-}" ]; then
  if ! tools/noray_local.sh status | grep -q running; then
    tools/noray_local.sh up >/dev/null || { echo "session_probe: noray would not start" >&2; exit 3; }
    STARTED_NORAY=1
  fi
  export DAWLINGS_NORAY="${DAWLINGS_NORAY:-127.0.0.1}"
  [ "$PROBE_NORAY" = "relay" ] && export DAWLINGS_NORAY_RELAY=1
fi
HOST_LOG="$(mktemp)"; GUEST_LOG="$(mktemp)"
HOST_GODOT=(godot --headless)
if [ "${1:-}" = "--built-in" ]; then
  SINK=dawlings_null
  pactl list short sinks | grep -q "$SINK" || pactl load-module module-null-sink "sink_name=$SINK" \
    "sink_properties=device.description=dawlings-rig" >/dev/null
  HOST_GODOT=(env PULSE_SINK="$SINK" PULSE_SOURCE="$SINK.monitor" godot --display-driver headless --audio-driver PulseAudio)
fi
"${HOST_GODOT[@]}" --path . tools/probe/session_probe.tscn -- --as host --port "$PORT" "${H_ARGS[@]}" >"$HOST_LOG" 2>&1 &
HOST=$!
godot --headless --path . tools/probe/session_probe.tscn -- --as guest --port "$PORT" "${G_ARGS[@]}" >"$GUEST_LOG" 2>&1 &
GUEST=$!
wait "$HOST"; H=$?
wait "$GUEST"; G=$?
echo "== host";  grep -E '^(PASS|FAIL|notices|take|count-in|punch|two inputs|meter|parts|sent files|engine)|session checks|host work done|SCRIPT ERROR' "$HOST_LOG"
echo "== guest"; grep -E '^(PASS|FAIL|notices|audio|take:|sent files)|session checks|SCRIPT ERROR' "$GUEST_LOG"
[ -n "${KEEP_LOGS:-}" ] && cp "$HOST_LOG" "$KEEP_LOGS.host.log" && cp "$GUEST_LOG" "$KEEP_LOGS.guest.log"
rm -f "$HOST_LOG" "$GUEST_LOG"
[ "$STARTED_RIG" -eq 1 ] && tools/reaper_rig.sh down >/dev/null
[ "$STARTED_NORAY" -eq 1 ] && tools/noray_local.sh down >/dev/null
[ "$H" -eq 0 ] && [ "$G" -eq 0 ]
