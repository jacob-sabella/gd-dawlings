#!/usr/bin/env bash
# How far behind the host's speakers a guest hears the mix, measured end to end on this machine.
#
#   tools/audio_latency.sh
#
# A click track stands in for Reaper. It is linked two ways at once: into the mix tap, where the
# host picks it up and sends it to a guest, and straight into a null sink as the reference. The
# guest plays into the same null sink. Recording that sink gives every click twice -- the
# reference, then the guest's copy -- and the gap between them is the latency a person would
# hear, sound card to sound card, with nothing estimated.
#
# R3D_LATENCY_ARGS is added to both launches: "--direct-audio" measures without AudioPorts.
#
# Both processes run with a headless display and a REAL audio driver, so there are no windows
# and nothing reaches the speakers: everything plays into the null sink.
set -uo pipefail
cd "$(dirname "$0")/.."
SINK=reaper3d_null
PORT="${PORT:-7352}"
WORK="${KEEP:-$(mktemp -d)}"; mkdir -p "$WORK"
trap 'kill $(jobs -p) 2>/dev/null; [ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT

pactl list short sinks | grep -q "$SINK" || pactl load-module module-null-sink "sink_name=$SINK" \
  "sink_properties=device.description=reaper-3d-rig" >/dev/null

python3 - "$WORK/clicks.wav" <<'PY'
import sys, wave, struct
rate, secs = 48000, 30
w = wave.open(sys.argv[1], "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
frames = bytearray()
for i in range(rate * secs):
    v = 30000 if i % (rate // 2) < 48 else 0
    frames += struct.pack("<hh", v, v)
w.writeframes(bytes(frames)); w.close()
PY

# Started unconnected, under a known name, before the host goes looking for it.
pw-play -P '{ node.name=r3d_clicks node.autoconnect=false }' "$WORK/clicks.wav" &
sleep 0.5
pw-link r3d_clicks:output_FL "$SINK:playback_FL"
pw-link r3d_clicks:output_FR "$SINK:playback_FR"

GODOT=(env R3D_AUDIO_STATS=1 godot --display-driver headless --audio-driver PulseAudio --path .)
"${GODOT[@]}" -- --host --name Ada --mix-from r3d_clicks --session-port "$PORT" ${R3D_LATENCY_ARGS:-} \
  >"$WORK/host.log" 2>&1 &
sleep 2.5
"${GODOT[@]}" -- --join 127.0.0.1 --session-port "$PORT" --name Grace --listen --audio-out "$SINK" ${R3D_LATENCY_ARGS:-} \
  >"$WORK/guest.log" 2>&1 &
sleep "${SETTLE:-6}"
timeout -s INT 6 pw-record --target "$SINK" -P '{ stream.capture.sink=true }' "$WORK/heard.wav" 2>/dev/null
python3 - "$WORK/heard.wav" <<'PY'
import sys, wave, array
w = wave.open(sys.argv[1]); rate = w.getframerate()
a = array.array({2: "h", 4: "i"}[w.getsampwidth()], w.readframes(w.getnframes()))
left = a[::w.getnchannels()]
full = max(abs(x) for x in left) or 1
onsets, last = [], -rate
for i, x in enumerate(left):
    if abs(x) > full * 0.3 and i - last > rate // 200:
        onsets.append(i); last = i
# Pairs inside each half-second: reference first, the guest's copy after it.
gaps = []
period = rate // 2
for i, t in enumerate(onsets):
    later = [u for u in onsets[i + 1:] if 0 < u - t < period * 0.8]
    if later and (i == 0 or t - onsets[i - 1] > period * 0.5):
        gaps.append((later[0] - t) * 1000.0 / rate)
if not gaps:
    print("audio_latency: heard %d onsets, no pairs -- the guest's copy never arrived" % len(onsets))
    sys.exit(1)
gaps.sort()
print("audio_latency: %d clicks, median %.1f ms, best %.1f, worst %.1f" % (
    len(gaps), gaps[len(gaps) // 2], gaps[0], gaps[-1]))
PY
measured=$?
grep -h "SCRIPT ERROR" -A4 "$WORK/host.log" "$WORK/guest.log" | head -20
grep -h "MIXFEED" "$WORK/guest.log" | tail -1
exit "$measured"
