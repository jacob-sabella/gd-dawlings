#!/usr/bin/env bash
# Record a clip of the running studio with Godot's movie writer, then encode it.
#
#   tools/movie.sh docs/media/road.mp4                        # the default clip, 10 s at 1280x720
#   MOVIE_ARGS="--venue grid --tl-road 20 --roll" MOVIE_SECONDS=12 tools/movie.sh out.mp4
#   MOVIE_GIF=1 ...                                           # also write out.gif beside it (heavy)
#
# The movie writer renders a frame at a time at a fixed rate, so the clip is smooth however slowly
# the machine draws it. Takes the same --cam/--look/--venue/--tl-* arguments as tools/shot.sh
# (see tools/screenshot.gd), with --roll to start the transport.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?output .mp4}"
RES="${MOVIE_RES:-1280x720}"
FPS="${MOVIE_FPS:-30}"
SECONDS_LONG="${MOVIE_SECONDS:-10}"
mkdir -p "$(dirname "$OUT")"
ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
RAW="$(mktemp --suffix=.avi)"
# shellcheck disable=SC2206
EXTRA=(${MOVIE_ARGS:-})
OVERRIDE=override.cfg
[ -e "$OVERRIDE" ] && { echo "$OVERRIDE already exists; refusing to overwrite it." >&2; exit 4; }
trap 'rm -f "$RAW" "$OVERRIDE"' EXIT
printf '[display]\n\nwindow/size/resizable=false\nwindow/vsync/vsync_mode=0\n' >"$OVERRIDE"
export PULSE_SINK="${SHOT_SINK:-dawlings_null}" PIPEWIRE_NODE="${SHOT_SINK:-dawlings_null}"
# shellcheck source=offscreen.sh
. tools/offscreen.sh
RUNNER=(godot --path . --resolution "$RES" --write-movie "$RAW" --fixed-fps "$FPS" --
  --quit-after "$((FPS * SECONDS_LONG))" --fresh-layout "${EXTRA[@]}")
if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  offscreen_run "${RUNNER[@]}"
else
  xvfb-run -a --server-args="-screen 0 ${RES}x24" "${RUNNER[@]}"
fi
[ -s "$RAW" ] || { echo "NO MOVIE PRODUCED" >&2; exit 1; }
# Without --no-hud the top 44 pixels at 1080p are the debug key-help line; MOVIE_VF replaces the
# default crop (a --no-hud shot may still show the hover prompt along the bottom).
VF="${MOVIE_VF:-crop=in_w:in_h-in_h*44/1080:0:in_h*44/1080}"
ffmpeg -loglevel error -y -i "$RAW" -vf "$VF" -c:v libx264 -crf 24 -preset slow -pix_fmt yuv420p -movflags +faststart -an "$ABS"
if [ -n "${MOVIE_GIF:-}" ]; then
  ffmpeg -loglevel error -y -i "$ABS" -vf "fps=12,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse" "${ABS%.mp4}.gif"
fi
echo "saved: $ABS"
