#!/usr/bin/env bash
# The singer demo as a clip with its sound, made in real time (the movie writer cannot: it runs the game at its
# own pace and the singer's engine in real time, so its clip has no singing and no take).
#
#   tools/singer_clip.sh docs/media/singer.mp4            # the built-in backend
#   tools/singer_clip.sh shots/singer_reaper.mp4 --reaper # the rig's Reaper (tools/reaper_rig.sh up first)
#
# (The demo runs inside the screenshot tool, so a --shot is taken at its end.) The window goes to workspace 10
# (tools/offscreen.sh) and its sound to the null sink. On the built-in backend the clip's sound is the song's mix
# (the Mix bus), caught inside the game (tools/singer_demo.gd, SINGER_DEMO_CLIP). With --reaper the song is played
# by Reaper, so its part is the null sink, recorded beside the run and cut to start at the clip's first frame (the
# demo writes that moment's wall clock); the game reaches the sink only at the per-app volumes you keep, so the
# singer is taken from inside the game (the Monitor bus, where it plays under Reaper) and mixed in. Nothing else
# may be playing into the sink meanwhile (a test run, say), or it is in the clip too.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-shots/singer.mp4}"
mode="${2:-}"
SINK=dawlings_null
dir="$(mktemp -d)"
backend=(--built-in)
ticks=(9000 9100) # a ceiling: the demo quits a clip run itself once the clip is written
if [ "$mode" = "--reaper" ]; then
  tools/reaper_rig.sh status 2>/dev/null | grep -q "running" \
    || { echo "singer_clip: the rig is not up (tools/reaper_rig.sh up)" >&2; exit 3; }
  backend=(--reaper --reaper-resource "$HOME/.cache/dawlings/rig")
fi
# Unvsynced, as budget.sh runs: a vsynced window on a workspace nobody looks at is given a frame a second. Not
# resizable, so it floats at its size: the rig's Reaper window is on the same workspace, and a tiled window is
# squeezed in beside it.
OVERRIDE=override.cfg
if [ -e "$OVERRIDE" ]; then echo "$OVERRIDE already exists; refusing to overwrite it." >&2; exit 4; fi
printf '[display]\n\nwindow/size/resizable=false\nwindow/vsync/vsync_mode=0\n' >"$OVERRIDE"
rec=""
trap '[ -n "$rec" ] && kill "$rec" 2>/dev/null; rm -rf "$dir" "$OVERRIDE"' EXIT
if [ "$mode" = "--reaper" ]; then
  date +%s%3N >"$dir/sink_t0"
  # float: Reaper's mix goes over 1.0, and a 16-bit capture clips it
  parec -d "$SINK.monitor" --format=float32le --file-format=wav --rate=48000 --channels=2 "$dir/sink.wav" &
  rec=$!
fi
# shellcheck source=offscreen.sh
. tools/offscreen.sh
export PULSE_SINK="${PULSE_SINK:-$SINK}" PIPEWIRE_NODE="${PIPEWIRE_NODE:-$SINK}"
offscreen_run env SINGER_DEMO_CLIP="$dir" SINGER_DEMO_SHOTS="${SINGER_DEMO_SHOTS:-}" godot --path . --resolution 1600x900 -- "${backend[@]}" --singer-demo \
  --fresh-layout --shot "$dir/end.png" --shot-res 1600x900 --shot-tick "${ticks[0]}" --quit-tick "${ticks[1]}" 2>&1 | grep -E "SINGER_DEMO|SCRIPT ERROR" || true
audio="$dir/clip.wav"
if [ -n "$rec" ]; then
  kill "$rec"; wait "$rec" 2>/dev/null || true; rec=""
  [ -s "$dir/t0" ] || { echo "singer_clip: the demo made no frames" >&2; exit 1; }
  skip="$(python3 -c 'import sys; print(max(0, int(sys.argv[1]) - int(sys.argv[2])) / 1000)' "$(cat "$dir/t0")" "$(cat "$dir/sink_t0")")"
  # Reaper's part (the sink: the game's own streams reach it only at the volumes you keep them at) and the game's
  # (the singer and the beatbox on the Monitor bus, the creature on the Mix, recorded from the first frame), each brought to a
  # peak of -6 dB before they are summed: the rig's mix of test tones runs far hotter than a voice, and levelled
  # together the game's part came out near -43 dB. A limiter keeps the sum under -1 dB.
  peak() { ffmpeg -hide_banner "$@" -af astats=measure_perchannel=none -f null - 2>&1 \
    | sed -n 's/.*Peak level dB: \(-\?[0-9.]*\).*/\1/p' | tail -1; }
  up() { python3 -c "import sys; p = sys.argv[1]; print(0 if p in ('', '-inf') else -6 - float(p))" "$1"; }
  reaper_gain="$(up "$(peak -ss "$skip" -i "$dir/sink.wav")")"
  # the game's part: its Monitor bus (the singer) and its Mix bus (the creature, which plays to the room)
  ffmpeg -v error -y -i "$dir/clip_monitor.wav" -i "$dir/clip.wav" -filter_complex \
    "[0:a]aresample=48000[m];[1:a]aresample=48000[x];[m][x]amix=inputs=2:duration=longest:normalize=0" -c:a pcm_f32le "$dir/game.wav"
  game_gain="$(up "$(peak -i "$dir/game.wav")")"
  ffmpeg -v error -y -ss "$skip" -i "$dir/sink.wav" -i "$dir/game.wav" -filter_complex \
    "[0:a]volume=${reaper_gain}dB[r];[1:a]volume=${game_gain}dB[g];[r][g]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.89:level=false" \
    -c:a pcm_s16le "$dir/sink_cut.wav"
  audio="$dir/sink_cut.wav"
fi
[ -s "$audio" ] || { echo "singer_clip: no clip was made" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
ffmpeg -v error -y -f concat -safe 0 -i "$dir/frames.ffconcat" -i "$audio" \
  -fps_mode vfr -c:v libx264 -pix_fmt yuv420p -crf 22 -c:a aac -b:a 160k -shortest "$out"
echo "singer_clip: $out"
