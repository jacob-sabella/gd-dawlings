#!/usr/bin/env bash
# Photograph every venue from where you stand, from across the room and from the activity zones
# behind you, and say whether each is within the light budget. Exits non-zero if any is over.
#
#   tools/light_check.sh                 every venue in Venue.IDS
#   tools/light_check.sh grid chalk      just these
#   tools/light_check.sh grid:1          one venue's second arrangement
#   OUT=~/somewhere tools/light_check.sh where the pictures go (default ~/.cache/dawlings/shots/light_check)
#
# The budget is measured, not felt: the mean grey of the picture, and how much of it is all but
# white. A room that reads as an operating theatre from the seat measured 0.27-0.31 mean; the
# same rooms, put right, 0.19-0.22. Glow, LEDs and screens are SUPPOSED to be bright, which is why
# the clipped share is allowed a little and the mean carries the weight.
#
# Windows go offscreen through tools/shot.sh, audio to the null sink, and every run holds the
# shared lock so it never fights a probe for the GPU.
set -uo pipefail
cd "$(dirname "$0")/.."

MEAN_MAX="${MEAN_MAX:-0.23}"
WIDE_MEAN_MAX="${WIDE_MEAN_MAX:-0.24}"
WHITE_MAX="${WHITE_MAX:-0.5}"
OUT="${OUT:-$HOME/.cache/dawlings/shots/light_check}"
mkdir -p "$OUT"

if [ $# -gt 0 ]; then
  VENUES=("$@")
else
  mapfile -t VENUES < <(grep -oP 'const IDS: Array\[StringName\] = \[\K[^]]*' core/venues/venue.gd \
    | tr ',' '\n' | sed -E 's/[ &"]//g' | grep -v '^$')
fi
# Every arrangement after a venue's first, as `id:n` (Venue.VARIANTS; bootstrap's --venue takes it).
if [ $# -eq 0 ]; then
  while IFS= read -r line; do
    id=$(sed -E 's/^\s*&"([a-z_]+)".*/\1/' <<<"$line")
    count=$(grep -o '"[^"]*"' <<<"${line#*:}" | wc -l)
    for ((n = 1; n < count; n++)); do VENUES+=("$id:$n"); done
  done < <(sed -n '/^const VARIANTS := {/,/^}/p' core/venues/venue.gd | grep -E '^\s*&"')
fi

shoot() {
  local file=$1 cam=$2 args=$3 frame=${4:-30} walk=${5:-}
  local env=(SHOT_RES=1280x720 "SHOT_ARGS=$args" PULSE_SINK=dawlings_null PIPEWIRE_NODE=dawlings_null)
  [ -n "$cam" ] && env+=("SHOT_CAM=$cam")
  [ -n "$walk" ] && env+=("SHOT_WALK=$walk")
  env "${env[@]}" flock "$HOME/.cache/dawlings/shared.lock" tools/shot.sh "$file" "$frame" \
    "$((frame + 6))" 2>&1 \
    | grep -E "SCRIPT ERROR" && return 1
  [ -f "$file" ]
}

measure() {
  magick "$1" -colorspace Gray -format "%[fx:mean]" info:
}

white() {
  magick "$1" -colorspace Gray -threshold 97% -format "%[fx:mean*100]" info:
}

over=0
printf "%-10s %-6s %8s %8s\n" venue view mean white%
for v in "${VENUES[@]}"; do
  views=(seat wide back)
  # The studio's side room (StudioVenue.BESIDE), which none of the others can see into.
  [ "$v" = studio:1 ] && views+=(side)
  for view in "${views[@]}"; do
    file="$OUT/${v}_${view}.png"
    if [ "$view" = seat ]; then
      shoot "$file" "" "--no-hud --venue $v" || { echo "$v $view: no picture"; over=1; continue; }
      limit=$MEAN_MAX
    elif [ "$view" = wide ]; then
      shoot "$file" "0.35,-0.25,4.2,0,1.0,-0.3" "--no-hud --venue $v --place timeline=studio" \
        || { echo "$v $view: no picture"; over=1; continue; }
      limit=$WIDE_MEAN_MAX
    elif [ "$view" = side ]; then
      # Standing in its far corner, looking past the booth and the kit to the window.
      shoot "$file" "" "--no-hud --venue $v --place timeline=studio" 60 "-8.6,2.4,-0.55,-0.2" \
        || { echo "$v $view: no picture"; over=1; continue; }
      limit=$WIDE_MEAN_MAX
    else
      # Turned round from the desk, standing in the opening: the activity zones (Venue.ZONES).
      # Late, after anything a venue draws on as you arrive has finished drawing.
      shoot "$file" "3.14,-0.2,2.7,0,1.0,5.6" "--no-hud --venue $v --place timeline=studio" 300 \
        || { echo "$v $view: no picture"; over=1; continue; }
      limit=$WIDE_MEAN_MAX
    fi
    m=$(measure "$file"); w=$(white "$file")
    verdict=ok
    if awk -v m="$m" -v l="$limit" -v w="$w" -v wl="$WHITE_MAX" 'BEGIN{exit !(m>l || w>wl)}'; then
      verdict=OVER; over=1
    fi
    printf "%-10s %-6s %8.3f %8.3f  %s\n" "$v" "$view" "$m" "$w" "$verdict"
  done
done
echo "pictures in $OUT"
exit $over
