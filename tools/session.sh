#!/usr/bin/env bash
# Bring up a two-process session: a host and a guest, on this machine.
#
#   tools/session.sh                      # headless host + a guest window
#   tools/session.sh --reaper             # host links to a real Reaper; guest still replicated
#   SHOT=shots/guest.png tools/session.sh  # capture the guest instead of leaving it open
#
# This exists because the multi-user half of the project CANNOT be tested in one process. A
# single run is always its own authority, so every bug in replication -- a field missing from
# the snapshot, a buffer that never flushes, an RPC that lands before the far scene tree exists
# -- is invisible until there are two. The host runs headless because it does not need to draw
# anything to be the authority, which is also the configuration a studio would actually use for
# a machine in a rack.
set -uo pipefail
cd "$(dirname "$0")/.."

HOST_ARGS=("--host")
if [ "${1:-}" = "--reaper" ]; then
  HOST_ARGS+=("--reaper")
  shift
fi

HOST_LOG="$(mktemp)"
godot --headless --path . -- "${HOST_ARGS[@]}" >"$HOST_LOG" 2>&1 &
HOST_PID=$!
cleanup() {
  kill "$HOST_PID" 2>/dev/null
  wait "$HOST_PID" 2>/dev/null
  rm -f "$HOST_LOG"
}
trap cleanup EXIT

# The host has to be accepting connections before the guest dials, or the guest fails to create
# its ENet client and silently falls back to showing nothing.
sleep 2
if ! kill -0 "$HOST_PID" 2>/dev/null; then
  echo "host failed to start:" >&2
  tail -20 "$HOST_LOG" >&2
  exit 1
fi
echo "host up (pid $HOST_PID, headless, ${HOST_ARGS[*]})"

if [ -n "${SHOT:-}" ]; then
  # Frame 150, not 30: the guest must connect, be sent a snapshot and rebuild its surfaces
  # before there is anything to photograph. A capture taken too early is a picture of an empty
  # room, which is exactly what a replication bug also looks like.
  SHOT_ARGS="--join 127.0.0.1" tools/shot.sh "$SHOT" 150 160
else
  echo "guest joining; close its window to end the session"
  godot --path . -- --join 127.0.0.1
fi
