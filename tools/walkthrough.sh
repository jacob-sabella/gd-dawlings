#!/usr/bin/env bash
# Photograph docs/session_walkthrough.md: one mixing session against a live Reaper, a step per
# launch. Reaper keeps the session between launches, so each step starts where the last left it
# -- the playhead it moved, the loop it set, the fader it pulled -- exactly as a person's would.
#
#   tools/walkthrough.sh            # every step, from a freshly opened rig session
#   tools/walkthrough.sh 05         # just that step, against whatever the rig holds now
#
# Needs the rig (tools/reaper_rig.sh). Controls are addressed by title (tools/screenshot.gd,
# --aim/--click/--pull); the few things that have no title of their own -- a bare spot on a lane,
# a stretch of the loop ruler -- by their pixel in the seated 1600x900 view.
set -uo pipefail
cd "$(dirname "$0")/.."
RIG="${REAPER_RIG:-$HOME/.cache/dawlings/rig}"
OUT=docs/walkthrough
LIVE="--reaper --reaper-resource $RIG"
ONLY="${1:-}"

step() {
  local id="$1"; shift
  [ -n "$ONLY" ] && [ "$ONLY" != "${id%%-*}" ] && return 0
  echo "== $id"
  # A capture takes about twelve seconds. Now and then one stalls for good inside the GPU
  # driver (a poll() under libnvidia-glcore, seen only against a live Reaper and never
  # pinned to a cause), so a step that has not finished in a minute is killed -- the window
  # too, which `timeout` alone leaves behind holding the OSC port -- and taken again.
  local try
  for try in 1 2; do
    if SHOT_ARGS="$LIVE $*" timeout 60 tools/shot.sh "$OUT/$id.png" 30 40 | grep -E "saved"; then
      rm -f override.cfg
      return 0
    fi
    pkill -f "^godot --path \. --resolution .* --shot $PWD/$OUT/$id\.png" || true
    rm -f override.cfg
    echo "   (stalled; try $((try + 1)))"
  done
  echo "   NO SCREENSHOT for $id"
}

if [ -z "$ONLY" ]; then
  tools/reaper_rig.sh down && tools/reaper_rig.sh up || exit 1
  sleep 3
fi

# 1. Sit down at the desk.
step 01-sit-down --shot-tick 400
# 2. Click a bare stretch of the DRUMS lane at CHORUS 1: the session's leftover selection
#    clears and the playhead jumps there. The hover card reads it back exactly.
step 02-find-the-chorus --shot-tick 400 --drag 773,88:773,88@120-124 --aim PLAYHEAD
# 3. Drag along the loop ruler over CHORUS 1, bars 25 to 33.
step 03-loop-the-chorus --shot-tick 400 --drag 773,58:913,58@120-150 --aim LOOP
# 4. Bring the tape deck over (F on it, or G) and press PLAY. Bar and beat run on its counter.
step 04-play --shot-tick 420 --focus tape_deck --click TRANSPORT__PLAY@200 --aim TRANSPORT__PLAY
# 5. Balance: pull the lead vocal fader down a touch. The card reads the exact dB.
step 05-balance --shot-tick 400 --pull LEAD_VOX__LEVEL:0,8@120-160 --aim LEAD_VOX__LEVEL
# 6. Spread the guitars: Gtr L's pan down (left), Gtr R's up (right). Knobs drag vertically,
#    as every plugin UI does; the card reads the exact percentage.
step 06-pan --shot-tick 400 --pull GTR_L__PAN:0,40@120-150 --pull GTR_R__PAN:0,-40@180-210 --aim GTR_L__PAN
# 7. Solo the lead vocal to hear it alone.
step 07-solo --shot-tick 400 --click LEAD_VOX__SOLO@150 --aim LEAD_VOX__SOLO
# 8. Unsolo, and mute the adlib track, which fights the vocal in the chorus.
step 08-mute --shot-tick 400 --click LEAD_VOX__SOLO@150 --click ADLIB__MUTE@190 --aim ADLIB__MUTE
# 9. Arm the vocal for a punch-in.
step 09-arm --shot-tick 400 --click LEAD_VOX__RECORD_ARM@150 --aim LEAD_VOX__RECORD_ARM
# 10. FX: bring the rack over. Every plugin on every track hangs in it, captioned by track.
step 10-rack --shot-tick 400 --focus rack
# 11. A/B the vocal compressor: its POWER key bypasses it in Reaper. The lamp goes dark.
step 11-bypass --shot-tick 400 --focus rack --click LEAD_VOX__REACOMP+POWER@150 --aim LEAD_VOX__REACOMP+POWER
# 12. Back in, and pull its threshold down. The card reads the value Reaper reports.
step 12-threshold --shot-tick 420 --focus rack --click LEAD_VOX__REACOMP+POWER@150 --pull LEAD_VOX__REACOMP+THRESHOLD:0,40@200-240 --aim LEAD_VOX__REACOMP+THRESHOLD
# 13. Stop.
step 13-stop --shot-tick 400 --focus tape_deck --click TRANSPORT__STOP@200 --aim TRANSPORT__STOP
# 14. Edit: Gtr R plays the whole chorus alone. Click a bare spot of the DRUMS folder lane at
#     bar 29 to put the playhead there, click Gtr R's chorus item to select it, and press SPLIT
#     (or B).
step 14-split --shot-tick 400 --drag 845,88:845,88@200-204 --drag 845,328:845,328@240-244 --click EDIT__SPLIT_AT_PLAYHEAD@280 --hover 885,328
# 15. Drag the back half two bars late, for a stutter into the second verse. Moves snap to the
#     beat; the card reads where it will land while it is held.
step 15-move --shot-tick 400 --drag 880,328:916,328@220-260 --hover 935,328
# 16. It does not work. UNDO on the deck takes it back -- Reaper's own undo, so the history is
#     the one Reaper keeps.
step 16-undo --shot-tick 420 --focus tape_deck --click EDIT__UNDO@200 --aim EDIT__UNDO
# 17. Forty tracks do not fit on the panel: drag the track names up to bring the vocals in.
step 17-scroll --shot-tick 400 --drag 300,320:300,100@120-170 --aim TRACKS
