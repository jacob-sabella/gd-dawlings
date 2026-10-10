#!/usr/bin/env bash
# How long from a MIDI key going down to its sound reaching a sink, through the keys helper
# (native/keys.c) -- the guest's monitor synth -- measured end to end on this machine.
#
#   tools/keys_latency.sh [QUANTUM...]      e.g. tools/keys_latency.sh 128 64
#
# The helper plays into the rig's null sink, never a real device. A real card adds its own
# output latency after the sink (pw-top's figure for it). Builds both programs into
# ~/.cache/dawlings/tmp/keys. Takes the shared rig lock itself; do not wrap it.
set -uo pipefail
cd "$(dirname "$0")/.."
SINK=dawlings_null
OUT=~/.cache/dawlings/tmp/keys
mkdir -p "$OUT"
FLAGS=($(pkg-config --cflags --libs libpipewire-0.3 alsa) -lm)
cc -O2 -o "$OUT/keys" native/keys.c "${FLAGS[@]}" || exit 1
cc -O2 -o "$OUT/keys_latency" tools/keys_latency.c "${FLAGS[@]}" || exit 1
exec 9>~/.cache/dawlings/shared.lock
flock 9
pactl list short sinks | grep -q "$SINK" || pactl load-module module-null-sink "sink_name=$SINK" \
  "sink_properties=device.description=dawlings-rig" >/dev/null
# The rig's sink is kept at 0%, and its monitor carries nothing at 0%. Nothing is linked from it,
# so nothing is heard while it is up; it goes back down afterwards whatever happens.
WAS=$(pactl get-sink-volume "$SINK" | grep -o '[0-9]*%' | head -1)
trap 'pactl set-sink-volume "$SINK" "${WAS:-0%}"; kill $(jobs -p) 2>/dev/null' EXIT
pactl set-sink-volume "$SINK" 100%
status=0
for q in "${@:-128}"; do
  log="$OUT/keys.$q.log"; : >"$log"
  # stdin held open by a sleep: the helper quits at EOF.
  sleep 600 | "$OUT/keys" --device "$SINK" --quantum "$q" >"$log" &
  for _ in $(seq 50); do grep -q '^ready' "$log" && break; sleep 0.1; done
  to=$(grep -m1 '^seq ' "$log" | cut -d' ' -f2)
  if [ -z "$to" ] || ! grep -q '^ready' "$log"; then echo "keys_latency: the helper did not start"; status=1; continue; fi
  printf "quantum %s: " "$q"
  "$OUT/keys_latency" --sink "$SINK" --to "$to" --notes "${NOTES:-16}" || status=1
  reported=$(grep '^latency' "$log" | cut -d' ' -f2 | sort -n | awk '{a[NR]=$1} END {if (NR) printf "%.2f", a[int((NR+1)/2)]/1000}')
  [ -n "$reported" ] && echo "  the helper's own account, median: $reported ms"
  pkill -P $$ -x sleep 2>/dev/null
  wait 2>/dev/null
done
exit $status
