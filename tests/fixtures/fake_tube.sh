#!/bin/sh
# A stand-in for both yt-dlp and ffmpeg, for Tube's tests (_test_tube_*): never the network.
# As yt-dlp it answers a "ytsearchN:" with a recorded flat search and a watch link by writing a
# small file where -o says (and the info JSON beside it); as ffmpeg it writes "RIFF" to its last
# argument, or, asked for rawvideo, FAKE_TUBE_FRAMES frames of TubeFrames' size (default 30) to
# its output, frame k every byte k.
#
#   FAKE_TUBE_FAIL   when set, says "ERROR: <it>" and fails
#   FAKE_TUBE_ARGS   where to write its own arguments, one a line
if [ -n "${FAKE_TUBE_ARGS:-}" ]; then
  for a in "$@"; do printf '%s\n' "$a" >> "$FAKE_TUBE_ARGS"; done
fi
if [ -n "${FAKE_TUBE_FAIL:-}" ]; then
  echo "ERROR: $FAKE_TUBE_FAIL"
  exit 1
fi
case "$1" in
  ytsearch*)
    echo '{"_type": "playlist", "entries": [
      {"id": "dQw4w9WgXcQ", "title": "A song", "duration": 213.0, "channel": "Someone"},
      {"id": "aBc_DeF-123", "title": "A loop", "duration": null, "channel": null, "uploader": "Uploader"}]}'
    exit 0 ;;
esac
case " $* " in
  *" rawvideo "*)
    k=0
    while [ "$k" -lt "${FAKE_TUBE_FRAMES:-30}" ]; do
      head -c 248832 /dev/zero | tr '\000' "\\$(printf '%03o' "$k")" || exit 0
      k=$((k + 1))
    done
    exit 0 ;;
esac
out=""; last=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  prev="$a"; last="$a"
done
if [ -n "$out" ]; then
  base="${out%.%(ext)s}"
  printf 'not really a video' > "$base.mp4"
  printf '{"title": "A song", "duration": 213.0, "channel": "Someone"}' > "$base.info.json"
  exit 0
fi
printf 'RIFF' > "$last"
