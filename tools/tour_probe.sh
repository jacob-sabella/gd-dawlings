#!/usr/bin/env bash
# Run the tour probe: a headless host and N-1 headless guests through a brief and a half of a
# Tour run, every flaw fixed and every part played from every seat that holds one. Exits
# non-zero if any process saw a failure. See tools/probe/tour_probe.gd.
#
#   tools/tour_probe.sh N        N players, 1..8 (default 4)
#   PORT=7352 tools/tour_probe.sh N
#   KEEP_LOGS=prefix tools/tour_probe.sh N
set -uo pipefail
cd "$(dirname "$0")/.."

N="${1:-4}"
if ! [[ "$N" =~ ^[0-9]+$ ]] || [ "$N" -lt 1 ] || [ "$N" -gt 8 ]; then
  echo "tour_probe: N must be 1..8 (got '$N')" >&2
  exit 2
fi
PORT="${PORT:-7352}"

LOGS=()
PIDS=()

HOST_LOG="$(mktemp)"
LOGS+=("$HOST_LOG")
timeout 100 godot --headless --path . tools/probe/tour_probe.tscn -- --as host --band "$N" --port "$PORT" \
    >"$HOST_LOG" 2>&1 &
PIDS+=("$!")

for ((k = 1; k < N; k++)); do
  G_LOG="$(mktemp)"
  LOGS+=("$G_LOG")
  timeout 100 godot --headless --path . tools/probe/tour_probe.tscn -- --as guest --index "$k" --band "$N" \
      --port "$PORT" >"$G_LOG" 2>&1 &
  PIDS+=("$!")
done

STATUSES=()
for pid in "${PIDS[@]}"; do
  wait "$pid"
  STATUSES+=("$?")
done

# A runtime error raised from the probe's own lines (a backtrace frame naming tour_probe.gd)
# fails the run too: a check whose label did not even format is not a check that passed.
BAD='SCRIPT ERROR|ERROR: Failed to load script|tools/probe/tour_probe\.gd:[0-9]+\)'

FAIL=0
echo "== host"
grep -E "^(PASS|FAIL)|tour checks|host work done|$BAD" "${LOGS[0]}"
[ "${STATUSES[0]}" -ne 0 ] && FAIL=1
grep -qE "$BAD" "${LOGS[0]}" && FAIL=1

for ((k = 1; k < N; k++)); do
  echo "== guest $k"
  grep -E "^(PASS|FAIL)|tour checks|$BAD" "${LOGS[$k]}"
  [ "${STATUSES[$k]}" -ne 0 ] && FAIL=1
  grep -qE "$BAD" "${LOGS[$k]}" && FAIL=1
done

if [ -n "${KEEP_LOGS:-}" ]; then
  cp "${LOGS[0]}" "$KEEP_LOGS.host.log"
  for ((k = 1; k < N; k++)); do
    cp "${LOGS[$k]}" "$KEEP_LOGS.guest$k.log"
  done
fi

for log in "${LOGS[@]}"; do
  rm -f "$log"
done

exit "$FAIL"
