#!/usr/bin/env bash
# The two-process realm probe (docs/realms.md): a headless host and a headless guest on one machine; the guest
# visits, takes the rack and the song, brings a song of its own and goes home. Exits non-zero if either half saw
# a failure. See tools/probe/realm_probe.gd.
set -uo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-7352}"
HOST_LOG="$(mktemp)"; GUEST_LOG="$(mktemp)"
godot --headless --path . tools/probe/realm_probe.tscn -- --as host --port "$PORT" >"$HOST_LOG" 2>&1 &
HOST=$!
godot --headless --path . tools/probe/realm_probe.tscn -- --as guest --port "$PORT" >"$GUEST_LOG" 2>&1 &
GUEST=$!
wait "$HOST"; H=$?
wait "$GUEST"; G=$?
echo "== host";  grep -E '^  (ok|FAIL)|realm checks|SCRIPT ERROR' "$HOST_LOG"
echo "== guest"; grep -E '^  (ok|FAIL)|realm checks|SCRIPT ERROR' "$GUEST_LOG"
rm -f "$HOST_LOG" "$GUEST_LOG"
git checkout -q project.godot 2>/dev/null || true
[ "$H" -eq 0 ] && [ "$G" -eq 0 ]
